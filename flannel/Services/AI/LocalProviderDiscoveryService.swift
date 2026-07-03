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
        let targets = AIKnownProviderCatalog.entries.compactMap { entry -> (LLMProviderKind, String)? in
            guard entry.modelDiscoveryStrategy == .localServer,
                  entry.requestBoundary == .localServer,
                  let endpoint = entry.endpoint else {
                return nil
            }
            return (LLMProviderKind(entry.providerKind), endpoint)
        }
        return await discover(targets: targets)
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
            let runningDiscovery: OllamaRunningModelsDiscovery
            if AIKnownProviderCatalog.entry(for: AIProviderKind.ollama)?.supportsRunningModelInventory == true {
                runningDiscovery = await discoverRunningOllamaModels(endpoint: endpoint)
            } else {
                runningDiscovery = .init(models: [:], errorMessage: nil)
            }
            let detailsDiscovery = await discoverOllamaModelDetails(
                endpoint: endpoint,
                models: response.models
            )
            let models = Self.makeOllamaDescriptors(
                response: response,
                runningModels: runningDiscovery.models,
                modelDetails: detailsDiscovery.models,
                endpoint: endpoint
            )
            return .init(
                providerKind: .ollama,
                endpoint: endpoint,
                status: .ready,
                models: models,
                errorMessage: Self.combinedOllamaDiscoveryWarning(
                    runningWarning: runningDiscovery.errorMessage,
                    detailsWarning: detailsDiscovery.errorMessage
                )
            )
        } catch {
            return .init(
                providerKind: .ollama,
                endpoint: endpoint,
                status: .needsAttention,
                errorMessage: Self.discoveryErrorDescription(error)
            )
        }
    }

    func discoverLMStudio(endpoint: String) async -> LocalProviderDiscoveryResult {
        do {
            let models = try await discoverLMStudioNative(endpoint: endpoint)
            return .init(providerKind: .lmStudio, endpoint: endpoint, status: .ready, models: models)
        } catch let nativeError {
            guard AIKnownProviderCatalog.entry(for: AIProviderKind.lmStudio)?.supportsOpenAICompatibleModelDiscovery == true else {
                return .init(
                    providerKind: .lmStudio,
                    endpoint: endpoint,
                    status: .needsAttention,
                    errorMessage: Self.discoveryErrorDescription(nativeError)
                )
            }

            do {
                let models = try await discoverOpenAICompatibleModels(
                    endpoint: endpoint,
                    providerKind: .lmStudio
                )
                return .init(providerKind: .lmStudio, endpoint: endpoint, status: .ready, models: models)
            } catch let fallbackError {
                return .init(
                    providerKind: .lmStudio,
                    endpoint: endpoint,
                    status: .needsAttention,
                    errorMessage: Self.combinedLMStudioDiscoveryError(
                        nativeError: nativeError,
                        fallbackError: fallbackError
                    )
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

    private func discoverRunningOllamaModels(endpoint: String) async -> OllamaRunningModelsDiscovery {
        do {
            let request = try makeRequest(endpoint: endpoint, appending: ["api", "ps"])
            let response: OllamaRunningModelsDiscoveryResponse = try await decode(request)
            return .init(models: Self.runningOllamaModelLookup(response.models))
        } catch {
            return .init(
                models: [:],
                errorMessage: "Ollama running-model metadata unavailable: \(Self.discoveryErrorDescription(error))"
            )
        }
    }

    private func discoverOllamaModelDetails(
        endpoint: String,
        models: [OllamaTagsDiscoveryResponse.OllamaModel]
    ) async -> OllamaModelDetailsDiscovery {
        var lookup: [String: OllamaShowModelDiscoveryResponse] = [:]
        var failedModelNames: [String] = []

        for model in models {
            let modelName = (model.model ?? model.name).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelName.isEmpty else { continue }

            do {
                let request = try makeOllamaShowRequest(endpoint: endpoint, model: modelName)
                let response: OllamaShowModelDiscoveryResponse = try await decode(request)
                lookup[Self.normalizedModelKey(modelName)] = response
                lookup[Self.normalizedModelKey(model.name)] = response
                if let modelIdentifier = model.model {
                    lookup[Self.normalizedModelKey(modelIdentifier)] = response
                }
            } catch {
                failedModelNames.append(modelName)
            }
        }

        return .init(
            models: lookup,
            errorMessage: Self.ollamaModelDetailsWarning(failedModelNames)
        )
    }

    static func makeOllamaDescriptors(
        from tagsData: Data,
        runningData: Data? = nil,
        modelDetailsData: [String: Data] = [:],
        endpoint: String
    ) throws -> [LocalModelDescriptor] {
        let tagsResponse = try JSONDecoder.discovery.decode(OllamaTagsDiscoveryResponse.self, from: tagsData)
        let runningModels = try runningData.map {
            runningOllamaModelLookup(
                try JSONDecoder.discovery.decode(OllamaRunningModelsDiscoveryResponse.self, from: $0).models
            )
        } ?? [:]
        let modelDetails = try modelDetailsData.reduce(into: [String: OllamaShowModelDiscoveryResponse]()) { result, entry in
            result[normalizedModelKey(entry.key)] = try JSONDecoder.discovery.decode(
                OllamaShowModelDiscoveryResponse.self,
                from: entry.value
            )
        }
        return makeOllamaDescriptors(
            response: tagsResponse,
            runningModels: runningModels,
            modelDetails: modelDetails,
            endpoint: endpoint
        )
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
        modelDetails: [String: OllamaShowModelDiscoveryResponse] = [:],
        endpoint: String
    ) -> [LocalModelDescriptor] {
        sortedDescriptors(response.models.map { model in
            let runningModel = runningModel(for: model, in: runningModels)
            let showDetails = modelDetailsFor(model, in: modelDetails)
            return LocalModelDescriptor(
                name: model.model ?? model.name,
                displayName: model.name,
                providerKind: .ollama,
                endpoint: endpoint,
                family: showDetails?.details?.family ?? model.details?.family,
                parameterSize: showDetails?.details?.parameterSize ?? model.details?.parameterSize,
                quantization: showDetails?.details?.quantizationLevel ?? model.details?.quantizationLevel,
                format: showDetails?.details?.format ?? model.details?.format,
                contextWindowTokens: runningModel?.contextLength ?? showDetails?.contextLength,
                loadedInstanceCount: runningModel == nil ? 0 : 1,
                sizeBytes: model.size,
                sizeVRAMBytes: runningModel?.sizeVRAM,
                modifiedAt: showDetails?.modifiedAt ?? model.modifiedAt,
                expiresAt: runningModel?.expiresAt,
                capabilities: ollamaCapabilities(for: model, details: showDetails)
            )
        })
    }

    private static func makeLMStudioDescriptors(
        response: LMStudioNativeModelsDiscoveryResponse,
        endpoint: String
    ) -> [LocalModelDescriptor] {
        sortedDescriptors(response.models.map { model in
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
                loadedInstanceIDs: loadedInstanceIDs(from: model.loadedInstances),
                sizeBytes: model.sizeBytes,
                selectedVariant: model.selectedVariant,
                capabilities: lmStudioCapabilities(for: model)
            )
        })
    }

    private static func makeOpenAICompatibleDescriptors(
        response: OpenAICompatibleModelsDiscoveryResponse,
        endpoint: String,
        providerKind: LLMProviderKind
    ) -> [LocalModelDescriptor] {
        sortedDescriptors(response.data.map { model in
            if providerKind == .lmStudio {
                return makeLMStudioFallbackDescriptor(from: model, endpoint: endpoint)
            }

            return LocalModelDescriptor(
                name: model.id,
                displayName: model.displayName ?? model.id,
                publisher: model.publisher ?? model.ownedBy,
                providerKind: providerKind,
                endpoint: endpoint,
                family: model.architecture,
                parameterSize: model.paramsString,
                quantization: model.quantization?.name,
                format: model.format,
                contextWindowTokens: model.loadedInstances?
                    .compactMap { $0.config?.contextLength }
                    .first
                    ?? model.maxContextLength,
                loadedInstanceCount: model.loadedInstances?.count,
                loadedInstanceIDs: loadedInstanceIDs(from: model.loadedInstances),
                sizeBytes: model.sizeBytes,
                selectedVariant: model.selectedVariant,
                capabilities: openAICompatibleCapabilities(for: model)
            )
        })
    }

    private static func makeLMStudioFallbackDescriptor(
        from model: OpenAICompatibleModelsDiscoveryResponse.Model,
        endpoint: String
    ) -> LocalModelDescriptor {
        LocalModelDescriptor(
            name: model.id,
            displayName: model.displayName ?? model.id,
            publisher: model.publisher ?? model.ownedBy,
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
            loadedInstanceIDs: loadedInstanceIDs(from: model.loadedInstances),
            sizeBytes: model.sizeBytes,
            selectedVariant: model.selectedVariant,
            capabilities: lmStudioFallbackCapabilities(for: model)
        )
    }

    private static func loadedInstanceIDs(
        from loadedInstances: [LMStudioNativeModelsDiscoveryResponse.LoadedInstance]?
    ) -> [String]? {
        let ids = loadedInstances?
            .compactMap { instance -> String? in
                let trimmed = instance.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            } ?? []
        return ids.isEmpty ? nil : ids
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

    private static func modelDetailsFor(
        _ model: OllamaTagsDiscoveryResponse.OllamaModel,
        in details: [String: OllamaShowModelDiscoveryResponse]
    ) -> OllamaShowModelDiscoveryResponse? {
        details[normalizedModelKey(model.model ?? model.name)]
            ?? details[normalizedModelKey(model.name)]
    }

    private static func normalizedModelKey(_ rawValue: String?) -> String {
        (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func ollamaCapabilities(
        for model: OllamaTagsDiscoveryResponse.OllamaModel,
        details: OllamaShowModelDiscoveryResponse? = nil
    ) -> [ModelCapability] {
        if let details,
           let officialCapabilities = details.capabilities,
           !officialCapabilities.isEmpty {
            return ollamaCapabilities(from: officialCapabilities)
        }

        if isEmbeddingModel(
            modelType: nil,
            identifiers: [model.name, model.model, model.details?.family] + (model.details?.families ?? [])
        ) {
            return [.embeddings]
        }
        return [.chat, .streaming, .toolCalling]
    }

    private static func ollamaCapabilities(from rawCapabilities: [String]) -> [ModelCapability] {
        let normalizedCapabilities = Set(
            rawCapabilities.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )

        if !normalizedCapabilities.isDisjoint(with: ["embedding", "embeddings", "embed"]) {
            return [.embeddings]
        }

        var capabilities: Set<ModelCapability> = []
        if !normalizedCapabilities.isDisjoint(with: ["completion", "chat", "generate", "vision"]) {
            capabilities.insert(.chat)
            capabilities.insert(.streaming)
        }
        if normalizedCapabilities.contains("vision") {
            capabilities.insert(.vision)
        }
        if !normalizedCapabilities.isDisjoint(with: ["tools", "tool", "tool_calling", "function_calling"]) {
            capabilities.insert(.toolCalling)
        }
        if !normalizedCapabilities.isDisjoint(with: ["thinking", "reasoning"]) {
            capabilities.insert(.reasoning)
        }

        if capabilities.isEmpty {
            capabilities.formUnion([.chat, .streaming])
        }
        return sortedCapabilities(capabilities)
    }

    private static func lmStudioCapabilities(for model: LMStudioNativeModelsDiscoveryResponse.Model) -> [ModelCapability] {
        guard !isEmbeddingModel(
            modelType: model.modelType,
            identifiers: [model.key, model.displayName, model.architecture]
        ) else {
            return [.embeddings, .openAICompatible]
        }

        var capabilities: Set<ModelCapability> = [.chat, .streaming, .openAICompatible, .anthropicCompatible]
        if model.capabilities?.trainedForToolUse == true {
            capabilities.insert(.toolCalling)
        }
        if model.capabilities?.vision == true {
            capabilities.insert(.vision)
        }
        if model.capabilities?.reasoning != nil {
            capabilities.insert(.reasoning)
        }
        return sortedCapabilities(capabilities)
    }

    private static func openAICompatibleCapabilities(
        for model: OpenAICompatibleModelsDiscoveryResponse.Model
    ) -> [ModelCapability] {
        if isEmbeddingModel(
            modelType: model.modelType,
            identifiers: [model.id, model.displayName, model.architecture, model.publisher, model.ownedBy]
        ) {
            return [.embeddings, .openAICompatible]
        }

        return [.chat, .openAICompatible, .streaming]
    }

    private static func lmStudioFallbackCapabilities(
        for model: OpenAICompatibleModelsDiscoveryResponse.Model
    ) -> [ModelCapability] {
        if isEmbeddingModel(
            modelType: model.modelType,
            identifiers: [model.id, model.displayName, model.architecture, model.publisher, model.ownedBy]
        ) {
            return [.embeddings, .openAICompatible]
        }

        var capabilities: Set<ModelCapability> = [.chat, .streaming, .openAICompatible, .anthropicCompatible]
        if model.capabilities?.trainedForToolUse == true {
            capabilities.insert(.toolCalling)
        }
        if model.capabilities?.vision == true {
            capabilities.insert(.vision)
        }
        if model.capabilities?.reasoning != nil {
            capabilities.insert(.reasoning)
        }
        return sortedCapabilities(capabilities)
    }

    private static func isEmbeddingModel(modelType: String?, identifiers: [String?]) -> Bool {
        if let modelType {
            let normalizedModelType = modelType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedModelType == "embedding"
                || normalizedModelType == "embeddings"
                || normalizedModelType == "text_embedding"
                || normalizedModelType == "text-embedding" {
                return true
            }
        }

        let tokens = Set(
            identifiers
                .compactMap { $0?.lowercased() }
                .flatMap { value in
                    value.split { !$0.isLetter && !$0.isNumber }.map(String.init)
                }
        )

        if !tokens.isDisjoint(with: [
            "embed",
            "embedding",
            "embeddings",
            "bge",
            "gte",
            "e5",
            "minilm",
            "nomic",
            "rerank",
            "reranker",
            "bert"
        ]) {
            return true
        }

        return identifiers
            .compactMap { $0?.lowercased() }
            .contains { value in
                value.contains("sentence-transformers")
                    || value.contains("all-minilm")
                    || value.contains("mxbai-embed")
                    || value.contains("nomic-embed")
                    || value.contains("snowflake-arctic-embed")
                    || value.contains("text-embedding")
            }
    }

    private static func sortedCapabilities(_ capabilities: Set<ModelCapability>) -> [ModelCapability] {
        Array(capabilities).sorted { $0.rawValue < $1.rawValue }
    }

    private static func sortedDescriptors(_ models: [LocalModelDescriptor]) -> [LocalModelDescriptor] {
        models.sorted { lhs, rhs in
            let lhsSupportsChat = lhs.capabilities.contains(.chat)
            let rhsSupportsChat = rhs.capabilities.contains(.chat)
            if lhsSupportsChat != rhsSupportsChat {
                return lhsSupportsChat
            }

            let lhsLoaded = lhs.loadedInstanceCount ?? 0
            let rhsLoaded = rhs.loadedInstanceCount ?? 0
            if lhsLoaded != rhsLoaded {
                return lhsLoaded > rhsLoaded
            }

            let titleComparison = descriptorTitle(lhs).localizedCaseInsensitiveCompare(descriptorTitle(rhs))
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func descriptorTitle(_ model: LocalModelDescriptor) -> String {
        if let displayName = model.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }

        return model.name
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

    private func makeOllamaShowRequest(endpoint: String, model: String) throws -> URLRequest {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw DiscoveryError.invalidModelName
        }

        var request = try makeRequest(endpoint: endpoint, appending: ["api", "show"])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaShowModelDiscoveryRequest(model: model, verbose: false)
        )
        return request
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport(request)
        guard let httpResponse = response else {
            throw DiscoveryError.badResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DiscoveryError.badStatus(
                httpResponse.statusCode,
                Self.responseErrorMessage(from: data)
            )
        }

        do {
            return try JSONDecoder.discovery.decode(T.self, from: data)
        } catch {
            throw DiscoveryError.decodingFailed(Self.discoveryErrorDescription(error))
        }
    }

    private static func combinedLMStudioDiscoveryError(nativeError: Error, fallbackError: Error) -> String {
        [
            "LM Studio native discovery failed: \(discoveryErrorDescription(nativeError))",
            "OpenAI-compatible fallback failed: \(discoveryErrorDescription(fallbackError))"
        ].joined(separator: " ")
    }

    private static func combinedOllamaDiscoveryWarning(
        runningWarning: String?,
        detailsWarning: String?
    ) -> String? {
        [runningWarning, detailsWarning]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty
    }

    private static func ollamaModelDetailsWarning(_ failedModelNames: [String]) -> String? {
        guard !failedModelNames.isEmpty else { return nil }

        let preview = failedModelNames
            .prefix(3)
            .joined(separator: ", ")
        let remainingCount = max(0, failedModelNames.count - 3)
        let suffix = remainingCount > 0 ? " and \(remainingCount) more" : ""
        let modelText = failedModelNames.count == 1 ? "model" : "models"
        return "Ollama model detail metadata unavailable for \(failedModelNames.count) \(modelText): \(preview)\(suffix)."
    }

    private static func discoveryErrorDescription(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private static func responseErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if let object = try? JSONSerialization.jsonObject(with: data),
           let message = responseErrorMessage(from: object) {
            return message
        }

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return compactMessage(text)
    }

    private static func responseErrorMessage(from object: Any) -> String? {
        if let message = object as? String {
            return compactMessage(message)
        }

        if let dictionary = object as? [String: Any] {
            for key in ["error", "message", "detail"] {
                if let value = dictionary[key],
                   let message = responseErrorMessage(from: value) {
                    return message
                }
            }
        }

        if let array = object as? [Any] {
            return array.lazy.compactMap { responseErrorMessage(from: $0) }.first
        }

        return nil
    }

    private static func compactMessage(_ rawValue: String) -> String? {
        let collapsed = rawValue
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return nil }

        let maxLength = 240
        if collapsed.count <= maxLength {
            return collapsed
        }

        return String(collapsed.prefix(maxLength - 1)) + "..."
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
        if normalizedPathComponents.suffix(3) == ["api", "v1", "models"] {
            pathComponents.removeLast(3)
        } else if normalizedPathComponents.suffix(2) == ["api", "v1"] {
            pathComponents.removeLast(2)
        } else if normalizedPathComponents.suffix(2) == ["v1", "models"] {
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
    case invalidModelName
    case badResponse
    case badStatus(Int, String?)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The endpoint URL is invalid."
        case .invalidModelName:
            "The model name is empty."
        case .badResponse:
            "The provider did not return an HTTP response."
        case .badStatus(let statusCode, let message):
            if let message, !message.isEmpty {
                "The provider returned HTTP \(statusCode): \(message)"
            } else {
                "The provider returned HTTP \(statusCode)."
            }
        case .decodingFailed(let message):
            "Unable to decode provider response: \(message)"
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

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct OllamaTagsDiscoveryResponse: Decodable, Sendable {
    var models: [OllamaModel]

    struct OllamaModel: Decodable, Sendable {
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

    struct Details: Decodable, Sendable {
        var format: String?
        var family: String?
        var families: [String]?
        var parameterSize: String?
        var quantizationLevel: String?

        enum CodingKeys: String, CodingKey {
            case format
            case family
            case families
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }
}

private struct OllamaRunningModelsDiscovery: Sendable {
    var models: [String: OllamaRunningModelDiscovery]
    var errorMessage: String?
}

private struct OllamaModelDetailsDiscovery: Sendable {
    var models: [String: OllamaShowModelDiscoveryResponse]
    var errorMessage: String?
}

private struct OllamaRunningModelsDiscoveryResponse: Decodable, Sendable {
    var models: [OllamaRunningModelDiscovery]
}

private struct OllamaRunningModelDiscovery: Decodable, Sendable {
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

private struct OllamaShowModelDiscoveryRequest: Encodable {
    var model: String
    var verbose: Bool
}

private struct OllamaShowModelDiscoveryResponse: Decodable, Sendable {
    var modifiedAt: Date?
    var details: OllamaTagsDiscoveryResponse.Details?
    var capabilities: [String]?
    var modelInfo: [String: OllamaModelInfoValue]?

    var contextLength: Int? {
        modelInfo?
            .first { key, _ in key.lowercased().hasSuffix(".context_length") || key.lowercased() == "context_length" }?
            .value
            .intValue
    }

    enum CodingKeys: String, CodingKey {
        case modifiedAt = "modified_at"
        case details
        case capabilities
        case modelInfo = "model_info"
    }
}

private enum OllamaModelInfoValue: Decodable, Sendable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)
    case ignored

    var intValue: Int? {
        switch self {
        case .int(let value):
            value
        case .double(let value) where value.isFinite:
            Int(value)
        case .string(let value):
            Int(value)
        case .double, .bool, .ignored:
            nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .ignored
        }
    }
}

private struct LMStudioNativeModelsDiscoveryResponse: Decodable, Sendable {
    var models: [Model]

    struct Model: Decodable, Sendable {
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

    struct Quantization: Decodable, Sendable {
        var name: String?
    }

    struct LoadedInstance: Decodable, Sendable {
        var id: String?
        var config: LoadedInstanceConfig?
    }

    struct LoadedInstanceConfig: Decodable, Sendable {
        var contextLength: Int?

        enum CodingKeys: String, CodingKey {
            case contextLength = "context_length"
        }
    }

    struct Capabilities: Decodable, Sendable {
        var vision: Bool?
        var trainedForToolUse: Bool?
        var reasoning: Reasoning?

        enum CodingKeys: String, CodingKey {
            case vision
            case trainedForToolUse = "trained_for_tool_use"
            case reasoning
        }
    }

    struct Reasoning: Decodable, Sendable {
        var allowedOptions: [String]?
        var defaultOption: String?

        enum CodingKeys: String, CodingKey {
            case allowedOptions = "allowed_options"
            case defaultOption = "default"
        }
    }
}

private struct OpenAICompatibleModelsDiscoveryResponse: Decodable, Sendable {
    var data: [Model]

    struct Model: Decodable, Sendable {
        var id: String
        var ownedBy: String?
        var publisher: String?
        var modelType: String?
        var displayName: String?
        var architecture: String?
        var quantization: LMStudioNativeModelsDiscoveryResponse.Quantization?
        var sizeBytes: Int64?
        var paramsString: String?
        var loadedInstances: [LMStudioNativeModelsDiscoveryResponse.LoadedInstance]?
        var maxContextLength: Int?
        var format: String?
        var capabilities: LMStudioNativeModelsDiscoveryResponse.Capabilities?
        var selectedVariant: String?

        enum CodingKeys: String, CodingKey {
            case id
            case ownedBy = "owned_by"
            case publisher
            case modelType = "type"
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
