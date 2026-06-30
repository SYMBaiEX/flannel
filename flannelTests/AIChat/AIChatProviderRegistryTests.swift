//
//  AIChatProviderRegistryTests.swift
//  flannelTests
//

import Foundation
import SwiftData
import Testing
@testable import flannel

struct AIChatProviderRegistryTests {
    @MainActor
    @Test("Active provider prefers the explicitly preferred enabled provider")
    func activeProviderRespectsEnabledPreferredProvider() throws {
        let (_, store) = try makeLoadedStore()

        let openAI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))
        let ollamaIndex = try #require(store.providerConfigurations.firstIndex(where: { $0.kind == .ollama }))

        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true
        store.preferences.preferredProviderID = openAI.id
        store.providerConfigurations[ollamaIndex].isEnabled = false
        let openAIIndex = try #require(store.providerConfigurations.firstIndex(where: { $0.id == openAI.id }))
        store.providerConfigurations[openAIIndex].secretReference = ProviderSetupService.shared
            .canonicalSecretReferenceString(for: store.providerConfigurations[openAIIndex])
        store.providerConfigurations[openAIIndex].connectionStatus = .ready

        let provider = try #require(store.activeProvider)

        #expect(provider.id == openAI.id)
        #expect(provider.kind == .openAI)
    }

    @MainActor
    @Test("External API providers require explicit cloud allowance")
    func externalAPIProviderRequiresCloudAllowance() throws {
        let (_, store) = try makeLoadedStore()

        let openAI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = false
        store.preferences.preferredProviderID = openAI.id

        #expect(store.isProviderAllowedByPreferences(openAI) == false)
        #expect(store.activeProvider?.privacyScope == .localOnly)
    }

    @MainActor
    @Test("External API providers become eligible when cloud allowance is explicit")
    func externalAPIProviderCanRunWhenCloudAllowanceIsExplicit() throws {
        let (_, store) = try makeLoadedStore()

        let openAI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true
        store.preferences.preferredProviderID = openAI.id
        let openAIIndex = try #require(store.providerConfigurations.firstIndex(where: { $0.id == openAI.id }))
        store.providerConfigurations[openAIIndex].secretReference = ProviderSetupService.shared
            .canonicalSecretReferenceString(for: store.providerConfigurations[openAIIndex])
        store.providerConfigurations[openAIIndex].connectionStatus = .ready

        #expect(store.isProviderAllowedByPreferences(openAI))
        #expect(store.activeProvider?.id == openAI.id)
    }

    @MainActor
    @Test("Preferred provider ID that is disabled falls back to another enabled provider")
    func activeProviderFallsBackWhenPreferredProviderIsDisabled() throws {
        let (_, store) = try makeLoadedStore()

        let ollamaIndex = try #require(store.providerConfigurations.firstIndex(where: { $0.kind == .ollama }))
        let ollama = store.providerConfigurations[ollamaIndex]
        let lmStudioIndex = try #require(store.providerConfigurations.firstIndex(where: { $0.kind == .lmStudio }))
        store.providerConfigurations[lmStudioIndex].modelIdentifier = "local-model"

        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true
        store.preferences.preferredProviderID = ollama.id
        store.providerConfigurations[ollamaIndex].isEnabled = false

        let provider = try #require(store.activeProvider)

        #expect(provider.kind == .lmStudio)
        #expect(provider.privacyScope == .localOnly)
    }

    @MainActor
    @Test("Invalid preferred provider id falls back to first enabled provider")
    func activeProviderFallsBackWhenPreferredIdIsMissing() throws {
        let (_, store) = try makeLoadedStore()

        store.preferences.preferredProviderID = UUID()

        let expectedID = try #require(
            store.providerConfigurations.first(where: { store.isProviderRunnableForChat($0) })?.id
        )

        let provider = try #require(store.activeProvider)
        #expect(provider.id == expectedID)
    }

    @MainActor
    @Test("Misconfigured preferred API provider is skipped for live chat")
    func activeProviderSkipsMisconfiguredPreferredAPIProvider() throws {
        let (_, store) = try makeLoadedStore()

        let openAI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true
        store.preferences.preferredProviderID = openAI.id

        #expect(store.isProviderAllowedByPreferences(openAI))
        #expect(store.isProviderRunnableForChat(openAI) == false)
        #expect(store.activeProvider?.kind == .ollama)
    }

    @MainActor
    @Test("Chat routing block reasons distinguish setup, capability, readiness, and CLI failures")
    func chatRoutingBlockReasonsDistinguishProviderFailures() throws {
        let (_, store) = try makeLoadedStore()
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true

        let disabledProvider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Disabled Local",
            endpoint: "http://localhost:1234/v1",
            modelIdentifier: "local-model",
            isEnabled: false,
            connectionStatus: .ready,
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )
        let embeddingOnlyProvider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Embedding Only",
            endpoint: "http://localhost:1234/v1",
            modelIdentifier: "text-embedding-model",
            isEnabled: true,
            connectionStatus: .ready,
            capabilities: [.embeddings],
            supportsStreaming: true
        )
        let nonStreamingProvider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Non Streaming",
            endpoint: "http://localhost:1234/v1",
            modelIdentifier: "local-model",
            isEnabled: true,
            connectionStatus: .ready,
            capabilities: [.chat],
            supportsStreaming: false
        )
        let failedReadinessProvider = ProviderConfiguration(
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Unavailable Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1",
            isEnabled: true,
            connectionStatus: .needsAttention,
            lastErrorMessage: "Connection refused.",
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )
        let invalidCLIProvider = ProviderConfiguration(
            kind: .claudeCodeCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "Claude Code CLI",
            endpoint: "claude",
            modelIdentifier: "claude-subscription",
            isEnabled: true,
            connectionStatus: .ready,
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )

        #expect(store.chatRoutingBlockReason(for: disabledProvider) == "Enable this provider before routing chat to it.")
        #expect(store.chatRoutingBlockReason(for: embeddingOnlyProvider) == "Chat capability is disabled for this provider configuration.")
        #expect(store.chatRoutingBlockReason(for: nonStreamingProvider) == "Streaming is disabled for this provider configuration.")
        #expect(store.chatRoutingBlockReason(for: failedReadinessProvider) == "Connection refused.")
        #expect(store.chatRoutingBlockReason(for: invalidCLIProvider)?.contains("print") == true)
    }

    @MainActor
    @Test("Preferred cloud provider is skipped while local-only mode is enabled")
    func activeProviderSkipsCloudProviderWhenLocalOnlyModeIsEnabled() throws {
        let (_, store) = try makeLoadedStore()

        let openAI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))
        store.preferences.localOnlyMode = true
        store.preferences.allowCloudProviders = true
        store.preferences.preferredProviderID = openAI.id

        let provider = try #require(store.activeProvider)

        #expect(provider.kind != .openAI)
        #expect(provider.privacyScope == .localOnly)
    }

    @MainActor
    @Test("No enabled providers resolves to nil active provider")
    func activeProviderIsNilWhenNoProviderEnabled() throws {
        let (_, store) = try makeLoadedStore()

        store.providerConfigurations = store.providerConfigurations.map { provider in
            var updated = provider
            updated.isEnabled = false
            return updated
        }

        #expect(store.activeProvider == nil)
    }

    @MainActor
    @Test("Selected provider fallback chain tries the selected route before local-safe fallbacks")
    func selectedProviderFallbackChainStartsWithSelectedThenLocalSafeRoutes() throws {
        let (_, store) = try makeLoadedStore()
        let selectedCloud = ProviderConfiguration(
            id: UUID(uuidString: "a1a5ac0d-bf75-4d8b-9fd5-0a8663d62e1c")!,
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Selected OpenAI route",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-5.5",
            secretReference: "flannel.test.openai",
            isEnabled: true,
            capabilities: [.chat, .streaming, .toolCalling],
            supportsStreaming: true,
            supportsToolCalling: true
        )
        let localFallback = ProviderConfiguration(
            id: UUID(uuidString: "9c7d4025-6f58-49b5-a3e8-2f8cce58be3d")!,
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Local Ollama fallback",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1",
            isEnabled: true,
            isLocalPreferred: true,
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )
        let cloudFallback = ProviderConfiguration(
            id: UUID(uuidString: "63cf71db-10a2-40a9-9a4d-69b275bbf197")!,
            kind: .groq,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Groq fallback",
            endpoint: "https://api.groq.com/openai/v1",
            modelIdentifier: "llama-3.3-70b-versatile",
            secretReference: "flannel.test.groq",
            isEnabled: true,
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )

        store.providerConfigurations = [cloudFallback, selectedCloud, localFallback]
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true
        store.preferences.preferredProviderID = selectedCloud.id
        store.preferences.providerRoutingPolicy = .selectedProvider

        let chain = store.chatProviderFallbackChain()

        #expect(chain.map(\.id) == [selectedCloud.id, localFallback.id, cloudFallback.id])
        #expect(store.activeProvider?.id == selectedCloud.id)
    }

    @MainActor
    @Test("Fallback chain respects local-only mode even when a cloud route is preferred")
    func fallbackChainRespectsLocalOnlyMode() throws {
        let (_, store) = try makeLoadedStore()
        let cloud = ProviderConfiguration(
            id: UUID(uuidString: "c8755e74-99a5-4b90-b3f4-e01c9d959777")!,
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Blocked cloud route",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-5.5",
            secretReference: "flannel.test.openai",
            isEnabled: true,
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )
        let local = ProviderConfiguration(
            id: UUID(uuidString: "d1e57ed2-41a6-4db8-933f-66fcbac09b1e")!,
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Local LM Studio route",
            endpoint: "http://localhost:1234/v1",
            modelIdentifier: "local-chat",
            isEnabled: true,
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )

        store.providerConfigurations = [cloud, local]
        store.preferences.localOnlyMode = true
        store.preferences.allowCloudProviders = true
        store.preferences.preferredProviderID = cloud.id
        store.preferences.providerRoutingPolicy = .selectedProvider

        let chain = store.chatProviderFallbackChain()

        #expect(chain.map(\.id) == [local.id])
        #expect(store.activeProvider?.id == local.id)
    }

    @MainActor
    @Test("Major providers expose distinct API and CLI-backed subscription rows")
    func majorProvidersExposeAPIAndCLIModeRows() throws {
        let (_, store) = try makeLoadedStore()

        let openAIAPI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))
        let chatGPTCLI = try #require(store.providerConfigurations.first(where: { $0.kind == .chatGPTCLI }))
        let anthropicAPI = try #require(store.providerConfigurations.first(where: { $0.kind == .anthropic }))
        let claudeCLI = try #require(store.providerConfigurations.first(where: { $0.kind == .claudeCodeCLI }))

        #expect(openAIAPI.accessMode == .apiKey)
        #expect(openAIAPI.privacyScope == .externalAPI)
        #expect(chatGPTCLI.accessMode == .subscriptionCLI)
        #expect(chatGPTCLI.privacyScope == .localCLI)
        #expect(anthropicAPI.accessMode == .apiKey)
        #expect(anthropicAPI.privacyScope == .externalAPI)
        #expect(claudeCLI.accessMode == .subscriptionCLI)
        #expect(claudeCLI.privacyScope == .localCLI)
    }

    @MainActor
    @Test("Provider mode families group API and subscription choices for major brands")
    func providerModeFamiliesGroupMajorBrandModes() throws {
        let (_, store) = try makeLoadedStore()

        let openAIAPI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))
        let chatGPTCLI = try #require(store.providerConfigurations.first(where: { $0.kind == .chatGPTCLI }))
        let anthropicAPI = try #require(store.providerConfigurations.first(where: { $0.kind == .anthropic }))
        let claudeCLI = try #require(store.providerConfigurations.first(where: { $0.kind == .claudeCodeCLI }))
        let ollama = try #require(store.providerConfigurations.first(where: { $0.kind == .ollama }))

        #expect(openAIAPI.modeFamily == .openAIChatGPT)
        #expect(chatGPTCLI.modeFamily == .openAIChatGPT)
        #expect(openAIAPI.providerModeChoiceTitle == "OpenAI API")
        #expect(chatGPTCLI.providerModeChoiceTitle == "ChatGPT/Codex subscription")
        #expect(openAIAPI.providerModeSelectionTitle == "Use OpenAI API key")
        #expect(chatGPTCLI.providerModeSelectionTitle == "Use ChatGPT/Codex subscription CLI")
        #expect(openAIAPI.providerModeSelectionDetail.contains("not ChatGPT subscription access"))
        #expect(chatGPTCLI.providerModeSelectionDetail.contains("does not read an OpenAI Platform key"))
        #expect(openAIAPI.providerModeBoundaryBadge == "API key")
        #expect(chatGPTCLI.providerModeBoundaryBadge == "Subscription CLI")
        #expect(openAIAPI.runtimeBoundary == .externalAPI)
        #expect(chatGPTCLI.runtimeBoundary == .localCLI)
        #expect(openAIAPI.providerPickerRouteSummary.contains("API key"))
        #expect(openAIAPI.providerPickerRouteSummary.contains("External API"))
        #expect(chatGPTCLI.providerPickerRouteSummary.contains("Subscription CLI"))
        #expect(chatGPTCLI.providerPickerRouteSummary.contains("Local CLI"))
        #expect(openAIAPI.providerPickerStatusLine(
            readinessText: "Ready",
            routingPolicy: .selectedProvider
        ).hasPrefix("API key"))
        #expect(chatGPTCLI.providerPickerStatusLine(
            readinessText: "Ready",
            routingPolicy: .localFirst
        ).contains("Local First • Subscription CLI"))
        #expect(openAIAPI.providerPickerAccessibilityLabel.contains("OpenAI API, API key"))
        #expect(chatGPTCLI.providerPickerAccessibilityLabel.contains("ChatGPT/Codex subscription, Subscription CLI"))

        #expect(anthropicAPI.modeFamily == .anthropicClaude)
        #expect(claudeCLI.modeFamily == .anthropicClaude)
        #expect(anthropicAPI.providerModeChoiceTitle == "Anthropic API")
        #expect(claudeCLI.providerModeChoiceTitle == "Claude Code subscription")
        #expect(anthropicAPI.providerModeSelectionTitle == "Use Anthropic API key")
        #expect(claudeCLI.providerModeSelectionTitle == "Use Claude Code subscription CLI")
        #expect(anthropicAPI.providerModeSelectionDetail.contains("not Claude subscription access"))
        #expect(claudeCLI.providerModeSelectionDetail.contains("does not read an Anthropic Console key"))
        #expect(anthropicAPI.providerModeBoundaryBadge == "API key")
        #expect(claudeCLI.providerModeBoundaryBadge == "Subscription CLI")
        #expect(anthropicAPI.runtimeBoundary == .externalAPI)
        #expect(claudeCLI.runtimeBoundary == .localCLI)
        #expect(anthropicAPI.providerPickerAccessibilityLabel.contains("Anthropic API, API key"))
        #expect(claudeCLI.providerPickerAccessibilityLabel.contains("Claude Code subscription, Subscription CLI"))

        #expect(ollama.modeFamily == .localModels)
        #expect(ollama.runtimeBoundary == .localServer)
        #expect(ProviderModeFamily.openAIChatGPT.detail.contains("API keys"))
        #expect(ProviderModeFamily.openAIChatGPT.detail.contains("subscription CLI"))
        #expect(ProviderModeFamily.openAIChatGPT.modeChoicePrompt?.contains("separate credentials") == true)
        #expect(ProviderModeFamily.anthropicClaude.detail.contains("API keys"))
        #expect(ProviderModeFamily.anthropicClaude.detail.contains("subscription CLI"))
        #expect(ProviderModeFamily.anthropicClaude.modeChoicePrompt?.contains("separate credentials") == true)
    }

    @Test("OpenAI-compatible runtime boundary follows endpoint locality")
    func openAICompatibleRuntimeBoundaryFollowsEndpointLocality() {
        let localEndpoint = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .localOnly,
            displayName: "Local gateway",
            endpoint: "http://localhost:8080/v1",
            modelIdentifier: "local-model"
        )
        let remoteEndpoint = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .externalAPI,
            displayName: "Remote gateway",
            endpoint: "https://models.example.com/v1",
            modelIdentifier: "remote-model"
        )

        #expect(localEndpoint.runtimeBoundary == .localServer)
        #expect(localEndpoint.runtimeBoundary.leavesDeviceDirectly == false)
        #expect(localEndpoint.providerPickerRouteSummary.contains("Local Server"))

        #expect(remoteEndpoint.runtimeBoundary == .externalAPI)
        #expect(remoteEndpoint.runtimeBoundary.leavesDeviceDirectly)
        #expect(remoteEndpoint.providerPickerRouteSummary.contains("External API"))
    }

    @MainActor
    @Test("Provider mode copy separates official API keys from subscription CLI sessions")
    func providerModeBoundaryCopySeparatesAPIAndSubscriptionCLI() throws {
        let (_, store) = try makeLoadedStore()

        let openAIAPI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))
        let chatGPTCLI = try #require(store.providerConfigurations.first(where: { $0.kind == .chatGPTCLI }))
        let anthropicAPI = try #require(store.providerConfigurations.first(where: { $0.kind == .anthropic }))
        let claudeCLI = try #require(store.providerConfigurations.first(where: { $0.kind == .claudeCodeCLI }))

        #expect(openAIAPI.modeBoundaryTitle == "OpenAI API key")
        #expect(openAIAPI.modeBoundaryDetail.contains("OpenAI Platform API key"))
        #expect(openAIAPI.modeBoundaryDetail.contains("separate from ChatGPT subscription access"))

        #expect(chatGPTCLI.modeBoundaryTitle == "ChatGPT/Codex subscription CLI")
        #expect(chatGPTCLI.modeBoundaryDetail.contains("authenticated Codex or ChatGPT CLI session"))
        #expect(chatGPTCLI.modeBoundaryDetail.contains("does not treat ChatGPT sign-in as an OpenAI API key"))

        #expect(anthropicAPI.modeBoundaryTitle == "Anthropic API key")
        #expect(anthropicAPI.modeBoundaryDetail.contains("Anthropic Console API key"))
        #expect(anthropicAPI.modeBoundaryDetail.contains("separate from Claude subscription access"))

        #expect(claudeCLI.modeBoundaryTitle == "Claude Code subscription CLI")
        #expect(claudeCLI.modeBoundaryDetail.contains("Claude Code print mode"))
        #expect(claudeCLI.modeBoundaryDetail.contains("does not treat Claude sign-in as an Anthropic API key"))
    }

    @MainActor
    @Test("Provider runtime policy centralizes readiness and chat transport modes")
    func providerRuntimePolicyCentralizesModeMatrix() throws {
        let (_, store) = try makeLoadedStore()

        let ollama = try #require(store.providerConfigurations.first(where: { $0.kind == .ollama }))
        let lmStudio = try #require(store.providerConfigurations.first(where: { $0.kind == .lmStudio }))
        let openAI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))
        let anthropic = try #require(store.providerConfigurations.first(where: { $0.kind == .anthropic }))
        let chatGPTCLI = try #require(store.providerConfigurations.first(where: { $0.kind == .chatGPTCLI }))
        let claudeCLI = try #require(store.providerConfigurations.first(where: { $0.kind == .claudeCodeCLI }))
        let customEndpoint = try #require(store.providerConfigurations.first(where: { $0.kind == .customOpenAICompatible }))
        let bridge = try #require(store.providerConfigurations.first(where: { $0.kind == .vercelAISDKBridge }))

        #expect(ollama.runtimePolicy.readinessStrategy == .localModelDiscovery)
        #expect(ollama.runtimePolicy.chatTransport == .ollamaNative)
        #expect(lmStudio.runtimePolicy.readinessStrategy == .localModelDiscovery)
        #expect(lmStudio.runtimePolicy.chatTransport == .openAICompatible)

        #expect(openAI.runtimePolicy.readinessStrategy == .openAICompatibleModels)
        #expect(openAI.runtimePolicy.chatTransport == .openAIResponses)
        #expect(openAI.runtimePolicy.requiresKeychainSecret)
        #expect(anthropic.runtimePolicy.readinessStrategy == .staticConfiguration)
        #expect(anthropic.runtimePolicy.chatTransport == .anthropicMessages)
        #expect(anthropic.runtimePolicy.requiresKeychainSecret)

        #expect(chatGPTCLI.runtimePolicy.readinessStrategy == .cliCommandResolution)
        #expect(chatGPTCLI.runtimePolicy.chatTransport == .subscriptionCLI)
        #expect(chatGPTCLI.runtimePolicy.requiresEndpoint == false)
        #expect(claudeCLI.runtimePolicy.readinessStrategy == .cliCommandResolution)
        #expect(claudeCLI.runtimePolicy.chatTransport == .subscriptionCLI)
        #expect(claudeCLI.runtimePolicy.requiresEndpoint == false)

        #expect(customEndpoint.runtimePolicy.readinessStrategy == .openAICompatibleModels)
        #expect(customEndpoint.runtimePolicy.chatTransport == .openAICompatible)
        #expect(customEndpoint.runtimePolicy.supportsOptionalKeychainSecret)

        #expect(bridge.runtimePolicy.readinessStrategy == .aiSDKBridgeHealth)
        #expect(bridge.runtimePolicy.chatTransport == .aiSDKBridge)
        #expect(bridge.runtimePolicy.supportsChatTransport)
    }

    @MainActor
    @Test("Subscription CLI providers advertise only text chat until structured tool events are implemented")
    func subscriptionCLIProvidersDoNotAdvertiseToolCalling() throws {
        let (_, store) = try makeLoadedStore()

        for kind in [LLMProviderKind.chatGPTCLI, .claudeCodeCLI] {
            let provider = try #require(store.providerConfigurations.first(where: { $0.kind == kind }))

            #expect(provider.accessMode == .subscriptionCLI)
            #expect(provider.capabilities.contains(.chat))
            #expect(provider.capabilities.contains(.streaming))
            #expect(provider.capabilities.contains(.toolCalling) == false)
            #expect(provider.supportsStreaming)
            #expect(provider.supportsToolCalling == false)
            #expect(provider.supportsEmbeddings == false)
            #expect(provider.supportsVision == false)
            #expect(provider.supportsStructuredOutput == false)
        }
    }

    @MainActor
    @Test("Provider matrix normalizes migrated CLI rows that used to claim tool calling")
    func providerMatrixNormalizesMigratedCLIProviderToolFlags() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(
            Item(
                providerConfigurations: [
                    ProviderConfiguration(
                        kind: .chatGPTCLI,
                        accessMode: .subscriptionCLI,
                        privacyScope: .localCLI,
                        displayName: "ChatGPT/Codex CLI",
                        endpoint: "codex",
                        modelIdentifier: "chatgpt-subscription",
                        isEnabled: false,
                        capabilities: [.chat, .streaming, .toolCalling, .embeddings, .vision, .structuredOutput],
                        supportsStreaming: false,
                        supportsToolCalling: true,
                        supportsEmbeddings: true,
                        supportsVision: true,
                        supportsStructuredOutput: true
                    ),
                    ProviderConfiguration(
                        kind: .claudeCodeCLI,
                        accessMode: .subscriptionCLI,
                        privacyScope: .localCLI,
                        displayName: "Claude Code CLI",
                        endpoint: "claude -p",
                        modelIdentifier: "claude-subscription",
                        isEnabled: false,
                        capabilities: [.chat, .streaming, .toolCalling, .embeddings, .vision, .structuredOutput],
                        supportsStreaming: false,
                        supportsToolCalling: true,
                        supportsEmbeddings: true,
                        supportsVision: true,
                        supportsStructuredOutput: true
                    )
                ]
            )
        )
        try context.save()

        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)

        let chatGPTCLI = try #require(store.providerConfigurations.first(where: { $0.kind == .chatGPTCLI }))
        let claudeCLI = try #require(store.providerConfigurations.first(where: { $0.kind == .claudeCodeCLI }))

        #expect(chatGPTCLI.endpoint == "codex exec --json -")
        #expect(claudeCLI.endpoint == "claude -p --output-format stream-json --verbose")

        for provider in [chatGPTCLI, claudeCLI] {
            #expect(provider.capabilities.contains(.chat))
            #expect(provider.capabilities.contains(.streaming))
            #expect(provider.capabilities.contains(.toolCalling) == false)
            #expect(provider.capabilities.contains(.embeddings) == false)
            #expect(provider.capabilities.contains(.vision) == false)
            #expect(provider.capabilities.contains(.structuredOutput) == false)
            #expect(provider.supportsStreaming)
            #expect(provider.supportsToolCalling == false)
            #expect(provider.supportsEmbeddings == false)
            #expect(provider.supportsVision == false)
            #expect(provider.supportsStructuredOutput == false)
        }
    }

    @MainActor
    @Test("Provider matrix restores hosted API capability defaults on migrated rows")
    func providerMatrixRestoresHostedAPICapabilityDefaults() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(
            Item(
                providerConfigurations: [
                    ProviderConfiguration(
                        kind: .openAI,
                        accessMode: .apiKey,
                        privacyScope: .externalAPI,
                        displayName: "OpenAI API",
                        endpoint: "https://api.openai.com/v1",
                        modelIdentifier: "gpt-5.5",
                        isEnabled: false,
                        capabilities: [.chat, .streaming],
                        supportsStreaming: true,
                        supportsToolCalling: false,
                        supportsVision: false,
                        supportsStructuredOutput: false
                    ),
                    ProviderConfiguration(
                        kind: .gemini,
                        accessMode: .apiKey,
                        privacyScope: .externalAPI,
                        displayName: "Google Gemini API",
                        endpoint: "https://generativelanguage.googleapis.com",
                        modelIdentifier: "gemini-2.5-pro",
                        isEnabled: false,
                        capabilities: [.chat, .streaming],
                        supportsStreaming: true,
                        supportsToolCalling: false,
                        supportsVision: false
                    ),
                    ProviderConfiguration(
                        kind: .perplexity,
                        accessMode: .apiKey,
                        privacyScope: .externalAPI,
                        displayName: "Perplexity API",
                        endpoint: "https://api.perplexity.ai",
                        modelIdentifier: "sonar-pro",
                        isEnabled: false,
                        capabilities: [.chat, .streaming],
                        supportsStreaming: true
                    )
                ]
            )
        )
        try context.save()

        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)
        let openAI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))
        let gemini = try #require(store.providerConfigurations.first(where: { $0.kind == .gemini }))
        let perplexity = try #require(store.providerConfigurations.first(where: { $0.kind == .perplexity }))

        #expect(openAI.capabilities.contains(.toolCalling))
        #expect(openAI.capabilities.contains(.vision))
        #expect(openAI.capabilities.contains(.reasoning))
        #expect(openAI.capabilities.contains(.structuredOutput))
        #expect(openAI.supportsToolCalling)
        #expect(openAI.supportsVision)
        #expect(openAI.supportsStructuredOutput)

        #expect(gemini.endpoint == "https://generativelanguage.googleapis.com/v1beta/openai")
        #expect(gemini.capabilities.contains(.openAICompatible))
        #expect(gemini.capabilities.contains(.toolCalling))
        #expect(gemini.capabilities.contains(.vision))
        #expect(gemini.supportsToolCalling)
        #expect(gemini.supportsVision)

        #expect(perplexity.capabilities.contains(.openAICompatible))
        #expect(perplexity.capabilities.contains(.webSearch))
        #expect(perplexity.supportsToolCalling == false)
        #expect(perplexity.supportsVision == false)
    }

    @MainActor
    @Test("Provider matrix backfills first-class Ollama and OpenAI rows into migrated workspaces")
    func providerMatrixBackfillsOllamaAndOpenAI() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(Item(providerConfigurations: []))
        try context.save()

        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)

        let ollama = try #require(store.providerConfigurations.first(where: { $0.kind == .ollama }))
        let openAI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))

        #expect(ollama.accessMode == .localServer)
        #expect(ollama.privacyScope == .localOnly)
        #expect(ollama.endpoint == "http://localhost:11434")
        #expect(ollama.capabilities.contains(.chat))
        #expect(ollama.capabilities.contains(.streaming))

        #expect(openAI.accessMode == .apiKey)
        #expect(openAI.privacyScope == .externalAPI)
        #expect(openAI.endpoint == "https://api.openai.com/v1")
        #expect(openAI.runtimePolicy.requiresKeychainSecret)
        #expect(openAI.capabilities.contains(.toolCalling))
    }

    @MainActor
    @Test("Provider matrix seeds routes from the known provider catalog")
    func providerMatrixSeedsRoutesFromKnownProviderCatalog() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(Item(providerConfigurations: []))
        try context.save()

        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)

        for catalogEntry in AIKnownProviderCatalog.entries {
            let providerKind = LLMProviderKind(catalogEntry.providerKind)
            let provider = try #require(
                store.providerConfigurations.first {
                    $0.kind == providerKind && $0.accessMode == catalogEntry.accessMode
                }
            )

            #expect(provider.privacyScope == catalogEntry.privacyScope)
            if let endpoint = catalogEntry.endpoint {
                #expect(provider.endpoint == endpoint)
            }
            #expect(provider.modelIdentifier == catalogEntry.defaultModelIdentifier)
            #expect(Set(catalogEntry.capabilities).isSubset(of: Set(provider.capabilities)))

            if !catalogEntry.defaultModelIdentifier.isEmpty {
                #expect(provider.availableModels.contains(catalogEntry.defaultModelIdentifier))
            }
        }
    }

    @MainActor
    @Test("Local discovery targets come from configured local provider rows")
    func localDiscoveryTargetsUseConfiguredProviderRows() throws {
        let (_, store) = try makeLoadedStore()
        store.providerConfigurations = [
            ProviderConfiguration(
                kind: .ollama,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "Remote Ollama",
                endpoint: " http://127.0.0.1:11500/custom ",
                modelIdentifier: "llama3.1"
            ),
            ProviderConfiguration(
                kind: .lmStudio,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "Team LM Studio",
                endpoint: "http://127.0.0.1:12434/v1",
                modelIdentifier: "local-model"
            ),
            ProviderConfiguration(
                kind: .openAI,
                accessMode: .apiKey,
                privacyScope: .externalAPI,
                displayName: "OpenAI API",
                endpoint: "https://api.openai.com/v1",
                modelIdentifier: "gpt-5.5"
            )
        ]

        #expect(discoveryTargetKeys(store.localProviderDiscoveryTargets()) == [
            "ollama|http://127.0.0.1:11500/custom",
            "lmStudio|http://127.0.0.1:12434/v1"
        ])

        #expect(discoveryTargetKeys(store.localProviderDiscoveryTargets(extraOllamaEndpoint: " http://localhost:11435 ")) == [
            "ollama|http://127.0.0.1:11500/custom",
            "lmStudio|http://127.0.0.1:12434/v1",
            "ollama|http://localhost:11435"
        ])
    }

    @Test("Chat domain provider kind bridging preserves every runtime provider")
    func chatDomainProviderKindBridgePreservesEveryRuntimeProvider() {
        for kind in LLMProviderKind.allCases {
            let domainKind = AIProviderKind(kind)

            #expect(LLMProviderKind(domainKind) == kind)
        }

        #expect(AIProviderKind.ollama.isLocalProvider)
        #expect(AIProviderKind.lmStudio.isLocalProvider)
        #expect(AIProviderKind.anthropic.isLocalProvider == false)
        #expect(AIProviderKind.chatGPTCLI.defaultBaseURL == nil)
        #expect(AIProviderKind.claudeCodeCLI.defaultBaseURL == nil)
        #expect(AIProviderKind.gemini.defaultBaseURL?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai")
        #expect(AIProviderKind.vercelAISDKBridge.defaultBaseURL?.absoluteString == "http://localhost:4177")
    }

    @Test("Known provider catalog covers every first-class route")
    func knownProviderCatalogCoversEveryFirstClassRoute() throws {
        let ids = AIKnownProviderCatalog.entries.map(\.id)

        #expect(Set(ids).count == ids.count)
        for kind in LLMProviderKind.allCases {
            let entry = try #require(AIKnownProviderCatalog.entry(for: kind))
            #expect(entry.providerKind == AIProviderKind(kind))
            #expect(
                entry.accessMode == ProviderAccessMode(entry.providerMode)
                    || (entry.accessMode == .apiKey && entry.providerMode == .openAICompatible)
                    || (entry.accessMode == .localServer && entry.providerMode == .openAICompatible)
            )
        }
    }

    @Test("Known provider catalog separates API keys from subscription CLI modes")
    func knownProviderCatalogSeparatesAPIKeysFromSubscriptionCLIModes() throws {
        let openAIAPI = try #require(AIKnownProviderCatalog.entry(for: LLMProviderKind.openAI))
        let chatGPTCLI = try #require(AIKnownProviderCatalog.entry(for: LLMProviderKind.chatGPTCLI))
        let anthropicAPI = try #require(AIKnownProviderCatalog.entry(for: LLMProviderKind.anthropic))
        let claudeCLI = try #require(AIKnownProviderCatalog.entry(for: LLMProviderKind.claudeCodeCLI))

        #expect(openAIAPI.credentialRequirement == AIProviderCredentialRequirement.requiredAPIKey)
        #expect(openAIAPI.requiresKeychainSecret)
        #expect(openAIAPI.leavesDeviceDirectly)
        #expect(openAIAPI.modelDiscoveryStrategy == AIProviderModelDiscoveryStrategy.openAICompatibleModels)
        #expect(openAIAPI.normalizedRecommendedModelIdentifiers.contains("gpt-5.5"))

        #expect(chatGPTCLI.credentialRequirement == AIProviderCredentialRequirement.subscriptionCLI)
        #expect(chatGPTCLI.supportsSubscriptionCLI)
        #expect(chatGPTCLI.requiresKeychainSecret == false)
        #expect(chatGPTCLI.leavesDeviceDirectly == false)
        #expect(chatGPTCLI.capabilities == [ModelCapability.chat, .streaming])

        #expect(anthropicAPI.credentialRequirement == AIProviderCredentialRequirement.requiredAPIKey)
        #expect(anthropicAPI.requiresKeychainSecret)
        #expect(anthropicAPI.leavesDeviceDirectly)
        #expect(anthropicAPI.modelDiscoveryStrategy == AIProviderModelDiscoveryStrategy.staticCatalog)

        #expect(claudeCLI.credentialRequirement == AIProviderCredentialRequirement.subscriptionCLI)
        #expect(claudeCLI.supportsSubscriptionCLI)
        #expect(claudeCLI.requiresKeychainSecret == false)
        #expect(claudeCLI.leavesDeviceDirectly == false)
        #expect(claudeCLI.capabilities == [ModelCapability.chat, .streaming])
    }

    @Test("Known provider catalog advertises local discovery and hosted model descriptors")
    func knownProviderCatalogAdvertisesLocalDiscoveryAndHostedModelDescriptors() throws {
        let ollama = try #require(AIKnownProviderCatalog.entry(for: LLMProviderKind.ollama))
        let lmStudio = try #require(AIKnownProviderCatalog.entry(for: LLMProviderKind.lmStudio))
        let perplexity = try #require(AIKnownProviderCatalog.entry(for: LLMProviderKind.perplexity))
        let customEndpoint = try #require(AIKnownProviderCatalog.entry(for: LLMProviderKind.customOpenAICompatible))

        #expect(ollama.credentialRequirement == AIProviderCredentialRequirement.none)
        #expect(ollama.modelDiscoveryStrategy == AIProviderModelDiscoveryStrategy.localServer)
        #expect(ollama.requestBoundary == ProviderRuntimeBoundary.localServer)
        #expect(ollama.normalizedRecommendedModelIdentifiers.contains("nomic-embed-text"))
        #expect(ollama.modelDescriptors.first?.capabilities.contains(AIModelCapability.embeddings) == true)

        #expect(lmStudio.credentialRequirement == AIProviderCredentialRequirement.none)
        #expect(lmStudio.modelDiscoveryStrategy == AIProviderModelDiscoveryStrategy.localServer)
        #expect(lmStudio.capabilities.contains(ModelCapability.openAICompatible))

        #expect(perplexity.modelDescriptors.first?.capabilities.contains(AIModelCapability.retrieval) == true)
        #expect(perplexity.normalizedRecommendedModelIdentifiers.contains("sonar-pro"))

        #expect(customEndpoint.credentialRequirement == AIProviderCredentialRequirement.optionalAPIKey)
        #expect(customEndpoint.supportsOptionalKeychainSecret)
        #expect(customEndpoint.modelDiscoveryStrategy == AIProviderModelDiscoveryStrategy.openAICompatibleModels)
    }

    @MainActor
    @Test("AI SDK bridge needs successful bridge health before routing")
    func aiSDKBridgeNeedsSuccessfulBridgeHealthBeforeRouting() throws {
        let (_, store) = try makeLoadedStore()
        let bridgeIndex = try #require(store.providerConfigurations.firstIndex(where: { $0.kind == .vercelAISDKBridge }))

        store.providerConfigurations[bridgeIndex].isEnabled = true
        store.providerConfigurations[bridgeIndex].modelIdentifier = "bridge-model"
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true

        let bridge = store.providerConfigurations[bridgeIndex]
        #expect(bridge.runtimePolicy.supportsChatTransport)
        #expect(store.isProviderAllowedByPreferences(bridge))
        #expect(store.isProviderRunnableForChat(bridge) == false)

        store.providerConfigurations[bridgeIndex].connectionStatus = .ready
        #expect(store.isProviderRunnableForChat(store.providerConfigurations[bridgeIndex]))
    }

    @MainActor
    @Test("Cached provider readiness failure removes a selected route from chat fallback")
    func cachedProviderReadinessFailureRemovesSelectedRouteFromChatFallback() throws {
        let (_, store) = try makeLoadedStore()
        let blockedLocal = ProviderConfiguration(
            id: UUID(uuidString: "3bec2c65-e814-48ec-88d7-7c6984a45899")!,
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Unavailable Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1",
            isEnabled: true,
            connectionStatus: .needsAttention,
            lastErrorMessage: "Connection refused.",
            isLocalPreferred: true,
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )
        let readyLocal = ProviderConfiguration(
            id: UUID(uuidString: "472f2cf4-fd0e-4754-91c4-f8fcb1794a0d")!,
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Ready LM Studio",
            endpoint: "http://localhost:1234/v1",
            modelIdentifier: "local-ready",
            isEnabled: true,
            connectionStatus: .ready,
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )

        store.providerConfigurations = [blockedLocal, readyLocal]
        store.preferences.localOnlyMode = true
        store.preferences.preferredProviderID = blockedLocal.id
        store.preferences.providerRoutingPolicy = .selectedProvider

        #expect(store.isProviderRunnableForChat(blockedLocal) == false)
        #expect(store.isProviderRunnableForChat(readyLocal))
        #expect(store.chatProviderFallbackChain().map(\.id) == [readyLocal.id])
        #expect(store.activeProvider?.id == readyLocal.id)
    }

    @MainActor
    @Test("Ready cached provider state restores selected route to chat fallback")
    func readyCachedProviderStateRestoresSelectedRouteToChatFallback() throws {
        let (_, store) = try makeLoadedStore()
        let selectedLocal = ProviderConfiguration(
            id: UUID(uuidString: "492d5eb5-5331-4d63-b508-fced0f6d01ce")!,
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Ready Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1",
            isEnabled: true,
            connectionStatus: .ready,
            isLocalPreferred: true,
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )

        store.providerConfigurations = [selectedLocal]
        store.preferences.localOnlyMode = true
        store.preferences.preferredProviderID = selectedLocal.id
        store.preferences.providerRoutingPolicy = .selectedProvider

        #expect(store.isProviderRunnableForChat(selectedLocal))
        #expect(store.chatProviderFallbackChain().map(\.id) == [selectedLocal.id])
        #expect(store.activeProvider?.id == selectedLocal.id)
    }

    @MainActor
    @Test("OpenAI-compatible hosted APIs require configured credentials and readiness")
    func openAICompatibleHostedProvidersRequireConfiguredCredentialsAndReadiness() throws {
        let (_, store) = try makeLoadedStore()
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true

        for kind in [LLMProviderKind.gemini, .xAI, .mistral, .perplexity] {
            let index = try #require(store.providerConfigurations.firstIndex(where: { $0.kind == kind }))
            store.providerConfigurations[index].isEnabled = true
            store.providerConfigurations[index].secretReference = ProviderSetupService.shared
                .canonicalSecretReferenceString(for: store.providerConfigurations[index])

            #expect(store.providerConfigurations[index].capabilities.contains(.openAICompatible))
            #expect(store.isProviderRunnableForChat(store.providerConfigurations[index]) == false)

            store.providerConfigurations[index].connectionStatus = .ready
            #expect(store.isProviderRunnableForChat(store.providerConfigurations[index]))
        }
    }

    @MainActor
    @Test("Selecting a cloud API provider preserves the explicit cloud routing gate")
    func selectingCloudProviderPreservesExplicitCloudRoutingGate() throws {
        let (_, store) = try makeLoadedStore()

        let openAI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))
        store.preferences.localOnlyMode = true
        store.preferences.allowCloudProviders = false

        let runnable = store.selectPreferredProviderForChat(openAI.id)

        let updatedOpenAI = try #require(store.providerConfigurations.first(where: { $0.id == openAI.id }))
        #expect(runnable == false)
        #expect(updatedOpenAI.isEnabled)
        #expect(store.preferences.preferredProviderID == openAI.id)
        #expect(store.preferences.allowCloudProviders == false)
        #expect(store.preferences.localOnlyMode == true)
        #expect(store.activeProvider?.privacyScope == .localOnly)
    }

    @MainActor
    @Test("Selecting a CLI subscription provider keeps it separate from API cloud policy")
    func selectingCLISubscriptionProviderDoesNotRequireCloudAPIAllowance() throws {
        let (_, store) = try makeLoadedStore()

        let cliProvider = try #require(store.providerConfigurations.first(where: { $0.kind == .claudeCodeCLI }))
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = false

        _ = store.selectPreferredProviderForChat(cliProvider.id)

        let updatedProvider = try #require(store.providerConfigurations.first(where: { $0.id == cliProvider.id }))
        #expect(updatedProvider.isEnabled)
        #expect(updatedProvider.accessMode == .subscriptionCLI)
        #expect(updatedProvider.privacyScope == .localCLI)
        #expect(store.preferences.preferredProviderID == cliProvider.id)
        #expect(store.preferences.allowCloudProviders == false)
    }

    @MainActor
    @Test("Manual provider selection resets policy routing to the selected provider")
    func manualProviderSelectionResetsPolicyRouting() throws {
        let (_, store) = try makeLoadedStore()
        let provider = try #require(store.providerConfigurations.first(where: { store.isProviderRunnableForChat($0) }))

        store.preferences.providerRoutingPolicy = .fastest
        _ = store.selectPreferredProviderForChat(provider.id)

        #expect(store.preferences.preferredProviderID == provider.id)
        #expect(store.preferences.providerRoutingPolicy == .selectedProvider)
        #expect(store.activeProvider?.id == provider.id)
    }

    @MainActor
    @Test("Selecting a provider model from the chat picker updates the preferred route")
    func selectingProviderModelFromChatPickerUpdatesPreferredRoute() throws {
        let (_, store) = try makeLoadedStore()
        let provider = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))

        store.preferences.providerRoutingPolicy = .fastest
        _ = store.selectPreferredProviderModelForChat(
            providerID: provider.id,
            modelIdentifier: " gpt-5.5-mini "
        )

        let updatedProvider = try #require(store.providerConfigurations.first(where: { $0.id == provider.id }))
        #expect(updatedProvider.isEnabled)
        #expect(updatedProvider.modelIdentifier == "gpt-5.5-mini")
        #expect(updatedProvider.availableModels.contains("gpt-5.5-mini"))
        #expect(store.preferences.preferredProviderID == provider.id)
        #expect(store.preferences.providerRoutingPolicy == .selectedProvider)
    }

    @MainActor
    @Test("Selecting an OpenAI model updates only OpenAI family configuration and keeps Anthropic separate")
    func selectingOpenAIModelFromChatPickerKeepsAnthropicFamilySeparate() throws {
        let (_, store) = try makeLoadedStore()

        let openAI = try #require(store.providerConfigurations.first(where: { $0.kind == .openAI }))
        let anthropicAPI = try #require(store.providerConfigurations.first(where: { $0.kind == .anthropic }))
        let claudeCLI = try #require(store.providerConfigurations.first(where: { $0.kind == .claudeCodeCLI }))

        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true
        store.preferences.providerRoutingPolicy = .fastest

        let openAIIndex = try #require(store.providerConfigurations.firstIndex(where: { $0.id == openAI.id }))
        store.providerConfigurations[openAIIndex].secretReference = ProviderSetupService.shared
            .canonicalSecretReferenceString(for: store.providerConfigurations[openAIIndex])
        store.providerConfigurations[openAIIndex].connectionStatus = .ready

        let anthropicIndex = try #require(store.providerConfigurations.firstIndex(where: { $0.id == anthropicAPI.id }))
        store.providerConfigurations[anthropicIndex].secretReference = ProviderSetupService.shared
            .canonicalSecretReferenceString(for: store.providerConfigurations[anthropicIndex])
        store.providerConfigurations[anthropicIndex].connectionStatus = .ready

        #expect(openAI.modeFamily == .openAIChatGPT)
        #expect(anthropicAPI.modeFamily == .anthropicClaude)
        #expect(claudeCLI.modeFamily == .anthropicClaude)
        #expect(openAI.modeBoundaryTitle == "OpenAI API key")
        #expect(anthropicAPI.modeBoundaryTitle == "Anthropic API key")
        #expect(claudeCLI.modeBoundaryTitle == "Claude Code subscription CLI")

        let initialAnthropicModel = anthropicAPI.modelIdentifier
        let initialAnthropicMode = anthropicAPI.availableModels

        let updated = store.selectPreferredProviderModelForChat(
            providerID: openAI.id,
            modelIdentifier: " gpt-5.5-preview "
        )

        let updatedOpenAI = try #require(store.providerConfigurations.first(where: { $0.id == openAI.id }))
        let untouchedAnthropic = try #require(store.providerConfigurations.first(where: { $0.id == anthropicAPI.id }))
        let untouchedClaudeCLI = try #require(store.providerConfigurations.first(where: { $0.id == claudeCLI.id }))

        #expect(updated)
        #expect(updatedOpenAI.modelIdentifier == "gpt-5.5-preview")
        #expect(store.preferences.preferredProviderID == updatedOpenAI.id)
        #expect(store.preferences.providerRoutingPolicy == .selectedProvider)
        #expect(store.activeProvider?.id == updatedOpenAI.id)
        #expect(untouchedAnthropic.modelIdentifier == initialAnthropicModel)
        #expect(untouchedAnthropic.availableModels == initialAnthropicMode)
        #expect(untouchedClaudeCLI.providerModeChoiceTitle.contains("Claude Code subscription"))
    }

    @MainActor
    @Test("Cheapest routing prefers zero marginal cost local providers")
    func cheapestRoutingPrefersLocalProviderCost() throws {
        let (_, store) = try makeLoadedStore()
        let local = ProviderConfiguration(
            id: UUID(uuidString: "b2259fb1-37d7-4c0f-a87d-0ef01161db91")!,
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Local free route",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1",
            isEnabled: true,
            isLocalPreferred: true,
            supportsStreaming: true
        )
        let cloud = ProviderConfiguration(
            id: UUID(uuidString: "2d918a01-1a68-40b8-b64f-89a6235a9c52")!,
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Paid cloud route",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-5.5",
            secretReference: "flannel.test.openai",
            isEnabled: true,
            capabilities: [.chat, .streaming, .toolCalling, .reasoning],
            supportsStreaming: true,
            supportsToolCalling: true,
            inputCostPerMillionTokens: 3,
            outputCostPerMillionTokens: 12
        )
        store.providerConfigurations = [cloud, local]
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true
        store.preferences.preferredProviderID = cloud.id
        store.preferences.providerRoutingPolicy = .cheapest

        #expect(store.activeProvider?.id == local.id)
    }

    @MainActor
    @Test("Best available routing prefers stronger runnable capability profiles")
    func bestAvailableRoutingPrefersCapabilityProfile() throws {
        let (_, store) = try makeLoadedStore()
        let basicLocal = ProviderConfiguration(
            id: UUID(uuidString: "4ae9dd9b-a5f3-4ef6-975f-9518a6850e66")!,
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Basic local route",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1",
            isEnabled: true,
            isLocalPreferred: true,
            capabilities: [.chat, .streaming],
            supportsStreaming: true,
            contextWindowTokens: 8_192
        )
        let capableLocal = ProviderConfiguration(
            id: UUID(uuidString: "14d8de84-9806-4179-83e9-fef8ac591dd8")!,
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Capable local route",
            endpoint: "http://localhost:1234/v1",
            modelIdentifier: "local-reasoner",
            isEnabled: true,
            capabilities: [.chat, .streaming, .toolCalling, .vision, .reasoning, .structuredOutput],
            supportsStreaming: true,
            supportsToolCalling: true,
            supportsVision: true,
            contextWindowTokens: 131_072,
            supportsStructuredOutput: true
        )
        store.providerConfigurations = [basicLocal, capableLocal]
        store.preferences.providerRoutingPolicy = .bestAvailable

        #expect(store.activeProvider?.id == capableLocal.id)
    }

    @MainActor
    @Test("Fastest routing uses recent comparison latency before static heuristics")
    func fastestRoutingUsesRecentComparisonLatency() throws {
        let (_, store) = try makeLoadedStore()
        store.modelComparisonRuns.removeAll()

        let slower = ProviderConfiguration(
            id: UUID(uuidString: "0f8a7626-c873-4435-bd4d-55e80e6ab46d")!,
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Measured slower route",
            endpoint: "http://localhost:11434",
            modelIdentifier: "slow-local",
            isEnabled: true,
            isLocalPreferred: true,
            supportsStreaming: true
        )
        let faster = ProviderConfiguration(
            id: UUID(uuidString: "8204cd27-d6b1-4bc5-97ff-1047cb66cf34")!,
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Measured faster route",
            endpoint: "http://localhost:1234/v1",
            modelIdentifier: "fast-local",
            isEnabled: true,
            supportsStreaming: true
        )
        store.providerConfigurations = [slower, faster]
        let runID = try #require(
            store.createModelComparisonRun(
                prompt: "Measure route latency.",
                providerIDs: [slower.id, faster.id]
            )
        )
        store.updateModelComparisonResult(
            runID: runID,
            providerID: slower.id,
            status: .completed,
            text: "Slow",
            latencyMilliseconds: 900
        )
        store.updateModelComparisonResult(
            runID: runID,
            providerID: faster.id,
            status: .completed,
            text: "Fast",
            latencyMilliseconds: 120
        )
        store.preferences.providerRoutingPolicy = .fastest

        #expect(store.activeProvider?.id == faster.id)
    }

    @MainActor
    @Test("Fastest routing fallback chain keeps measured latency order")
    func fastestRoutingFallbackChainKeepsMeasuredLatencyOrder() throws {
        let (_, store) = try makeLoadedStore()
        store.modelComparisonRuns.removeAll()

        let slower = ProviderConfiguration(
            id: UUID(uuidString: "b7d3f96a-cd04-4d89-84df-7cc24ab68135")!,
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Slower measured local",
            endpoint: "http://localhost:11434",
            modelIdentifier: "slow-local",
            isEnabled: true,
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )
        let faster = ProviderConfiguration(
            id: UUID(uuidString: "9ed8f9e5-4de4-418e-b7f5-9214a87e2f0b")!,
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Faster measured local",
            endpoint: "http://localhost:1234/v1",
            modelIdentifier: "fast-local",
            isEnabled: true,
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )
        let unmeasured = ProviderConfiguration(
            id: UUID(uuidString: "64440187-d588-4f77-9b87-fd4db090346f")!,
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .localOnly,
            displayName: "Unmeasured local compatible",
            endpoint: "http://localhost:8080/v1",
            modelIdentifier: "compatible-local",
            isEnabled: true,
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )
        store.providerConfigurations = [slower, unmeasured, faster]
        let runID = try #require(
            store.createModelComparisonRun(
                prompt: "Measure route latency.",
                providerIDs: [slower.id, faster.id]
            )
        )
        store.updateModelComparisonResult(
            runID: runID,
            providerID: slower.id,
            status: .completed,
            text: "Slow",
            latencyMilliseconds: 880
        )
        store.updateModelComparisonResult(
            runID: runID,
            providerID: faster.id,
            status: .completed,
            text: "Fast",
            latencyMilliseconds: 140
        )
        store.preferences.providerRoutingPolicy = .fastest

        let chain = store.chatProviderFallbackChain()

        #expect(chain.map(\.id) == [faster.id, unmeasured.id, slower.id])
        #expect(store.activeProvider?.id == faster.id)
    }

    @MainActor
    private func makeLoadedStore() throws -> (ModelContainer, WorkspaceStore) {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = WorkspaceStore()
        try store.loadOrCreate(in: ModelContext(container))
        return (container, store)
    }

    private func discoveryTargetKeys(_ targets: [(LLMProviderKind, String)]) -> [String] {
        targets.map { "\($0.0.rawValue)|\($0.1)" }
    }
}
