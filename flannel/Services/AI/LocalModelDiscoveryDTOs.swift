//
//  LocalModelDiscoveryDTOs.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

struct OllamaTagsResponseDTO: Codable, Hashable, Sendable {
    var models: [OllamaModelDTO]

    func descriptors(discoveredAt: Date = .now) -> [AIModelDescriptor] {
        models.map { $0.asDescriptor(discoveredAt: discoveredAt) }
    }
}

struct OllamaModelDTO: Identifiable, Codable, Hashable, Sendable {
    var name: String
    var model: String
    var modifiedAtRawValue: String?
    var size: Int64
    var digest: String
    var details: OllamaModelDetailsDTO

    var id: String { model }

    var modifiedAt: Date? {
        LocalModelTimestampParser.date(from: modifiedAtRawValue)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case modifiedAtRawValue = "modified_at"
        case size
        case digest
        case details
    }

    func asDescriptor(discoveredAt: Date = .now) -> AIModelDescriptor {
        AIModelDescriptor(
            providerKind: .ollama,
            providerMode: .nativeAPI,
            identifier: model,
            displayName: name,
            family: details.family,
            parameterCountLabel: details.parameterSize,
            quantizationLabel: details.quantizationLevel,
            installedSizeBytes: size,
            isAvailableLocally: true,
            loadedInstanceCount: 0,
            capabilities: [],
            lastDiscoveredAt: discoveredAt
        )
    }
}

struct OllamaModelDetailsDTO: Codable, Hashable, Sendable {
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

struct OllamaRunningModelsResponseDTO: Codable, Hashable, Sendable {
    var models: [OllamaRunningModelDTO]
}

struct OllamaRunningModelDTO: Identifiable, Codable, Hashable, Sendable {
    var name: String
    var model: String
    var size: Int64
    var digest: String
    var details: OllamaModelDetailsDTO
    var expiresAtRawValue: String?
    var sizeVRAM: Int64?
    var contextLength: Int?

    var id: String { model }

    var expiresAt: Date? {
        LocalModelTimestampParser.date(from: expiresAtRawValue)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case size
        case digest
        case details
        case expiresAtRawValue = "expires_at"
        case sizeVRAM = "size_vram"
        case contextLength = "context_length"
    }
}

struct LMStudioModelsResponseDTO: Codable, Hashable, Sendable {
    var models: [LMStudioModelDTO]

    func descriptors(discoveredAt: Date = .now) -> [AIModelDescriptor] {
        models.map { $0.asDescriptor(discoveredAt: discoveredAt) }
    }
}

struct LMStudioModelDTO: Identifiable, Codable, Hashable, Sendable {
    enum ModelType: String, Codable, Sendable {
        case llm
        case embedding
    }

    var type: ModelType
    var publisher: String
    var key: String
    var displayName: String
    var architecture: String?
    var quantization: LMStudioQuantizationDTO?
    var sizeBytes: Int64
    var paramsString: String?
    var loadedInstances: [LMStudioLoadedInstanceDTO]
    var maxContextLength: Int
    var format: String?
    var capabilities: LMStudioModelCapabilitiesDTO?
    var modelDescription: String?
    var variants: [String]?
    var selectedVariant: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case type
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
        case modelDescription = "description"
        case variants
        case selectedVariant = "selected_variant"
    }

    func asDescriptor(discoveredAt: Date = .now) -> AIModelDescriptor {
        AIModelDescriptor(
            providerKind: .lmStudio,
            providerMode: .nativeAPI,
            identifier: key,
            displayName: displayName,
            publisher: publisher,
            family: architecture,
            parameterCountLabel: paramsString,
            quantizationLabel: quantization?.name,
            contextWindow: loadedInstances.first?.config.contextLength ?? maxContextLength,
            installedSizeBytes: sizeBytes,
            isAvailableLocally: true,
            loadedInstanceCount: loadedInstances.count,
            capabilities: capabilitySet,
            defaultReasoningLevel: capabilities?.reasoning.flatMap {
                AIReasoningLevel(rawValue: $0.defaultOption)
            },
            supportedReasoningLevels: capabilities?.reasoning?.allowedOptions.compactMap(AIReasoningLevel.init(rawValue:)) ?? [],
            lastDiscoveredAt: discoveredAt
        )
    }

    private var capabilitySet: Set<AIModelCapability> {
        switch type {
        case .embedding:
            return [.embeddings]
        case .llm:
            var capabilitySet: Set<AIModelCapability> = [.chat, .streaming]

            if capabilities?.vision == true {
                capabilitySet.insert(.vision)
            }

            if capabilities?.trainedForToolUse == true {
                capabilitySet.insert(.toolUse)
            }

            if capabilities?.reasoning != nil {
                capabilitySet.insert(.reasoning)
            }

            return capabilitySet
        }
    }
}

struct LMStudioQuantizationDTO: Codable, Hashable, Sendable {
    var name: String?
    var bitsPerWeight: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case bitsPerWeight = "bits_per_weight"
    }
}

struct LMStudioLoadedInstanceDTO: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var config: LMStudioLoadedInstanceConfigDTO
}

struct LMStudioLoadedInstanceConfigDTO: Codable, Hashable, Sendable {
    var contextLength: Int
    var evalBatchSize: Int?
    var parallel: Int?
    var flashAttention: Bool?
    var numExperts: Int?
    var offloadKVCacheToGPU: Bool?

    enum CodingKeys: String, CodingKey {
        case contextLength = "context_length"
        case evalBatchSize = "eval_batch_size"
        case parallel
        case flashAttention = "flash_attention"
        case numExperts = "num_experts"
        case offloadKVCacheToGPU = "offload_kv_cache_to_gpu"
    }
}

struct LMStudioModelCapabilitiesDTO: Codable, Hashable, Sendable {
    var vision: Bool
    var trainedForToolUse: Bool
    var reasoning: LMStudioReasoningDTO?

    enum CodingKeys: String, CodingKey {
        case vision
        case trainedForToolUse = "trained_for_tool_use"
        case reasoning
    }
}

struct LMStudioReasoningDTO: Codable, Hashable, Sendable {
    var allowedOptions: [String]
    var defaultOption: String

    enum CodingKeys: String, CodingKey {
        case allowedOptions = "allowed_options"
        case defaultOption = "default"
    }
}

struct LMStudioOpenAIModelListDTO: Codable, Hashable, Sendable {
    var object: String
    var data: [LMStudioOpenAIModelDTO]
}

struct LMStudioOpenAIModelDTO: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var object: String
    var created: Int?
    var ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case ownedBy = "owned_by"
    }

    var createdAt: Date? {
        guard let created else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(created))
    }

    func asDescriptor(discoveredAt: Date = .now) -> AIModelDescriptor {
        AIModelDescriptor(
            providerKind: .lmStudio,
            providerMode: .openAICompatible,
            identifier: id,
            displayName: id,
            publisher: ownedBy,
            isAvailableLocally: true,
            capabilities: [.chat, .streaming],
            lastDiscoveredAt: discoveredAt
        )
    }
}

private enum LocalModelTimestampParser {
    private static let formatters: [ISO8601DateFormatter] = {
        let base = ISO8601DateFormatter()
        base.formatOptions = [.withInternetDateTime]

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return [fractional, base]
    }()

    static func date(from rawValue: String?) -> Date? {
        guard let rawValue else { return nil }

        for formatter in formatters {
            if let value = formatter.date(from: rawValue) {
                return value
            }
        }

        return nil
    }
}
