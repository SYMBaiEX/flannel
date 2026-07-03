//
//  SettingsSurface.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import AppKit
import SwiftUI

struct SettingsSurface: View {
    @Bindable var store: WorkspaceStore
    var persist: () -> Void
    var exitSettings: (() -> Void)?
    var importChat: (() -> Void)?
    var exportWorkspaceSnapshot: (() -> Void)?
    var importWorkspaceSnapshot: (() -> Void)?
    @AppStorage("flannel.settings.selectedTab") private var selectedTab: SettingsTab = .general
    @State private var localSearchText = ""
    private var externalSelectedTab: Binding<SettingsTab>?
    private var externalSearchText: Binding<String>?
    private let usesSidebarNavigation: Bool
    @State private var providerSetupReports: [UUID: ProviderSetupReport] = [:]
    @State private var providerReadinessValidations: [UUID: ProviderReadinessValidation] = [:]
    @State private var validatingProviderIDs: Set<UUID> = []
    @State private var isCheckingAllProviderReadiness = false
    @State private var providerReadinessBatchMessage: String?
    @State private var providerSecretDrafts: [UUID: String] = [:]
    @State private var providerSetupMessages: [UUID: String] = [:]
    @State private var toolSecretDrafts: [UUID: String] = [:]
    @State private var toolSetupMessages: [UUID: String] = [:]
    @State private var isDiscoveringLocalModels = false
    @State private var localDiscoveryMessage: String?
    @State private var isPullingOllamaModel = false
    @State private var ollamaPullModelName = "llama3.1"
    @State private var ollamaPullEndpoint = "http://localhost:11434"
    @State private var ollamaPullMessage: String?
    @State private var deletingOllamaModelID: String?
    @State private var inspectingOllamaModelID: String?
    @State private var loadingLMStudioModelID: String?
    @State private var unloadingLMStudioModelID: String?
    @State private var inspectedOllamaModelInfo: OllamaModelInfo?
    @State private var modelInspectionMessage: String?
    @State private var newChatFolderTitle = ""
    @State private var newMemoryTitle = ""
    @State private var newMemoryDetail = ""
    @State private var newMemoryCategory: LocalMemoryCategory = .fact
    @State private var newMemoryTags = ""
    @State private var newPromptProfileTitle = ""
    @State private var newPromptProfileDetail = ""
    @State private var newPromptProfilePrompt = ""
    @State private var newPromptProfileTags = ""
    @State private var newPromptProfileIsDefault = false
    @State private var newTemplateTitle = ""
    @State private var newTemplateDetail = ""
    @State private var newTemplateSystemPrompt = ""
    @State private var newTemplateStarterPrompt = ""
    @State private var newTemplateMode: AssistantMode = .workspaceCopilot
    @State private var newTemplateTags = ""
    @State private var newTemplateIsPinned = false
    @State private var newKnowledgeSourceKind: KnowledgeSourceKind = .folder
    @State private var newKnowledgeSourceTitle = ""
    @State private var newKnowledgeSourceLocation = ""
    @State private var newKnowledgeSourceWatched = true
    @State private var newKnowledgeSourceMessage: String?
    @State private var refreshingKnowledgeSourceIDs: Set<UUID> = []
    @State private var knowledgeRefreshMessage: String?
    @State private var resetWorkspaceConfirmation = ""
    @State private var resetWorkspaceMessage: String?

    init(
        store: WorkspaceStore,
        persist: @escaping () -> Void,
        exitSettings: (() -> Void)? = nil,
        importChat: (() -> Void)? = nil,
        exportWorkspaceSnapshot: (() -> Void)? = nil,
        importWorkspaceSnapshot: (() -> Void)? = nil,
        selectedTab: Binding<SettingsTab>? = nil,
        searchText: Binding<String>? = nil,
        usesSidebarNavigation: Bool = true
    ) {
        self.store = store
        self.persist = persist
        self.exitSettings = exitSettings
        self.importChat = importChat
        self.exportWorkspaceSnapshot = exportWorkspaceSnapshot
        self.importWorkspaceSnapshot = importWorkspaceSnapshot
        self.externalSelectedTab = selectedTab
        self.externalSearchText = searchText
        self.usesSidebarNavigation = usesSidebarNavigation
    }

    var body: some View {
        Group {
            if usesSidebarNavigation {
                sidebarSettings
                    .frame(minWidth: 760, idealWidth: 860, minHeight: 540, idealHeight: 650)
            } else {
                routedSettings
                    .searchable(text: searchTextBinding, placement: .toolbar, prompt: "Search settings")
            }
        }
        .sheet(item: $inspectedOllamaModelInfo) { info in
            OllamaModelInfoSheet(info: info)
        }
    }

    private var selectedTabBinding: Binding<SettingsTab> {
        externalSelectedTab ?? $selectedTab
    }

    private var optionalSelectedTabBinding: Binding<SettingsTab?> {
        Binding(
            get: { Optional(selectedTabBinding.wrappedValue) },
            set: { newValue in
                if let newValue {
                    selectedTabBinding.wrappedValue = newValue
                }
            }
        )
    }

    private var searchTextBinding: Binding<String> {
        externalSearchText ?? $localSearchText
    }

    private var settingsSearchQuery: String {
        searchTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var providerIndicesForModelsPane: [Int] {
        store.providerConfigurations.indices.filter { index in
            providerMatchesSearch(store.providerConfigurations[index])
        }
    }

    private var providerGroupsForModelsPane: [ProviderSettingsGroup] {
        ProviderSettingsGroupKind.allCases.compactMap { kind in
            let providerIndices = providerIndicesForModelsPane.filter { index in
                kind.contains(store.providerConfigurations[index])
            }
            guard !providerIndices.isEmpty else { return nil }
            return ProviderSettingsGroup(kind: kind, providerIndices: providerIndices)
        }
    }

    private var localDiscoveryResultsForModelsPane: [LocalProviderDiscoveryResult] {
        store.localDiscoveryResults.filter(localDiscoveryResultMatchesSearch)
    }

    private var settingsAddableKnowledgeSourceKinds: [KnowledgeSourceKind] {
        [.folder, .file, .codeRepository, .webPage, .chatHistory, .workspaceNotes]
    }

    private var canAddKnowledgeSourceFromSettings: Bool {
        !newKnowledgeSourceLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sidebarSettings: some View {
        let sidebarWidth = FlannelSidebarSurface.settings.columnWidth

        return NavigationSplitView {
            List(selection: optionalSelectedTabBinding) {
                ForEach(SettingsNavigationSection.allCases) { section in
                    Section(section.title) {
                        ForEach(section.tabs) { tab in
                            SettingsSidebarRow(tab: tab)
                                .tag(Optional(tab))
                                .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 10))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .frame(
                minWidth: sidebarWidth.min,
                idealWidth: sidebarWidth.ideal,
                maxWidth: sidebarWidth.max,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .navigationSplitViewColumnWidth(
                min: sidebarWidth.min,
                ideal: sidebarWidth.ideal,
                max: sidebarWidth.max
            )
        } detail: {
            routedSettings
        }
        .searchable(text: searchTextBinding, placement: .toolbar, prompt: "Search settings")
    }

    private var routedSettings: some View {
        VStack(spacing: 0) {
            SettingsRouteHeader(
                tab: selectedTabBinding.wrappedValue,
                isSearchActive: !settingsSearchQuery.isEmpty,
                exitSettings: exitSettings
            )
                .padding(.horizontal, 28)
                .padding(.vertical, 18)

            FlannelSeparator(opacity: 0.55)

            settingsPane(for: selectedTabBinding.wrappedValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private func settingsPane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            generalPane
        case .models:
            modelsPane
        case .knowledge:
            knowledgePane
        case .memory:
            memoryPane
        case .tools:
            toolsPane
        case .agents:
            agentsPane
        case .prompts:
            promptsPane
        case .privacy:
            privacyPane
        case .storage:
            storagePane
        case .advanced:
            advancedPane
        }
    }

    private var generalPane: some View {
        settingsForm {
            Section("Startup") {
                Picker("Transcript language", selection: Binding(
                    get: { store.preferences.defaultTranscriptLanguageCode ?? "en" },
                    set: {
                        store.preferences.defaultTranscriptLanguageCode = $0
                        persist()
                    }
                )) {
                    ForEach(transcriptLanguages) { language in
                        Text(language.label).tag(language.code)
                    }
                }

                Toggle("Show artifact rail by default", isOn: Binding(
                    get: { store.preferences.showsRightSidebar },
                    set: {
                        store.preferences.showsRightSidebar = $0
                        persist()
                    }
                ))
            }

            Section("Chat History") {
                LabeledContent("Active chats", value: "\(store.activeAssistantThreads.count)")
                LabeledContent("Archived chats", value: "\(store.archivedAssistantThreads.count)")
                LabeledContent("Pinned messages", value: "\(store.pinnedMessages.count)")
            }

            Section("Chat Folders") {
                if store.chatFolders.isEmpty {
                    EmptySettingsRow(
                        title: "No folders",
                        detail: "Create folders for research, writing, coding, projects, or any recurring AI workflow."
                    )
                } else {
                    ForEach(store.chatFolders.indices, id: \.self) { index in
                        ChatFolderSettingsRow(
                            folder: $store.chatFolders[index],
                            parentOptions: parentOptions(for: store.chatFolders[index]),
                            threadCount: store.threadCount(inFolder: store.chatFolders[index].id),
                            delete: {
                                _ = store.deleteChatFolder(store.chatFolders[index].id)
                                persist()
                            },
                            persist: persist
                        )
                    }
                }

                HStack {
                    TextField("New folder", text: $newChatFolderTitle)
                    Button("Add") {
                        if store.addChatFolder(title: newChatFolderTitle) != nil {
                            newChatFolderTitle = ""
                            persist()
                        }
                    }
                    .disabled(newChatFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var modelsPane: some View {
        settingsForm {
            Section("Provider Modes") {
                ProviderModeGuide(
                    networkMode: networkAccessBinding.wrappedValue,
                    providers: store.providerConfigurations
                )
            }

            Section("Routing") {
                ProviderRoutingOverview(
                    activeProvider: store.activeProvider,
                    selectedProvider: store.preferredProviderConfiguration,
                    routingPolicy: store.preferences.providerRoutingPolicy,
                    networkMode: networkAccessBinding.wrappedValue,
                    lastDiscoveryResult: store.localDiscoveryResults
                        .sorted { $0.discoveredAt > $1.discoveredAt }
                        .first,
                    runnableProviderCount: store.providerConfigurations.filter { store.isProviderRunnableForChat($0) }.count
                )

                Picker("Routing policy", selection: Binding(
                    get: { store.preferences.providerRoutingPolicy },
                    set: {
                        store.preferences.providerRoutingPolicy = $0
                        persist()
                    }
                )) {
                    ForEach(ProviderRoutingPolicy.allCases) { policy in
                        Label(policy.title, systemImage: policy.icon).tag(policy)
                    }
                }
                Text(store.preferences.providerRoutingPolicy.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Default model preset", selection: Binding(
                    get: { store.preferences.defaultModelPresetID },
                    set: { presetID in
                        _ = store.setDefaultModelPreset(presetID)
                        persist()
                    }
                )) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(store.modelPresets) { preset in
                        Text(preset.title).tag(Optional(preset.id))
                    }
                }
                .disabled(store.modelPresets.isEmpty)

                LabeledContent("Active provider", value: store.activeProvider?.displayName ?? "None")
            }

            Section("Providers") {
                providerRouteCreationRow
                providerReadinessBulkCheckRow

                if store.providerConfigurations.isEmpty {
                    EmptySettingsRow(
                        title: "No providers",
                        detail: "Add Ollama, LM Studio, CLI, or BYOK providers before routing chat."
                    )
                } else if providerIndicesForModelsPane.isEmpty {
                    EmptySettingsRow(
                        title: "No matching providers",
                        detail: "No provider name, model, mode, endpoint, or capability matches the current settings search."
                    )
                } else {
                    ForEach(providerGroupsForModelsPane) { group in
                        ProviderSettingsGroupHeader(kind: group.kind, count: group.providerIndices.count)

                        ForEach(group.providerIndices, id: \.self) { index in
                            let providerID = store.providerConfigurations[index].id
                            ProviderSettingsRow(
                                provider: $store.providerConfigurations[index],
                                isPreferred: store.preferences.preferredProviderID == providerID,
                                report: report(for: store.providerConfigurations[index]),
                                secretDraft: Binding(
                                    get: { providerSecretDrafts[providerID] ?? "" },
                                    set: { providerSecretDrafts[providerID] = $0 }
                                ),
                                setupMessage: providerSetupMessages[providerID],
                                readinessValidation: providerReadinessValidations[providerID],
                                isValidating: validatingProviderIDs.contains(providerID),
                                setPreferred: {
                                    _ = store.selectPreferredProviderForChat(providerID)
                                    checkProviderReadiness(providerID)
                                    persist()
                                },
                                validate: {
                                    checkProviderReadiness(providerID)
                                },
                                duplicate: {
                                    duplicateProviderRoute(providerID)
                                },
                                delete: {
                                    deleteProviderRoute(providerID)
                                },
                                canDelete: store.providerConfigurations.count > 1,
                                saveSecret: {
                                    saveAPIKey(for: providerID)
                                },
                                deleteSecret: {
                                    deleteAPIKey(for: providerID)
                                },
                                invalidateReadiness: {
                                    invalidateProviderReadiness(providerID)
                                },
                                persist: persist
                            )
                        }
                    }
                }
            }

            Section("Local Discovery") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ollama and LM Studio")
                            .font(.headline)
                        Text("Checks loopback servers and updates installed model lists in provider settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task {
                            await discoverLocalModels()
                        }
                    } label: {
                        if isDiscoveringLocalModels {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Discover Models", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isDiscoveringLocalModels)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pull Ollama model")
                        .font(.headline)
                    Text("Downloads a model through the configured local Ollama server, then refreshes discovery.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Model")
                                .foregroundStyle(.secondary)
                            TextField("llama3.1, qwen3:14b, nomic-embed-text", text: $ollamaPullModelName)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Endpoint")
                                .foregroundStyle(.secondary)
                            TextField("http://localhost:11434", text: $ollamaPullEndpoint)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await pullOllamaModel()
                            }
                        } label: {
                            if isPullingOllamaModel {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Pull Model", systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(isPullingOllamaModel || ollamaPullModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let ollamaPullMessage {
                        SettingsInlineNotice(
                            message: ollamaPullMessage,
                            tone: settingsNoticeTone(for: ollamaPullMessage, isLoading: isPullingOllamaModel)
                        )
                    }
                }
                .padding(.vertical, 4)

                if let localDiscoveryMessage {
                    SettingsInlineNotice(
                        message: localDiscoveryMessage,
                        tone: settingsNoticeTone(for: localDiscoveryMessage, isLoading: isDiscoveringLocalModels)
                    )
                }

                if let modelInspectionMessage {
                    SettingsInlineNotice(
                        message: modelInspectionMessage,
                        tone: settingsNoticeTone(for: modelInspectionMessage, isLoading: modelInspectionMessage.hasPrefix("Inspecting "))
                    )
                }

                if !store.localProviderHealthSnapshots.isEmpty {
                    LocalDiscoveryHealthSummary(
                        healthSnapshots: store.localProviderHealthSnapshots,
                        localModelCatalog: store.localModelCatalog
                    )
                }

                if store.localDiscoveryResults.isEmpty {
                    EmptySettingsRow(
                        title: "No local discovery results",
                        detail: "Start Ollama or LM Studio, then run discovery from this Settings pane."
                    )
                } else if localDiscoveryResultsForModelsPane.isEmpty {
                    EmptySettingsRow(
                        title: "No matching discovery results",
                        detail: "Discovery has results, but none match the current settings search."
                    )
                } else {
                    ForEach(localDiscoveryResultsForModelsPane) { result in
                        LocalDiscoverySettingsRow(
                            result: result,
                            deletingModelID: deletingOllamaModelID,
                            inspectingModelID: inspectingOllamaModelID,
                            loadingModelID: loadingLMStudioModelID,
                            unloadingModelID: unloadingLMStudioModelID,
                            useModel: selectLocalModel,
                            loadModel: { model in
                                Task {
                                    await loadLMStudioModel(model)
                                }
                            },
                            unloadModel: { model in
                                Task {
                                    await unloadLMStudioModel(model)
                                }
                            },
                            inspectModel: { model in
                                Task {
                                    await inspectOllamaModel(model)
                                }
                            },
                            deleteModel: { model in
                                Task {
                                    await deleteOllamaModel(model)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var providerRouteCreationRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Provider routes")
                    .font(.headline)
                Text("Add separate API-key, account CLI, local server, bridge, or OpenAI-compatible routes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Section("OpenAI / ChatGPT") {
                    Button {
                        addProviderRoute(kind: .openAI, accessMode: .apiKey)
                    } label: {
                        Label("OpenAI API key", systemImage: "key")
                    }

                    Button {
                        addProviderRoute(kind: .chatGPTCLI, accessMode: .subscriptionCLI)
                    } label: {
                        Label("ChatGPT/Codex CLI", systemImage: "terminal")
                    }
                }

                Section("Anthropic / Claude") {
                    Button {
                        addProviderRoute(kind: .anthropic, accessMode: .apiKey)
                    } label: {
                        Label("Anthropic API key", systemImage: "key")
                    }

                    Button {
                        addProviderRoute(kind: .claudeCodeCLI, accessMode: .subscriptionCLI)
                    } label: {
                        Label("Claude Code CLI", systemImage: "terminal")
                    }
                }

                Section("Local") {
                    Button {
                        addProviderRoute(kind: .ollama, accessMode: .localServer, privacyScope: .localOnly)
                    } label: {
                        Label("Ollama server", systemImage: "desktopcomputer")
                    }

                    Button {
                        addProviderRoute(kind: .lmStudio, accessMode: .localServer, privacyScope: .localOnly)
                    } label: {
                        Label("LM Studio server", systemImage: "server.rack")
                    }

                    Button {
                        addProviderRoute(kind: .customOpenAICompatible, accessMode: .openAICompatible, privacyScope: .localOnly)
                    } label: {
                        Label("Custom local OpenAI-compatible", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                }

                Section("Hosted BYOK APIs") {
                    ForEach([LLMProviderKind.gemini, .xAI, .mistral, .groq, .openRouter, .perplexity], id: \.self) { kind in
                        Button {
                            addProviderRoute(kind: kind, accessMode: .apiKey)
                        } label: {
                            Label("\(kind.title) API key", systemImage: "network")
                        }
                    }
                }

                Section("Advanced") {
                    Button {
                        addProviderRoute(kind: .customOpenAICompatible, accessMode: .openAICompatible, privacyScope: .externalAPI)
                    } label: {
                        Label("Custom remote OpenAI-compatible", systemImage: "globe")
                    }

                    Button {
                        addProviderRoute(kind: .vercelAISDKBridge, accessMode: .aiSDKBridge, privacyScope: .bridgeService)
                    } label: {
                        Label("Local AI SDK bridge", systemImage: "shippingbox")
                    }
                }
            } label: {
                Label("Add Route", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .controlSize(.regular)
            .help("Add a provider route")
        }
    }

    private var providerReadinessBulkCheckRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Readiness audit")
                        .font(.headline)
                    Text(providerReadinessBulkDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    checkAllProviderReadiness()
                } label: {
                    if isCheckingAllProviderReadiness {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Check All Routes", systemImage: "checkmark.seal")
                    }
                }
                .disabled(store.providerConfigurations.isEmpty || isCheckingAllProviderReadiness || !validatingProviderIDs.isEmpty)
            }

            if let providerReadinessBatchMessage {
                SettingsInlineNotice(
                    message: providerReadinessBatchMessage,
                    tone: settingsProviderReadinessNoticeTone(
                        for: providerReadinessBatchMessage,
                        isLoading: isCheckingAllProviderReadiness
                    )
                )
            }
        }
    }

    private var providerReadinessBulkDetail: String {

        let routeCount = store.providerConfigurations.count
        guard routeCount > 0 else {
            return "Add a provider route before running endpoint, CLI, model, and privacy readiness checks."
        }

        return "Check every configured route against endpoint, selected model, Keychain, CLI, and privacy gates."
    }

    private var knowledgePane: some View {
        settingsForm {
            Section("Add Retrieval Source") {
                Picker("Source type", selection: $newKnowledgeSourceKind) {
                    ForEach(settingsAddableKnowledgeSourceKinds) { kind in
                        Label(kind.settingsTitle, systemImage: kind.settingsSystemImage).tag(kind)
                    }
                }
                .onChange(of: newKnowledgeSourceKind) { _, kind in
                    applyDefaultKnowledgeLocation(for: kind)
                }

                TextField("Title", text: $newKnowledgeSourceTitle)

                HStack {
                    TextField(newKnowledgeSourceKind.settingsLocationPlaceholder, text: $newKnowledgeSourceLocation)
                        .textSelection(.enabled)

                    if newKnowledgeSourceKind.usesPathPicker {
                        Button {
                            chooseKnowledgeSourceLocation()
                        } label: {
                            Label("Choose...", systemImage: "folder.badge.plus")
                        }
                    }
                }

                Toggle("Watch for changes", isOn: $newKnowledgeSourceWatched)
                    .disabled(!newKnowledgeSourceKind.supportsWatching)

                HStack {
                    Button {
                        addKnowledgeSourceFromSettings()
                    } label: {
                        Label("Add Source", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAddKnowledgeSourceFromSettings)

                    Button {
                        Task { @MainActor in
                            await store.rebuildKnowledgeIndexManifestsUsingConfiguredEmbeddings(onlyQueued: true)
                            knowledgeRefreshMessage = "Rebuilt queued local knowledge sources."
                            persist()
                        }
                    } label: {
                        Label("Rebuild Queued", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.knowledgeSources.contains { $0.status == .queued || $0.status == .stale || $0.status == .notIndexed } == false)

                    Button {
                        Task { @MainActor in
                            await store.rebuildKnowledgeIndexManifestsUsingConfiguredEmbeddings()
                            knowledgeRefreshMessage = "Rebuilt all local knowledge sources."
                            persist()
                        }
                    } label: {
                        Label("Rebuild All", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.knowledgeSources.isEmpty)

                    Spacer()
                }

                Text(newKnowledgeSourceKind.settingsOnboardingDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let newKnowledgeSourceMessage {
                    SettingsInlineNotice(
                        message: newKnowledgeSourceMessage,
                        tone: settingsNoticeTone(for: newKnowledgeSourceMessage)
                    )
                }
            }

            Section("Retrieval Sources") {
                if store.knowledgeSources.isEmpty {
                    EmptySettingsRow(
                        title: "No knowledge sources",
                        detail: "Add local files, folders, web captures, or chat history sources to ground responses."
                    )
                } else {
                    ForEach(store.knowledgeSources) { source in
                        KnowledgeSettingsRow(
                            source: source,
                            manifest: knowledgeManifest(for: source),
                            capturedWebAsset: capturedWebAsset(for: source),
                            localOnlyMode: store.preferences.localOnlyMode ?? true,
                            isRefreshingPage: refreshingKnowledgeSourceIDs.contains(source.id),
                            refreshPage: {
                                Task { @MainActor in
                                    await refreshWebPageKnowledgeSource(source.id)
                                }
                            },
                            queueIndex: {
                                queueKnowledgeSourceIndex(source.id)
                            },
                            markStale: {
                                markKnowledgeSourceStale(source.id)
                            }
                        )
                    }
                }
            }

            Section("Index State") {
                LabeledContent("Indexed chunks", value: "\(store.knowledgeSources.reduce(0) { $0 + $1.chunkCount })")
                LabeledContent("Vector records", value: "\(store.knowledgeSources.reduce(0) { $0 + $1.embeddingRecordCount })")
                LabeledContent("Manifests", value: "\(store.knowledgeIndexManifests.count)")
                LabeledContent("Watched web pages", value: "\(watchedWebPageCount)")
                LabeledContent("Stale web captures", value: "\(staleWatchedWebPageCount)")
                LabeledContent("Queued web refreshes", value: "\(queuedWatchedWebPageCount)")

                HStack {
                    Button {
                        checkWatchedWebPageFreshness()
                    } label: {
                        Label("Check Web Captures", systemImage: "clock.arrow.circlepath")
                    }

                    Button {
                        Task { @MainActor in
                            await refreshStaleWatchedWebPages()
                        }
                    } label: {
                        Label("Refresh Queued Pages", systemImage: "arrow.clockwise")
                    }
                    .disabled(queuedWatchedWebPageCount == 0 || store.preferences.localOnlyMode == true)
                    .help(store.preferences.localOnlyMode == true ? "Turn off local-only mode before refreshing web pages from the network." : "Capture queued watched web pages and rebuild their local indexes.")

                    Spacer()
                }
                .buttonStyle(.bordered)

                if let knowledgeRefreshMessage {
                    SettingsInlineNotice(
                        message: knowledgeRefreshMessage,
                        tone: settingsNoticeTone(for: knowledgeRefreshMessage, isLoading: knowledgeRefreshMessage.hasPrefix("Refreshing "))
                    )
                }
            }
        }
    }

    private var memoryPane: some View {
        settingsForm {
            Section("Memory Behavior") {
                Toggle("Enable local memory", isOn: localMemoryBoolBinding(\.isEnabled))
                Toggle("Include memories in chat context", isOn: localMemoryBoolBinding(\.includeInChatContext))
                Toggle("Require explicit save", isOn: localMemoryBoolBinding(\.requireExplicitSave))

                Stepper(
                    value: localMemoryIntBinding(\.maximumContextMemories, range: 1...24),
                    in: 1...24
                ) {
                    LabeledContent("Maximum memories per chat") {
                        Text("\((store.preferences.localMemory ?? LocalMemorySettings()).maximumContextMemories)")
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Memory is local-first and explicit: use `/remember ...` in chat or save a memory here. Flannel does not auto-learn from every message.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Saved Memories") {
                let visibleMemoryIndices = store.localMemories.indices.filter {
                    localMemoryMatchesSearch(store.localMemories[$0])
                }

                if visibleMemoryIndices.isEmpty {
                    EmptySettingsRow(
                        title: store.localMemories.isEmpty ? "No saved memories" : "No matching memories",
                        detail: "Save preferences, durable facts, project constraints, or standing instructions for future chats."
                    )
                } else {
                    ForEach(visibleMemoryIndices, id: \.self) { index in
                        LocalMemorySettingsRow(
                            memory: $store.localMemories[index],
                            delete: {
                                store.deleteLocalMemory(store.localMemories[index].id)
                                persist()
                            },
                            persist: persist
                        )
                    }
                }
            }

            Section("Add Memory") {
                TextField("Title", text: $newMemoryTitle)
                TextField("Memory", text: $newMemoryDetail, axis: .vertical)
                    .lineLimit(2...5)

                Picker("Category", selection: $newMemoryCategory) {
                    ForEach(LocalMemoryCategory.allCases) { category in
                        Label(category.title, systemImage: category.systemImage).tag(category)
                    }
                }

                TextField("Tags", text: $newMemoryTags, prompt: Text("privacy, writing, project"))

                Button("Save Memory") {
                    guard store.addLocalMemory(
                        title: newMemoryTitle,
                        detail: newMemoryDetail,
                        category: newMemoryCategory,
                        tagNames: memoryTags(from: newMemoryTags)
                    ) != nil else { return }
                    newMemoryTitle = ""
                    newMemoryDetail = ""
                    newMemoryCategory = .fact
                    newMemoryTags = ""
                    persist()
                }
                .disabled(newMemoryDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func knowledgeManifest(for source: KnowledgeSource) -> KnowledgeIndexManifest? {
        store.knowledgeIndexManifests.first { $0.sourceID == source.id }
    }

    private func capturedWebAsset(for source: KnowledgeSource) -> LibraryAsset? {
        guard source.kind == .webPage else { return nil }
        return store.libraryAssets.first {
            $0.sourceURL?.absoluteString == source.location || $0.sourceIdentifier == source.location
        }
    }

    private var watchedWebPageCount: Int {
        store.knowledgeSources.filter { $0.kind == .webPage && $0.isWatched }.count
    }

    private var staleWatchedWebPageCount: Int {
        let watchedWebLocations = Set(
            store.knowledgeSources
                .filter { $0.kind == .webPage && $0.isWatched }
                .map(\.location)
        )
        return store.libraryAssets.filter { asset in
            guard asset.summaryStatus == .stale else { return false }
            let location = asset.sourceURL?.absoluteString ?? asset.sourceIdentifier
            return location.map { watchedWebLocations.contains($0) } ?? false
        }.count
    }

    private var queuedWatchedWebPageCount: Int {
        store.knowledgeSources.filter {
            $0.kind == .webPage && $0.isWatched && $0.status == .queued
        }.count
    }

    private func checkWatchedWebPageFreshness() {
        let queuedIDs = store.queueStaleWatchedWebPageKnowledgeSources(maximumSourceCount: Int.max)
        if queuedIDs.isEmpty {
            knowledgeRefreshMessage = "No watched web captures are older than the refresh window."
        } else {
            knowledgeRefreshMessage = "Queued \(queuedIDs.count) watched web page\(queuedIDs.count == 1 ? "" : "s") for refresh."
        }
        persist()
    }

    @MainActor
    private func refreshStaleWatchedWebPages() async {
        let staleSources = store.knowledgeSources
            .filter { $0.kind == .webPage && $0.isWatched && $0.status == .queued }
        guard !staleSources.isEmpty else {
            knowledgeRefreshMessage = "No queued watched web pages need refresh."
            return
        }

        knowledgeRefreshMessage = "Refreshing \(staleSources.count) queued web page\(staleSources.count == 1 ? "" : "s")..."
        for source in staleSources {
            await refreshWebPageKnowledgeSource(source.id, updateMessage: false)
        }
        knowledgeRefreshMessage = "Refreshed \(staleSources.count) queued web page\(staleSources.count == 1 ? "" : "s")."
        persist()
    }

    @MainActor
    private func refreshWebPageKnowledgeSource(
        _ sourceID: UUID,
        updateMessage: Bool = true
    ) async {
        guard !refreshingKnowledgeSourceIDs.contains(sourceID) else { return }
        refreshingKnowledgeSourceIDs.insert(sourceID)
        if updateMessage {
            knowledgeRefreshMessage = "Refreshing page capture..."
        }

        _ = await store.captureWebPageKnowledgeSource(sourceID)

        refreshingKnowledgeSourceIDs.remove(sourceID)
        if updateMessage {
            if let source = store.knowledgeSources.first(where: { $0.id == sourceID }) {
                knowledgeRefreshMessage = source.status == .failed
                    ? "Page refresh failed for \(source.title)."
                    : "Refreshed \(source.title)."
            } else {
                knowledgeRefreshMessage = "Page refresh finished."
            }
        }
        persist()
    }

    private func queueKnowledgeSourceIndex(_ sourceID: UUID) {
        guard let index = store.knowledgeSources.firstIndex(where: { $0.id == sourceID }) else { return }
        store.knowledgeSources[index].status = .queued
        store.knowledgeSources[index].lastErrorMessage = nil
        knowledgeRefreshMessage = "Queued \(store.knowledgeSources[index].title) for local index rebuild."
        persist()
    }

    private func markKnowledgeSourceStale(_ sourceID: UUID) {
        guard let index = store.knowledgeSources.firstIndex(where: { $0.id == sourceID }) else { return }
        store.knowledgeSources[index].status = .stale
        store.knowledgeSources[index].lastErrorMessage = nil
        if let assetIndex = store.libraryAssets.firstIndex(where: {
            $0.sourceURL?.absoluteString == store.knowledgeSources[index].location
                || $0.sourceIdentifier == store.knowledgeSources[index].location
        }) {
            store.libraryAssets[assetIndex].summaryStatus = .stale
        }
        knowledgeRefreshMessage = "Marked \(store.knowledgeSources[index].title) stale."
        persist()
    }

    private func addKnowledgeSourceFromSettings() {
        guard let source = store.addKnowledgeSource(
            title: newKnowledgeSourceTitle,
            kind: newKnowledgeSourceKind,
            location: newKnowledgeSourceLocation,
            watched: newKnowledgeSourceWatched && newKnowledgeSourceKind.supportsWatching
        ) else {
            newKnowledgeSourceMessage = "Add a readable path, repository, URL, chat history, or workspace source first."
            return
        }

        newKnowledgeSourceTitle = ""
        newKnowledgeSourceLocation = ""
        applyDefaultKnowledgeLocation(for: newKnowledgeSourceKind)
        newKnowledgeSourceMessage = "Queued \(source.title) for local retrieval."
        knowledgeRefreshMessage = "Queued \(source.title) for local index rebuild."
        persist()
    }

    private func applyDefaultKnowledgeLocation(for kind: KnowledgeSourceKind) {
        newKnowledgeSourceWatched = kind.supportsWatching

        switch kind {
        case .chatHistory:
            newKnowledgeSourceLocation = "flannel://chat-history"
        case .workspaceNotes:
            newKnowledgeSourceLocation = "flannel://workspace"
        case .folder, .file, .webPage, .codeRepository:
            if newKnowledgeSourceLocation.hasPrefix("flannel://") {
                newKnowledgeSourceLocation = ""
            }
        }
    }

    private func chooseKnowledgeSourceLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = newKnowledgeSourceKind == .file
        panel.canChooseDirectories = newKnowledgeSourceKind == .folder || newKnowledgeSourceKind == .codeRepository
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = newKnowledgeSourceKind == .codeRepository
            ? "Choose a local code repository or project folder for Flannel to index."
            : "Choose a local \(newKnowledgeSourceKind.settingsTitle.lowercased()) for Flannel to index."

        guard panel.runModal() == .OK,
              let url = panel.url else { return }

        newKnowledgeSourceLocation = url.path
        if newKnowledgeSourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newKnowledgeSourceTitle = url.lastPathComponent
        }
    }

    private var toolsPane: some View {
        settingsForm {
            Section("Tool Permissions") {
                if store.toolConfigurations.isEmpty {
                    EmptySettingsRow(
                        title: "No tools",
                        detail: "Local actions and tool permissions will appear here."
                    )
                } else {
                    ForEach(store.toolConfigurations.indices, id: \.self) { index in
                        ToolSettingsRow(
                            tool: store.toolConfigurations[index],
                            isEnabled: Binding(
                                get: { store.toolConfigurations[index].isEnabled },
                                set: {
                                    store.toolConfigurations[index].isEnabled = $0
                                    persist()
                                }
                            ),
                            policy: Binding(
                                get: { store.toolConfigurations[index].permissionPolicy },
                                set: {
                                    store.toolConfigurations[index].permissionPolicy = $0
                                    persist()
                                }
                            ),
                            endpoint: Binding(
                                get: { store.toolConfigurations[index].endpoint ?? "" },
                                set: {
                                    store.toolConfigurations[index].endpoint = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                                    persist()
                                }
                            ),
                            secretDraft: Binding(
                                get: { toolSecretDrafts[store.toolConfigurations[index].id] ?? "" },
                                set: { toolSecretDrafts[store.toolConfigurations[index].id] = $0 }
                            ),
                            setupMessage: toolSetupMessages[store.toolConfigurations[index].id],
                            saveAPIKey: { saveToolAPIKey(for: store.toolConfigurations[index].id) }
                        )
                    }
                }
            }

            Section("Recent Results") {
                if store.toolExecutionResults.isEmpty {
                    EmptySettingsRow(
                        title: "No tool results yet",
                        detail: "Executed local tools will leave auditable traces here."
                    )
                } else {
                    ForEach(store.toolExecutionResults.prefix(8)) { result in
                        LabeledContent(result.title) {
                            Text(humanized(result.status.rawValue))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var agentsPane: some View {
        settingsForm {
            Section("Workflow Defaults") {
                Toggle("Confirm before external actions", isOn: Binding(
                    get: { store.preferences.confirmBeforeExternalActions ?? true },
                    set: {
                        store.preferences.confirmBeforeExternalActions = $0
                        persist()
                    }
                ))

                Toggle("Safe mode", isOn: Binding(
                    get: { store.preferences.safeMode ?? true },
                    set: {
                        store.preferences.safeMode = $0
                        persist()
                    }
                ))

                Toggle("Enable local automations", isOn: Binding(
                    get: { store.preferences.automationsEnabled ?? true },
                    set: {
                        store.preferences.automationsEnabled = $0
                        persist()
                    }
                ))
            }

            Section("Workflow Automations") {
                if store.automations.isEmpty {
                    EmptySettingsRow(
                        title: "No automations configured",
                        detail: "Create local workflows to run approved read and retrieval tools from this workspace."
                    )
                } else {
                    ForEach(store.automations) { automation in
                        AutomationSettingsRow(
                            automation: automation,
                            toggleEnabled: {
                                store.toggleAutomation(automation.id)
                                persist()
                            },
                            run: {
                                store.runAutomation(automation.id)
                                persist()
                            }
                        )
                    }
                }
            }

            Section("Agent Traces") {
                if store.recentLocalActions.isEmpty {
                    EmptySettingsRow(
                        title: "No agent traces yet",
                        detail: "Approved local actions, automation runs, and tool-backed steps will appear here as an audit trail."
                    )
                } else {
                    ForEach(store.recentLocalActions) { action in
                        ActionTraceSettingsRow(action: action)
                    }
                }
            }

            Section("Approval Queues") {
                LabeledContent("Tool results requiring approval", value: "\(store.toolExecutionResults.filter(\.requiresApproval).count)")
                LabeledContent("Enabled automations", value: "\(store.enabledAutomations.count)")
            }
        }
    }

    private var promptsPane: some View {
        settingsForm {
            Section("Create Prompt Profile") {
                TextField("Profile name", text: $newPromptProfileTitle)
                TextField("Short description", text: $newPromptProfileDetail)
                TextField("System prompt", text: $newPromptProfilePrompt, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Tags", text: $newPromptProfileTags, prompt: Text("research, coding, writing"))
                Toggle("Make default", isOn: $newPromptProfileIsDefault)
                    .toggleStyle(.checkbox)

                Button {
                    addPromptProfile()
                } label: {
                    Label("Add Prompt Profile", systemImage: "text.badge.plus")
                }
                .disabled(!canAddPromptProfile)
            }

            Section("Default System Prompt") {
                Picker("Default prompt", selection: Binding(
                    get: { store.preferences.defaultSystemPromptProfileID },
                    set: { profileID in
                        store.preferences.defaultSystemPromptProfileID = profileID
                        for index in store.promptProfiles.indices {
                            store.promptProfiles[index].isDefault = store.promptProfiles[index].id == profileID
                        }
                        persist()
                    }
                )) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(store.promptProfiles) { profile in
                        Text(profile.title).tag(Optional(profile.id))
                    }
                }
                .disabled(store.promptProfiles.isEmpty)
            }

            Section("Profiles") {
                if store.promptProfiles.isEmpty {
                    EmptySettingsRow(
                        title: "No prompt profiles",
                        detail: "Create reusable assistant personalities and task profiles here."
                    )
                } else {
                    ForEach(store.promptProfiles.indices, id: \.self) { index in
                        let profileID = store.promptProfiles[index].id
                        PromptSettingsRow(
                            profile: $store.promptProfiles[index],
                            isDefault: profileID == store.preferences.defaultSystemPromptProfileID
                                || store.promptProfiles[index].isDefault,
                            setDefault: {
                                store.preferences.defaultSystemPromptProfileID = profileID
                                for candidateIndex in store.promptProfiles.indices {
                                    store.promptProfiles[candidateIndex].isDefault = store.promptProfiles[candidateIndex].id == profileID
                                }
                                persist()
                            },
                            clearDefault: {
                                if store.preferences.defaultSystemPromptProfileID == profileID {
                                    store.preferences.defaultSystemPromptProfileID = nil
                                }
                                if let candidateIndex = store.promptProfiles.firstIndex(where: { $0.id == profileID }) {
                                    store.promptProfiles[candidateIndex].isDefault = false
                                }
                                persist()
                            },
                            delete: {
                                store.deletePromptProfile(profileID)
                                persist()
                            },
                            persist: persist
                        )
                    }
                }
            }

            Section("Create Chat Template") {
                TextField("Template name", text: $newTemplateTitle)
                TextField("Short description", text: $newTemplateDetail)
                TextField("System prompt", text: $newTemplateSystemPrompt, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Starter prompt", text: $newTemplateStarterPrompt, axis: .vertical)
                    .lineLimit(2...6)
                Picker("Mode", selection: $newTemplateMode) {
                    ForEach(AssistantMode.allCases, id: \.self) { mode in
                        Text(mode.settingsTitle).tag(mode)
                    }
                }
                TextField("Tags", text: $newTemplateTags, prompt: Text("research, local"))
                Toggle("Pin template", isOn: $newTemplateIsPinned)
                    .toggleStyle(.checkbox)

                Button {
                    addChatTemplate()
                } label: {
                    Label("Add Chat Template", systemImage: "plus.bubble")
                }
                .disabled(!canAddChatTemplate)
            }

            Section("Chat Templates") {
                if store.chatTemplates.isEmpty {
                    EmptySettingsRow(
                        title: "No chat templates",
                        detail: "Reusable chat workflows with starter prompts, tool expectations, and provider hints will appear here."
                    )
                } else {
                    ForEach(store.chatTemplates.indices, id: \.self) { index in
                        let templateID = store.chatTemplates[index].id
                        ChatTemplateSettingsRow(
                            template: $store.chatTemplates[index],
                            providerKinds: LLMProviderKind.allCases,
                            accessModes: ProviderAccessMode.allCases,
                            toolKinds: AIToolKind.allCases,
                            knowledgeSources: store.knowledgeSources,
                            delete: {
                                store.deleteChatTemplate(templateID)
                                persist()
                            },
                            persist: persist
                        )
                    }
                }
            }
        }
    }

    private var canAddPromptProfile: Bool {
        !newPromptProfileTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !newPromptProfilePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAddChatTemplate: Bool {
        !newTemplateTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (
                !newTemplateSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !newTemplateStarterPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
    }

    private func addPromptProfile() {
        guard canAddPromptProfile else { return }
        let profile = SystemPromptProfile(
            title: newPromptProfileTitle,
            detail: newPromptProfileDetail,
            prompt: newPromptProfilePrompt,
            tags: tags(from: newPromptProfileTags),
            isDefault: newPromptProfileIsDefault
        )
        store.upsert(profile)
        newPromptProfileTitle = ""
        newPromptProfileDetail = ""
        newPromptProfilePrompt = ""
        newPromptProfileTags = ""
        newPromptProfileIsDefault = false
        persist()
    }

    private func addChatTemplate() {
        guard canAddChatTemplate else { return }
        store.upsert(
            ChatTemplate(
                title: newTemplateTitle,
                detail: newTemplateDetail,
                systemPrompt: newTemplateSystemPrompt,
                starterPrompt: newTemplateStarterPrompt,
                mode: newTemplateMode,
                tagNames: tags(from: newTemplateTags),
                isPinned: newTemplateIsPinned
            )
        )
        newTemplateTitle = ""
        newTemplateDetail = ""
        newTemplateSystemPrompt = ""
        newTemplateStarterPrompt = ""
        newTemplateMode = .workspaceCopilot
        newTemplateTags = ""
        newTemplateIsPinned = false
        persist()
    }

    private func tags(from rawValue: String) -> [String] {
        rawValue
            .split { $0 == "," || $0 == "\n" || $0 == "\t" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var privacyPane: some View {
        settingsForm {
            Section("Network Access") {
                Picker("Mode", selection: networkAccessBinding) {
                    ForEach(SettingsNetworkAccess.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(networkAccessBinding.wrappedValue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Confirm before external actions", isOn: Binding(
                    get: { store.preferences.confirmBeforeExternalActions ?? true },
                    set: {
                        store.preferences.confirmBeforeExternalActions = $0
                        persist()
                    }
                ))

                Toggle("Safe mode", isOn: Binding(
                    get: { store.preferences.safeMode ?? true },
                    set: {
                        store.preferences.safeMode = $0
                        persist()
                    }
                ))
            }

            Section("Secrets") {
                Text("API key material belongs in macOS Keychain. Flannel stores only Keychain references in the local SwiftData workspace.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var storagePane: some View {
        settingsForm {
            Section("Local Paths") {
                LabeledContent("Draft exports") {
                    HStack {
                        Text(store.preferences.draftExportDirectory ?? "")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose...") {
                            chooseExportDirectory()
                        }
                    }
                }

                TextField("Storage label", text: Binding(
                    get: { store.preferences.localStorageLabel ?? "" },
                    set: {
                        store.preferences.localStorageLabel = $0
                        persist()
                    }
                ))
            }

            Section("Workspace Counts") {
                LabeledContent("Providers", value: "\(store.providerConfigurations.count)")
                LabeledContent("Knowledge sources", value: "\(store.knowledgeSources.count)")
                LabeledContent("Tools", value: "\(store.toolConfigurations.count)")
                LabeledContent("Comparison runs", value: "\(store.modelComparisonRuns.count)")
            }

            if hasBackupActions {
                Section("Backup & Restore") {
                    Text("Export a portable local snapshot before risky changes, restore a full workspace snapshot, or import a single chat transcript.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let exportWorkspaceSnapshot {
                        Button {
                            exportWorkspaceSnapshot()
                        } label: {
                            Label("Export Workspace Snapshot", systemImage: "square.and.arrow.up")
                        }
                    }

                    if let importWorkspaceSnapshot {
                        Button {
                            importWorkspaceSnapshot()
                        } label: {
                            Label("Import Workspace Snapshot", systemImage: "square.and.arrow.down")
                        }
                    }

                    if let importChat {
                        Button {
                            importChat()
                        } label: {
                            Label("Import Chat Transcript", systemImage: "bubble.left.and.bubble.right")
                        }
                    }
                }
            }

            Section("Delete Local Workspace Data") {
                Text("This clears local chats, projects, drafts, captures, knowledge indexes, model comparison runs, pinned/archive state, local memories, provider references, and tool traces. Flannel will recreate clean local defaults. Keychain secret values are not deleted by this reset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Type DELETE FLANNEL DATA", text: $resetWorkspaceConfirmation)

                Button(role: .destructive) {
                    resetLocalWorkspaceData()
                } label: {
                    Label("Delete Local Workspace Data", systemImage: "trash")
                }
                .disabled(resetWorkspaceConfirmation != "DELETE FLANNEL DATA")

                if let resetWorkspaceMessage {
                    SettingsInlineNotice(
                        message: resetWorkspaceMessage,
                        tone: settingsNoticeTone(for: resetWorkspaceMessage)
                    )
                }
            }
        }
    }

    private var hasBackupActions: Bool {
        importChat != nil || exportWorkspaceSnapshot != nil || importWorkspaceSnapshot != nil
    }

    private var advancedPane: some View {
        settingsForm {
            Section("Automations") {
                Toggle("Enable local automations", isOn: Binding(
                    get: { store.preferences.automationsEnabled ?? true },
                    set: {
                        store.preferences.automationsEnabled = $0
                        persist()
                    }
                ))

                LabeledContent("Configured automations", value: "\(store.automations.count)")
            }

            Section("AI SDK Bridge") {
                Text("The current Vercel AI SDK remains an optional localhost bridge for TypeScript and Node workflow agents. Native chat stays Swift-first.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var networkAccessBinding: Binding<SettingsNetworkAccess> {
        Binding(
            get: {
                if store.preferences.localOnlyMode ?? true {
                    return .localOnly
                }
                return (store.preferences.allowCloudProviders ?? false) ? .allowCloudProviders : .localAndCLI
            },
            set: { mode in
                switch mode {
                case .localOnly:
                    store.preferences.localOnlyMode = true
                    store.preferences.allowCloudProviders = false
                case .localAndCLI:
                    store.preferences.localOnlyMode = false
                    store.preferences.allowCloudProviders = false
                case .allowCloudProviders:
                    store.preferences.localOnlyMode = false
                    store.preferences.allowCloudProviders = true
                }
                persist()
            }
        )
    }

    private func localMemoryBoolBinding(_ keyPath: WritableKeyPath<LocalMemorySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                (store.preferences.localMemory ?? LocalMemorySettings())[keyPath: keyPath]
            },
            set: { value in
                var settings = store.preferences.localMemory ?? LocalMemorySettings()
                settings[keyPath: keyPath] = value
                store.preferences.localMemory = settings
                persist()
            }
        )
    }

    private func localMemoryIntBinding(
        _ keyPath: WritableKeyPath<LocalMemorySettings, Int>,
        range: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding(
            get: {
                min(max((store.preferences.localMemory ?? LocalMemorySettings())[keyPath: keyPath], range.lowerBound), range.upperBound)
            },
            set: { value in
                var settings = store.preferences.localMemory ?? LocalMemorySettings()
                settings[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
                store.preferences.localMemory = settings
                persist()
            }
        )
    }

    private func localMemoryMatchesSearch(_ memory: LocalMemoryRecord) -> Bool {
        guard !settingsSearchQuery.isEmpty else { return true }
        let haystack = [
            memory.title,
            memory.detail,
            memory.category.title,
            memory.category.detail,
            memory.tagNames.joined(separator: " ")
        ].joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(settingsSearchQuery)
    }

    private func memoryTags(from rawValue: String) -> [String] {
        rawValue
            .split { $0 == "," || $0 == "\n" || $0 == "\t" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func providerMatchesSearch(_ provider: ProviderConfiguration) -> Bool {
        guard !settingsSearchQuery.isEmpty else { return true }

        let haystack = [
            provider.displayName,
            provider.kind.title,
            provider.modeFamily.title,
            provider.modeFamily.detail,
            provider.providerModeChoiceTitle,
            provider.providerModeChoiceDetail,
            provider.accessMode.title,
            provider.privacyScope.title,
            provider.endpoint,
            provider.modelIdentifier,
            provider.connectionStatus.rawValue,
            provider.lastErrorMessage ?? "",
            provider.availableModels.joined(separator: " "),
            provider.capabilities.map(\.title).joined(separator: " "),
            report(for: provider).diagnostics.map(\.message).joined(separator: " ")
        ].joined(separator: " ")

        return haystack.localizedCaseInsensitiveContains(settingsSearchQuery)
    }

    private func localDiscoveryResultMatchesSearch(_ result: LocalProviderDiscoveryResult) -> Bool {
        guard !settingsSearchQuery.isEmpty else { return true }

        let modelSearchText = result.models.map { model in
            let fields: [String] = [
                model.name,
                model.displayName ?? "",
                model.publisher ?? "",
                model.family ?? "",
                model.parameterSize ?? "",
                model.quantization ?? "",
                model.format ?? "",
                model.contextWindowTokens.map { String($0) } ?? "",
                model.loadedInstanceCount.map { String($0) } ?? "",
                model.sizeBytes.map { String($0) } ?? "",
                model.sizeVRAMBytes.map { String($0) } ?? "",
                model.selectedVariant ?? "",
                model.capabilities.map(\.title).joined(separator: " ")
            ]
            return fields.joined(separator: " ")
        }.joined(separator: " ")

        let haystack = [
            result.providerKind.title,
            result.endpoint,
            result.status.rawValue,
            result.errorMessage ?? "",
            modelSearchText
        ].joined(separator: " ")

        return haystack.localizedCaseInsensitiveContains(settingsSearchQuery)
    }

    private var transcriptLanguages: [SettingsTranscriptLanguage] {
        [
            SettingsTranscriptLanguage(code: "en", label: "English"),
            SettingsTranscriptLanguage(code: "es", label: "Spanish"),
            SettingsTranscriptLanguage(code: "fr", label: "French"),
            SettingsTranscriptLanguage(code: "de", label: "German"),
            SettingsTranscriptLanguage(code: "ja", label: "Japanese")
        ]
    }

    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form(content: content)
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 860, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func addProviderRoute(
        kind: LLMProviderKind,
        accessMode: ProviderAccessMode? = nil,
        privacyScope: ProviderPrivacyScope? = nil
    ) {
        let provider = store.createProviderRoute(
            kind: kind,
            accessMode: accessMode,
            privacyScope: privacyScope
        )
        providerSetupReports[provider.id] = ProviderSetupService.shared.report(
            for: provider,
            preferences: store.preferences
        )
        providerSetupMessages[provider.id] = "Created \(provider.displayName). Configure this route, then check readiness."
        persist()
    }

    private func duplicateProviderRoute(_ providerID: UUID) {
        guard let provider = store.duplicateProviderRoute(providerID) else { return }
        providerSetupReports[provider.id] = ProviderSetupService.shared.report(
            for: provider,
            preferences: store.preferences
        )
        providerSetupMessages[provider.id] = "Duplicated \(provider.displayName). Review settings before enabling."
        persist()
    }

    private func deleteProviderRoute(_ providerID: UUID) {
        guard store.deleteProviderRoute(providerID) else { return }
        providerSetupReports[providerID] = nil
        providerReadinessValidations[providerID] = nil
        providerSecretDrafts[providerID] = nil
        providerSetupMessages[providerID] = nil
        validatingProviderIDs.remove(providerID)
        persist()
    }

    private func resetLocalWorkspaceData() {
        let workspaceID = store.resetLocalWorkspace()
        providerSetupReports = [:]
        providerReadinessValidations = [:]
        validatingProviderIDs = []
        providerSecretDrafts = [:]
        providerSetupMessages = [:]
        isCheckingAllProviderReadiness = false
        providerReadinessBatchMessage = nil
        toolSecretDrafts = [:]
        toolSetupMessages = [:]
        localDiscoveryMessage = nil
        ollamaPullMessage = nil
        deletingOllamaModelID = nil
        resetWorkspaceConfirmation = ""
        resetWorkspaceMessage = "Local workspace data was reset. New workspace ID: \(workspaceID.uuidString). Keychain secret values were left untouched."
        persist()
    }

    private func report(for provider: ProviderConfiguration) -> ProviderSetupReport {
        providerSetupReports[provider.id] ?? ProviderSetupService.shared.report(
            for: provider,
            preferences: store.preferences
        )
    }

    private func validateProvider(_ providerID: UUID) {
        guard let provider = store.providerConfigurations.first(where: { $0.id == providerID }),
              let report = store.validateProviderSetup(providerID) else { return }
        providerSetupReports[providerID] = report
        providerReadinessValidations[providerID] = nil
        providerSetupMessages[providerID] = ProviderSettingsMessaging.preflightSetupMessage(
            for: provider,
            report: report
        )
    }

    private func invalidateProviderReadiness(_ providerID: UUID) {
        providerSetupReports[providerID] = nil
        providerReadinessValidations[providerID] = nil
        providerSetupMessages[providerID] = nil
    }

    private func checkProviderReadiness(_ providerID: UUID) {
        guard let provider = store.providerConfigurations.first(where: { $0.id == providerID }),
              !validatingProviderIDs.contains(providerID) else { return }

        validateProvider(providerID)
        validatingProviderIDs.insert(providerID)
        providerSetupMessages[providerID] = ProviderSettingsMessaging.pendingReadinessMessage(
            for: provider
        )

        Task {
            let validation = await ProviderSetupService.shared.validateReadiness(
                for: provider,
                preferences: store.preferences
            )

            await MainActor.run {
                validatingProviderIDs.remove(providerID)
                providerReadinessValidations[providerID] = validation
                providerSetupReports[providerID] = validation.report
                _ = store.applyProviderReadinessValidation(validation, providerID: providerID)
                providerSetupMessages[providerID] = ProviderSettingsMessaging.setupMessage(
                    for: provider,
                    validation: validation
                )

                persist()
            }
        }
    }

    private func checkAllProviderReadiness() {
        guard !isCheckingAllProviderReadiness else { return }

        let providerIDs = store.providerConfigurations.map(\.id)
        guard !providerIDs.isEmpty else {
            providerReadinessBatchMessage = ProviderReadinessBatchSummary(
                checkedCount: 0,
                readyCount: 0,
                needsAttentionCount: 0
            ).message
            return
        }

        isCheckingAllProviderReadiness = true
        providerReadinessBatchMessage = "Queued \(providerIDs.count) route\(providerIDs.count == 1 ? "" : "s") for readiness checks."
        validatingProviderIDs.formUnion(providerIDs)
        for providerID in providerIDs {
            providerReadinessValidations[providerID] = nil
            providerSetupMessages[providerID] = "Queued for readiness check..."
        }

        Task { @MainActor in
            var validations: [(providerID: UUID, validation: ProviderReadinessValidation)] = []

            for (offset, providerID) in providerIDs.enumerated() {
                guard store.providerConfigurations.contains(where: { $0.id == providerID }) else {
                    validatingProviderIDs.remove(providerID)
                    continue
                }

                validateProvider(providerID)

                guard let provider = store.providerConfigurations.first(where: { $0.id == providerID }) else {
                    validatingProviderIDs.remove(providerID)
                    continue
                }

                providerReadinessBatchMessage = "Checking \(offset + 1) of \(providerIDs.count): \(provider.displayName)"
                providerSetupMessages[providerID] = ProviderSettingsMessaging.pendingReadinessMessage(
                    for: provider
                )

                let validation = await ProviderSetupService.shared.validateReadiness(
                    for: provider,
                    preferences: store.preferences
                )
                validations.append((providerID: providerID, validation: validation))
                providerReadinessValidations[providerID] = validation
                providerSetupReports[providerID] = validation.report
                providerSetupMessages[providerID] = providerSetupMessage(
                    for: provider,
                    validation: validation
                )
                validatingProviderIDs.remove(providerID)
            }

            let summary = store.applyProviderReadinessValidations(validations)
            providerReadinessBatchMessage = summary.message
            isCheckingAllProviderReadiness = false
            persist()
        }
    }

    private func providerSetupMessage(
        for provider: ProviderConfiguration,
        validation: ProviderReadinessValidation
    ) -> String {
        ProviderSettingsMessaging.setupMessage(for: provider, validation: validation)
    }

    private func saveAPIKey(for providerID: UUID) {
        do {
            let secret = providerSecretDrafts[providerID] ?? ""
            guard let report = try store.saveProviderAPIKey(providerID, secret: secret) else { return }
            providerSetupReports[providerID] = report
            providerReadinessValidations[providerID] = nil
            providerSecretDrafts[providerID] = ""
            providerSetupMessages[providerID] = report.hasBlockingIssues
                ? report.diagnostics.first(where: \.isBlocking)?.message
                : "API key saved in Keychain."
            persist()
        } catch {
            providerSetupMessages[providerID] = error.localizedDescription
        }
    }

    private func deleteAPIKey(for providerID: UUID) {
        do {
            guard let result = try store.deleteProviderAPIKey(providerID) else { return }
            providerSetupReports[providerID] = result.report
            providerReadinessValidations[providerID] = nil
            providerSecretDrafts[providerID] = ""
            providerSetupMessages[providerID] = result.message
            persist()
        } catch {
            providerSetupMessages[providerID] = "Keychain delete failed: \(error.localizedDescription)"
        }
    }

    private func saveToolAPIKey(for toolID: UUID) {
        do {
            let secret = toolSecretDrafts[toolID] ?? ""
            guard let tool = try store.saveToolAPIKey(toolID, secret: secret) else { return }
            toolSecretDrafts[toolID] = ""
            toolSetupMessages[toolID] = tool.secretReference == nil
                ? "Paste a Brave Search API key before saving."
                : "API key saved in Keychain."
            persist()
        } catch {
            toolSetupMessages[toolID] = error.localizedDescription
        }
    }

    private func discoverLocalModels() async {
        isDiscoveringLocalModels = true
        localDiscoveryMessage = "Checking local providers..."
        let discoveryService = LocalProviderDiscoveryService()
        let targets = store.localProviderDiscoveryTargets(
            extraOllamaEndpoint: ollamaPullEndpoint
        )

        let results = await discoveryService.discover(targets: targets)
        store.apply(results)
        for provider in store.providerConfigurations where provider.kind == .ollama || provider.kind == .lmStudio {
            validateProvider(provider.id)
        }
        localDiscoveryMessage = ProviderSettingsMessaging.localDiscoveryMessage(for: results)
        isDiscoveringLocalModels = false
        persist()
    }

    private func pullOllamaModel() async {
        guard !isPullingOllamaModel else { return }

        let model = ollamaPullModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = ollamaPullEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            ollamaPullMessage = "Enter an Ollama model name."
            return
        }

        isPullingOllamaModel = true
        ollamaPullMessage = "Starting \(model)..."

        do {
            var lastUpdate: OllamaModelPullUpdate?
            let service = LocalModelManagementService()
            for try await update in service.pullOllamaModel(model: model, endpoint: endpoint) {
                lastUpdate = update
                if let progressFraction = update.progressFraction {
                    ollamaPullMessage = "\(update.status) - \(progressFraction.formatted(.percent.precision(.fractionLength(0))))"
                } else {
                    ollamaPullMessage = update.status
                }
            }

            if lastUpdate?.status.localizedCaseInsensitiveContains("success") == true {
                ollamaPullMessage = "Pulled \(model). Refreshing discovery..."
            } else {
                ollamaPullMessage = "Finished \(model). Refreshing discovery..."
            }
            await discoverLocalModels()
            ollamaPullMessage = "Ready: \(model) is available from Ollama."
        } catch {
            ollamaPullMessage = error.localizedDescription
        }

        isPullingOllamaModel = false
    }

    private func inspectOllamaModel(_ model: LocalModelDescriptor) async {
        guard model.providerKind == .ollama,
              inspectingOllamaModelID == nil else { return }

        inspectingOllamaModelID = model.id
        modelInspectionMessage = "Inspecting \(model.displayName ?? model.name)..."

        do {
            inspectedOllamaModelInfo = try await LocalModelManagementService().showOllamaModel(
                model: model.name,
                endpoint: model.endpoint,
                verbose: true
            )
            modelInspectionMessage = nil
        } catch {
            modelInspectionMessage = error.localizedDescription
        }

        inspectingOllamaModelID = nil
    }

    private func deleteOllamaModel(_ model: LocalModelDescriptor) async {
        guard model.providerKind == .ollama,
              deletingOllamaModelID == nil else { return }

        deletingOllamaModelID = model.id
        localDiscoveryMessage = "Deleting \(model.displayName ?? model.name) from Ollama..."

        do {
            try await LocalModelManagementService().deleteOllamaModel(
                model: model.name,
                endpoint: model.endpoint
            )
            removeCachedLocalModel(model)
            localDiscoveryMessage = "Deleted \(model.displayName ?? model.name). Refreshing discovery..."
            await discoverLocalModels()
            localDiscoveryMessage = "Deleted \(model.displayName ?? model.name) from Ollama."
        } catch {
            localDiscoveryMessage = error.localizedDescription
        }

        deletingOllamaModelID = nil
    }

    private func loadLMStudioModel(_ model: LocalModelDescriptor) async {
        guard model.providerKind == .lmStudio,
              loadingLMStudioModelID == nil else { return }

        loadingLMStudioModelID = model.id
        localDiscoveryMessage = "Loading \(model.displayName ?? model.name) in LM Studio..."

        do {
            let result = try await LocalModelManagementService().loadLMStudioModel(
                model: model.name,
                endpoint: model.endpoint
            )
            if let instanceID = result.instanceID {
                localDiscoveryMessage = "Loaded \(model.displayName ?? model.name) as \(instanceID). Refreshing discovery..."
            } else {
                localDiscoveryMessage = "Loaded \(model.displayName ?? model.name). Refreshing discovery..."
            }
            await discoverLocalModels()
            localDiscoveryMessage = "Loaded \(model.displayName ?? model.name) in LM Studio."
        } catch {
            localDiscoveryMessage = error.localizedDescription
        }

        loadingLMStudioModelID = nil
    }

    private func unloadLMStudioModel(_ model: LocalModelDescriptor) async {
        guard model.providerKind == .lmStudio,
              unloadingLMStudioModelID == nil else { return }

        guard let instanceID = model.loadedInstanceIDs?.first else {
            localDiscoveryMessage = "Run discovery again to get the loaded LM Studio instance ID for \(model.displayName ?? model.name)."
            return
        }

        unloadingLMStudioModelID = model.id
        localDiscoveryMessage = "Unloading \(model.displayName ?? model.name) from LM Studio..."

        do {
            _ = try await LocalModelManagementService().unloadLMStudioModel(
                instanceID: instanceID,
                endpoint: model.endpoint
            )
            localDiscoveryMessage = "Unloaded \(model.displayName ?? model.name). Refreshing discovery..."
            await discoverLocalModels()
            localDiscoveryMessage = "Unloaded \(model.displayName ?? model.name) from LM Studio."
        } catch {
            localDiscoveryMessage = error.localizedDescription
        }

        unloadingLMStudioModelID = nil
    }

    private func removeCachedLocalModel(_ model: LocalModelDescriptor) {
        for index in store.providerConfigurations.indices where
            store.providerConfigurations[index].kind == model.providerKind
                && store.providerConfigurations[index].endpoint == model.endpoint {
            store.providerConfigurations[index].availableModels.removeAll { candidate in
                candidate == model.name || model.displayName.map { candidate == $0 } == true
            }
            store.providerConfigurations[index].discoveredModelNames.removeAll { candidate in
                candidate == model.name || model.displayName.map { candidate == $0 } == true
            }
            store.providerConfigurations[index].staleDiscoveredModelNames.removeAll { candidate in
                candidate == model.name || model.displayName.map { candidate == $0 } == true
            }
            if store.providerConfigurations[index].modelIdentifier == model.name
                || model.displayName.map({ store.providerConfigurations[index].modelIdentifier == $0 }) == true {
                store.providerConfigurations[index].modelIdentifier = store.providerConfigurations[index].availableModels.first ?? ""
            }
        }
        persist()
    }

    private func selectLocalModel(_ model: LocalModelDescriptor) {
        guard let providerID = store.selectDiscoveredLocalModelForChat(model) else {
            localDiscoveryMessage = "\(model.displayName ?? model.name) is an embedding model. It is available for local RAG, but it cannot be used as the chat model."
            return
        }

        validateProvider(providerID)
        localDiscoveryMessage = "Using \(model.displayName ?? model.name) for \(model.providerKind.title)."
        persist()
    }

    private func parentOptions(for folder: ChatFolder) -> [ChatFolder] {
        let disallowedIDs = store.descendantFolderIDs(of: folder.id).union([folder.id])
        return store.chatFolders
            .filter { !disallowedIDs.contains($0.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where Flannel exports chat and draft files."

        if panel.runModal() == .OK, let url = panel.url {
            store.preferences.draftExportDirectory = url.path
            persist()
        }
    }

    private func humanized(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private extension ToolConfiguration {
    var exposesConnectorSettings: Bool {
        switch kind {
        case .webSearch, .github, .notion, .youtube, .x:
            true
        case .webPageReader, .localFileRead, .localFileWrite, .terminal, .codeExecution, .browserAutomation, .workspaceSearch, .ragRetrieval:
            false
        }
    }

    var connectorEndpointPlaceholder: String {
        switch kind {
        case .github:
            "GitHub API endpoint"
        case .notion:
            "Notion API endpoint"
        case .youtube:
            "YouTube Data API endpoint"
        case .x:
            "X API endpoint"
        case .webSearch:
            "Search endpoint"
        case .webPageReader, .localFileRead, .localFileWrite, .terminal, .codeExecution, .browserAutomation, .workspaceSearch, .ragRetrieval:
            "Connector endpoint"
        }
    }

    var connectorSecretName: String {
        switch kind {
        case .github:
            "GitHub token"
        case .notion:
            "Notion integration token"
        case .youtube:
            "YouTube Data API key"
        case .x:
            "X API bearer token"
        case .webSearch:
            "Brave Search API key"
        case .webPageReader, .localFileRead, .localFileWrite, .terminal, .codeExecution, .browserAutomation, .workspaceSearch, .ragRetrieval:
            "API key"
        }
    }

    var connectorSecretPlaceholder: String {
        "Paste \(connectorSecretName)"
    }
}

enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
    case general
    case models
    case knowledge
    case memory
    case tools
    case agents
    case prompts
    case privacy
    case storage
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .models:
            "Models & Providers"
        case .knowledge:
            "Knowledge"
        case .memory:
            "Memory"
        case .tools:
            "Tools"
        case .agents:
            "Agents"
        case .prompts:
            "Prompts"
        case .privacy:
            "Privacy"
        case .storage:
            "Storage"
        case .advanced:
            "Advanced"
        }
    }

    var detail: String {
        switch self {
        case .general:
            "Startup, history, and folders."
        case .models:
            "Provider routing, BYOK keys, account CLIs, local servers, and model defaults."
        case .knowledge:
            "Local retrieval sources, indexing state, and grounded context."
        case .memory:
            "User-saved memories, standing context, and local recall controls."
        case .tools:
            "Tool permissions, local actions, and recent execution results."
        case .agents:
            "Workflow defaults, safety controls, and agent trace queues."
        case .prompts:
            "System prompt profiles and reusable assistant personalities."
        case .privacy:
            "Network access, local-only mode, external confirmations, and secrets."
        case .storage:
            "Export paths, local storage labels, and workspace counts."
        case .advanced:
            "Automations and developer bridge preferences."
        }
    }

    var sidebarDetail: String {
        switch self {
        case .general:
            "Startup, history, folders"
        case .models:
            "Routes, keys, local models"
        case .knowledge:
            "Sources and indexing"
        case .memory:
            "Saved memory, recall"
        case .tools:
            "Permissions, tool runs"
        case .agents:
            "Workflows and traces"
        case .prompts:
            "Profiles and templates"
        case .privacy:
            "Network and secrets"
        case .storage:
            "Exports and storage"
        case .advanced:
            "Automation, bridge"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .models:
            "cpu"
        case .knowledge:
            "books.vertical"
        case .memory:
            "brain.head.profile"
        case .tools:
            "wrench.and.screwdriver"
        case .agents:
            "flowchart"
        case .prompts:
            "text.cursor"
        case .privacy:
            "lock.shield"
        case .storage:
            "internaldrive"
        case .advanced:
            "hammer"
        }
    }
}

enum SettingsNavigationSection: String, CaseIterable, Identifiable {
    case workspace
    case ai
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace:
            "Workspace"
        case .ai:
            "AI"
        case .system:
            "System"
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .workspace:
            [.general, .knowledge, .memory, .storage]
        case .ai:
            [.models, .tools, .agents, .prompts]
        case .system:
            [.privacy, .advanced]
        }
    }
}

private struct ProviderSettingsGroup: Identifiable {
    var kind: ProviderSettingsGroupKind
    var providerIndices: [Int]

    var id: ProviderSettingsGroupKind { kind }
}

private enum ProviderSettingsGroupKind: String, CaseIterable, Identifiable {
    case localServers
    case subscriptionCLI
    case byokAPIs
    case localBridge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localServers:
            "Local Server Routes"
        case .subscriptionCLI:
            "Account CLI Routes"
        case .byokAPIs:
            "API-Key Cloud Routes"
        case .localBridge:
            "Local Bridge Route"
        }
    }

    var detail: String {
        switch self {
        case .localServers:
            "Ollama and LM Studio require a running local server and selected local model. They do not use provider API keys or account sign-in."
        case .subscriptionCLI:
            "ChatGPT/Codex and Claude Code use locally authenticated commands. They do not store or read provider API keys."
        case .byokAPIs:
            "Hosted providers require your own API key saved in macOS Keychain before cloud requests are allowed."
        case .localBridge:
            "The optional bridge points at a local service that owns its own provider runtime and credential policy."
        }
    }

    var systemImage: String {
        switch self {
        case .localServers:
            "server.rack"
        case .subscriptionCLI:
            "terminal"
        case .byokAPIs:
            "key"
        case .localBridge:
            "point.3.connected.trianglepath.dotted"
        }
    }

    func contains(_ provider: ProviderConfiguration) -> Bool {
        switch self {
        case .localServers:
            provider.accessMode == .localServer || provider.privacyScope == .localOnly
        case .subscriptionCLI:
            provider.accessMode == .subscriptionCLI || provider.privacyScope == .localCLI
        case .byokAPIs:
            provider.privacyScope == .externalAPI
                || provider.accessMode == .apiKey
                || provider.accessMode == .openAICompatible
                || provider.accessMode == .anthropicCompatible
        case .localBridge:
            provider.accessMode == .aiSDKBridge || provider.privacyScope == .bridgeService
        }
    }

    func isAllowed(in networkMode: SettingsNetworkAccess) -> Bool {
        switch self {
        case .localServers:
            true
        case .subscriptionCLI:
            networkMode != .localOnly
        case .byokAPIs, .localBridge:
            networkMode == .allowCloudProviders
        }
    }
}

private enum ProviderModeGuideKind: String, CaseIterable, Identifiable {
    case localServer
    case subscriptionCLI
    case apiKey
    case compatibleEndpoint
    case aiSDKBridge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localServer:
            "Local server routes"
        case .subscriptionCLI:
            "Account CLI routes"
        case .apiKey:
            "API-key routes"
        case .compatibleEndpoint:
            "OpenAI-compatible endpoints"
        case .aiSDKBridge:
            "Local bridge route"
        }
    }

    var detail: String {
        switch self {
        case .localServer:
            "Use loopback model servers such as Ollama or LM Studio. These routes need a running local server and selected local model, not provider API keys."
        case .subscriptionCLI:
            "Use a locally authenticated CLI session such as ChatGPT/Codex or Claude Code. App API keys stay separate from CLI account or API-key auth."
        case .apiKey:
            "Use the provider's official hosted API. Each route needs its own Keychain-backed API key before remote requests can run."
        case .compatibleEndpoint:
            "Use a custom OpenAI-compatible endpoint, or an Anthropic-compatible endpoint when that route mode is selected. These routes always need an endpoint and model id, and they may stay local or go remote depending on the endpoint."
        case .aiSDKBridge:
            "Use the optional local AI SDK bridge service. The bridge owns downstream provider runtime and credential handling outside this app."
        }
    }

    var systemImage: String {
        switch self {
        case .localServer:
            "server.rack"
        case .subscriptionCLI:
            "terminal"
        case .apiKey:
            "key"
        case .compatibleEndpoint:
            "arrow.left.arrow.right"
        case .aiSDKBridge:
            "point.3.connected.trianglepath.dotted"
        }
    }

    var emptyStateExamples: String {
        switch self {
        case .localServer:
            "Examples: Ollama, LM Studio"
        case .subscriptionCLI:
            "Examples: ChatGPT/Codex CLI, Claude Code"
        case .apiKey:
            "Examples: OpenAI, Anthropic, Gemini, xAI, Mistral, Groq, OpenRouter, Perplexity"
        case .compatibleEndpoint:
            "Examples: local LM Studio-compatible servers, custom remote OpenAI-compatible APIs, Anthropic-compatible endpoints"
        case .aiSDKBridge:
            "Example: Vercel AI SDK bridge"
        }
    }

    func matches(_ provider: ProviderConfiguration) -> Bool {
        switch self {
        case .localServer:
            provider.accessMode == .localServer
        case .subscriptionCLI:
            provider.accessMode == .subscriptionCLI
        case .apiKey:
            provider.accessMode == .apiKey
        case .compatibleEndpoint:
            provider.accessMode == .openAICompatible || provider.accessMode == .anthropicCompatible
        case .aiSDKBridge:
            provider.accessMode == .aiSDKBridge
        }
    }
}

private struct ProviderModeGuideAvailability {
    var title: String
    var tone: FlannelStatusTone
    var systemImage: String
}

private struct SettingsSidebarRow: View {
    var tab: SettingsTab

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                Text(tab.detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2...3)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        } icon: {
            Image(systemName: tab.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
        .labelStyle(.titleAndIcon)
        .frame(minHeight: 58, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .help(tab.detail)
        .accessibilityHint(tab.detail)
    }
}

private enum SettingsNoticeTone: Equatable {
    case loading
    case info
    case success
    case error

    var color: Color {
        switch self {
        case .loading, .info:
            .secondary
        case .success:
            .green
        case .error:
            .red
        }
    }

    var systemImage: String {
        switch self {
        case .loading:
            "clock.arrow.circlepath"
        case .info:
            "info.circle"
        case .success:
            "checkmark.circle"
        case .error:
            "exclamationmark.triangle"
        }
    }
}

private func settingsNoticeTone(for message: String, isLoading: Bool = false) -> SettingsNoticeTone {
    if isLoading {
        return .loading
    }

    let normalizedMessage = message.lowercased()
    if normalizedMessage.contains("failed")
        || normalizedMessage.contains("error")
        || normalizedMessage.contains("attention")
        || normalizedMessage.contains("enter ") {
        return .error
    }
    if normalizedMessage.contains("ready")
        || normalizedMessage.contains("created")
        || normalizedMessage.contains("duplicated")
        || normalizedMessage.contains("deleted")
        || normalizedMessage.contains("finished")
        || normalizedMessage.contains("refreshed")
        || normalizedMessage.contains("saved")
        || normalizedMessage.hasPrefix("using ") {
        return .success
    }
    return .info
}

private func settingsProviderReadinessNoticeTone(for message: String, isLoading: Bool = false) -> SettingsNoticeTone {
    if isLoading {
        return .loading
    }

    let normalizedMessage = message.lowercased()
    if normalizedMessage.hasPrefix("checked ") && normalizedMessage.contains("0 need attention") {
        return .success
    }
    return settingsNoticeTone(for: message)
}

private struct SettingsInlineNotice: View {
    var message: String
    var tone: SettingsNoticeTone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if tone == .loading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: tone.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tone.color)
            }

            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(tone.color)
        .padding(.horizontal, FlannelSpacing.messageHorizontal)
        .padding(.vertical, FlannelSpacing.messageVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flannelPaneSurface(.subtle, cornerRadius: FlannelRadius.md)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsRouteHeader: View {
    var tab: SettingsTab
    var isSearchActive: Bool
    var exitSettings: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: tab.systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title)
                    .font(.title2.weight(.semibold))
                Text(tab.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            HStack(spacing: 8) {
                if isSearchActive {
                    FlannelStatusChip(
                        "Search active",
                        systemImage: "magnifyingglass",
                        tone: .info,
                        prominence: .subtle
                    )
                    .accessibilityLabel("Settings search is active")
                }

                if let exitSettings {
                    Button(action: exitSettings) {
                        Label("Exit Settings", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Return to the active chat.")
                    .accessibilityLabel("Exit Settings and return to chat")
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsTranscriptLanguage: Identifiable {
    var code: String
    var label: String

    var id: String { code }
}

private enum SettingsNetworkAccess: String, CaseIterable, Identifiable {
    case localOnly
    case localAndCLI
    case allowCloudProviders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localOnly:
            "Local models only"
        case .localAndCLI:
            "Local models and CLI subscriptions"
        case .allowCloudProviders:
            "Allow cloud providers"
        }
    }

    var detail: String {
        switch self {
        case .localOnly:
            "Only local server providers such as Ollama and LM Studio can become active."
        case .localAndCLI:
            "Local servers and authenticated local CLIs can become active; external API providers remain blocked."
        case .allowCloudProviders:
            "BYOK hosted API providers can become active after their keys are saved in Keychain."
        }
    }

    var systemImage: String {
        switch self {
        case .localOnly:
            "lock"
        case .localAndCLI:
            "terminal"
        case .allowCloudProviders:
            "network"
        }
    }
}

private struct ProviderModeGuide: View {
    var networkMode: SettingsNetworkAccess
    var providers: [ProviderConfiguration]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: networkMode.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Current privacy mode: \(networkMode.title)")
                        .font(.subheadline.weight(.semibold))
                    Text(networkMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(ProviderModeGuideKind.allCases) { kind in
                ProviderModeGuideRow(
                    kind: kind,
                    networkMode: networkMode,
                    providers: providers
                )
            }

            Text("Capabilities shown here come from the configured routes and their selected or discovered models. OpenAI API and ChatGPT/Codex CLI are separate routes, and Anthropic API and Claude Code CLI are separate routes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private struct ProviderModeGuideRow: View {
    var kind: ProviderModeGuideKind
    var networkMode: SettingsNetworkAccess
    var providers: [ProviderConfiguration]

    private var configuredProviders: [ProviderConfiguration] {
        providers.filter(kind.matches)
    }

    private var configuredRouteCount: Int {
        configuredProviders.count
    }

    private var configuredModelCount: Int {
        configuredProviders.filter {
            !$0.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var capabilitySummary: String {
        let capabilities = Set(configuredProviders.flatMap(\.capabilities))
        guard !capabilities.isEmpty else {
            return configuredProviders.isEmpty
                ? "Add a route here to surface its model capabilities in Settings."
                : "Choose a model or run Local Discovery to surface capabilities for this route type."
        }

        let orderedTitles = ModelCapability.allCases
            .filter { capabilities.contains($0) }
            .map(\.title)
        return "Capabilities: \(orderedTitles.joined(separator: ", "))"
    }

    private var configuredProviderSummary: String {
        guard !configuredProviders.isEmpty else { return kind.emptyStateExamples }

        let names = configuredProviders.prefix(4).map(\.displayName)
        let remainingCount = configuredProviders.count - names.count
        let suffix = remainingCount > 0 ? " +\(remainingCount) more" : ""
        return "Configured: \(names.joined(separator: ", "))\(suffix)"
    }

    private var routeSummary: String {
        guard !configuredProviders.isEmpty else { return "No routes configured yet." }

        let modelSummary = "\(configuredModelCount)/\(configuredRouteCount) models selected"

        switch kind {
        case .compatibleEndpoint:
            let localCount = configuredProviders.filter { $0.runtimeBoundary == .localServer }.count
            let remoteCount = configuredProviders.filter { $0.runtimeBoundary == .externalAPI }.count
            let localDetail = localCount > 0 ? "\(localCount) local" : nil
            let remoteDetail = remoteCount > 0 ? "\(remoteCount) remote" : nil
            let boundaryDetail = [localDetail, remoteDetail]
                .compactMap { $0 }
                .joined(separator: " • ")
            if boundaryDetail.isEmpty {
                return "\(configuredRouteCount) routes • \(modelSummary)"
            }
            return "\(configuredRouteCount) routes • \(modelSummary) • \(boundaryDetail)"
        case .aiSDKBridge:
            return "\(configuredRouteCount) routes • \(modelSummary) • bridge-managed runtime"
        case .subscriptionCLI:
            return "\(configuredRouteCount) routes • \(modelSummary) • account CLI auth"
        case .apiKey:
            return "\(configuredRouteCount) routes • \(modelSummary) • Keychain API keys"
        case .localServer:
            return "\(configuredRouteCount) routes • \(modelSummary) • local server runtime"
        }
    }

    private var availability: ProviderModeGuideAvailability {
        switch kind {
        case .localServer:
            return ProviderModeGuideAvailability(
                title: "Always available",
                tone: .success,
                systemImage: "lock"
            )
        case .subscriptionCLI:
            return networkMode == .localOnly
                ? ProviderModeGuideAvailability(
                    title: "Blocked by privacy mode",
                    tone: .warning,
                    systemImage: "hand.raised"
                )
                : ProviderModeGuideAvailability(
                    title: "Allowed in current privacy mode",
                    tone: .info,
                    systemImage: "terminal"
                )
        case .apiKey:
            return networkMode == .allowCloudProviders
                ? ProviderModeGuideAvailability(
                    title: "Allowed in current privacy mode",
                    tone: .warning,
                    systemImage: "network"
                )
                : ProviderModeGuideAvailability(
                    title: "Blocked until cloud providers are allowed",
                    tone: .warning,
                    systemImage: "hand.raised"
                )
        case .compatibleEndpoint:
            let hasLocalRoutes = configuredProviders.contains { $0.runtimeBoundary == .localServer }
            let hasRemoteRoutes = configuredProviders.contains { $0.runtimeBoundary == .externalAPI }
            if networkMode == .allowCloudProviders {
                return ProviderModeGuideAvailability(
                    title: "Local and remote-compatible routes allowed",
                    tone: .info,
                    systemImage: "arrow.left.arrow.right"
                )
            }
            if hasLocalRoutes && hasRemoteRoutes {
                return ProviderModeGuideAvailability(
                    title: "Local routes allowed; remote routes blocked",
                    tone: .info,
                    systemImage: "arrow.left.arrow.right"
                )
            }
            if hasRemoteRoutes && !hasLocalRoutes {
                return ProviderModeGuideAvailability(
                    title: "Remote-compatible routes blocked",
                    tone: .warning,
                    systemImage: "hand.raised"
                )
            }
            return ProviderModeGuideAvailability(
                title: "Local-compatible routes allowed",
                tone: .success,
                systemImage: "lock"
            )
        case .aiSDKBridge:
            return networkMode == .allowCloudProviders
                ? ProviderModeGuideAvailability(
                    title: "Allowed in current privacy mode",
                    tone: .info,
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                : ProviderModeGuideAvailability(
                    title: "Blocked until cloud providers are allowed",
                    tone: .warning,
                    systemImage: "hand.raised"
                )
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kind.title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    FlannelStatusChip(
                        availability.title,
                        systemImage: availability.systemImage,
                        tone: availability.tone,
                        prominence: .tinted
                    )
                }

                Text(kind.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(routeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(configuredProviderSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(capabilitySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        "\(kind.title). \(availability.title). \(kind.detail) \(routeSummary). \(configuredProviderSummary)."
    }
}

private struct ProviderSettingsGroupHeader: View {
    var kind: ProviderSettingsGroupKind
    var count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label(kind.title, systemImage: kind.systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(kind.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title). \(count) configured. \(kind.detail)")
    }
}

private struct ProviderRoutingOverview: View {
    var activeProvider: ProviderConfiguration?
    var selectedProvider: ProviderConfiguration?
    var routingPolicy: ProviderRoutingPolicy
    var networkMode: SettingsNetworkAccess
    var lastDiscoveryResult: LocalProviderDiscoveryResult?
    var runnableProviderCount: Int

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                overviewLabel("Active", systemImage: "checkmark.circle")
                overviewValue(activeProviderSummary, detail: activeProviderDetail)
            }
            GridRow {
                overviewLabel("Selected", systemImage: "scope")
                overviewValue(selectedProviderSummary, detail: selectedProviderDetail)
            }
            GridRow {
                overviewLabel("Policy", systemImage: routingPolicy.icon)
                overviewValue(routingPolicy.title, detail: routingPolicy.detail)
            }
            GridRow {
                overviewLabel("Network", systemImage: networkMode.systemImage)
                overviewValue(networkMode.title, detail: networkMode.detail)
            }
            GridRow {
                overviewLabel("Discovery", systemImage: "dot.radiowaves.left.and.right")
                overviewValue(discoverySummary, detail: discoveryDetail)
            }
        }
        .font(.caption)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func overviewLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(minWidth: 82, alignment: .leading)
    }

    private func overviewValue(_ value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if let detail,
               !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var activeProviderSummary: String {
        activeProvider?.displayName ?? "None active"
    }

    private var activeProviderDetail: String? {
        guard let activeProvider else {
            return "No runnable provider currently satisfies setup, privacy, and transport checks."
        }
        return activeProvider.providerPickerRouteSummary
    }

    private var selectedProviderSummary: String {
        selectedProvider?.displayName ?? "No preferred provider"
    }

    private var selectedProviderDetail: String? {
        guard let selectedProvider else {
            return "Choosing a provider records the route without changing privacy gates."
        }
        if activeProvider?.id == selectedProvider.id {
            return "This selected provider is active. \(selectedProvider.providerPickerRouteSummary). \(runnableProviderCount) runnable provider\(runnableProviderCount == 1 ? "" : "s") available."
        }
        return "Selected but inactive until setup and privacy gates allow it. \(selectedProvider.providerPickerRouteSummary)."
    }

    private var discoverySummary: String {
        guard let lastDiscoveryResult else { return "Not run yet" }
        return "\(lastDiscoveryResult.providerKind.title) - \(lastDiscoveryResult.models.count) model\(lastDiscoveryResult.models.count == 1 ? "" : "s")"
    }

    private var discoveryDetail: String? {
        guard let lastDiscoveryResult else {
            return "Run discovery to hydrate Ollama and LM Studio model lists."
        }
        return "\(humanized(lastDiscoveryResult.status.rawValue)) at \(lastDiscoveryResult.discoveredAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func humanized(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private struct ProviderSetupSummary: View {
    var provider: ProviderConfiguration
    var report: ProviderSetupReport

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(provider.settingsSetupInstruction, systemImage: provider.kind.settingsSystemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(provider.settingsSetupInstruction)

            HStack(alignment: .top, spacing: 14) {
                setupFact(
                    provider.settingsRouteSummaryTitle,
                    detail: provider.settingsRouteSummaryDetail,
                    systemImage: provider.accessMode.settingsSystemImage,
                    style: AnyShapeStyle(.secondary)
                )
                setupFact(
                    provider.settingsCredentialSummary,
                    detail: provider.settingsCredentialDetail,
                    systemImage: provider.settingsCredentialSystemImage,
                    style: provider.settingsCredentialStyle
                )
                setupFact(
                    routingTitle,
                    detail: routingDetail,
                    systemImage: routingIcon,
                    style: routingStyle
                )
            }
        }
    }

    private func setupFact(
        _ title: String,
        detail: String,
        systemImage: String,
        style: AnyShapeStyle
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(style)
        }
        .labelStyle(.titleAndIcon)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }

    private var routingTitle: String {
        switch report.routingEligibility {
        case .eligible:
            "Privacy allowed"
        case .blockedByLocalOnlyMode:
            "Blocked by local-only"
        case .blockedByCloudPreference:
            "Blocked by cloud gate"
        }
    }

    private var routingDetail: String {
        switch report.routingEligibility {
        case .eligible:
            "Can route after setup passes."
        case .blockedByLocalOnlyMode:
            "Change Privacy to allow CLI or cloud."
        case .blockedByCloudPreference:
            "Enable cloud providers in Privacy."
        }
    }

    private var routingIcon: String {
        switch report.routingEligibility {
        case .eligible:
            "checkmark.shield"
        case .blockedByLocalOnlyMode, .blockedByCloudPreference:
            "lock.shield"
        }
    }

    private var routingStyle: AnyShapeStyle {
        switch report.routingEligibility {
        case .eligible:
            AnyShapeStyle(.green)
        case .blockedByLocalOnlyMode, .blockedByCloudPreference:
            AnyShapeStyle(.orange)
        }
    }
}

private struct ProviderSettingsStatusChip: Identifiable {
    var title: String
    var systemImage: String
    var tone: FlannelStatusTone
    var prominence: FlannelStatusChipProminence
    var detail: String?

    var id: String {
        "\(systemImage)-\(title)"
    }

    var accessibilityLabel: String {
        if let detail,
           !detail.isEmpty {
            return "\(title). \(detail)"
        }
        return title
    }
}

private struct ProviderSettingsNextStep {
    var title: String
    var detail: String
    var systemImage: String
    var tone: FlannelStatusTone
}

private struct ProviderSettingsChipStrip: View {
    var primaryChips: [ProviderSettingsStatusChip]
    var capabilityChips: [ProviderSettingsStatusChip]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            chipRows(primaryChips)

            if !capabilityChips.isEmpty {
                chipRows(capabilityChips)
            }
        }
    }

    private func chipRows(_ chips: [ProviderSettingsStatusChip]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(chipGroups(chips).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { chip in
                        FlannelStatusChip(
                            chip.title,
                            systemImage: chip.systemImage,
                            tone: chip.tone,
                            prominence: chip.prominence
                        )
                        .help(chip.detail ?? chip.title)
                        .accessibilityLabel(chip.accessibilityLabel)
                    }
                }
            }
        }
    }

    private func chipGroups(_ chips: [ProviderSettingsStatusChip]) -> [[ProviderSettingsStatusChip]] {
        stride(from: 0, to: chips.count, by: 3).map { startIndex in
            Array(chips[startIndex..<min(startIndex + 3, chips.count)])
        }
    }
}

private struct ProviderNextStepCallout: View {
    var step: ProviderSettingsNextStep

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.caption.weight(.semibold))
                Text(step.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: step.systemImage)
                .foregroundStyle(step.tone.color)
        }
        .labelStyle(.titleAndIcon)
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(step.tone.color.opacity(0.18), lineWidth: 0.5)
        }
    }
}

private struct ProviderSourceReferences: View {
    var references: [AIProviderSourceReference]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("References", systemImage: "book.pages")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(referenceRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        ForEach(row) { reference in
                            if let url = URL(string: reference.url) {
                                Link(destination: url) {
                                    Label(reference.label, systemImage: "arrow.up.right.square")
                                        .labelStyle(.titleAndIcon)
                                }
                                .font(.caption)
                                .help(reference.url)
                                .accessibilityHint("Opens \(reference.url)")
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var referenceRows: [[AIProviderSourceReference]] {
        stride(from: 0, to: references.count, by: 2).map { startIndex in
            Array(references[startIndex..<min(startIndex + 2, references.count)])
        }
    }
}

private struct ProviderSettingsRow: View {
    @Binding var provider: ProviderConfiguration
    var isPreferred: Bool
    var report: ProviderSetupReport
    @Binding var secretDraft: String
    var setupMessage: String?
    var readinessValidation: ProviderReadinessValidation?
    var isValidating: Bool
    var setPreferred: () -> Void
    var validate: () -> Void
    var duplicate: () -> Void
    var delete: () -> Void
    var canDelete: Bool
    var saveSecret: () -> Void
    var deleteSecret: () -> Void
    var invalidateReadiness: () -> Void
    var persist: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: provider.kind.settingsSystemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text(provider.displayName)
                        .font(.headline)
                    Text(provider.settingsBoundarySubtitle(modelSummary: modelSummary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(provider.modeBoundaryDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .help(provider.modeBoundaryDetail)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(provider.settingsBoundaryAccessibilityLabel(modelSummary: modelSummary))
                .accessibilityHint(provider.modeBoundaryDetail)

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Toggle("Enabled", isOn: enabledBinding)
                    Button(isPreferred ? "In Use" : "Use for Chat", action: setPreferred)
                        .disabled(isPreferred || isValidating)
                    Button(action: validate) {
                        if isValidating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Check Readiness", systemImage: "checkmark.seal")
                        }
                    }
                    .disabled(isValidating)

                    Menu {
                        Button {
                            duplicate()
                        } label: {
                            Label("Duplicate Route", systemImage: "plus.square.on.square")
                        }

                        Button(role: .destructive) {
                            delete()
                        } label: {
                            Label("Delete Route", systemImage: "trash")
                        }
                        .disabled(!canDelete)
                    } label: {
                        Label("Route Actions", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .help("Route actions")
                }
            }

            ProviderSettingsChipStrip(
                primaryChips: primaryStatusChips,
                capabilityChips: capabilityStatusChips
            )

            ProviderNextStepCallout(step: nextStep)

            ProviderSetupSummary(provider: provider, report: report)

            if !sourceReferences.isEmpty {
                ProviderSourceReferences(references: sourceReferences)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Name")
                        .foregroundStyle(.secondary)
                    TextField("Route name", text: displayNameBinding)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text(endpointLabel)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        TextField(provider.settingsEndpointPlaceholder, text: endpointBinding)
                            .textFieldStyle(.roundedBorder)
                        if let endpointHelp {
                            Text(endpointHelp)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let commandHelp {
                            Text(commandHelp)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                GridRow {
                    Text("Model")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(provider.settingsModelPlaceholder, text: modelBinding)
                            .textFieldStyle(.roundedBorder)

                        if !knownModels.isEmpty {
                            Picker("Known models", selection: modelBinding) {
                                if !knownModels.contains(provider.modelIdentifier),
                                   !provider.modelIdentifier.isEmpty {
                                    Text(provider.modelIdentifier).tag(provider.modelIdentifier)
                                }
                                ForEach(knownModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                        }
                    }
                }

                GridRow {
                    Text("Request")
                        .foregroundStyle(.secondary)
                    ProviderRequestOverridesEditor(
                        provider: $provider,
                        invalidateReadiness: invalidateReadiness,
                        persist: persist
                    )
                }

                if showsSecretConfiguration {
                    GridRow {
                        Text("Credential")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            TextField(report.canonicalSecretReference?.rawValue ?? "service:account", text: secretReferenceBinding)
                                .textFieldStyle(.roundedBorder)
                            Text(provider.settingsSecretReferenceHelp)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GridRow {
                        Text("API key")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                SecureField(provider.settingsAPIKeyPlaceholder, text: $secretDraft)
                                    .textFieldStyle(.roundedBorder)
                                Button(action: saveSecret) {
                                    Label("Save Key", systemImage: "key.fill")
                                }
                                    .disabled(secretDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button(role: .destructive, action: deleteSecret) {
                                    Label("Remove Key", systemImage: "key.slash")
                                }
                                    .disabled(provider.secretReference == nil)
                            }

                            Label(secretStatusText, systemImage: secretStatusIcon)
                                .font(.caption)
                                .foregroundStyle(secretStatusStyle)
                        }
                    }
                }

                GridRow {
                    Text("Status")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(statusStyle)
                        if let setupMessage {
                            SettingsInlineNotice(
                                message: setupMessage,
                                tone: settingsNoticeTone(for: setupMessage, isLoading: isValidating)
                            )
                        } else if let lastError = provider.lastErrorMessage {
                            SettingsInlineNotice(message: lastError, tone: .error)
                        }
                    }
                }
            }

            if !report.diagnostics.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(report.diagnostics) { diagnostic in
                        Label(diagnostic.message, systemImage: diagnosticIcon(for: diagnostic.severity))
                            .font(.caption)
                            .foregroundStyle(diagnosticStyle(for: diagnostic.severity))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let readinessValidation {
                ProviderReadinessSummary(provider: provider, validation: readinessValidation)
            }
        }
        .padding(.vertical, 8)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { provider.isEnabled },
            set: {
                provider.isEnabled = $0
                provider.connectionStatus = .disconnected
                provider.lastErrorMessage = nil
                invalidateReadiness()
                persist()
            }
        )
    }

    private var displayNameBinding: Binding<String> {
        Binding(
            get: { provider.displayName },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                provider.displayName = trimmed.isEmpty ? provider.modeBoundaryTitle : trimmed
                persist()
            }
        )
    }

    private var endpointBinding: Binding<String> {
        Binding(
            get: { provider.endpoint },
            set: {
                provider.endpoint = $0
                provider.connectionStatus = .disconnected
                provider.lastErrorMessage = nil
                invalidateReadiness()
                persist()
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { provider.modelIdentifier },
            set: {
                provider.modelIdentifier = $0
                provider.connectionStatus = .disconnected
                provider.lastErrorMessage = nil
                invalidateReadiness()
                persist()
            }
        )
    }

    private var secretReferenceBinding: Binding<String> {
        Binding(
            get: { provider.secretReference ?? "" },
            set: {
                provider.secretReference = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                provider.connectionStatus = .disconnected
                provider.lastErrorMessage = nil
                invalidateReadiness()
                persist()
            }
        )
    }

    private var endpointLabel: String {
        switch provider.accessMode {
        case .subscriptionCLI:
            "CLI command"
        case .localServer:
            "Server endpoint"
        case .apiKey, .openAICompatible, .anthropicCompatible:
            "API endpoint"
        case .aiSDKBridge:
            "Bridge endpoint"
        }
    }

    private var endpointHelp: String? {
        provider.accessMode == .subscriptionCLI ? nil : provider.settingsEndpointHelp
    }

    private var commandHelp: String? {
        guard provider.accessMode == .subscriptionCLI else { return nil }
        switch provider.kind {
        case .chatGPTCLI:
            return "Account CLI route. Recommended: `codex exec --json -`. The `-` tells Codex to read Flannel's rendered prompt from stdin while `--json` emits JSONL events. ChatGPT sign-in or Codex API-key auth stays inside the CLI. Placeholders like `{prompt}`, `{last_user_message}`, `{model}`, and legacy `{stdin}` are also supported. Pipes and shell expansion are rejected."
        case .claudeCodeCLI:
            return "Account CLI route. Recommended: `claude -p --output-format stream-json --verbose`. Flannel decodes Claude JSON or stream-json output through the local Claude Code login. This does not read an Anthropic Console API key from this row. Interactive Claude sessions are not launched from chat."
        default:
            return "Use a direct argv-style account CLI command. Shell syntax, pipes, redirects, and command substitution are rejected."
        }
    }

    private var modelSummary: String {
        provider.modelIdentifier.isEmpty ? "No model selected" : provider.modelIdentifier
    }

    private var knownModels: [String] {
        Array(Set(provider.availableModels)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var sourceReferences: [AIProviderSourceReference] {
        AIKnownProviderCatalog.entry(for: provider.kind)?.sourceReferences ?? []
    }

    private var showsSecretConfiguration: Bool {
        provider.settingsShowsKeychainSecretControl
    }

    private var primaryStatusChips: [ProviderSettingsStatusChip] {
        var chips = [
            routeModeChip,
            runtimeBoundaryChip,
            credentialChip,
            modelChip,
            readinessChip,
            preferenceChip
        ]

        if !provider.staleDiscoveredModelNames.isEmpty {
            chips.append(staleDiscoveryChip)
        }

        return chips
    }

    private var capabilityStatusChips: [ProviderSettingsStatusChip] {
        let sortedCapabilities = Array(Set(provider.capabilities)).sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        let visibleCapabilities = sortedCapabilities.prefix(5).map { capability in
            ProviderSettingsStatusChip(
                title: capability.title,
                systemImage: capability.settingsSystemImage,
                tone: capability.settingsTone,
                prominence: .subtle
            )
        }
        let extraCount = max(0, sortedCapabilities.count - visibleCapabilities.count)
        guard extraCount > 0 else { return Array(visibleCapabilities) }

        return Array(visibleCapabilities) + [
            ProviderSettingsStatusChip(
                title: "+\(extraCount) more",
                systemImage: "ellipsis",
                tone: .neutral,
                prominence: .subtle
            )
        ]
    }

    private var routeModeChip: ProviderSettingsStatusChip {
        ProviderSettingsStatusChip(
            title: provider.settingsRouteChipTitle,
            systemImage: provider.accessMode.settingsSystemImage,
            tone: provider.settingsRouteChipTone,
            prominence: .tinted,
            detail: provider.settingsRouteChipDetail
        )
    }

    private var runtimeBoundaryChip: ProviderSettingsStatusChip {
        switch report.routingEligibility {
        case .eligible:
            ProviderSettingsStatusChip(
                title: provider.runtimeBoundary.title,
                systemImage: provider.runtimeBoundary.systemImage,
                tone: provider.runtimeBoundary.settingsTone,
                prominence: .subtle,
                detail: provider.runtimeBoundary.detail
            )
        case .blockedByLocalOnlyMode, .blockedByCloudPreference:
            ProviderSettingsStatusChip(
                title: "Privacy blocked",
                systemImage: "lock.shield",
                tone: .warning,
                prominence: .tinted
            )
        }
    }

    private var credentialChip: ProviderSettingsStatusChip {
        ProviderSettingsStatusChip(
            title: provider.settingsCredentialSummary,
            systemImage: provider.settingsCredentialSystemImage,
            tone: provider.settingsCredentialTone,
            prominence: provider.secretReference == nil && provider.settingsRequiresKeychainSecret ? .tinted : .subtle,
            detail: provider.settingsCredentialDetail
        )
    }

    private var modelChip: ProviderSettingsStatusChip {
        if report.normalizedModelIdentifier.isEmpty {
            return ProviderSettingsStatusChip(
                title: "Model needed",
                systemImage: "cpu",
                tone: .warning,
                prominence: .tinted
            )
        }

        if !knownModels.isEmpty {
            return ProviderSettingsStatusChip(
                title: "\(knownModels.count) known model\(knownModels.count == 1 ? "" : "s")",
                systemImage: "square.stack.3d.up",
                tone: .info,
                prominence: .subtle
            )
        }

        return ProviderSettingsStatusChip(
            title: "Model set",
            systemImage: "cpu",
            tone: .success,
            prominence: .subtle
        )
    }

    private var staleDiscoveryChip: ProviderSettingsStatusChip {
        ProviderSettingsStatusChip(
            title: "\(provider.staleDiscoveredModelNames.count) stale local",
            systemImage: "exclamationmark.triangle",
            tone: .warning,
            prominence: .tinted
        )
    }

    private var readinessChip: ProviderSettingsStatusChip {
        if isValidating {
            return ProviderSettingsStatusChip(
                title: "Checking",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .info,
                prominence: .tinted
            )
        }

        if let readinessValidation {
            return ProviderSettingsStatusChip(
                title: readinessValidation.isReady ? "Live ready" : "Needs check",
                systemImage: readinessValidation.isReady ? "checkmark.circle" : "exclamationmark.triangle",
                tone: readinessValidation.isReady ? .success : .warning,
                prominence: .tinted
            )
        }

        switch provider.connectionStatus {
        case .ready:
            return ProviderSettingsStatusChip(
                title: "Ready",
                systemImage: "checkmark.circle",
                tone: .success,
                prominence: .tinted
            )
        case .needsAttention, .rateLimited:
            return ProviderSettingsStatusChip(
                title: humanized(provider.connectionStatus.rawValue),
                systemImage: "exclamationmark.triangle",
                tone: .warning,
                prominence: .tinted
            )
        case .syncing:
            return ProviderSettingsStatusChip(
                title: "Syncing",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .info,
                prominence: .tinted
            )
        case .disconnected:
            return ProviderSettingsStatusChip(
                title: ProviderSettingsMessaging.disconnectedChipTitle(for: provider),
                systemImage: "circle.dashed",
                tone: .neutral,
                prominence: .subtle
            )
        }
    }

    private var preferenceChip: ProviderSettingsStatusChip {
        if !provider.isEnabled {
            return ProviderSettingsStatusChip(
                title: "Disabled",
                systemImage: "power",
                tone: .neutral,
                prominence: .subtle
            )
        }

        return ProviderSettingsStatusChip(
            title: isPreferred ? "Preferred" : "Available",
            systemImage: isPreferred ? "pin.fill" : "checkmark",
            tone: isPreferred ? .accent : .success,
            prominence: isPreferred ? .tinted : .subtle
        )
    }

    private var nextStep: ProviderSettingsNextStep {
        if !provider.isEnabled {
            return ProviderSettingsNextStep(
                title: "Enable this route when it should be considered",
                detail: "Disabled providers stay configured but are skipped by chat routing.",
                systemImage: "power",
                tone: .neutral
            )
        }

        if isValidating {
            return ProviderSettingsNextStep(
                title: "Checking readiness",
                detail: "Flannel is validating the setup fields and the selected model where this route supports live checks.",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .info
            )
        }

        switch report.routingEligibility {
        case .eligible:
            break
        case .blockedByLocalOnlyMode:
            return ProviderSettingsNextStep(
                title: "Privacy mode blocks this route",
                detail: "Switch Privacy from Local models only before CLI subscriptions, cloud APIs, or bridge routes can become active.",
                systemImage: "lock.shield",
                tone: .warning
            )
        case .blockedByCloudPreference:
            return ProviderSettingsNextStep(
                title: "Cloud providers are gated off",
                detail: "Choose Allow cloud providers in Privacy before this BYOK API route can send requests.",
                systemImage: "network.badge.shield.half.filled",
                tone: .warning
            )
        }

        if let blockingDiagnostic = report.diagnostics.first(where: \.isBlocking) {
            return nextStep(for: blockingDiagnostic)
        }

        if let readinessValidation {
            if readinessValidation.isReady {
                return ProviderSettingsNextStep(
                    title: isPreferred ? "Ready for chat" : "Ready; make it preferred when you want it used",
                    detail: isPreferred ? "This provider can be selected by the current routing policy." : "Use for Chat records this provider as the preferred route without changing transport behavior.",
                    systemImage: "checkmark.seal",
                    tone: .success
                )
            }

            if !readinessValidation.selectedModelIsAvailable {
                return ProviderSettingsNextStep(
                    title: "Select an available model",
                    detail: "Choose one of the returned models, or run local discovery before checking readiness again.",
                    systemImage: "square.stack.3d.up",
                    tone: .warning
                )
            }
        }

        if provider.connectionStatus == .ready {
            return ProviderSettingsNextStep(
                title: isPreferred ? "Ready for chat" : "Ready; make it preferred when you want it used",
                detail: isPreferred ? "The current routing policy can use this configured route." : "Use for Chat records this provider as the preferred route.",
                systemImage: "checkmark.seal",
                tone: .success
            )
        }

        return defaultNextStep
    }

    private var defaultNextStep: ProviderSettingsNextStep {
        switch provider.accessMode {
        case .localServer:
            return ProviderSettingsNextStep(
                title: "Start locally, then discover models",
                detail: "Launch \(provider.kind.title), run Local Discovery, choose a model, then check readiness.",
                systemImage: "server.rack",
                tone: .info
            )
        case .subscriptionCLI:
            return ProviderSettingsNextStep(
                title: "Confirm the CLI is signed in",
                detail: "Use the recommended command shape, make sure the CLI account works in Terminal, then check readiness. Do not paste a provider API key into this route.",
                systemImage: "terminal",
                tone: .info
            )
        case .apiKey, .anthropicCompatible:
            return ProviderSettingsNextStep(
                title: "Finish API-key setup",
                detail: "Save the provider API key in Keychain when required, confirm the model id, then check readiness. CLI account sign-in does not satisfy this route.",
                systemImage: "key",
                tone: .info
            )
        case .openAICompatible:
            return ProviderSettingsNextStep(
                title: "Confirm endpoint and key policy",
                detail: "Confirm whether the compatible endpoint is local or remote, save an API key only when that service requires one, then check readiness.",
                systemImage: "arrow.left.arrow.right",
                tone: .info
            )
        case .aiSDKBridge:
            return ProviderSettingsNextStep(
                title: "Start the local bridge",
                detail: "Run the bridge service, confirm the endpoint and model id, then check readiness.",
                systemImage: "point.3.connected.trianglepath.dotted",
                tone: .info
            )
        }
    }

    private func nextStep(for diagnostic: ProviderSetupDiagnostic) -> ProviderSettingsNextStep {
        switch diagnostic.code {
        case .missingEndpoint, .invalidEndpoint, .insecureRemoteEndpoint:
            return ProviderSettingsNextStep(
                title: "Fix the \(endpointLabel.lowercased())",
                detail: provider.accessMode == .subscriptionCLI ? "Enter a direct command without shell expansion, pipes, or redirects." : "Enter a valid base URL for this route, using HTTPS for remote APIs.",
                systemImage: provider.accessMode == .subscriptionCLI ? "terminal" : "link",
                tone: .warning
            )
        case .missingModelIdentifier, .modelUnavailable:
            return ProviderSettingsNextStep(
                title: provider.accessMode == .localServer ? "Choose a discovered model" : "Enter a model id",
                detail: provider.accessMode == .localServer ? "Run Local Discovery, then choose one of the installed chat models." : "Use a model id supported by this provider before checking readiness.",
                systemImage: "cpu",
                tone: .warning
            )
        case .missingKeychainReference, .keychainReferenceShouldBeCanonical:
            return ProviderSettingsNextStep(
                title: "Save the provider key in Keychain",
                detail: "Paste the BYOK API key here and save it; CLI account sign-in does not satisfy this API route.",
                systemImage: "key",
                tone: .warning
            )
        case .missingCLICommand, .invalidCLICommand, .missingCLIExecutable, .claudePrintModeRequired, .cliStatusCheckFailed, .cliSmokeProbeFailed:
            return ProviderSettingsNextStep(
                title: diagnostic.code == .cliSmokeProbeFailed || diagnostic.code == .cliStatusCheckFailed ? "Sign in or repair the CLI" : "Repair the local CLI command",
                detail: diagnostic.code == .cliSmokeProbeFailed || diagnostic.code == .cliStatusCheckFailed
                    ? "Run the same command in Terminal, confirm the CLI account is signed in, then check readiness again."
                    : "Install and sign in to the CLI, use the recommended print/JSON command, then check readiness.",
                systemImage: "terminal",
                tone: .warning
            )
        case .blockedByLocalOnlyMode, .blockedByCloudPreference:
            return defaultNextStep
        case .providerUnavailable, .providerReturnedNoModels:
            return ProviderSettingsNextStep(
                title: "Start the provider and refresh",
                detail: "Start the local server or bridge, then run discovery or readiness again.",
                systemImage: "arrow.clockwise",
                tone: .warning
            )
        }
    }

    private var secretStatusText: String {
        if provider.secretReference != nil {
            return "\(provider.settingsAPIKeyName) saved in Keychain"
        }

        return provider.settingsRequiresKeychainSecret
            ? "No \(provider.settingsAPIKeyName) saved"
            : "Optional \(provider.settingsAPIKeyName) not saved"
    }

    private var secretStatusIcon: String {
        provider.secretReference == nil ? "key.slash" : "key.fill"
    }

    private var secretStatusStyle: AnyShapeStyle {
        if provider.secretReference != nil {
            return AnyShapeStyle(.green)
        }
        return provider.settingsRequiresKeychainSecret ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary)
    }

    private var statusText: String {
        ProviderSettingsMessaging.statusText(for: provider)
    }

    private var statusStyle: AnyShapeStyle {
        switch provider.connectionStatus {
        case .ready:
            AnyShapeStyle(.green)
        case .needsAttention, .rateLimited:
            AnyShapeStyle(.orange)
        case .syncing:
            AnyShapeStyle(.blue)
        case .disconnected:
            AnyShapeStyle(.secondary)
        }
    }

    private func diagnosticIcon(for severity: ProviderSetupDiagnosticSeverity) -> String {
        switch severity {
        case .error:
            "exclamationmark.triangle.fill"
        case .warning:
            "exclamationmark.circle"
        case .info:
            "info.circle"
        }
    }

    private func diagnosticStyle(for severity: ProviderSetupDiagnosticSeverity) -> AnyShapeStyle {
        switch severity {
        case .error:
            AnyShapeStyle(.red)
        case .warning:
            AnyShapeStyle(.orange)
        case .info:
            AnyShapeStyle(.secondary)
        }
    }

    private func humanized(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private struct ProviderRequestOverridesEditor: View {
    @Binding var provider: ProviderConfiguration
    var invalidateReadiness: () -> Void
    var persist: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            LabeledContent("Temperature") {
                HStack(spacing: 8) {
                    Slider(value: temperatureBinding, in: 0 ... 2, step: 0.05)
                    Text(provider.temperature.formatted(.number.precision(.fractionLength(2))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            LabeledContent("Top P") {
                HStack(spacing: 8) {
                    Slider(value: topPBinding, in: 0 ... 1, step: 0.05)
                    Text(provider.requestOverrides.topP?.formatted(.number.precision(.fractionLength(2))) ?? "Default")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                    Button("Clear") {
                        provider.requestOverrides.topP = nil
                        markChanged()
                    }
                    .disabled(provider.requestOverrides.topP == nil)
                }
            }

            HStack(spacing: 10) {
                labeledTextField("Max tokens", text: optionalIntBinding(\.maxOutputTokens), width: 92)
                labeledTextField("Seed", text: optionalIntBinding(\.seed), width: 78)

                if supportsTopK {
                    labeledTextField("Top K", text: optionalIntBinding(\.topK), width: 78)
                }
            }

            if supportsPenaltyControls || supportsRepeatPenalty {
                HStack(spacing: 10) {
                    if supportsPenaltyControls {
                        labeledTextField("Presence", text: optionalDoubleBinding(\.presencePenalty), width: 78)
                        labeledTextField("Frequency", text: optionalDoubleBinding(\.frequencyPenalty), width: 78)
                    }

                    if supportsRepeatPenalty {
                        labeledTextField("Repeat", text: optionalDoubleBinding(\.repeatPenalty), width: 78)
                    }
                }
            }

            if supportsReasoningEffort {
                Picker("Reasoning", selection: reasoningEffortBinding) {
                    Text("Default").tag(nil as ProviderReasoningEffort?)
                    ForEach(ProviderReasoningEffort.allCases) { effort in
                        Text(effort.title).tag(Optional(effort))
                    }
                }
                .pickerStyle(.menu)
            }

            TextField("Stop sequences, comma separated", text: stopSequencesBinding)
                .textFieldStyle(.roundedBorder)
        }
        .font(.caption)
    }

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { provider.temperature },
            set: {
                provider.temperature = $0
                markChanged()
            }
        )
    }

    private var topPBinding: Binding<Double> {
        Binding(
            get: { provider.requestOverrides.topP ?? 1 },
            set: {
                provider.requestOverrides.topP = min(max($0, 0), 1)
                markChanged()
            }
        )
    }

    private var reasoningEffortBinding: Binding<ProviderReasoningEffort?> {
        Binding(
            get: { provider.requestOverrides.reasoningEffort },
            set: {
                provider.requestOverrides.reasoningEffort = $0
                markChanged()
            }
        )
    }

    private var stopSequencesBinding: Binding<String> {
        Binding(
            get: {
                provider.requestOverrides.stopSequences.joined(separator: ", ")
            },
            set: { rawValue in
                provider.requestOverrides.stopSequences = rawValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                markChanged()
            }
        )
    }

    private var supportsTopK: Bool {
        provider.kind == .ollama || provider.kind == .lmStudio || provider.kind == .anthropic
    }

    private var supportsRepeatPenalty: Bool {
        provider.kind == .ollama || provider.kind == .lmStudio
    }

    private var supportsPenaltyControls: Bool {
        switch provider.kind {
        case .lmStudio, .customOpenAICompatible, .openAI, .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            true
        case .ollama, .anthropic, .chatGPTCLI, .claudeCodeCLI, .vercelAISDKBridge:
            false
        }
    }

    private var supportsReasoningEffort: Bool {
        provider.kind == .openAI
    }

    private func labeledTextField(_ title: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .foregroundStyle(.secondary)
            TextField("Default", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private func optionalIntBinding(_ keyPath: WritableKeyPath<ProviderRequestOverrides, Int?>) -> Binding<String> {
        Binding(
            get: {
                provider.requestOverrides[keyPath: keyPath].map(String.init) ?? ""
            },
            set: { rawValue in
                let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                provider.requestOverrides[keyPath: keyPath] = trimmed.isEmpty ? nil : Int(trimmed)
                markChanged()
            }
        )
    }

    private func optionalDoubleBinding(_ keyPath: WritableKeyPath<ProviderRequestOverrides, Double?>) -> Binding<String> {
        Binding(
            get: {
                provider.requestOverrides[keyPath: keyPath].map {
                    $0.formatted(.number.precision(.fractionLength(0 ... 3)))
                } ?? ""
            },
            set: { rawValue in
                let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                provider.requestOverrides[keyPath: keyPath] = trimmed.isEmpty ? nil : Double(trimmed)
                markChanged()
            }
        )
    }

    private func markChanged() {
        provider.connectionStatus = .disconnected
        provider.lastErrorMessage = nil
        invalidateReadiness()
        persist()
    }
}

private struct ProviderReadinessSummary: View {
    var provider: ProviderConfiguration
    var validation: ProviderReadinessValidation

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(summaryText, systemImage: validation.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(validation.isReady ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                .fixedSize(horizontal: false, vertical: true)

            if let modelListSummary {
                Text(modelListSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var summaryText: String {
        ProviderSettingsMessaging.readinessSummary(for: provider, validation: validation)
    }

    private var modelListSummary: String? {
        ProviderSettingsMessaging.modelListSummary(for: validation)
    }
}

private extension ProviderConfiguration {
    var settingsSetupInstruction: String {
        switch kind {
        case .openAI:
            "API-key route for the OpenAI Platform API. ChatGPT/Codex CLI access is configured as a separate local CLI route."
        case .chatGPTCLI:
            "Account CLI route for ChatGPT/Codex. Flannel runs the configured local command; ChatGPT plan sign-in or Codex API-key auth stays inside that CLI."
        case .anthropic:
            "API-key route for the Anthropic API. Claude Code account access belongs to Claude Code CLI, not this API-key route."
        case .claudeCodeCLI:
            "Account CLI route for Claude Code. Flannel runs Claude Code print mode through a local authenticated install."
        case .ollama:
            "Local Ollama server route. No API key is required; start Ollama and run local discovery to hydrate models."
        case .lmStudio:
            "Local LM Studio server route. No API key is required; start the LM Studio local server before routing chat."
        case .gemini:
            "API-key route for Google Gemini using the configured OpenAI-compatible Gemini endpoint."
        case .xAI:
            "API-key route for xAI Grok models through the configured xAI API endpoint."
        case .mistral:
            "API-key route through the configured Mistral API endpoint."
        case .groq:
            "API-key route for hosted Groq models through the configured Groq endpoint."
        case .openRouter:
            "API-key route through OpenRouter. Model identifiers usually include the upstream provider prefix."
        case .perplexity:
            "API-key route for Perplexity chat and search-capable models."
        case .customOpenAICompatible:
            "Custom OpenAI-compatible route. Use the provider's base URL and key requirements, then validate before enabling."
        case .vercelAISDKBridge:
            "Local bridge route. A separate localhost service must be running; this row does not configure cloud keys directly."
        }
    }

    var settingsRouteSummaryTitle: String {
        switch accessMode {
        case .localServer:
            "Local server route"
        case .subscriptionCLI:
            "Account CLI route"
        case .apiKey:
            "API-key route"
        case .openAICompatible:
            "OpenAI-compatible route"
        case .anthropicCompatible:
            "Anthropic-compatible route"
        case .aiSDKBridge:
            "Local bridge route"
        }
    }

    var settingsRouteSummaryDetail: String {
        switch accessMode {
        case .localServer:
            "Uses a running local model server"
        case .subscriptionCLI:
            "Uses a signed-in local command"
        case .apiKey:
            "Uses a Keychain API key"
        case .openAICompatible:
            runtimeBoundary == .localServer
                ? "Uses a local compatible endpoint"
                : "Uses a remote compatible endpoint"
        case .anthropicCompatible:
            "Uses an Anthropic-compatible endpoint"
        case .aiSDKBridge:
            "Uses a local bridge service"
        }
    }

    func settingsBoundarySubtitle(modelSummary: String) -> String {
        "\(settingsRouteSummaryTitle) - \(runtimeBoundary.title) - \(modelSummary)"
    }

    func settingsBoundaryAccessibilityLabel(modelSummary: String) -> String {
        "\(displayName). \(settingsRouteSummaryTitle). \(runtimeBoundary.title). Model: \(modelSummary). \(settingsCredentialSummary)."
    }

    var settingsEndpointPlaceholder: String {
        switch kind {
        case .ollama:
            "http://localhost:11434"
        case .lmStudio:
            "http://localhost:1234"
        case .openAI:
            "https://api.openai.com/v1"
        case .anthropic:
            "https://api.anthropic.com"
        case .gemini:
            "https://generativelanguage.googleapis.com/v1beta/openai"
        case .xAI:
            "https://api.x.ai/v1"
        case .mistral:
            "https://api.mistral.ai/v1"
        case .groq:
            "https://api.groq.com/openai/v1"
        case .openRouter:
            "https://openrouter.ai/api/v1"
        case .perplexity:
            "https://api.perplexity.ai"
        case .customOpenAICompatible:
            "https://provider.example.com/v1"
        case .chatGPTCLI:
            "codex exec --json -"
        case .claudeCodeCLI:
            "claude -p --output-format stream-json --verbose"
        case .vercelAISDKBridge:
            "http://localhost:4177"
        }
    }

    var settingsEndpointHelp: String? {
        switch kind {
        case .ollama:
            "Local server route. Use the loopback Ollama server; no API key or account sign-in is read from this row."
        case .lmStudio:
            "Local server route. Use LM Studio's local server endpoint; start the server in LM Studio before validating."
        case .openAI:
            "API-key route. Use the OpenAI Platform API base URL. This is separate from ChatGPT/Codex CLI access."
        case .anthropic:
            "API-key route. Use the Anthropic API base URL. This is separate from Claude Code account access."
        case .gemini:
            "API-key route. Use Gemini's OpenAI-compatible endpoint when routing through the OpenAI-shaped transport."
        case .xAI:
            "API-key route. Use xAI's OpenAI-compatible API base URL for Grok models."
        case .mistral:
            "API-key route. Use Mistral's API base URL for Mistral-hosted models."
        case .groq:
            "API-key route. Use Groq's OpenAI-compatible base URL for Groq-hosted model ids."
        case .openRouter:
            "API-key route. Use OpenRouter's API base URL. The model id normally includes an upstream provider prefix."
        case .perplexity:
            "API-key route. Use Perplexity's API base URL for supported Perplexity model ids."
        case .customOpenAICompatible:
            "OpenAI-compatible route. Local endpoints can stay HTTP; remote endpoints should use HTTPS and follow the provider's key policy."
        case .chatGPTCLI, .claudeCodeCLI:
            nil
        case .vercelAISDKBridge:
            "Local bridge route. Use the local bridge URL after starting the separate bridge service."
        }
    }

    var settingsModelPlaceholder: String {
        switch kind {
        case .ollama:
            "llama3.1, qwen3:14b, nomic-embed-text"
        case .lmStudio:
            "Loaded LM Studio model id"
        case .openAI:
            "OpenAI model id"
        case .anthropic:
            "Claude model id"
        case .gemini:
            "Gemini model id"
        case .xAI:
            "Grok model id"
        case .mistral:
            "Mistral model id"
        case .groq:
            "Groq model id"
        case .openRouter:
            "provider/model id"
        case .perplexity:
            "Perplexity model id"
        case .customOpenAICompatible:
            "OpenAI-compatible model id"
        case .chatGPTCLI:
            "CLI model label or {model} value"
        case .claudeCodeCLI:
            "Claude Code model label or {model} value"
        case .vercelAISDKBridge:
            "Bridge model id"
        }
    }

    var settingsAPIKeyName: String {
        switch kind {
        case .openAI:
            "OpenAI API key"
        case .anthropic:
            "Anthropic API key"
        case .gemini:
            "Gemini API key"
        case .xAI:
            "xAI API key"
        case .mistral:
            "Mistral API key"
        case .groq:
            "Groq API key"
        case .openRouter:
            "OpenRouter API key"
        case .perplexity:
            "Perplexity API key"
        case .customOpenAICompatible:
            "provider API key"
        case .ollama, .lmStudio, .chatGPTCLI, .claudeCodeCLI, .vercelAISDKBridge:
            "API key"
        }
    }

    var settingsAPIKeyPlaceholder: String {
        "Paste \(settingsAPIKeyName) to store in Keychain"
    }

    var settingsSecretReferenceHelp: String {
        switch kind {
        case .openAI:
            "Save an OpenAI Platform API key here. ChatGPT/Codex CLI auth belongs to the ChatGPT/Codex CLI provider."
        case .anthropic:
            "Save an Anthropic Console API key here. Claude Code account sign-in belongs to the Claude Code CLI provider."
        case .gemini:
            "Save a Gemini API key here, even though this route uses an OpenAI-compatible endpoint."
        case .openRouter:
            "Save an OpenRouter key here; upstream provider accounts are managed by OpenRouter, not by this row."
        case .customOpenAICompatible:
            "Use the provider's required key. Leave only the canonical Keychain reference after saving."
        case .xAI, .mistral, .groq, .perplexity:
            "Save this provider's API key in Keychain before allowing external requests."
        case .ollama, .lmStudio, .chatGPTCLI, .claudeCodeCLI, .vercelAISDKBridge:
            "This route does not normally store a provider API key in this row."
        }
    }

    var settingsCredentialSummary: String {
        if settingsRequiresKeychainSecret {
            return secretReference == nil ? "API key missing" : "API key saved"
        }
        if settingsShowsKeychainSecretControl {
            return secretReference == nil ? "Optional API key" : "API key saved"
        }

        switch accessMode {
        case .localServer:
            return "No API key used"
        case .subscriptionCLI:
            return "Account CLI auth"
        case .aiSDKBridge:
            return "Bridge-owned credentials"
        case .apiKey, .openAICompatible, .anthropicCompatible:
            return "No key required"
        }
    }

    var settingsCredentialDetail: String {
        if settingsRequiresKeychainSecret {
            return "\(settingsAPIKeyName) in Keychain"
        }
        if settingsShowsKeychainSecretControl {
            return secretReference == nil ? "Provider key optional" : "\(settingsAPIKeyName) in Keychain"
        }

        switch accessMode {
        case .localServer:
            return "Start the local server and select a model"
        case .subscriptionCLI:
            return "Use the account already signed in to the local CLI"
        case .aiSDKBridge:
            return "Configured by the local bridge service"
        case .apiKey, .openAICompatible, .anthropicCompatible:
            return "Provider policy"
        }
    }

    var settingsCredentialSystemImage: String {
        if settingsRequiresKeychainSecret {
            return secretReference == nil ? "key.slash" : "key.fill"
        }
        if settingsShowsKeychainSecretControl {
            return secretReference == nil ? "key" : "key.fill"
        }

        switch accessMode {
        case .localServer:
            return "lock"
        case .subscriptionCLI:
            return "person.crop.circle.badge.checkmark"
        case .aiSDKBridge:
            return "point.3.connected.trianglepath.dotted"
        case .apiKey, .openAICompatible, .anthropicCompatible:
            return "key"
        }
    }

    var settingsCredentialStyle: AnyShapeStyle {
        if settingsRequiresKeychainSecret {
            return secretReference == nil ? AnyShapeStyle(.orange) : AnyShapeStyle(.green)
        }
        if settingsShowsKeychainSecretControl, secretReference != nil {
            return AnyShapeStyle(.green)
        }
        return AnyShapeStyle(.secondary)
    }

    var settingsCredentialTone: FlannelStatusTone {
        if settingsRequiresKeychainSecret {
            return secretReference == nil ? .warning : .success
        }
        if settingsShowsKeychainSecretControl, secretReference != nil {
            return .success
        }

        switch accessMode {
        case .localServer:
            return .success
        case .subscriptionCLI, .aiSDKBridge:
            return .info
        case .apiKey, .openAICompatible, .anthropicCompatible:
            return .neutral
        }
    }

    var settingsRequiresKeychainSecret: Bool {
        accessMode == .apiKey || accessMode == .anthropicCompatible
    }

    var settingsShowsKeychainSecretControl: Bool {
        settingsRequiresKeychainSecret
            || accessMode == .openAICompatible
            || accessMode == .anthropicCompatible
    }

    var settingsRouteChipTitle: String {
        switch accessMode {
        case .localServer:
            "Local server"
        case .apiKey, .anthropicCompatible:
            "API key"
        case .openAICompatible:
            runtimeBoundary == .localServer ? "Local endpoint" : "Remote endpoint"
        case .subscriptionCLI:
            "Account CLI"
        case .aiSDKBridge:
            "Bridge"
        }
    }

    var settingsRouteChipDetail: String {
        switch accessMode {
        case .localServer:
            "Routes chat to a configured local model server."
        case .apiKey:
            "Routes chat to the hosted provider API with a Keychain API key."
        case .subscriptionCLI:
            "Routes chat through the signed-in local command-line tool."
        case .openAICompatible:
            "Routes chat to an OpenAI-compatible endpoint; the endpoint decides whether it is local or remote."
        case .anthropicCompatible:
            "Routes chat to an Anthropic-compatible endpoint with its configured key policy."
        case .aiSDKBridge:
            "Routes chat to a local bridge process."
        }
    }

    var settingsRouteChipTone: FlannelStatusTone {
        switch accessMode {
        case .localServer:
            .success
        case .subscriptionCLI, .aiSDKBridge:
            .info
        case .openAICompatible:
            runtimeBoundary == .localServer ? .success : .warning
        case .apiKey, .anthropicCompatible:
            .warning
        }
    }
}

private extension ProviderAccessMode {
    var settingsSystemImage: String {
        switch self {
        case .localServer:
            "server.rack"
        case .apiKey:
            "key"
        case .subscriptionCLI:
            "terminal"
        case .openAICompatible:
            "arrow.left.arrow.right"
        case .anthropicCompatible:
            "text.bubble"
        case .aiSDKBridge:
            "point.3.connected.trianglepath.dotted"
        }
    }
}

private extension ProviderRuntimeBoundary {
    var settingsTone: FlannelStatusTone {
        switch self {
        case .localServer:
            .success
        case .localCLI, .localBridge:
            .info
        case .externalAPI:
            .warning
        }
    }
}

private extension ModelCapability {
    var settingsSystemImage: String {
        switch self {
        case .chat:
            "bubble.left.and.bubble.right"
        case .streaming:
            "dot.radiowaves.left.and.right"
        case .toolCalling:
            "wrench.and.screwdriver"
        case .embeddings:
            "point.3.connected.trianglepath.dotted"
        case .vision:
            "eye"
        case .reasoning:
            "brain"
        case .webSearch:
            "magnifyingglass"
        case .imageGeneration:
            "photo"
        case .structuredOutput:
            "curlybraces"
        case .openAICompatible:
            "arrow.left.arrow.right"
        case .anthropicCompatible:
            "text.bubble"
        }
    }

    var settingsTone: FlannelStatusTone {
        switch self {
        case .chat, .streaming:
            .success
        case .toolCalling, .embeddings, .vision, .reasoning, .webSearch, .imageGeneration, .structuredOutput:
            .info
        case .openAICompatible, .anthropicCompatible:
            .neutral
        }
    }
}

private extension LLMProviderKind {
    var settingsSystemImage: String {
        switch self {
        case .ollama:
            "server.rack"
        case .lmStudio:
            "desktopcomputer"
        case .openAI:
            "sparkles"
        case .anthropic:
            "text.bubble"
        case .gemini:
            "diamond"
        case .xAI:
            "xmark.circle"
        case .mistral:
            "wind"
        case .groq:
            "bolt"
        case .openRouter:
            "point.3.connected.trianglepath.dotted"
        case .perplexity:
            "magnifyingglass"
        case .customOpenAICompatible:
            "network"
        case .chatGPTCLI:
            "terminal"
        case .claudeCodeCLI:
            "terminal"
        case .vercelAISDKBridge:
            "curlybraces"
        }
    }
}

private struct LocalDiscoveryHealthSummary: View {
    var healthSnapshots: [AIProviderHealth]
    var localModelCatalog: [LocalModelDescriptor]

    private var readyProviderCount: Int {
        healthSnapshots.filter(\.canServeRequests).count
    }

    private var loadedModelCount: Int {
        healthSnapshots.reduce(0) { $0 + $1.loadedModelCount }
    }

    private var embeddingModelCount: Int {
        localModelCatalog.filter { $0.capabilities.contains(.embeddings) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    summaryMetric(
                        "Providers",
                        value: "\(readyProviderCount)/\(healthSnapshots.count)",
                        systemImage: "checkmark.circle"
                    )
                    summaryMetric(
                        "Models",
                        value: "\(localModelCatalog.count)",
                        systemImage: "cpu"
                    )
                    summaryMetric(
                        "Loaded",
                        value: "\(loadedModelCount)",
                        systemImage: "memorychip"
                    )
                    summaryMetric(
                        "Embeddings",
                        value: "\(embeddingModelCount)",
                        systemImage: "text.magnifyingglass"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(healthSnapshots) { health in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Label(health.providerKind.displayName, systemImage: statusSystemImage(for: health.status))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor(for: health.status))

                        Text(health.endpoint?.absoluteString ?? "No endpoint")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Text(providerDetail(health))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let message = health.warningMessage ?? health.failureMessage,
                       !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private func summaryMetric(
        _ title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .frame(minWidth: 84, alignment: .leading)
    }

    private func providerDetail(_ health: AIProviderHealth) -> String {
        let modelText = health.discoveredModelCount == 1
            ? "1 model"
            : "\(health.discoveredModelCount) models"
        let loadedText = health.loadedModelCount == 1
            ? "1 loaded"
            : "\(health.loadedModelCount) loaded"
        return "\(humanized(health.status.rawValue)) - \(modelText) - \(loadedText)"
    }

    private func statusSystemImage(for status: AIProviderHealthStatus) -> String {
        switch status {
        case .ready:
            "checkmark.circle"
        case .degraded:
            "exclamationmark.triangle"
        case .unavailable, .misconfigured:
            "xmark.circle"
        case .unknown:
            "questionmark.circle"
        }
    }

    private func statusColor(for status: AIProviderHealthStatus) -> Color {
        switch status {
        case .ready:
            .green
        case .degraded:
            .orange
        case .unavailable, .misconfigured:
            .red
        case .unknown:
            .secondary
        }
    }

    private func humanized(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private struct LocalDiscoverySettingsRow: View {
    var result: LocalProviderDiscoveryResult
    var deletingModelID: String?
    var inspectingModelID: String?
    var loadingModelID: String?
    var unloadingModelID: String?
    var useModel: (LocalModelDescriptor) -> Void
    var loadModel: (LocalModelDescriptor) -> Void
    var unloadModel: (LocalModelDescriptor) -> Void
    var inspectModel: (LocalModelDescriptor) -> Void
    var deleteModel: (LocalModelDescriptor) -> Void
    @State private var pendingDeleteModel: LocalModelDescriptor?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.providerKind.title)
                        .font(.headline)
                    Text(result.endpoint)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(result.status == .ready ? .green : .orange)
            }

            if let errorMessage = result.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if result.models.isEmpty {
                Text("No models reported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(result.models.prefix(8)) { model in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName ?? model.name)
                                .font(.subheadline.weight(.medium))
                            if let displayName = model.displayName,
                               displayName != model.name {
                                Text(model.name)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Text(modelDetail(model))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button(model.capabilities.contains(.chat) ? "Use" : "Embedding") {
                            useModel(model)
                        }
                        .disabled(!model.capabilities.contains(.chat))

                        if model.providerKind == .lmStudio {
                            lmStudioRuntimeControl(for: model)
                        }

                        if model.providerKind == .ollama {
                            Button {
                                inspectModel(model)
                            } label: {
                                if inspectingModelID == model.id {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Model Info", systemImage: "info.circle")
                                        .labelStyle(.iconOnly)
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(inspectingModelID != nil)
                            .help("Inspect this Ollama model")
                            .accessibilityLabel("Inspect \(model.displayName ?? model.name)")

                            Button(role: .destructive) {
                                pendingDeleteModel = model
                            } label: {
                                if deletingModelID == model.id {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Delete", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(deletingModelID != nil)
                            .help("Delete this model from Ollama")
                            .accessibilityLabel("Delete \(model.displayName ?? model.name) from Ollama")
                        }
                    }
                }

                if result.models.count > 8 {
                    Text("\(result.models.count - 8) more models are available from this provider.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .confirmationDialog(
            "Delete Ollama model?",
            isPresented: Binding(
                get: { pendingDeleteModel != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteModel = nil
                    }
                }
            )
        ) {
            if let pendingDeleteModel {
                Button("Delete \(pendingDeleteModel.displayName ?? pendingDeleteModel.name)", role: .destructive) {
                    let model = pendingDeleteModel
                    self.pendingDeleteModel = nil
                    deleteModel(model)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteModel = nil
            }
        } message: {
            if let pendingDeleteModel {
                Text("This removes \(pendingDeleteModel.name) and its local Ollama data from \(pendingDeleteModel.endpoint).")
            }
        }
    }

    @ViewBuilder
    private func lmStudioRuntimeControl(for model: LocalModelDescriptor) -> some View {
        if (model.loadedInstanceCount ?? 0) > 0 {
            Button {
                unloadModel(model)
            } label: {
                if unloadingModelID == model.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Unload from LM Studio", systemImage: "stop.circle")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.borderless)
            .disabled(localModelActionInFlight || model.loadedInstanceIDs?.isEmpty != false)
            .help(model.loadedInstanceIDs?.isEmpty == false
                  ? "Unload this model from LM Studio"
                  : "Run discovery again to get this model's LM Studio instance ID")
            .accessibilityLabel("Unload \(model.displayName ?? model.name) from LM Studio")
        } else {
            Button {
                loadModel(model)
            } label: {
                if loadingModelID == model.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Load in LM Studio", systemImage: "play.circle")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.borderless)
            .disabled(localModelActionInFlight)
            .help("Load this model in LM Studio")
            .accessibilityLabel("Load \(model.displayName ?? model.name) in LM Studio")
        }
    }

    private var localModelActionInFlight: Bool {
        deletingModelID != nil
            || inspectingModelID != nil
            || loadingModelID != nil
            || unloadingModelID != nil
    }

    private var statusText: String {
        "\(humanized(result.status.rawValue)) - \(result.models.count) models"
    }

    private func modelDetail(_ model: LocalModelDescriptor) -> String {
        var metadata = [
            model.publisher,
            model.family,
            model.parameterSize,
            model.quantization,
            model.format
        ].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        if let contextWindowTokens = model.contextWindowTokens {
            metadata.append("\(contextWindowTokens.formatted()) context")
        }
        if let loadedInstanceCount = model.loadedInstanceCount,
           loadedInstanceCount > 0 {
            metadata.append("\(loadedInstanceCount) loaded")
        }
        if let sizeBytes = model.sizeBytes {
            metadata.append(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .binary))
        }
        if let sizeVRAMBytes = model.sizeVRAMBytes {
            metadata.append("\(ByteCountFormatter.string(fromByteCount: sizeVRAMBytes, countStyle: .binary)) VRAM")
        }
        if let selectedVariant = model.selectedVariant,
           selectedVariant != model.name {
            metadata.append(selectedVariant)
        }
        let capabilities = model.capabilities.map(\.title).joined(separator: ", ")
        return (metadata + [capabilities]).filter { !$0.isEmpty }.joined(separator: " - ")
    }

    private func humanized(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private struct ChatFolderSettingsRow: View {
    @Binding var folder: ChatFolder
    var parentOptions: [ChatFolder]
    var threadCount: Int
    var delete: () -> Void
    var persist: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: folder.symbolName)
                    .frame(width: 22)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Folder name", text: Binding(
                        get: { folder.title },
                        set: {
                            folder.title = $0
                            folder.updatedAt = .now
                            persist()
                        }
                    ))

                    HStack {
                        TextField("Symbol", text: Binding(
                            get: { folder.symbolName },
                            set: {
                                folder.symbolName = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "folder" : $0
                                folder.updatedAt = .now
                                persist()
                            }
                        ))
                        .frame(maxWidth: 180)

                        Picker("Parent", selection: Binding(
                            get: { folder.parentID },
                            set: {
                                folder.parentID = $0
                                folder.updatedAt = .now
                                persist()
                            }
                        )) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(parentOptions) { option in
                                Text(option.title).tag(Optional(option.id))
                            }
                        }
                    }

                    Text("\(threadCount) chats")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive, action: delete) {
                    Label("Delete", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Delete folder and leave its chats unfiled")
                .accessibilityLabel("Delete \(folder.title)")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LocalMemorySettingsRow: View {
    @Binding var memory: LocalMemoryRecord
    var delete: () -> Void
    var persist: () -> Void

    private var tagBinding: Binding<String> {
        Binding(
            get: { memory.tagNames.joined(separator: ", ") },
            set: { value in
                memory.tagNames = value
                    .split { $0 == "," || $0 == "\n" || $0 == "\t" }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                memory.updatedAt = .now
                persist()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: memory.category.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: Binding(
                        get: { memory.title },
                        set: {
                            memory.title = $0
                            memory.updatedAt = .now
                            persist()
                        }
                    ))

                    TextField("Memory", text: Binding(
                        get: { memory.detail },
                        set: {
                            memory.detail = $0
                            memory.updatedAt = .now
                            persist()
                        }
                    ), axis: .vertical)
                    .lineLimit(2...5)

                    HStack {
                        Picker("Category", selection: Binding(
                            get: { memory.category },
                            set: {
                                memory.category = $0
                                memory.updatedAt = .now
                                persist()
                            }
                        )) {
                            ForEach(LocalMemoryCategory.allCases) { category in
                                Label(category.title, systemImage: category.systemImage).tag(category)
                            }
                        }

                        Toggle("Enabled", isOn: Binding(
                            get: { memory.isEnabled },
                            set: {
                                memory.isEnabled = $0
                                memory.updatedAt = .now
                                persist()
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }

                    TextField("Tags", text: tagBinding, prompt: Text("privacy, project"))

                    HStack(spacing: 8) {
                        Text(memory.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        if memory.useCount > 0 {
                            Text("Used \(memory.useCount) time\(memory.useCount == 1 ? "" : "s")")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive, action: delete) {
                    Label("Delete Memory", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Delete memory")
                .accessibilityLabel("Delete \(memory.title)")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct KnowledgeSettingsRow: View {
    var source: KnowledgeSource
    var manifest: KnowledgeIndexManifest?
    var capturedWebAsset: LibraryAsset?
    var localOnlyMode: Bool
    var isRefreshingPage: Bool
    var refreshPage: () -> Void
    var queueIndex: () -> Void
    var markStale: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label {
                    Text(source.title)
                        .font(.headline)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: source.kind.settingsSystemImage)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if source.isWatched {
                    FlannelStatusChip("Watched", systemImage: "eye", tone: .info, prominence: .subtle)
                }

                FlannelStatusChip(
                    indexStatus.settingsTitle,
                    systemImage: indexStatus.settingsSystemImage,
                    tone: indexStatus.settingsTone,
                    prominence: .tinted
                )

                if source.kind == .webPage {
                    ControlGroup {
                        Button {
                            refreshPage()
                        } label: {
                            Label(pageRefreshButtonTitle, systemImage: pageRefreshButtonSystemImage)
                        }
                        .disabled(!canRefreshPage)
                        .help(pageRefreshHelp)

                        Menu {
                            Button {
                                queueIndex()
                            } label: {
                                Label("Queue Index", systemImage: "arrow.triangle.2.circlepath")
                            }

                            Button {
                                markStale()
                            } label: {
                                Label("Mark Stale", systemImage: "clock.badge.exclamationmark")
                            }
                            .disabled(indexStatus == .stale)
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                        .accessibilityLabel("More actions for \(source.title)")
                    }
                    .controlSize(.small)
                }
            }

            Text("\(source.kind.settingsTitle) - \(source.location)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 6) {
                if source.kind == .webPage {
                    KnowledgeSettingsMetadataRow(
                        title: "Page capture",
                        systemImage: pageCaptureSystemImage,
                        value: pageCaptureSummary,
                        detail: pageCaptureDetail
                    )
                }

                KnowledgeSettingsMetadataRow(
                    title: "Index",
                    systemImage: "square.stack.3d.up",
                    value: indexSummary,
                    detail: indexDetail
                )

                KnowledgeSettingsMetadataRow(
                    title: "RAG mode",
                    systemImage: ragSystemImage,
                    value: ragSummary,
                    detail: ragDetail
                )

                KnowledgeSettingsMetadataRow(
                    title: "Vectors",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    value: vectorSummary,
                    detail: vectorDetail
                )

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var indexStatus: KnowledgeIndexStatus {
        manifest?.status ?? source.status
    }

    private var documentCount: Int {
        manifest?.documentCount ?? source.documentCount
    }

    private var chunkCount: Int {
        manifest?.chunkCount ?? source.chunkCount
    }

    private var embeddingRecordCount: Int {
        manifest?.embeddingRecordCount ?? source.embeddingRecordCount
    }

    private var vectorDimension: Int? {
        manifest?.vectorDimension ?? source.vectorDimension
    }

    private var embeddingModelIdentifier: String? {
        trimmed(manifest?.embeddingModelIdentifier) ?? trimmed(source.embeddingModelIdentifier)
    }

    private var embeddingProviderKind: LLMProviderKind? {
        manifest?.embeddingProviderKind
    }

    private var embeddingState: KnowledgeEmbeddingState {
        if let manifest {
            return manifest.embeddingState
        }
        if embeddingRecordCount > 0 {
            return .generated
        }
        if embeddingModelIdentifier != nil {
            return .configured
        }
        return .disabled
    }

    private var webTranscript: TranscriptRecord? {
        capturedWebAsset?.transcript
    }

    private var hasCapturedPageText: Bool {
        webTranscript?.status == .available
            && webTranscript?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var pageCaptureSummary: String {
        if isRefreshingPage {
            return "Refreshing page"
        }

        guard let webTranscript else {
            return "Never captured"
        }

        switch webTranscript.status {
        case .available:
            return hasCapturedPageText ? "Captured page text" : "Captured without readable text"
        case .queued:
            return "Capture queued"
        case .failed:
            return "Capture failed"
        case .notRequested:
            return "Never captured"
        }
    }

    private var pageCaptureDetail: String? {
        if localOnlyMode && !isRefreshingPage {
            return "Local-only mode blocks network refresh until privacy settings allow it."
        }

        if let error = webTranscript?.lastErrorMessage,
           !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return error
        }

        if let capturedAt = capturedWebAsset?.capturedAt {
            return "Captured \(capturedAt.formatted(date: .abbreviated, time: .shortened))"
        }

        return "Capture once to make page text available for local RAG."
    }

    private var pageCaptureSystemImage: String {
        if isRefreshingPage {
            return "arrow.triangle.2.circlepath"
        }
        switch webTranscript?.status {
        case .available:
            return hasCapturedPageText ? "doc.text.magnifyingglass" : "doc.badge.ellipsis"
        case .queued:
            return "clock.arrow.circlepath"
        case .failed:
            return "exclamationmark.triangle"
        case .notRequested, nil:
            return "network"
        }
    }

    private var pageRefreshButtonTitle: String {
        if isRefreshingPage {
            return "Refreshing..."
        }
        if webTranscript?.status == .failed {
            return "Retry Capture"
        }
        return hasCapturedPageText ? "Refresh Page" : "Capture Page"
    }

    private var pageRefreshButtonSystemImage: String {
        isRefreshingPage ? "arrow.triangle.2.circlepath" : "doc.text.magnifyingglass"
    }

    private var canRefreshPage: Bool {
        !isRefreshingPage && !localOnlyMode
    }

    private var pageRefreshHelp: String {
        if localOnlyMode {
            return "Turn off local-only mode before refreshing page text from the network."
        }
        if hasCapturedPageText {
            return "Capture the latest readable page text and rebuild the local index."
        }
        return "Capture readable page text and build a local RAG index."
    }

    private var isDeterministicEmbeddingModel: Bool {
        embeddingModelIdentifier == LocalEmbeddingService.deterministicModelIdentifier
    }

    private var indexSummary: String {
        switch indexStatus {
        case .ready:
            return "\(documentCount) docs, \(chunkCount) chunks"
        case .failed:
            return "Index failed"
        case .stale:
            return "\(documentCount) docs, \(chunkCount) chunks, stale"
        case .queued:
            return "Queued for rebuild"
        case .indexing:
            return "Indexing now"
        case .notIndexed:
            return "Not indexed yet"
        }
    }

    private var indexDetail: String? {
        var details: [String] = []

        if let lastBuiltAt = manifest?.lastBuiltAt ?? source.lastIndexedAt {
            details.append("Last built \(lastBuiltAt.formatted(date: .abbreviated, time: .shortened))")
        } else if manifest == nil {
            details.append("No manifest has been written for this source.")
        }

        if let contentFingerprint = manifest?.contentFingerprint ?? source.contentFingerprint,
           !contentFingerprint.isEmpty {
            details.append("Fingerprint \(String(contentFingerprint.prefix(12)))")
        }

        return details.isEmpty ? nil : details.joined(separator: " - ")
    }

    private var ragSummary: String {
        if embeddingRecordCount > 0 {
            return "Hybrid local RAG"
        }
        if chunkCount > 0 {
            return "Keyword-only local RAG"
        }
        return "RAG unavailable"
    }

    private var ragSystemImage: String {
        if embeddingRecordCount > 0 {
            return embeddingState.settingsSystemImage
        }
        return "text.magnifyingglass"
    }

    private var ragDetail: String? {
        switch embeddingState {
        case .disabled:
            return "No embedding model is configured; retrieval uses local chunks and keyword scoring."
        case .configured:
            return embeddingConfigurationDetail(suffix: "configured, waiting for vector records.")
        case .generated:
            if embeddingRecordCount == 0 {
                return "Embedding state is ready, but no vector records are present."
            }
            if isDeterministicEmbeddingModel {
                return "Uses offline deterministic vectors (\(LocalEmbeddingService.deterministicModelIdentifier)); no embedding provider is required."
            }
            if let provider = embeddingProviderKind {
                return embeddingConfigurationDetail(
                    suffix: "reported by the manifest as provider-backed local RAG."
                ) ?? "Manifest reports \(provider.title) as the embedding provider."
            }
            if let embeddingModelIdentifier {
                return "Uses vector records labeled \(embeddingModelIdentifier), with no provider attached in the manifest."
            }
            return "Vector records exist, but the manifest has no embedding model metadata."
        case .failed:
            return errorMessage ?? "Embedding generation failed for this source."
        }
    }

    private var vectorSummary: String {
        guard embeddingRecordCount > 0 else {
            return "No vector records"
        }
        return "\(embeddingRecordCount) vector records"
    }

    private var vectorDetail: String? {
        var details: [String] = []

        if let vectorDimension {
            details.append("\(vectorDimension)d")
        }

        if let embeddingModelIdentifier {
            if isDeterministicEmbeddingModel {
                details.append("offline deterministic model")
            } else {
                details.append("model \(embeddingModelIdentifier)")
            }
        }

        if let storageLocation = trimmed(manifest?.storageLocation) {
            details.append(storageLocation)
        }

        return details.isEmpty ? nil : details.joined(separator: " - ")
    }

    private var errorMessage: String? {
        trimmed(source.lastErrorMessage) ?? trimmed(manifest?.lastErrorMessage)
    }

    private func embeddingConfigurationDetail(suffix: String) -> String? {
        guard let embeddingModelIdentifier else {
            return embeddingProviderKind.map { "\($0.title) embedding provider \(suffix)" }
        }

        if let embeddingProviderKind {
            return "\(embeddingProviderKind.title) / \(embeddingModelIdentifier) \(suffix)"
        }

        return "\(embeddingModelIdentifier) \(suffix)"
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

private struct KnowledgeSettingsMetadataRow: View {
    var title: String
    var systemImage: String
    var value: String
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private extension KnowledgeSourceKind {
    var settingsTitle: String {
        switch self {
        case .folder:
            "Folder"
        case .file:
            "File"
        case .webPage:
            "Web page"
        case .chatHistory:
            "Chat history"
        case .workspaceNotes:
            "Workspace notes"
        case .codeRepository:
            "Code repository"
        }
    }

    var settingsSystemImage: String {
        switch self {
        case .folder:
            "folder"
        case .file:
            "doc"
        case .webPage:
            "globe"
        case .chatHistory:
            "bubble.left.and.bubble.right"
        case .workspaceNotes:
            "note.text"
        case .codeRepository:
            "chevron.left.forwardslash.chevron.right"
        }
    }

    var settingsLocationPlaceholder: String {
        switch self {
        case .folder:
            "~/Documents/Research"
        case .file:
            "~/Documents/brief.md"
        case .webPage:
            "https://example.com/reference"
        case .chatHistory:
            "flannel://chat-history"
        case .workspaceNotes:
            "flannel://workspace"
        case .codeRepository:
            "~/dev/project"
        }
    }

    var settingsOnboardingDetail: String {
        switch self {
        case .folder:
            "Indexes supported documents inside a local folder. Watched folders can be re-queued when files change."
        case .file:
            "Indexes one local document such as Markdown, TXT, PDF, DOCX, HTML, or a supported source file."
        case .webPage:
            "Adds a local web capture source. Page text stays local after capture; refreshes require network access."
        case .chatHistory:
            "Indexes local Flannel chat history so future chats can retrieve prior decisions and citations."
        case .workspaceNotes:
            "Indexes local workspace notes, projects, drafts, and saved context that already live in Flannel."
        case .codeRepository:
            "Indexes readable code and documentation from a local repository with default build/dependency exclusions."
        }
    }

    var usesPathPicker: Bool {
        switch self {
        case .folder, .file, .codeRepository:
            true
        case .webPage, .chatHistory, .workspaceNotes:
            false
        }
    }

    var supportsWatching: Bool {
        switch self {
        case .folder, .file, .webPage, .codeRepository:
            true
        case .chatHistory, .workspaceNotes:
            false
        }
    }
}

private extension KnowledgeIndexStatus {
    var settingsTitle: String {
        switch self {
        case .notIndexed:
            "Not indexed"
        case .queued:
            "Queued"
        case .indexing:
            "Indexing"
        case .ready:
            "Ready"
        case .stale:
            "Stale"
        case .failed:
            "Failed"
        }
    }

    var settingsSystemImage: String {
        switch self {
        case .ready:
            "checkmark.circle"
        case .queued, .indexing:
            "arrow.triangle.2.circlepath"
        case .failed:
            "exclamationmark.triangle"
        case .notIndexed, .stale:
            "clock"
        }
    }

    var settingsTone: FlannelStatusTone {
        switch self {
        case .ready:
            .success
        case .queued, .indexing:
            .info
        case .stale, .notIndexed:
            .warning
        case .failed:
            .danger
        }
    }
}

private extension KnowledgeEmbeddingState {
    var settingsSystemImage: String {
        switch self {
        case .disabled:
            "text.magnifyingglass"
        case .configured:
            "cpu"
        case .generated:
            "point.3.connected.trianglepath.dotted"
        case .failed:
            "exclamationmark.triangle"
        }
    }
}

private struct ToolSettingsRow: View {
    var tool: ToolConfiguration
    @Binding var isEnabled: Bool
    @Binding var policy: ToolPermissionPolicy
    @Binding var endpoint: String
    @Binding var secretDraft: String
    var setupMessage: String?
    var saveAPIKey: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.title)
                        .font(.headline)
                    Text(tool.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("Enabled", isOn: $isEnabled)
            }

            Picker("Permission", selection: $policy) {
                ForEach(ToolPermissionPolicy.allCases) { policy in
                    Text(humanized(policy.rawValue)).tag(policy)
                }
            }

            if tool.exposesConnectorSettings {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    TextField(tool.connectorEndpointPlaceholder, text: $endpoint)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        SecureField(tool.secretReference == nil ? tool.connectorSecretPlaceholder : "Replace \(tool.connectorSecretName)", text: $secretDraft)
                            .textFieldStyle(.roundedBorder)
                        Button("Save Key", action: saveAPIKey)
                            .disabled(secretDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    SettingsInlineNotice(
                        message: tool.secretReference == nil ? "No Keychain key saved" : "\(tool.connectorSecretName) saved in Keychain",
                        tone: tool.secretReference == nil ? .info : .success
                    )

                    if let setupMessage {
                        SettingsInlineNotice(
                            message: setupMessage,
                            tone: settingsNoticeTone(for: setupMessage)
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func humanized(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private struct AutomationSettingsRow: View {
    var automation: WorkspaceAutomation
    var toggleEnabled: () -> Void
    var run: () -> Void

    private var action: WorkspaceAutomationAction {
        automation.resolvedAction
    }

    private var actionTitle: String {
        if action.kind == .runTool,
           let toolKind = action.toolKind {
            return "Run \(toolKind.settingsTitle)"
        }
        return action.kind.settingsTitle
    }

    private var queryText: String? {
        let trimmedQuery = action.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedQuery.isEmpty ? nil : trimmedQuery
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(automation.title)
                        .font(.headline)
                    Text(automation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                Toggle("Enabled", isOn: Binding(
                    get: { automation.isEnabled },
                    set: { _ in toggleEnabled() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(automation.isEnabled ? "Disable automation" : "Enable automation")

                Button(action: run) {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!automation.isEnabled)
                .help("Run this automation now")
            }

            HStack(spacing: 10) {
                Label(actionTitle, systemImage: action.kind.settingsSymbolName)
                Label(automation.cadence.settingsTitle, systemImage: "clock.arrow.circlepath")
                Label(automation.lastRunState.settingsTitle, systemImage: automation.lastRunState.settingsSymbolName)
                    .foregroundStyle(automation.lastRunState.settingsTint)
                if automation.requiresConfirmation {
                    Label("Confirm first", systemImage: "checkmark.shield")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let queryText {
                Text(queryText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if let message = automation.lastResultMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct ActionTraceSettingsRow: View {
    var action: LocalActionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Label(action.title, systemImage: action.kind.settingsSymbolName)
                    .font(.headline)
                Spacer()
                Text(humanized(action.status.rawValue))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(action.status.settingsTint)
            }

            Text(action.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Label(action.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                Label(action.destination.title, systemImage: action.destination.systemImage)
                if action.requiresConfirmation {
                    Label("Approval gated", systemImage: "checkmark.shield")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func humanized(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private extension LocalActionKind {
    var settingsTitle: String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var settingsSymbolName: String {
        switch self {
        case .captureURL:
            "link"
        case .importTranscript:
            "text.badge.plus"
        case .generateSummary:
            "sparkles"
        case .createDraft:
            "square.and.pencil"
        case .scheduleDraft:
            "calendar.badge.plus"
        case .runAutomation:
            "arrow.triangle.2.circlepath"
        case .runTool:
            "wrench.and.screwdriver"
        case .exportDraft:
            "square.and.arrow.up"
        }
    }
}

private extension AutomationCadence {
    var settingsTitle: String {
        rawValue.capitalized
    }
}

private extension AutomationRunState {
    var settingsTitle: String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var settingsSymbolName: String {
        switch self {
        case .idle:
            "circle"
        case .queued:
            "clock"
        case .running:
            "arrow.triangle.2.circlepath"
        case .succeeded:
            "checkmark.circle"
        case .needsConfirmation:
            "checkmark.shield"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var settingsTint: Color {
        switch self {
        case .succeeded:
            .green
        case .needsConfirmation:
            .orange
        case .failed:
            .red
        case .idle, .queued, .running:
            .secondary
        }
    }
}

private extension LocalActionStatus {
    var settingsTint: Color {
        switch self {
        case .completed:
            .green
        case .queued:
            .secondary
        case .requiresConfirmation:
            .orange
        case .failed:
            .red
        }
    }
}

private struct PromptSettingsRow: View {
    @Binding var profile: SystemPromptProfile
    var isDefault: Bool
    var setDefault: () -> Void
    var clearDefault: () -> Void
    var delete: () -> Void
    var persist: () -> Void

    private var tagsBinding: Binding<String> {
        Binding(
            get: { profile.tags.joined(separator: ", ") },
            set: { value in
                profile.tags = editableTags(from: value)
                persist()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.badge.star")
                    .frame(width: 22)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Profile name", text: Binding(
                        get: { profile.title },
                        set: {
                            profile.title = $0
                            persist()
                        }
                    ))

                    TextField("Short description", text: Binding(
                        get: { profile.detail },
                        set: {
                            profile.detail = $0
                            persist()
                        }
                    ))

                    TextField("System prompt", text: Binding(
                        get: { profile.prompt },
                        set: {
                            profile.prompt = $0
                            persist()
                        }
                    ), axis: .vertical)
                    .lineLimit(3...8)

                    TextField("Tags", text: tagsBinding, prompt: Text("research, coding, writing"))

                    HStack(spacing: 10) {
                        Toggle("Default", isOn: Binding(
                            get: { isDefault },
                            set: { isOn in
                                if isOn {
                                    setDefault()
                                } else {
                                    clearDefault()
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)

                        if isDefault {
                            Text("Default")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.indigo)
                        }
                    }
                }

                Spacer()

                Button(role: .destructive, action: delete) {
                    Label("Delete Prompt Profile", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Delete prompt profile")
                .accessibilityLabel("Delete \(profile.title)")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ChatTemplateSettingsRow: View {
    @Binding var template: ChatTemplate
    var providerKinds: [LLMProviderKind]
    var accessModes: [ProviderAccessMode]
    var toolKinds: [AIToolKind]
    var knowledgeSources: [KnowledgeSource]
    var delete: () -> Void
    var persist: () -> Void

    private var tagsBinding: Binding<String> {
        Binding(
            get: { template.tagNames.joined(separator: ", ") },
            set: { value in
                template.tagNames = editableTags(from: value)
                template.updatedAt = .now
                persist()
            }
        )
    }

    private var toolSummary: String {
        let names = template.requiredToolKinds.map(\.settingsTitle)
        return names.isEmpty ? "No required tools" : names.joined(separator: ", ")
    }

    private var availableKnowledgeSources: [KnowledgeSource] {
        knowledgeSources.sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var selectedKnowledgeSourceIDs: Set<UUID> {
        Set(template.knowledgeSourceIDs)
    }

    private var knowledgeSummary: String {
        let selectedCount = availableKnowledgeSources.filter { selectedKnowledgeSourceIDs.contains($0.id) }.count
        if selectedCount == 0 {
            return "Use workspace knowledge defaults"
        }
        if selectedCount == 1 {
            return "1 scoped knowledge source"
        }
        return "\(selectedCount) scoped knowledge sources"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: template.isPinned ? "star.fill" : "sparkles")
                    .frame(width: 22)
                    .foregroundStyle(template.isPinned ? .indigo : .secondary)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Template name", text: Binding(
                        get: { template.title },
                        set: {
                            template.title = $0
                            template.updatedAt = .now
                            persist()
                        }
                    ))

                    TextField("Short description", text: Binding(
                        get: { template.detail },
                        set: {
                            template.detail = $0
                            template.updatedAt = .now
                            persist()
                        }
                    ))

                    TextField("System prompt", text: Binding(
                        get: { template.systemPrompt },
                        set: {
                            template.systemPrompt = $0
                            template.updatedAt = .now
                            persist()
                        }
                    ), axis: .vertical)
                    .lineLimit(3...8)

                    TextField("Starter prompt", text: Binding(
                        get: { template.starterPrompt },
                        set: {
                            template.starterPrompt = $0
                            template.updatedAt = .now
                            persist()
                        }
                    ), axis: .vertical)
                    .lineLimit(2...6)

                    HStack {
                        Picker("Mode", selection: Binding(
                            get: { template.mode },
                            set: {
                                template.mode = $0
                                template.updatedAt = .now
                                persist()
                            }
                        )) {
                            ForEach(AssistantMode.allCases, id: \.self) { mode in
                                Text(mode.settingsTitle).tag(mode)
                            }
                        }

                        Toggle("Pinned", isOn: Binding(
                            get: { template.isPinned },
                            set: {
                                template.isPinned = $0
                                template.updatedAt = .now
                                persist()
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }

                    HStack {
                        Picker("Provider", selection: Binding(
                            get: { template.preferredProviderKind },
                            set: {
                                template.preferredProviderKind = $0
                                template.updatedAt = .now
                                persist()
                            }
                        )) {
                            Text("Workspace default").tag(Optional<LLMProviderKind>.none)
                            ForEach(providerKinds) { kind in
                                Text(kind.title).tag(Optional(kind))
                            }
                        }

                        Picker("Access", selection: Binding(
                            get: { template.preferredAccessMode },
                            set: {
                                template.preferredAccessMode = $0
                                template.updatedAt = .now
                                persist()
                            }
                        )) {
                            Text("Any mode").tag(Optional<ProviderAccessMode>.none)
                            ForEach(accessModes) { mode in
                                Text(mode.title).tag(Optional(mode))
                            }
                        }
                    }

                    TextField("Preferred model", text: Binding(
                        get: { template.preferredModelIdentifier ?? "" },
                        set: {
                            template.preferredModelIdentifier = $0
                            template.updatedAt = .now
                            persist()
                        }
                    ), prompt: Text("llama3.1, gpt-5.5, claude-opus-4.7"))

                    TextField("Tags", text: tagsBinding, prompt: Text("research, local"))

                    DisclosureGroup {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150), spacing: 6, alignment: .leading)],
                            alignment: .leading,
                            spacing: 6
                        ) {
                            ForEach(toolKinds) { toolKind in
                                Toggle(toolKind.settingsTitle, isOn: Binding(
                                    get: { template.requiredToolKinds.contains(toolKind) },
                                    set: { isOn in
                                        if isOn {
                                            template.requiredToolKinds.append(toolKind)
                                        } else {
                                            template.requiredToolKinds.removeAll { $0 == toolKind }
                                        }
                                        template.updatedAt = .now
                                        persist()
                                    }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Label(toolSummary, systemImage: "wrench.and.screwdriver")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    DisclosureGroup {
                        if availableKnowledgeSources.isEmpty {
                            Text("Add local files, folders, web pages, repositories, chat history, or workspace notes from Knowledge settings before scoping this template.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 6)
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 210), spacing: 6, alignment: .leading)],
                                alignment: .leading,
                                spacing: 6
                            ) {
                                ForEach(availableKnowledgeSources) { source in
                                    Toggle(isOn: knowledgeSourceBinding(for: source.id)) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(source.title)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Text("\(source.kind.settingsTitle) - \(source.status.settingsTitle)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                            .padding(.top, 6)
                        }
                    } label: {
                        Label(knowledgeSummary, systemImage: "books.vertical")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text("\(template.mode.settingsTitle) - \(template.routeSummary)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button(role: .destructive, action: delete) {
                    Label("Delete Chat Template", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Delete chat template")
                .accessibilityLabel("Delete \(template.title)")
            }
        }
        .padding(.vertical, 4)
    }

    private func knowledgeSourceBinding(for sourceID: UUID) -> Binding<Bool> {
        Binding(
            get: { template.knowledgeSourceIDs.contains(sourceID) },
            set: { isSelected in
                if isSelected {
                    if !template.knowledgeSourceIDs.contains(sourceID) {
                        template.knowledgeSourceIDs.append(sourceID)
                    }
                } else {
                    template.knowledgeSourceIDs.removeAll { $0 == sourceID }
                }
                template.knowledgeSourceIDs = availableKnowledgeSources
                    .map(\.id)
                    .filter { template.knowledgeSourceIDs.contains($0) }
                template.updatedAt = .now
                persist()
            }
        )
    }
}

private extension AssistantMode {
    var settingsTitle: String {
        switch self {
        case .workspaceCopilot:
            "Workspace"
        case .research:
            "Research"
        case .drafting:
            "Drafting"
        }
    }
}

private extension AIToolKind {
    var settingsTitle: String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private func editableTags(from rawValue: String) -> [String] {
    rawValue
        .split { $0 == "," || $0 == "\n" || $0 == "\t" }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private struct OllamaModelInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    var info: OllamaModelInfo

    private var longSections: [(title: String, value: String, monospaced: Bool)] {
        let sections: [(title: String, value: String?, monospaced: Bool)] = [
            ("Parameters", info.parameters, true),
            ("Template", info.template, true),
            ("System", info.system, false),
            ("License", info.license, false),
            ("Modelfile", info.modelfile, true)
        ]
        return sections.compactMap { section in
            guard let value = section.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return nil
            }
            return (section.title, value, section.monospaced)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(info.model)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Text(info.endpoint)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !info.summaryPairs.isEmpty {
                        OllamaModelInfoPairGrid(title: "Summary", pairs: info.summaryPairs)
                    }

                    if !info.modelInfoPairs.isEmpty {
                        OllamaModelInfoPairGrid(title: "Model Info", pairs: Array(info.modelInfoPairs.prefix(32)))

                        if info.modelInfoPairs.count > 32 {
                            Text("+\(info.modelInfoPairs.count - 32) more metadata fields")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(longSections, id: \.title) { section in
                        OllamaModelInfoTextSection(
                            title: section.title,
                            value: section.value,
                            monospaced: section.monospaced
                        )
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 520, idealHeight: 680)
    }
}

private struct OllamaModelInfoPairGrid: View {
    var title: String
    var pairs: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    GridRow(alignment: .firstTextBaseline) {
                        Text(pair.0)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(pair.1)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct OllamaModelInfoTextSection: View {
    var title: String
    var value: String
    var monospaced: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(value, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy \(title)")
                .accessibilityLabel("Copy \(title)")
            }

            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.background.opacity(0.52), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptySettingsRow: View {
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "tray")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FlannelSpacing.paneInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flannelPaneSurface(.subtle, cornerRadius: FlannelRadius.lg)
        .accessibilityElement(children: .combine)
    }
}
