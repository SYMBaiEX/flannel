//
//  CLIProviderCommandSpec.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

nonisolated enum CLIProviderOutputFormat: String, Equatable, Sendable {
    case plainText
    case codexJSONLines
    case claudeJSON
    case claudeStreamJSON
}

nonisolated struct CLIProviderCommandSpec: Equatable, Sendable {
    var providerDisplayName: String
    var executable: String
    var arguments: [String]
    var stdinText: String?
    var timeout: Duration
    var outputFormat: CLIProviderOutputFormat
}

nonisolated enum CLIProviderTransportError: LocalizedError, Equatable {
    case unsupportedProvider(String)
    case missingCommandContract(String)
    case unsupportedShellSyntax(Character)
    case unterminatedQuote
    case danglingEscape
    case claudePrintModeRequired
    case missingExecutable(String)
    case missingModelPlaceholderValue
    case failedToStart(String)
    case processTimedOut(String, seconds: Int)
    case processExitedNonZero(String, code: Int32, stderr: String?)
    case invalidUTF8Output(String)
    case invalidStructuredOutput(String, detail: String)
    case cancelled(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "\(provider) is not backed by a local subscription CLI transport."
        case .missingCommandContract(let provider):
            return "\(provider) needs a local command contract before Flannel can invoke it."
        case .unsupportedShellSyntax(let character):
            return "CLI provider commands must be direct argv-style commands. Shell syntax like '\(character)' is not supported."
        case .unterminatedQuote:
            return "The CLI command contract contains an unterminated quote."
        case .danglingEscape:
            return "The CLI command contract ends with a dangling escape character."
        case .claudePrintModeRequired:
            return "Claude Code CLI must include -p/--print or a {prompt} placeholder."
        case .missingExecutable(let executable):
            return "The local command '\(executable)' was not found or is not executable."
        case .missingModelPlaceholderValue:
            return "This CLI command contract references {model}, but the provider does not have a configured model identifier."
        case .failedToStart(let detail):
            return "Flannel could not start the local CLI process: \(detail)"
        case .processTimedOut(let provider, let seconds):
            return "\(provider) did not produce a complete response within \(seconds) seconds."
        case .processExitedNonZero(let provider, let code, let stderr):
            if let stderr, !stderr.isEmpty {
                return "\(provider) exited with status \(code): \(stderr)"
            }
            return "\(provider) exited with status \(code)."
        case .invalidUTF8Output(let provider):
            return "\(provider) emitted output that Flannel could not decode as UTF-8 text."
        case .invalidStructuredOutput(let provider, let detail):
            return "\(provider) emitted structured output that Flannel could not parse: \(detail)"
        case .cancelled(let provider):
            return "\(provider) was cancelled before it finished."
        }
    }
}

nonisolated struct CLIProviderCommandBuilder: Sendable {
    static let promptPlaceholder = "{prompt}"
    static let modelPlaceholder = "{model}"
    static let systemPromptPlaceholder = "{system_prompt}"
    static let lastUserMessagePlaceholder = "{last_user_message}"
    static let stdinPlaceholder = "{stdin}"

    var timeout: Duration

    nonisolated init(timeout: Duration = .seconds(120)) {
        self.timeout = timeout
    }

    nonisolated func makeCommandSpec(for request: ChatStreamingRequest) throws -> CLIProviderCommandSpec {
        let provider = request.provider
        guard provider.kind == .claudeCodeCLI || provider.kind == .chatGPTCLI else {
            throw CLIProviderTransportError.unsupportedProvider(provider.displayName)
        }

        let tokens = try Self.parseCommand(provider.endpoint, providerName: provider.displayName)
        guard let executable = tokens.first else {
            throw CLIProviderTransportError.missingCommandContract(provider.displayName)
        }

        let rawArguments = Array(tokens.dropFirst())
        let promptText = Self.renderPrompt(for: request)
        let systemPrompt = request.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lastUserMessage = request.messages
            .last(where: {
                $0.role == .user
                    && !$0.textWithAttachmentPromptContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })?
            .textWithAttachmentPromptContext
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = provider.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        if rawArguments.contains(where: { $0.contains(Self.modelPlaceholder) }),
           model.isEmpty {
            throw CLIProviderTransportError.missingModelPlaceholderValue
        }

        let replacements = [
            Self.promptPlaceholder: promptText,
            Self.modelPlaceholder: model,
            Self.systemPromptPlaceholder: systemPrompt,
            Self.lastUserMessagePlaceholder: lastUserMessage
        ]

        let usesPromptPlaceholder = rawArguments.contains(where: { $0.contains(Self.promptPlaceholder) })
        let usesInlinePromptInput = rawArguments.contains {
            $0.contains(Self.promptPlaceholder) || $0.contains(Self.lastUserMessagePlaceholder)
        }
        var stdinText: String?
        var arguments: [String] = []

        for rawArgument in rawArguments {
            if rawArgument == Self.stdinPlaceholder {
                stdinText = promptText
                continue
            }
            arguments.append(Self.interpolate(rawArgument, replacements: replacements))
        }

        switch provider.kind {
        case .claudeCodeCLI:
            let hasPrintFlag = rawArguments.contains("-p") || rawArguments.contains("--print")
            guard hasPrintFlag || usesPromptPlaceholder else {
                throw CLIProviderTransportError.claudePrintModeRequired
            }
            if !usesPromptPlaceholder {
                arguments.append(promptText)
            }

        case .chatGPTCLI:
            if !usesInlinePromptInput && stdinText == nil {
                stdinText = promptText
            }

        default:
            throw CLIProviderTransportError.unsupportedProvider(provider.displayName)
        }

        return CLIProviderCommandSpec(
            providerDisplayName: provider.displayName,
            executable: executable,
            arguments: arguments,
            stdinText: stdinText,
            timeout: timeout,
            outputFormat: Self.inferOutputFormat(
                provider: provider,
                executable: executable,
                arguments: arguments
            )
        )
    }

    nonisolated static func parseCommand(_ rawValue: String, providerName: String) throws -> [String] {
        let command = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw CLIProviderTransportError.missingCommandContract(providerName)
        }

        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false
        var index = command.startIndex

        while index < command.endIndex {
            let character = command[index]

            if isEscaping {
                current.append(character)
                isEscaping = false
                index = command.index(after: index)
                continue
            }

            if character == "\\" {
                isEscaping = true
                index = command.index(after: index)
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                index = command.index(after: index)
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                index = command.index(after: index)
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                index = command.index(after: index)
                continue
            }

            if Self.isUnsupportedShellCharacter(character, in: command, at: index) {
                throw CLIProviderTransportError.unsupportedShellSyntax(character)
            }

            current.append(character)
            index = command.index(after: index)
        }

        if isEscaping {
            throw CLIProviderTransportError.danglingEscape
        }

        if quote != nil {
            throw CLIProviderTransportError.unterminatedQuote
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        guard !tokens.isEmpty else {
            throw CLIProviderTransportError.missingCommandContract(providerName)
        }

        return tokens
    }

    nonisolated static func renderPrompt(for request: ChatStreamingRequest) -> String {
        var sections: [String] = []

        if let systemPrompt = request.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !systemPrompt.isEmpty {
            sections.append("System:\n\(systemPrompt)")
        }

        for message in request.messages {
            guard let content = Self.renderMessageForPrompt(message) else { continue }
            sections.append("\(Self.promptLabel(for: message.role)):\n\(content)")
        }

        sections.append("Assistant:")
        return sections.joined(separator: "\n\n")
    }

    private static func renderMessageForPrompt(_ message: AssistantMessage) -> String? {
        var blocks: [String] = []

        let content = message.textWithAttachmentPromptContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty {
            blocks.append(content)
        }

        let metadata = Self.promptMetadata(for: message)
        if !metadata.isEmpty {
            blocks.append("Message metadata:\n\(metadata.map { "- \($0)" }.joined(separator: "\n"))")
        }

        let citations = Self.promptCitations(for: message)
        if !citations.isEmpty {
            blocks.append("Citations:\n\(citations.joined(separator: "\n"))")
        }

        let toolCalls = Self.promptToolCalls(for: message)
        if !toolCalls.isEmpty {
            blocks.append("Tool trace:\n\(toolCalls.joined(separator: "\n"))")
        }

        let rendered = blocks
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rendered.isEmpty ? nil : rendered
    }

    private static func promptMetadata(for message: AssistantMessage) -> [String] {
        var values: [String] = []

        if let runStatus = message.runStatus {
            values.append("Status: \(Self.title(for: runStatus))")
        }

        if let providerDisplayName = Self.trimmedNonEmpty(message.providerDisplayName) {
            values.append("Provider: \(providerDisplayName)")
        }

        if let providerAccessMode = message.providerAccessMode {
            values.append("Access mode: \(Self.title(for: providerAccessMode))")
        }

        if let providerPrivacyScope = message.providerPrivacyScope {
            values.append("Privacy scope: \(Self.title(for: providerPrivacyScope))")
        }

        if let modelIdentifier = Self.trimmedNonEmpty(message.modelIdentifier) {
            values.append("Model: \(modelIdentifier)")
        }

        if let inputTokenCount = message.inputTokenCount,
           let outputTokenCount = message.outputTokenCount {
            let suffix = message.tokenCountsAreEstimated ? " estimated" : ""
            values.append("Tokens: \(inputTokenCount) input / \(outputTokenCount) output\(suffix)")
        } else if let outputTokenCount = message.outputTokenCount {
            let suffix = message.tokenCountsAreEstimated ? " estimated" : ""
            values.append("Output tokens: \(outputTokenCount)\(suffix)")
        }

        if let contextTokenCount = message.contextTokenCount,
           let contextWindowTokens = message.contextWindowTokens,
           contextWindowTokens > 0 {
            values.append("Context: \(contextTokenCount) / \(contextWindowTokens) tokens")
        } else if let contextTokenCount = message.contextTokenCount {
            values.append("Context tokens: \(contextTokenCount)")
        }

        if let latencyMilliseconds = message.latencyMilliseconds {
            values.append("Latency: \(latencyMilliseconds) ms")
        }

        if let estimatedCostMicros = message.estimatedCostMicros,
           estimatedCostMicros > 0 {
            values.append("Estimated cost: \(Self.formatMicrosCost(estimatedCostMicros))")
        }

        if let fallbackReason = Self.trimmedNonEmpty(message.fallbackReason) {
            values.append("Fallback reason: \(fallbackReason.singleLinePromptValue(maxLength: 320))")
        }

        return values
    }

    private static func promptCitations(for message: AssistantMessage) -> [String] {
        message.citations
            .prefix(12)
            .enumerated()
            .map { index, citation in
                var parts = ["[\(index + 1)] \(citation.title.singleLinePromptValue(maxLength: 96))"]

                let snippet = citation.snippet.singleLinePromptValue(maxLength: 240)
                if !snippet.isEmpty {
                    parts.append("snippet: \(snippet)")
                }

                if let sourceIdentifier = Self.trimmedNonEmpty(citation.sourceIdentifier) {
                    parts.append("source: \(sourceIdentifier.singleLinePromptValue(maxLength: 160))")
                }

                if let score = citation.score {
                    parts.append("score: \(String(format: "%.3f", score))")
                }

                return "- \(parts.joined(separator: "; "))"
            }
    }

    private static func promptToolCalls(for message: AssistantMessage) -> [String] {
        message.toolCalls
            .prefix(12)
            .flatMap { toolCall -> [String] in
                var lines = [
                    "- \(toolCall.toolName.singleLinePromptValue(maxLength: 96)) (\(Self.title(for: toolCall.permissionScope)); \(Self.executionTitle(for: toolCall)))"
                ]

                if let providerCallID = Self.trimmedNonEmpty(toolCall.providerCallID) {
                    lines.append("  - Provider call ID: \(providerCallID.singleLinePromptValue(maxLength: 120))")
                }

                lines.append("  - Approved locally: \(toolCall.wasApproved ? "yes" : "no")")

                if let executionResultID = toolCall.executionResultID {
                    lines.append("  - Local result ID: \(executionResultID.uuidString)")
                }

                let arguments = toolCall.argumentsJSON.singleLinePromptValue(maxLength: 640)
                if !arguments.isEmpty {
                    lines.append("  - Arguments JSON: \(arguments)")
                }

                if let outputPreview = Self.trimmedNonEmpty(toolCall.outputPreview) {
                    lines.append("  - Output preview: \(outputPreview.singleLinePromptValue(maxLength: 640))")
                }

                return lines
            }
    }

    private static func executionTitle(for toolCall: AIToolCallRecord) -> String {
        guard let executionStatus = toolCall.executionStatus else {
            return "Pending"
        }
        return Self.title(for: executionStatus)
    }

    private static func title(for status: AssistantMessageRunStatus) -> String {
        switch status {
        case .queued:
            "Queued"
        case .streaming:
            "Streaming"
        case .completed:
            "Completed"
        case .fallback:
            "Fallback"
        case .failed:
            "Failed"
        case .stopped:
            "Stopped"
        }
    }

    private static func title(for accessMode: ProviderAccessMode) -> String {
        switch accessMode {
        case .localServer:
            "Local Server"
        case .apiKey:
            "API Key"
        case .subscriptionCLI:
            "Subscription CLI"
        case .openAICompatible:
            "OpenAI Compatible"
        case .anthropicCompatible:
            "Anthropic Compatible"
        case .aiSDKBridge:
            "AI SDK Bridge"
        }
    }

    private static func title(for privacyScope: ProviderPrivacyScope) -> String {
        switch privacyScope {
        case .localOnly:
            "Local Only"
        case .externalAPI:
            "External API"
        case .localCLI:
            "Local CLI"
        case .bridgeService:
            "Local Bridge"
        }
    }

    private static func title(for scope: AIToolPermissionScope) -> String {
        switch scope {
        case .readWorkspace:
            "Read workspace"
        case .writeWorkspace:
            "Write workspace"
        case .runShellCommand:
            "Run shell command"
        case .makeNetworkRequest:
            "Network request"
        case .queryRAGIndex:
            "Query RAG index"
        case .mutateRAGIndex:
            "Mutate RAG index"
        }
    }

    private static func title(for status: LocalToolExecutionStatus) -> String {
        switch status {
        case .completed:
            "Executed"
        case .requiresApproval:
            "Approval required"
        case .denied:
            "Denied"
        case .blocked:
            "Blocked"
        case .unavailable:
            "Unavailable"
        }
    }

    private static func formatMicrosCost(_ micros: Int) -> String {
        "$\(String(format: "%.4f", Double(micros) / 1_000_000.0))"
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func interpolate(
        _ value: String,
        replacements: [String: String]
    ) -> String {
        replacements.reduce(value) { partialResult, replacement in
            partialResult.replacingOccurrences(of: replacement.key, with: replacement.value)
        }
    }

    private static func inferOutputFormat(
        provider: ProviderConfiguration,
        executable: String,
        arguments: [String]
    ) -> CLIProviderOutputFormat {
        switch provider.kind {
        case .chatGPTCLI:
            let executableName = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
            if executableName == "codex",
               arguments.contains("--json") {
                return .codexJSONLines
            }
            return .plainText

        case .claudeCodeCLI:
            guard let outputFormat = optionValue(named: "--output-format", in: arguments) else {
                return .plainText
            }
            switch outputFormat.lowercased() {
            case "json":
                return .claudeJSON
            case "stream-json":
                return .claudeStreamJSON
            default:
                return .plainText
            }

        default:
            return .plainText
        }
    }

    private static func optionValue(named option: String, in arguments: [String]) -> String? {
        for index in arguments.indices {
            let argument = arguments[index]
            if argument == option {
                let valueIndex = arguments.index(after: index)
                return arguments.indices.contains(valueIndex) ? arguments[valueIndex] : nil
            }

            let prefix = "\(option)="
            if argument.hasPrefix(prefix) {
                return String(argument.dropFirst(prefix.count))
            }
        }

        return nil
    }

    private static func isUnsupportedShellCharacter(
        _ character: Character,
        in command: String,
        at index: String.Index
    ) -> Bool {
        if "|&;<>`".contains(character) {
            return true
        }

        guard character == "$" else { return false }
        let nextIndex = command.index(after: index)
        return nextIndex < command.endIndex && command[nextIndex] == "("
    }

    private static func promptLabel(for role: AssistantRole) -> String {
        switch role {
        case .system:
            "System"
        case .user:
            "User"
        case .assistant:
            "Assistant"
        }
    }
}

private extension String {
    nonisolated func singleLinePromptValue(maxLength: Int) -> String {
        let collapsed = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard maxLength > 0, collapsed.count > maxLength else {
            return collapsed
        }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return "\(collapsed[..<endIndex])..."
    }
}
