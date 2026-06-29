//
//  LocalProviderDiscoveryService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

struct LocalProviderDiscoveryService: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse?)

    private var transport: Transport
    var timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 4) {
        self.transport = { request in
            let (data, response) = try await session.data(for: request)
            return (data, response as? HTTPURLResponse)
        }
        self.timeout = timeout
    }

    init(timeout: TimeInterval = 4, transport: @escaping Transport) {
        self.transport = transport
        self.timeout = timeout
    }

    func discover() async -> [LocalProviderDiscoveryResult] {
        await discover(
            targets: [
                (.ollama, "http://localhost:11434"),
                (.lmStudio, "http://localhost:1234")
            ]
        )
    }

    func discover(targets: [(LLMProviderKind, String)]) async -> [LocalProviderDiscoveryResult] {
        var seenTargets = Set<String>()
        var results: [LocalProviderDiscoveryResult] = []

        for (kind, endpoint) in targets {
            let normalizedEndpoint = Self.normalizedEndpoint(endpoint)
            guard !normalizedEndpoint.isEmpty else { continue }
            guard seenTargets.insert("\(kind.rawValue):\(normalizedEndpoint.lowercased())").inserted else { continue }

            switch kind {
            case .ollama:
                results.append(await discoverOllama(endpoint: normalizedEndpoint))
            case .lmStudio:
                results.append(await discoverLMStudio(endpoint: normalizedEndpoint))
            case .openAI, .anthropic, .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity,
                 .customOpenAICompatible, .chatGPTCLI, .claudeCodeCLI, .vercelAISDKBridge:
                break
            }
        }

        return results
    }

    func discoverOllama(endpoint: String) async -> LocalProviderDiscoveryResult {
        do {
            let request = try makeRequest(endpoint: endpoint, appending: ["api", "tags"])
            let response: OllamaTagsDiscoveryResponse = try await decode(request)
            let runningModels = await discoverRunningOllamaModels(endpoint: endpoint)
            let models = Self.makeOllamaDescriptors(
                response: response,
                runningModels: runningModels,
                endpoint: endpoint
            )
            return .init(providerKind: .ollama, endpoint: endpoint, status: .ready, models: models)
        } catch {
            return .init(
                providerKind: .ollama,
                endpoint: endpoint,
                status: .needsAttention,
                errorMessage: error.localizedDescription
            )
        }
    }

    func discoverLMStudio(endpoint: String) async -> LocalProviderDiscoveryResult {
        do {
            let models = try await discoverLMStudioNative(endpoint: endpoint)
            return .init(providerKind: .lmStudio, endpoint: endpoint, status: .ready, models: models)
        } catch {
            do {
                let models = try await discoverOpenAICompatibleModels(
                    endpoint: endpoint,
                    providerKind: .lmStudio
                )
                return .init(providerKind: .lmStudio, endpoint: endpoint, status: .ready, models: models)
            } catch {
                return .init(
                    providerKind: .lmStudio,
                    endpoint: endpoint,
                    status: .needsAttention,
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    private func discoverLMStudioNative(endpoint: String) async throws -> [LocalModelDescriptor] {
        let request = try makeRequest(
            endpoint: Self.nativeLMStudioEndpoint(from: endpoint),
            appending: ["api", "v1", "models"]
        )
        let response: LMStudioNativeModelsDiscoveryResponse = try await decode(request)
        return Self.makeLMStudioDescriptors(response: response, endpoint: endpoint)
    }

    private func discoverOpenAICompatibleModels(
        endpoint: String,
        providerKind: LLMProviderKind
    ) async throws -> [LocalModelDescriptor] {
        let response: OpenAICompatibleModelsDiscoveryResponse = try await decode(
            makeOpenAICompatibleModelsRequest(endpoint: endpoint)
        )
        return Self.makeOpenAICompatibleDescriptors(
            response: response,
            endpoint: endpoint,
            providerKind: providerKind
        )
    }

    private func discoverRunningOllamaModels(endpoint: String) async -> [String: OllamaRunningModelDiscovery] {
        do {
            let request = try makeRequest(endpoint: endpoint, appending: ["api", "ps"])
            let response: OllamaRunningModelsDiscoveryResponse = try await decode(request)
            return Self.runningOllamaModelLookup(response.models)
        } catch {
            return [:]
        }
    }

    static func makeOllamaDescriptors(
        from tagsData: Data,
        runningData: Data? = nil,
        endpoint: String
    ) throws -> [LocalModelDescriptor] {
        let tagsResponse = try JSONDecoder.discovery.decode(OllamaTagsDiscoveryResponse.self, from: tagsData)
        let runningModels = try runningData.map {
            runningOllamaModelLookup(
                try JSONDecoder.discovery.decode(OllamaRunningModelsDiscoveryResponse.self, from: $0).models
            )
        } ?? [:]
        return makeOllamaDescriptors(response: tagsResponse, runningModels: runningModels, endpoint: endpoint)
    }

    static func makeLMStudioDescriptors(from data: Data, endpoint: String) throws -> [LocalModelDescriptor] {
        let response = try JSONDecoder.discovery.decode(LMStudioNativeModelsDiscoveryResponse.self, from: data)
        return makeLMStudioDescriptors(response: response, endpoint: endpoint)
    }

    static func makeOpenAICompatibleDescriptors(
        from data: Data,
        endpoint: String,
        providerKind: LLMProviderKind
    ) throws -> [LocalModelDescriptor] {
        let response = try JSONDecoder.discovery.decode(OpenAICompatibleModelsDiscoveryResponse.self, from: data)
        return makeOpenAICompatibleDescriptors(
            response: response,
            endpoint: endpoint,
            providerKind: providerKind
        )
    }

    private static func makeOllamaDescriptors(
        response: OllamaTagsDiscoveryResponse,
        runningModels: [String: OllamaRunningModelDiscovery],
        endpoint: String
    ) -> [LocalModelDescriptor] {
        response.models.map { model in
            let runningModel = runningModel(for: model, in: runningModels)
            return LocalModelDescriptor(
                name: model.model ?? model.name,
                displayName: model.name,
                providerKind: .ollama,
                endpoint: endpoint,
                family: model.details?.family,
                parameterSize: model.details?.parameterSize,
                quantization: model.details?.quantizationLevel,
                format: model.details?.format,
                contextWindowTokens: runningModel?.contextLength,
                loadedInstanceCount: runningModel == nil ? 0 : 1,
                sizeBytes: model.size,
                sizeVRAMBytes: runningModel?.sizeVRAM,
                modifiedAt: model.modifiedAt,
                expiresAt: runningModel?.expiresAt,
                capabilities: ollamaCapabilities(for: model)
            )
        }
    }

    private static func makeLMStudioDescriptors(
        response: LMStudioNativeModelsDiscoveryResponse,
        endpoint: String
    ) -> [LocalModelDescriptor] {
        response.models.map { model in
            LocalModelDescriptor(
                name: model.key,
                displayName: model.displayName ?? model.key,
                publisher: model.publisher,
                providerKind: .lmStudio,
                endpoint: endpoint,
                family: model.architecture,
                parameterSize: model.paramsString,
                quantization: model.quantization?.name,
                format: model.format,
                contextWindowTokens: model.loadedInstances?
                    .compactMap { $0.config?.contextLength }
                    .first
                    ?? model.maxContextLength,
                loadedInstanceCount: model.loadedInstances?.count ?? 0,
                sizeBytes: model.sizeBytes,
                selectedVariant: model.selectedVariant,
                capabilities: lmStudioCapabilities(for: model)
            )
        }
    }

    private static func makeOpenAICompatibleDescriptors(
        response: OpenAICompatibleModelsDiscoveryResponse,
        endpoint: String,
        providerKind: LLMProviderKind
    ) -> [LocalModelDescriptor] {
        response.data.map { model in
            LocalModelDescriptor(
                name: model.id,
                displayName: model.id,
                publisher: model.ownedBy,
                providerKind: providerKind,
                endpoint: endpoint,
                capabilities: openAICompatibleCapabilities(for: model.id)
            )
        }
    }

    private static func runningOllamaModelLookup(
        _ models: [OllamaRunningModelDiscovery]
    ) -> [String: OllamaRunningModelDiscovery] {
        models.reduce(into: [:]) { partialResult, model in
            partialResult[normalizedModelKey(model.name)] = model
            partialResult[normalizedModelKey(model.model)] = model
        }
    }

    private static func runningModel(
        for model: OllamaTagsDiscoveryResponse.OllamaModel,
        in runningModels: [String: OllamaRunningModelDiscovery]
    ) -> OllamaRunningModelDiscovery? {
        runningModels[normalizedModelKey(model.model ?? model.name)]
            ?? runningModels[normalizedModelKey(model.name)]
    }

    private static func normalizedModelKey(_ rawValue: String?) -> String {
        (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func ollamaCapabilities(for model: OllamaTagsDiscoveryResponse.OllamaModel) -> [ModelCapability] {
        let searchableName = [model.name, model.model, model.details?.family]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if searchableName.contains("embed") || searchableName.contains("embedding") || searchableName.contains("nomic") {
            return [.embeddings]
        }
        return [.chat, .streaming, .toolCalling, .embeddings]
    }

    private static func lmStudioCapabilities(for model: LMStudioNativeModelsDiscoveryResponse.Model) -> [ModelCapability] {
        guard model.modelType != "embedding" else {
            return [.embeddings]
        }

        var capabilities: Set<ModelCapability> = [.chat, .streaming, .embeddings, .openAICompatible, .anthropicCompatible]
        if model.capabilities?.trainedForToolUse == true {
            capabilities.insert(.toolCalling)
        }
        if model.capabilities?.vision == true {
            capabilities.insert(.vision)
        }
        if model.capabilities?.reasoning != nil {
            capabilities.insert(.reasoning)
        }
        return Array(capabilities).sorted { $0.rawValue < $1.rawValue }
    }

    private static func openAICompatibleCapabilities(for modelIdentifier: String) -> [ModelCapability] {
        if isEmbeddingModelIdentifier(modelIdentifier) {
            return [.embeddings, .openAICompatible]
        }

        return [.chat, .openAICompatible, .streaming]
    }

    private static func isEmbeddingModelIdentifier(_ modelIdentifier: String) -> Bool {
        let normalizedIdentifier = modelIdentifier.lowercased()
        let embeddingHints = [
            "embedding",
            "text-embedding",
            "nomic-embed",
            "bge-",
            "/bge",
            "gte-",
            "/gte",
            "e5-",
            "/e5",
            "embed"
        ]
        return embeddingHints.contains { normalizedIdentifier.contains($0) }
    }

    private func makeRequest(endpoint: String, appending pathComponents: [String]) throws -> URLRequest {
        let url = try Self.endpointURL(endpoint, appending: pathComponents)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeOpenAICompatibleModelsRequest(endpoint: String) throws -> URLRequest {
        let pathComponents = Self.endpointPathComponents(endpoint)
        let normalizedPathComponents = pathComponents.map { $0.lowercased() }
        let appendedPath: [String]

        if normalizedPathComponents.suffix(2) == ["v1", "models"] {
            appendedPath = []
        } else if normalizedPathComponents.last == "v1" {
            appendedPath = ["models"]
        } else {
            appendedPath = ["v1", "models"]
        }

        return try makeRequest(endpoint: endpoint, appending: appendedPath)
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport(request)
        guard let httpResponse = response else {
            throw DiscoveryError.badResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DiscoveryError.badStatus(httpResponse.statusCode)
        }

        return try JSONDecoder.discovery.decode(T.self, from: data)
    }

    private static func normalizedEndpoint(_ rawValue: String) -> String {
        guard let url = try? endpointURL(rawValue, appending: []) else {
            return rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingTrailingSlashes()
        }

        return url.absoluteString.trimmingTrailingSlashes()
    }

    private static func nativeLMStudioEndpoint(from endpoint: String) -> String {
        guard var components = URLComponents(string: endpoint) else {
            return endpoint
        }

        var pathComponents = components.path
            .split(separator: "/")
            .map(String.init)

        let normalizedPathComponents = pathComponents.map { $0.lowercased() }
        if normalizedPathComponents.suffix(2) == ["v1", "models"] {
            pathComponents.removeLast(2)
        } else if normalizedPathComponents.last == "v1" {
            pathComponents.removeLast()
        }

        components.path = pathComponents.isEmpty ? "" : "/" + pathComponents.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? endpoint
    }

    private static func endpointURL(_ rawValue: String, appending pathComponents: [String]) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil else {
            throw DiscoveryError.invalidEndpoint
        }

        var combinedPath = components.path
            .split(separator: "/")
            .map(String.init)

        combinedPath.append(
            contentsOf: pathComponents
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
                .filter { !$0.isEmpty }
        )

        components.path = combinedPath.isEmpty ? "" : "/" + combinedPath.joined(separator: "/")
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw DiscoveryError.invalidEndpoint
        }
        return url
    }

    private static func endpointPathComponents(_ endpoint: String) -> [String] {
        URLComponents(string: endpoint)?
            .path
            .split(separator: "/")
            .map(String.init) ?? []
    }
}

private enum DiscoveryError: LocalizedError {
    case invalidEndpoint
    case badResponse
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The endpoint URL is invalid."
        case .badResponse:
            "The provider did not return an HTTP response."
        case .badStatus(let statusCode):
            "The provider returned HTTP \(statusCode)."
        }
    }
}

private extension String {
    func trimmingTrailingSlashes() -> String {
        var value = self
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}

private struct OllamaTagsDiscoveryResponse: Decodable {
    var models: [OllamaModel]

    struct OllamaModel: Decodable {
        var name: String
        var model: String?
        var modifiedAt: Date?
        var size: Int64?
        var details: Details?

        enum CodingKeys: String, CodingKey {
            case name
            case model
            case modifiedAt = "modified_at"
            case size
            case details
        }
    }

    struct Details: Decodable {
        var format: String?
        var family: String?
        var parameterSize: String?
        var quantizationLevel: String?

        enum CodingKeys: String, CodingKey {
            case format
            case family
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }
}

private struct OllamaRunningModelsDiscoveryResponse: Decodable {
    var models: [OllamaRunningModelDiscovery]
}

private struct OllamaRunningModelDiscovery: Decodable {
    var name: String
    var model: String?
    var size: Int64?
    var digest: String?
    var details: OllamaTagsDiscoveryResponse.Details?
    var expiresAt: Date?
    var sizeVRAM: Int64?
    var contextLength: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case size
        case digest
        case details
        case expiresAt = "expires_at"
        case sizeVRAM = "size_vram"
        case contextLength = "context_length"
    }
}

private struct LMStudioNativeModelsDiscoveryResponse: Decodable {
    var models: [Model]

    struct Model: Decodable {
        var modelType: String
        var publisher: String?
        var key: String
        var displayName: String?
        var architecture: String?
        var quantization: Quantization?
        var sizeBytes: Int64?
        var paramsString: String?
        var loadedInstances: [LoadedInstance]?
        var maxContextLength: Int?
        var format: String?
        var capabilities: Capabilities?
        var selectedVariant: String?

        enum CodingKeys: String, CodingKey {
            case modelType = "type"
            case publisher
            case key
            case displayName = "display_name"
            case architecture
            case quantization
            case sizeBytes = "size_bytes"
            case paramsString = "params_string"
            case loadedInstances = "loaded_instances"
            case maxContextLength = "max_context_length"
            case format
            case capabilities
            case selectedVariant = "selected_variant"
        }
    }

    struct Quantization: Decodable {
        var name: String?
    }

    struct LoadedInstance: Decodable {
        var id: String?
        var config: LoadedInstanceConfig?
    }

    struct LoadedInstanceConfig: Decodable {
        var contextLength: Int?

        enum CodingKeys: String, CodingKey {
            case contextLength = "context_length"
        }
    }

    struct Capabilities: Decodable {
        var vision: Bool?
        var trainedForToolUse: Bool?
        var reasoning: Reasoning?

        enum CodingKeys: String, CodingKey {
            case vision
            case trainedForToolUse = "trained_for_tool_use"
            case reasoning
        }
    }

    struct Reasoning: Decodable {
        var allowedOptions: [String]?
        var defaultOption: String?

        enum CodingKeys: String, CodingKey {
            case allowedOptions = "allowed_options"
            case defaultOption = "default"
        }
    }
}

private struct OpenAICompatibleModelsDiscoveryResponse: Decodable {
    var data: [Model]

    struct Model: Decodable {
        var id: String
        var ownedBy: String?

        enum CodingKeys: String, CodingKey {
            case id
            case ownedBy = "owned_by"
        }
    }
}

private extension JSONDecoder {
    static var discovery: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: rawValue)
                ?? ISO8601DateFormatter.withInternetDateTime.date(from: rawValue) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(rawValue)"
            )
        }
        return decoder
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let withInternetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
