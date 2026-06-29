//
//  ChatStreamingService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation
import UniformTypeIdentifiers

struct ChatStreamingRequest: Sendable {
    var provider: ProviderConfiguration
    var messages: [AssistantMessage]
    var systemPrompt: String?
    var tools: [ChatToolDefinition]

    nonisolated init(
        provider: ProviderConfiguration,
        messages: [AssistantMessage],
        systemPrompt: String? = nil,
        tools: [ChatToolDefinition] = []
    ) {
        self.provider = provider
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.tools = tools
    }
}

struct ChatToolDefinition: Codable, Hashable, Sendable {
    var name: String
    var description: String
    var argumentDescription: String
    var inputSchema: ChatToolInputSchema

    nonisolated init(
        name: String,
        description: String,
        argumentDescription: String = "Natural-language tool input or JSON details needed to run this local Flannel tool.",
        inputSchema: ChatToolInputSchema? = nil
    ) {
        self.name = name
        self.description = description
        self.argumentDescription = argumentDescription
        self.inputSchema = inputSchema ?? .query(description: argumentDescription)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case argumentDescription
        case inputSchema
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        argumentDescription = try container.decodeIfPresent(String.self, forKey: .argumentDescription)
            ?? "Natural-language tool input or JSON details needed to run this local Flannel tool."
        inputSchema = try container.decodeIfPresent(ChatToolInputSchema.self, forKey: .inputSchema)
            ?? .query(description: argumentDescription)
    }
}

struct ChatToolInputSchema: Codable, Hashable, Sendable {
    var type = "object"
    var properties: [String: ChatToolInputProperty]
    var required: [String]
    var additionalProperties: Bool

    nonisolated init(
        properties: [String: ChatToolInputProperty],
        required: [String],
        additionalProperties: Bool = false
    ) {
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }

    enum CodingKeys: String, CodingKey {
        case type
        case properties
        case required
        case additionalProperties = "additionalProperties"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "object"
        properties = try container.decode([String: ChatToolInputProperty].self, forKey: .properties)
        required = try container.decodeIfPresent([String].self, forKey: .required) ?? []
        additionalProperties = try container.decodeIfPresent(Bool.self, forKey: .additionalProperties) ?? false
    }

    nonisolated static func query(
        description: String,
        required: Bool = true
    ) -> ChatToolInputSchema {
        ChatToolInputSchema(
            properties: [
                "query": .string(description)
            ],
            required: required ? ["query"] : []
        )
    }
}

struct ChatToolInputProperty: Codable, Hashable, Sendable {
    var type: String
    var description: String
    var enumValues: [String]?

    nonisolated init(
        type: String,
        description: String,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }

    nonisolated static func string(_ description: String) -> ChatToolInputProperty {
        ChatToolInputProperty(type: "string", description: description)
    }

    nonisolated static func integer(_ description: String) -> ChatToolInputProperty {
        ChatToolInputProperty(type: "integer", description: description)
    }

    nonisolated static func boolean(_ description: String) -> ChatToolInputProperty {
        ChatToolInputProperty(type: "boolean", description: description)
    }

    nonisolated static func stringEnum(
        _ values: [String],
        description: String
    ) -> ChatToolInputProperty {
        ChatToolInputProperty(type: "string", description: description, enumValues: values)
    }
}

struct ChatStreamUsage: Codable, Hashable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
    var latencyMilliseconds: Int?

    var hasCompleteTokenCounts: Bool {
        inputTokens != nil && outputTokens != nil
    }

    func merged(with newer: ChatStreamUsage) -> ChatStreamUsage {
        ChatStreamUsage(
            inputTokens: newer.inputTokens ?? inputTokens,
            outputTokens: newer.outputTokens ?? outputTokens,
            totalTokens: newer.totalTokens ?? totalTokens,
            latencyMilliseconds: newer.latencyMilliseconds ?? latencyMilliseconds
        )
    }
}

struct ChatStreamToolCallDelta: Codable, Hashable, Sendable {
    var index: Int
    var id: String?
    var type: String?
    var name: String?
    var argumentsFragment: String

    var hasContent: Bool {
        id != nil
            || type != nil
            || name != nil
            || !argumentsFragment.isEmpty
    }
}

struct ChatStreamToolCall: Codable, Hashable, Sendable {
    var index: Int
    var id: String?
    var type: String?
    var name: String
    var arguments: String
}

struct ChatStreamToolCallAccumulator: Hashable, Sendable {
    private struct PartialToolCall: Hashable, Sendable {
        var index: Int
        var id: String?
        var type: String?
        var name: String?
        var arguments: String = ""
    }

    private var partials: [Int: PartialToolCall] = [:]

    var toolCalls: [ChatStreamToolCall] {
        partials.values
            .sorted { $0.index < $1.index }
            .compactMap { partial in
                guard let name = partial.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty else {
                    return nil
                }
                return ChatStreamToolCall(
                    index: partial.index,
                    id: partial.id,
                    type: partial.type,
                    name: name,
                    arguments: partial.arguments
                )
            }
    }

    var isEmpty: Bool {
        toolCalls.isEmpty
    }

    mutating func apply(_ delta: ChatStreamToolCallDelta) {
        var partial = partials[delta.index] ?? PartialToolCall(index: delta.index)
        if let id = delta.id, !id.isEmpty {
            partial.id = id
        }
        if let type = delta.type, !type.isEmpty {
            partial.type = type
        }
        if let name = delta.name, !name.isEmpty {
            partial.name = name
        }
        partial.arguments += delta.argumentsFragment
        partials[delta.index] = partial
    }
}

enum ChatStreamingEvent: Hashable, Sendable {
    case text(String)
    case usage(ChatStreamUsage)
    case toolCallDelta(ChatStreamToolCallDelta)
    case toolCallDeltas([ChatStreamToolCallDelta])
}

struct ChatStreamingService: Sendable {
    var session: URLSession
    var keychain: KeychainSecretStore
    var cliTransport: CLIProviderTransport

    init(
        session: URLSession = .shared,
        keychain: KeychainSecretStore = KeychainSecretStore(),
        cliTransport: CLIProviderTransport = CLIProviderTransport()
    ) {
        self.session = session
        self.keychain = keychain
        self.cliTransport = cliTransport
    }

    func streamText(for request: ChatStreamingRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in streamEvents(for: request) {
                        try Task.checkCancellation()
                        guard case .text(let token) = event,
                              !token.isEmpty else { continue }
                        continuation.yield(token)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func streamEvents(for request: ChatStreamingRequest) -> AsyncThrowingStream<ChatStreamingEvent, Error> {
        if request.provider.accessMode == .subscriptionCLI {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await token in cliTransport.streamText(for: request) {
                            try Task.checkCancellation()
                            continuation.yield(.text(token))
                        }

                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(for: request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200..<300).contains(httpResponse.statusCode) else {
                        throw ChatStreamingError.badStatus
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let event = try parseEvent(line: line, provider: request.provider) else { continue }
                        if case .text(let token) = event,
                           token.isEmpty {
                            continue
                        }
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func makeURLRequest(for request: ChatStreamingRequest) throws -> URLRequest {
        let provider = request.provider
        let model = provider.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw ChatStreamingError.missingModel
        }

        switch provider.kind {
        case .ollama:
            return try makeOllamaRequest(
                provider: provider,
                messages: request.messages,
                systemPrompt: request.systemPrompt,
                model: model,
                tools: request.tools
            )

        case .openAI:
            return try makeOpenAIResponsesRequest(
                provider: provider,
                messages: request.messages,
                systemPrompt: request.systemPrompt,
                model: model,
                tools: request.tools
            )

        case .lmStudio, .customOpenAICompatible, .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            return try makeOpenAICompatibleRequest(
                provider: provider,
                messages: request.messages,
                systemPrompt: request.systemPrompt,
                model: model,
                tools: request.tools
            )

        case .anthropic:
            return try makeAnthropicRequest(
                provider: provider,
                messages: request.messages,
                systemPrompt: request.systemPrompt,
                model: model,
                tools: request.tools
            )

        case .vercelAISDKBridge:
            return try makeAISDKBridgeRequest(
                provider: provider,
                messages: request.messages,
                systemPrompt: request.systemPrompt,
                model: model,
                tools: request.tools
            )

        case .claudeCodeCLI, .chatGPTCLI:
            throw ChatStreamingError.unsupportedProviderMode(provider.displayName)
        }
    }

    func parse(line: String, provider: ProviderConfiguration) throws -> String? {
        guard let event = try parseEvent(line: line, provider: provider),
              case .text(let token) = event else {
            return nil
        }
        return token
    }

    func parseEvent(line: String, provider: ProviderConfiguration) throws -> ChatStreamingEvent? {
        switch provider.kind {
        case .ollama:
            return try Self.parseOllamaEvent(line)
        case .openAI:
            return try Self.parseOpenAIResponsesEvent(line)
        case .lmStudio, .customOpenAICompatible, .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            return try Self.parseOpenAICompatibleEvent(line)
        case .anthropic:
            return try Self.parseAnthropicEvent(line)
        case .vercelAISDKBridge:
            return try Self.parseAISDKBridgeEvent(line)
        case .claudeCodeCLI, .chatGPTCLI:
            return nil
        }
    }

    static func parseOllamaLine(_ line: String) throws -> String? {
        guard let event = try parseOllamaEvent(line),
              case .text(let token) = event else {
            return nil
        }
        return token
    }

    static func parseOllamaEvent(_ line: String) throws -> ChatStreamingEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let data = Data(trimmed.utf8)
        let chunk = try JSONDecoder().decode(OllamaChatStreamChunk.self, from: data)
        if let usage = chunk.usage {
            return .usage(usage)
        }
        if let content = chunk.message?.content,
           !content.isEmpty {
            return .text(content)
        }
        let toolCalls = chunk.message?.toolCalls.enumerated().map { index, toolCall in
            toolCall.streamDelta(index: index)
        }.filter(\.hasContent) ?? []
        if toolCalls.count == 1, let toolCall = toolCalls.first {
            return .toolCallDelta(toolCall)
        }
        if !toolCalls.isEmpty {
            return .toolCallDeltas(toolCalls)
        }
        return nil
    }

    static func parseOpenAICompatibleLine(_ line: String) throws -> String? {
        guard let event = try parseOpenAICompatibleEvent(line),
              case .text(let token) = event else {
            return nil
        }
        return token
    }

    static func parseOpenAIResponsesLine(_ line: String) throws -> String? {
        guard let event = try parseOpenAIResponsesEvent(line),
              case .text(let token) = event else {
            return nil
        }
        return token
    }

    static func parseOpenAIResponsesEvent(_ line: String) throws -> ChatStreamingEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }

        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard payload != "[DONE]", !payload.isEmpty else { return nil }

        let data = Data(payload.utf8)
        let event = try JSONDecoder().decode(OpenAIResponsesStreamEvent.self, from: data)
        if let usage = event.streamUsage {
            return .usage(usage)
        }
        if let toolCall = event.toolCallDelta {
            return .toolCallDelta(toolCall)
        }
        if event.type == "response.output_text.delta",
           let delta = event.delta,
           !delta.isEmpty {
            return .text(delta)
        }
        return nil
    }

    static func parseOpenAICompatibleEvent(_ line: String) throws -> ChatStreamingEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }

        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard payload != "[DONE]" else { return nil }

        let data = Data(payload.utf8)
        let chunk = try JSONDecoder().decode(OpenAICompatibleChatStreamChunk.self, from: data)
        if let usage = chunk.usage?.streamUsage {
            return .usage(usage)
        }
        if let content = chunk.choices.first?.delta.content {
            return .text(content)
        }
        let toolCalls = chunk.choices
            .flatMap { $0.delta.toolCalls.map(\.streamDelta) }
            .filter(\.hasContent)
        if toolCalls.count == 1, let toolCall = toolCalls.first {
            return .toolCallDelta(toolCall)
        }
        if !toolCalls.isEmpty {
            return .toolCallDeltas(toolCalls)
        }
        return nil
    }

    static func parseAnthropicLine(_ line: String) throws -> String? {
        guard let event = try parseAnthropicEvent(line),
              case .text(let token) = event else {
            return nil
        }
        return token
    }

    static func parseAISDKBridgeLine(_ line: String) throws -> String? {
        guard let event = try parseAISDKBridgeEvent(line),
              case .text(let token) = event else {
            return nil
        }
        return token
    }

    static func parseAnthropicEvent(_ line: String) throws -> ChatStreamingEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }

        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return nil }

        let data = Data(payload.utf8)
        let event = try JSONDecoder().decode(AnthropicStreamEvent.self, from: data)
        if let usage = event.streamUsage {
            return .usage(usage)
        }
        if let toolCall = event.toolCallDelta {
            return .toolCallDelta(toolCall)
        }
        guard event.type == "content_block_delta",
              event.delta?.type == "text_delta" else {
            return nil
        }
        return event.delta?.text.map(ChatStreamingEvent.text)
    }

    static func parseAISDKBridgeEvent(_ line: String) throws -> ChatStreamingEvent? {
        if isOpenAICompatibleSSEPayload(line),
           let compatibleEvent = try? parseOpenAICompatibleEvent(line) {
            return compatibleEvent
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }

        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard payload != "[DONE]", !payload.isEmpty else { return nil }

        let data = Data(payload.utf8)
        let event = try JSONDecoder().decode(AISDKBridgeStreamEvent.self, from: data)

        if let usage = event.streamUsage {
            return .usage(usage)
        }

        switch event.normalizedType {
        case "text", "text-delta", "text_delta":
            let text = event.text ?? event.delta ?? ""
            return text.isEmpty ? nil : .text(text)
        case "tool-call", "tool_call", "tool-call-delta", "tool_call_delta":
            let delta = event.toolCallDelta
            return delta.hasContent ? .toolCallDelta(delta) : nil
        case "tool-result", "tool_result", "finish", "done", "error":
            return nil
        default:
            return nil
        }
    }

    private static func isOpenAICompatibleSSEPayload(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return false }

        let payload = trimmed.dropFirst("data:".count)
        return payload.contains("\"choices\"")
            || payload.contains("\"chat.completion.chunk\"")
    }

    private func makeOllamaRequest(
        provider: ProviderConfiguration,
        messages: [AssistantMessage],
        systemPrompt: String?,
        model: String,
        tools: [ChatToolDefinition]
    ) throws -> URLRequest {
        let url = try endpoint(provider.endpoint, appending: ["api", "chat"])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = OllamaChatRequestPayload(
            model: model,
            messages: try messages.ollamaMessages(
                overridingSystemPrompt: systemPrompt,
                usesNativeImages: provider.supportsVision
            ),
            stream: true,
            options: .init(
                temperature: provider.temperature,
                numPredict: provider.requestOverrides.maxOutputTokens,
                topP: provider.requestOverrides.topP,
                topK: provider.requestOverrides.topK,
                seed: provider.requestOverrides.seed,
                stop: provider.requestOverrides.nonEmptyStopSequences,
                repeatPenalty: provider.requestOverrides.repeatPenalty,
                numCtx: provider.contextWindowTokens
            ),
            tools: tools.chatToolPayloads
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private func makeAnthropicRequest(
        provider: ProviderConfiguration,
        messages: [AssistantMessage],
        systemPrompt: String?,
        model: String,
        tools: [ChatToolDefinition]
    ) throws -> URLRequest {
        let url = try endpoint(provider.endpoint, appending: ["messages"], ensuringVersionPath: "v1")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        guard let secretReference = keychainReference(from: provider.secretReference) else {
            throw ChatStreamingError.missingKeychainReference(provider.displayName)
        }
        let apiKey = try keychain.read(secretReference)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let payload = AnthropicMessagesRequestPayload(
            model: model,
            maxTokens: provider.requestOverrides.maxOutputTokens ?? 4096,
            messages: try messages.anthropicMessages(usesNativeImages: provider.supportsVision),
            system: messages.anthropicSystemPrompt(overridingSystemPrompt: systemPrompt),
            temperature: provider.temperature,
            topP: provider.requestOverrides.topP,
            topK: provider.requestOverrides.topK,
            stopSequences: provider.requestOverrides.nonEmptyStopSequences,
            stream: true,
            tools: tools.anthropicToolPayloads
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private func makeOpenAIResponsesRequest(
        provider: ProviderConfiguration,
        messages: [AssistantMessage],
        systemPrompt: String?,
        model: String,
        tools: [ChatToolDefinition]
    ) throws -> URLRequest {
        let url = try endpoint(provider.endpoint, appending: ["responses"], ensuringVersionPath: "v1")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let secretReference = keychainReference(from: provider.secretReference) else {
            throw ChatStreamingError.missingKeychainReference(provider.displayName)
        }
        let apiKey = try keychain.read(secretReference)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let resolvedSystemPrompt = messages.openAIResponsesInstructions(overridingSystemPrompt: systemPrompt)
        let payload = OpenAIResponsesRequestPayload(
            model: model,
            input: try messages.openAIResponsesInputItems(usesNativeImages: provider.supportsVision),
            instructions: resolvedSystemPrompt,
            temperature: provider.temperature,
            maxOutputTokens: provider.requestOverrides.maxOutputTokens,
            topP: provider.requestOverrides.topP,
            stream: true,
            tools: tools.openAIResponsesToolPayloads,
            toolChoice: tools.isEmpty ? nil : "auto",
            reasoning: provider.requestOverrides.reasoningEffort?.openAIResponsesReasoning
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private func makeOpenAICompatibleRequest(
        provider: ProviderConfiguration,
        messages: [AssistantMessage],
        systemPrompt: String?,
        model: String,
        tools: [ChatToolDefinition]
    ) throws -> URLRequest {
        let url = try endpoint(
            provider.endpoint,
            appending: ["chat", "completions"],
            ensuringVersionPath: openAICompatibleVersionPath(for: provider)
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresOpenAICompatibleAuthorization(provider) {
            guard let secretReference = keychainReference(from: provider.secretReference) else {
                throw ChatStreamingError.missingKeychainReference(provider.displayName)
            }
            let apiKey = try keychain.read(secretReference)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else if let secretReference = keychainReference(from: provider.secretReference) {
            let apiKey = try keychain.read(secretReference)
            if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }

        let payload = OpenAICompatibleChatRequestPayload(
            model: model,
            messages: try messages.openAICompatibleMessages(
                overridingSystemPrompt: systemPrompt,
                usesNativeImages: provider.supportsVision
            ),
            temperature: provider.temperature,
            maxCompletionTokens: provider.usesMaxCompletionTokens
                ? provider.requestOverrides.maxOutputTokens
                : nil,
            maxTokens: provider.usesMaxCompletionTokens
                ? nil
                : provider.requestOverrides.maxOutputTokens,
            topP: provider.requestOverrides.topP,
            stop: provider.requestOverrides.nonEmptyStopSequences,
            seed: provider.requestOverrides.seed,
            presencePenalty: provider.requestOverrides.presencePenalty,
            frequencyPenalty: provider.requestOverrides.frequencyPenalty,
            reasoningEffort: provider.requestOverrides.reasoningEffort?.rawValue,
            topK: provider.supportsLocalOpenAICompatibleSamplerOverrides
                ? provider.requestOverrides.topK
                : nil,
            repeatPenalty: provider.supportsLocalOpenAICompatibleSamplerOverrides
                ? provider.requestOverrides.repeatPenalty
                : nil,
            stream: true,
            streamOptions: provider.requestsOpenAICompatibleStreamUsage
                ? .init(includeUsage: true)
                : nil,
            tools: tools.chatToolPayloads,
            toolChoice: tools.isEmpty ? nil : "auto"
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private func makeAISDKBridgeRequest(
        provider: ProviderConfiguration,
        messages: [AssistantMessage],
        systemPrompt: String?,
        model: String,
        tools: [ChatToolDefinition]
    ) throws -> URLRequest {
        let url = try aiSDKBridgeEndpoint(provider.endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream, application/x-ndjson, application/json", forHTTPHeaderField: "Accept")

        let payload = AISDKBridgeRequestPayload(
            model: model,
            provider: .init(provider),
            system: messages.openAIResponsesInstructions(overridingSystemPrompt: systemPrompt),
            messages: try messages.openAICompatibleMessages(
                overridingSystemPrompt: systemPrompt,
                usesNativeImages: provider.supportsVision
            ),
            tools: tools.chatToolPayloads,
            temperature: provider.temperature,
            maxOutputTokens: provider.requestOverrides.maxOutputTokens,
            topP: provider.requestOverrides.topP,
            stop: provider.requestOverrides.nonEmptyStopSequences,
            seed: provider.requestOverrides.seed,
            reasoningEffort: provider.requestOverrides.reasoningEffort?.rawValue,
            stream: true
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private func openAICompatibleVersionPath(for provider: ProviderConfiguration) -> String? {
        switch provider.kind {
        case .gemini, .perplexity:
            nil
        case .lmStudio, .customOpenAICompatible, .openAI, .xAI, .mistral, .groq, .openRouter:
            "v1"
        case .ollama, .anthropic, .chatGPTCLI, .claudeCodeCLI, .vercelAISDKBridge:
            nil
        }
    }

    private func requiresOpenAICompatibleAuthorization(_ provider: ProviderConfiguration) -> Bool {
        ProviderSetupService.shared.requiresKeychainSecret(for: provider)
    }

    private func endpoint(
        _ rawValue: String,
        appending pathComponents: [String],
        ensuringVersionPath versionPath: String? = nil
    ) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil else {
            throw ChatStreamingError.invalidEndpoint
        }

        var path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let versionPath,
           path.split(separator: "/").last != Substring(versionPath) {
            path = path.isEmpty ? versionPath : "\(path)/\(versionPath)"
        }

        for component in pathComponents {
            path = path.isEmpty ? component : "\(path)/\(component)"
        }

        components.path = "/" + path
        guard let url = components.url else {
            throw ChatStreamingError.invalidEndpoint
        }
        return url
    }

    private func aiSDKBridgeEndpoint(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil else {
            throw ChatStreamingError.invalidEndpoint
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathComponents = path.split(separator: "/").map(String.init)
        if pathComponents.last?.lowercased() != "chat" {
            components.path = "/" + (path.isEmpty ? "api/chat" : "\(path)/api/chat")
        }

        guard let url = components.url else {
            throw ChatStreamingError.invalidEndpoint
        }
        return url
    }

    private func keychainReference(from rawValue: String?) -> KeychainSecretReference? {
        ProviderSetupService.shared.parseSecretReference(rawValue)
    }
}

enum ChatStreamingError: LocalizedError, Equatable {
    case invalidEndpoint
    case missingModel
    case missingKeychainReference(String)
    case unsupportedProviderMode(String)
    case unreadableAttachment(String, String)
    case attachmentTooLarge(String, Int)
    case badStatus

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The provider endpoint is not a valid URL."
        case .missingModel:
            "Choose a model before starting a streaming chat."
        case .missingKeychainReference(let provider):
            "\(provider) needs a Keychain-backed API key before Flannel can stream from it."
        case .unsupportedProviderMode(let provider):
            "\(provider) is configured, but this streaming transport is not implemented yet."
        case .unreadableAttachment(let title, let detail):
            "Flannel could not read the image attachment \(title): \(detail)"
        case .attachmentTooLarge(let title, let limit):
            "\(title) is larger than Flannel's \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) native image payload limit."
        case .badStatus:
            "The provider returned a non-success HTTP status."
        }
    }
}

private struct OllamaChatRequestPayload: Encodable {
    var model: String
    var messages: [OllamaChatPayloadMessage]
    var stream: Bool
    var options: Options
    var tools: [ChatToolPayload]?

    struct Options: Encodable {
        var temperature: Double
        var numPredict: Int?
        var topP: Double?
        var topK: Int?
        var seed: Int?
        var stop: [String]?
        var repeatPenalty: Double?
        var numCtx: Int?

        enum CodingKeys: String, CodingKey {
            case temperature
            case numPredict = "num_predict"
            case topP = "top_p"
            case topK = "top_k"
            case seed
            case stop
            case repeatPenalty = "repeat_penalty"
            case numCtx = "num_ctx"
        }
    }
}

private struct OllamaChatPayloadMessage: Encodable, Hashable, Sendable {
    var role: String
    var content: String
    var images: [String]?
    var toolName: String?
    var toolCalls: [OllamaChatPayloadToolCall]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case images
        case toolName = "tool_name"
        case toolCalls = "tool_calls"
    }
}

private struct OpenAICompatibleChatRequestPayload: Encodable {
    var model: String
    var messages: [OpenAICompatibleChatPayloadMessage]
    var temperature: Double
    var maxCompletionTokens: Int?
    var maxTokens: Int?
    var topP: Double?
    var stop: [String]?
    var seed: Int?
    var presencePenalty: Double?
    var frequencyPenalty: Double?
    var reasoningEffort: String?
    var topK: Int?
    var repeatPenalty: Double?
    var stream: Bool
    var streamOptions: StreamOptions?
    var tools: [ChatToolPayload]?
    var toolChoice: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case stop
        case seed
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case reasoningEffort = "reasoning_effort"
        case topK = "top_k"
        case repeatPenalty = "repeat_penalty"
        case stream
        case streamOptions = "stream_options"
        case tools
        case toolChoice = "tool_choice"
    }

    struct StreamOptions: Encodable {
        var includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }
}

private struct AISDKBridgeRequestPayload: Encodable {
    var schemaVersion = "flannel.ai-sdk-bridge.v1"
    var model: String
    var provider: AISDKBridgeProviderContext
    var system: String?
    var messages: [OpenAICompatibleChatPayloadMessage]
    var tools: [ChatToolPayload]?
    var temperature: Double
    var maxOutputTokens: Int?
    var topP: Double?
    var stop: [String]?
    var seed: Int?
    var reasoningEffort: String?
    var stream: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case model
        case provider
        case system
        case messages
        case tools
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case topP = "top_p"
        case stop
        case seed
        case reasoningEffort = "reasoning_effort"
        case stream
    }
}

private struct AISDKBridgeProviderContext: Encodable {
    var kind: String
    var displayName: String
    var accessMode: String
    var privacyScope: String
    var endpoint: String
    var capabilities: [String]

    init(_ provider: ProviderConfiguration) {
        kind = provider.kind.rawValue
        displayName = provider.displayName
        accessMode = provider.accessMode.rawValue
        privacyScope = provider.privacyScope.rawValue
        endpoint = provider.endpoint
        capabilities = provider.capabilities.map(\.rawValue).sorted()
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case displayName = "display_name"
        case accessMode = "access_mode"
        case privacyScope = "privacy_scope"
        case endpoint
        case capabilities
    }
}

private struct OpenAIResponsesRequestPayload: Encodable {
    var model: String
    var input: [OpenAIResponsesInputItem]
    var instructions: String?
    var temperature: Double
    var maxOutputTokens: Int?
    var topP: Double?
    var stream: Bool
    var tools: [OpenAIResponsesToolPayload]?
    var toolChoice: String?
    var reasoning: OpenAIResponsesReasoning?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case instructions
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case topP = "top_p"
        case stream
        case tools
        case toolChoice = "tool_choice"
        case reasoning
    }
}

private struct OpenAIResponsesReasoning: Encodable, Hashable, Sendable {
    var effort: String
}

private struct OpenAIResponsesToolPayload: Encodable, Hashable, Sendable {
    var type = "function"
    var name: String
    var description: String
    var parameters: ChatToolInputSchema
    var strict: Bool

    nonisolated init(definition: ChatToolDefinition) {
        name = definition.name
        description = definition.description
        parameters = definition.inputSchema
        strict = false
    }
}

private struct ChatToolPayload: Encodable, Hashable, Sendable {
    var type = "function"
    var function: Function

    nonisolated init(definition: ChatToolDefinition) {
        function = Function(
            name: definition.name,
            description: definition.description,
            parameters: definition.inputSchema
        )
    }

    struct Function: Encodable, Hashable, Sendable {
        var name: String
        var description: String
        var parameters: ChatToolInputSchema
    }
}

private extension Array where Element == ChatToolDefinition {
    var chatToolPayloads: [ChatToolPayload]? {
        let payloads = map(ChatToolPayload.init(definition:))
        return payloads.isEmpty ? nil : payloads
    }

    var openAIResponsesToolPayloads: [OpenAIResponsesToolPayload]? {
        let payloads = map(OpenAIResponsesToolPayload.init(definition:))
        return payloads.isEmpty ? nil : payloads
    }

    var anthropicToolPayloads: [AnthropicToolPayload]? {
        let payloads = map(AnthropicToolPayload.init(definition:))
        return payloads.isEmpty ? nil : payloads
    }
}

private enum OpenAIResponsesInputItem: Encodable, Hashable, Sendable {
    case message(OpenAIResponsesMessageInputItem)
    case functionCall(OpenAIResponsesFunctionCallInputItem)
    case functionCallOutput(OpenAIResponsesFunctionCallOutputInputItem)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let item):
            try item.encode(to: encoder)
        case .functionCall(let item):
            try item.encode(to: encoder)
        case .functionCallOutput(let item):
            try item.encode(to: encoder)
        }
    }
}

private struct OpenAIResponsesMessageInputItem: Encodable, Hashable, Sendable {
    var type = "message"
    var role: String
    var content: OpenAIResponsesMessageContent
}

private struct OpenAIResponsesFunctionCallInputItem: Encodable, Hashable, Sendable {
    var type = "function_call"
    var callID: String
    var name: String
    var arguments: String

    enum CodingKeys: String, CodingKey {
        case type
        case callID = "call_id"
        case name
        case arguments
    }
}

private struct OpenAIResponsesFunctionCallOutputInputItem: Encodable, Hashable, Sendable {
    var type = "function_call_output"
    var callID: String
    var output: String

    enum CodingKeys: String, CodingKey {
        case type
        case callID = "call_id"
        case output
    }
}

private enum OpenAIResponsesMessageContent: Encodable, Hashable, Sendable {
    case text(String)
    case parts([OpenAIResponsesContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

private struct OpenAIResponsesContentPart: Encodable, Hashable, Sendable {
    var type: String
    var text: String?
    var imageURL: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct AnthropicMessagesRequestPayload: Encodable {
    var model: String
    var maxTokens: Int
    var messages: [AnthropicChatPayloadMessage]
    var system: String?
    var temperature: Double
    var topP: Double?
    var topK: Int?
    var stopSequences: [String]?
    var stream: Bool
    var tools: [AnthropicToolPayload]?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case system
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case stopSequences = "stop_sequences"
        case stream
        case tools
    }
}

private struct AnthropicToolPayload: Encodable, Hashable, Sendable {
    var name: String
    var description: String
    var inputSchema: ChatToolInputSchema

    nonisolated init(definition: ChatToolDefinition) {
        name = definition.name
        description = definition.description
        inputSchema = definition.inputSchema
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

private struct OpenAICompatibleChatPayloadMessage: Encodable, Hashable, Sendable {
    var role: String
    var content: OpenAICompatibleMessageContent?
    var toolCalls: [OpenAICompatiblePayloadToolCall]?
    var toolCallID: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }
}

private struct OpenAICompatiblePayloadToolCall: Encodable, Hashable, Sendable {
    var id: String
    var type = "function"
    var function: Function

    struct Function: Encodable, Hashable, Sendable {
        var name: String
        var arguments: String
    }
}

private struct OllamaChatPayloadToolCall: Encodable, Hashable, Sendable {
    var type = "function"
    var function: Function

    struct Function: Encodable, Hashable, Sendable {
        var index: Int
        var name: String
        var arguments: JSONValue
    }
}

private enum OpenAICompatibleMessageContent: Encodable, Hashable, Sendable {
    case text(String)
    case parts([OpenAICompatibleContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

private struct OpenAICompatibleContentPart: Encodable, Hashable, Sendable {
    var type: String
    var text: String?
    var imageURL: ImageURL?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    struct ImageURL: Encodable, Hashable, Sendable {
        var url: String
    }
}

private struct AnthropicChatPayloadMessage: Encodable, Hashable, Sendable {
    var role: String
    var content: AnthropicMessageContent
}

private enum AnthropicMessageContent: Encodable, Hashable, Sendable {
    case text(String)
    case blocks([AnthropicContentBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

private struct AnthropicContentBlock: Encodable, Hashable, Sendable {
    var type: String
    var text: String? = nil
    var source: AnthropicImageSource? = nil
    var id: String? = nil
    var name: String? = nil
    var input: JSONValue? = nil
    var toolUseID: String? = nil
    var content: String? = nil

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case id
        case name
        case input
        case toolUseID = "tool_use_id"
        case content
    }
}

private struct AnthropicImageSource: Encodable, Hashable, Sendable {
    var type = "base64"
    var mediaType: String
    var data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct EncodedChatImage: Hashable, Sendable {
    static let maximumNativePayloadBytes = 20_000_000

    var mimeType: String
    var base64Data: String

    var dataURL: String {
        "data:\(mimeType);base64,\(base64Data)"
    }
}

private indirect enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    init(toolArgumentsJSONString rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            self = trimmed.isEmpty ? .object([:]) : .object(["query": .string(trimmed)])
            return
        }

        switch decoded {
        case .object:
            self = decoded
        default:
            self = .object(["query": decoded])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var jsonString: String {
        let value = jsonCompatibleValue
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    var isEmptyObject: Bool {
        if case .object(let value) = self {
            return value.isEmpty
        }
        return false
    }

    private var jsonCompatibleValue: Any {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            value
        case .object(let value):
            value.mapValues(\.jsonCompatibleValue)
        case .array(let value):
            value.map(\.jsonCompatibleValue)
        case .bool(let value):
            value
        case .null:
            NSNull()
        }
    }
}

private struct OllamaChatStreamChunk: Decodable {
    var message: Message?
    var done: Bool?
    var promptEvalCount: Int?
    var evalCount: Int?
    var totalDuration: Int64?

    var usage: ChatStreamUsage? {
        guard promptEvalCount != nil || evalCount != nil || totalDuration != nil else {
            return nil
        }
        return ChatStreamUsage(
            inputTokens: promptEvalCount,
            outputTokens: evalCount,
            totalTokens: nil,
            latencyMilliseconds: totalDuration.map { Int(Double($0) / 1_000_000.0) }
        )
    }

    enum CodingKeys: String, CodingKey {
        case message
        case done
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
        case totalDuration = "total_duration"
    }

    struct Message: Decodable {
        var role: String?
        var content: String?
        var toolCalls: [ToolCall]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try container.decodeIfPresent(String.self, forKey: .role)
            content = try container.decodeIfPresent(String.self, forKey: .content)
            toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls) ?? []
        }

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCall: Decodable {
        var function: Function

        func streamDelta(index: Int) -> ChatStreamToolCallDelta {
            ChatStreamToolCallDelta(
                index: index,
                id: nil,
                type: "function",
                name: function.name,
                argumentsFragment: function.arguments
            )
        }
    }

    struct Function: Decodable {
        var name: String?
        var arguments: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            if let stringArguments = try? container.decode(String.self, forKey: .arguments) {
                arguments = stringArguments
            } else if let jsonArguments = try? container.decode(JSONValue.self, forKey: .arguments) {
                arguments = jsonArguments.jsonString
            } else {
                arguments = ""
            }
        }

        enum CodingKeys: String, CodingKey {
            case name
            case arguments
        }
    }
}

private struct OpenAICompatibleChatStreamChunk: Decodable {
    var choices: [Choice]
    var usage: Usage?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
    }

    enum CodingKeys: String, CodingKey {
        case choices
        case usage
    }

    struct Choice: Decodable {
        var delta: Delta
    }

    struct Delta: Decodable {
        var content: String?
        var toolCalls: [ToolCallDelta]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            content = try container.decodeIfPresent(String.self, forKey: .content)
            toolCalls = try container.decodeIfPresent([ToolCallDelta].self, forKey: .toolCalls) ?? []
        }

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCallDelta: Decodable {
        var index: Int
        var id: String?
        var type: String?
        var function: FunctionDelta?

        var streamDelta: ChatStreamToolCallDelta {
            ChatStreamToolCallDelta(
                index: index,
                id: id,
                type: type,
                name: function?.name,
                argumentsFragment: function?.arguments ?? ""
            )
        }

        enum CodingKeys: String, CodingKey {
            case index
            case id
            case type
            case function
        }
    }

    struct FunctionDelta: Decodable {
        var name: String?
        var arguments: String?
    }

    struct Usage: Decodable {
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?

        var streamUsage: ChatStreamUsage {
            ChatStreamUsage(
                inputTokens: promptTokens,
                outputTokens: completionTokens,
                totalTokens: totalTokens,
                latencyMilliseconds: nil
            )
        }

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

private struct OpenAIResponsesStreamEvent: Decodable {
    var type: String
    var delta: String?
    var outputIndex: Int?
    var itemID: String?
    var item: Item?
    var response: Response?
    var usage: Usage?

    var streamUsage: ChatStreamUsage? {
        let eventUsage = usage ?? response?.usage
        guard let eventUsage else { return nil }
        return ChatStreamUsage(
            inputTokens: eventUsage.inputTokens,
            outputTokens: eventUsage.outputTokens,
            totalTokens: eventUsage.totalTokens,
            latencyMilliseconds: nil
        )
    }

    var toolCallDelta: ChatStreamToolCallDelta? {
        if type == "response.output_item.added",
           item?.type == "function_call" {
            return ChatStreamToolCallDelta(
                index: outputIndex ?? 0,
                id: item?.callID ?? item?.id ?? itemID,
                type: "function",
                name: item?.name,
                argumentsFragment: ""
            )
        }

        if type == "response.function_call_arguments.delta" {
            return ChatStreamToolCallDelta(
                index: outputIndex ?? 0,
                id: item?.callID ?? itemID,
                type: "function",
                name: nil,
                argumentsFragment: delta ?? ""
            )
        }

        return nil
    }

    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case outputIndex = "output_index"
        case itemID = "item_id"
        case item
        case response
        case usage
    }

    struct Item: Decodable {
        var id: String?
        var callID: String?
        var type: String?
        var name: String?

        enum CodingKeys: String, CodingKey {
            case id
            case callID = "call_id"
            case type
            case name
        }
    }

    struct Response: Decodable {
        var usage: Usage?
    }

    struct Usage: Decodable {
        var inputTokens: Int?
        var outputTokens: Int?
        var totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

private struct AnthropicStreamEvent: Decodable {
    var type: String
    var index: Int?
    var delta: Delta?
    var message: Message?
    var usage: Usage?
    var contentBlock: ContentBlock?

    var streamUsage: ChatStreamUsage? {
        let eventUsage = usage ?? message?.usage
        guard let eventUsage else { return nil }
        return ChatStreamUsage(
            inputTokens: eventUsage.inputTokens,
            outputTokens: eventUsage.outputTokens,
            totalTokens: nil,
            latencyMilliseconds: nil
        )
    }

    var toolCallDelta: ChatStreamToolCallDelta? {
        if type == "content_block_start",
           contentBlock?.type == "tool_use" {
            let inputFragment = contentBlock?.input?.isEmptyObject == false
                ? contentBlock?.input?.jsonString ?? ""
                : ""
            return ChatStreamToolCallDelta(
                index: index ?? 0,
                id: contentBlock?.id,
                type: "function",
                name: contentBlock?.name,
                argumentsFragment: inputFragment
            )
        }

        if type == "content_block_delta",
           delta?.type == "input_json_delta" {
            return ChatStreamToolCallDelta(
                index: index ?? 0,
                id: nil,
                type: "function",
                name: nil,
                argumentsFragment: delta?.partialJSON ?? ""
            )
        }

        return nil
    }

    enum CodingKeys: String, CodingKey {
        case type
        case index
        case delta
        case message
        case usage
        case contentBlock = "content_block"
    }

    struct Delta: Decodable {
        var type: String?
        var text: String?
        var partialJSON: String?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case partialJSON = "partial_json"
        }
    }

    struct ContentBlock: Decodable {
        var type: String?
        var id: String?
        var name: String?
        var input: JSONValue?
    }

    struct Message: Decodable {
        var usage: Usage?
    }

    struct Usage: Decodable {
        var inputTokens: Int?
        var outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

private struct AISDKBridgeStreamEvent: Decodable {
    var type: String
    var text: String?
    var delta: String?
    var index: Int?
    var id: String?
    var toolCallID: String?
    var toolName: String?
    var name: String?
    var input: JSONValue?
    var arguments: String?
    var argsTextDelta: String?
    var inputDelta: String?
    var usage: Usage?
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
    var latencyMilliseconds: Int?

    var normalizedType: String {
        type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var streamUsage: ChatStreamUsage? {
        let resolved = usage.map {
            ChatStreamUsage(
                inputTokens: $0.inputTokens,
                outputTokens: $0.outputTokens,
                totalTokens: $0.totalTokens,
                latencyMilliseconds: $0.latencyMilliseconds
            )
        } ?? ChatStreamUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            latencyMilliseconds: latencyMilliseconds
        )

        guard resolved.inputTokens != nil
                || resolved.outputTokens != nil
                || resolved.totalTokens != nil
                || resolved.latencyMilliseconds != nil else {
            return nil
        }
        return resolved
    }

    var toolCallDelta: ChatStreamToolCallDelta {
        let inputFragment = input?.jsonString ?? ""
        return ChatStreamToolCallDelta(
            index: index ?? 0,
            id: toolCallID ?? id,
            type: "function",
            name: toolName ?? name,
            argumentsFragment: argsTextDelta ?? inputDelta ?? arguments ?? delta ?? inputFragment
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        delta = try container.decodeIfPresent(String.self, forKey: .delta)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
            ?? container.decodeIfPresent(String.self, forKey: .toolCallId)
            ?? container.decodeIfPresent(String.self, forKey: .toolCallSnakeID)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
            ?? container.decodeIfPresent(String.self, forKey: .toolNameSnake)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        input = try container.decodeIfPresent(JSONValue.self, forKey: .input)
        arguments = try container.decodeIfPresent(String.self, forKey: .arguments)
        argsTextDelta = try container.decodeIfPresent(String.self, forKey: .argsTextDelta)
            ?? container.decodeIfPresent(String.self, forKey: .argsTextDeltaSnake)
        inputDelta = try container.decodeIfPresent(String.self, forKey: .inputDelta)
            ?? container.decodeIfPresent(String.self, forKey: .inputDeltaSnake)
        usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .inputTokensSnake)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .outputTokensSnake)
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .totalTokensSnake)
        latencyMilliseconds = try container.decodeIfPresent(Int.self, forKey: .latencyMilliseconds)
            ?? container.decodeIfPresent(Int.self, forKey: .latencyMillisecondsSnake)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case delta
        case index
        case id
        case toolCallID = "toolCallID"
        case toolCallId
        case toolCallSnakeID = "tool_call_id"
        case toolName
        case toolNameSnake = "tool_name"
        case name
        case input
        case arguments
        case argsTextDelta
        case argsTextDeltaSnake = "args_text_delta"
        case inputDelta
        case inputDeltaSnake = "input_delta"
        case usage
        case inputTokens
        case inputTokensSnake = "input_tokens"
        case outputTokens
        case outputTokensSnake = "output_tokens"
        case totalTokens
        case totalTokensSnake = "total_tokens"
        case latencyMilliseconds
        case latencyMillisecondsSnake = "latency_milliseconds"
    }

    struct Usage: Decodable {
        var inputTokens: Int?
        var outputTokens: Int?
        var totalTokens: Int?
        var latencyMilliseconds: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
                ?? container.decodeIfPresent(Int.self, forKey: .inputTokensSnake)
                ?? container.decodeIfPresent(Int.self, forKey: .promptTokens)
            outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
                ?? container.decodeIfPresent(Int.self, forKey: .outputTokensSnake)
                ?? container.decodeIfPresent(Int.self, forKey: .completionTokens)
            totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
                ?? container.decodeIfPresent(Int.self, forKey: .totalTokensSnake)
            latencyMilliseconds = try container.decodeIfPresent(Int.self, forKey: .latencyMilliseconds)
                ?? container.decodeIfPresent(Int.self, forKey: .latencyMillisecondsSnake)
        }

        enum CodingKeys: String, CodingKey {
            case inputTokens
            case inputTokensSnake = "input_tokens"
            case promptTokens = "prompt_tokens"
            case outputTokens
            case outputTokensSnake = "output_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens
            case totalTokensSnake = "total_tokens"
            case latencyMilliseconds
            case latencyMillisecondsSnake = "latency_milliseconds"
        }
    }
}

private extension ProviderConfiguration {
    var requestsOpenAICompatibleStreamUsage: Bool {
        switch kind {
        case .lmStudio, .openAI, .customOpenAICompatible, .groq, .openRouter, .xAI, .mistral:
            true
        case .gemini, .perplexity, .ollama, .anthropic, .chatGPTCLI, .claudeCodeCLI, .vercelAISDKBridge:
            false
        }
    }

    var usesMaxCompletionTokens: Bool {
        kind == .openAI
    }

    var supportsLocalOpenAICompatibleSamplerOverrides: Bool {
        kind == .lmStudio
    }
}

private extension ProviderRequestOverrides {
    var nonEmptyStopSequences: [String]? {
        let sequences = stopSequences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return sequences.isEmpty ? nil : sequences
    }
}

private extension ProviderReasoningEffort {
    var openAIResponsesReasoning: OpenAIResponsesReasoning {
        OpenAIResponsesReasoning(effort: rawValue)
    }
}

private extension Array where Element == AssistantMessage {
    func openAIResponsesInputItems(
        usesNativeImages: Bool
    ) throws -> [OpenAIResponsesInputItem] {
        let toolResultLookup = toolCallsByExecutionResultID
        let resolvedToolResultIDs = toolResultEntityIDs
        var payload: [OpenAIResponsesInputItem] = []

        for message in self {
            let role = message.role == .assistant ? "assistant" : "user"
            let content = message.textWithAttachmentPromptContext.trimmingCharacters(in: .whitespacesAndNewlines)
            let toolResultContent = message.toolResultOutputText
            if let toolCall = toolResultCall(for: message, using: toolResultLookup),
               let providerCallID = toolCall.normalizedProviderCallID,
               !toolResultContent.isEmpty {
                payload.append(
                    .functionCallOutput(
                        OpenAIResponsesFunctionCallOutputInputItem(
                            callID: providerCallID,
                            output: toolResultContent
                        )
                    )
                )
                continue
            }

            guard message.role != .system else { continue }

            let functionCallItems = message.openAIResponsesFunctionCallItems(resolvedToolResultIDs: resolvedToolResultIDs)
            let images = usesNativeImages && message.role == .user
                ? try message.attachments.nativeImagePayloads()
                : []

            if !content.isEmpty || !images.isEmpty {
                if images.isEmpty {
                    payload.append(
                        .message(
                            OpenAIResponsesMessageInputItem(
                                role: role,
                                content: .text(content)
                            )
                        )
                    )
                } else {
                    let textParts = content.isEmpty
                        ? []
                        : [OpenAIResponsesContentPart(type: "input_text", text: content, imageURL: nil)]
                    let imageParts = images.map {
                        OpenAIResponsesContentPart(
                            type: "input_image",
                            text: nil,
                            imageURL: $0.dataURL
                        )
                    }

                    payload.append(
                        .message(
                            OpenAIResponsesMessageInputItem(
                                role: role,
                                content: .parts(textParts + imageParts)
                            )
                        )
                    )
                }
            }

            payload.append(contentsOf: functionCallItems)
        }

        return payload
    }

    func openAIResponsesInstructions(overridingSystemPrompt systemPrompt: String?) -> String? {
        if let systemPrompt,
           !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return systemPrompt
        }

        return first(where: { $0.role == .system })?.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func ollamaMessages(
        overridingSystemPrompt systemPrompt: String?,
        usesNativeImages: Bool
    ) throws -> [OllamaChatPayloadMessage] {
        let toolResultLookup = toolCallsByExecutionResultID
        let resolvedToolResultIDs = toolResultEntityIDs

        var payload = try compactMap { message -> OllamaChatPayloadMessage? in
            let content = message.textWithAttachmentPromptContext.trimmingCharacters(in: .whitespacesAndNewlines)
            if let toolCall = toolResultCall(for: message, using: toolResultLookup) {
                let toolResultContent = message.toolResultOutputText
                guard !toolResultContent.isEmpty else { return nil }
                return OllamaChatPayloadMessage(
                    role: "tool",
                    content: toolResultContent,
                    images: nil,
                    toolName: toolCall.normalizedToolName,
                    toolCalls: nil
                )
            }

            let toolCalls = message.ollamaPayloadToolCalls(resolvedToolResultIDs: resolvedToolResultIDs)
            guard !content.isEmpty || !toolCalls.isEmpty else { return nil }
            let images = usesNativeImages ? try message.attachments.nativeImagePayloads().map(\.base64Data) : []
            return OllamaChatPayloadMessage(
                role: message.role.transportRole,
                content: content,
                images: images.isEmpty ? nil : images,
                toolName: nil,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            )
        }

        if let systemPrompt,
           !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload.removeAll { $0.role == "system" }
            payload.insert(
                OllamaChatPayloadMessage(role: "system", content: systemPrompt, images: nil, toolName: nil, toolCalls: nil),
                at: 0
            )
        }

        return payload
    }

    func openAICompatibleMessages(
        overridingSystemPrompt systemPrompt: String?,
        usesNativeImages: Bool
    ) throws -> [OpenAICompatibleChatPayloadMessage] {
        let toolResultLookup = toolCallsByExecutionResultID
        let resolvedToolResultIDs = toolResultEntityIDs

        var payload = try compactMap { message -> OpenAICompatibleChatPayloadMessage? in
            let content = message.textWithAttachmentPromptContext.trimmingCharacters(in: .whitespacesAndNewlines)
            if let toolCall = toolResultCall(for: message, using: toolResultLookup),
               let providerCallID = toolCall.normalizedProviderCallID {
                let toolResultContent = message.toolResultOutputText
                guard !toolResultContent.isEmpty else { return nil }
                return OpenAICompatibleChatPayloadMessage(
                    role: "tool",
                    content: .text(toolResultContent),
                    toolCalls: nil,
                    toolCallID: providerCallID
                )
            }

            let toolCalls = message.openAICompatiblePayloadToolCalls(resolvedToolResultIDs: resolvedToolResultIDs)
            guard !content.isEmpty || !toolCalls.isEmpty else { return nil }
            let images = usesNativeImages ? try message.attachments.nativeImagePayloads() : []

            if images.isEmpty {
                return OpenAICompatibleChatPayloadMessage(
                    role: message.role.transportRole,
                    content: .text(content),
                    toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                    toolCallID: nil
                )
            }

            let parts = [OpenAICompatibleContentPart(type: "text", text: content, imageURL: nil)]
                + images.map {
                    OpenAICompatibleContentPart(
                        type: "image_url",
                        text: nil,
                        imageURL: .init(url: $0.dataURL)
                    )
                }

            return OpenAICompatibleChatPayloadMessage(
                role: message.role.transportRole,
                content: .parts(parts),
                toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                toolCallID: nil
            )
        }

        if let systemPrompt,
           !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload.removeAll { $0.role == "system" }
            payload.insert(
                OpenAICompatibleChatPayloadMessage(role: "system", content: .text(systemPrompt), toolCalls: nil, toolCallID: nil),
                at: 0
            )
        }

        return payload
    }

    func anthropicMessages(usesNativeImages: Bool) throws -> [AnthropicChatPayloadMessage] {
        let toolResultLookup = toolCallsByExecutionResultID
        let resolvedToolResultIDs = toolResultEntityIDs
        var payload: [AnthropicChatPayloadMessage] = []
        var pendingToolResultBlocks: [AnthropicContentBlock] = []

        func flushPendingToolResults() {
            guard !pendingToolResultBlocks.isEmpty else { return }
            payload.append(
                AnthropicChatPayloadMessage(
                    role: "user",
                    content: .blocks(pendingToolResultBlocks)
                )
            )
            pendingToolResultBlocks.removeAll()
        }

        func projectedMessage(for message: AssistantMessage) throws -> AnthropicChatPayloadMessage? {
            let content = message.textWithAttachmentPromptContext.trimmingCharacters(in: .whitespacesAndNewlines)
            guard message.role != .system else { return nil }

            let toolUseBlocks = message.anthropicToolUseBlocks(resolvedToolResultIDs: resolvedToolResultIDs)
            guard !content.isEmpty || !toolUseBlocks.isEmpty else { return nil }

            guard usesNativeImages else {
                if toolUseBlocks.isEmpty {
                    return AnthropicChatPayloadMessage(role: message.role.transportRole, content: .text(content))
                }

                let blocks = ([AnthropicContentBlock(type: "text", text: content)] + toolUseBlocks)
                    .filter { block in
                        block.type != "text" || !(block.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                return AnthropicChatPayloadMessage(role: message.role.transportRole, content: .blocks(blocks))
            }

            let images = try message.attachments.nativeImagePayloads()
            guard !images.isEmpty || !toolUseBlocks.isEmpty else {
                return AnthropicChatPayloadMessage(role: message.role.transportRole, content: .text(content))
            }

            let blocks = [AnthropicContentBlock(type: "text", text: content, source: nil)]
                + images.map {
                    AnthropicContentBlock(
                        type: "image",
                        text: nil,
                        source: AnthropicImageSource(mediaType: $0.mimeType, data: $0.base64Data)
                    )
                }
                + toolUseBlocks
            let nonEmptyBlocks = blocks.filter { block in
                block.type != "text" || !(block.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            return AnthropicChatPayloadMessage(role: message.role.transportRole, content: .blocks(nonEmptyBlocks))
        }

        for message in self {
            let toolResultContent = message.toolResultOutputText
            if let toolCall = toolResultCall(for: message, using: toolResultLookup),
               let providerCallID = toolCall.normalizedProviderCallID,
               !toolResultContent.isEmpty {
                pendingToolResultBlocks.append(
                    AnthropicContentBlock(
                        type: "tool_result",
                        toolUseID: providerCallID,
                        content: toolResultContent
                    )
                )
                continue
            }

            flushPendingToolResults()
            if let message = try projectedMessage(for: message) {
                payload.append(message)
            }
        }

        flushPendingToolResults()
        return payload
    }

    func anthropicSystemPrompt(overridingSystemPrompt systemPrompt: String?) -> String? {
        if let systemPrompt,
           !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return systemPrompt
        }

        return first(where: { $0.role == .system })?.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var toolCallsByExecutionResultID: [UUID: AIToolCallRecord] {
        reduce(into: [:]) { lookup, message in
            for toolCall in message.toolCalls {
                guard let executionResultID = toolCall.executionResultID else { continue }
                lookup[executionResultID] = toolCall
            }
        }
    }

    private var toolResultEntityIDs: Set<UUID> {
        reduce(into: Set<UUID>()) { resultIDs, message in
            guard message.attachments.contains(where: { $0.kind == .toolResult }) else { return }
            resultIDs.formUnion(message.referencedEntityIDs)
        }
    }

    private func toolResultCall(
        for message: AssistantMessage,
        using lookup: [UUID: AIToolCallRecord]
    ) -> AIToolCallRecord? {
        guard message.attachments.contains(where: { $0.kind == .toolResult }) else { return nil }
        return message.referencedEntityIDs
            .compactMap { lookup[$0] }
            .first { $0.normalizedProviderCallID != nil || !$0.normalizedToolName.isEmpty }
    }
}

private extension AssistantMessage {
    var toolResultOutputText: String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            return trimmedText
        }

        return attachments.promptContextBlock.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func openAIResponsesFunctionCallItems(
        resolvedToolResultIDs: Set<UUID>
    ) -> [OpenAIResponsesInputItem] {
        toolCalls.compactMap { toolCall in
            guard let executionResultID = toolCall.executionResultID,
                  resolvedToolResultIDs.contains(executionResultID),
                  let providerCallID = toolCall.normalizedProviderCallID,
                  !toolCall.normalizedToolName.isEmpty else {
                return nil
            }
            return .functionCall(
                OpenAIResponsesFunctionCallInputItem(
                    callID: providerCallID,
                    name: toolCall.normalizedToolName,
                    arguments: toolCall.normalizedArgumentsJSON
                )
            )
        }
    }

    func openAICompatiblePayloadToolCalls(
        resolvedToolResultIDs: Set<UUID>
    ) -> [OpenAICompatiblePayloadToolCall] {
        toolCalls.compactMap { toolCall in
            guard let executionResultID = toolCall.executionResultID,
                  resolvedToolResultIDs.contains(executionResultID) else {
                return nil
            }
            return toolCall.openAICompatiblePayloadToolCall
        }
    }

    func ollamaPayloadToolCalls(
        resolvedToolResultIDs: Set<UUID>
    ) -> [OllamaChatPayloadToolCall] {
        toolCalls.enumerated().compactMap { index, toolCall in
            guard let executionResultID = toolCall.executionResultID,
                  resolvedToolResultIDs.contains(executionResultID) else {
                return nil
            }
            return toolCall.ollamaPayloadToolCall(index: index)
        }
    }

    func anthropicToolUseBlocks(
        resolvedToolResultIDs: Set<UUID>
    ) -> [AnthropicContentBlock] {
        toolCalls.compactMap { toolCall in
            guard let executionResultID = toolCall.executionResultID,
                  resolvedToolResultIDs.contains(executionResultID),
                  let providerCallID = toolCall.normalizedProviderCallID,
                  !toolCall.normalizedToolName.isEmpty else {
                return nil
            }

            return AnthropicContentBlock(
                type: "tool_use",
                id: providerCallID,
                name: toolCall.normalizedToolName,
                input: JSONValue(toolArgumentsJSONString: toolCall.normalizedArgumentsJSON)
            )
        }
    }
}

private extension AIToolCallRecord {
    var normalizedProviderCallID: String? {
        let trimmed = providerCallID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedToolName: String {
        toolName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedArgumentsJSON: String {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let encodedString = String(data: encoded, encoding: .utf8) else {
            guard !trimmed.isEmpty,
                  let encoded = try? JSONSerialization.data(withJSONObject: ["query": trimmed], options: [.sortedKeys]),
                  let encodedString = String(data: encoded, encoding: .utf8) else {
                return "{}"
            }
            return encodedString
        }
        return encodedString
    }

    var openAICompatiblePayloadToolCall: OpenAICompatiblePayloadToolCall? {
        guard let providerCallID = normalizedProviderCallID,
              !normalizedToolName.isEmpty else {
            return nil
        }

        return OpenAICompatiblePayloadToolCall(
            id: providerCallID,
            function: .init(
                name: normalizedToolName,
                arguments: normalizedArgumentsJSON
            )
        )
    }

    func ollamaPayloadToolCall(index: Int) -> OllamaChatPayloadToolCall? {
        guard !normalizedToolName.isEmpty else { return nil }
        return OllamaChatPayloadToolCall(
            function: .init(
                index: index,
                name: normalizedToolName,
                arguments: JSONValue(toolArgumentsJSONString: normalizedArgumentsJSON)
            )
        )
    }
}

private extension Array where Element == AIChatAttachment {
    func nativeImagePayloads() throws -> [EncodedChatImage] {
        try compactMap { try $0.nativeImagePayload() }
    }
}

private extension AIChatAttachment {
    func nativeImagePayload() throws -> EncodedChatImage? {
        guard kind == .image else { return nil }
        let url = try resolvedLocalURL()
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw ChatStreamingError.unreadableAttachment(title, error.localizedDescription)
        }

        guard data.count <= EncodedChatImage.maximumNativePayloadBytes else {
            throw ChatStreamingError.attachmentTooLarge(title, EncodedChatImage.maximumNativePayloadBytes)
        }

        return EncodedChatImage(
            mimeType: resolvedMIMEType(for: url),
            base64Data: data.base64EncodedString()
        )
    }

    private func resolvedLocalURL() throws -> URL {
        if let securityScopedBookmarkData {
            var isStale = false
            do {
                return try URL(
                    resolvingBookmarkData: securityScopedBookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            } catch {
                if localPath == nil {
                    throw ChatStreamingError.unreadableAttachment(title, error.localizedDescription)
                }
            }
        }

        if let localPath,
           !localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: localPath)
        }

        throw ChatStreamingError.unreadableAttachment(title, "No local file path or bookmark is available.")
    }

    private func resolvedMIMEType(for url: URL) -> String {
        if let mimeType,
           mimeType.hasPrefix("image/") {
            return mimeType
        }

        return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
    }
}

private extension AssistantRole {
    var transportRole: String {
        switch self {
        case .system:
            "system"
        case .user:
            "user"
        case .assistant:
            "assistant"
        }
    }
}
