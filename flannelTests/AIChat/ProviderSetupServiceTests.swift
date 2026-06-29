//
//  ProviderSetupServiceTests.swift
//  flannelTests
//

import Foundation
import Testing
@testable import flannel

struct ProviderSetupServiceTests {
    private let service = ProviderSetupService.shared

    @Test("API-key provider report flags missing model and Keychain reference")
    func apiKeyProviderReportCapturesBlockingSetupIssues() {
        let provider = ProviderConfiguration(
            kind: .openAI,
            displayName: "OpenAI",
            endpoint: " https://api.openai.com/v1 ",
            modelIdentifier: "   "
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: true,
            localOnlyMode: false
        )

        let report = service.report(for: provider, preferences: preferences)

        #expect(report.normalizedEndpoint == "https://api.openai.com/v1")
        #expect(report.normalizedModelIdentifier.isEmpty)
        #expect(report.canonicalSecretReference?.rawValue == "flannel.ai.keys:provider/openai/api-openai-com")
        #expect(report.routingEligibility == .eligible)
        #expect(report.hasBlockingIssues)
        #expect(report.diagnostics.contains(where: { $0.code == .missingModelIdentifier }))
        #expect(report.diagnostics.contains(where: { $0.code == .missingKeychainReference }))
    }

    @Test("Canonical Keychain references are deterministic and legacy references stay parseable")
    func canonicalKeychainReferenceIsDeterministic() {
        let provider = ProviderConfiguration(
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "OpenAI",
            endpoint: "https://api.example.com/v1",
            modelIdentifier: "gpt-oss"
        )

        let first = service.canonicalSecretReference(for: provider)
        let second = service.canonicalSecretReference(for: provider)
        let legacy = service.parseSecretReference("keychain:flannel/custom-endpoint")

        #expect(first == second)
        #expect(first?.rawValue == "flannel.ai.keys:provider/openai/api-example-com")
        #expect(legacy == KeychainSecretReference(service: "keychain", account: "flannel/custom-endpoint"))
    }

    @Test("OpenAI-compatible custom endpoints offer optional API keys")
    func openAICompatibleCustomEndpointAllowsOptionalKeychainSecret() {
        let provider = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .externalAPI,
            displayName: "Custom OpenAI-compatible",
            endpoint: "http://localhost:8080/v1",
            modelIdentifier: "local-router-model",
            secretReference: nil,
            capabilities: [.chat, .streaming, .openAICompatible]
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: true,
            localOnlyMode: false
        )

        let report = service.report(for: provider, preferences: preferences)

        #expect(report.routingEligibility == .eligible)
        #expect(report.hasBlockingIssues == false)
        #expect(report.canonicalSecretReference?.rawValue == "flannel.ai.keys:provider/customopenaicompatible/localhost-8080")
        #expect(!report.diagnostics.contains(where: { $0.code == .missingKeychainReference }))
    }

    @Test("Keyed custom OpenAI-compatible providers require a Keychain reference")
    func keyedCustomOpenAICompatibleProviderRequiresKeychainReference() {
        let provider = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Hosted Custom Router",
            endpoint: "https://router.example.com/v1",
            modelIdentifier: "hosted-router-model",
            secretReference: nil,
            capabilities: [.chat, .streaming, .openAICompatible]
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: true,
            localOnlyMode: false
        )

        let report = service.report(for: provider, preferences: preferences)

        #expect(report.routingEligibility == .eligible)
        #expect(report.hasBlockingIssues)
        #expect(report.canonicalSecretReference?.rawValue == "flannel.ai.keys:provider/customopenaicompatible/router-example-com")
        #expect(report.diagnostics.contains(where: { $0.code == .missingKeychainReference }))
    }

    @Test("Loopback OpenAI-compatible endpoints stay eligible under local-only routing")
    func loopbackOpenAICompatibleEndpointIsTreatedAsLocalBoundary() {
        let provider = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .externalAPI,
            displayName: "Local Router",
            endpoint: "http://127.0.0.1:8080/v1",
            modelIdentifier: "router-model",
            capabilities: [.chat, .streaming, .openAICompatible]
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: false,
            localOnlyMode: true
        )

        let report = service.report(for: provider, preferences: preferences)

        #expect(report.routingEligibility == .eligible)
        #expect(!report.diagnostics.contains(where: { $0.code == .blockedByLocalOnlyMode }))
        #expect(!report.diagnostics.contains(where: { $0.code == .blockedByCloudPreference }))
    }

    @Test("Cloud providers are blocked while local-only mode remains enabled")
    func localOnlyModeBlocksCloudProviderActivation() {
        let provider = ProviderConfiguration(
            kind: .openAI,
            displayName: "OpenAI",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-4.1",
            secretReference: "flannel.ai.keys:provider/openai/api-openai-com"
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: true,
            localOnlyMode: true
        )

        let report = service.report(for: provider, preferences: preferences)

        #expect(report.routingEligibility == .blockedByLocalOnlyMode)
        #expect(report.diagnostics.contains(where: { $0.code == .blockedByLocalOnlyMode }))
    }

    @Test("Local providers stay eligible when cloud providers are disabled")
    func localProviderRemainsEligibleWhenCloudProvidersAreDisabled() {
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "local-model"
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: false,
            localOnlyMode: false
        )

        let report = service.report(for: provider, preferences: preferences)

        #expect(report.routingEligibility == .eligible)
        #expect(report.hasBlockingIssues == false)
        #expect(report.diagnostics.isEmpty)
    }

    @MainActor
    @Test("Custom OpenAI-compatible readiness validates model availability through /v1/models")
    func customOpenAICompatibleReadinessChecksModelList() async throws {
        let transport = ProviderReadinessTransportRecorder(
            responses: [
                "http://localhost:8080/v1/models": .init(
                    statusCode: 200,
                    body: """
                    {
                      "object": "list",
                      "data": [
                        { "id": "router-model", "object": "model", "owned_by": "local-router" },
                        { "id": "text-embedding-nomic-embed-text-v1.5", "object": "model", "owned_by": "local-router" }
                      ]
                    }
                    """
                )
            ]
        )
        let service = ProviderSetupService(
            readinessTimeout: 7,
            readinessTransport: { request in try await transport.send(request) }
        )
        let provider = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .externalAPI,
            displayName: "Local Router",
            endpoint: " http://localhost:8080/v1/ ",
            modelIdentifier: "router-model",
            capabilities: [.chat, .streaming, .openAICompatible]
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: false,
            localOnlyMode: true
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences,
            checkedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        let requests = await transport.requests()

        #expect(validation.isReady)
        #expect(validation.connectionStatus == .ready)
        #expect(validation.selectedModelIsAvailable)
        #expect(validation.availableModels == [
            "router-model",
            "text-embedding-nomic-embed-text-v1.5"
        ])
        #expect(validation.report.diagnostics.isEmpty)
        #expect(requests.map(\.url) == ["http://localhost:8080/v1/models"])
        #expect(requests.map(\.timeout) == [7])
        #expect(requests.map(\.acceptHeader) == ["application/json"])
        #expect(requests.map(\.authorizationHeader) == [nil])
    }

    @MainActor
    @Test("API-key OpenAI-compatible providers validate models with Keychain auth")
    func apiKeyOpenAICompatibleReadinessUsesAuthenticatedModelList() async throws {
        let secretReference = "flannel.ai.keys:provider/openai/api-openai-com"
        let transport = ProviderReadinessTransportRecorder(
            responses: [
                "https://api.openai.com/v1/models": .init(
                    statusCode: 200,
                    body: """
                    {
                      "object": "list",
                      "data": [
                        { "id": "gpt-4.1", "object": "model", "owned_by": "openai" },
                        { "id": "gpt-4.1-mini", "object": "model", "owned_by": "openai" }
                      ]
                    }
                    """
                )
            ]
        )
        let service = ProviderSetupService(
            readinessTransport: { request in try await transport.send(request) },
            secretReader: { reference in
                #expect(reference.rawValue == secretReference)
                return "sk-test-live-readiness"
            }
        )
        let provider = ProviderConfiguration(
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "OpenAI",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-4.1",
            secretReference: secretReference,
            organizationIdentifier: "org_live_readiness"
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: true,
            localOnlyMode: false
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences
        )
        let requests = await transport.requests()

        #expect(validation.isReady)
        #expect(validation.availableModels == ["gpt-4.1", "gpt-4.1-mini"])
        #expect(validation.selectedModelIsAvailable)
        #expect(requests.map(\.url) == ["https://api.openai.com/v1/models"])
        #expect(requests.map(\.authorizationHeader) == ["Bearer sk-test-live-readiness"])
        #expect(requests.map(\.openAIOrganizationHeader) == ["org_live_readiness"])
    }

    @MainActor
    @Test("Gemini OpenAI-compatible readiness preserves the v1beta openai models path")
    func geminiReadinessUsesOpenAICompatibleModelsPath() async throws {
        let secretReference = "flannel.ai.keys:provider/gemini/generativelanguage-googleapis-com"
        let transport = ProviderReadinessTransportRecorder(
            responses: [
                "https://generativelanguage.googleapis.com/v1beta/openai/models": .init(
                    statusCode: 200,
                    body: """
                    {
                      "object": "list",
                      "data": [
                        { "id": "gemini-2.5-pro", "object": "model", "owned_by": "google" },
                        { "id": "gemini-2.5-flash", "object": "model", "owned_by": "google" }
                      ]
                    }
                    """
                )
            ]
        )
        let service = ProviderSetupService(
            readinessTransport: { request in try await transport.send(request) },
            secretReader: { reference in
                #expect(reference.rawValue == secretReference)
                return "gemini-test-key"
            }
        )
        let provider = ProviderConfiguration(
            kind: .gemini,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Google Gemini API",
            endpoint: "https://generativelanguage.googleapis.com/v1beta/openai",
            modelIdentifier: "gemini-2.5-pro",
            secretReference: secretReference
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: true,
            localOnlyMode: false
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences
        )
        let requests = await transport.requests()

        #expect(validation.isReady)
        #expect(validation.availableModels == ["gemini-2.5-flash", "gemini-2.5-pro"])
        #expect(validation.selectedModelIsAvailable)
        #expect(requests.map(\.url) == ["https://generativelanguage.googleapis.com/v1beta/openai/models"])
        #expect(requests.map(\.authorizationHeader) == ["Bearer gemini-test-key"])
    }

    @MainActor
    @Test("Perplexity readiness still uses the provider models endpoint with v1")
    func perplexityReadinessUsesModelsPath() async throws {
        let secretReference = "flannel.ai.keys:provider/perplexity/api-perplexity-ai"
        let transport = ProviderReadinessTransportRecorder(
            responses: [
                "https://api.perplexity.ai/v1/models": .init(
                    statusCode: 200,
                    body: """
                    {
                      "object": "list",
                      "data": [
                        { "id": "sonar-pro", "object": "model", "owned_by": "perplexity" }
                      ]
                    }
                    """
                )
            ]
        )
        let service = ProviderSetupService(
            readinessTransport: { request in try await transport.send(request) },
            secretReader: { reference in
                #expect(reference.rawValue == secretReference)
                return "pplx-test-key"
            }
        )
        let provider = ProviderConfiguration(
            kind: .perplexity,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Perplexity API",
            endpoint: "https://api.perplexity.ai",
            modelIdentifier: "sonar-pro",
            secretReference: secretReference
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: true,
            localOnlyMode: false
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences
        )
        let requests = await transport.requests()

        #expect(validation.isReady)
        #expect(validation.availableModels == ["sonar-pro"])
        #expect(validation.selectedModelIsAvailable)
        #expect(requests.map(\.url) == ["https://api.perplexity.ai/v1/models"])
        #expect(requests.map(\.authorizationHeader) == ["Bearer pplx-test-key"])
    }

    @MainActor
    @Test("Readiness reports selected model missing from custom OpenAI-compatible model list")
    func customOpenAICompatibleReadinessReportsMissingModel() async throws {
        let transport = ProviderReadinessTransportRecorder(
            responses: [
                "http://localhost:8080/v1/models": .init(
                    statusCode: 200,
                    body: """
                    {
                      "object": "list",
                      "data": [
                        { "id": "other-model", "object": "model", "owned_by": "local-router" }
                      ]
                    }
                    """
                )
            ]
        )
        let service = ProviderSetupService(
            readinessTransport: { request in try await transport.send(request) }
        )
        let provider = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .externalAPI,
            displayName: "Local Router",
            endpoint: "http://localhost:8080/v1",
            modelIdentifier: "router-model",
            capabilities: [.chat, .streaming, .openAICompatible]
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: false,
            localOnlyMode: true
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences
        )

        #expect(validation.isReady == false)
        #expect(validation.connectionStatus == .needsAttention)
        #expect(validation.selectedModelIsAvailable == false)
        #expect(validation.availableModels == ["other-model"])
        #expect(validation.report.diagnostics.contains(where: { $0.code == .modelUnavailable }))
    }

    @MainActor
    @Test("Local server readiness delegates to injected local discovery")
    func localServerReadinessUsesInjectedDiscovery() async throws {
        let localDiscovery = ProviderLocalDiscoveryRecorder(
            result: LocalProviderDiscoveryResult(
                providerKind: .ollama,
                endpoint: "http://localhost:11434",
                status: .ready,
                models: [
                    LocalModelDescriptor(
                        name: "llama3.1:latest",
                        providerKind: .ollama,
                        endpoint: "http://localhost:11434"
                    )
                ]
            )
        )
        let service = ProviderSetupService(
            localDiscovery: { kind, endpoint in
                await localDiscovery.discover(kind: kind, endpoint: endpoint)
            }
        )
        let provider = ProviderConfiguration(
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Ollama",
            endpoint: " http://localhost:11434 ",
            modelIdentifier: "llama3.1:latest"
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: false,
            localOnlyMode: true
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences
        )
        let requests = await localDiscovery.requests()

        #expect(validation.isReady)
        #expect(validation.availableModels == ["llama3.1:latest"])
        #expect(validation.selectedModelIsAvailable)
        #expect(requests == [
            .init(kind: .ollama, endpoint: "http://localhost:11434")
        ])
    }

    @MainActor
    @Test("AI SDK bridge readiness checks the local health endpoint")
    func aiSDKBridgeReadinessChecksHealthEndpoint() async throws {
        let transport = ProviderReadinessTransportRecorder(
            responses: [
                "http://localhost:4177/api/health": .init(
                    statusCode: 200,
                    body: """
                    {
                      "status": "ready",
                      "models": [
                        "anthropic/claude-opus-4.7",
                        "openai/gpt-5-mini"
                      ]
                    }
                    """
                )
            ]
        )
        let service = ProviderSetupService(
            readinessTimeout: 5,
            readinessTransport: { request in try await transport.send(request) }
        )
        let provider = ProviderConfiguration(
            kind: .vercelAISDKBridge,
            accessMode: .aiSDKBridge,
            privacyScope: .bridgeService,
            displayName: "Local AI SDK Bridge",
            endpoint: "http://localhost:4177",
            modelIdentifier: "openai/gpt-5-mini",
            capabilities: [.chat, .streaming, .toolCalling]
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: true,
            localOnlyMode: false
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences
        )
        let requests = await transport.requests()

        #expect(validation.isReady)
        #expect(validation.availableModels == [
            "anthropic/claude-opus-4.7",
            "openai/gpt-5-mini"
        ])
        #expect(validation.selectedModelIsAvailable)
        #expect(requests.map(\.url) == ["http://localhost:4177/api/health"])
        #expect(requests.map(\.timeout) == [5])
        #expect(requests.map(\.acceptHeader) == ["application/json"])
    }

    @MainActor
    @Test("AI SDK bridge readiness accepts a chat endpoint and falls back to configured model")
    func aiSDKBridgeReadinessUsesConfiguredModelWhenHealthHasNoModelList() async throws {
        let transport = ProviderReadinessTransportRecorder(
            responses: [
                "http://localhost:4177/api/health": .init(
                    statusCode: 200,
                    body: """
                    { "status": "ok" }
                    """
                )
            ]
        )
        let service = ProviderSetupService(
            readinessTransport: { request in try await transport.send(request) }
        )
        let provider = ProviderConfiguration(
            kind: .vercelAISDKBridge,
            accessMode: .aiSDKBridge,
            privacyScope: .bridgeService,
            displayName: "Local AI SDK Bridge",
            endpoint: "http://localhost:4177/api/chat",
            modelIdentifier: "bridge-default-model",
            capabilities: [.chat, .streaming, .toolCalling]
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: true,
            localOnlyMode: false
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences
        )
        let requests = await transport.requests()

        #expect(validation.isReady)
        #expect(validation.availableModels == ["bridge-default-model"])
        #expect(validation.selectedModelIsAvailable)
        #expect(requests.map(\.url) == ["http://localhost:4177/api/health"])
    }

    @MainActor
    @Test("AI SDK bridge readiness reports unhealthy bridge status")
    func aiSDKBridgeReadinessReportsUnhealthyStatus() async throws {
        let transport = ProviderReadinessTransportRecorder(
            responses: [
                "http://localhost:4177/api/health": .init(
                    statusCode: 200,
                    body: """
                    { "status": "not_ready", "message": "provider env vars missing" }
                    """
                )
            ]
        )
        let service = ProviderSetupService(
            readinessTransport: { request in try await transport.send(request) }
        )
        let provider = ProviderConfiguration(
            kind: .vercelAISDKBridge,
            accessMode: .aiSDKBridge,
            privacyScope: .bridgeService,
            displayName: "Local AI SDK Bridge",
            endpoint: "http://localhost:4177",
            modelIdentifier: "bridge-default-model",
            capabilities: [.chat, .streaming, .toolCalling]
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: true,
            localOnlyMode: false
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences
        )

        #expect(validation.isReady == false)
        #expect(validation.connectionStatus == .needsAttention)
        #expect(validation.errorMessage == "provider env vars missing")
        #expect(validation.report.diagnostics.contains(where: { $0.code == .providerUnavailable }))
    }

    @Test("Subscription CLI providers are blocked when the executable is missing")
    func subscriptionCLIProviderReportCapturesMissingExecutable() {
        let service = ProviderSetupService(
            cliTransport: CLIProviderTransport(resolveExecutable: { _ in nil })
        )
        let provider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "codex exec --json -",
            modelIdentifier: "chatgpt-subscription"
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: false,
            localOnlyMode: false
        )

        let report = service.report(for: provider, preferences: preferences)

        #expect(report.routingEligibility == .eligible)
        #expect(report.hasBlockingIssues)
        #expect(report.diagnostics.contains(where: { $0.code == .missingCLIExecutable }))
    }

    @MainActor
    @Test("Subscription CLI readiness runs a smoke probe and validates decoded output")
    func subscriptionCLIReadinessRunsSmokeProbeAndValidatesOutput() async {
        let commandRecorder = CLIReadinessCommandRecorder()
        let service = ProviderSetupService(
            cliTransport: CLIProviderTransport(
                resolveExecutable: { executable in
                    executable == "codex" ? URL(fileURLWithPath: "/usr/bin/true") : nil
                },
                executeCommand: { command in
                    AsyncThrowingStream { continuation in
                        Task {
                            await commandRecorder.record(command)
                            continuation.yield("flannel-ready")
                            continuation.finish()
                        }
                    }
                }
            )
        )
        let provider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "codex exec --json -",
            modelIdentifier: "chatgpt-subscription"
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: false,
            localOnlyMode: false
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences,
            checkedAt: Date(timeIntervalSince1970: 1_780_000_001)
        )

        #expect(validation.isReady)
        #expect(validation.connectionStatus == .ready)
        #expect(validation.availableModels == ["chatgpt-subscription"])
        #expect(validation.selectedModelIsAvailable)
        #expect(validation.errorMessage == nil)
        #expect(validation.checkedAt == Date(timeIntervalSince1970: 1_780_000_001))

        let commands = await commandRecorder.commands()
        #expect(commands.count == 1)
        #expect(commands.first?.providerDisplayName == "ChatGPT/Codex CLI")
        #expect(commands.first?.timeout == .seconds(4))
        #expect(commands.first?.stdinText?.contains("Flannel local CLI readiness check") == true)
    }

    @MainActor
    @Test("Subscription CLI readiness fails when command executable is unavailable")
    func subscriptionCLIReadinessFailsMissingExecutable() async {
        let service = ProviderSetupService(
            cliTransport: CLIProviderTransport(resolveExecutable: { _ in nil })
        )
        let provider = ProviderConfiguration(
            kind: .claudeCodeCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "Claude Code CLI",
            endpoint: "claude -p --output-format stream-json {prompt}",
            modelIdentifier: "claude-subscription"
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: false,
            localOnlyMode: false
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences
        )

        #expect(validation.isReady == false)
        #expect(validation.connectionStatus == .needsAttention)
        #expect(validation.selectedModelIsAvailable == false)
        #expect(validation.report.diagnostics.contains(where: { $0.code == .missingCLIExecutable }))
        #expect(validation.errorMessage?.contains("claude") == true)
    }

    @MainActor
    @Test("Subscription CLI readiness fails when the smoke probe returns no decoded text")
    func subscriptionCLIReadinessFailsEmptySmokeProbe() async {
        let commandRecorder = CLIReadinessCommandRecorder()
        let service = ProviderSetupService(
            cliTransport: CLIProviderTransport(
                resolveExecutable: { executable in
                    executable == "claude" ? URL(fileURLWithPath: "/usr/bin/true") : nil
                },
                executeCommand: { command in
                    AsyncThrowingStream { continuation in
                        Task {
                            await commandRecorder.record(command)
                            continuation.finish()
                        }
                    }
                }
            )
        )
        let provider = ProviderConfiguration(
            kind: .claudeCodeCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "Claude Code CLI",
            endpoint: "claude -p --output-format stream-json {prompt}",
            modelIdentifier: "claude-subscription"
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: false,
            localOnlyMode: false
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences,
            checkedAt: Date(timeIntervalSince1970: 1_780_000_002)
        )

        #expect(validation.isReady == false)
        #expect(validation.connectionStatus == .needsAttention)
        #expect(validation.selectedModelIsAvailable == false)
        #expect(validation.report.diagnostics.contains(where: { $0.code == .cliSmokeProbeFailed }))
        #expect(validation.errorMessage?.contains("could not decode any assistant text") == true)
        #expect(validation.checkedAt == Date(timeIntervalSince1970: 1_780_000_002))

        let commands = await commandRecorder.commands()
        #expect(commands.count == 1)
        #expect(commands.first?.arguments.contains("-p") == true)
        #expect(commands.first?.arguments.contains("--output-format") == true)
    }

    @MainActor
    @Test("Subscription CLI readiness requires the expected smoke probe token")
    func subscriptionCLIReadinessRequiresExpectedSmokeProbeToken() async {
        let commandRecorder = CLIReadinessCommandRecorder()
        let service = ProviderSetupService(
            cliTransport: CLIProviderTransport(
                resolveExecutable: { executable in
                    executable == "codex" ? URL(fileURLWithPath: "/usr/bin/true") : nil
                },
                executeCommand: { command in
                    AsyncThrowingStream { continuation in
                        Task {
                            await commandRecorder.record(command)
                            continuation.yield("Signed in and ready")
                            continuation.finish()
                        }
                    }
                }
            )
        )
        let provider = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "codex exec --json -",
            modelIdentifier: "chatgpt-subscription"
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: false,
            localOnlyMode: false
        )

        let validation = await service.validateReadiness(
            for: provider,
            preferences: preferences,
            checkedAt: Date(timeIntervalSince1970: 1_780_000_003)
        )

        #expect(validation.isReady == false)
        #expect(validation.connectionStatus == .needsAttention)
        #expect(validation.selectedModelIsAvailable == false)
        #expect(validation.report.diagnostics.contains(where: { $0.code == .cliSmokeProbeFailed }))
        #expect(validation.errorMessage?.contains("did not match the expected flannel-ready token") == true)
        #expect(validation.checkedAt == Date(timeIntervalSince1970: 1_780_000_003))

        let commands = await commandRecorder.commands()
        #expect(commands.count == 1)
        #expect(commands.first?.stdinText?.contains("flannel-ready") == true)
    }

    @Test("Claude subscription CLI providers require print mode or a prompt placeholder")
    func claudeCLIProviderReportRequiresPrintMode() {
        let service = ProviderSetupService(
            cliTransport: CLIProviderTransport(resolveExecutable: { _ in URL(fileURLWithPath: "/usr/bin/true") })
        )
        let provider = ProviderConfiguration(
            kind: .claudeCodeCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "Claude Code CLI",
            endpoint: "claude",
            modelIdentifier: "claude-subscription"
        )
        let preferences = WorkspacePreferences(
            allowCloudProviders: false,
            localOnlyMode: false
        )

        let report = service.report(for: provider, preferences: preferences)

        #expect(report.hasBlockingIssues)
        #expect(report.diagnostics.contains(where: { $0.code == .claudePrintModeRequired }))
    }
}

private actor ProviderReadinessTransportRecorder {
    struct Response: Sendable {
        var statusCode: Int
        var body: String
    }

    struct RecordedRequest: Equatable, Sendable {
        var url: String
        var timeout: TimeInterval
        var acceptHeader: String?
        var authorizationHeader: String?
        var openAIOrganizationHeader: String?
    }

    private let responses: [String: Response]
    private var recordedRequests: [RecordedRequest] = []

    init(responses: [String: Response]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse?) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        let urlString = url.absoluteString
        recordedRequests.append(
            RecordedRequest(
                url: urlString,
                timeout: request.timeoutInterval,
                acceptHeader: request.value(forHTTPHeaderField: "Accept"),
                authorizationHeader: request.value(forHTTPHeaderField: "Authorization"),
                openAIOrganizationHeader: request.value(forHTTPHeaderField: "OpenAI-Organization")
            )
        )

        guard let response = responses[urlString],
              let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
              ) else {
            throw URLError(.unsupportedURL)
        }

        return (Data(response.body.utf8), httpResponse)
    }

    func requests() -> [RecordedRequest] {
        recordedRequests
    }
}

private actor CLIReadinessCommandRecorder {
    private var recordedCommands: [CLIProviderPreparedCommand] = []

    func record(_ command: CLIProviderPreparedCommand) {
        recordedCommands.append(command)
    }

    func commands() -> [CLIProviderPreparedCommand] {
        recordedCommands
    }
}

private actor ProviderLocalDiscoveryRecorder {
    struct RecordedRequest: Equatable, Sendable {
        var kind: LLMProviderKind
        var endpoint: String
    }

    private let result: LocalProviderDiscoveryResult
    private var recordedRequests: [RecordedRequest] = []

    init(result: LocalProviderDiscoveryResult) {
        self.result = result
    }

    func discover(kind: LLMProviderKind, endpoint: String) -> LocalProviderDiscoveryResult {
        recordedRequests.append(.init(kind: kind, endpoint: endpoint))
        return result
    }

    func requests() -> [RecordedRequest] {
        recordedRequests
    }
}
