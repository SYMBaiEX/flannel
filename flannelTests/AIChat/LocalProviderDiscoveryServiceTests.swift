//
//  LocalProviderDiscoveryServiceTests.swift
//  flannelTests
//

import Foundation
import Testing
@testable import flannel

struct LocalProviderDiscoveryServiceTests {
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
        #expect(requests.map(\.url) == [
            "http://localhost:11434/api/tags",
            "http://localhost:11434/api/ps"
        ])
        #expect(requests.allSatisfy { $0.timeout == 9 })
        #expect(requests.allSatisfy { $0.acceptHeader == "application/json" })
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
        #expect(model.sizeBytes == 18_038_862_643)
        #expect(model.selectedVariant == "4bit")
        #expect(model.capabilities.contains(.chat))
        #expect(model.capabilities.contains(.streaming))
        #expect(model.capabilities.contains(.anthropicCompatible))
        #expect(model.capabilities.contains(.openAICompatible))
        #expect(model.capabilities.contains(.toolCalling))
        #expect(model.capabilities.contains(.vision))
        #expect(model.capabilities.contains(.reasoning))
        #expect(requests.map(\.url) == [
            "http://localhost:1234/api/v1/models",
            "http://localhost:1234/v1/models"
        ])
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
        #expect(result.errorMessage == "The provider returned HTTP 503.")
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
        var timeout: TimeInterval
        var acceptHeader: String?
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
                timeout: request.timeoutInterval,
                acceptHeader: request.value(forHTTPHeaderField: "Accept")
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
