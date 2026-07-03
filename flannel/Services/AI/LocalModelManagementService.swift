//
//  LocalModelManagementService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation

nonisolated struct OllamaModelPullUpdate: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var status: String
    var digest: String?
    var total: Int64?
    var completed: Int64?
    var error: String?

    init(
        id: UUID = UUID(),
        status: String,
        digest: String? = nil,
        total: Int64? = nil,
        completed: Int64? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.status = status
        self.digest = digest
        self.total = total
        self.completed = completed
        self.error = error
    }

    var progressFraction: Double? {
        guard let total,
              let completed,
              total > 0 else {
            return nil
        }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case digest
        case total
        case completed
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        digest = try container.decodeIfPresent(String.self, forKey: .digest)
        total = try container.decodeIfPresent(Int64.self, forKey: .total)
        completed = try container.decodeIfPresent(Int64.self, forKey: .completed)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

nonisolated indirect enum LocalModelMetadataValue: Codable, Hashable, Sendable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case array([LocalModelMetadataValue])
    case object([String: LocalModelMetadataValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([LocalModelMetadataValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: LocalModelMetadataValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var displayText: String {
        switch self {
        case .string(let value):
            value
        case .integer(let value):
            value.formatted()
        case .number(let value):
            value.formatted()
        case .bool(let value):
            value ? "true" : "false"
        case .array(let values):
            values.map(\.displayText).joined(separator: ", ")
        case .object(let value):
            value
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { "\($0.key): \($0.value.displayText)" }
                .joined(separator: ", ")
        case .null:
            "null"
        }
    }
}

nonisolated struct OllamaModelInfo: Identifiable, Hashable, Sendable {
    var model: String
    var endpoint: String
    var modifiedAt: Date?
    var modelfile: String?
    var parameters: String?
    var template: String?
    var system: String?
    var license: String?
    var details: OllamaModelInfoDetails?
    var modelInfo: [String: LocalModelMetadataValue]
    var capabilities: [String]

    var id: String { "\(endpoint):\(model)" }

    var summaryPairs: [(String, String)] {
        var pairs: [(String, String)] = []
        if let family = details?.family, !family.isEmpty {
            pairs.append(("Family", family))
        }
        if let parameterSize = details?.parameterSize, !parameterSize.isEmpty {
            pairs.append(("Parameters", parameterSize))
        }
        if let quantizationLevel = details?.quantizationLevel, !quantizationLevel.isEmpty {
            pairs.append(("Quantization", quantizationLevel))
        }
        if let format = details?.format, !format.isEmpty {
            pairs.append(("Format", format))
        }
        if !capabilities.isEmpty {
            pairs.append(("Capabilities", capabilities.joined(separator: ", ")))
        }
        if let modifiedAt {
            pairs.append(("Modified", modifiedAt.formatted(date: .abbreviated, time: .shortened)))
        }
        return pairs
    }

    var modelInfoPairs: [(String, String)] {
        modelInfo
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { (Self.humanizedMetadataKey($0.key), $0.value.displayText) }
    }

    init(
        model: String,
        endpoint: String,
        modifiedAt: Date? = nil,
        modelfile: String? = nil,
        parameters: String? = nil,
        template: String? = nil,
        system: String? = nil,
        license: String? = nil,
        details: OllamaModelInfoDetails? = nil,
        modelInfo: [String: LocalModelMetadataValue] = [:],
        capabilities: [String] = []
    ) {
        self.model = model
        self.endpoint = endpoint
        self.modifiedAt = modifiedAt
        self.modelfile = modelfile
        self.parameters = parameters
        self.template = template
        self.system = system
        self.license = license
        self.details = details
        self.modelInfo = modelInfo
        self.capabilities = capabilities
    }

    private static func humanizedMetadataKey(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}

nonisolated struct LMStudioModelLoadResult: Hashable, Sendable {
    var model: String
    var endpoint: String
    var responseType: String?
    var instanceID: String?
    var loadTimeSeconds: Double?
    var status: String?
    var contextLength: Int?
}

nonisolated struct LMStudioModelUnloadResult: Hashable, Sendable {
    var instanceID: String
    var endpoint: String
}

nonisolated struct OllamaModelInfoDetails: Codable, Hashable, Sendable {
    var parentModel: String?
    var format: String?
    var family: String?
    var families: [String]?
    var parameterSize: String?
    var quantizationLevel: String?

    enum CodingKeys: String, CodingKey {
        case parentModel = "parent_model"
        case format
        case family
        case families
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
}

nonisolated enum LocalModelManagementError: LocalizedError, Equatable {
    case invalidEndpoint
    case missingModelName
    case missingInstanceID
    case badStatus(Int)
    case providerError(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The local model endpoint is not a valid URL."
        case .missingModelName:
            "Enter a local model name before starting the action."
        case .missingInstanceID:
            "Run discovery again to get the loaded LM Studio instance ID."
        case .badStatus(let statusCode):
            "The local model provider returned HTTP \(statusCode)."
        case .providerError(let message):
            message
        }
    }
}

struct LocalModelManagementService: Sendable {
    var session: URLSession
    var timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 1_800) {
        self.session = session
        self.timeout = timeout
    }

    func pullOllamaModel(
        model rawModel: String,
        endpoint rawEndpoint: String,
        stream: Bool = true
    ) -> AsyncThrowingStream<OllamaModelPullUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeOllamaPullRequest(
                        endpoint: rawEndpoint,
                        model: rawModel,
                        stream: stream
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LocalModelManagementError.badStatus(-1)
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw LocalModelManagementError.badStatus(httpResponse.statusCode)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let update = try Self.parseOllamaPullLine(line) else { continue }
                        if let error = update.error?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !error.isEmpty {
                            throw LocalModelManagementError.providerError(error)
                        }
                        continuation.yield(update)
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

    func makeOllamaPullRequest(
        endpoint rawEndpoint: String,
        model rawModel: String,
        stream: Bool = true
    ) throws -> URLRequest {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw LocalModelManagementError.missingModelName
        }

        let url = try endpoint(rawEndpoint, appending: ["api", "pull"])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaPullRequestPayload(model: model, stream: stream)
        )
        return request
    }

    func deleteOllamaModel(
        model rawModel: String,
        endpoint rawEndpoint: String
    ) async throws {
        let request = try makeOllamaDeleteRequest(
            endpoint: rawEndpoint,
            model: rawModel
        )
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalModelManagementError.badStatus(-1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LocalModelManagementError.badStatus(httpResponse.statusCode)
        }
    }

    func showOllamaModel(
        model rawModel: String,
        endpoint rawEndpoint: String,
        verbose: Bool = false
    ) async throws -> OllamaModelInfo {
        let request = try makeOllamaShowRequest(
            endpoint: rawEndpoint,
            model: rawModel,
            verbose: verbose
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalModelManagementError.badStatus(-1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LocalModelManagementError.badStatus(httpResponse.statusCode)
        }
        return try Self.parseOllamaShowResponse(
            data,
            model: rawModel.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func loadLMStudioModel(
        model rawModel: String,
        endpoint rawEndpoint: String,
        contextLength: Int? = nil
    ) async throws -> LMStudioModelLoadResult {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootEndpoint = try nativeLMStudioEndpoint(rawEndpoint)
        let request = try makeLMStudioLoadRequest(
            endpoint: rootEndpoint,
            model: model,
            contextLength: contextLength
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalModelManagementError.badStatus(-1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LocalModelManagementError.badStatus(httpResponse.statusCode)
        }
        return try Self.parseLMStudioLoadResponse(
            data,
            model: model,
            endpoint: rootEndpoint
        )
    }

    func unloadLMStudioModel(
        instanceID rawInstanceID: String,
        endpoint rawEndpoint: String
    ) async throws -> LMStudioModelUnloadResult {
        let rootEndpoint = try nativeLMStudioEndpoint(rawEndpoint)
        let request = try makeLMStudioUnloadRequest(
            endpoint: rootEndpoint,
            instanceID: rawInstanceID
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalModelManagementError.badStatus(-1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LocalModelManagementError.badStatus(httpResponse.statusCode)
        }
        return try Self.parseLMStudioUnloadResponse(data, endpoint: rootEndpoint)
    }

    func makeOllamaDeleteRequest(
        endpoint rawEndpoint: String,
        model rawModel: String
    ) throws -> URLRequest {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw LocalModelManagementError.missingModelName
        }

        let url = try endpoint(rawEndpoint, appending: ["api", "delete"])
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaDeleteRequestPayload(model: model)
        )
        return request
    }

    func makeOllamaShowRequest(
        endpoint rawEndpoint: String,
        model rawModel: String,
        verbose: Bool = false
    ) throws -> URLRequest {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw LocalModelManagementError.missingModelName
        }

        let url = try endpoint(rawEndpoint, appending: ["api", "show"])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaShowRequestPayload(model: model, verbose: verbose)
        )
        return request
    }

    func makeLMStudioLoadRequest(
        endpoint rawEndpoint: String,
        model rawModel: String,
        contextLength: Int? = nil
    ) throws -> URLRequest {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw LocalModelManagementError.missingModelName
        }

        let rootEndpoint = try nativeLMStudioEndpoint(rawEndpoint)
        let url = try endpoint(rootEndpoint, appending: ["api", "v1", "models", "load"])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            LMStudioLoadRequestPayload(
                model: model,
                contextLength: contextLength,
                echoLoadConfig: true
            )
        )
        return request
    }

    func makeLMStudioUnloadRequest(
        endpoint rawEndpoint: String,
        instanceID rawInstanceID: String
    ) throws -> URLRequest {
        let instanceID = rawInstanceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instanceID.isEmpty else {
            throw LocalModelManagementError.missingInstanceID
        }

        let rootEndpoint = try nativeLMStudioEndpoint(rawEndpoint)
        let url = try endpoint(rootEndpoint, appending: ["api", "v1", "models", "unload"])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            LMStudioUnloadRequestPayload(instanceID: instanceID)
        )
        return request
    }

    nonisolated static func parseOllamaPullLine(_ line: String) throws -> OllamaModelPullUpdate? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let data = Data(trimmed.utf8)
        return try JSONDecoder().decode(OllamaModelPullUpdate.self, from: data)
    }

    nonisolated static func parseOllamaShowResponse(
        _ data: Data,
        model: String,
        endpoint: String
    ) throws -> OllamaModelInfo {
        let response = try JSONDecoder().decode(OllamaShowResponsePayload.self, from: data)
        return OllamaModelInfo(
            model: model,
            endpoint: endpoint,
            modifiedAt: parseOllamaDate(response.modifiedAtRawValue),
            modelfile: response.modelfile,
            parameters: response.parameters,
            template: response.template,
            system: response.system,
            license: response.license,
            details: response.details,
            modelInfo: response.modelInfo ?? [:],
            capabilities: response.capabilities ?? []
        )
    }

    nonisolated static func parseLMStudioLoadResponse(
        _ data: Data,
        model: String,
        endpoint: String
    ) throws -> LMStudioModelLoadResult {
        let response = try JSONDecoder().decode(LMStudioLoadResponsePayload.self, from: data)
        return LMStudioModelLoadResult(
            model: model,
            endpoint: endpoint,
            responseType: response.responseType?.trimmedNonEmpty,
            instanceID: response.instanceID?.trimmedNonEmpty,
            loadTimeSeconds: response.loadTimeSeconds,
            status: response.status?.trimmedNonEmpty,
            contextLength: response.loadConfig?.contextLength
        )
    }

    nonisolated static func parseLMStudioUnloadResponse(
        _ data: Data,
        endpoint: String
    ) throws -> LMStudioModelUnloadResult {
        let response = try JSONDecoder().decode(LMStudioUnloadResponsePayload.self, from: data)
        guard let instanceID = response.instanceID?.trimmedNonEmpty else {
            throw LocalModelManagementError.missingInstanceID
        }
        return LMStudioModelUnloadResult(instanceID: instanceID, endpoint: endpoint)
    }

    private func endpoint(_ rawValue: String, appending pathComponents: [String]) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil else {
            throw LocalModelManagementError.invalidEndpoint
        }

        var path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for component in pathComponents {
            path = path.isEmpty ? component : "\(path)/\(component)"
        }

        components.path = "/" + path
        guard let url = components.url else {
            throw LocalModelManagementError.invalidEndpoint
        }
        return url
    }

    private func nativeLMStudioEndpoint(_ rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil else {
            throw LocalModelManagementError.invalidEndpoint
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
        guard let url = components.url else {
            throw LocalModelManagementError.invalidEndpoint
        }
        return url.absoluteString
    }

    private nonisolated static func parseOllamaDate(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: rawValue) {
            return date
        }

        let base = ISO8601DateFormatter()
        base.formatOptions = [.withInternetDateTime]
        return base.date(from: rawValue)
    }
}

private nonisolated struct OllamaPullRequestPayload: Encodable {
    var model: String
    var stream: Bool
}

private nonisolated struct OllamaDeleteRequestPayload: Encodable {
    var model: String
}

private nonisolated struct OllamaShowRequestPayload: Encodable {
    var model: String
    var verbose: Bool
}

private nonisolated struct LMStudioLoadRequestPayload: Encodable {
    var model: String
    var contextLength: Int?
    var echoLoadConfig: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case contextLength = "context_length"
        case echoLoadConfig = "echo_load_config"
    }
}

private nonisolated struct LMStudioUnloadRequestPayload: Encodable {
    var instanceID: String

    enum CodingKeys: String, CodingKey {
        case instanceID = "instance_id"
    }
}

private nonisolated struct OllamaShowResponsePayload: Decodable {
    var modifiedAtRawValue: String?
    var modelfile: String?
    var parameters: String?
    var template: String?
    var system: String?
    var license: String?
    var details: OllamaModelInfoDetails?
    var modelInfo: [String: LocalModelMetadataValue]?
    var capabilities: [String]?

    enum CodingKeys: String, CodingKey {
        case modifiedAtRawValue = "modified_at"
        case modelfile
        case parameters
        case template
        case system
        case license
        case details
        case modelInfo = "model_info"
        case capabilities
    }
}

private nonisolated struct LMStudioLoadResponsePayload: Decodable {
    var responseType: String?
    var instanceID: String?
    var loadTimeSeconds: Double?
    var status: String?
    var loadConfig: LoadConfig?

    enum CodingKeys: String, CodingKey {
        case responseType = "type"
        case instanceID = "instance_id"
        case loadTimeSeconds = "load_time_seconds"
        case status
        case loadConfig = "load_config"
    }

    struct LoadConfig: Decodable {
        var contextLength: Int?

        enum CodingKeys: String, CodingKey {
            case contextLength = "context_length"
        }
    }
}

private nonisolated struct LMStudioUnloadResponsePayload: Decodable {
    var instanceID: String?

    enum CodingKeys: String, CodingKey {
        case instanceID = "instance_id"
    }
}

private extension String {
    nonisolated var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
