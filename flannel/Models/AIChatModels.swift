//
//  AIChatModels.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

enum ProviderAccessMode: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case localServer
    case apiKey
    case subscriptionCLI
    case openAICompatible
    case anthropicCompatible
    case aiSDKBridge

    var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .localServer:
            "Local Server"
        case .apiKey:
            "API Key"
        case .subscriptionCLI:
            "Account CLI"
        case .openAICompatible:
            "OpenAI Compatible"
        case .anthropicCompatible:
            "Anthropic Compatible"
        case .aiSDKBridge:
            "AI SDK Bridge"
        }
    }

    var detail: String {
        switch self {
        case .localServer:
            "Runs against a loopback model server such as Ollama or LM Studio."
        case .apiKey:
            "Uses the provider's official API with a key stored in Keychain."
        case .subscriptionCLI:
            "Runs through a locally authenticated command-line tool; credentials stay inside that CLI."
        case .openAICompatible:
            "Uses a custom endpoint that implements OpenAI-compatible routes."
        case .anthropicCompatible:
            "Uses a custom endpoint that implements Anthropic-compatible messages routes."
        case .aiSDKBridge:
            "Uses an optional local TypeScript bridge for Vercel AI SDK workflows."
        }
    }
}

enum ProviderReadinessStrategy: String, Codable, Hashable, Sendable {
    case staticConfiguration
    case localModelDiscovery
    case openAICompatibleModels
    case anthropicModels
    case cliCommandResolution
    case aiSDKBridgeHealth
}

enum ProviderChatTransportKind: String, Codable, Hashable, Sendable {
    case ollamaNative
    case openAIResponses
    case openAICompatible
    case anthropicMessages
    case subscriptionCLI
    case aiSDKBridge
    case unsupported

    nonisolated var isImplemented: Bool {
        self != .unsupported
    }
}

struct ProviderRuntimePolicy: Hashable, Sendable {
    var readinessStrategy: ProviderReadinessStrategy
    var chatTransport: ProviderChatTransportKind
    var requiresEndpoint: Bool
    var requiresHTTPSForRemoteEndpoint: Bool
    var requiresKeychainSecret: Bool
    var supportsOptionalKeychainSecret: Bool

    nonisolated var supportsChatTransport: Bool {
        chatTransport.isImplemented
    }

    nonisolated init(
        readinessStrategy: ProviderReadinessStrategy,
        chatTransport: ProviderChatTransportKind,
        requiresEndpoint: Bool,
        requiresHTTPSForRemoteEndpoint: Bool,
        requiresKeychainSecret: Bool,
        supportsOptionalKeychainSecret: Bool
    ) {
        self.readinessStrategy = readinessStrategy
        self.chatTransport = chatTransport
        self.requiresEndpoint = requiresEndpoint
        self.requiresHTTPSForRemoteEndpoint = requiresHTTPSForRemoteEndpoint
        self.requiresKeychainSecret = requiresKeychainSecret
        self.supportsOptionalKeychainSecret = supportsOptionalKeychainSecret
    }
}

enum ProviderPrivacyScope: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case localOnly
    case externalAPI
    case localCLI
    case bridgeService

    var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .localOnly:
            "Local Only"
        case .externalAPI:
            "External API"
        case .localCLI:
            "Local CLI"
        case .bridgeService:
            "Local Bridge"
        }
    }
}

enum ProviderRuntimeBoundary: String, Codable, CaseIterable, Hashable, Sendable {
    case localServer
    case localCLI
    case externalAPI
    case localBridge

    var title: String {
        switch self {
        case .localServer:
            "Local Server"
        case .localCLI:
            "Local CLI"
        case .externalAPI:
            "External API"
        case .localBridge:
            "Local Bridge"
        }
    }

    var detail: String {
        switch self {
        case .localServer:
            "Requests stay inside a loopback or local-network model server configured by the user."
        case .localCLI:
            "Requests run through a locally authenticated command-line session."
        case .externalAPI:
            "Requests leave this Mac for a BYOK hosted provider endpoint."
        case .localBridge:
            "Requests go to a local bridge process that owns its downstream provider routing."
        }
    }

    var systemImage: String {
        switch self {
        case .localServer:
            "desktopcomputer"
        case .localCLI:
            "terminal"
        case .externalAPI:
            "network"
        case .localBridge:
            "point.3.connected.trianglepath.dotted"
        }
    }

    nonisolated var leavesDeviceDirectly: Bool {
        self == .externalAPI
    }
}

enum ProviderModeFamily: String, CaseIterable, Identifiable, Hashable, Sendable {
    case localModels
    case openAIChatGPT
    case anthropicClaude
    case hostedAPIs
    case customEndpoints

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localModels:
            "Local models"
        case .openAIChatGPT:
            "OpenAI / ChatGPT"
        case .anthropicClaude:
            "Anthropic / Claude"
        case .hostedAPIs:
            "Hosted BYOK APIs"
        case .customEndpoints:
            "Custom and bridge"
        }
    }

    var detail: String {
        switch self {
        case .localModels:
            "Ollama and LM Studio stay on local model servers."
        case .openAIChatGPT:
            "Choose official OpenAI API keys or a locally authenticated ChatGPT/Codex CLI route."
        case .anthropicClaude:
            "Choose official Anthropic API keys or a locally authenticated Claude Code CLI route."
        case .hostedAPIs:
            "Gemini, xAI, Mistral, Groq, OpenRouter, and Perplexity use bring-your-own API keys."
        case .customEndpoints:
            "Use OpenAI-compatible endpoints or an optional local AI SDK bridge."
        }
    }

    var modeChoicePrompt: String? {
        switch self {
        case .openAIChatGPT:
            "Choose one access route. OpenAI Platform API keys, ChatGPT sign-in, and Codex CLI auth stay separate."
        case .anthropicClaude:
            "Choose one access route. Anthropic Console API keys and Claude Code account sign-in stay separate."
        case .localModels, .hostedAPIs, .customEndpoints:
            nil
        }
    }

    var icon: String {
        switch self {
        case .localModels:
            "desktopcomputer"
        case .openAIChatGPT:
            "sparkles"
        case .anthropicClaude:
            "text.bubble"
        case .hostedAPIs:
            "key"
        case .customEndpoints:
            "point.3.connected.trianglepath.dotted"
        }
    }

    func contains(_ provider: ProviderConfiguration) -> Bool {
        switch self {
        case .localModels:
            provider.kind == .ollama || provider.kind == .lmStudio
        case .openAIChatGPT:
            provider.kind == .openAI || provider.kind == .chatGPTCLI
        case .anthropicClaude:
            provider.kind == .anthropic || provider.kind == .claudeCodeCLI
        case .hostedAPIs:
            provider.kind == .gemini
                || provider.kind == .xAI
                || provider.kind == .mistral
                || provider.kind == .groq
                || provider.kind == .openRouter
                || provider.kind == .perplexity
        case .customEndpoints:
            provider.kind == .customOpenAICompatible || provider.kind == .vercelAISDKBridge
        }
    }
}

extension ProviderConfiguration {
    nonisolated var runtimeBoundary: ProviderRuntimeBoundary {
        switch accessMode {
        case .localServer:
            .localServer
        case .subscriptionCLI:
            .localCLI
        case .aiSDKBridge:
            .localBridge
        case .apiKey, .anthropicCompatible:
            .externalAPI
        case .openAICompatible:
            isLoopbackEndpoint ? .localServer : .externalAPI
        }
    }

    nonisolated var runtimePolicy: ProviderRuntimePolicy {
        let boundary = runtimeBoundary
        return ProviderRuntimePolicy(
            readinessStrategy: runtimeReadinessStrategy,
            chatTransport: runtimeChatTransport,
            requiresEndpoint: runtimeRequiresEndpoint,
            requiresHTTPSForRemoteEndpoint: boundary == .externalAPI || accessMode == .apiKey,
            requiresKeychainSecret: accessMode == .apiKey || accessMode == .anthropicCompatible,
            supportsOptionalKeychainSecret: accessMode == .openAICompatible
        )
    }

    nonisolated private var runtimeReadinessStrategy: ProviderReadinessStrategy {
        switch accessMode {
        case .localServer where kind == .ollama || kind == .lmStudio:
            .localModelDiscovery
        case .apiKey where kind == .anthropic:
            .anthropicModels
        case .openAICompatible:
            .openAICompatibleModels
        case .apiKey where kind.usesOpenAICompatibleReadiness:
            .openAICompatibleModels
        case .subscriptionCLI where kind == .chatGPTCLI || kind == .claudeCodeCLI:
            .cliCommandResolution
        case .aiSDKBridge:
            .aiSDKBridgeHealth
        case .localServer, .apiKey, .subscriptionCLI, .anthropicCompatible:
            .staticConfiguration
        }
    }

    nonisolated private var runtimeChatTransport: ProviderChatTransportKind {
        if accessMode == .subscriptionCLI {
            return kind == .chatGPTCLI || kind == .claudeCodeCLI ? .subscriptionCLI : .unsupported
        }

        switch kind {
        case .ollama:
            return .ollamaNative
        case .openAI:
            return .openAIResponses
        case .lmStudio, .customOpenAICompatible, .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            return .openAICompatible
        case .anthropic:
            return .anthropicMessages
        case .vercelAISDKBridge:
            return .aiSDKBridge
        case .chatGPTCLI, .claudeCodeCLI:
            return .unsupported
        }
    }

    nonisolated private var runtimeRequiresEndpoint: Bool {
        switch accessMode {
        case .localServer, .apiKey, .openAICompatible, .anthropicCompatible, .aiSDKBridge:
            true
        case .subscriptionCLI:
            false
        }
    }

    nonisolated private var isLoopbackEndpoint: Bool {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased() else {
            return false
        }

        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
    }

    var modeFamily: ProviderModeFamily {
        ProviderModeFamily.allCases.first { $0.contains(self) } ?? .customEndpoints
    }

    var providerModeChoiceTitle: String {
        switch kind {
        case .openAI:
            return "OpenAI API"
        case .chatGPTCLI:
            return "ChatGPT/Codex CLI"
        case .anthropic:
            return "Anthropic API"
        case .claudeCodeCLI:
            return "Claude Code CLI"
        case .ollama:
            return "Ollama"
        case .lmStudio:
            return "LM Studio"
        case .customOpenAICompatible:
            return "OpenAI-compatible endpoint"
        case .vercelAISDKBridge:
            return "AI SDK bridge"
        case .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            return "\(kind.title) API"
        }
    }

    var providerModeChoiceDetail: String {
        let model = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelText = model.isEmpty ? "No model" : model
        return "\(accessMode.title) • \(privacyScope.title) • \(modelText)"
    }

    var providerPickerRouteSummary: String {
        let model = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelText = model.isEmpty ? "No model" : model
        return "\(providerModeBoundaryBadge) • \(runtimeBoundary.title) • \(modelText)"
    }

    func providerPickerStatusLine(
        readinessText: String,
        routingPolicy: ProviderRoutingPolicy
    ) -> String {
        let routeSummary = providerPickerRouteSummary
        guard routingPolicy != .selectedProvider else {
            return "\(routeSummary) • \(readinessText)"
        }
        return "\(routingPolicy.title) • \(routeSummary) • \(readinessText)"
    }

    var providerPickerAccessibilityLabel: String {
        switch kind {
        case .ollama, .lmStudio:
            "\(providerModeChoiceTitle), \(providerPickerRouteSummary)"
        default:
            "\(modeBoundaryTitle), \(providerPickerRouteSummary)"
        }
    }

    var providerModeSelectionTitle: String {
        switch kind {
        case .openAI:
            return "Use OpenAI API key"
        case .chatGPTCLI:
            return "Use ChatGPT/Codex CLI"
        case .anthropic:
            return "Use Anthropic API key"
        case .claudeCodeCLI:
            return "Use Claude Code CLI"
        case .ollama:
            return "Use Ollama local server"
        case .lmStudio:
            return "Use LM Studio local server"
        case .customOpenAICompatible:
            return "Use OpenAI-compatible endpoint"
        case .vercelAISDKBridge:
            return "Use local AI SDK bridge"
        case .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            return "Use \(kind.title) API key"
        }
    }

    var providerModePickerTitle: String {
        switch kind {
        case .openAI:
            return "OpenAI API key"
        case .chatGPTCLI:
            return "ChatGPT subscription via Codex CLI"
        case .anthropic:
            return "Anthropic API key"
        case .claudeCodeCLI:
            return "Claude subscription via Claude Code"
        case .ollama:
            return "Ollama local server"
        case .lmStudio:
            return "LM Studio local server"
        case .customOpenAICompatible:
            return "OpenAI-compatible endpoint"
        case .vercelAISDKBridge:
            return "Local AI SDK bridge"
        case .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            return "\(kind.title) API key"
        }
    }

    var providerModePickerSummary: String {
        let model = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelText = model.isEmpty ? "No model" : model
        return "\(providerModeBoundaryBadge) • \(runtimeBoundary.title) • \(modelText)"
    }

    var providerModeSelectionDetail: String {
        switch kind {
        case .openAI:
            return "Official OpenAI API route. Requires a Keychain API key; it is not ChatGPT or Codex CLI access."
        case .chatGPTCLI:
            return "Local account CLI route. Uses the configured Codex/ChatGPT command; ChatGPT plan sign-in or Codex API-key auth stays inside that CLI."
        case .anthropic:
            return "Official Anthropic API route. Requires a Keychain API key; it is not Claude Code account access."
        case .claudeCodeCLI:
            return "Local Claude Code account route. Uses Claude Code print mode; it does not read an Anthropic Console key from this row."
        case .ollama:
            return "Local Ollama chat route using the selected discovered or manual model."
        case .lmStudio:
            return "Local LM Studio route through its OpenAI-compatible server."
        case .customOpenAICompatible:
            return "Custom OpenAI-compatible base URL with optional Keychain API key."
        case .vercelAISDKBridge:
            return "Local bridge route for AI SDK experiments and provider abstraction."
        case .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            return "Hosted BYOK route using this provider's configured endpoint and Keychain API key."
        }
    }

    var providerModeBoundaryBadge: String {
        switch accessMode {
        case .apiKey:
            return "API key"
        case .subscriptionCLI:
            return "Account CLI"
        case .localServer:
            return "Local server"
        case .openAICompatible:
            return "OpenAI endpoint"
        case .anthropicCompatible:
            return "Anthropic endpoint"
        case .aiSDKBridge:
            return "Bridge"
        }
    }

    var modeBoundaryTitle: String {
        switch kind {
        case .openAI:
            return "OpenAI API key"
        case .chatGPTCLI:
            return "ChatGPT/Codex CLI"
        case .anthropic:
            return "Anthropic API key"
        case .claudeCodeCLI:
            return "Claude Code CLI"
        case .ollama:
            return "Ollama local server"
        case .lmStudio:
            return "LM Studio local server"
        case .customOpenAICompatible:
            return "OpenAI-compatible endpoint"
        case .vercelAISDKBridge:
            return "Local AI SDK bridge"
        case .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            return "\(kind.title) API key"
        }
    }

    var modeBoundaryDetail: String {
        switch kind {
        case .openAI:
            return "Official OpenAI API mode. Requests leave this Mac and bill through the OpenAI Platform API key stored by Keychain reference. This is separate from ChatGPT or Codex CLI access."
        case .chatGPTCLI:
            return "Local ChatGPT/Codex CLI mode. Flannel invokes an authenticated local CLI session; ChatGPT plan sign-in or Codex API-key auth stays inside that tool."
        case .anthropic:
            return "Official Anthropic API mode. Requests leave this Mac and bill through the Anthropic Console API key stored by Keychain reference. This is separate from Claude Code account access."
        case .claudeCodeCLI:
            return "Local Claude Code CLI mode. Flannel invokes Claude Code print mode with an authenticated local install and does not treat Claude account sign-in as an Anthropic API key."
        case .ollama:
            return "Local Ollama server mode. Chat stays on the configured loopback host unless you point the endpoint at another machine."
        case .lmStudio:
            return "Local LM Studio server mode. Flannel uses the configured OpenAI-compatible local endpoint and keeps chat local unless the endpoint leaves this Mac."
        case .customOpenAICompatible:
            return "OpenAI-compatible endpoint mode. Flannel sends OpenAI-shaped requests to the configured base URL and uses an API key only when one is configured."
        case .vercelAISDKBridge:
            return "Local bridge mode. A separate local service owns provider routing, streaming, and tools before chat can use it."
        case .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            return "Official or provider-compatible API mode. Requests leave this Mac and use a provider API key stored by Keychain reference."
        }
    }

    var modeBoundarySubtitle: String {
        let model = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(modeBoundaryTitle) • \(model.isEmpty ? "No model" : model)"
    }
}

private extension LLMProviderKind {
    nonisolated var usesOpenAICompatibleReadiness: Bool {
        switch self {
        case .openAI, .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity, .customOpenAICompatible:
            true
        case .ollama, .lmStudio, .anthropic, .chatGPTCLI, .claudeCodeCLI, .vercelAISDKBridge:
            false
        }
    }
}

enum ProviderRoutingPolicy: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case selectedProvider
    case localFirst
    case bestAvailable
    case cheapest
    case fastest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selectedProvider:
            "Selected Provider"
        case .localFirst:
            "Local First"
        case .bestAvailable:
            "Best Available"
        case .cheapest:
            "Cheapest"
        case .fastest:
            "Fastest"
        }
    }

    var detail: String {
        switch self {
        case .selectedProvider:
            "Use the chosen provider when it is runnable, then fall back safely."
        case .localFirst:
            "Prefer local servers and local CLI routes before external APIs."
        case .bestAvailable:
            "Prefer the strongest runnable model by capabilities and context."
        case .cheapest:
            "Prefer the lowest marginal API cost while honoring privacy gates."
        case .fastest:
            "Prefer recent low-latency providers, then known fast local routes."
        }
    }

    var icon: String {
        switch self {
        case .selectedProvider:
            "target"
        case .localFirst:
            "lock"
        case .bestAvailable:
            "sparkles"
        case .cheapest:
            "dollarsign.circle"
        case .fastest:
            "bolt"
        }
    }
}

enum ModelCapability: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case chat
    case streaming
    case toolCalling
    case embeddings
    case vision
    case reasoning
    case webSearch
    case imageGeneration
    case structuredOutput
    case openAICompatible
    case anthropicCompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            "Chat"
        case .streaming:
            "Streaming"
        case .toolCalling:
            "Tools"
        case .embeddings:
            "Embeddings"
        case .vision:
            "Vision"
        case .reasoning:
            "Reasoning"
        case .webSearch:
            "Web Search"
        case .imageGeneration:
            "Images"
        case .structuredOutput:
            "Structured Output"
        case .openAICompatible:
            "OpenAI Compatible"
        case .anthropicCompatible:
            "Anthropic Compatible"
        }
    }
}

struct LocalModelDescriptor: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var displayName: String?
    var publisher: String?
    var providerKind: LLMProviderKind
    var endpoint: String
    var family: String?
    var parameterSize: String?
    var quantization: String?
    var format: String?
    var contextWindowTokens: Int?
    var loadedInstanceCount: Int?
    var loadedInstanceIDs: [String]?
    var sizeBytes: Int64?
    var sizeVRAMBytes: Int64?
    var modifiedAt: Date?
    var expiresAt: Date?
    var selectedVariant: String?
    var capabilities: [ModelCapability]

    init(
        id: String? = nil,
        name: String,
        displayName: String? = nil,
        publisher: String? = nil,
        providerKind: LLMProviderKind,
        endpoint: String,
        family: String? = nil,
        parameterSize: String? = nil,
        quantization: String? = nil,
        format: String? = nil,
        contextWindowTokens: Int? = nil,
        loadedInstanceCount: Int? = nil,
        loadedInstanceIDs: [String]? = nil,
        sizeBytes: Int64? = nil,
        sizeVRAMBytes: Int64? = nil,
        modifiedAt: Date? = nil,
        expiresAt: Date? = nil,
        selectedVariant: String? = nil,
        capabilities: [ModelCapability] = [.chat, .streaming]
    ) {
        self.id = id ?? "\(providerKind.rawValue):\(endpoint):\(name)"
        self.name = name
        self.displayName = displayName
        self.publisher = publisher
        self.providerKind = providerKind
        self.endpoint = endpoint
        self.family = family
        self.parameterSize = parameterSize
        self.quantization = quantization
        self.format = format
        self.contextWindowTokens = contextWindowTokens
        self.loadedInstanceCount = loadedInstanceCount
        self.loadedInstanceIDs = loadedInstanceIDs
        self.sizeBytes = sizeBytes
        self.sizeVRAMBytes = sizeVRAMBytes
        self.modifiedAt = modifiedAt
        self.expiresAt = expiresAt
        self.selectedVariant = selectedVariant
        self.capabilities = capabilities
    }
}

struct ChatFolder: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var parentID: UUID?
    var title: String
    var symbolName: String
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        title: String,
        symbolName: String = "folder",
        isPinned: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.symbolName = symbolName
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct SystemPromptProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var detail: String
    var prompt: String
    var tags: [String]
    var isDefault: Bool

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        prompt: String,
        tags: [String] = [],
        isDefault: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.prompt = prompt
        self.tags = tags
        self.isDefault = isDefault
    }
}

struct ChatTemplate: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var detail: String
    var systemPrompt: String
    var starterPrompt: String
    var mode: AssistantMode
    var tagNames: [String]
    var preferredProviderKind: LLMProviderKind?
    var preferredAccessMode: ProviderAccessMode?
    var preferredModelIdentifier: String?
    var requiredToolKinds: [AIToolKind]
    var knowledgeSourceIDs: [UUID]
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        systemPrompt: String,
        starterPrompt: String = "",
        mode: AssistantMode = .workspaceCopilot,
        tagNames: [String] = [],
        preferredProviderKind: LLMProviderKind? = nil,
        preferredAccessMode: ProviderAccessMode? = nil,
        preferredModelIdentifier: String? = nil,
        requiredToolKinds: [AIToolKind] = [],
        knowledgeSourceIDs: [UUID] = [],
        isPinned: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.systemPrompt = systemPrompt
        self.starterPrompt = starterPrompt
        self.mode = mode
        self.tagNames = tagNames
        self.preferredProviderKind = preferredProviderKind
        self.preferredAccessMode = preferredAccessMode
        self.preferredModelIdentifier = preferredModelIdentifier
        self.requiredToolKinds = requiredToolKinds
        self.knowledgeSourceIDs = knowledgeSourceIDs
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id, default: UUID())
        title = try container.decode(String.self, forKey: .title, default: "Chat Template")
        detail = try container.decode(String.self, forKey: .detail, default: "")
        systemPrompt = try container.decode(String.self, forKey: .systemPrompt, default: "")
        starterPrompt = try container.decode(String.self, forKey: .starterPrompt, default: "")
        mode = try container.decode(AssistantMode.self, forKey: .mode, default: .workspaceCopilot)
        tagNames = try container.decode([String].self, forKey: .tagNames, default: [])
        preferredProviderKind = try container.decodeIfPresent(LLMProviderKind.self, forKey: .preferredProviderKind)
        preferredAccessMode = try container.decodeIfPresent(ProviderAccessMode.self, forKey: .preferredAccessMode)
        preferredModelIdentifier = try container.decodeIfPresent(String.self, forKey: .preferredModelIdentifier)
        requiredToolKinds = try container.decode([AIToolKind].self, forKey: .requiredToolKinds, default: [])
        knowledgeSourceIDs = try container.decode([UUID].self, forKey: .knowledgeSourceIDs, default: [])
        isPinned = try container.decode(Bool.self, forKey: .isPinned, default: false)
        createdAt = try container.decode(Date.self, forKey: .createdAt, default: .now)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt, default: createdAt)
    }

    var routeSummary: String {
        let provider = preferredProviderKind?.title ?? "Workspace default"
        let mode = preferredAccessMode?.title
        let model = preferredModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [provider, mode, model]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " - ")
    }
}

struct ModelPreset: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var providerKind: LLMProviderKind
    var accessMode: ProviderAccessMode
    var modelIdentifier: String
    var temperature: Double
    var contextWindowTokens: Int?
    var capabilities: [ModelCapability]
    var privacyScope: ProviderPrivacyScope
    var isDefault: Bool

    init(
        id: UUID = UUID(),
        title: String,
        providerKind: LLMProviderKind,
        accessMode: ProviderAccessMode,
        modelIdentifier: String,
        temperature: Double = 0.2,
        contextWindowTokens: Int? = nil,
        capabilities: [ModelCapability] = [.chat, .streaming],
        privacyScope: ProviderPrivacyScope,
        isDefault: Bool = false
    ) {
        self.id = id
        self.title = title
        self.providerKind = providerKind
        self.accessMode = accessMode
        self.modelIdentifier = modelIdentifier
        self.temperature = temperature
        self.contextWindowTokens = contextWindowTokens
        self.capabilities = capabilities
        self.privacyScope = privacyScope
        self.isDefault = isDefault
    }
}

enum ModelComparisonStatus: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case queued
    case streaming
    case completed
    case failed

    var id: String { rawValue }
}

struct ModelComparisonResult: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var providerID: UUID
    var providerDisplayName: String
    var providerKind: LLMProviderKind
    var accessMode: ProviderAccessMode
    var privacyScope: ProviderPrivacyScope
    var modelIdentifier: String
    var status: ModelComparisonStatus
    var text: String
    var errorMessage: String?
    var inputTokenCount: Int?
    var outputTokenCount: Int?
    var latencyMilliseconds: Int?
    var firstTokenLatencyMilliseconds: Int?
    var estimatedCostMicros: Int?
    var tokenCountsAreEstimated: Bool
    var startedAt: Date?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        provider: ProviderConfiguration,
        status: ModelComparisonStatus = .queued,
        text: String = "",
        errorMessage: String? = nil,
        inputTokenCount: Int? = nil,
        outputTokenCount: Int? = nil,
        latencyMilliseconds: Int? = nil,
        firstTokenLatencyMilliseconds: Int? = nil,
        estimatedCostMicros: Int? = nil,
        tokenCountsAreEstimated: Bool = true,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.providerID = provider.id
        self.providerDisplayName = provider.displayName
        self.providerKind = provider.kind
        self.accessMode = provider.accessMode
        self.privacyScope = provider.privacyScope
        self.modelIdentifier = provider.modelIdentifier
        self.status = status
        self.text = text
        self.errorMessage = errorMessage
        self.inputTokenCount = inputTokenCount
        self.outputTokenCount = outputTokenCount
        self.latencyMilliseconds = latencyMilliseconds
        self.firstTokenLatencyMilliseconds = firstTokenLatencyMilliseconds
        self.estimatedCostMicros = estimatedCostMicros
        self.tokenCountsAreEstimated = tokenCountsAreEstimated
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        providerID = try container.decode(UUID.self, forKey: .providerID)
        providerDisplayName = try container.decode(String.self, forKey: .providerDisplayName)
        providerKind = try container.decode(LLMProviderKind.self, forKey: .providerKind)
        accessMode = try container.decode(ProviderAccessMode.self, forKey: .accessMode)
        privacyScope = try container.decode(ProviderPrivacyScope.self, forKey: .privacyScope)
        modelIdentifier = try container.decode(String.self, forKey: .modelIdentifier)
        status = try container.decode(ModelComparisonStatus.self, forKey: .status)
        text = try container.decode(String.self, forKey: .text)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        inputTokenCount = try container.decodeIfPresent(Int.self, forKey: .inputTokenCount)
        outputTokenCount = try container.decodeIfPresent(Int.self, forKey: .outputTokenCount)
        latencyMilliseconds = try container.decodeIfPresent(Int.self, forKey: .latencyMilliseconds)
        firstTokenLatencyMilliseconds = try container.decodeIfPresent(Int.self, forKey: .firstTokenLatencyMilliseconds)
        estimatedCostMicros = try container.decodeIfPresent(Int.self, forKey: .estimatedCostMicros)
        tokenCountsAreEstimated = try container.decodeIfPresent(Bool.self, forKey: .tokenCountsAreEstimated) ?? true
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

struct ModelComparisonRun: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var prompt: String
    var systemPrompt: String?
    var providerIDs: [UUID]
    var results: [ModelComparisonResult]
    var citations: [AIChatCitation]
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        prompt: String,
        systemPrompt: String? = nil,
        providerIDs: [UUID],
        results: [ModelComparisonResult],
        citations: [AIChatCitation] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.providerIDs = providerIDs
        self.results = results
        self.citations = citations
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    var status: ModelComparisonStatus {
        if results.contains(where: { $0.status == .streaming || $0.status == .queued }) {
            return results.contains(where: { $0.status == .streaming }) ? .streaming : .queued
        }
        if results.contains(where: { $0.status == .completed }) {
            return .completed
        }
        return .failed
    }

    var recommendedResult: ModelComparisonResult? {
        results
            .filter(\.isRecommendationCandidate)
            .max { lhs, rhs in
                let lhsScore = recommendationScore(for: lhs)
                let rhsScore = recommendationScore(for: rhs)
                if lhsScore == rhsScore {
                    return lhs.providerDisplayName.localizedCaseInsensitiveCompare(rhs.providerDisplayName) == .orderedDescending
                }
                return lhsScore < rhsScore
            }
    }

    func recommendationScore(for result: ModelComparisonResult) -> Int {
        guard result.isRecommendationCandidate else { return Int.min }

        var score = 1_000

        switch result.privacyScope {
        case .localOnly:
            score += 240
        case .localCLI:
            score += 180
        case .bridgeService:
            score += 120
        case .externalAPI:
            score += 60
        }

        if result.tokenCountsAreEstimated {
            score += 20
        } else {
            score += 90
        }

        if let firstTokenLatencyMilliseconds = result.firstTokenLatencyMilliseconds {
            score += max(0, 180 - min(180, firstTokenLatencyMilliseconds / 20))
        }

        if let latencyMilliseconds = result.latencyMilliseconds {
            score += max(0, 220 - min(220, latencyMilliseconds / 35))
        }

        if let estimatedCostMicros = result.estimatedCostMicros {
            score += max(0, 180 - min(180, estimatedCostMicros / 120))
        } else if result.privacyScope == .localOnly || result.privacyScope == .localCLI {
            score += 120
        }

        let answerLength = result.text.trimmingCharacters(in: .whitespacesAndNewlines).count
        score += min(80, max(0, answerLength / 20))

        return score
    }

    func recommendationReasons(for result: ModelComparisonResult) -> [String] {
        guard result.isRecommendationCandidate else { return [] }

        var reasons: [String] = []

        switch result.privacyScope {
        case .localOnly:
            reasons.append("local-only route")
        case .localCLI:
            reasons.append("local account CLI")
        case .bridgeService:
            reasons.append("local bridge")
        case .externalAPI:
            break
        }

        if let firstTokenLatencyMilliseconds = result.firstTokenLatencyMilliseconds,
           firstTokenLatencyMilliseconds <= 1_000 {
            reasons.append("fast first token")
        } else if let latencyMilliseconds = result.latencyMilliseconds,
                  latencyMilliseconds <= 4_000 {
            reasons.append("low latency")
        }

        if !result.tokenCountsAreEstimated {
            reasons.append("measured tokens")
        }

        if let estimatedCostMicros = result.estimatedCostMicros {
            if estimatedCostMicros == 0 {
                reasons.append("no estimated API cost")
            } else if estimatedCostMicros <= 1_000 {
                reasons.append("low estimated cost")
            }
        } else if result.privacyScope == .localOnly || result.privacyScope == .localCLI {
            reasons.append("no API cost estimate")
        }

        if reasons.isEmpty {
            reasons.append("best observable telemetry")
        }

        return Array(reasons.prefix(3))
    }
}

extension ModelComparisonResult {
    var isRecommendationCandidate: Bool {
        status == .completed && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum KnowledgeSourceKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case folder
    case file
    case webPage
    case chatHistory
    case workspaceNotes
    case codeRepository

    var id: String { rawValue }
}

enum KnowledgeIndexStatus: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case notIndexed
    case queued
    case indexing
    case ready
    case stale
    case failed

    var id: String { rawValue }
}

enum KnowledgeEmbeddingState: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case disabled
    case configured
    case generated
    case failed

    var id: String { rawValue }
}

struct KnowledgeSource: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var kind: KnowledgeSourceKind
    var location: String
    var status: KnowledgeIndexStatus
    var chunkCount: Int
    var embeddingModelIdentifier: String?
    var lastIndexedAt: Date?
    var isWatched: Bool
    var exclusionRules: [String]
    var documentCount: Int
    var embeddingRecordCount: Int
    var vectorDimension: Int?
    var contentFingerprint: String?
    var lastErrorMessage: String?

    init(
        id: UUID = UUID(),
        title: String,
        kind: KnowledgeSourceKind,
        location: String,
        status: KnowledgeIndexStatus = .notIndexed,
        chunkCount: Int = 0,
        embeddingModelIdentifier: String? = nil,
        lastIndexedAt: Date? = nil,
        isWatched: Bool = false,
        exclusionRules: [String] = [],
        documentCount: Int = 0,
        embeddingRecordCount: Int = 0,
        vectorDimension: Int? = nil,
        contentFingerprint: String? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.location = location
        self.status = status
        self.chunkCount = chunkCount
        self.embeddingModelIdentifier = embeddingModelIdentifier
        self.lastIndexedAt = lastIndexedAt
        self.isWatched = isWatched
        self.exclusionRules = exclusionRules
        self.documentCount = documentCount
        self.embeddingRecordCount = embeddingRecordCount
        self.vectorDimension = vectorDimension
        self.contentFingerprint = contentFingerprint
        self.lastErrorMessage = lastErrorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(KnowledgeSourceKind.self, forKey: .kind)
        location = try container.decode(String.self, forKey: .location)
        status = try container.decode(KnowledgeIndexStatus.self, forKey: .status, default: .notIndexed)
        chunkCount = try container.decode(Int.self, forKey: .chunkCount, default: 0)
        embeddingModelIdentifier = try container.decodeIfPresent(String.self, forKey: .embeddingModelIdentifier)
        lastIndexedAt = try container.decodeIfPresent(Date.self, forKey: .lastIndexedAt)
        isWatched = try container.decode(Bool.self, forKey: .isWatched, default: false)
        exclusionRules = try container.decode([String].self, forKey: .exclusionRules, default: [])
        documentCount = try container.decode(Int.self, forKey: .documentCount, default: 0)
        embeddingRecordCount = try container.decode(Int.self, forKey: .embeddingRecordCount, default: 0)
        vectorDimension = try container.decodeIfPresent(Int.self, forKey: .vectorDimension)
        contentFingerprint = try container.decodeIfPresent(String.self, forKey: .contentFingerprint)
        lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
    }
}

struct KnowledgeIndexManifest: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var sourceID: UUID?
    var title: String
    var kind: KnowledgeSourceKind
    var location: String
    var status: KnowledgeIndexStatus
    var documentCount: Int
    var chunkCount: Int
    var embeddingRecordCount: Int
    var vectorDimension: Int?
    var embeddingModelIdentifier: String?
    var embeddingProviderKind: LLMProviderKind?
    var embeddingState: KnowledgeEmbeddingState
    var contentFingerprint: String?
    var storageLocation: String
    var lastBuiltAt: Date?
    var lastErrorMessage: String?

    init(
        id: UUID = UUID(),
        sourceID: UUID? = nil,
        title: String,
        kind: KnowledgeSourceKind,
        location: String,
        status: KnowledgeIndexStatus = .notIndexed,
        documentCount: Int = 0,
        chunkCount: Int = 0,
        embeddingRecordCount: Int = 0,
        vectorDimension: Int? = nil,
        embeddingModelIdentifier: String? = nil,
        embeddingProviderKind: LLMProviderKind? = nil,
        embeddingState: KnowledgeEmbeddingState = .disabled,
        contentFingerprint: String? = nil,
        storageLocation: String = "",
        lastBuiltAt: Date? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.kind = kind
        self.location = location
        self.status = status
        self.documentCount = documentCount
        self.chunkCount = chunkCount
        self.embeddingRecordCount = embeddingRecordCount
        self.vectorDimension = vectorDimension
        self.embeddingModelIdentifier = embeddingModelIdentifier
        self.embeddingProviderKind = embeddingProviderKind
        self.embeddingState = embeddingState
        self.contentFingerprint = contentFingerprint
        self.storageLocation = storageLocation
        self.lastBuiltAt = lastBuiltAt
        self.lastErrorMessage = lastErrorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id, default: UUID())
        sourceID = try container.decodeIfPresent(UUID.self, forKey: .sourceID)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(KnowledgeSourceKind.self, forKey: .kind)
        location = try container.decode(String.self, forKey: .location)
        status = try container.decode(KnowledgeIndexStatus.self, forKey: .status, default: .notIndexed)
        documentCount = try container.decode(Int.self, forKey: .documentCount, default: 0)
        chunkCount = try container.decode(Int.self, forKey: .chunkCount, default: 0)
        embeddingRecordCount = try container.decode(Int.self, forKey: .embeddingRecordCount, default: 0)
        vectorDimension = try container.decodeIfPresent(Int.self, forKey: .vectorDimension)
        embeddingModelIdentifier = try container.decodeIfPresent(String.self, forKey: .embeddingModelIdentifier)
        embeddingProviderKind = try container.decodeIfPresent(LLMProviderKind.self, forKey: .embeddingProviderKind)
        embeddingState = try container.decode(
            KnowledgeEmbeddingState.self,
            forKey: .embeddingState,
            default: embeddingModelIdentifier == nil ? .disabled : .configured
        )
        contentFingerprint = try container.decodeIfPresent(String.self, forKey: .contentFingerprint)
        storageLocation = try container.decode(String.self, forKey: .storageLocation, default: "")
        lastBuiltAt = try container.decodeIfPresent(Date.self, forKey: .lastBuiltAt)
        lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
    }
}

struct KnowledgeCitationPreview: Identifiable, Hashable, Sendable {
    var citation: AIChatCitation
    var source: KnowledgeSource?
    var manifest: KnowledgeIndexManifest?
    var chunkIdentifier: String?

    var id: UUID { citation.id }

    var displayTitle: String {
        if shouldPreferCitedDocument,
           !citedDocumentTitle.isEmpty {
            return citedDocumentTitle
        }

        return source?.title
            ?? manifest?.title
            ?? citedDocumentTitle
    }

    var displayLocation: String? {
        if shouldPreferCitedDocument,
           let citedLocation = citation.sourceLocation?.trimmingCharacters(in: .whitespacesAndNewlines),
           !citedLocation.isEmpty {
            return citedLocation
        }

        return source?.location
            ?? manifest?.location
            ?? citation.sourceLocation
    }

    var kind: KnowledgeSourceKind? {
        source?.kind ?? manifest?.kind
    }

    var status: KnowledgeIndexStatus? {
        source?.status ?? manifest?.status
    }

    var documentCount: Int? {
        source?.documentCount ?? manifest?.documentCount
    }

    var chunkCount: Int? {
        source?.chunkCount ?? manifest?.chunkCount
    }

    var embeddingRecordCount: Int? {
        source?.embeddingRecordCount ?? manifest?.embeddingRecordCount
    }

    var vectorDimension: Int? {
        source?.vectorDimension ?? manifest?.vectorDimension
    }

    var embeddingModelIdentifier: String? {
        source?.embeddingModelIdentifier ?? manifest?.embeddingModelIdentifier
    }

    var lastIndexedAt: Date? {
        source?.lastIndexedAt ?? manifest?.lastBuiltAt
    }

    var isWatched: Bool {
        source?.isWatched ?? false
    }

    var isResolved: Bool {
        source != nil || manifest != nil
    }

    var score: Double? {
        citation.score
    }

    var chunkLabel: String? {
        citation.chunkSuffixLabel
    }

    private var citedDocumentTitle: String {
        citation.sourceTitleWithoutChunkSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldPreferCitedDocument: Bool {
        let rootKind = source?.kind ?? manifest?.kind
        switch rootKind {
        case .chatHistory, .folder, .codeRepository:
            return source?.title != citedDocumentTitle && manifest?.title != citedDocumentTitle
        case .file, .workspaceNotes, .webPage, nil:
            return false
        }
    }

    init(
        citation: AIChatCitation,
        source: KnowledgeSource? = nil,
        manifest: KnowledgeIndexManifest? = nil,
        chunkIdentifier: String? = nil
    ) {
        self.citation = citation
        self.source = source
        self.manifest = manifest
        self.chunkIdentifier = chunkIdentifier
    }
}

private extension AIChatCitation {
    var sourceTitleWithoutChunkSuffix: String {
        guard let range = title.range(of: " • chunk ", options: .backwards) else {
            return title
        }
        return String(title[..<range.lowerBound])
    }

    var chunkSuffixLabel: String? {
        guard let range = title.range(of: " • chunk ", options: .backwards) else {
            return nil
        }
        let suffix = title[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty else { return nil }
        return "Chunk \(suffix)"
    }
}

enum AIToolKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case webSearch
    case webPageReader
    case localFileRead
    case localFileWrite
    case terminal
    case codeExecution
    case browserAutomation
    case workspaceSearch
    case ragRetrieval
    case github
    case notion
    case youtube
    case x

    var id: String { rawValue }
}

enum ToolPermissionPolicy: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case alwaysAllow
    case askEveryTime
    case deny
    case localOnly

    var id: String { rawValue }
}

struct ToolConfiguration: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: AIToolKind
    var title: String
    var detail: String
    var permissionPolicy: ToolPermissionPolicy
    var isEnabled: Bool
    var requiresNetwork: Bool
    var canModifyFiles: Bool
    var endpoint: String?
    var secretReference: String?

    init(
        id: UUID = UUID(),
        kind: AIToolKind,
        title: String,
        detail: String,
        permissionPolicy: ToolPermissionPolicy = .askEveryTime,
        isEnabled: Bool = false,
        requiresNetwork: Bool = false,
        canModifyFiles: Bool = false,
        endpoint: String? = nil,
        secretReference: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.permissionPolicy = permissionPolicy
        self.isEnabled = isEnabled
        self.requiresNetwork = requiresNetwork
        self.canModifyFiles = canModifyFiles
        self.endpoint = endpoint
        self.secretReference = secretReference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id, default: UUID())
        kind = try container.decode(AIToolKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title, default: kind.rawValue)
        detail = try container.decode(String.self, forKey: .detail, default: "")
        permissionPolicy = try container.decode(ToolPermissionPolicy.self, forKey: .permissionPolicy, default: .askEveryTime)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled, default: false)
        requiresNetwork = try container.decode(Bool.self, forKey: .requiresNetwork, default: false)
        canModifyFiles = try container.decode(Bool.self, forKey: .canModifyFiles, default: false)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        secretReference = try container.decodeIfPresent(String.self, forKey: .secretReference)
    }
}

enum LocalToolExecutionStatus: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case completed
    case requiresApproval
    case denied
    case blocked
    case unavailable

    var id: String { rawValue }
}

struct LocalToolExecutionResult: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var toolID: UUID?
    var toolKind: AIToolKind
    var title: String
    var query: String
    var status: LocalToolExecutionStatus
    var output: String
    var requiresApproval: Bool
    var usedNetwork: Bool
    var modifiedFiles: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        toolID: UUID? = nil,
        toolKind: AIToolKind,
        title: String,
        query: String = "",
        status: LocalToolExecutionStatus,
        output: String,
        requiresApproval: Bool = false,
        usedNetwork: Bool = false,
        modifiedFiles: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.toolID = toolID
        self.toolKind = toolKind
        self.title = title
        self.query = query
        self.status = status
        self.output = output
        self.requiresApproval = requiresApproval
        self.usedNetwork = usedNetwork
        self.modifiedFiles = modifiedFiles
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id, default: UUID())
        toolID = try container.decodeIfPresent(UUID.self, forKey: .toolID)
        toolKind = try container.decode(AIToolKind.self, forKey: .toolKind)
        title = try container.decode(String.self, forKey: .title)
        query = try container.decode(String.self, forKey: .query, default: "")
        status = try container.decode(LocalToolExecutionStatus.self, forKey: .status, default: .completed)
        output = try container.decode(String.self, forKey: .output, default: "")
        requiresApproval = try container.decode(Bool.self, forKey: .requiresApproval, default: false)
        usedNetwork = try container.decode(Bool.self, forKey: .usedNetwork, default: false)
        modifiedFiles = try container.decode(Bool.self, forKey: .modifiedFiles, default: false)
        createdAt = try container.decode(Date.self, forKey: .createdAt, default: .now)
    }
}

private extension KeyedDecodingContainer {
    nonisolated func decode<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) throws -> T {
        try decodeIfPresent(type, forKey: key) ?? defaultValue
    }
}

struct LocalProviderDiscoveryResult: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(providerKind.rawValue):\(endpoint)" }
    var providerKind: LLMProviderKind
    var endpoint: String
    var status: IntegrationConnectionStatus
    var models: [LocalModelDescriptor]
    var errorMessage: String?
    var discoveredAt: Date

    init(
        providerKind: LLMProviderKind,
        endpoint: String,
        status: IntegrationConnectionStatus,
        models: [LocalModelDescriptor] = [],
        errorMessage: String? = nil,
        discoveredAt: Date = .now
    ) {
        self.providerKind = providerKind
        self.endpoint = endpoint
        self.status = status
        self.models = models
        self.errorMessage = errorMessage
        self.discoveredAt = discoveredAt
    }
}
