//
//  LocalEmbeddingService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

nonisolated struct LocalEmbeddingRequest: Sendable {
    var provider: ProviderConfiguration
    var modelIdentifier: String
    var inputs: [String]

    init(
        provider: ProviderConfiguration,
        modelIdentifier: String? = nil,
        inputs: [String]
    ) {
        self.provider = provider
        self.modelIdentifier = modelIdentifier ?? provider.modelIdentifier
        self.inputs = inputs
    }
}

nonisolated struct LocalEmbeddingResult: Sendable, Hashable {
    var modelIdentifier: String
    var vectors: [[Double]]

    var vectorDimension: Int? {
        vectors.first?.count
    }
}

nonisolated struct LocalEmbeddingService: Sendable {
    static let defaultLocalVectorDimension = 384
    static let deterministicModelIdentifier = "flannel-local-384"

    var session: URLSession
    var keychain: KeychainSecretStore

    init(
        session: URLSession = .shared,
        keychain: KeychainSecretStore = KeychainSecretStore()
    ) {
        self.session = session
        self.keychain = keychain
    }

    func makeURLRequest(for request: LocalEmbeddingRequest) throws -> URLRequest {
        let model = request.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw LocalEmbeddingError.missingModel
        }
        guard request.inputs.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw LocalEmbeddingError.emptyInput
        }

        switch request.provider.kind {
        case .ollama:
            return try makeOllamaRequest(provider: request.provider, model: model, inputs: request.inputs)

        case .lmStudio, .customOpenAICompatible, .openAI, .groq, .openRouter:
            return try makeOpenAICompatibleRequest(provider: request.provider, model: model, inputs: request.inputs)

        case .anthropic, .chatGPTCLI, .claudeCodeCLI, .gemini, .xAI, .mistral, .perplexity, .vercelAISDKBridge:
            throw LocalEmbeddingError.unsupportedProvider(request.provider.displayName)
        }
    }

    func embed(_ request: LocalEmbeddingRequest) async throws -> LocalEmbeddingResult {
        let urlRequest = try makeURLRequest(for: request)
        let (data, response) = try await session.data(for: urlRequest)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let body = String(data: data.prefix(512), encoding: .utf8) ?? ""
            throw LocalEmbeddingError.httpStatus(httpResponse.statusCode, body)
        }

        let result = try parse(
            data: data,
            provider: request.provider,
            modelIdentifier: request.modelIdentifier
        )
        guard result.vectors.count == request.inputs.count else {
            throw LocalEmbeddingError.vectorCountMismatch(
                expected: request.inputs.count,
                actual: result.vectors.count
            )
        }
        return result
    }

    func parse(data: Data, provider: ProviderConfiguration, modelIdentifier: String) throws -> LocalEmbeddingResult {
        switch provider.kind {
        case .ollama:
            let payload = try JSONDecoder().decode(OllamaEmbeddingResponse.self, from: data)
            return LocalEmbeddingResult(
                modelIdentifier: payload.model ?? modelIdentifier,
                vectors: payload.embeddings
            )

        case .lmStudio, .customOpenAICompatible, .openAI, .groq, .openRouter:
            let payload = try JSONDecoder().decode(OpenAICompatibleEmbeddingResponse.self, from: data)
            let vectors = payload.data.sorted { $0.index < $1.index }.map(\.embedding)
            return LocalEmbeddingResult(modelIdentifier: modelIdentifier, vectors: vectors)

        case .anthropic, .chatGPTCLI, .claudeCodeCLI, .gemini, .xAI, .mistral, .perplexity, .vercelAISDKBridge:
            throw LocalEmbeddingError.unsupportedProvider(provider.displayName)
        }
    }

    func deterministicLocalVector(
        for text: String,
        dimensions: Int = Self.defaultLocalVectorDimension
    ) -> [Double] {
        let dimensionCount = max(8, dimensions)
        var vector = Array(repeating: 0.0, count: dimensionCount)
        let tokens = tokenize(text)

        for token in tokens {
            let bucket = stableHash(token) % dimensionCount
            vector[bucket] += 1.0
        }

        let magnitude = sqrt(vector.reduce(0.0) { $0 + ($1 * $1) })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    private func makeOllamaRequest(
        provider: ProviderConfiguration,
        model: String,
        inputs: [String]
    ) throws -> URLRequest {
        let url = try endpoint(provider.endpoint, appending: ["api", "embed"])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaEmbeddingRequestPayload(model: model, input: inputs)
        )
        return request
    }

    private func makeOpenAICompatibleRequest(
        provider: ProviderConfiguration,
        model: String,
        inputs: [String]
    ) throws -> URLRequest {
        let url = try endpoint(provider.endpoint, appending: ["embeddings"], ensuringVersionPath: "v1")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if provider.privacyScope == .externalAPI || provider.accessMode == .apiKey {
            guard let secretReference = ProviderSetupService.shared.trustedSecretReference(for: provider) else {
                throw LocalEmbeddingError.missingKeychainReference(provider.displayName)
            }
            let apiKey = try keychain.read(secretReference)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(
            OpenAICompatibleEmbeddingRequestPayload(model: model, input: inputs)
        )
        return request
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
            throw LocalEmbeddingError.invalidEndpoint
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
            throw LocalEmbeddingError.invalidEndpoint
        }
        return url
    }

    private func tokenize(_ text: String) -> [String] {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var tokens: [String] = []
        var current = ""

        for scalar in normalized.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if current.isEmpty == false {
                tokens.append(current.lowercased())
                current.removeAll(keepingCapacity: true)
            }
        }

        if current.isEmpty == false {
            tokens.append(current.lowercased())
        }

        return tokens
    }

    private func stableHash(_ value: String) -> Int {
        var hash = UInt64(14_695_981_039_346_656_037)
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return Int(hash % UInt64(Int.max))
    }
}

nonisolated enum LocalEmbeddingError: LocalizedError, Equatable {
    case invalidEndpoint
    case missingModel
    case emptyInput
    case missingKeychainReference(String)
    case unsupportedProvider(String)
    case httpStatus(Int, String)
    case vectorCountMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The embedding provider endpoint is not a valid URL."
        case .missingModel:
            "Choose an embedding model before indexing this source."
        case .emptyInput:
            "The embedding request did not include any text."
        case .missingKeychainReference(let provider):
            "\(provider) needs a Keychain-backed API key before Flannel can request embeddings."
        case .unsupportedProvider(let provider):
            "\(provider) does not expose an embedding transport in Flannel yet."
        case .httpStatus(let statusCode, let body):
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                "The embedding provider returned HTTP \(statusCode)."
            } else {
                "The embedding provider returned HTTP \(statusCode): \(body)"
            }
        case .vectorCountMismatch(let expected, let actual):
            "The embedding provider returned \(actual) vectors for \(expected) chunks."
        }
    }
}

nonisolated private struct OllamaEmbeddingRequestPayload: Encodable {
    var model: String
    var input: [String]
}

nonisolated private struct OpenAICompatibleEmbeddingRequestPayload: Encodable {
    var model: String
    var input: [String]
}

nonisolated private struct OllamaEmbeddingResponse: Decodable {
    var model: String?
    var embeddings: [[Double]]
}

nonisolated private struct OpenAICompatibleEmbeddingResponse: Decodable {
    nonisolated struct DataItem: Decodable {
        var index: Int
        var embedding: [Double]
    }

    var data: [DataItem]
}
