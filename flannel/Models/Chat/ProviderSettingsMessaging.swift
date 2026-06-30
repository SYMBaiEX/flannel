//
//  ProviderSettingsMessaging.swift
//  flannel
//
//  Created by OpenAI Codex on 6/30/26.
//

import Foundation

enum ProviderSettingsMessaging {
    static func preflightSetupMessage(
        for provider: ProviderConfiguration,
        report: ProviderSetupReport
    ) -> String {
        if report.hasBlockingIssues {
            return report.diagnostics.first(where: \.isBlocking)?.message
                ?? fallbackNeedsAttentionMessage(for: provider)
        }

        if report.routingEligibility != .eligible {
            return report.diagnostics.first?.message
                ?? fallbackNeedsAttentionMessage(for: provider)
        }

        switch provider.accessMode {
        case .localServer:
            return "Setup looks complete. Run discovery or readiness to confirm the selected local model."
        case .subscriptionCLI:
            return "Setup looks complete. Run readiness to confirm the local CLI account can answer a smoke check."
        case .apiKey, .anthropicCompatible:
            return "Setup looks complete. Run readiness to confirm the endpoint, credentials, and selected model."
        case .openAICompatible:
            return provider.runtimeBoundary == .localServer
                ? "Setup looks complete. Run readiness to confirm the compatible local endpoint and selected model."
                : "Setup looks complete. Run readiness to confirm the compatible endpoint and selected model."
        case .aiSDKBridge:
            return "Setup looks complete. Run readiness to confirm bridge health and the selected model."
        }
    }

    static func pendingReadinessMessage(for provider: ProviderConfiguration) -> String {
        switch provider.accessMode {
        case .localServer:
            return "Checking local server and selected model..."
        case .subscriptionCLI:
            return "Running local CLI smoke check..."
        case .apiKey, .anthropicCompatible:
            return "Checking endpoint, credentials, and selected model..."
        case .openAICompatible:
            return provider.runtimeBoundary == .localServer
                ? "Checking compatible local endpoint and selected model..."
                : "Checking compatible endpoint and selected model..."
        case .aiSDKBridge:
            return "Checking bridge health and selected model..."
        }
    }

    static func setupMessage(
        for provider: ProviderConfiguration,
        validation: ProviderReadinessValidation
    ) -> String {
        if validation.isReady {
            switch provider.accessMode {
            case .localServer:
                let modelCount = validation.availableModels.count
                let modelSummary = modelCount == 0
                    ? "provider metadata"
                    : "\(modelCount) local model\(modelCount == 1 ? "" : "s")"
                return "Ready. Confirmed \(provider.kind.title) and checked \(modelSummary)."
            case .subscriptionCLI:
                return "Ready. Local CLI smoke check passed."
            case .apiKey, .anthropicCompatible:
                return "Ready. Endpoint, credentials, and selected model were confirmed."
            case .openAICompatible:
                return provider.runtimeBoundary == .localServer
                    ? "Ready. Compatible local endpoint responded and returned the selected model."
                    : "Ready. Compatible endpoint responded and returned the selected model."
            case .aiSDKBridge:
                return "Ready. Local bridge health and selected model were confirmed."
            }
        }

        return validation.errorMessage ?? fallbackNeedsAttentionMessage(for: provider)
    }

    static func readinessSummary(
        for provider: ProviderConfiguration,
        validation: ProviderReadinessValidation
    ) -> String {
        let checkedText = validation.checkedAt.formatted(date: .abbreviated, time: .shortened)
        if validation.selectedModelIdentifier.isEmpty {
            return "Readiness checked \(checkedText). Enter a model before routing chat."
        }

        if validation.isReady {
            switch provider.accessMode {
            case .localServer:
                return "Local readiness checked \(checkedText). Selected model is installed and reachable."
            case .subscriptionCLI:
                return "CLI readiness checked \(checkedText). The local subscription command answered Flannel's smoke check."
            case .apiKey, .anthropicCompatible:
                return "Endpoint readiness checked \(checkedText). Credentials and selected model were confirmed."
            case .openAICompatible:
                return provider.runtimeBoundary == .localServer
                    ? "Compatible local endpoint checked \(checkedText). Selected model is available."
                    : "Compatible endpoint checked \(checkedText). Selected model is available."
            case .aiSDKBridge:
                return "Bridge readiness checked \(checkedText). Selected model is available through the local bridge."
            }
        }

        if !validation.selectedModelIsAvailable {
            switch provider.accessMode {
            case .localServer:
                return "Local readiness checked \(checkedText). Selected model was not returned by discovery."
            case .subscriptionCLI:
                return "CLI readiness checked \(checkedText). The local subscription command still needs attention before chat can route here."
            case .apiKey, .anthropicCompatible:
                return "Endpoint readiness checked \(checkedText). Selected model was not returned by the configured API route."
            case .openAICompatible:
                return provider.runtimeBoundary == .localServer
                    ? "Compatible local endpoint checked \(checkedText). Selected model was not returned."
                    : "Compatible endpoint checked \(checkedText). Selected model was not returned."
            case .aiSDKBridge:
                return "Bridge readiness checked \(checkedText). Selected model was not returned by the local bridge."
            }
        }

        return "Readiness checked \(checkedText). This route still needs attention before chat can use it."
    }

    static func modelListSummary(for validation: ProviderReadinessValidation) -> String? {
        guard !validation.availableModels.isEmpty else { return nil }
        let models = validation.availableModels.prefix(5).joined(separator: ", ")
        let extraCount = max(0, validation.availableModels.count - 5)
        if extraCount == 0 {
            return "Returned models: \(models)"
        }
        return "Returned models: \(models), and \(extraCount) more"
    }

    static func localDiscoveryMessage(for results: [LocalProviderDiscoveryResult]) -> String {
        guard !results.isEmpty else {
            return "No local provider routes are configured for discovery."
        }

        let readyResults = results.filter { $0.status == .ready }
        let readyCount = readyResults.count
        let modelCount = readyResults.reduce(0) { $0 + $1.models.count }
        let attentionSummary = results
            .filter { $0.status != .ready }
            .compactMap { result in
                let message = result.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let message,
                      !message.isEmpty else { return nil }
                return "\(result.providerKind.title): \(message)"
            }
            .joined(separator: " ")

        if readyCount == 0 {
            if !attentionSummary.isEmpty {
                return "No local providers were ready. \(attentionSummary)"
            }
            return "No local providers were ready. Start Ollama or LM Studio, then run discovery again."
        }

        let base = "Found \(modelCount) model\(modelCount == 1 ? "" : "s") across \(readyCount) local provider route\(readyCount == 1 ? "" : "s")."
        guard !attentionSummary.isEmpty else {
            return base
        }
        return "\(base) Needs attention: \(attentionSummary)"
    }

    static func statusText(for provider: ProviderConfiguration) -> String {
        let checkedSuffix = provider.lastValidatedAt.map {
            " Checked \($0.formatted(date: .abbreviated, time: .shortened))."
        } ?? ""

        switch provider.connectionStatus {
        case .ready:
            switch provider.accessMode {
            case .localServer:
                return "Local route ready.\(checkedSuffix)"
            case .subscriptionCLI:
                return "CLI route ready.\(checkedSuffix)"
            case .apiKey, .anthropicCompatible:
                return "API route ready.\(checkedSuffix)"
            case .openAICompatible:
                return provider.runtimeBoundary == .localServer
                    ? "Compatible local endpoint ready.\(checkedSuffix)"
                    : "Compatible endpoint ready.\(checkedSuffix)"
            case .aiSDKBridge:
                return "Local bridge ready.\(checkedSuffix)"
            }
        case .needsAttention:
            return "Needs attention.\(checkedSuffix)"
        case .rateLimited:
            return "Rate limited.\(checkedSuffix)"
        case .syncing:
            return "Checking readiness now."
        case .disconnected:
            if provider.lastValidatedAt != nil {
                return "Settings changed since the last readiness check."
            }
            switch provider.accessMode {
            case .localServer:
                return "Discovery and readiness have not run yet."
            case .subscriptionCLI:
                return "CLI command has not been smoke-tested yet."
            case .apiKey, .anthropicCompatible:
                return "Endpoint and credentials have not been checked yet."
            case .openAICompatible:
                return provider.runtimeBoundary == .localServer
                    ? "Compatible local endpoint has not been checked yet."
                    : "Compatible endpoint has not been checked yet."
            case .aiSDKBridge:
                return "Local bridge health has not been checked yet."
            }
        }
    }

    static func disconnectedChipTitle(for provider: ProviderConfiguration) -> String {
        switch provider.accessMode {
        case .localServer:
            return "Discovery needed"
        case .subscriptionCLI:
            return "CLI not checked"
        case .apiKey, .anthropicCompatible:
            return "Route not checked"
        case .openAICompatible:
            return provider.runtimeBoundary == .localServer ? "Local endpoint not checked" : "Endpoint not checked"
        case .aiSDKBridge:
            return "Bridge not checked"
        }
    }

    private static func fallbackNeedsAttentionMessage(for provider: ProviderConfiguration) -> String {
        switch provider.accessMode {
        case .localServer:
            return "Local server route needs attention before chat routing."
        case .subscriptionCLI:
            return "Subscription CLI route needs attention before chat routing."
        case .apiKey, .anthropicCompatible:
            return "API route needs attention before chat routing."
        case .openAICompatible:
            return "Compatible endpoint needs attention before chat routing."
        case .aiSDKBridge:
            return "Bridge route needs attention before chat routing."
        }
    }
}
