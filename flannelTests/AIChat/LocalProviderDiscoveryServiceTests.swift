//
//  LocalProviderDiscoveryServiceTests.swift
//  flannelTests
//

import Foundation
import Testing
@testable import flannel

struct LocalProviderDiscoveryServiceTests {
    @MainActor
    @Test("Default local discovery targets come from the known provider catalog")
    func defaultDiscoveryTargetsComeFromCatalog() async throws {
        let transport = LocalDiscoveryTransportRecorder(
            responses: [
                "http://localhost:11434/api/tags": .init(statusCode: 200, body: #"{"models":[]}"#),
                "http://localhost:11434/api/ps": .init(statusCode: 200, body: #"{"models":[]}"#),
                "http://localhost:1234/api/v1/models": .init(statusCode: 200, body: #"{"models":[]}"#)
            ]
        )
        let service = LocalProviderDiscoveryService(
            transport: { request in try await transport.send(request) }
        )

        let results = await service.discover()
        let requests = await transport.requests()

        #expect(results.map(\.providerKind) == [.ollama, .lmStudio])
        #expect(requests.map(\.url) == [
            "http://localhost:11434/api/tags",
            "http://localhost:11434/api/ps",
            "http://localhost:1234/api/v1/models"
        ])
    }

    @MainActor
    @Test("Ollama discovery uses native tags and ps endpoints")
    func ollamaDiscoveryUsesNativeTagsAndRunningModels() async throws {
        let transport = LocalDiscoveryTransportRecorder(
            responses: [
                "http://localhost:11434/api/tags": .init(
                    statusCode: 200,
                    body: """
                    {
                      "models": [
                        {
                          "name": "llama3.1",
                          "model": "llama3.1:latest",
                          "modified_at": "2026-06-29T12:00:00Z",
                          "size": 4661224676,
                          "details": {
                            "format": "gguf",
                            "family": "llama",
                            "parameter_size": "8B",
                            "quantization_level": "Q4_K_M"
                          }
                        }
                      ]
                    }
                    """
                ),
                "http://localhost:11434/api/ps": .init(
                    statusCode: 200,
                    body: """
                    {
                      "models": [
                        {
                          "name": "llama3.1:latest",
                          "model": "llama3.1:latest",
                          "size": 4661224676,
                          "expires_at": "2026-06-29T12:05:00Z",
                          "size_vram": 2147483648,
                          "context_length": 16384
                        }
                      ]
                    }
                    """
                ),
                "http://localhost:11434/api/show": .init(
                    statusCode: 200,
                    body: """
                    {
                      "modified_at": "2026-06-29T12:01:00Z",
                      "capabilities": ["completion", "vision", "tools", "thinking"],
                      "details": {
                        "format": "gguf",
                        "family": "llama",
                        "parameter_size": "8B",
                        "quantization_level": "Q4_K_M"
                      },
                      "model_info": {
                        "llama.context_length": 131072
                      }
                    }
                    """
                )
            ]
        )
        let service = LocalProviderDiscoveryService(
            timeout: 9,
            transport: { request in try await transport.send(request) }
        )

        let results = await service.discover(
            targets: [
                (.ollama, " http://localhost:11434/ "),
                (.ollama, "http://localhost:11434")
            ]
        )
        let result = try #require(results.first)
        let model = try #require(result.models.first)
        let requests = await transport.requests()

        #expect(results.count == 1)
        #expect(result.providerKind == .ollama)
        #expect(result.endpoint == "http://localhost:11434")
        #expect(result.status == .ready)
        #expect(model.name == "llama3.1:latest")
        #expect(model.contextWindowTokens == 16384)
        #expect(model.loadedInstanceCount == 1)
        #expect(model.sizeVRAMBytes == 2_147_483_648)
        #expect(model.capabilities.contains(.chat))
        #expect(model.capabilities.contains(.toolCalling))
        #expect(model.capabilities.contains(.vision))
        #expect(model.capabilities.contains(.reasoning))
        #expect(model.capabilities.contains(.embeddings) == false)
        #expect(requests.map(\.url) == [
            "http://localhost:11434/api/tags",
            "http://localhost:11434/api/ps",
            "http://localhost:11434/api/show"
        ])
        #expect(requests.last?.method == "POST")
        #expect(requests.last?.contentType == "application/json")
        #expect(requests.last?.body?.contains(#""model":"llama3.1:latest""#) == true)
        #expect(requests.last?.body?.contains(#""verbose":false"#) == true)
        #expect(requests.allSatisfy { $0.timeout == 9 })
        #expect(requests.allSatisfy { $0.acceptHeader == "application/json" })
    }

    @MainActor
    @Test("Ollama discovery keeps chat and embedding models distinct")
    func ollamaDiscoveryKeepsChatAndEmbeddingModelsDistinct() throws {
        let data = Data(
            """
            {
              "models": [
                {
                  "name": "nomic-embed-text",
                  "model": "nomic-embed-text:latest",
                  "details": {
                    "family": "bert",
                    "families": ["bert"],
                    "parameter_size": "137M"
                  }
                },
                {
                  "name": "llama3.1",
                  "model": "llama3.1:latest",
                  "details": {
                    "family": "llama",
                    "parameter_size": "8B"
                  }
                }
              ]
            }
            """.utf8
        )

        let models = try LocalProviderDiscoveryService.makeOllamaDescriptors(
            from: data,
            endpoint: "http://localhost:11434"
        )
        let chat = try #require(models.first)
        let embedding = try #require(models.last)

        #expect(models.map(\.name) == ["llama3.1:latest", "nomic-embed-text:latest"])
        #expect(chat.capabilities.contains(.chat))
        #expect(chat.capabilities.contains(.streaming))
        #expect(chat.capabilities.contains(.toolCalling))
        #expect(chat.capabilities.contains(.embeddings) == false)
        #expect(embedding.capabilities == [.embeddings])
    }

    @MainActor
    @Test("Ollama discovery enriches unloaded models from show metadata")
    func ollamaDiscoveryEnrichesUnloadedModelsFromShowMetadata() throws {
        let tags = Data(
            """
            {
              "models": [
                {
                  "name": "llava",
                  "model": "llava:latest",
                  "details": {
                    "family": "llama",
                    "parameter_size": "7B",
                    "quantization_level": "Q4_0"
                  }
                }
              ]
            }
            """.utf8
        )
        let show = Data(
            """
            {
              "modified_at": "2026-06-29T12:01:00Z",
              "capabilities": ["completion", "vision"],
              "details": {
                "format": "gguf",
                "family": "llava",
                "parameter_size": "7B",
                "quantization_level": "Q4_K_M"
              },
              "model_info": {
                "llava.context_length": 32768
              }
            }
            """.utf8
        )

        let models = try LocalProviderDiscoveryService.makeOllamaDescriptors(
            from: tags,
            modelDetailsData: ["llava:latest": show],
            endpoint: "http://localhost:11434"
        )
        let model = try #require(models.first)

        #expect(model.name == "llava:latest")
        #expect(model.family == "llava")
        #expect(model.format == "gguf")
        #expect(model.quantization == "Q4_K_M")
        #expect(model.contextWindowTokens == 32768)
        #expect(model.loadedInstanceCount == 0)
        #expect(model.modifiedAt != nil)
        #expect(model.capabilities.contains(.chat))
        #expect(model.capabilities.contains(.streaming))
        #expect(model.capabilities.contains(.vision))
        #expect(model.capabilities.contains(.toolCalling) == false)
        #expect(model.capabilities.contains(.embeddings) == false)
    }

    @MainActor
    @Test("Ollama discovery keeps model list when running metadata is unavailable")
    func ollamaDiscoveryKeepsModelListWhenRunningMetadataIsUnavailable() async throws {
        let transport = LocalDiscoveryTransportRecorder(
            responses: [
                "http://localhost:11434/api/tags": .init(
                    statusCode: 200,
                    body: """
                    {
                      "models": [
                        {
                          "name": "llama3.1",
                          "model": "llama3.1:latest",
                          "details": {
                            "family": "llama"
                          }
                        }
                      ]
                    }
                    """
                ),
                "http://localhost:11434/api/ps": .init(
                    statusCode: 500,
                    body: #"{"error":"ps unavailable"}"#
                ),
                "http://localhost:11434/api/show": .init(
                    statusCode: 200,
                    body: #"{"capabilities":["completion"]}"#
                )
            ]
        )
        let service = LocalProviderDiscoveryService(
            transport: { request in try await transport.send(request) }
        )

        let results = await service.discover(targets: [(.ollama, "http://localhost:11434")])
        let result = try #require(results.first)
        let model = try #require(result.models.first)

        #expect(result.status == .ready)
        #expect(model.name == "llama3.1:latest")
        #expect(model.loadedInstanceCount == 0)
        #expect(result.errorMessage == "Ollama running-model metadata unavailable: The provider returned HTTP 500: ps unavailable")
    }

    @MainActor
    @Test("LM Studio fallback preserves rich model metadata from OpenAI-compatible model list")
    func lmStudioFallsBackToOpenAICompatibleModelList() async throws {
        let transport = LocalDiscoveryTransportRecorder(
            responses: [
                "http://localhost:1234/api/v1/models": .init(
                    statusCode: 404,
                    body: #"{"error":"not found"}"#
                ),
                "http://localhost:1234/v1/models": .init(
                    statusCode: 200,
                    body: """
                    {
                      "object": "list",
                      "data": [
                        {
                          "id": "google/gemma-3-27b-it",
                          "object": "model",
                          "owned_by": "google",
                          "publisher": "Google",
                          "display_name": "Gemma 3 27B Instruct",
                          "architecture": "gemma3",
                          "quantization": {
                            "name": "Q4_K_M"
                          },
                          "size_bytes": 18038862643,
                          "params_string": "27B",
                          "loaded_instances": [
                            {
                              "id": "loaded-gemma",
                              "config": {
                                "context_length": 32768
                              }
                            }
                          ],
                          "max_context_length": 131072,
                          "format": "gguf",
                          "capabilities": {
                            "vision": true,
                            "trained_for_tool_use": true,
                            "reasoning": {
                              "allowed_options": ["low", "medium"],
                              "default": "medium"
                            }
                          },
                          "selected_variant": "4bit"
                        }
                      ]
                    }
                    """
                )
            ]
        )
        let service = LocalProviderDiscoveryService(
            transport: { request in try await transport.send(request) }
        )

        let results = await service.discover(targets: [(.lmStudio, " http://localhost:1234/v1/ ")])
        let result = try #require(results.first)
        let model = try #require(result.models.first)
        let requests = await transport.requests()

        #expect(result.providerKind == .lmStudio)
        #expect(result.endpoint == "http://localhost:1234/v1")
        #expect(result.status == .ready)
        #expect(model.name == "google/gemma-3-27b-it")
        #expect(model.displayName == "Gemma 3 27B Instruct")
        #expect(model.endpoint == "http://localhost:1234/v1")
        #expect(model.publisher == "Google")
        #expect(model.family == "gemma3")
        #expect(model.parameterSize == "27B")
        #expect(model.quantization == "Q4_K_M")
        #expect(model.format == "gguf")
        #expect(model.contextWindowTokens == 32768)
        #expect(model.loadedInstanceCount == 1)
        #expect(model.loadedInstanceIDs == ["loaded-gemma"])
        #expect(model.sizeBytes == 18_038_862_643)
        #expect(model.selectedVariant == "4bit")
        #expect(model.capabilities.contains(.chat))
        #expect(model.capabilities.contains(.streaming))
        #expect(model.capabilities.contains(.anthropicCompatible))
        #expect(model.capabilities.contains(.openAICompatible))
        #expect(model.capabilities.contains(.toolCalling))
        #expect(model.capabilities.contains(.vision))
        #expect(model.capabilities.contains(.reasoning))
        #expect(model.capabilities.contains(.embeddings) == false)
        #expect(requests.map(\.url) == [
            "http://localhost:1234/api/v1/models",
            "http://localhost:1234/v1/models"
        ])
    }

    @MainActor
    @Test("LM Studio native discovery accepts api v1 models endpoints")
    func lmStudioNativeDiscoveryAcceptsAPIV1ModelsEndpoint() async throws {
        let transport = LocalDiscoveryTransportRecorder(
            responses: [
                "http://localhost:1234/api/v1/models": .init(
                    statusCode: 200,
                    body: """
                    {
                      "models": [
                        {
                          "type": "llm",
                          "publisher": "Qwen",
                          "key": "qwen/qwen3-14b",
                          "display_name": "Qwen 3 14B"
                        }
                      ]
                    }
                    """
                )
            ]
        )
        let service = LocalProviderDiscoveryService(
            transport: { request in try await transport.send(request) }
        )

        let results = await service.discover(targets: [(.lmStudio, "http://localhost:1234/api/v1/models")])
        let result = try #require(results.first)
        let requests = await transport.requests()

        #expect(result.status == .ready)
        #expect(result.models.first?.name == "qwen/qwen3-14b")
        #expect(requests.map(\.url) == ["http://localhost:1234/api/v1/models"])
    }

    @MainActor
    @Test("LM Studio native discovery keeps chat and embedding models distinct")
    func lmStudioNativeDiscoveryKeepsChatAndEmbeddingModelsDistinct() throws {
        let data = Data(
            """
            {
              "models": [
                {
                  "type": "embedding",
                  "publisher": "Nomic",
                  "key": "text-embedding-nomic-embed-text-v1.5",
                  "display_name": "Nomic Embed Text v1.5",
                  "architecture": "nomic-bert"
                },
                {
                  "type": "llm",
                  "publisher": "Qwen",
                  "key": "qwen/qwen3-14b",
                  "display_name": "Qwen 3 14B",
                  "architecture": "qwen3",
                  "loaded_instances": [
                    {
                      "id": "loaded-qwen",
                      "config": {
                        "context_length": 65536
                      }
                    },
                    {
                      "id": "loaded-qwen-second"
                    }
                  ],
                  "capabilities": {
                    "trained_for_tool_use": true
                  }
                }
              ]
            }
            """.utf8
        )

        let models = try LocalProviderDiscoveryService.makeLMStudioDescriptors(
            from: data,
            endpoint: "http://localhost:1234"
        )
        let chat = try #require(models.first)
        let embedding = try #require(models.last)

        #expect(models.map(\.name) == ["qwen/qwen3-14b", "text-embedding-nomic-embed-text-v1.5"])
        #expect(chat.contextWindowTokens == 65536)
        #expect(chat.loadedInstanceCount == 2)
        #expect(chat.loadedInstanceIDs == ["loaded-qwen", "loaded-qwen-second"])
        #expect(chat.capabilities.contains(.chat))
        #expect(chat.capabilities.contains(.streaming))
        #expect(chat.capabilities.contains(.toolCalling))
        #expect(chat.capabilities.contains(.openAICompatible))
        #expect(chat.capabilities.contains(.anthropicCompatible))
        #expect(chat.capabilities.contains(.embeddings) == false)
        #expect(embedding.capabilities == [.embeddings, .openAICompatible])
    }

    @MainActor
    @Test("LM Studio discovery reports native and fallback failures")
    func lmStudioDiscoveryReportsNativeAndFallbackFailures() async throws {
        let transport = LocalDiscoveryTransportRecorder(
            responses: [
                "http://localhost:1234/api/v1/models": .init(
                    statusCode: 404,
                    body: #"{"error":"native catalog unavailable"}"#
                ),
                "http://localhost:1234/v1/models": .init(
                    statusCode: 503,
                    body: #"{"error":{"message":"fallback server warming up"}}"#
                )
            ]
        )
        let service = LocalProviderDiscoveryService(
            transport: { request in try await transport.send(request) }
        )

        let results = await service.discover(targets: [(.lmStudio, "http://localhost:1234")])
        let result = try #require(results.first)

        #expect(result.status == .needsAttention)
        #expect(result.models.isEmpty)
        #expect(result.errorMessage == "LM Studio native discovery failed: The provider returned HTTP 404: native catalog unavailable OpenAI-compatible fallback failed: The provider returned HTTP 503: fallback server warming up")
    }

    @MainActor
    @Test("Local discovery reports provider health status codes")
    func discoveryReportsProviderHealthStatusCodes() async throws {
        let transport = LocalDiscoveryTransportRecorder(
            responses: [
                "http://localhost:11434/api/tags": .init(
                    statusCode: 503,
                    body: #"{"error":"starting"}"#
                )
            ]
        )
        let service = LocalProviderDiscoveryService(
            transport: { request in try await transport.send(request) }
        )

        let results = await service.discover(targets: [(.ollama, "http://localhost:11434")])
        let result = try #require(results.first)
        let requests = await transport.requests()

        #expect(result.status == .needsAttention)
        #expect(result.models.isEmpty)
        #expect(result.errorMessage == "The provider returned HTTP 503: starting")
        #expect(requests.map(\.url) == ["http://localhost:11434/api/tags"])
    }
}

private actor LocalDiscoveryTransportRecorder {
    struct Response: Sendable {
        var statusCode: Int
        var body: String
    }

    struct RecordedRequest: Equatable, Sendable {
        var url: String
        var method: String?
        var timeout: TimeInterval
        var acceptHeader: String?
        var contentType: String?
        var body: String?
    }

    private let responses: [String: Response]
    private var recordedRequests: [RecordedRequest] = []

    init(responses: [String: Response]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse?) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        let urlString = url.absoluteString
        recordedRequests.append(
            RecordedRequest(
                url: urlString,
                method: request.httpMethod,
                timeout: request.timeoutInterval,
                acceptHeader: request.value(forHTTPHeaderField: "Accept"),
                contentType: request.value(forHTTPHeaderField: "Content-Type"),
                body: request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            )
        )

        guard let response = responses[urlString],
              let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
              ) else {
            throw URLError(.unsupportedURL)
        }

        return (Data(response.body.utf8), httpResponse)
    }

    func requests() -> [RecordedRequest] {
        recordedRequests
    }
}
