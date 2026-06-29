//
//  LocalEmbeddingServiceTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation
import Testing
@testable import flannel

struct LocalEmbeddingServiceTests {
    @Test("Ollama embeddings use the native embed endpoint")
    func ollamaEmbeddingsUseNativeEndpoint() throws {
        let provider = ProviderConfiguration(
            kind: .ollama,
            displayName: "Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "nomic-embed-text"
        )

        let request = try LocalEmbeddingService().makeURLRequest(
            for: LocalEmbeddingRequest(provider: provider, inputs: ["local rag"])
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(request.url?.absoluteString == "http://localhost:11434/api/embed")
        #expect(request.httpMethod == "POST")
        #expect(json["model"] as? String == "nomic-embed-text")
        #expect(json["input"] as? [String] == ["local rag"])
    }

    @Test("LM Studio embeddings use OpenAI-compatible endpoint")
    func lmStudioEmbeddingsUseOpenAICompatibleEndpoint() throws {
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "text-embedding-local"
        )

        let request = try LocalEmbeddingService().makeURLRequest(
            for: LocalEmbeddingRequest(provider: provider, inputs: ["workspace context"])
        )

        #expect(request.url?.absoluteString == "http://localhost:1234/v1/embeddings")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Embedding parsers decode Ollama and OpenAI-compatible vectors")
    func embeddingParsersDecodeProviderVectors() throws {
        let service = LocalEmbeddingService()
        let ollamaProvider = ProviderConfiguration(
            kind: .ollama,
            displayName: "Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "nomic-embed-text"
        )
        let openAICompatibleProvider = ProviderConfiguration(
            kind: .lmStudio,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "text-embedding-local"
        )

        let ollama = try service.parse(
            data: Data(#"{"model":"nomic-embed-text","embeddings":[[0.1,0.2,0.3]]}"#.utf8),
            provider: ollamaProvider,
            modelIdentifier: "fallback"
        )
        let compatible = try service.parse(
            data: Data(#"{"data":[{"object":"embedding","index":1,"embedding":[0.4,0.5]},{"object":"embedding","index":0,"embedding":[0.1,0.2]}]}"#.utf8),
            provider: openAICompatibleProvider,
            modelIdentifier: "text-embedding-local"
        )

        #expect(ollama.modelIdentifier == "nomic-embed-text")
        #expect(ollama.vectorDimension == 3)
        #expect(compatible.vectors == [[0.1, 0.2], [0.4, 0.5]])
    }

    @MainActor
    @Test("Embedding execution rejects mismatched provider vector counts")
    func embeddingExecutionRejectsMismatchedProviderVectorCounts() async throws {
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "text-embedding-local"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EmbeddingURLProtocol.self]
        EmbeddingURLProtocol.register(
            url: "http://localhost:1234/v1/embeddings",
            statusCode: 200,
            data: Data(#"{"data":[{"index":0,"embedding":[0.1,0.2]}]}"#.utf8)
        )
        let service = LocalEmbeddingService(session: URLSession(configuration: configuration))

        await #expect(throws: LocalEmbeddingError.vectorCountMismatch(expected: 2, actual: 1)) {
            _ = try await service.embed(
                LocalEmbeddingRequest(
                    provider: provider,
                    inputs: ["first", "second"]
                )
            )
        }
    }

    @MainActor
    @Test("Embedding execution surfaces provider HTTP failures")
    func embeddingExecutionSurfacesProviderHTTPFailures() async throws {
        let provider = ProviderConfiguration(
            kind: .ollama,
            displayName: "Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "nomic-embed-text"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EmbeddingURLProtocol.self]
        EmbeddingURLProtocol.register(
            url: "http://localhost:11434/api/embed",
            statusCode: 404,
            data: Data(#"{"error":"model not found"}"#.utf8)
        )
        let service = LocalEmbeddingService(session: URLSession(configuration: configuration))

        await #expect(throws: LocalEmbeddingError.httpStatus(404, #"{"error":"model not found"}"#)) {
            _ = try await service.embed(
                LocalEmbeddingRequest(
                    provider: provider,
                    inputs: ["local rag"]
                )
            )
        }
    }

    @Test("Deterministic local vectors are normalized and stable")
    func deterministicLocalVectorsAreStable() {
        let service = LocalEmbeddingService()

        let first = service.deterministicLocalVector(for: "Local RAG local citations", dimensions: 32)
        let second = service.deterministicLocalVector(for: "Local RAG local citations", dimensions: 32)
        let magnitude = sqrt(first.reduce(0.0) { $0 + ($1 * $1) })

        #expect(first == second)
        #expect(first.count == 32)
        #expect(abs(magnitude - 1.0) < 0.000001)
    }
}

private final class EmbeddingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: (statusCode: Int, data: Data)] = [:]

    static func register(url: String, statusCode: Int, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        responses[url] = (statusCode, data)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let key = request.url?.absoluteString ?? ""
        Self.lock.lock()
        let registeredResponse = Self.responses[key]
        Self.lock.unlock()
        let statusCode = registeredResponse?.statusCode ?? 404
        let data = registeredResponse?.data ?? Data(#"{"error":"missing fake embedding response"}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://localhost")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
