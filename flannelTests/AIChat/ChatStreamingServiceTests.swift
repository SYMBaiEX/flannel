//
//  ChatStreamingServiceTests.swift
//  flannelTests
//

import Foundation
import Testing
@testable import flannel

struct ChatStreamingServiceTests {
    @Test("Ollama stream parser extracts message content")
    func ollamaParserExtractsContent() throws {
        let line = #"{"model":"llama3.1","created_at":"2026-06-28T22:00:00Z","message":{"role":"assistant","content":"Hello"},"done":false}"#

        let token = try ChatStreamingService.parseOllamaLine(line)

        #expect(token == "Hello")
    }

    @Test("Ollama stream parser extracts final usage counters")
    func ollamaParserExtractsUsageCounters() throws {
        let line = #"{"model":"llama3.1","done":true,"total_duration":1230000000,"prompt_eval_count":17,"eval_count":23}"#

        let event = try ChatStreamingService.parseOllamaEvent(line)
        guard case .usage(let usage) = event else {
            Issue.record("Expected Ollama usage event")
            return
        }

        #expect(usage.inputTokens == 17)
        #expect(usage.outputTokens == 23)
        #expect(usage.latencyMilliseconds == 1230)
        #expect(usage.hasCompleteTokenCounts)
    }

    @Test("Ollama parser extracts native tool calls with JSON object arguments")
    func ollamaParserExtractsNativeToolCalls() throws {
        let line = #"{"model":"llama3.1","created_at":"2026-06-28T22:00:00Z","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"workspace_search","arguments":{"query":"local","limit":3}}}]},"done":false}"#

        let event = try ChatStreamingService.parseOllamaEvent(line)
        guard case .toolCallDelta(let toolCall) = event else {
            Issue.record("Expected Ollama tool call event")
            return
        }

        #expect(toolCall.index == 0)
        #expect(toolCall.type == "function")
        #expect(toolCall.name == "workspace_search")
        #expect(toolCall.argumentsFragment == #"{"limit":3,"query":"local"}"#)
    }

    @Test("OpenAI-compatible stream parser extracts delta content")
    func openAICompatibleParserExtractsDelta() throws {
        let line = #"data: {"id":"chatcmpl-local","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}"#

        let token = try ChatStreamingService.parseOpenAICompatibleLine(line)

        #expect(token == "Hi")
    }

    @Test("OpenAI-compatible parser extracts streamed usage chunks")
    func openAICompatibleParserExtractsUsage() throws {
        let line = #"data: {"id":"chatcmpl-local","object":"chat.completion.chunk","choices":[],"usage":{"prompt_tokens":11,"completion_tokens":19,"total_tokens":30}}"#

        let event = try ChatStreamingService.parseOpenAICompatibleEvent(line)
        guard case .usage(let usage) = event else {
            Issue.record("Expected OpenAI-compatible usage event")
            return
        }

        #expect(usage.inputTokens == 11)
        #expect(usage.outputTokens == 19)
        #expect(usage.totalTokens == 30)
        #expect(usage.hasCompleteTokenCounts)
    }

    @Test("OpenAI-compatible parser extracts streamed tool call deltas")
    func openAICompatibleParserExtractsToolCallDelta() throws {
        let line = #"data: {"id":"chatcmpl-local","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"workspace_search","arguments":"{\"query\":\"local"}}]},"finish_reason":null}]}"#

        let event = try ChatStreamingService.parseOpenAICompatibleEvent(line)
        guard case .toolCallDelta(let toolCall) = event else {
            Issue.record("Expected OpenAI-compatible tool call delta event")
            return
        }

        #expect(toolCall.index == 0)
        #expect(toolCall.id == "call_abc")
        #expect(toolCall.type == "function")
        #expect(toolCall.name == "workspace_search")
        #expect(toolCall.argumentsFragment == #"{"query":"local"#)
    }

    @Test("OpenAI-compatible parser accepts tool-call arguments encoded as JSON object")
    func openAICompatibleParserAcceptsToolCallArgumentsAsObject() throws {
        let line = #"data: {"id":"chatcmpl-local","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_json_obj","type":"function","function":{"name":"workspace_search","arguments":{"query":"local","limit":3}}}]},"finish_reason":null}]}"#

        let event = try ChatStreamingService.parseOpenAICompatibleEvent(line)
        guard case .toolCallDelta(let toolCall) = event else {
            Issue.record("Expected OpenAI-compatible tool call event")
            return
        }

        #expect(toolCall.index == 0)
        #expect(toolCall.id == "call_json_obj")
        #expect(toolCall.type == "function")
        #expect(toolCall.name == "workspace_search")

        let argsData = try #require(toolCall.argumentsFragment.data(using: .utf8))
        let args = try #require(JSONSerialization.jsonObject(with: argsData) as? [String: Any])
        #expect(args["query"] as? String == "local")
        #expect(args["limit"] as? Int == 3)
    }

    @Test("OpenAI-compatible parser preserves multiple streamed tool call deltas")
    func openAICompatibleParserExtractsMultipleToolCallDeltas() throws {
        let line = #"data: {"id":"chatcmpl-local","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"workspace_search","arguments":"{\"query\":\"local\"}"}},{"index":1,"id":"call_b","type":"function","function":{"name":"web_search","arguments":"{\"query\":\"docs\"}"}}]},"finish_reason":null}]}"#

        let event = try ChatStreamingService.parseOpenAICompatibleEvent(line)
        guard case .toolCallDeltas(let toolCalls) = event else {
            Issue.record("Expected OpenAI-compatible tool call delta batch event")
            return
        }

        #expect(toolCalls.count == 2)
        #expect(toolCalls[0].id == "call_a")
        #expect(toolCalls[0].name == "workspace_search")
        #expect(toolCalls[1].id == "call_b")
        #expect(toolCalls[1].name == "web_search")
    }

    @Test("OpenAI-compatible line parser ignores non-text tool call deltas")
    func openAICompatibleLineParserIgnoresToolCallDelta() throws {
        let line = #"data: {"id":"chatcmpl-local","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]},"finish_reason":null}]}"#

        let token = try ChatStreamingService.parseOpenAICompatibleLine(line)

        #expect(token == nil)
    }

    @Test("Tool call accumulator merges streamed function call fragments by index")
    func toolCallAccumulatorMergesFragmentsByIndex() {
        var accumulator = ChatStreamToolCallAccumulator()

        accumulator.apply(
            ChatStreamToolCallDelta(
                index: 0,
                id: "call_workspace",
                type: "function",
                name: "workspace_search",
                argumentsFragment: "{\"query\":\"local\""
            )
        )
        accumulator.apply(
            ChatStreamToolCallDelta(
                index: 1,
                id: "call_web",
                type: "function",
                name: "web_search",
                argumentsFragment: #"{"query":"docs"#
            )
        )
        accumulator.apply(
            ChatStreamToolCallDelta(
                index: 0,
                id: nil,
                type: nil,
                name: nil,
                argumentsFragment: ",\"limit\":3}"
            )
        )

        let calls = accumulator.toolCalls

        #expect(calls.count == 2)
        #expect(calls[0].id == "call_workspace")
        #expect(calls[0].name == "workspace_search")
        #expect(calls[0].arguments == #"{"query":"local","limit":3}"#)
        #expect(calls[1].id == "call_web")
        #expect(calls[1].arguments == #"{"query":"docs"#)
    }

    @Test("OpenAI-compatible parser ignores done sentinel")
    func openAICompatibleParserIgnoresDoneSentinel() throws {
        let token = try ChatStreamingService.parseOpenAICompatibleLine("data: [DONE]")

        #expect(token == nil)
    }

    @Test("OpenAI Responses parser extracts output text deltas")
    func openAIResponsesParserExtractsOutputTextDeltas() throws {
        let line = #"data: {"type":"response.output_text.delta","delta":"Hello from Responses"}"#

        let token = try ChatStreamingService.parseOpenAIResponsesLine(line)

        #expect(token == "Hello from Responses")
    }

    @Test("OpenAI Responses parser extracts function call argument deltas")
    func openAIResponsesParserExtractsFunctionCallDeltas() throws {
        let addedLine = #"data: {"type":"response.output_item.added","output_index":0,"item":{"id":"fc_123","call_id":"call_123","type":"function_call","name":"workspace_search"}}"#
        let deltaLine = #"data: {"type":"response.function_call_arguments.delta","output_index":0,"item_id":"fc_123","delta":"{\"query\":\"local\"}"}"#

        let addedEvent = try ChatStreamingService.parseOpenAIResponsesEvent(addedLine)
        let deltaEvent = try ChatStreamingService.parseOpenAIResponsesEvent(deltaLine)
        guard case .toolCallDelta(let addedDelta) = addedEvent,
              case .toolCallDelta(let argumentDelta) = deltaEvent else {
            Issue.record("Expected OpenAI Responses tool call deltas")
            return
        }

        #expect(addedDelta.id == "call_123")
        #expect(addedDelta.type == "function")
        #expect(addedDelta.name == "workspace_search")
        #expect(addedDelta.argumentsFragment.isEmpty)
        #expect(argumentDelta.index == 0)
        #expect(argumentDelta.argumentsFragment == #"{"query":"local"}"#)
    }

    @Test("OpenAI Responses parser extracts completed usage")
    func openAIResponsesParserExtractsCompletedUsage() throws {
        let line = #"data: {"type":"response.completed","response":{"usage":{"input_tokens":21,"output_tokens":34,"total_tokens":55}}}"#

        let event = try ChatStreamingService.parseOpenAIResponsesEvent(line)
        guard case .usage(let usage) = event else {
            Issue.record("Expected OpenAI Responses usage event")
            return
        }

        #expect(usage.inputTokens == 21)
        #expect(usage.outputTokens == 34)
        #expect(usage.totalTokens == 55)
        #expect(usage.hasCompleteTokenCounts)
    }

    @Test("Anthropic stream parser extracts text deltas")
    func anthropicParserExtractsTextDeltas() throws {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello from Claude"}}"#

        let token = try ChatStreamingService.parseAnthropicLine(line)

        #expect(token == "Hello from Claude")
    }

    @Test("Anthropic parser ignores non-text events")
    func anthropicParserIgnoresNonTextEvents() throws {
        let line = #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#

        let token = try ChatStreamingService.parseAnthropicLine(line)

        #expect(token == nil)
    }

    @Test("Anthropic parser extracts input and output usage events")
    func anthropicParserExtractsUsageEvents() throws {
        let startLine = #"data: {"type":"message_start","message":{"usage":{"input_tokens":13,"output_tokens":1}}}"#
        let deltaLine = #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":42}}"#

        let startEvent = try ChatStreamingService.parseAnthropicEvent(startLine)
        let deltaEvent = try ChatStreamingService.parseAnthropicEvent(deltaLine)
        guard case .usage(let startUsage) = startEvent,
              case .usage(let deltaUsage) = deltaEvent else {
            Issue.record("Expected Anthropic usage events")
            return
        }

        #expect(startUsage.inputTokens == 13)
        #expect(startUsage.outputTokens == 1)
        #expect(deltaUsage.inputTokens == nil)
        #expect(deltaUsage.outputTokens == 42)
    }

    @Test("Anthropic parser extracts streamed tool use blocks and JSON input deltas")
    func anthropicParserExtractsToolUseDeltas() throws {
        let startLine = #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_workspace","name":"workspace_search","input":{}}}"#
        let deltaLine = #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"query\":\"local\"}"}}"#

        let startEvent = try ChatStreamingService.parseAnthropicEvent(startLine)
        let deltaEvent = try ChatStreamingService.parseAnthropicEvent(deltaLine)
        guard case .toolCallDelta(let startDelta) = startEvent,
              case .toolCallDelta(let inputDelta) = deltaEvent else {
            Issue.record("Expected Anthropic tool use deltas")
            return
        }

        #expect(startDelta.index == 1)
        #expect(startDelta.id == "toolu_workspace")
        #expect(startDelta.type == "function")
        #expect(startDelta.name == "workspace_search")
        #expect(startDelta.argumentsFragment == "")
        #expect(inputDelta.index == 1)
        #expect(inputDelta.argumentsFragment == #"{"query":"local"}"#)
    }

    @Test("LM Studio request targets OpenAI-compatible chat completions path")
    func lmStudioRequestUsesChatCompletionsPath() throws {
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "local-model"
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hello")]
            )
        )

        #expect(request.url?.absoluteString == "http://localhost:1234/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let streamOptions = try #require(json["stream_options"] as? [String: Any])
        #expect(streamOptions["include_usage"] as? Bool == true)
    }

    @Test("Streaming HTTP failures include status and response preview")
    @MainActor
    func streamingHTTPFailuresIncludeStatusAndResponsePreview() async throws {
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "local-model"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatStreamingURLProtocolStub.self]
        ChatStreamingURLProtocolStub.statusCode = 429
        ChatStreamingURLProtocolStub.responseBody = Data(
            #"{"error":{"message":"Rate limit exceeded for local-model."}}"#.utf8
        )
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = ChatStreamingService(session: session)

        do {
            for try await _ in service.streamEvents(
                for: ChatStreamingRequest(
                    provider: provider,
                    messages: [AssistantMessage(role: .user, text: "Hello")]
                )
            ) {
                Issue.record("Unexpected stream event")
            }
            Issue.record("Expected HTTP status failure")
        } catch let error as ChatStreamingError {
            #expect(error == .badStatus(429, #"{"error":{"message":"Rate limit exceeded for local-model."}}"#))
            #expect(error.localizedDescription.contains("HTTP 429"))
            #expect(error.localizedDescription.contains("Rate limit exceeded for local-model."))
        }
    }

    @Test("LM Studio request includes local advanced generation overrides")
    func lmStudioRequestIncludesAdvancedGenerationOverrides() throws {
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "local-model",
            requestOverrides: ProviderRequestOverrides(
                maxOutputTokens: 1024,
                topP: 0.85,
                topK: 40,
                stopSequences: ["END"],
                seed: 42,
                presencePenalty: 0.2,
                frequencyPenalty: 0.1,
                repeatPenalty: 1.15
            )
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hello")]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["max_tokens"] as? Int == 1024)
        #expect(json["max_completion_tokens"] == nil)
        #expect(json["top_p"] as? Double == 0.85)
        #expect(json["top_k"] as? Int == 40)
        #expect(json["seed"] as? Int == 42)
        #expect(json["presence_penalty"] as? Double == 0.2)
        #expect(json["frequency_penalty"] as? Double == 0.1)
        #expect(json["repeat_penalty"] as? Double == 1.15)
        #expect(json["stop"] as? [String] == ["END"])
    }

    @Test("OpenAI-compatible request includes tool definitions when provided")
    func openAICompatibleRequestIncludesToolDefinitions() throws {
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "local-model"
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Search my notes")],
                tools: [
                    ChatToolDefinition(
                        name: "workspace_search",
                        description: "Search the local workspace.",
                        argumentDescription: "Search query"
                    )
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let tools = try #require(json["tools"] as? [[String: Any]])
        let firstTool = try #require(tools.first)
        let function = try #require(firstTool["function"] as? [String: Any])
        let parameters = try #require(function["parameters"] as? [String: Any])
        let properties = try #require(parameters["properties"] as? [String: Any])
        let query = try #require(properties["query"] as? [String: Any])

        #expect(json["tool_choice"] as? String == "auto")
        #expect(firstTool["type"] as? String == "function")
        #expect(function["name"] as? String == "workspace_search")
        #expect(query["type"] as? String == "string")
        #expect(parameters["additionalProperties"] as? Bool == false)
    }

    @Test("AI SDK bridge request uses local bridge chat contract")
    func aiSDKBridgeRequestUsesLocalBridgeChatContract() throws {
        let provider = ProviderConfiguration(
            kind: .vercelAISDKBridge,
            accessMode: .aiSDKBridge,
            privacyScope: .bridgeService,
            displayName: "Vercel AI SDK Bridge",
            endpoint: "http://localhost:4177",
            modelIdentifier: "openai/gpt-5-mini",
            capabilities: [.chat, .streaming, .toolCalling, .structuredOutput],
            supportsStreaming: true,
            supportsToolCalling: true,
            supportsStructuredOutput: true
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(role: .system, text: "Use local context."),
                    AssistantMessage(role: .user, text: "Search my notes.")
                ],
                tools: [
                    ChatToolDefinition(
                        name: "workspace_search",
                        description: "Search local workspace knowledge."
                    )
                ]
            )
        )

        #expect(request.url?.absoluteString == "http://localhost:4177/api/chat")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept")?.contains("text/event-stream") == true)

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let providerContext = try #require(json["provider"] as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let tools = try #require(json["tools"] as? [[String: Any]])

        #expect(json["schema_version"] as? String == "flannel.ai-sdk-bridge.v1")
        #expect(json["model"] as? String == "openai/gpt-5-mini")
        #expect(json["system"] as? String == "Use local context.")
        #expect(json["stream"] as? Bool == true)
        #expect(providerContext["kind"] as? String == "vercelAISDKBridge")
        #expect(providerContext["access_mode"] as? String == "aiSDKBridge")
        #expect(providerContext["privacy_scope"] as? String == "bridgeService")
        #expect(messages.count == 2)
        #expect(messages.first?["role"] as? String == "system")
        #expect(messages.last?["role"] as? String == "user")
        #expect(tools.first?["type"] as? String == "function")
    }

    @Test("AI SDK bridge parser accepts custom text usage and tool events")
    func aiSDKBridgeParserAcceptsCustomEvents() throws {
        let textLine = #"data: {"type":"text-delta","text":"Hello from bridge"}"#
        let usageLine = #"data: {"type":"finish","usage":{"inputTokens":12,"output_tokens":34,"total_tokens":46,"latency_milliseconds":1200}}"#
        let toolLine = #"data: {"type":"tool-call","toolCallID":"call_bridge","toolName":"workspace_search","input":{"query":"local","limit":3}}"#

        let text = try ChatStreamingService.parseAISDKBridgeLine(textLine)
        let usageEvent = try ChatStreamingService.parseAISDKBridgeEvent(usageLine)
        let toolEvent = try ChatStreamingService.parseAISDKBridgeEvent(toolLine)

        #expect(text == "Hello from bridge")
        guard case .usage(let usage) = usageEvent else {
            Issue.record("Expected bridge usage event")
            return
        }
        #expect(usage.inputTokens == 12)
        #expect(usage.outputTokens == 34)
        #expect(usage.totalTokens == 46)
        #expect(usage.latencyMilliseconds == 1200)

        guard case .toolCallDelta(let toolCall) = toolEvent else {
            Issue.record("Expected bridge tool call event")
            return
        }
        #expect(toolCall.id == "call_bridge")
        #expect(toolCall.name == "workspace_search")
        #expect(toolCall.argumentsFragment == #"{"limit":3,"query":"local"}"#)
    }

    @Test("AI SDK bridge parser accepts OpenAI-compatible SSE chunks")
    func aiSDKBridgeParserAcceptsOpenAICompatibleSSE() throws {
        let line = #"data: {"id":"chatcmpl-bridge","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"OpenAI shaped bridge token"},"finish_reason":null}]}"#

        let token = try ChatStreamingService.parseAISDKBridgeLine(line)

        #expect(token == "OpenAI shaped bridge token")
    }

    @Test("OpenAI API request uses Responses API with max output tokens and reasoning effort")
    func openAIRequestUsesResponsesAPIWithMaxOutputTokensAndReasoningEffort() throws {
        let (keychain, reference, cleanup) = try makeTemporaryAPIKey()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "OpenAI API",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-5.2",
            secretReference: reference.rawValue,
            requestOverrides: ProviderRequestOverrides(
                maxOutputTokens: 2048,
                topK: 50,
                repeatPenalty: 1.1,
                reasoningEffort: .high
            )
        )

        let request = try ChatStreamingService(keychain: keychain).makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(role: .system, text: "Use concise citations."),
                    AssistantMessage(role: .user, text: "Reason carefully.")
                ],
                tools: [
                    ChatToolDefinition(
                        name: "workspace_search",
                        description: "Search local workspace knowledge."
                    )
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try #require(json["input"] as? [[String: Any]])
        let tools = try #require(json["tools"] as? [[String: Any]])
        let reasoning = try #require(json["reasoning"] as? [String: Any])

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(json["instructions"] as? String == "Use concise citations.")
        #expect(json["max_output_tokens"] as? Int == 2048)
        #expect(json["max_completion_tokens"] == nil)
        #expect(json["max_tokens"] == nil)
        #expect(json["tool_choice"] as? String == "auto")
        #expect(tools.first?["type"] as? String == "function")
        #expect(tools.first?["name"] as? String == "workspace_search")
        #expect(reasoning["effort"] as? String == "high")
        #expect(input.count == 1)
        #expect(input.first?["type"] as? String == "message")
        #expect(input.first?["role"] as? String == "user")
        #expect(input.first?["content"] as? String == "Reason carefully.")
        #expect(json["top_k"] == nil)
        #expect(json["repeat_penalty"] == nil)
    }

    @Test("OpenAI Responses request encodes resolved function call history and outputs")
    func openAIResponsesRequestEncodesResolvedFunctionCallHistory() throws {
        let (keychain, reference, cleanup) = try makeTemporaryAPIKey()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "OpenAI API",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-5.2",
            secretReference: reference.rawValue
        )
        let resultID = UUID()
        let assistantToolCall = AssistantMessage(
            role: .assistant,
            text: "",
            toolCalls: [
                AIToolCallRecord(
                    providerCallID: "call_workspace_search",
                    toolName: "workspace_search",
                    permissionScope: .readWorkspace,
                    argumentsJSON: #"{"query":"local notes","limit":3}"#,
                    wasApproved: true,
                    executionStatus: .completed,
                    executionResultID: resultID,
                    outputPreview: "Found local notes."
                )
            ]
        )
        let toolResult = AssistantMessage(
            role: .assistant,
            text: "Found local notes.",
            attachments: [
                AIChatAttachment(
                    kind: .toolResult,
                    title: "Workspace Search",
                    mimeType: "text/plain",
                    excerpt: "Found local notes."
                )
            ],
            referencedEntityIDs: [resultID]
        )

        let request = try ChatStreamingService(keychain: keychain).makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(role: .user, text: "Search my notes."),
                    assistantToolCall,
                    toolResult
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try #require(json["input"] as? [[String: Any]])
        let functionCall = try #require(input.first { $0["type"] as? String == "function_call" })
        let functionOutput = try #require(input.first { $0["type"] as? String == "function_call_output" })
        let arguments = try #require(functionCall["arguments"] as? String)
        let argumentData = try #require(arguments.data(using: .utf8))
        let argumentJSON = try #require(JSONSerialization.jsonObject(with: argumentData) as? [String: Any])

        #expect(functionCall["call_id"] as? String == "call_workspace_search")
        #expect(functionCall["name"] as? String == "workspace_search")
        #expect(argumentJSON["query"] as? String == "local notes")
        #expect(argumentJSON["limit"] as? Int == 3)
        #expect(functionOutput["call_id"] as? String == "call_workspace_search")
        #expect(functionOutput["output"] as? String == "Found local notes.")
    }

    @Test("OpenAI-compatible request preserves typed tool input schemas")
    func openAICompatibleRequestPreservesTypedToolInputSchemas() throws {
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "local-model"
        )
        let fileWriteSchema = ChatToolInputSchema(
            properties: [
                "path": .string("Local destination file path."),
                "content": .string("Complete UTF-8 file content."),
                "mode": .stringEnum(["overwrite"], description: "Write behavior.")
            ],
            required: ["path", "content"]
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Write a file")],
                tools: [
                    ChatToolDefinition(
                        name: "local_file_write",
                        description: "Write a local file after approval.",
                        inputSchema: fileWriteSchema
                    )
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let tools = try #require(json["tools"] as? [[String: Any]])
        let function = try #require(tools.first?["function"] as? [String: Any])
        let parameters = try #require(function["parameters"] as? [String: Any])
        let properties = try #require(parameters["properties"] as? [String: Any])
        let required = try #require(parameters["required"] as? [String])
        let mode = try #require(properties["mode"] as? [String: Any])

        #expect(function["name"] as? String == "local_file_write")
        #expect(Set(required) == Set(["path", "content"]))
        #expect(properties["path"] != nil)
        #expect(properties["content"] != nil)
        #expect(mode["enum"] as? [String] == ["overwrite"])
        #expect(parameters["additionalProperties"] as? Bool == false)
    }

    @Test("OpenAI-compatible request encodes resolved provider tool calls and tool result messages")
    func openAICompatibleRequestEncodesResolvedToolCallHistory() throws {
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "local-model"
        )
        let resultID = UUID()
        let assistantToolCall = AssistantMessage(
            role: .assistant,
            text: "Provider requested a local workspace search.",
            toolCalls: [
                AIToolCallRecord(
                    providerCallID: "call_workspace_search",
                    toolName: "workspace_search",
                    permissionScope: .readWorkspace,
                    argumentsJSON: #"{"query":"local notes","limit":3}"#,
                    wasApproved: true,
                    executionStatus: .completed,
                    executionResultID: resultID,
                    outputPreview: "Found local notes."
                )
            ]
        )
        let toolResult = AssistantMessage(
            role: .assistant,
            text: "Tool run: Workspace Search\nStatus: Completed locally.\n\nFound local notes.",
            attachments: [
                AIChatAttachment(
                    kind: .toolResult,
                    title: "Workspace Search",
                    mimeType: "text/plain",
                    excerpt: "Found local notes."
                )
            ],
            referencedEntityIDs: [resultID]
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(role: .user, text: "Search my notes."),
                    assistantToolCall,
                    toolResult
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let assistantMessage = try #require(messages.first { $0["role"] as? String == "assistant" })
        let toolCalls = try #require(assistantMessage["tool_calls"] as? [[String: Any]])
        let firstToolCall = try #require(toolCalls.first)
        let function = try #require(firstToolCall["function"] as? [String: Any])
        let arguments = try #require(function["arguments"] as? String)
        let argumentData = try #require(arguments.data(using: .utf8))
        let argumentJSON = try #require(JSONSerialization.jsonObject(with: argumentData) as? [String: Any])
        let toolMessage = try #require(messages.first { $0["role"] as? String == "tool" })

        #expect(firstToolCall["id"] as? String == "call_workspace_search")
        #expect(firstToolCall["type"] as? String == "function")
        #expect(function["name"] as? String == "workspace_search")
        #expect(argumentJSON["query"] as? String == "local notes")
        #expect(argumentJSON["limit"] as? Int == 3)
        #expect(toolMessage["tool_call_id"] as? String == "call_workspace_search")
        #expect((toolMessage["content"] as? String)?.contains("Found local notes.") == true)
    }

    @Test("Gemini API uses its OpenAI-compatible chat completions path")
    func geminiRequestUsesOpenAICompatiblePath() throws {
        let (keychain, reference, cleanup) = try makeTemporaryAPIKey()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .gemini,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Google Gemini API",
            endpoint: "https://generativelanguage.googleapis.com/v1beta/openai",
            modelIdentifier: "gemini-2.5-pro",
            secretReference: reference.rawValue
        )

        let request = try ChatStreamingService(keychain: keychain).makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hello")]
            )
        )

        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    }

    @Test("xAI API uses OpenAI-compatible v1 chat completions")
    func xAIRequestUsesOpenAICompatiblePath() throws {
        let (keychain, reference, cleanup) = try makeTemporaryAPIKey()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .xAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "xAI API",
            endpoint: "https://api.x.ai/v1",
            modelIdentifier: "grok-4.3",
            secretReference: reference.rawValue
        )

        let request = try ChatStreamingService(keychain: keychain).makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hello")]
            )
        )

        #expect(request.url?.absoluteString == "https://api.x.ai/v1/chat/completions")
    }

    @Test("Mistral API uses OpenAI-compatible v1 chat completions")
    func mistralRequestUsesOpenAICompatiblePath() throws {
        let (keychain, reference, cleanup) = try makeTemporaryAPIKey()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .mistral,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Mistral API",
            endpoint: "https://api.mistral.ai/v1",
            modelIdentifier: "mistral-large-latest",
            secretReference: reference.rawValue
        )

        let request = try ChatStreamingService(keychain: keychain).makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hello")]
            )
        )

        #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/chat/completions")
    }

    @Test("Perplexity API uses OpenAI-compatible chat completions without forcing v1")
    func perplexityRequestUsesOpenAICompatiblePath() throws {
        let (keychain, reference, cleanup) = try makeTemporaryAPIKey()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .perplexity,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Perplexity API",
            endpoint: "https://api.perplexity.ai",
            modelIdentifier: "sonar-pro",
            secretReference: reference.rawValue
        )

        let request = try ChatStreamingService(keychain: keychain).makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hello")]
            )
        )

        #expect(request.url?.absoluteString == "https://api.perplexity.ai/chat/completions")
    }

    @Test("OpenRouter request includes optional app attribution headers")
    func openRouterRequestIncludesAttributionHeaders() throws {
        let (keychain, reference, cleanup) = try makeTemporaryAPIKey()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .openRouter,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "OpenRouter",
            endpoint: "https://openrouter.ai/api/v1",
            modelIdentifier: "openai/gpt-5.5",
            secretReference: reference.rawValue,
            organizationIdentifier: "https://flannel.local"
        )

        let request = try ChatStreamingService(keychain: keychain).makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hello")]
            )
        )

        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "X-OpenRouter-Title") == "Flannel")
        #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == "https://flannel.local")
    }

    @Test("Custom OpenAI-compatible endpoint can stream without an API key")
    func customOpenAICompatibleRequestAllowsMissingAPIKey() throws {
        let provider = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .externalAPI,
            displayName: "Custom Router",
            endpoint: "http://localhost:8080/v1",
            modelIdentifier: "router-model"
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hello")]
            )
        )

        #expect(request.url?.absoluteString == "http://localhost:8080/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Custom OpenAI-compatible endpoint sends optional saved API key")
    func customOpenAICompatibleRequestUsesOptionalAPIKey() throws {
        let (keychain, reference, cleanup) = try makeTemporaryAPIKey()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .externalAPI,
            displayName: "Custom Router",
            endpoint: "https://router.example.com/v1",
            modelIdentifier: "router-model",
            secretReference: reference.rawValue
        )

        let request = try ChatStreamingService(keychain: keychain).makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hello")]
            )
        )

        #expect(request.url?.absoluteString == "https://router.example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    }

    @Test("Keyed custom OpenAI-compatible endpoint requires a Keychain reference")
    func keyedCustomOpenAICompatibleRequestRequiresKeychainReference() throws {
        let provider = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Hosted Custom Router",
            endpoint: "https://router.example.com/v1",
            modelIdentifier: "hosted-router-model"
        )

        #expect(throws: ChatStreamingError.missingKeychainReference("Hosted Custom Router")) {
            _ = try ChatStreamingService().makeURLRequest(
                for: ChatStreamingRequest(
                    provider: provider,
                    messages: [AssistantMessage(role: .user, text: "Hello")]
                )
            )
        }
    }

    @Test("Ollama request targets native chat endpoint")
    func ollamaRequestUsesNativeChatEndpoint() throws {
        let provider = ProviderConfiguration(
            kind: .ollama,
            displayName: "Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1"
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hello")]
            )
        )

        #expect(request.url?.absoluteString == "http://localhost:11434/api/chat")
        #expect(request.httpMethod == "POST")
    }

    @Test("Ollama request includes advanced generation options")
    func ollamaRequestIncludesAdvancedGenerationOptions() throws {
        let provider = ProviderConfiguration(
            kind: .ollama,
            displayName: "Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1",
            contextWindowTokens: 32_768,
            requestOverrides: ProviderRequestOverrides(
                maxOutputTokens: 512,
                topP: 0.9,
                topK: 30,
                stopSequences: ["</done>"],
                seed: 7,
                repeatPenalty: 1.2
            )
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hello")]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let options = try #require(json["options"] as? [String: Any])

        #expect(options["temperature"] as? Double == 0.2)
        #expect(options["num_predict"] as? Int == 512)
        #expect(options["top_p"] as? Double == 0.9)
        #expect(options["top_k"] as? Int == 30)
        #expect(options["seed"] as? Int == 7)
        #expect(options["repeat_penalty"] as? Double == 1.2)
        #expect(options["num_ctx"] as? Int == 32_768)
        #expect(options["stop"] as? [String] == ["</done>"])
    }

    @Test("Ollama request includes overridden system prompt context")
    func ollamaRequestIncludesSystemPromptContext() throws {
        let provider = ProviderConfiguration(
            kind: .ollama,
            displayName: "Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1"
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(role: .system, text: "Old system"),
                    AssistantMessage(role: .user, text: "Hello")
                ],
                systemPrompt: "Use local citations."
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let firstMessage = try #require(messages.first)

        #expect(firstMessage["role"] as? String == "system")
        #expect(firstMessage["content"] as? String == "Use local citations.")
    }

    @Test("Ollama request includes native tool definitions when provided")
    func ollamaRequestIncludesNativeToolDefinitions() throws {
        let provider = ProviderConfiguration(
            kind: .ollama,
            displayName: "Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1"
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Search my notes")],
                tools: [
                    ChatToolDefinition(
                        name: "workspace_search",
                        description: "Search the local workspace.",
                        argumentDescription: "Search query"
                    )
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let tools = try #require(json["tools"] as? [[String: Any]])
        let firstTool = try #require(tools.first)
        let function = try #require(firstTool["function"] as? [String: Any])

        #expect(firstTool["type"] as? String == "function")
        #expect(function["name"] as? String == "workspace_search")
        #expect(json["tool_choice"] == nil)
    }

    @Test("Ollama request encodes resolved native tool calls and tool result messages")
    func ollamaRequestEncodesResolvedToolCallHistory() throws {
        let provider = ProviderConfiguration(
            kind: .ollama,
            displayName: "Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1"
        )
        let resultID = UUID()
        let assistantToolCall = AssistantMessage(
            role: .assistant,
            text: "Provider requested a local workspace search.",
            toolCalls: [
                AIToolCallRecord(
                    providerCallID: nil,
                    toolName: "workspace_search",
                    permissionScope: .readWorkspace,
                    argumentsJSON: #"{"query":"local notes","limit":3}"#,
                    wasApproved: true,
                    executionStatus: .completed,
                    executionResultID: resultID,
                    outputPreview: "Found local notes."
                )
            ]
        )
        let toolResult = AssistantMessage(
            role: .assistant,
            text: "Tool run: Workspace Search\nStatus: Completed locally.\n\nFound local notes.",
            attachments: [
                AIChatAttachment(
                    kind: .toolResult,
                    title: "Workspace Search",
                    mimeType: "text/plain",
                    excerpt: "Found local notes."
                )
            ],
            referencedEntityIDs: [resultID]
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(role: .user, text: "Search my notes."),
                    assistantToolCall,
                    toolResult
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let assistantMessage = try #require(messages.first { $0["role"] as? String == "assistant" })
        let toolCalls = try #require(assistantMessage["tool_calls"] as? [[String: Any]])
        let firstToolCall = try #require(toolCalls.first)
        let function = try #require(firstToolCall["function"] as? [String: Any])
        let arguments = try #require(function["arguments"] as? [String: Any])
        let toolMessage = try #require(messages.first { $0["role"] as? String == "tool" })

        #expect(firstToolCall["type"] as? String == "function")
        #expect(function["name"] as? String == "workspace_search")
        #expect(function["index"] as? Int == 0)
        #expect(arguments["query"] as? String == "local notes")
        #expect(arguments["limit"] as? Int == 3)
        #expect(toolMessage["tool_name"] as? String == "workspace_search")
        #expect((toolMessage["content"] as? String)?.contains("Found local notes.") == true)
    }

    @Test("Provider request includes local attachment context in user content")
    func providerRequestIncludesAttachmentContext() throws {
        let provider = ProviderConfiguration(
            kind: .ollama,
            displayName: "Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1"
        )
        let attachment = AIChatAttachment(
            kind: .textSnippet,
            title: "research.md",
            mimeType: "text/markdown",
            localPath: "/tmp/research.md",
            byteCount: 128,
            excerpt: "Use the local answer."
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(
                        role: .user,
                        text: "Answer with this source.",
                        attachments: [attachment]
                    )
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? String)

        #expect(content.contains("Answer with this source."))
        #expect(content.contains("Attached files:"))
        #expect(content.contains("research.md"))
        #expect(content.contains("Use the local answer."))
    }

    @Test("Ollama vision providers receive native base64 image payloads")
    func ollamaVisionProviderReceivesNativeImagePayload() throws {
        let (attachment, imageData, cleanup) = try makeImageAttachment()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .ollama,
            displayName: "Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llava",
            supportsVision: true
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(
                        role: .user,
                        text: "Describe this image.",
                        attachments: [attachment]
                    )
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let images = try #require(messages.first?["images"] as? [String])

        #expect(images == [imageData.base64EncodedString()])
        #expect(messages.first?["content"] as? String != nil)
    }

    @Test("OpenAI-compatible vision providers receive image_url content parts")
    func openAICompatibleVisionProviderReceivesImageURLParts() throws {
        let (attachment, imageData, cleanup) = try makeImageAttachment()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "local-vision-model",
            supportsVision: true
        )

        let request = try ChatStreamingService().makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(
                        role: .user,
                        text: "Describe this image.",
                        attachments: [attachment]
                    )
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        let imagePart = try #require(content.first { $0["type"] as? String == "image_url" })
        let imageURL = try #require(imagePart["image_url"] as? [String: Any])

        #expect(content.first?["type"] as? String == "text")
        #expect((imageURL["url"] as? String)?.contains("data:image/png;base64,\(imageData.base64EncodedString())") == true)
    }

    @Test("Anthropic vision providers receive image content blocks")
    func anthropicVisionProviderReceivesImageBlocks() throws {
        let (attachment, imageData, cleanupImage) = try makeImageAttachment()
        defer { cleanupImage() }
        let keychain = KeychainSecretStore()
        let account = "flannel-tests-\(UUID().uuidString)"
        let reference = try keychain.save("test-key", account: account)
        defer { try? keychain.delete(reference) }
        let provider = ProviderConfiguration(
            kind: .anthropic,
            displayName: "Anthropic",
            endpoint: "https://api.anthropic.com",
            modelIdentifier: "claude-sonnet-4-5",
            secretReference: reference.rawValue,
            supportsVision: true
        )

        let request = try ChatStreamingService(keychain: keychain).makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(
                        role: .user,
                        text: "Describe this image.",
                        attachments: [attachment]
                    )
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        let imageBlock = try #require(content.first { $0["type"] as? String == "image" })
        let source = try #require(imageBlock["source"] as? [String: Any])

        #expect(content.first?["type"] as? String == "text")
        #expect(source["type"] as? String == "base64")
        #expect(source["media_type"] as? String == "image/png")
        #expect(source["data"] as? String == imageData.base64EncodedString())
    }

    @Test("Anthropic request includes advanced generation controls")
    func anthropicRequestIncludesAdvancedGenerationControls() throws {
        let (keychain, reference, cleanup) = try makeTemporaryAPIKey()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .anthropic,
            displayName: "Anthropic",
            endpoint: "https://api.anthropic.com",
            modelIdentifier: "claude-sonnet-4-5",
            secretReference: reference.rawValue,
            requestOverrides: ProviderRequestOverrides(
                maxOutputTokens: 3072,
                topP: 0.75,
                topK: 64,
                stopSequences: ["DONE"]
            )
        )

        let request = try ChatStreamingService(keychain: keychain).makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [AssistantMessage(role: .user, text: "Hello Claude")]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["max_tokens"] as? Int == 3072)
        #expect(json["top_p"] as? Double == 0.75)
        #expect(json["top_k"] as? Int == 64)
        #expect(json["stop_sequences"] as? [String] == ["DONE"])
    }

    @Test("Anthropic request includes tool definitions and resolved tool result blocks")
    func anthropicRequestIncludesToolDefinitionsAndResolvedToolResultBlocks() throws {
        let (keychain, reference, cleanup) = try makeTemporaryAPIKey()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .anthropic,
            displayName: "Anthropic",
            endpoint: "https://api.anthropic.com",
            modelIdentifier: "claude-sonnet-4-5",
            secretReference: reference.rawValue
        )
        let resultID = UUID()
        let assistantToolCall = AssistantMessage(
            role: .assistant,
            text: "I will search the local workspace.",
            toolCalls: [
                AIToolCallRecord(
                    providerCallID: "toolu_workspace_search",
                    toolName: "workspace_search",
                    permissionScope: .readWorkspace,
                    argumentsJSON: #"{"query":"local notes","limit":3}"#,
                    wasApproved: true,
                    executionStatus: .completed,
                    executionResultID: resultID,
                    outputPreview: "Found local notes."
                )
            ]
        )
        let toolResult = AssistantMessage(
            role: .assistant,
            text: "Tool run: Workspace Search\nStatus: Completed locally.\n\nFound local notes.",
            attachments: [
                AIChatAttachment(
                    kind: .toolResult,
                    title: "Workspace Search",
                    mimeType: "text/plain",
                    excerpt: "Found local notes."
                )
            ],
            referencedEntityIDs: [resultID]
        )

        let request = try ChatStreamingService(keychain: keychain).makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(role: .user, text: "Search my notes."),
                    assistantToolCall,
                    toolResult
                ],
                tools: [
                    ChatToolDefinition(
                        name: "workspace_search",
                        description: "Search local workspace notes.",
                        argumentDescription: "Search query",
                        inputSchema: ChatToolInputSchema(
                            properties: [
                                "query": .string("Search query"),
                                "limit": .integer("Maximum number of chunks")
                            ],
                            required: ["query"]
                        )
                    )
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let tools = try #require(json["tools"] as? [[String: Any]])
        let firstTool = try #require(tools.first)
        let inputSchema = try #require(firstTool["input_schema"] as? [String: Any])
        let inputProperties = try #require(inputSchema["properties"] as? [String: Any])
        let inputRequired = try #require(inputSchema["required"] as? [String])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let assistantMessage = try #require(messages.first { $0["role"] as? String == "assistant" })
        let assistantBlocks = try #require(assistantMessage["content"] as? [[String: Any]])
        let toolUse = try #require(assistantBlocks.first { $0["type"] as? String == "tool_use" })
        let toolInput = try #require(toolUse["input"] as? [String: Any])
        let toolResultMessage = try #require(messages.first { message in
            guard message["role"] as? String == "user",
                  let content = message["content"] as? [[String: Any]] else { return false }
            return content.contains { $0["type"] as? String == "tool_result" }
        })
        let toolResultBlocks = try #require(toolResultMessage["content"] as? [[String: Any]])
        let toolResultBlock = try #require(toolResultBlocks.first)

        #expect(firstTool["name"] as? String == "workspace_search")
        #expect(firstTool["description"] as? String == "Search local workspace notes.")
        #expect(inputSchema["type"] as? String == "object")
        #expect(inputProperties["query"] != nil)
        #expect(inputProperties["limit"] != nil)
        #expect(inputRequired == ["query"])
        #expect(toolUse["id"] as? String == "toolu_workspace_search")
        #expect(toolUse["name"] as? String == "workspace_search")
        #expect(toolInput["query"] as? String == "local notes")
        #expect(toolInput["limit"] as? Int == 3)
        #expect(toolResultBlock["type"] as? String == "tool_result")
        #expect(toolResultBlock["tool_use_id"] as? String == "toolu_workspace_search")
        #expect((toolResultBlock["content"] as? String)?.contains("Found local notes.") == true)
    }

    @Test("Anthropic request groups parallel tool results into one following user message")
    func anthropicRequestGroupsParallelToolResults() throws {
        let (keychain, reference, cleanup) = try makeTemporaryAPIKey()
        defer { cleanup() }
        let provider = ProviderConfiguration(
            kind: .anthropic,
            displayName: "Anthropic",
            endpoint: "https://api.anthropic.com",
            modelIdentifier: "claude-sonnet-4-5",
            secretReference: reference.rawValue
        )
        let firstResultID = UUID()
        let secondResultID = UUID()
        let assistantToolCall = AssistantMessage(
            role: .assistant,
            text: "",
            toolCalls: [
                AIToolCallRecord(
                    providerCallID: "toolu_workspace",
                    toolName: "workspace_search",
                    permissionScope: .readWorkspace,
                    argumentsJSON: #"{"query":"workspace"}"#,
                    wasApproved: true,
                    executionStatus: .completed,
                    executionResultID: firstResultID,
                    outputPreview: "Workspace result."
                ),
                AIToolCallRecord(
                    providerCallID: "toolu_rag",
                    toolName: "rag_retrieval",
                    permissionScope: .queryRAGIndex,
                    argumentsJSON: #"{"query":"rag"}"#,
                    wasApproved: true,
                    executionStatus: .completed,
                    executionResultID: secondResultID,
                    outputPreview: "RAG result."
                )
            ]
        )
        let firstToolResult = AssistantMessage(
            role: .assistant,
            text: "Workspace result.",
            attachments: [
                AIChatAttachment(kind: .toolResult, title: "Workspace Search", mimeType: "text/plain")
            ],
            referencedEntityIDs: [firstResultID]
        )
        let secondToolResult = AssistantMessage(
            role: .assistant,
            text: "RAG result.",
            attachments: [
                AIChatAttachment(kind: .toolResult, title: "RAG Retrieval", mimeType: "text/plain")
            ],
            referencedEntityIDs: [secondResultID]
        )

        let request = try ChatStreamingService(keychain: keychain).makeURLRequest(
            for: ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(role: .user, text: "Use two tools."),
                    assistantToolCall,
                    firstToolResult,
                    secondToolResult
                ]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let toolResultMessages = messages.filter { message in
            guard message["role"] as? String == "user",
                  let content = message["content"] as? [[String: Any]] else { return false }
            return content.contains { $0["type"] as? String == "tool_result" }
        }
        let groupedMessage = try #require(toolResultMessages.first)
        let blocks = try #require(groupedMessage["content"] as? [[String: Any]])

        #expect(toolResultMessages.count == 1)
        #expect(blocks.count == 2)
        #expect(blocks[0]["tool_use_id"] as? String == "toolu_workspace")
        #expect((blocks[0]["content"] as? String)?.contains("Workspace result.") == true)
        #expect(blocks[1]["tool_use_id"] as? String == "toolu_rag")
        #expect((blocks[1]["content"] as? String)?.contains("RAG result.") == true)
    }

    @Test("Anthropic request requires a Keychain reference")
    func anthropicRequestRequiresKeychainReference() throws {
        let provider = ProviderConfiguration(
            kind: .anthropic,
            displayName: "Anthropic",
            endpoint: "https://api.anthropic.com",
            modelIdentifier: "claude-sonnet-4-5"
        )

        #expect(throws: ChatStreamingError.missingKeychainReference("Anthropic")) {
            _ = try ChatStreamingService().makeURLRequest(
                for: ChatStreamingRequest(
                    provider: provider,
                    messages: [AssistantMessage(role: .user, text: "Hello")]
                )
            )
        }
    }

    private func makeImageAttachment() throws -> (
        attachment: AIChatAttachment,
        data: Data,
        cleanup: () -> Void
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-vision-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let imageURL = directory.appendingPathComponent("sample.png")
        try imageData.write(to: imageURL)
        let attachment = AIChatAttachment(
            kind: .image,
            title: "sample.png",
            mimeType: "image/png",
            localPath: imageURL.path,
            byteCount: Int64(imageData.count)
        )

        return (attachment, imageData, {
            try? FileManager.default.removeItem(at: directory)
        })
    }

    private func makeTemporaryAPIKey() throws -> (
        keychain: KeychainSecretStore,
        reference: KeychainSecretReference,
        cleanup: () -> Void
    ) {
        let keychain = KeychainSecretStore()
        let account = "flannel-tests-\(UUID().uuidString)"
        let reference = try keychain.save("test-key", account: account)
        return (keychain, reference, {
            try? keychain.delete(reference)
        })
    }
}

private final class ChatStreamingURLProtocolStub: URLProtocol, @unchecked Sendable {
    static var statusCode = 200
    static var responseBody = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: Self.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !Self.responseBody.isEmpty {
            client?.urlProtocol(self, didLoad: Self.responseBody)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
