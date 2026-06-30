//
//  CLIProviderTransportTests.swift
//  flannelTests
//

import Foundation
import Testing
@testable import flannel

struct CLIProviderTransportTests {
    @Test("Claude Code CLI appends a rendered prompt when the contract uses print mode")
    func claudePrintModeBuildsPromptArgument() throws {
        let provider = ProviderConfiguration(
            kind: .claudeCodeCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "Claude Code CLI",
            endpoint: "claude -p",
            modelIdentifier: "claude-subscription"
        )

        let spec = try CLIProviderCommandBuilder().makeCommandSpec(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Summarize this repo")],
                systemPrompt: "Be terse."
            )
        )

        #expect(spec.executable == "claude")
        #expect(spec.arguments.first == "-p")
        #expect(spec.arguments.last == "System:\nBe terse.\n\nUser:\nSummarize this repo\n\nAssistant:")
        #expect(spec.stdinText == nil)
    }

    @Test("ChatGPT or Codex CLI contracts can inject placeholders directly into argv")
    func codexPlaceholderContractBuildsArguments() throws {
        let provider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: #"codex --model {model} --prompt "{last_user_message}""#,
            modelIdentifier: "gpt-subscription"
        )

        let spec = try CLIProviderCommandBuilder().makeCommandSpec(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(role: .assistant, text: "Ready."),
                    AssistantMessage(role: .user, text: "Fix the failing tests")
                ]
            )
        )

        #expect(spec.executable == "codex")
        #expect(spec.arguments == ["--model", "gpt-subscription", "--prompt", "Fix the failing tests"])
        #expect(spec.stdinText == nil)
    }

    @Test("ChatGPT or Codex CLI falls back to stdin when no prompt placeholder is configured")
    func codexFallsBackToStdinPrompt() throws {
        let provider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "codex exec --json -",
            modelIdentifier: "chatgpt-subscription"
        )

        let spec = try CLIProviderCommandBuilder().makeCommandSpec(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Explain the crash")]
            )
        )

        #expect(spec.arguments == ["exec", "--json", "-"])
        #expect(spec.stdinText == "User:\nExplain the crash\n\nAssistant:")
        #expect(spec.outputFormat == .codexJSONLines)
    }

    @Test("Legacy Codex stdin placeholder contracts remain supported")
    func codexLegacyStdinPlaceholderStillBuildsStdinPrompt() throws {
        let provider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "codex exec --json {stdin}",
            modelIdentifier: "chatgpt-subscription"
        )

        let spec = try CLIProviderCommandBuilder().makeCommandSpec(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Explain the crash")]
            )
        )

        #expect(spec.arguments == ["exec", "--json"])
        #expect(spec.stdinText == "User:\nExplain the crash\n\nAssistant:")
        #expect(spec.outputFormat == .codexJSONLines)
    }

    @Test("Subscription CLI providers expose documented auth status commands for readiness")
    func subscriptionCLIReadinessStatusCommandsUseDocumentedContracts() throws {
        let codexProvider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "/usr/local/bin/codex exec --json -",
            modelIdentifier: "chatgpt-subscription"
        )
        let claudeProvider = ProviderConfiguration(
            kind: .claudeCodeCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "Claude Code CLI",
            endpoint: "/Applications/Claude Code.app/Contents/MacOS/claude -p --output-format stream-json --verbose",
            modelIdentifier: "claude-subscription"
        )
        let builder = CLIProviderCommandBuilder()

        let codexStatusSpec = try builder.makeReadinessStatusCommandSpec(for: codexProvider)
        let claudeStatusSpec = try builder.makeReadinessStatusCommandSpec(for: claudeProvider)
        let codexSpec = try #require(codexStatusSpec)
        let claudeSpec = try #require(claudeStatusSpec)

        #expect(codexSpec.executable == "/usr/local/bin/codex")
        #expect(codexSpec.arguments == ["login", "status"])
        #expect(codexSpec.stdinText == nil)
        #expect(codexSpec.outputFormat == .plainText)

        #expect(claudeSpec.executable == "/Applications/Claude Code.app/Contents/MacOS/claude")
        #expect(claudeSpec.arguments == ["auth", "status"])
        #expect(claudeSpec.stdinText == nil)
        #expect(claudeSpec.outputFormat == .plainText)
    }

    @Test("Rendered CLI prompts preserve transcript metadata, citations, and tool traces")
    func renderedPromptIncludesDurableContextForSubscriptionCLI() throws {
        let provider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "codex exec --json -",
            modelIdentifier: "chatgpt-subscription"
        )
        let toolResultID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let priorAssistantContext = AssistantMessage(
            role: .assistant,
            text: "",
            citations: [
                AIChatCitation(
                    title: "Local RAG source",
                    snippet: "The source explains the current Flannel provider routing design.",
                    sourceIdentifier: "flannel://knowledge/provider-routing",
                    score: 0.9324
                )
            ],
            providerDisplayName: "OpenAI API",
            modelIdentifier: "gpt-5.2",
            inputTokenCount: 120,
            outputTokenCount: 40,
            latencyMilliseconds: 280,
            estimatedCostMicros: 1234,
            providerAccessMode: .apiKey,
            providerPrivacyScope: .externalAPI,
            runStatus: .completed,
            contextTokenCount: 640,
            contextWindowTokens: 128_000,
            tokenCountsAreEstimated: false,
            toolCalls: [
                AIToolCallRecord(
                    providerCallID: "call_workspace",
                    toolName: "workspace_search",
                    permissionScope: .queryRAGIndex,
                    argumentsJSON: #"{"query":"provider routing","limit":3}"#,
                    wasApproved: true,
                    executionStatus: .completed,
                    executionResultID: toolResultID,
                    outputPreview: "Matched the provider matrix and subscription CLI route notes."
                )
            ]
        )

        let spec = try CLIProviderCommandBuilder().makeCommandSpec(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(role: .user, text: "Use the local routing notes."),
                    priorAssistantContext,
                    AssistantMessage(role: .user, text: "Continue from the latest tool result.")
                ]
            )
        )

        let prompt = try #require(spec.stdinText)
        #expect(prompt.contains("Message metadata:"))
        #expect(prompt.contains("- Status: Completed"))
        #expect(prompt.contains("- Provider: OpenAI API"))
        #expect(prompt.contains("- Access mode: API Key"))
        #expect(prompt.contains("- Privacy scope: External API"))
        #expect(prompt.contains("- Model: gpt-5.2"))
        #expect(prompt.contains("- Tokens: 120 input / 40 output"))
        #expect(prompt.contains("- Context: 640 / 128000 tokens"))
        #expect(prompt.contains("- Estimated cost: $0.0012"))
        #expect(prompt.contains("Citations:"))
        #expect(prompt.contains("- [1] Local RAG source; snippet: The source explains the current Flannel provider routing design.; source: flannel://knowledge/provider-routing; score: 0.932"))
        #expect(prompt.contains("Tool trace:"))
        #expect(prompt.contains("- workspace_search (Query RAG index; Executed)"))
        #expect(prompt.contains("  - Provider call ID: call_workspace"))
        #expect(prompt.contains("  - Approved locally: yes"))
        #expect(prompt.contains("  - Local result ID: \(toolResultID.uuidString)"))
        #expect(prompt.contains(#"  - Arguments JSON: {"query":"provider routing","limit":3}"#))
        #expect(prompt.contains("  - Output preview: Matched the provider matrix and subscription CLI route notes."))
        #expect(prompt.hasSuffix("Assistant:"))
    }

    @Test("Claude Code stream-json command contracts select the structured decoder")
    func claudeStreamJSONContractSelectsDecoder() throws {
        let provider = ProviderConfiguration(
            kind: .claudeCodeCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "Claude Code CLI",
            endpoint: "claude -p --output-format stream-json --verbose",
            modelIdentifier: "claude-subscription"
        )

        let spec = try CLIProviderCommandBuilder().makeCommandSpec(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Explain the plan")]
            )
        )

        #expect(Array(spec.arguments.prefix(4)) == ["-p", "--output-format", "stream-json", "--verbose"])
        #expect(spec.outputFormat == .claudeStreamJSON)
    }

    @Test("Command parser keeps quoted argv segments intact")
    func parserPreservesQuotedSegments() throws {
        let tokens = try CLIProviderCommandBuilder.parseCommand(
            #"'/Applications/Claude Code.app/Contents/MacOS/claude' -p "{prompt}""#,
            providerName: "Claude Code CLI"
        )

        #expect(tokens == ["/Applications/Claude Code.app/Contents/MacOS/claude", "-p", "{prompt}"])
    }

    @Test("Command parser handles escaped tokens and whitespace")
    func parserHandlesEscapedTokens() throws {
        let tokens = try CLIProviderCommandBuilder.parseCommand(
            #"codex --prompt "hello\ world" with\ spaces"#,
            providerName: "ChatGPT/Codex CLI"
        )

        #expect(tokens == ["codex", "--prompt", "hello world", "with spaces"])
    }

    @Test("Command parser rejects unterminated quotes")
    func parserRejectsUnterminatedQuote() {
        #expect(throws: CLIProviderTransportError.unterminatedQuote) {
            try CLIProviderCommandBuilder.parseCommand(
                "codex --json \"missing",
                providerName: "ChatGPT/Codex CLI"
            )
        }
    }

    @Test("Command parser rejects dangling escapes")
    func parserRejectsDanglingEscape() {
        #expect(throws: CLIProviderTransportError.danglingEscape) {
            try CLIProviderCommandBuilder.parseCommand(
                "codex --prompt hi\\",
                providerName: "ChatGPT/Codex CLI"
            )
        }
    }

    @Test("Command parser rejects shell syntax")
    func parserRejectsShellSyntax() {
        #expect(throws: CLIProviderTransportError.unsupportedShellSyntax("|")) {
            try CLIProviderCommandBuilder.parseCommand(
                "codex --json | cat",
                providerName: "ChatGPT/Codex CLI"
            )
        }
    }

    @Test("Command parser rejects command substitution syntax")
    func parserRejectsCommandSubstitution() {
        #expect(throws: CLIProviderTransportError.unsupportedShellSyntax("$")) {
            try CLIProviderCommandBuilder.parseCommand(
                #"codex $(ls)"#,
                providerName: "ChatGPT/Codex CLI"
            )
        }
    }

    @Test("Command builder interpolates model, system prompt, and last user placeholders")
    func commandBuilderInterpolatesPromptVariables() throws {
        let provider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "codex --model {model} --system \"{system_prompt}\" \"{last_user_message}\"",
            modelIdentifier: "gpt-subscription"
        )

        let spec = try CLIProviderCommandBuilder().makeCommandSpec(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(role: .system, text: "This should be replaced"),
                    AssistantMessage(role: .user, text: "Seed"),
                    AssistantMessage(role: .assistant, text: "Interim"),
                    AssistantMessage(role: .user, text: "Final user request")
                ],
                systemPrompt: "Be terse."
            )
        )

        #expect(spec.executable == "codex")
        #expect(spec.arguments == ["--model", "gpt-subscription", "--system", "Be terse.", "Final user request"])
        #expect(spec.stdinText == nil)
    }

    @Test("Command builder requires model placeholder value when requested")
    func commandBuilderRequiresModelForModelPlaceholder() {
        let provider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "codex --model {model}",
            modelIdentifier: "   "
        )

        #expect(throws: CLIProviderTransportError.missingModelPlaceholderValue) {
            try CLIProviderCommandBuilder().makeCommandSpec(
                for: ChatStreamingRequest(
                    provider: provider,
                    messages: [AssistantMessage(role: .user, text: "Hi")]
                )
            )
        }
    }

    @Test("Command builder rejects unsupported provider kinds")
    func commandBuilderRejectsUnsupportedProviderKind() {
        let provider = ProviderConfiguration(
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Ollama",
            endpoint: "http://localhost:11434/api/chat",
            modelIdentifier: "llama3.1"
        )

        #expect(throws: CLIProviderTransportError.unsupportedProvider("Ollama")) {
            try CLIProviderCommandBuilder().makeCommandSpec(
                for: ChatStreamingRequest(
                    provider: provider,
                    messages: [AssistantMessage(role: .user, text: "Hi")]
                )
            )
        }
    }

    @Test("Claude Code CLI requires print mode or a prompt placeholder")
    func claudeRequiresPrintModeContract() {
        let provider = ProviderConfiguration(
            kind: .claudeCodeCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "Claude Code CLI",
            endpoint: "claude",
            modelIdentifier: "claude-subscription"
        )

        #expect(throws: CLIProviderTransportError.claudePrintModeRequired) {
            try CLIProviderCommandBuilder().makeCommandSpec(
                for: ChatStreamingRequest(
                    provider: provider,
                    messages: [AssistantMessage(role: .user, text: "Hi")]
                )
            )
        }
    }

    @Test("Prepared commands fail fast when the configured executable is unavailable")
    func preparedCommandChecksExecutableAvailability() {
        let provider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "codex exec --json -",
            modelIdentifier: "chatgpt-subscription"
        )
        let transport = CLIProviderTransport(resolveExecutable: { _ in nil })

        #expect(throws: CLIProviderTransportError.missingExecutable("codex")) {
            try transport.makePreparedCommand(
                for: ChatStreamingRequest(
                    provider: provider,
                    messages: [AssistantMessage(role: .user, text: "Hi")]
                )
            )
        }
    }

    @Test("Prepared readiness status commands fail fast when the configured executable is unavailable")
    func preparedReadinessStatusCommandChecksExecutableAvailability() {
        let provider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "codex exec --json -",
            modelIdentifier: "chatgpt-subscription"
        )
        let transport = CLIProviderTransport(resolveExecutable: { _ in nil })
        let commandSpec = try! CLIProviderCommandBuilder().makeReadinessStatusCommandSpec(for: provider)
        let preparedSpec = try! #require(commandSpec)

        #expect(throws: CLIProviderTransportError.missingExecutable("codex")) {
            try transport.makePreparedCommand(for: preparedSpec)
        }
    }

    @Test("Codex JSONL decoder extracts completed assistant message text")
    func codexJSONLDecoderExtractsAssistantMessageText() throws {
        var decoder = CLIProviderOutputDecoder(
            providerDisplayName: "ChatGPT/Codex CLI",
            format: .codexJSONLines
        )

        let chunks = try decoder.decode(
            """
            {"msg":{"type":"session_configured","session_id":"abc"}}
            {"msg":{"type":"item.completed","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello"},{"type":"output_text","text":" world"}]}}}
            """
        ) + decoder.finish()

        #expect(chunks.joined() == "Hello world")
    }

    @Test("Claude stream-json decoder extracts deltas and avoids duplicate final result")
    func claudeStreamJSONDecoderExtractsStreamingText() throws {
        var decoder = CLIProviderOutputDecoder(
            providerDisplayName: "Claude Code CLI",
            format: .claudeStreamJSON
        )

        let chunks = try decoder.decode(
            """
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello"}]}}
            {"type":"content_block_delta","delta":{"type":"text_delta","text":" world"}}
            {"type":"result","result":"Hello world"}
            """
        ) + decoder.finish()

        #expect(chunks.joined() == "Hello world")
    }

    @Test("Claude json decoder extracts the final result field")
    func claudeJSONDecoderExtractsResultText() throws {
        var decoder = CLIProviderOutputDecoder(
            providerDisplayName: "Claude Code CLI",
            format: .claudeJSON
        )

        let chunks = try decoder.decode(
            """
            {"type":"result","subtype":"success","result":"Done","usage":{"input_tokens":4,"output_tokens":1}}
            """
        ) + decoder.finish()

        #expect(chunks == ["Done"])
    }

    @MainActor
    @Test("ChatStreamingService routes subscription CLI providers into the CLI transport")
    func chatStreamingServiceUsesCLITransportForSubscriptionProviders() async throws {
        let provider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "codex exec --json -",
            modelIdentifier: "chatgpt-subscription"
        )
        let transport = CLIProviderTransport(
            resolveExecutable: { _ in URL(fileURLWithPath: "/usr/bin/true") },
            executeCommand: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield("Hello")
                    continuation.yield(" world")
                    continuation.finish()
                }
            }
        )
        let service = ChatStreamingService(cliTransport: transport)

        var collected = ""
        for try await token in service.streamText(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hi")]
            )
        ) {
            collected += token
        }

        #expect(collected == "Hello world")
    }
}
