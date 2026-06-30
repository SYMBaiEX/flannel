//
//  ProviderSetupService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

nonisolated enum ProviderSetupDiagnosticSeverity: String, Hashable, Sendable {
    case error
    case warning
    case info
}

nonisolated enum ProviderSetupDiagnosticCode: String, Hashable, Sendable {
    case missingEndpoint
    case invalidEndpoint
    case insecureRemoteEndpoint
    case missingModelIdentifier
    case missingKeychainReference
    case keychainReferenceShouldBeCanonical
    case missingCLICommand
    case invalidCLICommand
    case missingCLIExecutable
    case claudePrintModeRequired
    case cliStatusCheckFailed
    case cliSmokeProbeFailed
    case blockedByLocalOnlyMode
    case blockedByCloudPreference
    case providerUnavailable
    case providerReturnedNoModels
    case modelUnavailable
}

nonisolated struct ProviderSetupDiagnostic: Identifiable, Hashable, Sendable {
    var code: ProviderSetupDiagnosticCode
    var severity: ProviderSetupDiagnosticSeverity
    var field: String?
    var message: String

    var id: String {
        [code.rawValue, field].compactMap { $0 }.joined(separator: ":")
    }

    var isBlocking: Bool {
        severity == .error
    }
}

nonisolated enum ProviderRoutingEligibility: String, Hashable, Sendable {
    case eligible
    case blockedByLocalOnlyMode
    case blockedByCloudPreference
}

nonisolated struct ProviderSetupReport: Hashable, Sendable {
    var normalizedEndpoint: String?
    var normalizedModelIdentifier: String
    var canonicalSecretReference: KeychainSecretReference?
    var routingEligibility: ProviderRoutingEligibility
    var diagnostics: [ProviderSetupDiagnostic]

    var hasBlockingIssues: Bool {
        diagnostics.contains(where: \.isBlocking)
    }
}

nonisolated struct ProviderReadinessValidation: Hashable, Sendable {
    var report: ProviderSetupReport
    var connectionStatus: IntegrationConnectionStatus
    var availableModels: [String]
    var selectedModelIdentifier: String
    var selectedModelIsAvailable: Bool
    var checkedAt: Date
    var errorMessage: String?

    var isReady: Bool {
        connectionStatus == .ready && report.hasBlockingIssues == false
    }
}

nonisolated struct ProviderSetupService: Sendable {
    typealias ReadinessTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse?)
    typealias LocalDiscovery = @Sendable (LLMProviderKind, String) async -> LocalProviderDiscoveryResult?
    typealias SecretReader = @Sendable (KeychainSecretReference) throws -> String

    static let shared = ProviderSetupService()

    var cliTransport: CLIProviderTransport
    private var readinessTransport: ReadinessTransport
    private var localDiscovery: LocalDiscovery
    private var secretReader: SecretReader
    private var readinessTimeout: TimeInterval
    private static let cliReadinessExpectedToken = "flannel-ready"
    private static let cliReadinessProbePrompt = """
    This is a Flannel local CLI readiness check. Do not inspect files, run commands, use tools, or modify anything. Reply with exactly:
    flannel-ready
    """
    private static let cliReadinessProbeSystemPrompt = "You are responding to a local Flannel provider readiness check. Return only the requested readiness token."

    init(
        cliTransport: CLIProviderTransport = CLIProviderTransport(),
        readinessTimeout: TimeInterval = 4,
        readinessTransport: @escaping ReadinessTransport = Self.urlSessionReadinessTransport,
        secretReader: SecretReader? = nil,
        localDiscovery: LocalDiscovery? = nil
    ) {
        self.cliTransport = cliTransport
        self.readinessTimeout = readinessTimeout
        self.readinessTransport = readinessTransport
        self.secretReader = secretReader ?? { reference in
            try KeychainSecretStore().read(reference)
        }
        self.localDiscovery = localDiscovery ?? { kind, endpoint in
            await LocalProviderDiscoveryService(timeout: readinessTimeout)
                .discover(targets: [(kind, endpoint)])
                .first
        }
    }

    func report(
        for provider: ProviderConfiguration,
        preferences: WorkspacePreferences
    ) -> ProviderSetupReport {
        let normalizedEndpoint = normalizedEndpoint(from: provider.endpoint)
        let normalizedModelIdentifier = provider.modelIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalSecretReference = canonicalSecretReference(for: provider)
        let routingEligibility = routingEligibility(for: provider, preferences: preferences)
        let runtimePolicy = provider.runtimePolicy

        var diagnostics: [ProviderSetupDiagnostic] = []

        if runtimePolicy.requiresEndpoint {
            if normalizedEndpoint == nil {
                diagnostics.append(
                    ProviderSetupDiagnostic(
                        code: trimmed(provider.endpoint).isEmpty ? .missingEndpoint : .invalidEndpoint,
                        severity: .error,
                        field: "endpoint",
                        message: "Enter a valid provider endpoint before this configuration can be used."
                    )
                )
            } else if runtimePolicy.requiresHTTPSForRemoteEndpoint,
                      let url = normalizedEndpoint.flatMap(URL.init(string:)),
                      url.scheme?.lowercased() != "https",
                      !isLoopback(url) {
                diagnostics.append(
                    ProviderSetupDiagnostic(
                        code: .insecureRemoteEndpoint,
                        severity: .warning,
                        field: "endpoint",
                        message: "Remote API providers should use HTTPS unless they stay on loopback."
                    )
                )
            }
        }

        if normalizedModelIdentifier.isEmpty {
            diagnostics.append(
                ProviderSetupDiagnostic(
                    code: .missingModelIdentifier,
                    severity: .error,
                    field: "modelIdentifier",
                    message: "Choose a model before enabling this provider."
                )
            )
        }

        if runtimePolicy.requiresKeychainSecret {
            if let storedReference = parseSecretReference(provider.secretReference) {
                if let canonicalSecretReference,
                   storedReference != canonicalSecretReference {
                    diagnostics.append(
                        ProviderSetupDiagnostic(
                            code: .keychainReferenceShouldBeCanonical,
                            severity: .info,
                            field: "secretReference",
                            message: "Use the canonical Keychain reference \(canonicalSecretReference.rawValue) for consistent secret lookup."
                        )
                    )
                }
            } else {
                diagnostics.append(
                    ProviderSetupDiagnostic(
                        code: .missingKeychainReference,
                        severity: .error,
                        field: "secretReference",
                        message: "Save this provider's API key in Keychain before enabling cloud requests."
                    )
                )
            }
        }

        if let cliDiagnostic = subscriptionCLIDiagnostic(for: provider) {
            diagnostics.append(cliDiagnostic)
        }

        switch routingEligibility {
        case .eligible:
            break
        case .blockedByLocalOnlyMode:
            diagnostics.append(
                ProviderSetupDiagnostic(
                    code: .blockedByLocalOnlyMode,
                    severity: .warning,
                    field: "privacyScope",
                    message: "Local-only mode is enabled, so this provider cannot become active."
                )
            )
        case .blockedByCloudPreference:
            diagnostics.append(
                ProviderSetupDiagnostic(
                    code: .blockedByCloudPreference,
                    severity: .warning,
                    field: "privacyScope",
                    message: "Cloud providers are disabled in preferences, so this provider cannot become active."
                )
            )
        }

        return ProviderSetupReport(
            normalizedEndpoint: normalizedEndpoint,
            normalizedModelIdentifier: normalizedModelIdentifier,
            canonicalSecretReference: canonicalSecretReference,
            routingEligibility: routingEligibility,
            diagnostics: diagnostics
        )
    }

    func validateReadiness(
        for provider: ProviderConfiguration,
        preferences: WorkspacePreferences,
        checkedAt: Date = .now
    ) async -> ProviderReadinessValidation {
        var setupReport = report(for: provider, preferences: preferences)
        let selectedModelIdentifier = setupReport.normalizedModelIdentifier

        guard setupReport.routingEligibility == .eligible else {
            return ProviderReadinessValidation(
                report: setupReport,
                connectionStatus: .needsAttention,
                availableModels: provider.availableModels,
                selectedModelIdentifier: selectedModelIdentifier,
                selectedModelIsAvailable: providerHasSelectedModel(provider, selectedModelIdentifier),
                checkedAt: checkedAt,
                errorMessage: setupReport.diagnostics.first?.message
            )
        }

        guard setupReport.hasBlockingIssues == false else {
            return ProviderReadinessValidation(
                report: setupReport,
                connectionStatus: .needsAttention,
                availableModels: provider.availableModels,
                selectedModelIdentifier: selectedModelIdentifier,
                selectedModelIsAvailable: providerHasSelectedModel(provider, selectedModelIdentifier),
                checkedAt: checkedAt,
                errorMessage: setupReport.diagnostics.first(where: \.isBlocking)?.message
            )
        }

        if provider.runtimePolicy.readinessStrategy == .cliCommandResolution {
            return await cliSubscriptionReadiness(
                for: provider,
                setupReport: setupReport,
                selectedModelIdentifier: selectedModelIdentifier,
                checkedAt: checkedAt
            )
        }

        guard provider.runtimePolicy.readinessStrategy != .staticConfiguration,
              let endpoint = setupReport.normalizedEndpoint else {
            let configuredModels = configuredAvailableModels(
                for: provider,
                selectedModelIdentifier: selectedModelIdentifier
            )
            return ProviderReadinessValidation(
                report: setupReport,
                connectionStatus: .ready,
                availableModels: configuredModels,
                selectedModelIdentifier: selectedModelIdentifier,
                selectedModelIsAvailable: !selectedModelIdentifier.isEmpty,
                checkedAt: checkedAt,
                errorMessage: nil
            )
        }

        let availability = await modelAvailability(
            for: provider,
            endpoint: endpoint,
            checkedAt: checkedAt
        )
        let availableModelNames = availability.models.map(\.name).sorted()
        let selectedModelIsAvailable = containsModel(
            availability.models,
            matching: selectedModelIdentifier
        )

        if availability.status != .ready {
            setupReport.diagnostics.append(
                ProviderSetupDiagnostic(
                    code: .providerUnavailable,
                    severity: .error,
                    field: "endpoint",
                    message: availability.errorMessage ?? "The provider did not respond to a readiness check."
                )
            )
        } else if availability.models.isEmpty {
            setupReport.diagnostics.append(
                ProviderSetupDiagnostic(
                    code: .providerReturnedNoModels,
                    severity: .error,
                    field: "endpoint",
                    message: "The provider is reachable, but it did not return any models."
                )
            )
        } else if selectedModelIsAvailable == false {
            setupReport.diagnostics.append(
                ProviderSetupDiagnostic(
                    code: .modelUnavailable,
                    severity: .error,
                    field: "modelIdentifier",
                    message: "The selected model \(selectedModelIdentifier) was not returned by this provider."
                )
            )
        }

        return ProviderReadinessValidation(
            report: setupReport,
            connectionStatus: setupReport.hasBlockingIssues ? .needsAttention : .ready,
            availableModels: availableModelNames,
            selectedModelIdentifier: selectedModelIdentifier,
            selectedModelIsAvailable: selectedModelIsAvailable,
            checkedAt: availability.checkedAt,
            errorMessage: setupReport.diagnostics.first(where: \.isBlocking)?.message ?? availability.errorMessage
        )
    }

    func subscriptionCLIDiagnostic(for provider: ProviderConfiguration) -> ProviderSetupDiagnostic? {
        guard provider.accessMode == .subscriptionCLI else { return nil }

        let request = ChatStreamingRequest(
            provider: provider,
            messages: [
                AssistantMessage(role: .user, text: "Provider readiness check")
            ],
            systemPrompt: nil
        )

        do {
            _ = try cliTransport.makePreparedCommand(for: request)
            return nil
        } catch let error as CLIProviderTransportError {
            return diagnostic(for: error, provider: provider)
        } catch {
            return ProviderSetupDiagnostic(
                code: .invalidCLICommand,
                severity: .error,
                field: "endpoint",
                message: error.localizedDescription
            )
        }
    }

    private func cliSubscriptionReadiness(
        for provider: ProviderConfiguration,
        setupReport: ProviderSetupReport,
        selectedModelIdentifier: String,
        checkedAt: Date
    ) async -> ProviderReadinessValidation {
        var report = setupReport

        do {
            try await runCLIStatusCheck(for: provider)
        } catch {
            return cliReadinessFailureValidation(
                for: provider,
                report: &report,
                selectedModelIdentifier: selectedModelIdentifier,
                checkedAt: checkedAt,
                diagnostic: cliStatusCheckDiagnostic(for: error, provider: provider)
            )
        }

        do {
            _ = try await runCLIReadinessSmokeProbe(for: provider)
            return ProviderReadinessValidation(
                report: report,
                connectionStatus: .ready,
                availableModels: configuredAvailableModels(
                    for: provider,
                    selectedModelIdentifier: selectedModelIdentifier
                ),
                selectedModelIdentifier: selectedModelIdentifier,
                selectedModelIsAvailable: !selectedModelIdentifier.isEmpty,
                checkedAt: checkedAt,
                errorMessage: nil
            )
        } catch {
            return cliReadinessFailureValidation(
                for: provider,
                report: &report,
                selectedModelIdentifier: selectedModelIdentifier,
                checkedAt: checkedAt,
                diagnostic: cliSmokeProbeDiagnostic(for: error, provider: provider)
            )
        }
    }

    private func runCLIStatusCheck(for provider: ProviderConfiguration) async throws {
        var readinessTransport = cliTransport
        readinessTransport.commandBuilder.timeout = .seconds(max(1, Int(ceil(readinessTimeout))))
        guard let commandSpec = try readinessTransport.commandBuilder.makeReadinessStatusCommandSpec(for: provider) else {
            return
        }

        for try await _ in readinessTransport.streamText(for: commandSpec) {
            // Exit status is the contract boundary for auth/status checks.
        }
    }

    private func runCLIReadinessSmokeProbe(for provider: ProviderConfiguration) async throws -> String {
        var smokeTransport = cliTransport
        smokeTransport.commandBuilder.timeout = .seconds(max(1, Int(ceil(readinessTimeout))))
        var output = ""
        let request = ChatStreamingRequest(
            provider: provider,
            messages: [
                AssistantMessage(role: .user, text: Self.cliReadinessProbePrompt)
            ],
            systemPrompt: Self.cliReadinessProbeSystemPrompt,
            tools: []
        )

        for try await chunk in smokeTransport.streamText(for: request) {
            output.append(chunk)
        }

        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            throw CLIReadinessSmokeProbeError.emptyOutput(provider.displayName)
        }
        guard Self.normalizedReadinessToken(trimmedOutput) == Self.cliReadinessExpectedToken else {
            throw CLIReadinessSmokeProbeError.unexpectedOutput(provider.displayName, trimmedOutput)
        }
        return trimmedOutput
    }

    private static func normalizedReadinessToken(_ output: String) -> String {
        output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func routingEligibility(
        for provider: ProviderConfiguration,
        preferences: WorkspacePreferences
    ) -> ProviderRoutingEligibility {
        guard !isLocalExecutionBoundary(provider) else {
            return .eligible
        }

        if preferences.localOnlyMode ?? true {
            return .blockedByLocalOnlyMode
        }

        if provider.privacyScope == .localCLI {
            return .eligible
        }

        if !(preferences.allowCloudProviders ?? false) {
            return .blockedByCloudPreference
        }

        return .eligible
    }

    func isEligibleForActivation(
        _ provider: ProviderConfiguration,
        preferences: WorkspacePreferences
    ) -> Bool {
        routingEligibility(for: provider, preferences: preferences) == .eligible
    }

    func canonicalSecretReference(for provider: ProviderConfiguration) -> KeychainSecretReference? {
        guard requiresKeychainSecret(for: provider) || supportsOptionalKeychainSecret(provider) else {
            return nil
        }

        return KeychainSecretReference(
            service: KeychainSecretStore.defaultService,
            account: canonicalSecretAccount(for: provider)
        )
    }

    func canonicalSecretReferenceString(for provider: ProviderConfiguration) -> String? {
        canonicalSecretReference(for: provider)?.rawValue
    }

    func requiresKeychainSecret(for provider: ProviderConfiguration) -> Bool {
        provider.runtimePolicy.requiresKeychainSecret
    }

    func parseSecretReference(_ rawValue: String?) -> KeychainSecretReference? {
        let trimmedValue = trimmed(rawValue)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        let parts = trimmedValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              !parts[0].isEmpty,
              !parts[1].isEmpty else {
            return KeychainSecretReference(
                service: KeychainSecretStore.defaultService,
                account: trimmedValue
            )
        }

        return KeychainSecretReference(service: parts[0], account: parts[1])
    }

    private func modelAvailability(
        for provider: ProviderConfiguration,
        endpoint: String,
        checkedAt: Date
    ) async -> ProviderModelAvailability {
        switch provider.runtimePolicy.readinessStrategy {
        case .localModelDiscovery:
            guard let result = await localDiscovery(provider.kind, endpoint) else {
                return ProviderModelAvailability(
                    status: .needsAttention,
                    models: [],
                    errorMessage: "No local discovery route is available for this provider.",
                    checkedAt: checkedAt
                )
            }

            return ProviderModelAvailability(
                status: result.status,
                models: result.models.map {
                    ProviderAvailableModel(name: $0.name, displayName: $0.displayName)
                },
                errorMessage: result.errorMessage,
                checkedAt: result.discoveredAt
            )
        case .openAICompatibleModels:
            return await openAICompatibleModelAvailability(
                for: provider,
                endpoint: endpoint,
                checkedAt: checkedAt
            )
        case .aiSDKBridgeHealth:
            return await aiSDKBridgeAvailability(
                for: provider,
                endpoint: endpoint,
                checkedAt: checkedAt
            )
        case .staticConfiguration, .cliCommandResolution:
            return ProviderModelAvailability(
                status: .ready,
                models: provider.availableModels.map { ProviderAvailableModel(name: $0) },
                errorMessage: nil,
                checkedAt: checkedAt
            )
        }
    }

    private func aiSDKBridgeAvailability(
        for provider: ProviderConfiguration,
        endpoint: String,
        checkedAt: Date
    ) async -> ProviderModelAvailability {
        do {
            let request = try makeAISDKBridgeHealthRequest(for: provider, endpoint: endpoint)
            let (data, urlResponse) = try await readinessTransport(request)
            guard let httpResponse = urlResponse else {
                throw ProviderReadinessError.badResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ProviderReadinessError.badStatus(httpResponse.statusCode)
            }

            let health = try AISDKBridgeHealthResponse.decodeIfPresent(from: data)
            if health?.isReady == false {
                return ProviderModelAvailability(
                    status: .needsAttention,
                    models: bridgeFallbackModels(for: provider),
                    errorMessage: health?.message ?? "The AI SDK bridge reported that it is not ready.",
                    checkedAt: checkedAt
                )
            }

            let models = health?.availableModels.isEmpty == false
                ? health?.availableModels ?? []
                : bridgeFallbackModels(for: provider)

            return ProviderModelAvailability(
                status: .ready,
                models: models,
                errorMessage: health?.message,
                checkedAt: checkedAt
            )
        } catch {
            return ProviderModelAvailability(
                status: .needsAttention,
                models: bridgeFallbackModels(for: provider),
                errorMessage: error.localizedDescription,
                checkedAt: checkedAt
            )
        }
    }

    private func openAICompatibleModelAvailability(
        for provider: ProviderConfiguration,
        endpoint: String,
        checkedAt: Date
    ) async -> ProviderModelAvailability {
        do {
            let request = try makeOpenAICompatibleModelsRequest(for: provider, endpoint: endpoint)
            let (data, urlResponse) = try await readinessTransport(request)
            guard let httpResponse = urlResponse else {
                throw ProviderReadinessError.badResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ProviderReadinessError.badStatus(httpResponse.statusCode)
            }

            let modelList = try JSONDecoder().decode(OpenAICompatibleModelListResponse.self, from: data)
            return ProviderModelAvailability(
                status: .ready,
                models: modelList.data.map { ProviderAvailableModel(name: $0.id, displayName: $0.id) },
                errorMessage: nil,
                checkedAt: checkedAt
            )
        } catch {
            return ProviderModelAvailability(
                status: .needsAttention,
                models: [],
                errorMessage: error.localizedDescription,
                checkedAt: checkedAt
            )
        }
    }

    private func bridgeFallbackModels(for provider: ProviderConfiguration) -> [ProviderAvailableModel] {
        configuredAvailableModels(
            for: provider,
            selectedModelIdentifier: provider.modelIdentifier
        )
        .map { ProviderAvailableModel(name: $0, displayName: $0) }
    }

    private func requiresEndpoint(_ provider: ProviderConfiguration) -> Bool {
        provider.runtimePolicy.requiresEndpoint
    }

    private func requiresHTTPS(_ provider: ProviderConfiguration) -> Bool {
        provider.runtimePolicy.requiresHTTPSForRemoteEndpoint
    }

    private func supportsOptionalKeychainSecret(_ provider: ProviderConfiguration) -> Bool {
        provider.runtimePolicy.supportsOptionalKeychainSecret
    }

    private func isLocalExecutionBoundary(_ provider: ProviderConfiguration) -> Bool {
        if provider.privacyScope == .localOnly {
            return true
        }

        guard provider.accessMode == .openAICompatible,
              let endpoint = normalizedEndpoint(from: provider.endpoint),
              let url = URL(string: endpoint) else {
            return false
        }

        return isLoopback(url)
    }

    private func diagnostic(for error: CLIProviderTransportError, provider: ProviderConfiguration) -> ProviderSetupDiagnostic {
        let code: ProviderSetupDiagnosticCode
        switch error {
        case .missingCommandContract:
            code = .missingCLICommand
        case .missingExecutable:
            code = .missingCLIExecutable
        case .claudePrintModeRequired:
            code = .claudePrintModeRequired
        case .unsupportedProvider, .unsupportedShellSyntax, .unterminatedQuote, .danglingEscape,
             .missingModelPlaceholderValue, .failedToStart, .processTimedOut,
             .processExitedNonZero, .invalidUTF8Output, .invalidStructuredOutput, .cancelled:
            code = .invalidCLICommand
        }

        let message = appendCLIRecommendation(
            to: error.localizedDescription,
            provider: provider
        )
        return ProviderSetupDiagnostic(
            code: code,
            severity: .error,
            field: "endpoint",
            message: message
        )
    }

    private func cliStatusCheckDiagnostic(
        for error: Error,
        provider: ProviderConfiguration
    ) -> ProviderSetupDiagnostic {
        let code: ProviderSetupDiagnosticCode
        if let transportError = error as? CLIProviderTransportError,
           case .missingExecutable = transportError {
            code = .missingCLIExecutable
        } else {
            code = .cliStatusCheckFailed
        }

        return ProviderSetupDiagnostic(
            code: code,
            severity: .error,
            field: "endpoint",
            message: appendCLIRecommendation(
                to: error.localizedDescription,
                provider: provider
            )
        )
    }

    private func cliSmokeProbeDiagnostic(
        for error: Error,
        provider: ProviderConfiguration
    ) -> ProviderSetupDiagnostic {
        let code: ProviderSetupDiagnosticCode
        if let transportError = error as? CLIProviderTransportError,
           case .missingExecutable = transportError {
            code = .missingCLIExecutable
        } else {
            code = .cliSmokeProbeFailed
        }

        return ProviderSetupDiagnostic(
            code: code,
            severity: .error,
            field: "endpoint",
            message: appendCLIRecommendation(
                to: error.localizedDescription,
                provider: provider
            )
        )
    }

    private func cliReadinessFailureValidation(
        for provider: ProviderConfiguration,
        report: inout ProviderSetupReport,
        selectedModelIdentifier: String,
        checkedAt: Date,
        diagnostic: ProviderSetupDiagnostic
    ) -> ProviderReadinessValidation {
        if !report.diagnostics.contains(where: { $0.id == diagnostic.id }) {
            report.diagnostics.append(diagnostic)
        }

        return ProviderReadinessValidation(
            report: report,
            connectionStatus: .needsAttention,
            availableModels: provider.availableModels,
            selectedModelIdentifier: selectedModelIdentifier,
            selectedModelIsAvailable: false,
            checkedAt: checkedAt,
            errorMessage: diagnostic.message
        )
    }

    private func appendCLIRecommendation(
        to message: String,
        provider: ProviderConfiguration
    ) -> String {
        guard provider.accessMode == .subscriptionCLI,
              let recommendedCommand = provider.providerCatalogEntry?.recommendedCLICommand,
              !recommendedCommand.isEmpty else {
            return message
        }

        if message.contains(recommendedCommand) {
            return message
        }

        return "\(message) Recommended command: \(recommendedCommand)"
    }

    private func makeOpenAICompatibleModelsRequest(for provider: ProviderConfiguration, endpoint: String) throws -> URLRequest {
        let appendedPath = Self.openAICompatibleModelsPathComponents(
            endpoint: endpoint
        )

        var request = URLRequest(url: try Self.endpointURL(endpoint, appending: appendedPath))
        request.timeoutInterval = readinessTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if requiresKeychainSecret(for: provider) {
            guard let secretReference = parseSecretReference(provider.secretReference) else {
                throw ProviderReadinessError.missingKeychainReference(provider.displayName)
            }
            let apiKey = try secretReader(secretReference).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw ProviderReadinessError.emptyKeychainSecret(provider.displayName)
            }
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else if let secretReference = parseSecretReference(provider.secretReference) {
            let apiKey = try secretReader(secretReference).trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }

        if provider.kind == .openAI {
            let organization = trimmed(provider.organizationIdentifier)
            if !organization.isEmpty {
                request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
            }
        }

        return request
    }

    private static func openAICompatibleModelsPathComponents(
        endpoint: String
    ) -> [String] {
        let pathComponents = endpointPathComponents(endpoint)
        let normalizedPathComponents = pathComponents.map { $0.lowercased() }

        if normalizedPathComponents.last == "models" {
            return []
        }

        if normalizedPathComponents.last == "openai" {
            return ["models"]
        }

        if normalizedPathComponents.last == "v1" {
            return ["models"]
        }

        return ["v1", "models"]
    }

    private func makeAISDKBridgeHealthRequest(for provider: ProviderConfiguration, endpoint: String) throws -> URLRequest {
        var request = URLRequest(url: try Self.aiSDKBridgeHealthURL(endpoint))
        request.httpMethod = "GET"
        request.timeoutInterval = readinessTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let secretReference = parseSecretReference(provider.secretReference) {
            let apiKey = try secretReader(secretReference).trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }

        return request
    }

    private func normalizedEndpoint(from rawValue: String) -> String? {
        let trimmedValue = trimmed(rawValue)
        guard !trimmedValue.isEmpty,
              let components = URLComponents(string: trimmedValue),
              components.scheme != nil,
              components.host != nil,
              let url = components.url else {
            return nil
        }

        return url.absoluteString
    }

    private static func endpointURL(_ rawValue: String, appending pathComponents: [String]) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil else {
            throw ProviderReadinessError.invalidEndpoint
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
            throw ProviderReadinessError.invalidEndpoint
        }
        return url
    }

    private static func aiSDKBridgeHealthURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil else {
            throw ProviderReadinessError.invalidEndpoint
        }

        let pathComponents = components.path
            .split(separator: "/")
            .map(String.init)
        let normalizedPathComponents = pathComponents.map { $0.lowercased() }
        let healthPathComponents: [String]

        if normalizedPathComponents.last == "health" {
            healthPathComponents = pathComponents
        } else if normalizedPathComponents.last == "chat" {
            healthPathComponents = Array(pathComponents.dropLast()) + ["health"]
        } else if normalizedPathComponents.last == "api" {
            healthPathComponents = pathComponents + ["health"]
        } else {
            healthPathComponents = pathComponents + ["api", "health"]
        }

        components.path = healthPathComponents.isEmpty
            ? "/api/health"
            : "/" + healthPathComponents.joined(separator: "/")
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw ProviderReadinessError.invalidEndpoint
        }
        return url
    }

    private static func endpointPathComponents(_ endpoint: String) -> [String] {
        URLComponents(string: endpoint)?
            .path
            .split(separator: "/")
            .map(String.init) ?? []
    }

    private func canonicalSecretAccount(for provider: ProviderConfiguration) -> String {
        let kindComponent = slug(provider.kind.rawValue)
        let endpointComponent: String

        if let endpoint = normalizedEndpoint(from: provider.endpoint),
           let url = URL(string: endpoint) {
            let host = slug(url.host ?? provider.displayName)
            if let port = url.port {
                endpointComponent = "\(host)-\(port)"
            } else {
                endpointComponent = host
            }
        } else {
            endpointComponent = slug(provider.displayName)
        }

        return "provider/\(kindComponent)/\(endpointComponent)"
    }

    private func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }

        let collapsed = String(scalars)
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return collapsed.isEmpty ? "provider" : collapsed
    }

    private func providerHasSelectedModel(
        _ provider: ProviderConfiguration,
        _ selectedModelIdentifier: String
    ) -> Bool {
        let target = normalizedModelIdentifier(selectedModelIdentifier)
        guard !target.isEmpty else { return false }
        return provider.availableModels.contains {
            normalizedModelIdentifier($0) == target
        }
    }

    private func configuredAvailableModels(
        for provider: ProviderConfiguration,
        selectedModelIdentifier: String
    ) -> [String] {
        let selectedModel = selectedModelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        var models = provider.availableModels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !selectedModel.isEmpty,
           !models.contains(where: { normalizedModelIdentifier($0) == normalizedModelIdentifier(selectedModel) }) {
            models.append(selectedModel)
        }

        return models.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func containsModel(
        _ models: [ProviderAvailableModel],
        matching selectedModelIdentifier: String
    ) -> Bool {
        let target = normalizedModelIdentifier(selectedModelIdentifier)
        guard !target.isEmpty else { return false }

        return models.contains { model in
            normalizedModelIdentifier(model.name) == target
                || normalizedModelIdentifier(model.displayName) == target
        }
    }

    private func normalizedModelIdentifier(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static let urlSessionReadinessTransport: ReadinessTransport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as? HTTPURLResponse)
    }
}

nonisolated private struct ProviderModelAvailability: Sendable {
    var status: IntegrationConnectionStatus
    var models: [ProviderAvailableModel]
    var errorMessage: String?
    var checkedAt: Date
}

nonisolated private struct ProviderAvailableModel: Sendable {
    var name: String
    var displayName: String?
}

nonisolated private struct OpenAICompatibleModelListResponse: Decodable {
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

nonisolated private struct AISDKBridgeHealthResponse: Decodable {
    var status: String?
    var ready: Bool?
    var model: String?
    var defaultModel: String?
    var models: [String]?
    var data: [Model]?
    var message: String?

    var isReady: Bool {
        if let ready {
            return ready
        }

        guard let status = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !status.isEmpty else {
            return true
        }

        return status == "ok"
            || status == "ready"
            || status == "healthy"
            || status == "running"
    }

    var availableModels: [ProviderAvailableModel] {
        let explicitModels = models ?? []
        let dataModels = data?.map(\.id) ?? []
        let preferredModel = [model, defaultModel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Array(Set(explicitModels + dataModels + preferredModel))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { ProviderAvailableModel(name: $0, displayName: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case status
        case ready
        case model
        case defaultModel
        case defaultModelSnake = "default_model"
        case models
        case data
        case message
        case error
    }

    struct Model: Decodable {
        var id: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        ready = try container.decodeIfPresent(Bool.self, forKey: .ready)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel)
            ?? (try container.decodeIfPresent(String.self, forKey: .defaultModelSnake))
        models = try container.decodeIfPresent([String].self, forKey: .models)
        data = try container.decodeIfPresent([Model].self, forKey: .data)
        message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? (try container.decodeIfPresent(String.self, forKey: .error))
    }

    static func decodeIfPresent(from data: Data) throws -> AISDKBridgeHealthResponse? {
        guard data.isEmpty == false,
              data.contains(where: { byte in
                  byte != 9 && byte != 10 && byte != 13 && byte != 32
              }) else {
            return nil
        }
        return try JSONDecoder().decode(AISDKBridgeHealthResponse.self, from: data)
    }
}

private enum ProviderReadinessError: LocalizedError {
    case invalidEndpoint
    case badResponse
    case badStatus(Int)
    case missingKeychainReference(String)
    case emptyKeychainSecret(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The endpoint URL is invalid."
        case .badResponse:
            "The provider did not return an HTTP response."
        case .badStatus(let statusCode):
            "The provider returned HTTP \(statusCode)."
        case .missingKeychainReference(let providerName):
            "Save an API key for \(providerName) in Keychain before running the live readiness check."
        case .emptyKeychainSecret(let providerName):
            "The saved API key for \(providerName) is empty."
        }
    }
}

private enum CLIReadinessSmokeProbeError: LocalizedError {
    case emptyOutput(String)
    case unexpectedOutput(String, String)

    var errorDescription: String? {
        switch self {
        case .emptyOutput(let providerName):
            "\(providerName) ran, but Flannel could not decode any assistant text from the readiness response."
        case .unexpectedOutput(let providerName, let output):
            "\(providerName) ran, but its readiness response did not match the expected flannel-ready token. Response: \(output)"
        }
    }
}
