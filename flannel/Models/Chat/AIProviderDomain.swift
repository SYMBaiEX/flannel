//
//  AIProviderDomain.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

enum AIProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case ollama
    case lmStudio
    case openAI
    case anthropic
    case gemini
    case xAI
    case mistral
    case groq
    case openRouter
    case perplexity
    case customOpenAICompatible
    case chatGPTCLI
    case claudeCodeCLI
    case vercelAISDKBridge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama:
            "Ollama"
        case .lmStudio:
            "LM Studio"
        case .openAI:
            "OpenAI"
        case .anthropic:
            "Anthropic"
        case .gemini:
            "Google Gemini"
        case .xAI:
            "xAI"
        case .mistral:
            "Mistral"
        case .groq:
            "Groq"
        case .openRouter:
            "OpenRouter"
        case .perplexity:
            "Perplexity"
        case .customOpenAICompatible:
            "Custom OpenAI-compatible"
        case .chatGPTCLI:
            "ChatGPT/Codex CLI"
        case .claudeCodeCLI:
            "Claude Code CLI"
        case .vercelAISDKBridge:
            "Vercel AI SDK Bridge"
        }
    }

    var isLocalProvider: Bool {
        switch self {
        case .ollama, .lmStudio:
            true
        case .openAI, .anthropic, .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity,
             .customOpenAICompatible, .chatGPTCLI, .claudeCodeCLI, .vercelAISDKBridge:
            false
        }
    }

    var defaultBaseURL: URL? {
        switch self {
        case .ollama:
            URL(string: "http://localhost:11434")
        case .lmStudio:
            URL(string: "http://localhost:1234")
        case .openAI:
            URL(string: "https://api.openai.com/v1")
        case .anthropic:
            URL(string: "https://api.anthropic.com")
        case .gemini:
            URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")
        case .xAI:
            URL(string: "https://api.x.ai/v1")
        case .mistral:
            URL(string: "https://api.mistral.ai/v1")
        case .groq:
            URL(string: "https://api.groq.com/openai/v1")
        case .openRouter:
            URL(string: "https://openrouter.ai/api/v1")
        case .perplexity:
            URL(string: "https://api.perplexity.ai")
        case .customOpenAICompatible:
            URL(string: "http://localhost:8080/v1")
        case .chatGPTCLI, .claudeCodeCLI:
            nil
        case .vercelAISDKBridge:
            URL(string: "http://localhost:4177")
        }
    }
}

enum AIProviderMode: String, Codable, CaseIterable, Sendable {
    case nativeAPI
    case apiKey
    case subscriptionCLI
    case openAICompatible
    case anthropicCompatible
    case aiSDKBridge

    var defaultPathComponent: String {
        switch self {
        case .nativeAPI:
            "/api"
        case .apiKey, .openAICompatible:
            "/v1"
        case .anthropicCompatible:
            "/v1"
        case .subscriptionCLI, .aiSDKBridge:
            ""
        }
    }
}

enum AIReasoningLevel: String, Codable, CaseIterable, Sendable {
    case off
    case on
    case low
    case medium
    case high
}

enum AIModelCapability: String, Codable, CaseIterable, Sendable {
    case chat
    case embeddings
    case vision
    case toolUse
    case structuredOutput
    case reasoning
    case streaming
    case retrieval
}

struct AIModelDescriptor: Identifiable, Codable, Hashable, Sendable {
    var providerKind: AIProviderKind
    var providerMode: AIProviderMode
    var identifier: String
    var displayName: String
    var publisher: String?
    var family: String?
    var parameterCountLabel: String?
    var quantizationLabel: String?
    var contextWindow: Int?
    var maxOutputTokens: Int?
    var installedSizeBytes: Int64?
    var isAvailableLocally: Bool
    var loadedInstanceCount: Int
    var capabilities: Set<AIModelCapability>
    var defaultReasoningLevel: AIReasoningLevel?
    var supportedReasoningLevels: [AIReasoningLevel]
    var lastDiscoveredAt: Date?

    var id: String {
        "\(providerKind.rawValue):\(providerMode.rawValue):\(identifier)"
    }

    var supportsStreaming: Bool {
        capabilities.contains(.streaming)
    }

    var supportsToolUse: Bool {
        capabilities.contains(.toolUse)
    }

    var supportsVision: Bool {
        capabilities.contains(.vision)
    }

    init(
        providerKind: AIProviderKind,
        providerMode: AIProviderMode,
        identifier: String,
        displayName: String,
        publisher: String? = nil,
        family: String? = nil,
        parameterCountLabel: String? = nil,
        quantizationLabel: String? = nil,
        contextWindow: Int? = nil,
        maxOutputTokens: Int? = nil,
        installedSizeBytes: Int64? = nil,
        isAvailableLocally: Bool = true,
        loadedInstanceCount: Int = 0,
        capabilities: Set<AIModelCapability> = [],
        defaultReasoningLevel: AIReasoningLevel? = nil,
        supportedReasoningLevels: [AIReasoningLevel] = [],
        lastDiscoveredAt: Date? = nil
    ) {
        self.providerKind = providerKind
        self.providerMode = providerMode
        self.identifier = identifier
        self.displayName = displayName
        self.publisher = publisher
        self.family = family
        self.parameterCountLabel = parameterCountLabel
        self.quantizationLabel = quantizationLabel
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.installedSizeBytes = installedSizeBytes
        self.isAvailableLocally = isAvailableLocally
        self.loadedInstanceCount = loadedInstanceCount
        self.capabilities = capabilities
        self.defaultReasoningLevel = defaultReasoningLevel
        self.supportedReasoningLevels = supportedReasoningLevels
        self.lastDiscoveredAt = lastDiscoveredAt
    }
}

enum AIProviderHealthStatus: String, Codable, CaseIterable, Sendable {
    case unknown
    case ready
    case degraded
    case unavailable
    case misconfigured
}

struct AIProviderHealth: Identifiable, Codable, Hashable, Sendable {
    var providerKind: AIProviderKind
    var providerMode: AIProviderMode
    var endpoint: URL?
    var status: AIProviderHealthStatus
    var checkedAt: Date?
    var lastSuccessfulCheckAt: Date?
    var roundTripLatencyMilliseconds: Int?
    var discoveredModelCount: Int
    var loadedModelCount: Int
    var serverVersion: String?
    var warningMessage: String?
    var failureMessage: String?

    var id: String {
        "\(providerKind.rawValue):\(providerMode.rawValue)"
    }

    var canServeRequests: Bool {
        switch status {
        case .ready, .degraded:
            true
        case .unknown, .unavailable, .misconfigured:
            false
        }
    }

    init(
        providerKind: AIProviderKind,
        providerMode: AIProviderMode,
        endpoint: URL? = nil,
        status: AIProviderHealthStatus = .unknown,
        checkedAt: Date? = nil,
        lastSuccessfulCheckAt: Date? = nil,
        roundTripLatencyMilliseconds: Int? = nil,
        discoveredModelCount: Int = 0,
        loadedModelCount: Int = 0,
        serverVersion: String? = nil,
        warningMessage: String? = nil,
        failureMessage: String? = nil
    ) {
        self.providerKind = providerKind
        self.providerMode = providerMode
        self.endpoint = endpoint
        self.status = status
        self.checkedAt = checkedAt
        self.lastSuccessfulCheckAt = lastSuccessfulCheckAt
        self.roundTripLatencyMilliseconds = roundTripLatencyMilliseconds
        self.discoveredModelCount = discoveredModelCount
        self.loadedModelCount = loadedModelCount
        self.serverVersion = serverVersion
        self.warningMessage = warningMessage
        self.failureMessage = failureMessage
    }
}

extension AIProviderKind {
    init(_ providerKind: LLMProviderKind) {
        switch providerKind {
        case .ollama:
            self = .ollama
        case .lmStudio:
            self = .lmStudio
        case .openAI:
            self = .openAI
        case .anthropic:
            self = .anthropic
        case .gemini:
            self = .gemini
        case .xAI:
            self = .xAI
        case .mistral:
            self = .mistral
        case .groq:
            self = .groq
        case .openRouter:
            self = .openRouter
        case .perplexity:
            self = .perplexity
        case .customOpenAICompatible:
            self = .customOpenAICompatible
        case .chatGPTCLI:
            self = .chatGPTCLI
        case .claudeCodeCLI:
            self = .claudeCodeCLI
        case .vercelAISDKBridge:
            self = .vercelAISDKBridge
        }
    }
}

extension LLMProviderKind {
    init(_ providerKind: AIProviderKind) {
        switch providerKind {
        case .ollama:
            self = .ollama
        case .openAI:
            self = .openAI
        case .lmStudio:
            self = .lmStudio
        case .anthropic:
            self = .anthropic
        case .gemini:
            self = .gemini
        case .xAI:
            self = .xAI
        case .mistral:
            self = .mistral
        case .groq:
            self = .groq
        case .openRouter:
            self = .openRouter
        case .perplexity:
            self = .perplexity
        case .customOpenAICompatible:
            self = .customOpenAICompatible
        case .chatGPTCLI:
            self = .chatGPTCLI
        case .claudeCodeCLI:
            self = .claudeCodeCLI
        case .vercelAISDKBridge:
            self = .vercelAISDKBridge
        }
    }
}

extension AIProviderMode {
    init(_ accessMode: ProviderAccessMode) {
        switch accessMode {
        case .localServer:
            self = .nativeAPI
        case .apiKey:
            self = .apiKey
        case .subscriptionCLI:
            self = .subscriptionCLI
        case .openAICompatible:
            self = .openAICompatible
        case .anthropicCompatible:
            self = .anthropicCompatible
        case .aiSDKBridge:
            self = .aiSDKBridge
        }
    }
}
