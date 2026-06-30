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

enum AIProviderCredentialRequirement: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case requiredAPIKey
    case optionalAPIKey
    case subscriptionCLI
    case localBridge

    var title: String {
        switch self {
        case .none:
            "No credential"
        case .requiredAPIKey:
            "API key required"
        case .optionalAPIKey:
            "Optional API key"
        case .subscriptionCLI:
            "Subscription CLI"
        case .localBridge:
            "Local bridge"
        }
    }

    var requiresKeychainSecret: Bool {
        self == .requiredAPIKey
    }

    var supportsKeychainSecret: Bool {
        self == .requiredAPIKey || self == .optionalAPIKey
    }

    var isSubscriptionBacked: Bool {
        self == .subscriptionCLI
    }
}

enum AIProviderModelDiscoveryStrategy: String, Codable, CaseIterable, Hashable, Sendable {
    case localServer
    case openAICompatibleModels
    case staticCatalog
    case cliSession
    case bridgeHealth

    var title: String {
        switch self {
        case .localServer:
            "Local server discovery"
        case .openAICompatibleModels:
            "OpenAI-compatible model list"
        case .staticCatalog:
            "Manual catalog"
        case .cliSession:
            "CLI session"
        case .bridgeHealth:
            "Bridge health"
        }
    }
}

struct AIProviderCatalogEntry: Identifiable, Hashable, Sendable {
    var providerKind: AIProviderKind
    var providerMode: AIProviderMode
    var accessMode: ProviderAccessMode
    var privacyScope: ProviderPrivacyScope
    var displayName: String
    var endpoint: String?
    var defaultModelIdentifier: String
    var recommendedModelIdentifiers: [String]
    var capabilities: [ModelCapability]
    var credentialRequirement: AIProviderCredentialRequirement
    var modelDiscoveryStrategy: AIProviderModelDiscoveryStrategy
    var requestBoundary: ProviderRuntimeBoundary

    var id: String {
        "\(providerKind.rawValue):\(providerMode.rawValue):\(accessMode.rawValue)"
    }

    var leavesDeviceDirectly: Bool {
        requestBoundary.leavesDeviceDirectly
    }

    var requiresKeychainSecret: Bool {
        credentialRequirement.requiresKeychainSecret
    }

    var supportsOptionalKeychainSecret: Bool {
        credentialRequirement == .optionalAPIKey
    }

    var supportsSubscriptionCLI: Bool {
        credentialRequirement.isSubscriptionBacked
    }

    var normalizedRecommendedModelIdentifiers: [String] {
        Self.normalizedModelIdentifiers(recommendedModelIdentifiers + [defaultModelIdentifier])
    }

    var modelDescriptors: [AIModelDescriptor] {
        normalizedRecommendedModelIdentifiers.map { modelIdentifier in
            AIModelDescriptor(
                providerKind: providerKind,
                providerMode: providerMode,
                identifier: modelIdentifier,
                displayName: modelIdentifier,
                publisher: providerKind.displayName,
                isAvailableLocally: requestBoundary == .localServer,
                capabilities: Set(capabilities.compactMap(\.aiModelCapability))
            )
        }
    }

    private static func normalizedModelIdentifiers(_ modelIdentifiers: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for modelIdentifier in modelIdentifiers {
            let trimmed = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            normalized.append(trimmed)
        }
        return normalized
    }
}

enum AIKnownProviderCatalog {
    static let entries: [AIProviderCatalogEntry] = [
        AIProviderCatalogEntry(
            providerKind: .ollama,
            providerMode: .nativeAPI,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Local Ollama",
            endpoint: "http://localhost:11434",
            defaultModelIdentifier: "llama3.1",
            recommendedModelIdentifiers: ["llama3.1", "qwen3:14b", "mistral-nemo", "nomic-embed-text"],
            capabilities: [.chat, .streaming, .toolCalling, .embeddings],
            credentialRequirement: .none,
            modelDiscoveryStrategy: .localServer,
            requestBoundary: .localServer
        ),
        AIProviderCatalogEntry(
            providerKind: .lmStudio,
            providerMode: .openAICompatible,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            defaultModelIdentifier: "",
            recommendedModelIdentifiers: [],
            capabilities: [.chat, .streaming, .toolCalling, .embeddings, .openAICompatible, .anthropicCompatible],
            credentialRequirement: .none,
            modelDiscoveryStrategy: .localServer,
            requestBoundary: .localServer
        ),
        AIProviderCatalogEntry(
            providerKind: .openAI,
            providerMode: .apiKey,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "OpenAI API",
            endpoint: "https://api.openai.com/v1",
            defaultModelIdentifier: "gpt-5.5",
            recommendedModelIdentifiers: ["gpt-5.5", "gpt-5.5-mini"],
            capabilities: [.chat, .streaming, .toolCalling, .vision, .reasoning, .structuredOutput],
            credentialRequirement: .requiredAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI
        ),
        AIProviderCatalogEntry(
            providerKind: .anthropic,
            providerMode: .apiKey,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Anthropic API",
            endpoint: "https://api.anthropic.com",
            defaultModelIdentifier: "claude-opus-4.7",
            recommendedModelIdentifiers: ["claude-opus-4.7", "claude-sonnet-4-5"],
            capabilities: [.chat, .streaming, .toolCalling, .vision, .reasoning],
            credentialRequirement: .requiredAPIKey,
            modelDiscoveryStrategy: .staticCatalog,
            requestBoundary: .externalAPI
        ),
        AIProviderCatalogEntry(
            providerKind: .gemini,
            providerMode: .openAICompatible,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Google Gemini API",
            endpoint: "https://generativelanguage.googleapis.com/v1beta/openai",
            defaultModelIdentifier: "gemini-2.5-pro",
            recommendedModelIdentifiers: ["gemini-2.5-pro", "gemini-2.5-flash"],
            capabilities: [.chat, .streaming, .toolCalling, .vision, .openAICompatible],
            credentialRequirement: .requiredAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI
        ),
        AIProviderCatalogEntry(
            providerKind: .xAI,
            providerMode: .openAICompatible,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "xAI API",
            endpoint: "https://api.x.ai/v1",
            defaultModelIdentifier: "grok-4.3",
            recommendedModelIdentifiers: ["grok-4.3"],
            capabilities: [.chat, .streaming, .toolCalling, .reasoning, .openAICompatible],
            credentialRequirement: .requiredAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI
        ),
        AIProviderCatalogEntry(
            providerKind: .mistral,
            providerMode: .openAICompatible,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Mistral API",
            endpoint: "https://api.mistral.ai/v1",
            defaultModelIdentifier: "mistral-large-latest",
            recommendedModelIdentifiers: ["mistral-large-latest", "codestral-latest"],
            capabilities: [.chat, .streaming, .toolCalling, .openAICompatible],
            credentialRequirement: .requiredAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI
        ),
        AIProviderCatalogEntry(
            providerKind: .groq,
            providerMode: .openAICompatible,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Groq API",
            endpoint: "https://api.groq.com/openai/v1",
            defaultModelIdentifier: "llama-3.3-70b-versatile",
            recommendedModelIdentifiers: ["llama-3.3-70b-versatile", "deepseek-r1-distill-llama-70b"],
            capabilities: [.chat, .streaming, .toolCalling, .openAICompatible],
            credentialRequirement: .requiredAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI
        ),
        AIProviderCatalogEntry(
            providerKind: .openRouter,
            providerMode: .openAICompatible,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "OpenRouter",
            endpoint: "https://openrouter.ai/api/v1",
            defaultModelIdentifier: "openai/gpt-5.5",
            recommendedModelIdentifiers: ["openai/gpt-5.5", "anthropic/claude-sonnet-4-5"],
            capabilities: [.chat, .streaming, .toolCalling, .openAICompatible],
            credentialRequirement: .requiredAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI
        ),
        AIProviderCatalogEntry(
            providerKind: .perplexity,
            providerMode: .openAICompatible,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Perplexity API",
            endpoint: "https://api.perplexity.ai",
            defaultModelIdentifier: "sonar-pro",
            recommendedModelIdentifiers: ["sonar-pro", "sonar"],
            capabilities: [.chat, .streaming, .webSearch, .openAICompatible],
            credentialRequirement: .requiredAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI
        ),
        AIProviderCatalogEntry(
            providerKind: .customOpenAICompatible,
            providerMode: .openAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .externalAPI,
            displayName: "Custom OpenAI-compatible",
            endpoint: "http://localhost:8080/v1",
            defaultModelIdentifier: "",
            recommendedModelIdentifiers: [],
            capabilities: [.chat, .streaming, .toolCalling, .openAICompatible],
            credentialRequirement: .optionalAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI
        ),
        AIProviderCatalogEntry(
            providerKind: .chatGPTCLI,
            providerMode: .subscriptionCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: nil,
            defaultModelIdentifier: "chatgpt-subscription",
            recommendedModelIdentifiers: ["chatgpt-subscription"],
            capabilities: [.chat, .streaming],
            credentialRequirement: .subscriptionCLI,
            modelDiscoveryStrategy: .cliSession,
            requestBoundary: .localCLI
        ),
        AIProviderCatalogEntry(
            providerKind: .claudeCodeCLI,
            providerMode: .subscriptionCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "Claude Code CLI",
            endpoint: nil,
            defaultModelIdentifier: "claude-subscription",
            recommendedModelIdentifiers: ["claude-subscription"],
            capabilities: [.chat, .streaming],
            credentialRequirement: .subscriptionCLI,
            modelDiscoveryStrategy: .cliSession,
            requestBoundary: .localCLI
        ),
        AIProviderCatalogEntry(
            providerKind: .vercelAISDKBridge,
            providerMode: .aiSDKBridge,
            accessMode: .aiSDKBridge,
            privacyScope: .bridgeService,
            displayName: "Vercel AI SDK Bridge",
            endpoint: "http://localhost:4177",
            defaultModelIdentifier: "",
            recommendedModelIdentifiers: [],
            capabilities: [.chat, .streaming, .toolCalling, .embeddings, .structuredOutput],
            credentialRequirement: .localBridge,
            modelDiscoveryStrategy: .bridgeHealth,
            requestBoundary: .localBridge
        )
    ]

    static func entry(for providerKind: AIProviderKind) -> AIProviderCatalogEntry? {
        entries.first { $0.providerKind == providerKind }
    }

    static func entry(for providerKind: LLMProviderKind) -> AIProviderCatalogEntry? {
        entry(for: AIProviderKind(providerKind))
    }

    static func recommendedModelIdentifiers(for providerKind: AIProviderKind) -> [String] {
        entry(for: providerKind)?.normalizedRecommendedModelIdentifiers ?? []
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

private extension ModelCapability {
    var aiModelCapability: AIModelCapability? {
        switch self {
        case .chat:
            .chat
        case .streaming:
            .streaming
        case .toolCalling:
            .toolUse
        case .embeddings:
            .embeddings
        case .vision:
            .vision
        case .reasoning:
            .reasoning
        case .structuredOutput:
            .structuredOutput
        case .webSearch:
            .retrieval
        case .imageGeneration, .openAICompatible, .anthropicCompatible:
            nil
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

extension ProviderAccessMode {
    init(_ providerMode: AIProviderMode) {
        switch providerMode {
        case .nativeAPI:
            self = .localServer
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
