//
//  ProviderRoutingPicker.swift
//  flannel
//

import SwiftUI

private struct ProviderRouteReadiness {
    var text: String
    var icon: String
    var tint: Color
}

private struct ProviderRouteMenuTemplate: Identifiable, Hashable {
    var kind: LLMProviderKind
    var accessMode: ProviderAccessMode
    var privacyScope: ProviderPrivacyScope?
    var title: String
    var systemImage: String
    var helpText: String

    var id: String {
        "\(kind.rawValue)-\(accessMode.rawValue)-\(privacyScope?.rawValue ?? "default")"
    }

    var menuTitle: String {
        "Add \(title)"
    }

    static func templates(for family: ProviderModeFamily) -> [ProviderRouteMenuTemplate] {
        switch family {
        case .localModels:
            [
                ProviderRouteMenuTemplate(
                    kind: .ollama,
                    accessMode: .localServer,
                    privacyScope: .localOnly,
                    title: "Ollama Local Server",
                    systemImage: "server.rack",
                    helpText: "Create and select an Ollama local server route, then run discovery or pick an installed model."
                ),
                ProviderRouteMenuTemplate(
                    kind: .lmStudio,
                    accessMode: .localServer,
                    privacyScope: .localOnly,
                    title: "LM Studio Local Server",
                    systemImage: "desktopcomputer",
                    helpText: "Create and select an LM Studio local server route using its OpenAI-compatible local endpoint."
                )
            ]
        case .openAIChatGPT:
            [
                ProviderRouteMenuTemplate(
                    kind: .openAI,
                    accessMode: .apiKey,
                    privacyScope: .externalAPI,
                    title: "OpenAI Platform API Key",
                    systemImage: "key",
                    helpText: "Create and select an official OpenAI Platform API route. Usage bills through the API key saved in Keychain, separate from ChatGPT subscription or Codex CLI access."
                ),
                ProviderRouteMenuTemplate(
                    kind: .chatGPTCLI,
                    accessMode: .subscriptionCLI,
                    privacyScope: .localCLI,
                    title: "ChatGPT Subscription via Codex CLI",
                    systemImage: "terminal",
                    helpText: "Create and select a local Codex CLI route. Flannel runs codex exec --json - while ChatGPT subscription or Codex API-key auth stays inside the CLI."
                )
            ]
        case .anthropicClaude:
            [
                ProviderRouteMenuTemplate(
                    kind: .anthropic,
                    accessMode: .apiKey,
                    privacyScope: .externalAPI,
                    title: "Anthropic Console API Key",
                    systemImage: "key",
                    helpText: "Create and select an official Anthropic API route. Usage uses the Anthropic Console key saved in Keychain, separate from Claude Code account access."
                ),
                ProviderRouteMenuTemplate(
                    kind: .claudeCodeCLI,
                    accessMode: .subscriptionCLI,
                    privacyScope: .localCLI,
                    title: "Claude Plan via Claude Code CLI",
                    systemImage: "terminal",
                    helpText: "Create and select a Claude Code account route. Flannel runs claude -p in print mode while Claude Pro, Max, Team, Enterprise, or Console auth stays inside Claude Code."
                )
            ]
        case .hostedAPIs:
            [
                (.gemini, "Google Gemini API Route"),
                (.xAI, "xAI API Route"),
                (.mistral, "Mistral API Route"),
                (.groq, "Groq API Route"),
                (.openRouter, "OpenRouter API Route"),
                (.perplexity, "Perplexity API Route")
            ].map { kind, title in
                ProviderRouteMenuTemplate(
                    kind: kind,
                    accessMode: .apiKey,
                    privacyScope: .externalAPI,
                    title: title,
                    systemImage: "key",
                    helpText: "Create and select a BYOK \(kind.title) route. It will need a Keychain API key before it can become active."
                )
            }
        case .customEndpoints:
            [
                ProviderRouteMenuTemplate(
                    kind: .customOpenAICompatible,
                    accessMode: .openAICompatible,
                    privacyScope: nil,
                    title: "OpenAI-Compatible Endpoint",
                    systemImage: "arrow.left.arrow.right",
                    helpText: "Create and select a custom OpenAI-compatible endpoint route. Configure endpoint, model, and optional key in settings."
                ),
                ProviderRouteMenuTemplate(
                    kind: .vercelAISDKBridge,
                    accessMode: .aiSDKBridge,
                    privacyScope: .bridgeService,
                    title: "Local AI SDK Bridge",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    helpText: "Create and select a local Vercel AI SDK bridge route."
                )
            ]
        }
    }
}

struct ProviderRoutingPicker: View {
    @Bindable var store: WorkspaceStore
    var isDiscoveringModels: Bool
    var discoverModels: () -> Void
    var openProviderSetup: () -> Void
    var persist: () -> Void

    private var preferredProvider: ProviderConfiguration? {
        store.preferredProviderConfiguration
    }

    private var selectedProvider: ProviderConfiguration? {
        if store.preferences.providerRoutingPolicy == .selectedProvider {
            return preferredProvider ?? store.activeProvider
        }
        return store.activeProvider ?? preferredProvider
    }

    private var discoveredLocalModelCount: Int {
        store.localDiscoveryResults.flatMap(\.models).count
    }

    private var discoveredLocalChatResults: [LocalProviderDiscoveryResult] {
        store.localDiscoveryResults.compactMap { result in
            let chatModels = result.models
                .filter { $0.capabilities.contains(.chat) }
                .sorted { lhs, rhs in
                    let lhsLoaded = lhs.loadedInstanceCount ?? 0
                    let rhsLoaded = rhs.loadedInstanceCount ?? 0
                    if lhsLoaded != rhsLoaded {
                        return lhsLoaded > rhsLoaded
                    }
                    let titleComparison = lhs.localModelPickerDisplayName.localizedCaseInsensitiveCompare(rhs.localModelPickerDisplayName)
                    if titleComparison != .orderedSame {
                        return titleComparison == .orderedAscending
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            guard !chatModels.isEmpty else { return nil }

            var result = result
            result.models = chatModels
            return result
        }
    }

    private var selectedReadiness: ProviderRouteReadiness? {
        selectedProvider.map(readiness(for:))
    }

    var body: some View {
        Menu {
            Section("Current Route") {
                Button { } label: {
                    Label(currentRouteMenuTitle, systemImage: selectedProvider?.accessMode.icon ?? "cpu")
                }
                .disabled(true)

                Button(action: openProviderSetup) {
                    Label("Open Models & Providers", systemImage: "slider.horizontal.3")
                }
                .help("Open the in-window Models and Providers settings.")
            }

            Section("Routing Policy") {
                ForEach(ProviderRoutingPolicy.allCases) { policy in
                    Button {
                        select(policy)
                    } label: {
                        Label(
                            policy.title,
                            systemImage: store.preferences.providerRoutingPolicy == policy ? "checkmark" : policy.icon
                        )
                    }
                    .help(policy.detail)
                }
            }

            Section("Local Discovery") {
                Button {
                    discoverModels()
                } label: {
                    Label(
                        isDiscoveringModels ? "Discovering Ollama and LM Studio" : "Discover Ollama and LM Studio",
                        systemImage: isDiscoveringModels ? "arrow.triangle.2.circlepath" : "dot.radiowaves.left.and.right"
                    )
                }
                .disabled(isDiscoveringModels)

                Button(action: openProviderSetup) {
                    Label(
                        discoveredLocalModelCount == 1
                            ? "1 Local Model in Settings"
                            : "\(discoveredLocalModelCount) Local Models in Settings",
                        systemImage: "desktopcomputer"
                    )
                }
                .help("Open model settings to inspect discovered local models.")
            }

            ForEach(discoveredLocalChatResults) { result in
                Section("\(result.providerKind.title) Models") {
                    ForEach(result.models) { model in
                        Button {
                            select(model)
                        } label: {
                            Label(
                                model.localModelPickerMenuTitle,
                                systemImage: isSelected(model) ? "checkmark" : localModelMenuIcon(model)
                            )
                        }
                        .help(model.localModelPickerHelpText)
                    }
                }
            }

            ForEach(ProviderModeFamily.allCases) { family in
                let familyProviders = providers(in: family)
                let missingRoutes = missingRouteTemplates(in: family)
                if !familyProviders.isEmpty || !missingRoutes.isEmpty {
                    Section(family.title) {
                        if let prompt = family.modeChoicePrompt {
                            Button { } label: {
                                Label(prompt, systemImage: family.icon)
                            }
                            .disabled(true)
                        }

                        if !missingRoutes.isEmpty {
                            ForEach(missingRoutes) { template in
                                Button {
                                    select(template)
                                } label: {
                                    Label(template.menuTitle, systemImage: template.systemImage)
                                }
                                .help(template.helpText)
                            }
                        }

                        ForEach(familyProviders) { provider in
                            let modelNames = selectableModelNames(for: provider)
                            Button {
                                select(provider)
                            } label: {
                                Label(
                                    providerMenuTitle(for: provider),
                                    systemImage: providerMenuIcon(for: provider)
                                )
                            }

                            ForEach(modelNames, id: \.self) { modelName in
                                Button {
                                    select(provider, modelIdentifier: modelName)
                                } label: {
                                    Label(
                                        providerModelMenuTitle(provider: provider, modelName: modelName),
                                        systemImage: providerModelMenuIcon(provider: provider, modelName: modelName)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            ProviderRoutingPickerLabel(
                selectedProvider: selectedProvider,
                activeProvider: store.activeProvider,
                preferredProvider: preferredProvider,
                routingPolicy: store.preferences.providerRoutingPolicy,
                readiness: selectedReadiness,
                isDiscoveringModels: isDiscoveringModels
            )
        }
        .menuStyle(.borderlessButton)
        .help("Choose provider mode for this chat")
        .accessibilityLabel("Provider routing")
        .accessibilityValue(providerRoutingAccessibilityValue)
    }

    private var currentRouteMenuTitle: String {
        guard let selectedProvider else {
            return "Current: choose a provider route"
        }

        let readinessText = selectedReadiness?.text ?? "Check setup"
        if isDiscoveringModels {
            return "Current: discovering local models - \(selectedProvider.providerPickerRouteSummary)"
        }

        return "Current: \(selectedProvider.modeBoundaryTitle) - \(selectedProvider.providerPickerStatusLine(readinessText: readinessText, routingPolicy: store.preferences.providerRoutingPolicy))"
    }

    private func providers(in family: ProviderModeFamily) -> [ProviderConfiguration] {
        store.providerConfigurations
            .filter { family.contains($0) }
            .sorted { lhs, rhs in
                let lhsRank = providerSortRank(lhs)
                let rhsRank = providerSortRank(rhs)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.providerModeChoiceTitle.localizedCaseInsensitiveCompare(rhs.providerModeChoiceTitle) == .orderedAscending
        }
    }

    private func missingRouteTemplates(in family: ProviderModeFamily) -> [ProviderRouteMenuTemplate] {
        ProviderRouteMenuTemplate.templates(for: family).filter { template in
            !store.providerConfigurations.contains {
                $0.kind == template.kind && $0.accessMode == template.accessMode
            }
        }
    }

    private func providerSortRank(_ provider: ProviderConfiguration) -> Int {
        switch provider.accessMode {
        case .localServer:
            return 0
        case .apiKey, .openAICompatible, .anthropicCompatible:
            return 1
        case .subscriptionCLI:
            return 2
        case .aiSDKBridge:
            return 3
        }
    }

    private func select(_ template: ProviderRouteMenuTemplate) {
        _ = store.ensureProviderRouteForChat(
            kind: template.kind,
            accessMode: template.accessMode,
            privacyScope: template.privacyScope
        )
        persist()
    }

    private func select(_ provider: ProviderConfiguration) {
        _ = store.selectPreferredProviderForChat(provider.id)
        persist()
    }

    private func select(_ provider: ProviderConfiguration, modelIdentifier: String) {
        _ = store.selectPreferredProviderModelForChat(
            providerID: provider.id,
            modelIdentifier: modelIdentifier
        )
        persist()
    }

    private func select(_ model: LocalModelDescriptor) {
        guard store.selectDiscoveredLocalModelForChat(model) != nil else {
            return
        }
        persist()
    }

    private func select(_ policy: ProviderRoutingPolicy) {
        store.preferences.providerRoutingPolicy = policy
        persist()
    }

    private func isSelected(_ model: LocalModelDescriptor) -> Bool {
        selectedProvider?.kind == model.providerKind
            && selectedProvider?.endpoint == model.endpoint
            && selectedProvider?.modelIdentifier == model.name
    }

    private func selectableModelNames(for provider: ProviderConfiguration) -> [String] {
        let candidates = provider.availableModels
            + provider.discoveredModelNames
            + [provider.modelIdentifier]
        return Array(Set(candidates.compactMap { candidate in
            let modelName = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return modelName.isEmpty ? nil : modelName
        }))
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func currentModelMenuTitle(for provider: ProviderConfiguration) -> String {
        let modelName = provider.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return modelName.isEmpty ? "Use current route" : "Use current model: \(modelName)"
    }

    private func providerMenuTitle(for provider: ProviderConfiguration) -> String {
        let readiness = readiness(for: provider)
        var parts: [String] = []
        if store.activeProvider?.id == provider.id {
            parts.append("Active")
        } else if preferredProvider?.id == provider.id {
            parts.append("Selected")
        }
        parts.append(provider.providerModePickerSummary)
        parts.append(readiness.text)
        return "\(provider.providerModePickerTitle) - \(parts.joined(separator: " - "))"
    }

    private func providerMenuIcon(for provider: ProviderConfiguration) -> String {
        if store.activeProvider?.id == provider.id || preferredProvider?.id == provider.id {
            return "checkmark"
        }

        return provider.accessMode.icon
    }

    private func providerModelMenuTitle(provider: ProviderConfiguration, modelName: String) -> String {
        let isActive = store.activeProvider?.id == provider.id
            && store.activeProvider?.modelIdentifier == modelName
        let isSelected = provider.modelIdentifier == modelName
        var status: [String] = []
        if isActive {
            status.append("Active")
        } else if isSelected {
            status.append("Selected")
        }
        status.append(provider.accessMode.title)
        return "\(provider.providerModePickerTitle): \(modelName) - \(status.joined(separator: " - "))"
    }

    private func providerModelMenuIcon(provider: ProviderConfiguration, modelName: String) -> String {
        if store.activeProvider?.id == provider.id
            && store.activeProvider?.modelIdentifier == modelName {
            return "checkmark"
        }
        if provider.modelIdentifier == modelName {
            return "circle.inset.filled"
        }
        return "memorychip"
    }

    private func localModelMenuIcon(_ model: LocalModelDescriptor) -> String {
        if model.capabilities.contains(.vision) {
            return "eye"
        }
        if model.capabilities.contains(.reasoning) {
            return "brain.head.profile"
        }
        return "cpu"
    }

    private var providerRoutingAccessibilityValue: String {
        guard let selectedProvider else {
            return "Choose provider"
        }
        return "\(selectedProvider.providerPickerAccessibilityLabel), \(readiness(for: selectedProvider).text)"
    }

    private func readiness(for provider: ProviderConfiguration) -> ProviderRouteReadiness {
        if store.activeProvider?.id == provider.id {
            return ProviderRouteReadiness(text: "Active", icon: "checkmark.circle", tint: .green)
        }

        if !provider.isEnabled {
            return ProviderRouteReadiness(text: "Disabled", icon: "power", tint: .secondary)
        }

        let report = ProviderSetupService.shared.report(for: provider, preferences: store.preferences)
        if let blockingIssue = report.diagnostics.first(where: \.isBlocking) {
            return ProviderRouteReadiness(text: blockingIssue.message, icon: "exclamationmark.triangle", tint: .orange)
        }

        if !store.isProviderAllowedByPreferences(provider) {
            switch report.routingEligibility {
            case .blockedByLocalOnlyMode:
                return ProviderRouteReadiness(text: "Blocked by Local Only", icon: "lock", tint: .orange)
            case .blockedByCloudPreference:
                return ProviderRouteReadiness(text: "Cloud providers disabled", icon: "network.slash", tint: .orange)
            case .eligible:
                break
            }
        }

        if store.isProviderRunnableForChat(provider) {
            return ProviderRouteReadiness(text: "Ready", icon: "checkmark.circle", tint: .green)
        }

        return ProviderRouteReadiness(text: "Check setup", icon: "wrench.adjustable", tint: .secondary)
    }
}

private struct ProviderModeFamilyPromptMenuRow: View {
    var prompt: String
    var icon: String

    var body: some View {
        Label {
            Text(prompt)
                .font(.caption)
        } icon: {
            Image(systemName: icon)
        }
    }
}

private struct ProviderRoutingCurrentMenuRow: View {
    var selectedProvider: ProviderConfiguration?
    var routingPolicy: ProviderRoutingPolicy
    var readiness: ProviderRouteReadiness?
    var isDiscoveringModels: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isDiscoveringModels ? "arrow.triangle.2.circlepath" : selectedProvider?.accessMode.icon ?? "cpu")
                .frame(width: 16)
                .foregroundStyle(isDiscoveringModels ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedProvider?.modeBoundaryTitle ?? "Choose provider")
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var detailText: String {
        guard let selectedProvider else {
            return "Open Models & Providers to configure a chat route."
        }

        if isDiscoveringModels {
            return "Discovering local models • \(selectedProvider.providerPickerRouteSummary)"
        }

        return selectedProvider.providerPickerStatusLine(
            readinessText: readiness?.text ?? "Check setup",
            routingPolicy: routingPolicy
        )
    }
}

private struct ProviderRoutingPickerLabel: View {
    var selectedProvider: ProviderConfiguration?
    var activeProvider: ProviderConfiguration?
    var preferredProvider: ProviderConfiguration?
    var routingPolicy: ProviderRoutingPolicy
    var readiness: ProviderRouteReadiness?
    var isDiscoveringModels: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isDiscoveringModels ? "arrow.triangle.2.circlepath" : selectedProvider?.accessMode.icon ?? "cpu")
                .frame(width: 16)
                .foregroundStyle(isDiscoveringModels ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedProvider?.modeBoundaryTitle ?? "Choose provider")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(labelDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 200, alignment: .leading)

            Image(systemName: statusIcon)
                .font(.caption)
                .foregroundStyle(statusTint)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .flannelChromePanel(cornerRadius: 16, interactive: true)
        .help(selectedProvider?.modeBoundaryDetail ?? "Choose a provider route for chat.")
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusText: String {
        guard let selectedProvider else { return "No runnable provider" }
        if activeProvider?.id == selectedProvider.id {
            return "\(selectedProvider.providerModeBoundaryBadge) active"
        }
        if preferredProvider?.id == selectedProvider.id {
            return "\(selectedProvider.providerModeBoundaryBadge) selected, not active"
        }
        return selectedProvider.providerModeBoundaryBadge
    }

    private var labelDetail: String {
        let readinessText = readiness?.text ?? statusText
        guard let selectedProvider else { return readinessText }

        if isDiscoveringModels {
            return "Discovering local models"
        }

        return selectedProvider.providerPickerStatusLine(
            readinessText: readinessText,
            routingPolicy: routingPolicy
        )
    }

    private var accessibilityLabel: String {
        guard let selectedProvider else {
            return "Choose provider"
        }
        return "\(selectedProvider.providerPickerAccessibilityLabel), \(readiness?.text ?? statusText)"
    }

    private var statusTint: Color {
        if isDiscoveringModels {
            return Color.accentColor
        }
        guard let selectedProvider else { return .secondary }
        if activeProvider?.id == selectedProvider.id {
            return .green
        }
        if preferredProvider?.id == selectedProvider.id {
            return Color.accentColor
        }
        return readiness?.tint ?? .secondary
    }

    private var statusIcon: String {
        if isDiscoveringModels {
            return "arrow.triangle.2.circlepath"
        }
        guard let selectedProvider else { return "circle" }
        if activeProvider?.id == selectedProvider.id {
            return "checkmark.circle.fill"
        }
        if preferredProvider?.id == selectedProvider.id {
            return "circle.inset.filled"
        }
        return readiness?.icon ?? "circle"
    }
}

private struct ProviderRoutingMenuRow: View {
    var provider: ProviderConfiguration
    var readiness: ProviderRouteReadiness
    var isPreferred: Bool
    var isActive: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: provider.accessMode.icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.providerModeSelectionTitle)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: statusIcon)
                .font(.caption)
                .foregroundStyle(statusTint)
        }
    }

    private var detailText: String {
        var parts: [String] = []
        if isActive {
            parts.append("Active")
        } else if isPreferred {
            parts.append("Selected")
        }
        parts.append(provider.providerPickerRouteSummary)
        parts.append(readiness.text)
        return parts.joined(separator: " • ")
    }

    private var statusIcon: String {
        if isActive {
            return "checkmark.circle.fill"
        }
        if isPreferred {
            return "checkmark.circle"
        }
        return readiness.icon
    }

    private var statusTint: Color {
        if isActive {
            return .green
        }
        if isPreferred {
            return Color.accentColor
        }
        return readiness.tint
    }
}

private struct ProviderModelRoutingMenuRow: View {
    var modelName: String
    var provider: ProviderConfiguration
    var isSelected: Bool
    var isActive: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: statusIcon)
                .frame(width: 16)
                .foregroundStyle(statusTint)

            VStack(alignment: .leading, spacing: 1) {
                Text(modelName)
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var detailText: String {
        var parts: [String] = []
        if isActive {
            parts.append("Active")
        } else if isSelected {
            parts.append("Selected")
        }
        parts.append(provider.accessMode.title)
        parts.append(provider.runtimeBoundary.title)
        return parts.joined(separator: " • ")
    }

    private var statusIcon: String {
        if isActive {
            return "checkmark.circle.fill"
        }
        if isSelected {
            return "checkmark.circle"
        }
        return "memorychip"
    }

    private var statusTint: Color {
        if isActive {
            return .green
        }
        if isSelected {
            return Color.accentColor
        }
        return .secondary
    }
}

private struct LocalModelRoutingMenuRow: View {
    var model: LocalModelDescriptor
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle" : icon)
                .frame(width: 16)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.localModelPickerDisplayName)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var icon: String {
        if model.capabilities.contains(.vision) {
            return "eye"
        }
        if model.capabilities.contains(.reasoning) {
            return "brain.head.profile"
        }
        return "cpu"
    }

    private var detail: String {
        model.localModelPickerDetail
    }

    private var subtitle: String {
        [
            model.providerKind.title,
            detail.replacingOccurrences(of: " - ", with: " • ")
        ].joined(separator: " • ")
    }
}
