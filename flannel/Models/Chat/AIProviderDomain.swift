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

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
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

    nonisolated var isLocalProvider: Bool {
        switch self {
        case .ollama, .lmStudio:
            true
        case .openAI, .anthropic, .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity,
             .customOpenAICompatible, .chatGPTCLI, .claudeCodeCLI, .vercelAISDKBridge:
            false
        }
    }

    nonisolated var defaultBaseURL: URL? {
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

    nonisolated init(
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
        [
            providerKind.rawValue,
            providerMode.rawValue,
            endpoint?.absoluteString ?? "default"
        ].joined(separator: ":")
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

    nonisolated var title: String {
        switch self {
        case .none:
            "No credential"
        case .requiredAPIKey:
            "API key required"
        case .optionalAPIKey:
            "Optional API key"
        case .subscriptionCLI:
            "Account CLI"
        case .localBridge:
            "Local bridge"
        }
    }

    nonisolated var requiresKeychainSecret: Bool {
        self == .requiredAPIKey
    }

    nonisolated var supportsKeychainSecret: Bool {
        self == .requiredAPIKey || self == .optionalAPIKey
    }

    nonisolated var isSubscriptionBacked: Bool {
        self == .subscriptionCLI
    }
}

enum AIProviderModelDiscoveryStrategy: String, Codable, CaseIterable, Hashable, Sendable {
    case localServer
    case openAICompatibleModels
    case anthropicModels
    case staticCatalog
    case cliSession
    case bridgeHealth

    var title: String {
        switch self {
        case .localServer:
            "Local server discovery"
        case .openAICompatibleModels:
            "OpenAI-compatible model list"
        case .anthropicModels:
            "Anthropic Models API"
        case .staticCatalog:
            "Manual catalog"
        case .cliSession:
            "CLI session"
        case .bridgeHealth:
            "Bridge health"
        }
    }
}

enum AIProviderRuntimeInterface: String, Codable, CaseIterable, Hashable, Sendable {
    case nativeAPI
    case openAICompatible
    case anthropicCompatible
    case subscriptionCLI
    case aiSDKBridge

    nonisolated var title: String {
        switch self {
        case .nativeAPI:
            "Official or native API"
        case .openAICompatible:
            "OpenAI-compatible"
        case .anthropicCompatible:
            "Anthropic-compatible"
        case .subscriptionCLI:
            "Account CLI"
        case .aiSDKBridge:
            "AI SDK bridge"
        }
    }
}

enum AIProviderDiscoveryCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case nativeModelCatalog
    case runningModelInventory
    case openAICompatibleModelList
    case bridgeHealthEndpoint

    nonisolated var title: String {
        switch self {
        case .nativeModelCatalog:
            "Native model catalog"
        case .runningModelInventory:
            "Running model inventory"
        case .openAICompatibleModelList:
            "OpenAI-compatible model list"
        case .bridgeHealthEndpoint:
            "Bridge health endpoint"
        }
    }
}

enum AIProviderCLIOutputDecoding: String, Codable, CaseIterable, Hashable, Sendable {
    case plainText
    case codexJSONLines
    case claudeJSON
    case claudeStreamJSON
}

struct AIProviderCLIContract: Hashable, Sendable {
    var preferredExecutable: String
    var recommendedCommand: String
    var statusCommandArguments: [String]
    var defaultOutputDecoding: AIProviderCLIOutputDecoding
    var supportsPromptViaStdin: Bool
    var supportsPromptPlaceholderArguments: Bool
}

struct AIProviderSourceReference: Identifiable, Hashable, Sendable {
    var label: String
    var url: String

    nonisolated var id: String {
        "\(label)::\(url)"
    }
}

enum AIProviderCredentialPath: String, Codable, CaseIterable, Hashable, Sendable {
    case noCredential
    case officialAPIKey
    case optionalEndpointKey
    case localAccountCLI
    case localBridge

    nonisolated var title: String {
        switch self {
        case .noCredential:
            "No credential"
        case .officialAPIKey:
            "Official API key"
        case .optionalEndpointKey:
            "Endpoint key"
        case .localAccountCLI:
            "Local account CLI"
        case .localBridge:
            "Local bridge"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .noCredential:
            "lock"
        case .officialAPIKey, .optionalEndpointKey:
            "key"
        case .localAccountCLI:
            "terminal"
        case .localBridge:
            "point.3.connected.trianglepath.dotted"
        }
    }
}

struct AIProviderModeGuide: Identifiable, Hashable, Sendable {
    var providerKind: AIProviderKind
    var providerMode: AIProviderMode
    var accessMode: ProviderAccessMode
    var credentialPath: AIProviderCredentialPath
    var title: String
    var credentialBoundary: String
    var requestBoundary: String
    var setupSummary: String
    var verificationSummary: String
    var command: String?
    var promptTransport: String?
    var outputContract: String?
    var sourceReferences: [AIProviderSourceReference]

    nonisolated var id: String {
        "\(providerKind.rawValue):\(providerMode.rawValue):\(credentialPath.rawValue)"
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
    var embeddingModelIdentifiers: [String] = []
    var capabilities: [ModelCapability]
    var credentialRequirement: AIProviderCredentialRequirement
    var modelDiscoveryStrategy: AIProviderModelDiscoveryStrategy
    var requestBoundary: ProviderRuntimeBoundary
    var primaryRuntimeInterface: AIProviderRuntimeInterface
    var supportedRuntimeInterfaces: [AIProviderRuntimeInterface]
    var discoveryCapabilities: [AIProviderDiscoveryCapability]
    var cliContract: AIProviderCLIContract?
    var sourceReferences: [AIProviderSourceReference]

    nonisolated var id: String {
        "\(providerKind.rawValue):\(providerMode.rawValue):\(accessMode.rawValue)"
    }

    nonisolated var leavesDeviceDirectly: Bool {
        requestBoundary.leavesDeviceDirectly
    }

    nonisolated var requiresKeychainSecret: Bool {
        credentialRequirement.requiresKeychainSecret
    }

    nonisolated var supportsOptionalKeychainSecret: Bool {
        credentialRequirement == .optionalAPIKey
    }

    nonisolated var supportsSubscriptionCLI: Bool {
        credentialRequirement.isSubscriptionBacked
    }

    nonisolated var usesOfficialAPI: Bool {
        primaryRuntimeInterface == .nativeAPI && requestBoundary == .externalAPI
    }

    nonisolated var supportsOpenAICompatibleRuntime: Bool {
        supportedRuntimeInterfaces.contains(.openAICompatible)
    }

    nonisolated var supportsAnthropicCompatibleRuntime: Bool {
        supportedRuntimeInterfaces.contains(.anthropicCompatible)
    }

    nonisolated var supportsNativeModelCatalogDiscovery: Bool {
        discoveryCapabilities.contains(.nativeModelCatalog)
    }

    nonisolated var supportsRunningModelInventory: Bool {
        discoveryCapabilities.contains(.runningModelInventory)
    }

    nonisolated var supportsOpenAICompatibleModelDiscovery: Bool {
        discoveryCapabilities.contains(.openAICompatibleModelList)
    }

    nonisolated var supportsBridgeHealthDiscovery: Bool {
        discoveryCapabilities.contains(.bridgeHealthEndpoint)
    }

    nonisolated var recommendedCLICommand: String? {
        cliContract?.recommendedCommand
    }

    nonisolated var modeGuide: AIProviderModeGuide {
        let credentialPath = Self.credentialPath(for: credentialRequirement)
        let requestBoundary = requestBoundaryGuide
        let command = cliContract?.recommendedCommand
        return AIProviderModeGuide(
            providerKind: providerKind,
            providerMode: providerMode,
            accessMode: accessMode,
            credentialPath: credentialPath,
            title: "\(displayName) route contract",
            credentialBoundary: credentialBoundaryGuide(credentialPath: credentialPath),
            requestBoundary: requestBoundary,
            setupSummary: setupGuide(credentialPath: credentialPath),
            verificationSummary: verificationGuide(credentialPath: credentialPath),
            command: command,
            promptTransport: promptTransportGuide,
            outputContract: outputContractGuide,
            sourceReferences: sourceReferences
        )
    }

    nonisolated var normalizedRecommendedModelIdentifiers: [String] {
        Self.normalizedModelIdentifiers(recommendedModelIdentifiers + [defaultModelIdentifier])
    }

    nonisolated var normalizedEmbeddingModelIdentifiers: [String] {
        Self.normalizedModelIdentifiers(embeddingModelIdentifiers)
    }

    nonisolated var modelDescriptors: [AIModelDescriptor] {
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

    nonisolated private static func normalizedModelIdentifiers(_ modelIdentifiers: [String]) -> [String] {
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

    nonisolated private static func credentialPath(
        for requirement: AIProviderCredentialRequirement
    ) -> AIProviderCredentialPath {
        switch requirement {
        case .none:
            .noCredential
        case .requiredAPIKey:
            .officialAPIKey
        case .optionalAPIKey:
            .optionalEndpointKey
        case .subscriptionCLI:
            .localAccountCLI
        case .localBridge:
            .localBridge
        }
    }

    nonisolated private func credentialBoundaryGuide(credentialPath: AIProviderCredentialPath) -> String {
        switch credentialPath {
        case .noCredential:
            return "No provider account is required. Flannel talks to a local server on this Mac or loopback network."
        case .officialAPIKey:
            return "Uses a provider API key saved in macOS Keychain. Subscription sign-in to a consumer app does not satisfy this route."
        case .optionalEndpointKey:
            return "Uses the endpoint's own key policy. If a key is needed, Flannel stores that endpoint key in macOS Keychain."
        case .localAccountCLI:
            return "Uses the account already authenticated inside the local CLI. Flannel does not store a provider API key for this route."
        case .localBridge:
            return "Uses a local bridge process. Provider credentials stay owned by the bridge, not by this row."
        }
    }

    nonisolated private var requestBoundaryGuide: String {
        switch requestBoundary {
        case .localServer:
            "Requests stay on the configured local server endpoint."
        case .localCLI:
            "Requests are handed to a local command-line process, which may use its own signed-in account or network policy."
        case .externalAPI:
            "Requests leave this Mac for the configured hosted provider API."
        case .localBridge:
            "Requests go to the configured local bridge endpoint, and the bridge owns downstream provider calls."
        }
    }

    nonisolated private func setupGuide(credentialPath: AIProviderCredentialPath) -> String {
        switch credentialPath {
        case .noCredential:
            return "Start the local provider, run discovery, then select an installed chat model."
        case .officialAPIKey:
            return "Create the provider API route, save its BYOK key to Keychain, then pick a supported model."
        case .optionalEndpointKey:
            return "Confirm the base URL, decide whether the endpoint needs a key, then run model discovery or enter a model id."
        case .localAccountCLI:
            let command = recommendedCLICommand ?? cliContract?.preferredExecutable ?? "the CLI command"
            return "Install and sign in to the CLI, keep the command direct argv-style, then use `\(command)` as the route command."
        case .localBridge:
            return "Start the local bridge, confirm its health endpoint, then select a model exposed by the bridge."
        }
    }

    nonisolated private func verificationGuide(credentialPath: AIProviderCredentialPath) -> String {
        switch credentialPath {
        case .noCredential:
            return "Readiness checks the local endpoint and discovered model inventory."
        case .officialAPIKey:
            return "Readiness verifies Keychain access, model configuration, and a provider-compatible model or health call."
        case .optionalEndpointKey:
            return "Readiness verifies endpoint shape, optional Keychain access, and the configured model route."
        case .localAccountCLI:
            if let statusArguments = cliContract?.statusCommandArguments,
               !statusArguments.isEmpty {
                let command = ([cliContract?.preferredExecutable].compactMap { $0 } + statusArguments).joined(separator: " ")
                return "Readiness resolves the executable and runs `\(command)` before chat uses the configured command."
            }
            return "Readiness resolves the executable and runs a local CLI smoke check before routing chat."
        case .localBridge:
            return "Readiness checks the bridge health endpoint before routing chat."
        }
    }

    nonisolated private var promptTransportGuide: String? {
        guard let cliContract else { return nil }
        if cliContract.supportsPromptViaStdin {
            return "Prompt can be sent through stdin or placeholders."
        }
        if cliContract.supportsPromptPlaceholderArguments {
            return "Prompt is supplied through a print-mode argument or placeholder."
        }
        return "Prompt transport is defined by the configured CLI command."
    }

    nonisolated private var outputContractGuide: String? {
        guard let decoding = cliContract?.defaultOutputDecoding else { return nil }
        switch decoding {
        case .plainText:
            return "Flannel reads plain stdout as assistant text."
        case .codexJSONLines:
            return "Flannel expects Codex JSONL events and extracts assistant message text."
        case .claudeJSON:
            return "Flannel expects one Claude JSON response and extracts assistant content."
        case .claudeStreamJSON:
            return "Flannel expects Claude stream-json events and extracts assistant deltas."
        }
    }
}

enum AIKnownProviderCatalog {
    nonisolated static let entries: [AIProviderCatalogEntry] = [
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
            requestBoundary: .localServer,
            primaryRuntimeInterface: .nativeAPI,
            supportedRuntimeInterfaces: [.nativeAPI, .openAICompatible],
            discoveryCapabilities: [.nativeModelCatalog, .runningModelInventory],
            cliContract: nil,
            sourceReferences: [
                AIProviderSourceReference(label: "Ollama API", url: "https://docs.ollama.com/api"),
                AIProviderSourceReference(label: "Ollama OpenAI compatibility", url: "https://docs.ollama.com/api/openai-compatibility")
            ]
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
            requestBoundary: .localServer,
            primaryRuntimeInterface: .openAICompatible,
            supportedRuntimeInterfaces: [.nativeAPI, .openAICompatible, .anthropicCompatible],
            discoveryCapabilities: [.nativeModelCatalog, .openAICompatibleModelList],
            cliContract: nil,
            sourceReferences: [
                AIProviderSourceReference(label: "LM Studio REST API", url: "https://lmstudio.ai/docs/developer/rest"),
                AIProviderSourceReference(label: "LM Studio local server", url: "https://lmstudio.ai/docs/developer/core/server"),
                AIProviderSourceReference(label: "LM Studio model list", url: "https://lmstudio.ai/docs/developer/openai-compat/models")
            ]
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
            embeddingModelIdentifiers: ["text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002"],
            capabilities: [.chat, .streaming, .toolCalling, .embeddings, .vision, .reasoning, .structuredOutput],
            credentialRequirement: .requiredAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI,
            primaryRuntimeInterface: .nativeAPI,
            supportedRuntimeInterfaces: [.nativeAPI],
            discoveryCapabilities: [.openAICompatibleModelList],
            cliContract: nil,
            sourceReferences: [
                AIProviderSourceReference(label: "OpenAI Responses API", url: "https://platform.openai.com/docs/api-reference/responses"),
                AIProviderSourceReference(label: "OpenAI embeddings", url: "https://developers.openai.com/api/docs/guides/embeddings")
            ]
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
            modelDiscoveryStrategy: .anthropicModels,
            requestBoundary: .externalAPI,
            primaryRuntimeInterface: .nativeAPI,
            supportedRuntimeInterfaces: [.nativeAPI],
            discoveryCapabilities: [],
            cliContract: nil,
            sourceReferences: [
                AIProviderSourceReference(label: "Anthropic Messages API", url: "https://platform.claude.com/docs/en/api/messages"),
                AIProviderSourceReference(label: "Anthropic Models API", url: "https://platform.claude.com/docs/en/api/models/list")
            ]
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
            embeddingModelIdentifiers: ["gemini-embedding-2", "gemini-embedding-001"],
            capabilities: [.chat, .streaming, .toolCalling, .embeddings, .vision, .openAICompatible],
            credentialRequirement: .requiredAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI,
            primaryRuntimeInterface: .openAICompatible,
            supportedRuntimeInterfaces: [.openAICompatible],
            discoveryCapabilities: [.openAICompatibleModelList],
            cliContract: nil,
            sourceReferences: [
                AIProviderSourceReference(label: "Gemini embeddings", url: "https://ai.google.dev/gemini-api/docs/embeddings")
            ]
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
            requestBoundary: .externalAPI,
            primaryRuntimeInterface: .openAICompatible,
            supportedRuntimeInterfaces: [.openAICompatible],
            discoveryCapabilities: [.openAICompatibleModelList],
            cliContract: nil,
            sourceReferences: []
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
            embeddingModelIdentifiers: ["mistral-embed"],
            capabilities: [.chat, .streaming, .toolCalling, .embeddings, .openAICompatible],
            credentialRequirement: .requiredAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI,
            primaryRuntimeInterface: .openAICompatible,
            supportedRuntimeInterfaces: [.openAICompatible],
            discoveryCapabilities: [.openAICompatibleModelList],
            cliContract: nil,
            sourceReferences: [
                AIProviderSourceReference(label: "Mistral embeddings", url: "https://docs.mistral.ai/api/endpoint/embeddings")
            ]
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
            requestBoundary: .externalAPI,
            primaryRuntimeInterface: .openAICompatible,
            supportedRuntimeInterfaces: [.openAICompatible],
            discoveryCapabilities: [.openAICompatibleModelList],
            cliContract: nil,
            sourceReferences: []
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
            requestBoundary: .externalAPI,
            primaryRuntimeInterface: .openAICompatible,
            supportedRuntimeInterfaces: [.openAICompatible],
            discoveryCapabilities: [.openAICompatibleModelList],
            cliContract: nil,
            sourceReferences: []
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
            embeddingModelIdentifiers: ["pplx-embed-v1-0.6b", "pplx-embed-v1-4b"],
            capabilities: [.chat, .streaming, .webSearch, .embeddings, .openAICompatible],
            credentialRequirement: .requiredAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI,
            primaryRuntimeInterface: .openAICompatible,
            supportedRuntimeInterfaces: [.openAICompatible],
            discoveryCapabilities: [.openAICompatibleModelList],
            cliContract: nil,
            sourceReferences: [
                AIProviderSourceReference(label: "Perplexity embeddings", url: "https://docs.perplexity.ai/docs/embeddings/quickstart"),
                AIProviderSourceReference(label: "Perplexity create embeddings", url: "https://docs.perplexity.ai/api-reference/embeddings-post")
            ]
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
            capabilities: [.chat, .streaming, .toolCalling, .embeddings, .openAICompatible],
            credentialRequirement: .optionalAPIKey,
            modelDiscoveryStrategy: .openAICompatibleModels,
            requestBoundary: .externalAPI,
            primaryRuntimeInterface: .openAICompatible,
            supportedRuntimeInterfaces: [.openAICompatible],
            discoveryCapabilities: [.openAICompatibleModelList],
            cliContract: nil,
            sourceReferences: []
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
            requestBoundary: .localCLI,
            primaryRuntimeInterface: .subscriptionCLI,
            supportedRuntimeInterfaces: [.subscriptionCLI],
            discoveryCapabilities: [],
            cliContract: AIProviderCLIContract(
                preferredExecutable: "codex",
                recommendedCommand: "codex exec --json -",
                statusCommandArguments: ["login", "status"],
                defaultOutputDecoding: .codexJSONLines,
                supportsPromptViaStdin: true,
                supportsPromptPlaceholderArguments: true
            ),
            sourceReferences: [
                AIProviderSourceReference(label: "Codex CLI reference", url: "https://developers.openai.com/codex/cli/reference"),
                AIProviderSourceReference(label: "Codex non-interactive mode", url: "https://developers.openai.com/codex/noninteractive"),
                AIProviderSourceReference(label: "Codex authentication and subscription access", url: "https://developers.openai.com/codex/auth")
            ]
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
            requestBoundary: .localCLI,
            primaryRuntimeInterface: .subscriptionCLI,
            supportedRuntimeInterfaces: [.subscriptionCLI],
            discoveryCapabilities: [],
            cliContract: AIProviderCLIContract(
                preferredExecutable: "claude",
                recommendedCommand: "claude -p --output-format stream-json --verbose",
                statusCommandArguments: ["auth", "status", "--text"],
                defaultOutputDecoding: .claudeStreamJSON,
                supportsPromptViaStdin: false,
                supportsPromptPlaceholderArguments: true
            ),
            sourceReferences: [
                AIProviderSourceReference(label: "Claude Code CLI reference", url: "https://code.claude.com/docs/en/cli-reference"),
                AIProviderSourceReference(label: "Claude Code authentication", url: "https://code.claude.com/docs/en/iam"),
                AIProviderSourceReference(label: "Claude Code data usage", url: "https://code.claude.com/docs/en/data-usage")
            ]
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
            capabilities: [.chat, .streaming, .toolCalling, .structuredOutput],
            credentialRequirement: .localBridge,
            modelDiscoveryStrategy: .bridgeHealth,
            requestBoundary: .localBridge,
            primaryRuntimeInterface: .aiSDKBridge,
            supportedRuntimeInterfaces: [.aiSDKBridge],
            discoveryCapabilities: [.bridgeHealthEndpoint],
            cliContract: nil,
            sourceReferences: [
                AIProviderSourceReference(label: "Vercel AI SDK", url: "https://vercel.com/docs/ai-sdk")
            ]
        )
    ]

    nonisolated static func entry(for providerKind: AIProviderKind) -> AIProviderCatalogEntry? {
        entries.first { $0.providerKind == providerKind }
    }

    nonisolated static func entry(for providerKind: LLMProviderKind) -> AIProviderCatalogEntry? {
        entry(for: AIProviderKind(providerKind))
    }

    nonisolated static func recommendedModelIdentifiers(for providerKind: AIProviderKind) -> [String] {
        entry(for: providerKind)?.normalizedRecommendedModelIdentifiers ?? []
    }
}

extension AIProviderKind {
    nonisolated init(_ providerKind: LLMProviderKind) {
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

extension ProviderConfiguration {
    nonisolated var providerCatalogEntry: AIProviderCatalogEntry? {
        AIKnownProviderCatalog.entry(for: kind)
    }
}

private extension ModelCapability {
    nonisolated var aiModelCapability: AIModelCapability? {
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
