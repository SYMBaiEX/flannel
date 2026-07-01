//
//  ContentView.swift
//  flannel
//
//  Created by SYMBiEX on 6/28/26.
//

import SwiftData
import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct ChatProviderStreamAttempt {
    var provider: ProviderConfiguration
    var history: [AssistantMessage]
    var systemPrompt: String
    var contextTokenCount: Int?
}

private enum ShellFocusDestination {
    case composer
    case sidebarSearch
    case inspector
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var store: WorkspaceStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var composerText = ""
    @State private var composerAttachments: [AIChatAttachment] = []
    @State private var isDiscoveringModels = false
    @State private var isStreamingResponse = false
    @State private var streamingTask: Task<Void, Never>?
    @State private var activeStreamingMessageID: UUID?
    @State private var activeStreamingThreadID: UUID?
    @State private var comparisonPrompt = "Compare the selected providers for accuracy, latency, privacy, tool support, and the safest next action for this workspace."
    @State private var selectedComparisonProviderIDs: Set<UUID> = []
    @State private var selectedComparisonRunID: UUID?
    @State private var selectedComparisonResultID: UUID?
    @State private var isRunningComparison = false
    @State private var comparisonTask: Task<Void, Never>?
    @State private var knowledgeSourceWatchService = KnowledgeSourceWatchService()
    @State private var isCommandPalettePresented = false
    @State private var commandPaletteQuery = ""
    @SceneStorage("flannel.sidebar.surface") private var sidebarSurfaceRawValue = FlannelSidebarSurface.conversation.rawValue
    @SceneStorage("flannel.settings.route") private var selectedSettingsTabRawValue = SettingsTab.general.rawValue
    @SceneStorage("flannel.settings.search") private var settingsSearchText = ""
    @State private var sidebarSearchFocusRequest = 0
    @State private var settingsSidebarFocusRequest = 0
    @State private var composerFocusRequest = 0
    @State private var inspectorFocusRequest = 0
    @State private var settingsReturnFocus: ShellFocusDestination = .composer

    var body: some View {
        rootSplitView
            .background {
                FlannelShellBackdrop()
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar {
                primaryToolbar
            }
            .overlay {
                commandPaletteOverlay
            }
            .onExitCommand(perform: handleExitCommand)
            .focusedSceneValue(\.flannelCommandContext, commandContext)
            .focusedSceneValue(\.flannelCommandRunner) { commandID in
                runCommand(id: commandID)
            }
            .persistenceIssueAlert(store: store, retrySave: persistQuietly)
            .frame(minWidth: 1080, minHeight: 680)
            .tint(.accentColor)
            .task {
                do {
                    try store.loadOrCreate(in: modelContext)
                    store.clearPersistenceIssue(matching: .load)
                } catch {
                    store.recordPersistenceFailure(error, operation: .load)
                }
                columnVisibility = sidebarSurface == .settings
                    ? .doubleColumn
                    : (store.preferences.showsRightSidebar ? .all : .doubleColumn)
                if store.localDiscoveryResults.isEmpty {
                    discoverLocalModels()
                }
                synchronizeKnowledgeSourceWatchers()
            }
            .onChange(of: store.knowledgeSources) {
                synchronizeKnowledgeSourceWatchers()
            }
            .onDisappear {
                streamingTask?.cancel()
                comparisonTask?.cancel()
                knowledgeSourceWatchService.stop()
                persistQuietly()
            }
    }

    private var rootSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
    }

    private var sidebarColumn: some View {
        let width = sidebarSurface.columnWidth

        return AppSidebar(
            store: store,
            sidebarSurface: sidebarSurface,
            selectedSettingsTab: selectedSettingsTabBinding,
            searchFocusRequest: sidebarSearchFocusRequest,
            settingsFocusRequest: settingsSidebarFocusRequest,
            newChat: newChat,
            enterSettings: { tab in
                enterSettingsMode(tab, returnFocus: .sidebarSearch)
            },
            exitSettings: { exitSettingsMode() },
            persist: persistQuietly
        )
        .navigationSplitViewColumnWidth(min: width.min, ideal: width.ideal, max: width.max)
    }

    private var contentColumn: some View {
        MainSurface(
            store: store,
            sidebarSurface: sidebarSurface,
            selectedSettingsTab: selectedSettingsTabBinding,
            settingsSearchText: $settingsSearchText,
            composerText: $composerText,
            composerAttachments: $composerAttachments,
            comparisonPrompt: $comparisonPrompt,
            selectedComparisonProviderIDs: $selectedComparisonProviderIDs,
            selectedComparisonRunID: $selectedComparisonRunID,
            selectedComparisonResultID: $selectedComparisonResultID,
            composerFocusRequest: composerFocusRequest,
            isArtifactsVisible: columnVisibility == .all,
            isDiscoveringModels: isDiscoveringModels,
            isStreamingResponse: isStreamingResponse,
            isRunningComparison: isRunningComparison,
            sendMessage: sendMessage,
            cancelStreaming: cancelStreaming,
            compareCurrentPrompt: compareCurrentPrompt,
            runComparison: runModelComparison,
            cancelComparison: cancelModelComparison,
            toggleMessagePin: toggleMessagePin,
            copyMessage: copyMessage,
            copyComparisonResult: copyComparisonResult,
            useComparisonResultProvider: useComparisonResultProvider,
            retryFromMessage: retryFromMessage,
            editMessage: editMessage,
            forkThreadFromMessage: forkThreadFromMessage,
            discoverModels: discoverLocalModels,
            continueAfterToolResult: { result, toolCall in
                continueAfterToolResult(result, sourceToolCall: toolCall)
            },
            openModelSetup: {
                enterSettingsMode(.models, returnFocus: .composer)
            },
            showArtifacts: {
                setInspectorVisibility(true, focusChromeWhenShown: true)
            },
            exitSettings: { exitSettingsMode() },
            importChat: importChat,
            exportWorkspaceSnapshot: exportWorkspaceSnapshot,
            importWorkspaceSnapshot: importWorkspaceSnapshot,
            persist: persistQuietly
        )
        .navigationSplitViewColumnWidth(min: 620, ideal: 1_020)
    }

    @ViewBuilder
    private var detailColumn: some View {
        if sidebarSurface.showsInspectorColumn {
            inspectorColumn
        } else {
            Color.clear
                .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
        }
    }

    private var inspectorColumn: some View {
        InspectorSurface(
            store: store,
            selectedComparisonRunID: selectedComparisonRunID,
            selectedComparisonResultID: selectedComparisonResultID,
            isDiscoveringModels: isDiscoveringModels,
            isRunningComparison: isRunningComparison,
            focusRequest: inspectorFocusRequest,
            discoverModels: discoverLocalModels,
            collapseArtifacts: { setInspectorVisibility(false) },
            copyComparisonResult: copyComparisonResult,
            useComparisonResultProvider: useComparisonResultProvider,
            openSettingsTab: { tab in
                enterSettingsMode(tab, returnFocus: .inspector)
            },
            persist: persistQuietly
        )
        .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
    }

    @ToolbarContentBuilder
    private var primaryToolbar: some ToolbarContent {
        if sidebarSurface == .conversation {
            ToolbarItemGroup(placement: .primaryAction) {
                ProviderRoutingPicker(
                    store: store,
                    isDiscoveringModels: isDiscoveringModels,
                    discoverModels: discoverLocalModels,
                    openProviderSetup: {
                        enterSettingsMode(.models, returnFocus: .composer)
                    },
                    persist: persistQuietly
                )

                Button {
                    setInspectorVisibility(columnVisibility != .all)
                } label: {
                    Label(columnVisibility == .all ? "Hide Artifacts" : "Show Artifacts", systemImage: "sidebar.right")
                        .labelStyle(.iconOnly)
                }
                .help(columnVisibility == .all ? "Hide Artifacts" : "Show Artifacts")
                .accessibilityLabel(columnVisibility == .all ? "Hide Artifacts" : "Show Artifacts")
            }
        }
    }

    @ViewBuilder
    private var commandPaletteOverlay: some View {
        if isCommandPalettePresented {
            CommandPaletteOverlay(
                commands: FlannelCommand.defaultCommands(context: commandContext),
                query: $commandPaletteQuery,
                dismissPalette: { closeCommandPalette() },
                run: runCommand
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private var sidebarSurface: FlannelSidebarSurface {
        get { FlannelSidebarSurface(rawValue: sidebarSurfaceRawValue) ?? .conversation }
        nonmutating set { sidebarSurfaceRawValue = newValue.rawValue }
    }

    private var selectedSettingsTab: SettingsTab {
        get { SettingsTab(rawValue: selectedSettingsTabRawValue) ?? .general }
        nonmutating set { selectedSettingsTabRawValue = newValue.rawValue }
    }

    private var selectedSettingsTabBinding: Binding<SettingsTab> {
        Binding(
            get: { selectedSettingsTab },
            set: { selectedSettingsTab = $0 }
        )
    }

    private var canSendMessageFromCommand: Bool {
        !isStreamingResponse
            && (!composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !composerAttachments.isEmpty)
    }

    private var canRunComparisonFromCommand: Bool {
        !isRunningComparison
            && !comparisonPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canCompareCurrentPromptFromCommand: Bool {
        !isStreamingResponse
            && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var commandContext: FlannelCommandContext {
        FlannelCommandContext(
            hasCurrentThread: store.currentAssistantThread != nil,
            canSendMessage: canSendMessageFromCommand,
            isStreaming: isStreamingResponse,
            isDiscoveringModels: isDiscoveringModels,
            canCompareCurrentPrompt: canCompareCurrentPromptFromCommand,
            canRunComparison: canRunComparisonFromCommand,
            localOnlyMode: store.preferences.localOnlyMode ?? true,
            allowCloudProviders: store.preferences.allowCloudProviders ?? false,
            inspectorVisible: columnVisibility == .all,
            canPresentInspector: sidebarSurface.showsInspectorColumn,
            hasKnowledgeSources: !store.knowledgeSources.isEmpty,
            hasQueuedKnowledgeSources: store.knowledgeSources.contains { source in
                source.status == .queued || source.status == .stale || source.status == .notIndexed
            },
            providerRoutingPolicy: store.preferences.providerRoutingPolicy
        )
    }

    private func openCommandPalette() {
        commandPaletteQuery = ""
        withAnimation(.easeOut(duration: 0.14)) {
            isCommandPalettePresented = true
        }
    }

    private func closeCommandPalette(restoreComposerFocus: Bool = true) {
        withAnimation(.easeOut(duration: 0.12)) {
            isCommandPalettePresented = false
        }
        if restoreComposerFocus && sidebarSurface == .conversation {
            requestComposerFocus()
        }
    }

    private func handleExitCommand() {
        let action = FlannelExitCommandAction.resolve(
            isCommandPalettePresented: isCommandPalettePresented,
            sidebarSurface: sidebarSurface,
            isInspectorVisible: columnVisibility == .all,
            isStreamingResponse: isStreamingResponse
        )

        switch action {
        case .closeCommandPalette:
            closeCommandPalette()
        case .exitSettings:
            exitSettingsMode()
        case .collapseArtifacts:
            setInspectorVisibility(false)
        case .cancelStreaming:
            cancelStreaming()
        case .none:
            break
        }
    }

    private func synchronizeKnowledgeSourceWatchers() {
        knowledgeSourceWatchService.update(sources: store.knowledgeSources) { changedSourceIDs in
            Task { @MainActor in
                handleWatchedKnowledgeSourceChanges(changedSourceIDs)
            }
        }
    }

    private func handleWatchedKnowledgeSourceChanges(_ sourceIDs: Set<UUID>) {
        let queuedSourceIDs = store.queueWatchedKnowledgeSources(sourceIDs)
        guard !queuedSourceIDs.isEmpty else { return }

        Task { @MainActor in
            await store.rebuildKnowledgeIndexManifestsUsingConfiguredEmbeddings(onlyQueued: true)
            persistQuietly()
        }
    }

    private func runCommand(_ command: FlannelCommand) {
        guard command.isEnabled else { return }

        if command.id == .openCommandPalette {
            openCommandPalette()
            return
        }

        closeCommandPalette(restoreComposerFocus: false)

        if let routingPolicy = command.id.routingPolicy {
            store.preferences.providerRoutingPolicy = routingPolicy
            persistQuietly()
            return
        }

        switch command.id {
        case .newChat:
            newChat()
        case .importChat:
            importChat()
        case .openCommandPalette:
            break
        case .sendMessage:
            sendMessage()
        case .stopStreaming:
            cancelStreaming()
        case .comparePrompt:
            compareCurrentPrompt()
        case .runComparison:
            runModelComparison()
        case .discoverModels:
            discoverLocalModels()
        case .toggleLocalOnly:
            store.preferences.localOnlyMode = !(store.preferences.localOnlyMode ?? true)
            persistQuietly()
        case .toggleCloudProviders:
            if (store.preferences.allowCloudProviders ?? false) && !(store.preferences.localOnlyMode ?? true) {
                store.preferences.allowCloudProviders = false
            } else {
                store.preferences.localOnlyMode = false
                store.preferences.allowCloudProviders = true
            }
            persistQuietly()
        case .setRoutingSelectedProvider, .setRoutingLocalFirst, .setRoutingBestAvailable,
             .setRoutingCheapest, .setRoutingFastest:
            break
        case .openChat:
            openConversationShell(focusComposer: true)
        case .openHistory:
            openConversationShell(focusHistorySearch: true)
        case .openCompare:
            runModelComparison()
        case .openModels:
            enterSettingsMode(.models, returnFocus: .composer)
        case .openKnowledge:
            enterSettingsMode(.knowledge, returnFocus: .composer)
        case .rebuildQueuedKnowledge:
            rebuildKnowledgeIndex(onlyQueued: true)
        case .rebuildAllKnowledge:
            rebuildKnowledgeIndex(onlyQueued: false)
        case .openTools:
            enterSettingsMode(.tools, returnFocus: .composer)
        case .openAgents:
            enterSettingsMode(.agents, returnFocus: .composer)
        case .openPrompts:
            enterSettingsMode(.prompts, returnFocus: .composer)
        case .openSettings:
            enterSettingsMode(.general, returnFocus: .composer)
        case .focusChat:
            setInspectorVisibility(false, focusComposerWhenHidden: true)
        case .showInspector:
            setInspectorVisibility(true, focusChromeWhenShown: true)
        case .exportMarkdown:
            exportCurrentThread(as: .markdown)
        case .exportJSON:
            exportCurrentThread(as: .json)
        case .exportHTML:
            exportCurrentThread(as: .html)
        case .exportPDF:
            exportCurrentThread(as: .pdf)
        case .exportWorkspaceSnapshot:
            exportWorkspaceSnapshot()
        case .importWorkspaceSnapshot:
            importWorkspaceSnapshot()
        }
    }

    private func runCommand(id commandID: FlannelCommandID) {
        guard let command = FlannelCommand.defaultCommand(commandID, context: commandContext) else { return }
        runCommand(command)
    }

    private func rebuildKnowledgeIndex(onlyQueued: Bool) {
        Task { @MainActor in
            await store.rebuildKnowledgeIndexManifestsUsingConfiguredEmbeddings(onlyQueued: onlyQueued)
            persistQuietly()
        }
    }

    private func openConversationShell(focusHistorySearch: Bool = false, focusComposer: Bool = false) {
        if sidebarSurface != .conversation {
            exitSettingsMode(focusComposer: focusComposer && !focusHistorySearch)
        }
        if focusHistorySearch {
            sidebarSearchFocusRequest += 1
        } else if focusComposer {
            requestComposerFocus()
        }
    }

    private func enterSettingsMode(_ tab: SettingsTab = .general, returnFocus: ShellFocusDestination = .composer) {
        selectedSettingsTab = tab
        let isEnteringSettings = sidebarSurface != .settings
        if isEnteringSettings {
            settingsReturnFocus = returnFocus
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            sidebarSurface = .settings
            columnVisibility = .doubleColumn
        }
        if isEnteringSettings {
            DispatchQueue.main.async {
                settingsSidebarFocusRequest += 1
                announce("Settings")
            }
        }
    }

    private func exitSettingsMode(focusComposer: Bool = true) {
        let restoredVisibility: NavigationSplitViewVisibility = store.preferences.showsRightSidebar ? .all : .doubleColumn
        let returnFocus = settingsReturnFocus
        withAnimation(.easeInOut(duration: 0.18)) {
            sidebarSurface = .conversation
            columnVisibility = restoredVisibility
            persistQuietly()
        }
        if focusComposer {
            requestFocus(returnFocus)
        }
    }

    private func setInspectorVisibility(
        _ isVisible: Bool,
        focusComposerWhenHidden: Bool = true,
        focusChromeWhenShown: Bool = false
    ) {
        let wasVisible = columnVisibility == .all
        withAnimation(.easeInOut(duration: 0.18)) {
            columnVisibility = isVisible ? .all : .doubleColumn
            store.preferences.showsRightSidebar = isVisible
            persistQuietly()
        }
        if wasVisible != isVisible {
            announce(isVisible ? "Artifacts shown" : "Artifacts hidden")
        }
        if isVisible && focusChromeWhenShown {
            inspectorFocusRequest += 1
        }
        if !isVisible && focusComposerWhenHidden {
            requestComposerFocus()
        }
    }

    private func requestComposerFocus() {
        composerFocusRequest += 1
    }

    private func requestFocus(_ destination: ShellFocusDestination) {
        switch destination {
        case .composer:
            requestComposerFocus()
        case .sidebarSearch:
            sidebarSearchFocusRequest += 1
        case .inspector:
            if columnVisibility == .all {
                inspectorFocusRequest += 1
            } else {
                requestComposerFocus()
            }
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message]
        )
    }

    private func newChat(from template: ChatTemplate? = nil, folderID: UUID? = nil) {
        let starterPrompt = template.map { store.renderChatTemplateStarterPrompt($0) } ?? ""
        store.createAssistantThread(from: template, folderID: folderID)
        composerText = starterPrompt
        composerAttachments = []
        requestComposerFocus()
        persistQuietly()
    }

    private func sendMessage() {
        guard !isStreamingResponse else { return }
        let prompt = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let outgoingAttachments = composerAttachments
        guard !prompt.isEmpty || !outgoingAttachments.isEmpty else { return }

        let messageText = prompt.isEmpty ? "Review the attached files." : prompt
        store.appendAssistantMessage(messageText, role: .user, attachments: outgoingAttachments)
        guard let sourceThreadID = store.selectedAssistantThreadID else { return }
        composerText = ""
        composerAttachments = []

        if let memoryText = store.parseRememberCommand(messageText) {
            if let memory = store.rememberFromCurrentThread(memoryText) {
                _ = store.appendAssistantMessage(
                    "Saved to local memory: \(memory.title)",
                    role: .assistant
                )
            } else {
                _ = store.appendAssistantMessage(
                    "I could not save that memory because it was empty.",
                    role: .assistant
                )
            }
            persistQuietly()
            return
        }

        if let toolCommand = store.parseChatToolCommand(messageText) {
            Task { @MainActor in
                let result = await store.runChatToolCommand(
                    toolCommand,
                    webPageCaptureService: WebPageCaptureService()
                )
                _ = store.appendToolResultMessage(result)
                persistQuietly()
            }
            return
        }

        let retrievalQuery = [messageText, outgoingAttachments.map(\.title).joined(separator: " ")]
            .joined(separator: " ")
        startAssistantResponse(for: messageText, in: sourceThreadID, retrievalQuery: retrievalQuery)
    }

    private func startAssistantResponse(
        for messageText: String,
        in sourceThreadID: UUID,
        retrievalQuery: String,
        additionalSystemPrompt: String? = nil,
        toolsEnabled: Bool = true
    ) {
        guard !isStreamingResponse else { return }
        isStreamingResponse = true

        streamingTask = Task { @MainActor in
            let sourceThread = store.assistantThreads.first(where: { $0.id == sourceThreadID })
            let retrievalPacket = await store.localKnowledgeRetrievalPacketUsingConfiguredEmbeddings(
                for: retrievalQuery,
                knowledgeSourceIDs: store.threadKnowledgeSourceScope(for: sourceThread)
            )
            guard !Task.isCancelled,
                  isStreamingResponse else { return }
            startAssistantResponseAfterRetrieval(
                for: messageText,
                in: sourceThreadID,
                retrievalPacket: retrievalPacket,
                additionalSystemPrompt: additionalSystemPrompt,
                toolsEnabled: toolsEnabled
            )
        }
    }

    private func startAssistantResponseAfterRetrieval(
        for messageText: String,
        in sourceThreadID: UUID,
        retrievalPacket: LocalKnowledgeRetrievalPacket,
        additionalSystemPrompt: String? = nil,
        toolsEnabled: Bool = true
    ) {
        let rawHistory = store.assistantThreads.first(where: { $0.id == sourceThreadID })?.messages ?? []
        let baseSystemPrompt = store.defaultSystemPrompt()
        let localMemoryContext = store.localMemoryPromptContext(for: messageText)
        let contextAssembler = ChatContextAssemblyService()

        let streamAttempts = store.chatProviderFallbackChain().map { provider in
            let assembledContext = contextAssembler.assemble(
                ChatContextAssemblyInput(
                    baseSystemPrompt: baseSystemPrompt ?? "",
                    additionalSystemPrompt: additionalSystemPrompt,
                    localMemoryContext: localMemoryContext,
                    retrievalPacket: retrievalPacket,
                    history: rawHistory,
                    provider: provider
                )
            )
            return ChatProviderStreamAttempt(
                provider: provider,
                history: assembledContext.history,
                systemPrompt: assembledContext.systemPrompt,
                contextTokenCount: assembledContext.estimatedTokenCount
            )
        }

        guard let firstAttempt = streamAttempts.first else {
            let startedAt = Date()
            let contextTokenCount = estimatedContextTokenCount(
                systemPrompt: [baseSystemPrompt, additionalSystemPrompt, localMemoryContext, retrievalPacket.promptContext]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n"),
                history: rawHistory
            )
            if let messageID = appendDeterministicResponse(
                for: messageText,
                in: sourceThreadID,
                updating: nil,
                retrievalPacket: retrievalPacket
            ) {
                annotateAssistantMessage(
                    messageID,
                    in: sourceThreadID,
                    provider: nil,
                    prompt: messageText,
                    output: currentAssistantMessageText(messageID, in: sourceThreadID),
                    startedAt: startedAt,
                    runStatus: .fallback,
                    contextTokenCount: contextTokenCount,
                    contextWindowTokens: nil,
                    fallbackReason: "No runnable provider was selected."
                )
            }
            isStreamingResponse = false
            streamingTask = nil
            activeStreamingMessageID = nil
            activeStreamingThreadID = nil
            persistQuietly()
            return
        }

        let assistantMessageID = store.appendAssistantMessage("", role: .assistant, in: sourceThreadID)
            ?? store.appendAssistantMessage("", role: .assistant)
        let streamStartedAt = Date()
        markAssistantRunStarted(
            assistantMessageID,
            in: sourceThreadID,
            provider: firstAttempt.provider,
            prompt: messageText,
            startedAt: streamStartedAt,
            contextTokenCount: firstAttempt.contextTokenCount
        )
        isStreamingResponse = true
        activeStreamingMessageID = assistantMessageID
        activeStreamingThreadID = sourceThreadID
        persistQuietly()

        streamingTask = Task {
            var lastFailure: (providerName: String, reason: String)?
            let streamingService = ChatStreamingService()

            for (attemptIndex, attempt) in streamAttempts.enumerated() {
                let attemptStartedAt = attemptIndex == 0 ? streamStartedAt : Date()
                var streamedText = ""
                var streamedUsage: ChatStreamUsage?
                var firstTokenLatencyMilliseconds: Int?
                var toolCallAccumulator = ChatStreamToolCallAccumulator()

                if attemptIndex > 0 {
                    let retryText: String
                    if let lastFailure {
                        retryText = "Retrying with \(attempt.provider.displayName) after \(lastFailure.providerName) failed: \(lastFailure.reason)"
                    } else {
                        retryText = "Retrying with \(attempt.provider.displayName)."
                    }

                    await MainActor.run {
                        store.updateAssistantMessage(assistantMessageID, in: sourceThreadID, text: retryText)
                        updateAssistantToolCalls(assistantMessageID, in: sourceThreadID, toolCalls: [])
                        markAssistantRunStarted(
                            assistantMessageID,
                            in: sourceThreadID,
                            provider: attempt.provider,
                            prompt: messageText,
                            startedAt: attemptStartedAt,
                            contextTokenCount: attempt.contextTokenCount
                        )
                        persistQuietly()
                    }
                }

                do {
                    let stream = streamingService.streamEvents(
                        for: ChatStreamingRequest(
                            provider: attempt.provider,
                            messages: attempt.history,
                            systemPrompt: attempt.systemPrompt.isEmpty ? nil : attempt.systemPrompt,
                            tools: toolsEnabled ? chatToolDefinitions(for: attempt.provider) : []
                        )
                    )

                    for try await event in stream {
                        switch event {
                        case .text(let token):
                            if firstTokenLatencyMilliseconds == nil, !token.isEmpty {
                                let latency = max(0, Int(Date().timeIntervalSince(attemptStartedAt) * 1_000))
                                firstTokenLatencyMilliseconds = latency
                                await MainActor.run {
                                    updateAssistantFirstTokenLatency(assistantMessageID, in: sourceThreadID, latencyMilliseconds: latency)
                                }
                            }
                            streamedText += token
                            await MainActor.run {
                                store.updateAssistantMessage(assistantMessageID, in: sourceThreadID, text: streamedText)
                            }
                        case .usage(let usage):
                            streamedUsage = streamedUsage?.merged(with: usage) ?? usage
                        case .toolCallDelta(let delta):
                            toolCallAccumulator.apply(delta)
                            let toolCalls = toolCallRecords(from: toolCallAccumulator.toolCalls, startedAt: attemptStartedAt)
                            await MainActor.run {
                                updateAssistantToolCalls(assistantMessageID, in: sourceThreadID, toolCalls: toolCalls)
                            }
                        case .toolCallDeltas(let deltas):
                            for delta in deltas {
                                toolCallAccumulator.apply(delta)
                            }
                            let toolCalls = toolCallRecords(from: toolCallAccumulator.toolCalls, startedAt: attemptStartedAt)
                            await MainActor.run {
                                updateAssistantToolCalls(assistantMessageID, in: sourceThreadID, toolCalls: toolCalls)
                            }
                        }
                    }

                    let toolCalls = toolCallRecords(from: toolCallAccumulator.toolCalls, startedAt: attemptStartedAt)
                    if streamedText.isEmpty && toolCalls.isEmpty {
                        lastFailure = (attempt.provider.displayName, "The provider returned an empty stream.")
                        continue
                    }

                    await MainActor.run {
                        isStreamingResponse = false
                        streamingTask = nil
                        activeStreamingMessageID = nil
                        activeStreamingThreadID = nil
                        updateAssistantToolCalls(assistantMessageID, in: sourceThreadID, toolCalls: toolCalls)
                        let finalText = streamedText.isEmpty
                            ? toolCallSummaryText(for: toolCalls)
                            : streamedText + retrievalPacket.responseCitationBlock
                        store.updateAssistantMessage(
                            assistantMessageID,
                            in: sourceThreadID,
                            text: finalText,
                            citations: retrievalPacket.citations
                        )
                        annotateAssistantMessage(
                            assistantMessageID,
                            in: sourceThreadID,
                            provider: attempt.provider,
                            prompt: messageText,
                            output: finalText,
                            startedAt: attemptStartedAt,
                            runStatus: .completed,
                            contextTokenCount: attempt.contextTokenCount,
                            contextWindowTokens: attempt.provider.contextWindowTokens,
                            fallbackReason: lastFailure.map { "Fell back after \($0.providerName): \($0.reason)" },
                            usage: streamedUsage,
                            firstTokenLatencyMilliseconds: firstTokenLatencyMilliseconds
                        )
                        persistQuietly()
                    }

                    await runAutoApprovedRequestedToolCallsIfNeeded(in: assistantMessageID, threadID: sourceThreadID)
                    return
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        await MainActor.run {
                            if isStreamingResponse {
                                stopStreamingMessage(assistantMessageID, in: sourceThreadID)
                            }
                        }
                        return
                    }

                    let toolCalls = toolCallRecords(from: toolCallAccumulator.toolCalls, startedAt: attemptStartedAt)
                    if streamedText.isEmpty && toolCalls.isEmpty && attemptIndex < streamAttempts.count - 1 {
                        lastFailure = (attempt.provider.displayName, error.localizedDescription)
                        continue
                    }

                    await MainActor.run {
                        isStreamingResponse = false
                        streamingTask = nil
                        activeStreamingMessageID = nil
                        activeStreamingThreadID = nil

                        if !streamedText.isEmpty || !toolCalls.isEmpty {
                            updateAssistantToolCalls(assistantMessageID, in: sourceThreadID, toolCalls: toolCalls)
                            let interruptedText = streamedText.isEmpty
                                ? "\(toolCallSummaryText(for: toolCalls))\n\nStream interrupted: \(error.localizedDescription)"
                                : "\(streamedText)\n\nStream interrupted: \(error.localizedDescription)"
                            store.updateAssistantMessage(
                                assistantMessageID,
                                in: sourceThreadID,
                                text: interruptedText,
                                citations: retrievalPacket.citations
                            )
                            annotateAssistantMessage(
                                assistantMessageID,
                                in: sourceThreadID,
                                provider: attempt.provider,
                                prompt: messageText,
                                output: interruptedText,
                                startedAt: attemptStartedAt,
                                runStatus: .failed,
                                contextTokenCount: attempt.contextTokenCount,
                                contextWindowTokens: attempt.provider.contextWindowTokens,
                                fallbackReason: error.localizedDescription,
                                usage: streamedUsage,
                                firstTokenLatencyMilliseconds: firstTokenLatencyMilliseconds
                            )
                        } else {
                            let preamble = "Streaming from \(attempt.provider.displayName) was unavailable: \(error.localizedDescription)\n\nLocal fallback\n"
                            appendDeterministicResponse(
                                for: messageText,
                                in: sourceThreadID,
                                updating: assistantMessageID,
                                prefix: preamble,
                                retrievalPacket: retrievalPacket
                            )
                            annotateAssistantMessage(
                                assistantMessageID,
                                in: sourceThreadID,
                                provider: attempt.provider,
                                prompt: messageText,
                                output: currentAssistantMessageText(assistantMessageID, in: sourceThreadID),
                                startedAt: attemptStartedAt,
                                runStatus: .fallback,
                                contextTokenCount: attempt.contextTokenCount,
                                contextWindowTokens: attempt.provider.contextWindowTokens,
                                fallbackReason: error.localizedDescription,
                                usage: streamedUsage
                            )
                        }
                        persistQuietly()
                    }
                    return
                }
            }

            await MainActor.run {
                let fallbackReason = lastFailure.map { "\($0.providerName): \($0.reason)" }
                    ?? "No configured provider returned content."
                let preamble = "All configured providers were unavailable. Last failure: \(fallbackReason)\n\nLocal fallback\n"
                let contextTokenCount = firstAttempt.contextTokenCount
                isStreamingResponse = false
                streamingTask = nil
                activeStreamingMessageID = nil
                activeStreamingThreadID = nil
                appendDeterministicResponse(
                    for: messageText,
                    in: sourceThreadID,
                    updating: assistantMessageID,
                    prefix: preamble,
                    retrievalPacket: retrievalPacket
                )
                annotateAssistantMessage(
                    assistantMessageID,
                    in: sourceThreadID,
                    provider: nil,
                    prompt: messageText,
                    output: currentAssistantMessageText(assistantMessageID, in: sourceThreadID),
                    startedAt: streamStartedAt,
                    runStatus: .fallback,
                    contextTokenCount: contextTokenCount,
                    contextWindowTokens: nil,
                    fallbackReason: fallbackReason
                )
                persistQuietly()
            }
        }
    }

    private func continueAfterToolResult(
        _ result: LocalToolExecutionResult,
        sourceToolCall: AIToolCallRecord?,
        in threadID: UUID? = nil
    ) {
        guard result.status == .completed else { return }

        let toolName = sourceToolCall?.toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = Self.toolResultFollowUpPrompt(
            result: result,
            toolName: toolName?.isEmpty == false ? toolName : nil
        )
        let retrievalQuery = [result.query, result.output]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard let sourceThreadID = threadID ?? store.selectedAssistantThreadID else { return }
        startAssistantResponse(
            for: prompt,
            in: sourceThreadID,
            retrievalQuery: retrievalQuery,
            additionalSystemPrompt: Self.toolResultFollowUpSystemPrompt,
            toolsEnabled: true
        )
    }

    private func runAutoApprovedRequestedToolCallsIfNeeded(in messageID: UUID, threadID: UUID) async {
        guard automaticToolContinuationCountSinceLastUser(in: threadID) < Self.maximumAutomaticToolContinuations else { return }

        let executions = await store.runAutoApprovedRequestedToolCalls(
            in: messageID,
            webPageCaptureService: WebPageCaptureService()
        )
        guard !executions.isEmpty else { return }

        persistQuietly()
        continueAfterToolResults(executions, in: threadID)
    }

    private func continueAfterToolResults(_ executions: [AutoApprovedToolExecution], in threadID: UUID? = nil) {
        let completedExecutions = executions.filter { $0.result.status == .completed }
        guard !completedExecutions.isEmpty else { return }

        if let execution = completedExecutions.first, completedExecutions.count == 1 {
            continueAfterToolResult(execution.result, sourceToolCall: execution.toolCall, in: threadID)
            return
        }

        let prompt = Self.toolResultsFollowUpPrompt(executions: completedExecutions)
        let retrievalQuery = completedExecutions
            .flatMap { [$0.result.query, $0.result.output] }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard let sourceThreadID = threadID ?? store.selectedAssistantThreadID else { return }
        startAssistantResponse(
            for: prompt,
            in: sourceThreadID,
            retrievalQuery: retrievalQuery,
            additionalSystemPrompt: Self.toolResultFollowUpSystemPrompt,
            toolsEnabled: true
        )
    }

    private func automaticToolContinuationCountSinceLastUser(in threadID: UUID? = nil) -> Int {
        let messages: [AssistantMessage]
        if let threadID,
           let thread = store.assistantThreads.first(where: { $0.id == threadID }) {
            messages = thread.messages
        } else {
            messages = store.currentAssistantThread?.messages ?? []
        }
        guard !messages.isEmpty else { return 0 }

        var count = 0
        for message in messages.reversed() {
            if message.role == .user {
                break
            }
            if message.attachments.contains(where: { $0.kind == .toolResult }) {
                count += 1
            }
        }
        return count
    }

    private static let maximumAutomaticToolContinuations = 3

    private static let toolResultFollowUpSystemPrompt = """
    You are continuing after a local Flannel tool result. Treat the latest tool result message in the transcript as authoritative local output. Summarize what changed or what was found, answer the user's original intent, and request another tool only if the next step genuinely needs one. Do not claim that a new external request, file write, command, or browser action happened unless the transcript contains that tool result.
    """

    private static func toolResultFollowUpPrompt(
        result: LocalToolExecutionResult,
        toolName: String?
    ) -> String {
        let queryLine = result.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\nTool query: \(result.query)"
        return """
        Continue the assistant response after the approved local tool result.

        Tool: \(toolName ?? result.title)
        Status: \(result.status.rawValue)\(queryLine)

        Use the latest tool result message in this chat as context. Provide the next useful assistant response now.
        """
    }

    private static func toolResultsFollowUpPrompt(executions: [AutoApprovedToolExecution]) -> String {
        let lines = executions.map { execution in
            let toolName = execution.toolCall.toolName.trimmingCharacters(in: .whitespacesAndNewlines)
            let query = execution.result.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = toolName.isEmpty ? execution.result.title : toolName
            return query.isEmpty
                ? "- Tool: \(displayName)\n  Status: \(execution.result.status.rawValue)"
                : "- Tool: \(displayName)\n  Status: \(execution.result.status.rawValue)\n  Query: \(query)"
        }
        .joined(separator: "\n")

        return """
        Continue the assistant response after the approved local tool results.

        \(lines)

        Use the latest tool result messages in this chat as context. Provide the next useful assistant response now.
        """
    }

    private func markAssistantRunStarted(
        _ messageID: UUID,
        in threadID: UUID,
        provider: ProviderConfiguration,
        prompt: String,
        startedAt: Date,
        contextTokenCount: Int?
    ) {
        guard let threadIndex = store.assistantThreads.firstIndex(where: { $0.id == threadID }),
              let messageIndex = store.assistantThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }

        store.assistantThreads[threadIndex].messages[messageIndex].providerDisplayName = provider.displayName
        store.assistantThreads[threadIndex].messages[messageIndex].modelIdentifier = provider.modelIdentifier
        store.assistantThreads[threadIndex].messages[messageIndex].providerAccessMode = provider.accessMode
        store.assistantThreads[threadIndex].messages[messageIndex].providerPrivacyScope = provider.privacyScope
        store.assistantThreads[threadIndex].messages[messageIndex].runStatus = .streaming
        store.assistantThreads[threadIndex].messages[messageIndex].startedAt = startedAt
        store.assistantThreads[threadIndex].messages[messageIndex].contextTokenCount = contextTokenCount
        store.assistantThreads[threadIndex].messages[messageIndex].contextWindowTokens = provider.contextWindowTokens
        store.assistantThreads[threadIndex].messages[messageIndex].inputTokenCount = estimatedTokenCount(for: prompt)
        store.assistantThreads[threadIndex].messages[messageIndex].firstTokenLatencyMilliseconds = nil
        store.assistantThreads[threadIndex].messages[messageIndex].tokenCountsAreEstimated = true
        store.assistantThreads[threadIndex].messages[messageIndex].updatedAt = .now
        store.assistantThreads[threadIndex].updatedAt = .now
    }

    private func updateAssistantFirstTokenLatency(
        _ messageID: UUID,
        in threadID: UUID,
        latencyMilliseconds: Int
    ) {
        guard let threadIndex = store.assistantThreads.firstIndex(where: { $0.id == threadID }),
              let messageIndex = store.assistantThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }

        store.assistantThreads[threadIndex].messages[messageIndex].firstTokenLatencyMilliseconds = latencyMilliseconds
        store.assistantThreads[threadIndex].messages[messageIndex].updatedAt = .now
        store.assistantThreads[threadIndex].updatedAt = .now
    }

    private func annotateAssistantMessage(
        _ messageID: UUID,
        in threadID: UUID,
        provider: ProviderConfiguration?,
        prompt: String,
        output: String,
        startedAt: Date,
        runStatus: AssistantMessageRunStatus,
        contextTokenCount: Int? = nil,
        contextWindowTokens: Int? = nil,
        fallbackReason: String? = nil,
        usage: ChatStreamUsage? = nil,
        firstTokenLatencyMilliseconds: Int? = nil
    ) {
        guard let threadIndex = store.assistantThreads.firstIndex(where: { $0.id == threadID }),
              let messageIndex = store.assistantThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }

        let completedAt = Date()
        let outputTokenEstimate = estimatedTokenCount(for: output)
        let inputTokenEstimate = estimatedTokenCount(for: prompt)
        let inputTokenCount = usage?.inputTokens ?? inputTokenEstimate
        let outputTokenCount = usage?.outputTokens ?? outputTokenEstimate
        let latencyMilliseconds = usage?.latencyMilliseconds
            ?? max(0, Int(completedAt.timeIntervalSince(startedAt) * 1_000))
        store.assistantThreads[threadIndex].messages[messageIndex].providerDisplayName = provider?.displayName ?? "Local fallback"
        store.assistantThreads[threadIndex].messages[messageIndex].modelIdentifier = provider?.modelIdentifier
        store.assistantThreads[threadIndex].messages[messageIndex].providerAccessMode = provider?.accessMode
        store.assistantThreads[threadIndex].messages[messageIndex].providerPrivacyScope = provider?.privacyScope ?? .localOnly
        store.assistantThreads[threadIndex].messages[messageIndex].runStatus = runStatus
        store.assistantThreads[threadIndex].messages[messageIndex].startedAt = startedAt
        store.assistantThreads[threadIndex].messages[messageIndex].completedAt = completedAt
        store.assistantThreads[threadIndex].messages[messageIndex].contextTokenCount = contextTokenCount
        store.assistantThreads[threadIndex].messages[messageIndex].contextWindowTokens = contextWindowTokens
        store.assistantThreads[threadIndex].messages[messageIndex].tokenCountsAreEstimated = usage?.hasCompleteTokenCounts != true
        store.assistantThreads[threadIndex].messages[messageIndex].fallbackReason = fallbackReason
        store.assistantThreads[threadIndex].messages[messageIndex].inputTokenCount = inputTokenCount
        store.assistantThreads[threadIndex].messages[messageIndex].outputTokenCount = outputTokenCount
        store.assistantThreads[threadIndex].messages[messageIndex].latencyMilliseconds = latencyMilliseconds
        store.assistantThreads[threadIndex].messages[messageIndex].firstTokenLatencyMilliseconds = firstTokenLatencyMilliseconds
        store.assistantThreads[threadIndex].messages[messageIndex].estimatedCostMicros = estimatedCostMicros(
            provider: provider,
            inputTokens: inputTokenCount,
            outputTokens: outputTokenCount
        )
        store.assistantThreads[threadIndex].messages[messageIndex].updatedAt = .now
        store.assistantThreads[threadIndex].updatedAt = .now
    }

    private func estimatedTokenCount(for text: String) -> Int {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard characterCount > 0 else { return 0 }
        return max(1, Int(ceil(Double(characterCount) / 4.0)))
    }

    private func estimatedContextTokenCount(
        systemPrompt: String,
        history: [AssistantMessage]
    ) -> Int? {
        let contextText = ([systemPrompt] + history.map(\.shareText))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !contextText.isEmpty else { return nil }
        return estimatedTokenCount(for: contextText)
    }

    private func currentAssistantMessageText(_ messageID: UUID, in threadID: UUID) -> String {
        store.assistantMessageText(messageID, in: threadID) ?? ""
    }

    private func updateAssistantToolCalls(_ messageID: UUID, in threadID: UUID, toolCalls: [AIToolCallRecord]) {
        guard let threadIndex = store.assistantThreads.firstIndex(where: { $0.id == threadID }),
              let messageIndex = store.assistantThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        store.assistantThreads[threadIndex].messages[messageIndex].toolCalls = toolCalls
        store.assistantThreads[threadIndex].messages[messageIndex].updatedAt = .now
        store.assistantThreads[threadIndex].updatedAt = .now
    }

    private func toolCallRecords(
        from toolCalls: [ChatStreamToolCall],
        startedAt: Date
    ) -> [AIToolCallRecord] {
        toolCalls.map { toolCall in
            AIToolCallRecord(
                providerCallID: toolCall.id,
                toolName: toolCall.name,
                permissionScope: permissionScope(forStreamedToolName: toolCall.name),
                argumentsJSON: toolCall.arguments,
                wasApproved: false,
                startedAt: startedAt
            )
        }
    }

    private func toolCallSummaryText(for toolCalls: [AIToolCallRecord]) -> String {
        guard !toolCalls.isEmpty else { return "" }
        let names = toolCalls
            .map(\.toolName)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ", ")
        let suffix = names.isEmpty ? "" : ": \(names)"
        return "Provider requested \(toolCalls.count) tool call\(toolCalls.count == 1 ? "" : "s")\(suffix). Review the tool call details before running anything locally."
    }

    private func permissionScope(forStreamedToolName rawName: String) -> AIToolPermissionScope {
        let normalized = rawName
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        if normalized.contains("terminal") || normalized.contains("shell") || normalized.contains("command") {
            return .runShellCommand
        }
        if normalized.contains("write") || normalized.contains("edit") || normalized.contains("patch") || normalized.contains("save") {
            return .writeWorkspace
        }
        if normalized.contains("web") || normalized.contains("http") || normalized.contains("github") || normalized.contains("notion")
            || normalized.contains("youtube") || normalized.contains("searchx") {
            return .makeNetworkRequest
        }
        if normalized.contains("rag") || normalized.contains("retriev") || normalized.contains("index") {
            return .queryRAGIndex
        }
        return .readWorkspace
    }

    private func chatToolDefinitions(for provider: ProviderConfiguration) -> [ChatToolDefinition] {
        guard provider.supportsToolCalling else { return [] }
        let localOnlyMode = store.preferences.localOnlyMode ?? true

        return store.toolConfigurations
            .filter { tool in
                tool.isEnabled
                    && tool.permissionPolicy != .deny
                    && !(localOnlyMode && tool.requiresNetwork)
            }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map { tool in
                ChatToolDefinition(
                    name: tool.kind.chatFunctionName,
                    description: tool.chatToolDescription,
                    argumentDescription: tool.chatToolArgumentDescription,
                    inputSchema: tool.chatToolInputSchema
                )
            }
    }

    private func estimatedCostMicros(
        provider: ProviderConfiguration?,
        inputTokens: Int,
        outputTokens: Int
    ) -> Int? {
        ProviderCostEstimator.shared.estimatedCostMicros(
            provider: provider,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    private func toggleMessagePin(_ message: AssistantMessage) {
        if store.isMessagePinned(message.id, in: store.selectedAssistantThreadID) {
            store.unpinMessage(message.id, in: store.selectedAssistantThreadID)
        } else {
            _ = store.pinMessage(message.id, in: store.selectedAssistantThreadID)
        }
        persistQuietly()
    }

    private func copyMessage(_ message: AssistantMessage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.shareText, forType: .string)
    }

    private func exportCurrentThread(as format: ChatExportFormat) {
        guard let thread = store.currentAssistantThread else { return }

        do {
            let service = ChatExportService()
            let data = try service.export(thread: thread, format: format)
            let panel = NSSavePanel()
            panel.title = "Export Chat"
            panel.nameFieldStringValue = service.defaultFilename(for: thread, format: format)
            panel.allowedContentTypes = [format.contentType]
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK,
                  let url = panel.url else { return }

            try data.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Chat export failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func exportWorkspaceSnapshot() {
        do {
            let service = WorkspaceSnapshotService()
            let data = try service.export(store: store)
            let panel = NSSavePanel()
            panel.title = "Export Workspace Snapshot"
            panel.nameFieldStringValue = service.defaultFilename(for: store)
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK,
                  let url = panel.url else { return }

            try data.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Workspace export failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func importWorkspaceSnapshot() {
        let panel = NSOpenPanel()
        panel.title = "Import Workspace Snapshot"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK,
              let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let result = try WorkspaceSnapshotService().importWorkspace(from: data)
            modelContext.insert(result.item)
            store.adoptWorkspace(result.item)
            try store.persist(in: modelContext)
            synchronizeKnowledgeSourceWatchers()
            withAnimation(.easeInOut(duration: 0.18)) {
                sidebarSurface = .conversation
                columnVisibility = store.preferences.showsRightSidebar ? .all : .doubleColumn
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Workspace import failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func importChat() {
        let panel = NSOpenPanel()
        panel.title = "Import Chat"
        panel.allowedContentTypes = ChatImportFormat.allowedContentTypes
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK,
              let url = panel.url else { return }

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
                    let data = try Data(contentsOf: url)
                    return try ChatImportService().importThread(
                        from: data,
                        sourceURL: url,
                        contentType: contentType
                    )
                }.value

                _ = store.importAssistantThread(result.thread)
                store.searchText = ""
                withAnimation(.easeInOut(duration: 0.18)) {
                    sidebarSurface = .conversation
                    columnVisibility = store.preferences.showsRightSidebar ? .all : .doubleColumn
                }
                persistQuietly()
                presentChatImportWarnings(result.warnings)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "Chat import failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    private func presentChatImportWarnings(_ warnings: [String]) {
        guard !warnings.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Chat imported with limited fidelity"
        alert.informativeText = warnings.joined(separator: "\n\n")
        alert.runModal()
    }

    private func retryFromMessage(_ message: AssistantMessage) {
        guard let draft = store.rewindThreadForRetry(from: message.id, in: store.selectedAssistantThreadID) else { return }
        composerText = draft.prompt
        composerAttachments = draft.attachments
        persistQuietly()
        sendMessage()
    }

    private func editMessage(_ message: AssistantMessage) {
        guard let draft = store.rewindThreadForRetry(from: message.id, in: store.selectedAssistantThreadID) else { return }
        composerText = draft.prompt
        composerAttachments = draft.attachments
        persistQuietly()
    }

    private func compareCurrentPrompt() {
        let prompt = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        comparisonPrompt = prompt
        runModelComparison()
    }

    private func forkThreadFromMessage(_ message: AssistantMessage) {
        guard store.forkThread(from: message.id, in: store.selectedAssistantThreadID) != nil else { return }
        store.selectedDestination = .home
        persistQuietly()
    }

    private func cancelStreaming() {
        let messageID = activeStreamingMessageID
        let threadID = activeStreamingThreadID
        streamingTask?.cancel()
        streamingTask = nil
        if let messageID, let threadID {
            stopStreamingMessage(messageID, in: threadID)
        } else {
            isStreamingResponse = false
            activeStreamingMessageID = nil
            activeStreamingThreadID = nil
        }
    }

    private func stopStreamingMessage(_ messageID: UUID, in threadID: UUID) {
        let existingText = store.assistantMessageText(messageID, in: threadID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stoppedText = existingText.isEmpty
            ? "Response stopped before any tokens arrived."
            : "\(existingText)\n\nResponse stopped."

        store.updateAssistantMessage(messageID, in: threadID, text: stoppedText)
        if let threadIndex = store.assistantThreads.firstIndex(where: { $0.id == threadID }),
           let messageIndex = store.assistantThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }) {
            let completedAt = Date()
            let startedAt = store.assistantThreads[threadIndex].messages[messageIndex].startedAt
                ?? store.assistantThreads[threadIndex].messages[messageIndex].createdAt
            store.assistantThreads[threadIndex].messages[messageIndex].runStatus = .stopped
            store.assistantThreads[threadIndex].messages[messageIndex].completedAt = completedAt
            store.assistantThreads[threadIndex].messages[messageIndex].outputTokenCount = estimatedTokenCount(for: stoppedText)
            store.assistantThreads[threadIndex].messages[messageIndex].latencyMilliseconds = max(0, Int(completedAt.timeIntervalSince(startedAt) * 1_000))
            store.assistantThreads[threadIndex].messages[messageIndex].tokenCountsAreEstimated = true
            store.assistantThreads[threadIndex].messages[messageIndex].updatedAt = completedAt
            store.assistantThreads[threadIndex].updatedAt = completedAt
        }
        isStreamingResponse = false
        activeStreamingMessageID = nil
        activeStreamingThreadID = nil
        persistQuietly()
    }

    private func runModelComparison() {
        guard !isRunningComparison else { return }
        let prompt = comparisonPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let selectedIDs = selectedComparisonProviderIDs.isEmpty
            ? Set(store.defaultComparisonProviderIDs(limit: 3))
            : selectedComparisonProviderIDs
        let selectedProviders = store.runnableComparisonProviders
            .filter { selectedIDs.contains($0.id) }
            .prefix(4)
        let providers = Array(selectedProviders)
        let providerIDs = providers.map(\.id)
        guard providers.count >= 2 else { return }

        isRunningComparison = true
        comparisonTask?.cancel()
        comparisonTask = Task { @MainActor in
            let retrievalPacket = await store.localKnowledgeRetrievalPacketUsingConfiguredEmbeddings(
                for: prompt,
                knowledgeSourceIDs: store.currentThreadKnowledgeSourceScope()
            )
            let baseSystemPrompt = store.defaultSystemPrompt()
            let systemPrompt = [baseSystemPrompt, retrievalPacket.promptContext]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")

            guard let runID = store.createModelComparisonRun(
                prompt: prompt,
                providerIDs: providerIDs,
                systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
                citations: retrievalPacket.citations
            ) else {
                isRunningComparison = false
                comparisonTask = nil
                persistQuietly()
                return
            }

            selectedComparisonProviderIDs = Set(providerIDs)
            selectedComparisonRunID = runID
            selectedComparisonResultID = store.modelComparisonRuns.first(where: { $0.id == runID })?.results.first?.id
            persistQuietly()

            await withTaskGroup(of: Void.self) { group in
                for provider in providers {
                    group.addTask {
                        await streamComparisonResult(
                            runID: runID,
                            provider: provider,
                            prompt: prompt,
                            systemPrompt: systemPrompt,
                            responseCitationBlock: retrievalPacket.responseCitationBlock
                        )
                    }
                }
            }

            isRunningComparison = false
            comparisonTask = nil
            persistQuietly()
        }
    }

    private func cancelModelComparison() {
        comparisonTask?.cancel()
        comparisonTask = nil
        isRunningComparison = false

        guard let runID = selectedComparisonRunID ?? store.modelComparisonRuns.first?.id,
              let run = store.modelComparisonRuns.first(where: { $0.id == runID }) else {
            persistQuietly()
            return
        }

        let stoppedAt = Date()
        for result in run.results where result.status == .queued || result.status == .streaming {
            store.updateModelComparisonResult(
                runID: runID,
                providerID: result.providerID,
                status: .failed,
                text: result.text,
                errorMessage: "Stopped by user.",
                startedAt: result.startedAt ?? stoppedAt,
                completedAt: stoppedAt
            )
        }
        persistQuietly()
    }

    private func copyComparisonResult(_ result: ModelComparisonResult) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.text, forType: .string)
        selectedComparisonResultID = result.id
    }

    private func useComparisonResultProvider(_ result: ModelComparisonResult) {
        guard store.providerConfigurations.contains(where: { $0.id == result.providerID }) else { return }
        store.preferences.preferredProviderID = result.providerID
        selectedComparisonResultID = result.id
        store.selectedDestination = .home
        persistQuietly()
    }

    private func streamComparisonResult(
        runID: UUID,
        provider: ProviderConfiguration,
        prompt: String,
        systemPrompt: String,
        responseCitationBlock: String
    ) async {
        let startedAt = Date()
        await MainActor.run {
            store.updateModelComparisonResult(
                runID: runID,
                providerID: provider.id,
                status: .streaming,
                startedAt: startedAt
            )
        }

        var streamedText = ""
        var streamedUsage: ChatStreamUsage?
        var firstTokenLatencyMilliseconds: Int?
        do {
            let stream = ChatStreamingService().streamEvents(
                for: ChatStreamingRequest(
                    provider: provider,
                    messages: [AssistantMessage(role: .user, text: prompt)],
                    systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
                )
            )

            var charactersSinceUpdate = 0
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case .text(let token):
                    if firstTokenLatencyMilliseconds == nil, !token.isEmpty {
                        firstTokenLatencyMilliseconds = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
                    }
                    streamedText += token
                    charactersSinceUpdate += token.count
                    if charactersSinceUpdate >= 160 {
                        charactersSinceUpdate = 0
                        let snapshot = streamedText
                        await MainActor.run {
                            store.updateModelComparisonResult(
                                runID: runID,
                                providerID: provider.id,
                                status: .streaming,
                                text: snapshot,
                                startedAt: startedAt,
                                firstTokenLatencyMilliseconds: firstTokenLatencyMilliseconds
                            )
                        }
                    }
                case .usage(let usage):
                    streamedUsage = streamedUsage?.merged(with: usage) ?? usage
                case .toolCallDelta, .toolCallDeltas:
                    continue
                }
            }

            let finalText = streamedText.isEmpty
                ? "The provider returned an empty stream. Try a different model identifier or run local discovery again."
                : streamedText + responseCitationBlock
            let usage = streamedUsage
            await MainActor.run {
                store.updateModelComparisonResult(
                    runID: runID,
                    providerID: provider.id,
                    status: .completed,
                    text: finalText,
                    startedAt: startedAt,
                    completedAt: Date(),
                    inputTokenCount: usage?.inputTokens,
                    outputTokenCount: usage?.outputTokens,
                    latencyMilliseconds: usage?.latencyMilliseconds,
                    firstTokenLatencyMilliseconds: firstTokenLatencyMilliseconds,
                    tokenCountsAreEstimated: usage?.hasCompleteTokenCounts != true
                )
                persistQuietly()
            }
        } catch {
            let usage = streamedUsage
            await MainActor.run {
                store.updateModelComparisonResult(
                    runID: runID,
                    providerID: provider.id,
                    status: .failed,
                    text: streamedText,
                    errorMessage: error is CancellationError ? "Comparison stopped." : error.localizedDescription,
                    startedAt: startedAt,
                    completedAt: Date(),
                    inputTokenCount: usage?.inputTokens,
                    outputTokenCount: usage?.outputTokens,
                    latencyMilliseconds: usage?.latencyMilliseconds,
                    firstTokenLatencyMilliseconds: firstTokenLatencyMilliseconds,
                    tokenCountsAreEstimated: usage?.hasCompleteTokenCounts != true
                )
                persistQuietly()
            }
        }
    }

    private func boundedChatHistory(
        _ messages: [AssistantMessage],
        provider: ProviderConfiguration
    ) -> [AssistantMessage] {
        let contextWindow = provider.contextWindowTokens ?? 16_000
        let characterBudget = min(max(contextWindow * 3, 8_000), 64_000)
        let maxMessages = provider.accessMode == .subscriptionCLI ? 20 : 36
        var selected: [AssistantMessage] = []
        var usedCharacters = 0

        for message in messages.reversed() {
            let trimmedText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { continue }

            let messageCost = max(trimmedText.count, 1)
            if selected.count >= maxMessages || usedCharacters + messageCost > characterBudget {
                break
            }

            selected.append(message)
            usedCharacters += messageCost
        }

        return selected.reversed()
    }

    @discardableResult
    private func appendDeterministicResponse(
        for prompt: String,
        in threadID: UUID,
        updating messageID: UUID?,
        prefix: String = "",
        retrievalPacket: LocalKnowledgeRetrievalPacket? = nil
    ) -> UUID? {
        do {
            let result = try AssistantRuntime().run(
                AssistantRuntimeRequest(
                    prompt: prompt,
                    context: store.assistantContext,
                    selectedChips: contextChips,
                    provider: store.activeProvider
                )
            )
            let toolSummary = result.executedTools
                .map { "\($0.title): \($0.output)" }
                .joined(separator: "\n\n")
            let response = toolSummary.isEmpty
                ? "\(prefix)\(result.responseText)"
                : "\(prefix)\(result.responseText)\n\nTool results\n\(toolSummary)"
            let finalResponse = response + (retrievalPacket?.responseCitationBlock ?? "")

            if let messageID {
                store.updateAssistantMessage(
                    messageID,
                    in: threadID,
                    text: finalResponse,
                    citations: retrievalPacket?.citations
                )
                return messageID
            } else {
                return store.appendAssistantMessage(
                    finalResponse,
                    role: .assistant,
                    in: threadID,
                    citations: retrievalPacket?.citations ?? []
                )
            }
        } catch {
            let response = "\(prefix)Flannel could not run this request: \(error.localizedDescription)"
            if let messageID {
                store.updateAssistantMessage(
                    messageID,
                    in: threadID,
                    text: response,
                    citations: retrievalPacket?.citations
                )
                return messageID
            } else {
                return store.appendAssistantMessage(
                    response,
                    role: .assistant,
                    in: threadID,
                    citations: retrievalPacket?.citations ?? []
                )
            }
        }
    }

    private func discoverLocalModels() {
        guard !isDiscoveringModels else { return }
        isDiscoveringModels = true

        Task {
            let results = await LocalProviderDiscoveryService().discover(
                targets: store.localProviderDiscoveryTargets()
            )
            await MainActor.run {
                store.apply(results)
                isDiscoveringModels = false
                persistQuietly()
            }
        }
    }

    private var contextChips: [AssistantContextChip] {
        [
            AssistantContextChip(
                id: "provider",
                title: "Provider",
                detail: store.activeProvider?.displayName ?? "Local only",
                symbolName: "cpu",
                isSelected: true
            ),
            AssistantContextChip(
                id: "knowledge",
                title: "Knowledge",
                detail: "\(store.knowledgeSources.count) local sources",
                symbolName: "books.vertical",
                isSelected: true
            ),
            AssistantContextChip(
                id: "tools",
                title: "Tools",
                detail: "\(store.toolConfigurations.filter(\.isEnabled).count) enabled",
                symbolName: "wrench.and.screwdriver",
                isSelected: true
            )
        ]
    }

    private func persistQuietly() {
        do {
            try store.persist(in: modelContext)
            store.clearPersistenceIssue(matching: .save)
        } catch {
            store.recordPersistenceFailure(error, operation: .save)
        }
    }
}

extension View {
    func persistenceIssueAlert(store: WorkspaceStore, retrySave: @escaping () -> Void) -> some View {
        alert(
            Text(store.persistenceIssue?.operation.title ?? "Local storage needs attention"),
            isPresented: Binding(
                get: { store.persistenceIssue != nil },
                set: { isPresented in
                    if !isPresented {
                        store.clearPersistenceIssue()
                    }
                }
            )
        ) {
            if store.persistenceIssue?.operation == .save {
                Button("Retry Save", action: retrySave)
            }
            Button("Dismiss", role: .cancel) {
                store.clearPersistenceIssue()
            }
        } message: {
            Text(store.persistenceIssue?.detailText ?? "Flannel could not complete a local storage operation.")
        }
    }
}

private enum SidebarThreadDateBucket: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case previousSevenDays
    case older

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            "Today"
        case .yesterday:
            "Yesterday"
        case .previousSevenDays:
            "Previous 7 Days"
        case .older:
            "Older"
        }
    }
}

private struct SidebarThreadDateSection: Identifiable {
    var bucket: SidebarThreadDateBucket
    var threads: [AssistantThread]

    var id: SidebarThreadDateBucket { bucket }
    var title: String { bucket.title }
}

private struct AppSidebar: View {
    @Bindable var store: WorkspaceStore
    var sidebarSurface: FlannelSidebarSurface
    @Binding var selectedSettingsTab: SettingsTab
    var searchFocusRequest: Int
    var settingsFocusRequest: Int
    var newChat: (ChatTemplate?, UUID?) -> Void
    var enterSettings: (SettingsTab) -> Void
    var exitSettings: () -> Void
    var persist: () -> Void
    @State private var scope: ChatHistoryScope = .active
    @State private var selectedFolderID: UUID?
    @State private var selectedTagName: String?
    @State private var selectedProviderDisplayName: String?
    @State private var selectedModelIdentifier: String?
    @State private var selectedProjectFilterID: UUID?
    @State private var selectedDateFilter: ChatHistoryDateFilter = .all

    private var query: String {
        store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleThreads: [AssistantThread] {
        filterBySelectedTag(filterBySelectedFolder(baseScopedThreads))
    }

    private var visibleSearchResults: [AssistantChatSearchResult] {
        store.searchChats(
            query,
            includeArchived: true,
            filters: chatHistoryFilters
        )
        .filter { result in
            guard matchesSelectedFolder(result.threadID) else { return false }
            guard matchesSelectedTag(result.threadID) else { return false }
            switch scope {
            case .active:
                return !result.isArchived
            case .archived:
                return result.isArchived
            }
        }
    }

    private var chatHistoryFilters: ChatHistoryFilters {
        ChatHistoryFilters(
            providerDisplayName: selectedProviderDisplayName,
            modelIdentifier: selectedModelIdentifier,
            projectID: selectedProjectFilterID,
            dateFilter: selectedDateFilter
        )
    }

    private var baseScopedThreads: [AssistantThread] {
        let filteredThreads = store.chatHistoryThreads(
            includeArchived: true,
            filters: chatHistoryFilters
        )

        switch scope {
        case .active:
            return filteredThreads.filter { !store.archivedAssistantThreadIDs.contains($0.id) }
        case .archived:
            return filteredThreads.filter { store.archivedAssistantThreadIDs.contains($0.id) }
        }
    }

    private var availableProviderFilters: [String] {
        filterOptions(from: store.assistantThreads.flatMap { thread in
            thread.messages.compactMap(\.providerDisplayName)
        })
    }

    private var availableModelFilters: [String] {
        filterOptions(from: store.assistantThreads.flatMap { thread in
            thread.messages.compactMap(\.modelIdentifier)
        })
    }

    private var availableProjectFilters: [WorkspaceProject] {
        store.projects.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var activeAdvancedFilterCount: Int {
        [
            selectedProviderDisplayName != nil,
            selectedModelIdentifier != nil,
            selectedProjectFilterID != nil,
            selectedDateFilter != .all
        ].filter { $0 }.count
    }

    private var activeSidebarRefinementCount: Int {
        activeAdvancedFilterCount
            + (scope == .archived ? 1 : 0)
            + (selectedFolderTitle == nil ? 0 : 1)
            + (selectedTagTitle == nil ? 0 : 1)
    }

    private var activeAdvancedFilterSummary: String {
        if activeAdvancedFilterCount == 0 {
            return "Filters"
        }

        if activeAdvancedFilterCount > 1 {
            return "\(activeAdvancedFilterCount) filters"
        }

        if let selectedProviderDisplayName {
            return selectedProviderDisplayName
        }

        if let selectedModelIdentifier {
            return selectedModelIdentifier
        }

        if let selectedProjectFilterID,
           let project = store.projects.first(where: { $0.id == selectedProjectFilterID }) {
            return project.title
        }

        return selectedDateFilter.title
    }

    private var selectedFolderTitle: String? {
        guard let selectedFolderID,
              selectedFolderIsAvailable else {
            return nil
        }
        return store.chatFolders.first(where: { $0.id == selectedFolderID })?.title
    }

    private var selectedTagTitle: String? {
        guard let selectedTagName,
              selectedTagIsAvailable else {
            return nil
        }
        return selectedTagName
    }

    private var sidebarRefinementSummary: String {
        if activeSidebarRefinementCount == 0 {
            return "All active chats"
        }

        if activeSidebarRefinementCount > 1 {
            return "\(activeSidebarRefinementCount) refinements"
        }

        if scope == .archived {
            return "Archived"
        }

        if let selectedFolderTitle {
            return selectedFolderTitle
        }

        if let selectedTagTitle {
            return selectedTagTitle
        }

        return activeAdvancedFilterSummary
    }

    private var sidebarHeaderTitle: String {
        if !query.isEmpty {
            return "Search"
        }
        return scope == .archived ? "Archived Chats" : "Chats"
    }

    private var sidebarHeaderDetail: String {
        if !query.isEmpty {
            let matchCount = visibleSearchResults.count
            return matchCount == 1 ? "1 match" : "\(matchCount) matches"
        }

        let chatCount = visibleThreads.count
        let chatSummary = chatCount == 1 ? "1 chat" : "\(chatCount) chats"
        if activeSidebarRefinementCount == 0 {
            return chatSummary
        }
        return "\(chatSummary) • \(sidebarRefinementSummary)"
    }

    private var folderRows: [(folder: ChatFolder, depth: Int)] {
        flattenedFolders(parentID: nil, depth: 0)
    }

    private var sortedVisibleThreads: [AssistantThread] {
        visibleThreads.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private var pinnedVisibleThreads: [AssistantThread] {
        sortedVisibleThreads.filter(isThreadPinned)
    }

    private var recentVisibleSections: [SidebarThreadDateSection] {
        let groupedThreads = Dictionary(grouping: sortedVisibleThreads.filter { !isThreadPinned($0) }) { thread in
            bucket(for: thread.updatedAt)
        }

        return SidebarThreadDateBucket.allCases.compactMap { bucket in
            guard let threads = groupedThreads[bucket],
                  !threads.isEmpty else { return nil }
            return SidebarThreadDateSection(bucket: bucket, threads: threads)
        }
    }

    private var selectedFolderIsAvailable: Bool {
        guard let selectedFolderID else { return true }
        return store.chatFolders.contains(where: { $0.id == selectedFolderID })
    }

    private var selectedTagIsAvailable: Bool {
        guard let selectedTagName else { return true }
        return store.tags.contains { $0.name == selectedTagName }
    }

    private var selectedThreadListBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedAssistantThreadID },
            set: { selectedThreadID in
                guard let selectedThreadID else {
                    store.selectedAssistantThreadID = nil
                    persist()
                    return
                }
                guard let thread = store.assistantThreads.first(where: { $0.id == selectedThreadID }) else {
                    store.selectedAssistantThreadID = nil
                    persist()
                    return
                }

                open(thread)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if sidebarSurface == .settings {
                SettingsSidebar(
                    selectedTab: $selectedSettingsTab,
                    focusRequest: settingsFocusRequest,
                    exitSettings: exitSettings
                )
                .transition(.opacity)
            } else {
                conversationSidebar
                    .transition(.opacity)
            }

            if sidebarSurface.showsConversationFooter {
                SidebarFooter(
                    provider: store.activeProvider,
                    localOnlyMode: store.preferences.localOnlyMode ?? true,
                    allowCloudProviders: store.preferences.allowCloudProviders ?? false,
                    openModels: { enterSettings(.models) },
                    openSettings: { enterSettings(.general) }
                )
                .transition(.opacity)
            }
        }
    }

    private var conversationSidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: FlannelSpacing.sidebarSectionSpacing) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sidebarHeaderTitle)
                            .font(.title3.weight(.semibold))

                        Text(sidebarHeaderDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 8)

                    newChatControl
                }
                sidebarSearchField
                sidebarRefinementControl
            }
            .padding(FlannelSpacing.sidebarInset)
            .padding(.top, FlannelSpacing.sidebarInset)
            .padding(.bottom, 10)

            List(selection: selectedThreadListBinding) {
                if query.isEmpty {
                    if visibleThreads.isEmpty {
                        EmptyState(
                            icon: scope == .archived ? "archivebox" : "bubble.left.and.bubble.right",
                            title: emptyThreadTitle,
                            detail: emptyThreadDetail
                        )
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    } else {
                        if !pinnedVisibleThreads.isEmpty {
                            Section("Favorites") {
                                ForEach(pinnedVisibleThreads) { thread in
                                    threadRow(thread)
                                        .tag(thread.id)
                                }
                            }
                        }

                        ForEach(recentVisibleSections) { section in
                            Section(scope == .archived ? "Archived \(section.title)" : section.title) {
                                ForEach(section.threads) { thread in
                                    threadRow(thread)
                                        .tag(thread.id)
                                }
                            }
                        }
                    }
                } else if visibleSearchResults.isEmpty {
                    EmptyState(
                        icon: "magnifyingglass",
                        title: "No matches",
                        detail: "Search thread titles, messages, attachments, or citations."
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                } else {
                    Section("\(visibleSearchResults.count) matches") {
                        ForEach(visibleSearchResults) { result in
                            SidebarSearchResultRow(
                                result: result,
                                isSelected: store.selectedAssistantThreadID == result.threadID,
                                choose: { openSearchResult(result) },
                                archiveToggle: { toggleArchive(result.threadID) }
                            )
                            .tag(result.threadID)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .padding(.top, 2)
        }
    }

    private var sidebarSearchField: some View {
        NativeSidebarSearchField(
            text: $store.searchText,
            placeholder: "Search chats",
            focusRequest: searchFocusRequest
        )
        .frame(height: 28)
        .accessibilityLabel("Search chats")
    }

    @ViewBuilder
    private var newChatControl: some View {
        if store.chatTemplates.isEmpty {
            Button {
                createChat()
            } label: {
                SidebarCommandLabel(title: "New Chat", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("New Chat")
            .accessibilityLabel("New Chat")
        } else {
            Menu {
                Button {
                    createChat()
                } label: {
                    Label("Blank Chat", systemImage: "bubble.left.and.bubble.right")
                }

                Section("Templates") {
                    ForEach(store.chatTemplates) { template in
                        Button {
                            createChat(from: template)
                        } label: {
                            Label(template.title, systemImage: template.isPinned ? "star" : "sparkles")
                        }
                    }
                }
            } label: {
                SidebarCommandLabel(title: "New Chat", systemImage: "square.and.pencil")
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .help("New Chat")
            .accessibilityLabel("New Chat")
        }
    }

    private var sidebarRefinementControl: some View {
        HStack(spacing: 8) {
            Menu {
                Section("History") {
                    ForEach(ChatHistoryScope.allCases) { option in
                        Button {
                            scope = option
                        } label: {
                            Label(option.rawValue, systemImage: scope == option ? "checkmark" : option.icon)
                        }
                    }
                }

                Section("Provider") {
                    Button {
                        selectedProviderDisplayName = nil
                    } label: {
                        Label("Any Provider", systemImage: selectedProviderDisplayName == nil ? "checkmark" : "cpu")
                    }

                    ForEach(availableProviderFilters, id: \.self) { provider in
                        Button {
                            selectedProviderDisplayName = provider
                        } label: {
                            Label(provider, systemImage: selectedProviderDisplayName == provider ? "checkmark" : "cpu")
                        }
                    }
                }

                Section("Model") {
                    Button {
                        selectedModelIdentifier = nil
                    } label: {
                        Label("Any Model", systemImage: selectedModelIdentifier == nil ? "checkmark" : "memorychip")
                    }

                    ForEach(availableModelFilters, id: \.self) { model in
                        Button {
                            selectedModelIdentifier = model
                        } label: {
                            Label(model, systemImage: selectedModelIdentifier == model ? "checkmark" : "memorychip")
                        }
                    }
                }

                Section("Project") {
                    Button {
                        selectedProjectFilterID = nil
                    } label: {
                        Label("Any Project", systemImage: selectedProjectFilterID == nil ? "checkmark" : "rectangle.stack")
                    }

                    ForEach(availableProjectFilters) { project in
                        Button {
                            selectedProjectFilterID = project.id
                        } label: {
                            Label(project.title, systemImage: selectedProjectFilterID == project.id ? "checkmark" : "rectangle.stack")
                        }
                    }
                }

                Section("Date") {
                    ForEach(ChatHistoryDateFilter.allCases) { filter in
                        Button {
                            selectedDateFilter = filter
                        } label: {
                            Label(filter.title, systemImage: selectedDateFilter == filter ? "checkmark" : filter.icon)
                        }
                    }
                }

                if !folderRows.isEmpty {
                    Section("Folders") {
                        Button {
                            selectedFolderID = nil
                        } label: {
                            Label("All Folders", systemImage: selectedFolderID == nil || !selectedFolderIsAvailable ? "checkmark" : "tray.full")
                        }

                        ForEach(folderRows, id: \.folder.id) { row in
                            Button {
                                selectedFolderID = row.folder.id
                            } label: {
                                Label(
                                    row.folder.title,
                                    systemImage: selectedFolderID == row.folder.id ? "checkmark" : row.folder.symbolName
                                )
                            }
                        }
                    }
                }

                if !store.tags.isEmpty {
                    Section("Tags") {
                        Button {
                            selectedTagName = nil
                        } label: {
                            Label("All Tags", systemImage: selectedTagName == nil || !selectedTagIsAvailable ? "checkmark" : "tag")
                        }

                        ForEach(store.tags) { tag in
                            Button {
                                selectedTagName = tag.name
                            } label: {
                                Label(tag.name, systemImage: selectedTagName == tag.name ? "checkmark" : "tag")
                            }
                        }
                    }
                }

                if activeSidebarRefinementCount > 0 {
                    Divider()

                    Button {
                        clearSidebarRefinements()
                    } label: {
                        Label("Clear Refinements", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Label("Refine", systemImage: "line.3.horizontal.decrease.circle")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .help("Refine chat history by archive state, folder, tag, provider, model, project, or date")
            .accessibilityLabel("Refine chats: \(sidebarRefinementSummary)")

            Spacer(minLength: 6)

            Text(sidebarRefinementSummary)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if activeSidebarRefinementCount > 0 {
                Text(activeSidebarRefinementCount.formatted())
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            if activeSidebarRefinementCount > 0 {
                Button {
                    clearSidebarRefinements()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .help("Clear chat refinements")
                .accessibilityLabel("Clear chat refinements")
            }
        }
        .font(.caption)
        .padding(.horizontal, 2)
    }

    private func threadRow(_ thread: AssistantThread) -> some View {
        SidebarThreadRow(
            thread: thread,
            isSelected: store.selectedAssistantThreadID == thread.id,
            isArchived: store.archivedAssistantThreadIDs.contains(thread.id),
            isPinned: isThreadPinned(thread),
            folder: store.folder(for: thread),
            folders: folderRows.map { $0.folder },
            tags: store.tags,
            choose: { open(thread) },
            archiveToggle: { toggleArchive(thread.id) },
            pinToggle: { togglePin(thread.id) },
            assignFolder: { folderID in
                _ = store.assignThread(thread.id, toFolder: folderID)
                persist()
            },
            addTag: { tagName in
                store.applyTags([tagName], threadID: thread.id)
                persist()
            },
            removeTag: { tagName in
                _ = store.removeTag(tagName, fromThread: thread.id)
                if selectedTagName == tagName && !selectedTagIsAvailable {
                    selectedTagName = nil
                }
                persist()
            }
        )
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
    }

    private var emptyThreadTitle: String {
        if chatHistoryFilters.isActive {
            return "No chats match filters"
        }
        if selectedFolderID != nil && selectedFolderIsAvailable {
            return scope == .archived ? "No archived chats in folder" : "No chats in folder"
        }
        return scope == .archived ? "No archived chats" : "No chats yet"
    }

    private var emptyThreadDetail: String {
        if chatHistoryFilters.isActive {
            return "Clear provider, model, project, or date filters to broaden the chat history."
        }
        if selectedTagName != nil && selectedTagIsAvailable {
            return "No chats match this tag in the current history filter."
        }
        if selectedFolderID != nil && selectedFolderIsAvailable {
            return scope == .archived
                ? "Archived conversations assigned to this folder stay searchable here."
                : "Start a chat while this folder is selected, or move existing chats here from their row menu."
        }
        return scope == .archived
            ? "Archived conversations stay searchable here."
            : "Start a chat to keep the workspace moving."
    }

    private func filterBySelectedFolder(_ threads: [AssistantThread]) -> [AssistantThread] {
        guard let selectedFolderID,
              selectedFolderIsAvailable else {
            return threads
        }
        return threads.filter { $0.folderID == selectedFolderID }
    }

    private func filterBySelectedTag(_ threads: [AssistantThread]) -> [AssistantThread] {
        guard let selectedTagName,
              selectedTagIsAvailable else {
            return threads
        }
        return threads.filter { thread in
            thread.tagNames.contains(selectedTagName)
        }
    }

    private func filterOptions(from values: [String]) -> [String] {
        Array(Set(values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }))
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func clearAdvancedFilters() {
        selectedProviderDisplayName = nil
        selectedModelIdentifier = nil
        selectedProjectFilterID = nil
        selectedDateFilter = .all
    }

    private func clearSidebarRefinements() {
        scope = .active
        selectedFolderID = nil
        selectedTagName = nil
        clearAdvancedFilters()
    }

    private func isThreadPinned(_ thread: AssistantThread) -> Bool {
        thread.isPinned || store.pinnedMessages.contains { $0.threadID == thread.id }
    }

    private func bucket(for date: Date) -> SidebarThreadDateBucket {
        let calendar = Calendar.autoupdatingCurrent
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfPreviousSevenDays = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfYesterday

        if date >= startOfToday {
            return .today
        }
        if date >= startOfYesterday {
            return .yesterday
        }
        if date >= startOfPreviousSevenDays {
            return .previousSevenDays
        }
        return .older
    }

    private func matchesSelectedFolder(_ threadID: UUID) -> Bool {
        guard let selectedFolderID,
              selectedFolderIsAvailable else {
            return true
        }
        return store.assistantThreads.first(where: { $0.id == threadID })?.folderID == selectedFolderID
    }

    private func matchesSelectedTag(_ threadID: UUID) -> Bool {
        guard let selectedTagName,
              selectedTagIsAvailable else {
            return true
        }
        return store.assistantThreads.first(where: { $0.id == threadID })?.tagNames.contains(selectedTagName) == true
    }

    private func flattenedFolders(parentID: UUID?, depth: Int) -> [(folder: ChatFolder, depth: Int)] {
        store.chatFolders
            .filter { $0.parentID == parentID }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .flatMap { folder in
                [(folder, depth)] + flattenedFolders(parentID: folder.id, depth: depth + 1)
            }
    }

    private func open(_ thread: AssistantThread) {
        store.selectedAssistantThreadID = thread.id
        store.selectedDestination = .home
        persist()
    }

    private func createChat(from template: ChatTemplate? = nil) {
        let folderID = selectedFolderIsAvailable ? selectedFolderID : nil
        newChat(template, folderID)
    }

    private func openSearchResult(_ result: AssistantChatSearchResult) {
        store.selectedAssistantThreadID = result.threadID
        store.selectedDestination = .home
        persist()
    }

    private func toggleArchive(_ threadID: UUID) {
        if store.archivedAssistantThreadIDs.contains(threadID) {
            _ = store.unarchiveThread(threadID)
        } else {
            _ = store.archiveThread(threadID)
        }
        persist()
    }

    private func togglePin(_ threadID: UUID) {
        if store.assistantThreads.first(where: { $0.id == threadID })?.isPinned == true {
            _ = store.unpinThread(threadID)
        } else {
            _ = store.pinThread(threadID)
        }
        persist()
    }
}

private struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab
    var focusRequest: Int
    var exitSettings: () -> Void
    @FocusState private var isExitSettingsFocused: Bool

    private var selection: Binding<SettingsTab?> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if let newValue {
                    selectedTab = newValue
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: exitSettings) {
                    Label("Back to Chats", systemImage: "chevron.left")
                        .font(.callout.weight(.medium))
                        .labelStyle(.titleAndIcon)
                        .symbolRenderingMode(.hierarchical)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .focused($isExitSettingsFocused)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Return to chat")
                .accessibilityLabel("Back to Chats")
                .accessibilityHint("Returns the sidebar to chat history and restores the chat surface.")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.title3.weight(.semibold))
                    Text("Choose a settings route in this sidebar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .flannelSeparator(edge: .bottom, inset: 14, opacity: 0.4)

            List(selection: selection) {
                ForEach(SettingsNavigationSection.allCases) { section in
                    Section(section.title) {
                        settingsRows(section.tabs)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(maxHeight: .infinity)
        .onAppear(perform: focusExitSettingsIfRequested)
        .onChange(of: focusRequest) { _, _ in
            focusExitSettingsIfRequested()
        }
    }

    private func focusExitSettingsIfRequested() {
        guard focusRequest > 0 else { return }
        DispatchQueue.main.async {
            isExitSettingsFocused = true
        }
    }

    @ViewBuilder
    private func settingsRows(_ tabs: [SettingsTab]) -> some View {
        ForEach(tabs) { tab in
            SettingsRouteRow(tab: tab, isSelected: selectedTab == tab)
                .tag(tab)
        }
    }
}

private struct SettingsRouteRow: View {
    var tab: SettingsTab
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: tab.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(tab.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint(tab.detail)
    }
}

private struct NativeSidebarSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = SidebarSearchField()
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .default
        searchField.controlSize = .regular
        searchField.font = .preferredFont(forTextStyle: .body)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.windowChangeHandler = { [weak coordinator = context.coordinator] in
            coordinator?.focusIfPossible()
        }
        context.coordinator.searchField = searchField
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.text = $text
        searchField.placeholderString = placeholder

        if searchField.stringValue != text {
            searchField.stringValue = text
        }

        guard focusRequest > 0 else { return }
        context.coordinator.requestFocus(focusRequest, searchField: searchField)
    }

    final class SidebarSearchField: NSSearchField {
        var windowChangeHandler: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowChangeHandler?()
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        weak var searchField: NSSearchField?
        private var pendingFocusRequest = 0
        private var handledFocusRequest = 0

        init(text: Binding<String>) {
            self.text = text
        }

        func requestFocus(_ focusRequest: Int, searchField: NSSearchField) {
            guard focusRequest != handledFocusRequest else { return }
            pendingFocusRequest = focusRequest
            self.searchField = searchField
            DispatchQueue.main.async { [weak self] in
                self?.focusIfPossible()
            }
        }

        func focusIfPossible() {
            guard pendingFocusRequest != handledFocusRequest,
                  let searchField,
                  let window = searchField.window,
                  window.makeFirstResponder(searchField) else {
                return
            }
            handledFocusRequest = pendingFocusRequest
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            text.wrappedValue = searchField.stringValue
        }

        func searchFieldDidEndSearching(_ sender: NSSearchField) {
            text.wrappedValue = sender.stringValue
        }
    }
}

private struct SidebarCommandLabel: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.hierarchical)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05), in: Capsule())
            .contentShape(Capsule())
    }
}

private struct SidebarFooter: View {
    var provider: ProviderConfiguration?
    var localOnlyMode: Bool
    var allowCloudProviders: Bool
    var openModels: () -> Void
    var openSettings: () -> Void

    private var providerStatusTitle: String {
        if let provider {
            return provider.providerModeChoiceTitle
        }
        return "No active model"
    }

    private var providerStatusDetail: String {
        if let provider {
            return provider.accessMode.title
        }

        if localOnlyMode {
            return "Choose Ollama or LM Studio"
        }

        return allowCloudProviders ? "Cloud routes allowed" : "Cloud routes blocked"
    }

    private var privacyTitle: String {
        if localOnlyMode {
            return "Local-only"
        }

        if provider?.privacyScope == .externalAPI {
            return allowCloudProviders ? "External API" : "Cloud blocked"
        }

        return provider?.privacyScope.title ?? "Private"
    }

    private var privacyIcon: String {
        if localOnlyMode {
            return "lock.fill"
        }

        if provider?.privacyScope == .externalAPI {
            return allowCloudProviders ? "network" : "network.slash"
        }

        return provider?.privacyScope == .localCLI ? "terminal" : "lock"
    }

    private var privacyTone: FlannelStatusTone {
        if localOnlyMode {
            return .accent
        }

        if provider?.privacyScope == .externalAPI {
            return allowCloudProviders ? .warning : .danger
        }

        return provider == nil ? .warning : .neutral
    }

    private var footerHint: String {
        if localOnlyMode {
            return "Local-only routing"
        }
        return allowCloudProviders ? "Cloud routes available" : "Cloud routes blocked"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SidebarFooterRow(
                title: "Models & Providers",
                detail: providerStatusTitle,
                caption: providerStatusDetail,
                systemImage: provider == nil ? "exclamationmark.triangle" : "cpu",
                tint: provider == nil ? .orange : .secondary,
                action: openModels
            ) {
                FlannelStatusChip(
                    privacyTitle,
                    systemImage: privacyIcon,
                    tone: privacyTone,
                    prominence: .subtle
                )
            }

            SidebarFooterRow(
                title: "Settings",
                detail: "General, privacy, tools",
                caption: footerHint,
                systemImage: "gearshape",
                tint: .secondary,
                action: openSettings
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .flannelSeparator(edge: .top, inset: 12, opacity: 0.48)
    }
}

private struct SidebarFooterRow<Trailing: View>: View {
    var title: String
    var detail: String
    var caption: String
    var systemImage: String
    var tint: Color
    var action: () -> Void
    private let trailing: Trailing

    init(
        title: String,
        detail: String,
        caption: String,
        systemImage: String,
        tint: Color = .secondary,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.detail = detail
        self.caption = caption
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.medium))
                    .frame(width: 18)
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("\(detail) • \(caption)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                trailing

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue("\(detail), \(caption)")
    }
}

private struct SidebarThreadRow: View {
    var thread: AssistantThread
    var isSelected: Bool
    var isArchived: Bool
    var isPinned: Bool
    var folder: ChatFolder?
    var folders: [ChatFolder]
    var tags: [WorkspaceTag]
    var choose: () -> Void
    var archiveToggle: () -> Void
    var pinToggle: () -> Void
    var assignFolder: (UUID?) -> Void
    var addTag: (String) -> Void
    var removeTag: (String) -> Void
    @State private var isHovering = false

    private var showsQuickActions: Bool {
        isHovering || isSelected
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    private var rowBackgroundStyle: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(FlannelSystemColor.sidebarSelectionTint)
        }

        if isHovering {
            return AnyShapeStyle(Color.primary.opacity(0.045))
        }

        return AnyShapeStyle(Color.clear)
    }

    private var lastMessagePreview: String? {
        guard let lastMessage = thread.messages.last(where: { $0.role != .system }) else {
            return nil
        }
        let preview = lastMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? nil : preview
    }

    private var updatedTimeText: String {
        thread.updatedAt.formatted(date: .omitted, time: .shortened)
    }

    private var accessibilityLabelText: String {
        var parts = [thread.title]
        if isPinned {
            parts.append("Favorite")
        }
        if isArchived {
            parts.append("Archived")
        }
        if let folder {
            parts.append("Folder \(folder.title)")
        }
        parts.append("updated \(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))")
        return parts.joined(separator: ", ")
    }

    private var accessibilityValueText: String {
        var parts: [String] = []
        if let lastMessagePreview {
            parts.append(lastMessagePreview)
        }
        if !thread.tagNames.isEmpty {
            parts.append("Tags \(thread.tagNames.sorted().joined(separator: ", "))")
        }
        return parts.joined(separator: ". ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: choose) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: isArchived ? "archivebox" : "bubble.left")
                        .font(.callout)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(thread.title)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            if isPinned {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let lastMessagePreview {
                                Text(lastMessagePreview)
                                    .layoutPriority(1)
                            } else {
                                Text("Updated \(updatedTimeText)")
                            }

                            if lastMessagePreview != nil {
                                Text(updatedTimeText)
                                    .foregroundStyle(.tertiary)
                            }

                            if let folder {
                                CapsuleLabel(folder.title, icon: folder.symbolName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(metadataAccessibilityLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                    }

                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityValue(accessibilityValueText)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .help(lastMessagePreview ?? thread.title)

            HStack(spacing: 0) {
                SidebarThreadQuickAction(
                    title: isPinned ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isPinned ? "star.fill" : "star",
                    action: pinToggle
                )
                SidebarThreadQuickAction(
                    title: isArchived ? "Restore" : "Archive",
                    systemImage: isArchived ? "tray.and.arrow.up" : "archivebox",
                    action: archiveToggle
                )
            }
            .frame(width: 62)
            .opacity(showsQuickActions ? 1 : 0)
            .disabled(!showsQuickActions)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackgroundStyle, in: rowShape)
        .overlay {
            rowShape.strokeBorder(
                isSelected ? FlannelSystemColor.chromeStrokeStrong : Color.clear,
                lineWidth: FlannelSpacing.hairline
            )
        }
        .contentShape(rowShape)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: isPinned ? "Remove from Favorites" : "Add to Favorites", pinToggle)
        .accessibilityAction(named: isArchived ? "Restore" : "Archive", archiveToggle)
        .contextMenu {
            Button(action: pinToggle) {
                Label(isPinned ? "Remove from Favorites" : "Add to Favorites", systemImage: isPinned ? "star.slash" : "star")
            }
            Button(action: archiveToggle) {
                Label(isArchived ? "Restore" : "Archive", systemImage: isArchived ? "tray.and.arrow.up" : "archivebox")
            }

            if !folders.isEmpty {
                Divider()
                Menu("Move to Folder") {
                    Button("No Folder") {
                        assignFolder(nil)
                    }
                    ForEach(folders) { folder in
                        Button {
                            assignFolder(folder.id)
                        } label: {
                            Label(folder.title, systemImage: folder.symbolName)
                        }
                    }
                }
            }

            if !tags.isEmpty {
                Divider()
                Menu("Tags") {
                    let tagNames = tags.map(\.name)
                    ForEach(tagNames, id: \.self) { tagName in
                        if thread.tagNames.contains(tagName) {
                            Button {
                                removeTag(tagName)
                            } label: {
                                Label(tagName, systemImage: "checkmark")
                            }
                        } else {
                            Button(tagName) {
                                addTag(tagName)
                            }
                        }
                    }
                }
            }
        }
    }

    private var metadataAccessibilityLabel: String {
        var parts = [lastMessagePreview ?? "Updated \(updatedTimeText)"]
        if lastMessagePreview != nil {
            parts.append("Updated \(updatedTimeText)")
        }
        if let folder {
            parts.append("Folder \(folder.title)")
        }
        return parts.joined(separator: ", ")
    }
}

private struct SidebarThreadQuickAction: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 28, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .flannelGlassCapsule(.clear, interactive: true)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct SidebarSearchResultRow: View {
    var result: AssistantChatSearchResult
    var isSelected: Bool
    var choose: () -> Void
    var archiveToggle: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: result.matchKind.icon)
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(result.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        if result.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(result.matchKind.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if !result.snippet.isEmpty {
                        Text(result.snippet)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? FlannelSystemColor.sidebarSelectionTint : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button(result.isArchived ? "Restore" : "Archive", action: archiveToggle)
        }
    }
}

private struct SidebarProviderStatus: View {
    var provider: ProviderConfiguration?

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: provider?.privacyScope == .externalAPI ? "network" : "lock")
                .frame(width: 20)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(provider == nil ? .orange : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(provider?.displayName ?? "No runnable provider")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(provider?.accessMode.title ?? "Open Settings to configure models")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CommandPaletteOverlay: View {
    var commands: [FlannelCommand]
    @Binding var query: String
    var dismissPalette: () -> Void
    var run: (FlannelCommand) -> Void
    @FocusState private var isSearchFocused: Bool
    @State private var selectedID: FlannelCommandID?
    @State private var announcesSelectionChanges = false

    private var filteredCommands: [FlannelCommand] {
        commands.filter { $0.matches(query) }
    }

    private var selectedCommand: FlannelCommand? {
        filteredCommands.first { $0.id == selectedID } ?? filteredCommands.first(where: \.isEnabled)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.black.opacity(0.16))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("Search commands", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($isSearchFocused)
                        .accessibilityLabel("Search commands")
                        .accessibilityHint("Type to filter available Flannel commands.")
                        .onSubmit {
                            runSelectedCommand()
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                if filteredCommands.isEmpty {
                    EmptyState(
                        icon: "magnifyingglass",
                        title: "No commands",
                        detail: "Try a different action, surface, provider, or export name."
                    )
                    .padding(18)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredCommands) { command in
                                CommandPaletteRow(
                                    command: command,
                                    isSelected: selectedCommand?.id == command.id
                                ) {
                                    run(command)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 430)
                }
            }
            .frame(minWidth: 520, idealWidth: 640, maxWidth: 640)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(FlannelSystemColor.quietStroke, lineWidth: FlannelSpacing.hairline)
            }
            .shadow(color: .black.opacity(0.22), radius: 34, x: 0, y: 20)
            .padding(.horizontal, 28)
            .padding(.top, 86)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Command palette")
            .accessibilityAddTraits(.isModal)
        }
        .onAppear {
            selectedID = filteredCommands.first(where: \.isEnabled)?.id ?? filteredCommands.first?.id
            isSearchFocused = true
            DispatchQueue.main.async {
                announcesSelectionChanges = true
            }
        }
        .onChange(of: query) { _, _ in
            reconcileSelection()
        }
        .onChange(of: selectedID) { _, _ in
            announceSelectedCommandIfNeeded()
        }
        .onMoveCommand { direction in
            moveSelection(direction)
        }
        .onExitCommand {
            dismiss()
        }
    }

    private func runSelectedCommand() {
        guard let selectedCommand,
              selectedCommand.isEnabled else { return }
        run(selectedCommand)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !filteredCommands.isEmpty else { return }
        let enabledCommands = filteredCommands.filter(\.isEnabled)
        let navigableCommands = enabledCommands.isEmpty ? filteredCommands : enabledCommands
        let currentID = selectedCommand?.id ?? selectedID
        let currentIndex = navigableCommands.firstIndex { $0.id == currentID } ?? 0

        switch direction {
        case .down, .right:
            selectedID = navigableCommands[(currentIndex + 1) % navigableCommands.count].id
        case .up, .left:
            selectedID = navigableCommands[(currentIndex - 1 + navigableCommands.count) % navigableCommands.count].id
        @unknown default:
            break
        }
    }

    private func dismiss() {
        dismissPalette()
    }

    private func reconcileSelection() {
        let selectedIDIsVisible = filteredCommands.contains { $0.id == selectedID }
        if !selectedIDIsVisible || selectedCommand == nil || selectedCommand?.isEnabled == false {
            selectedID = filteredCommands.first(where: \.isEnabled)?.id ?? filteredCommands.first?.id
        }
    }

    private func announceSelectedCommandIfNeeded() {
        guard announcesSelectionChanges,
              let selectedCommand else { return }
        let availability = selectedCommand.isEnabled ? "" : " Unavailable."
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: "\(selectedCommand.title). \(selectedCommand.subtitle).\(availability)"]
        )
    }
}

private struct CommandPaletteRow: View {
    var command: FlannelCommand
    var isSelected: Bool
    var run: () -> Void

    var body: some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: command.systemImage)
                    .frame(width: 24)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(command.isEnabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(command.title)
                            .font(.callout.weight(.semibold))
                        Text(command.category)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.thinMaterial, in: Capsule())
                    }
                    Text(command.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if !command.isEnabled {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                        .help("Unavailable")
                } else if let keyEquivalent = command.keyEquivalent {
                    Text(keyEquivalent)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospaced()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!command.isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(command.accessibilityLabel)
        .accessibilityHint(commandAccessibilityHint)
        .accessibilityValue(isSelected ? "Selected" : "")
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.clear))
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: FlannelSpacing.hairline)
            }
        }
    }

    private var commandAccessibilityHint: String {
        guard command.isEnabled else {
            return "\(command.accessibilityHint) This command is unavailable in the current context."
        }
        return command.accessibilityHint
    }
}

private struct MainSurface: View {
    @Bindable var store: WorkspaceStore
    var sidebarSurface: FlannelSidebarSurface
    @Binding var selectedSettingsTab: SettingsTab
    @Binding var settingsSearchText: String
    @Binding var composerText: String
    @Binding var composerAttachments: [AIChatAttachment]
    @Binding var comparisonPrompt: String
    @Binding var selectedComparisonProviderIDs: Set<UUID>
    @Binding var selectedComparisonRunID: UUID?
    @Binding var selectedComparisonResultID: UUID?
    var composerFocusRequest: Int
    var isArtifactsVisible: Bool
    var isDiscoveringModels: Bool
    var isStreamingResponse: Bool
    var isRunningComparison: Bool
    var sendMessage: () -> Void
    var cancelStreaming: () -> Void
    var compareCurrentPrompt: () -> Void
    var runComparison: () -> Void
    var cancelComparison: () -> Void
    var toggleMessagePin: (AssistantMessage) -> Void
    var copyMessage: (AssistantMessage) -> Void
    var copyComparisonResult: (ModelComparisonResult) -> Void
    var useComparisonResultProvider: (ModelComparisonResult) -> Void
    var retryFromMessage: (AssistantMessage) -> Void
    var editMessage: (AssistantMessage) -> Void
    var forkThreadFromMessage: (AssistantMessage) -> Void
    var discoverModels: () -> Void
    var continueAfterToolResult: (LocalToolExecutionResult, AIToolCallRecord?) -> Void
    var openModelSetup: () -> Void
    var showArtifacts: () -> Void
    var exitSettings: () -> Void
    var importChat: () -> Void
    var exportWorkspaceSnapshot: () -> Void
    var importWorkspaceSnapshot: () -> Void
    var persist: () -> Void

    var body: some View {
        Group {
            switch sidebarSurface {
            case .conversation:
                ZStack(alignment: .trailing) {
                    ChatSurface(
                        store: store,
                        composerText: $composerText,
                        composerAttachments: $composerAttachments,
                        composerFocusRequest: composerFocusRequest,
                        isStreamingResponse: isStreamingResponse,
                        sendMessage: sendMessage,
                        cancelStreaming: cancelStreaming,
                        compareCurrentPrompt: compareCurrentPrompt,
                        toggleMessagePin: toggleMessagePin,
                        copyMessage: copyMessage,
                        retryFromMessage: retryFromMessage,
                        editMessage: editMessage,
                        forkThreadFromMessage: forkThreadFromMessage,
                        continueAfterToolResult: continueAfterToolResult,
                        openModelSetup: openModelSetup,
                        persist: persist
                    )

                    if !isArtifactsVisible {
                        CollapsedArtifactsRail(
                            store: store,
                            isRunningComparison: isRunningComparison,
                            showArtifacts: showArtifacts
                        )
                        .padding(.trailing, 10)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
            case .settings:
                SettingsSurface(
                    store: store,
                    persist: persist,
                    exitSettings: exitSettings,
                    importChat: importChat,
                    exportWorkspaceSnapshot: exportWorkspaceSnapshot,
                    importWorkspaceSnapshot: importWorkspaceSnapshot,
                    selectedTab: $selectedSettingsTab,
                    searchText: $settingsSearchText,
                    usesSidebarNavigation: false
                )
            }
        }
    }
}

private struct CollapsedArtifactsRail: View {
    @Bindable var store: WorkspaceStore
    var isRunningComparison: Bool
    var showArtifacts: () -> Void

    private var currentCitations: [AIChatCitation] {
        store.currentAssistantThread?.messages.flatMap(\.citations) ?? []
    }

    private var currentThreadToolResultIDs: Set<UUID> {
        Set(store.currentAssistantThread?.messages.flatMap(\.referencedEntityIDs) ?? [])
    }

    private var currentThreadToolResultCount: Int {
        store.toolExecutionResults.filter { currentThreadToolResultIDs.contains($0.id) }.count
    }

    private var comparisonCount: Int {
        max(store.modelComparisonRuns.count, isRunningComparison ? 1 : 0)
    }

    private var artifactSummaries: [CollapsedArtifactSummary] {
        [
            CollapsedArtifactSummary(
                title: "Sources",
                systemImage: FlannelInspectorSection.sources.icon,
                count: currentCitations.count
            ),
            CollapsedArtifactSummary(
                title: "Compare",
                systemImage: FlannelInspectorSection.compare.icon,
                count: comparisonCount
            ),
            CollapsedArtifactSummary(
                title: "Tools",
                systemImage: FlannelInspectorSection.tools.icon,
                count: currentThreadToolResultCount
            )
        ]
        .filter { $0.count > 0 }
    }

    private var accessibilitySummary: String {
        guard !artifactSummaries.isEmpty else {
            return "No artifacts yet"
        }

        return artifactSummaries
            .map { "\($0.title): \($0.count)" }
            .joined(separator: ", ")
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            Button(action: showArtifacts) {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 24, height: 24)

                    if artifactSummaries.isEmpty {
                        Image(systemName: "tray")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, height: 20)
                    } else {
                        FlannelSeparator(opacity: 0.38)
                            .frame(width: 24)

                        ForEach(artifactSummaries) { summary in
                            CollapsedArtifactBadge(summary: summary)
                        }
                    }
                }
                .padding(7)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .flannelChromePanel(cornerRadius: 18, interactive: true)
            .help("Show Artifacts")
            .accessibilityLabel("Show Artifacts")
            .accessibilityValue(accessibilitySummary)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct CollapsedArtifactSummary: Identifiable {
    var title: String
    var systemImage: String
    var count: Int

    var id: String { title }
}

private struct CollapsedArtifactBadge: View {
    var summary: CollapsedArtifactSummary

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: summary.systemImage)
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text(summary.count.formatted())
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 24)
        .frame(minHeight: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.title)
        .accessibilityValue(summary.count.formatted())
    }
}

private struct ChatTranscriptViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatTranscriptBottomYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatSurface: View {
    private static let transcriptScrollCoordinateSpace = "flannel.chat.transcript.scroll"
    private static let transcriptBottomAnchorID = "flannel.chat.transcript.bottom"
    private static let chatContentMaxWidth: CGFloat = 880

    @Bindable var store: WorkspaceStore
    @Binding var composerText: String
    @Binding var composerAttachments: [AIChatAttachment]
    var composerFocusRequest: Int
    var isStreamingResponse: Bool
    var sendMessage: () -> Void
    var cancelStreaming: () -> Void
    var compareCurrentPrompt: () -> Void
    var toggleMessagePin: (AssistantMessage) -> Void
    var copyMessage: (AssistantMessage) -> Void
    var retryFromMessage: (AssistantMessage) -> Void
    var editMessage: (AssistantMessage) -> Void
    var forkThreadFromMessage: (AssistantMessage) -> Void
    var continueAfterToolResult: (LocalToolExecutionResult, AIToolCallRecord?) -> Void
    var openModelSetup: () -> Void
    var persist: () -> Void
    @State private var transcriptSearchText = ""
    @State private var selectedTranscriptSearchIndex = 0
    @State private var isTranscriptSearchVisible = false
    @State private var transcriptSearchFocusRequest = 0
    @State private var composerFocusNonce = UUID()
    @State private var transcriptViewportHeight: CGFloat = 0
    @State private var isTranscriptPinnedToBottom = true
    @State private var announcedOffscreenMessageID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ChatThreadHeader(
                store: store,
                transcriptSearchText: $transcriptSearchText,
                isTranscriptSearchVisible: $isTranscriptSearchVisible,
                transcriptSearchMatchCount: transcriptSearchMatches.count,
                selectedTranscriptSearchPosition: selectedTranscriptSearchPosition,
                transcriptSearchFocusRequest: transcriptSearchFocusRequest,
                revealTranscriptSearch: revealTranscriptSearch,
                selectPreviousTranscriptSearchMatch: selectPreviousTranscriptSearchMatch,
                selectNextTranscriptSearchMatch: selectNextTranscriptSearchMatch,
                clearTranscriptSearch: closeTranscriptSearch
            )
            .padding(.horizontal, FlannelSpacing.shellInset)
            .padding(.top, 12)
            .padding(.bottom, 10)

            FlannelSeparator(opacity: 0.36)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ChatTranscript(
                            messages: visibleMessages,
                            toolResultsByID: toolResultsByID,
                            pinnedMessageIDs: Set(store.pinnedMessages
                                .filter { $0.threadID == store.currentAssistantThread?.id }
                                .map(\.messageID)),
                            searchMatchedMessageIDs: transcriptSearchMatchedMessageIDs,
                            activeSearchMessageID: activeTranscriptSearchMatch?.messageID,
                            activeSearchMatchLabel: activeTranscriptSearchMatchLabel,
                            hasRunnableProvider: store.activeProvider != nil,
                            citationPreviews: { store.knowledgeCitationPreviews(for: $0.citations) },
                            chooseSuggestedPrompt: chooseSuggestedPrompt,
                            openModelSetup: openModelSetup,
                            toggleMessagePin: toggleMessagePin,
                            copyMessage: copyMessage,
                            retryFromMessage: retryFromMessage,
                            editMessage: editMessage,
                            forkThreadFromMessage: forkThreadFromMessage,
                            runRequestedToolCall: runRequestedToolCall,
                            denyRequestedToolCall: denyRequestedToolCall,
                            approveToolResult: { resolveToolApproval($0, approve: true) },
                            denyToolResult: { resolveToolApproval($0, approve: false) }
                        )
                        .frame(maxWidth: Self.chatContentMaxWidth)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 26)
                        .frame(maxWidth: .infinity)

                        transcriptBottomSentinel
                    }
                }
                .coordinateSpace(name: Self.transcriptScrollCoordinateSpace)
                .scrollContentBackground(.hidden)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ChatTranscriptViewportHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        FlannelSeparator(opacity: 0.42)

                        VStack(spacing: 0) {
                            if shouldShowJumpToLatest {
                                Button {
                                    isTranscriptPinnedToBottom = true
                                    scrollToLatest(using: proxy)
                                } label: {
                                    Label("Jump to latest", systemImage: "arrow.down")
                                }
                                .buttonStyle(.plain)
                                .controlSize(.small)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .flannelGlassCapsule(.regular, interactive: true)
                                .frame(maxWidth: Self.chatContentMaxWidth, alignment: .trailing)
                                .padding(.bottom, 8)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                                .help("Scroll to the newest message.")
                            }

                            Composer(
                                contextBudget: composerContextBudget,
                                text: $composerText,
                                attachments: $composerAttachments,
                                isStreamingResponse: isStreamingResponse,
                                focusNonce: composerFocusNonce,
                                send: {
                                    isTranscriptPinnedToBottom = true
                                    sendMessage()
                                },
                                cancel: cancelStreaming,
                                compare: compareCurrentPrompt
                            )
                            .frame(maxWidth: Self.chatContentMaxWidth)
                            .padding(12)
                            .flannelFloatingDockSurface(cornerRadius: 28)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 16)
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.top, 14)
                    }
                }
                .onChange(of: visibleMessages.count) { _, _ in
                    if shouldFollowLatestMessage {
                        scrollToLatest(using: proxy)
                    } else {
                        announceNewTranscriptOutputIfNeeded()
                    }
                }
                .onChange(of: latestMessageScrollFingerprint) { _, _ in
                    if shouldFollowLatestMessage {
                        scrollToLatest(using: proxy)
                    } else {
                        announceNewTranscriptOutputIfNeeded()
                    }
                }
                .onChange(of: store.currentAssistantThread?.id) { _, _ in
                    announcedOffscreenMessageID = nil
                }
                .onChange(of: composerFocusRequest) { _, _ in
                    composerFocusNonce = UUID()
                }
                .onChange(of: transcriptSearchText) { _, _ in
                    selectedTranscriptSearchIndex = 0
                }
                .onChange(of: transcriptSearchMatches.map(\.id)) { _, _ in
                    clampTranscriptSearchSelection()
                    scrollToSearchMatch(activeTranscriptSearchMatch?.messageID, using: proxy)
                }
                .onChange(of: activeTranscriptSearchMatch?.id) { _, _ in
                    scrollToSearchMatch(activeTranscriptSearchMatch?.messageID, using: proxy)
                    announceActiveTranscriptSearchMatch()
                }
                .onAppear {
                    isTranscriptPinnedToBottom = true
                    scrollToLatest(using: proxy)
                }
                .onPreferenceChange(ChatTranscriptViewportHeightPreferenceKey.self) { height in
                    transcriptViewportHeight = height
                }
                .onPreferenceChange(ChatTranscriptBottomYPreferenceKey.self) { bottomY in
                    updateTranscriptBottomPosition(bottomY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcriptBottomSentinel: some View {
        Color.clear
            .frame(height: 1)
            .id(Self.transcriptBottomAnchorID)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ChatTranscriptBottomYPreferenceKey.self,
                        value: geometry.frame(in: .named(Self.transcriptScrollCoordinateSpace)).maxY
                    )
                }
            }
    }

    private var visibleMessages: [AssistantMessage] {
        (store.currentAssistantThread?.messages ?? []).filter { $0.role != .system }
    }

    private var latestMessageScrollFingerprint: String {
        guard let latestMessage = visibleMessages.last else { return "empty" }
        return [
            latestMessage.id.uuidString,
            "\(latestMessage.text.count)",
            "\(latestMessage.toolCalls.count)",
            "\(latestMessage.referencedEntityIDs.count)"
        ].joined(separator: "-")
    }

    private var shouldFollowLatestMessage: Bool {
        isTranscriptPinnedToBottom
            && transcriptSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowJumpToLatest: Bool {
        !visibleMessages.isEmpty
            && !isTranscriptPinnedToBottom
            && transcriptSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composerContextBudget: ChatContextBudget? {
        let contextText = (
            (store.currentAssistantThread?.messages.map(\.shareText) ?? [])
                + [composerText]
                + composerAttachments.map(attachmentContextText)
        )
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        let estimatedTokens = Self.estimatedTokenCount(for: contextText)
        guard estimatedTokens > 0 else { return nil }
        return ChatContextBudget(
            estimatedTokens: estimatedTokens,
            windowTokens: store.activeProvider?.contextWindowTokens
        )
    }

    private func attachmentContextText(_ attachment: AIChatAttachment) -> String {
        [
            attachment.title,
            attachment.excerpt ?? ""
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private static func estimatedTokenCount(for text: String) -> Int {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard characterCount > 0 else { return 0 }
        return max(1, Int(ceil(Double(characterCount) / 4.0)))
    }

    private func chooseSuggestedPrompt(_ prompt: String) {
        composerText = prompt
        composerFocusNonce = UUID()
    }

    private var toolResultsByID: [UUID: LocalToolExecutionResult] {
        Dictionary(uniqueKeysWithValues: store.toolExecutionResults.map { ($0.id, $0) })
    }

    private var transcriptSearchMatches: [ChatTranscriptSearchMatch] {
        ChatTranscriptSearchService.matches(in: visibleMessages, query: transcriptSearchText)
    }

    private var activeTranscriptSearchMatch: ChatTranscriptSearchMatch? {
        guard transcriptSearchMatches.indices.contains(selectedTranscriptSearchIndex) else {
            return nil
        }
        return transcriptSearchMatches[selectedTranscriptSearchIndex]
    }

    private var transcriptSearchMatchedMessageIDs: Set<UUID> {
        Set(transcriptSearchMatches.map(\.messageID))
    }

    private var selectedTranscriptSearchPosition: Int? {
        transcriptSearchMatches.isEmpty ? nil : selectedTranscriptSearchIndex + 1
    }

    private var activeTranscriptSearchMatchLabel: String? {
        guard let selectedTranscriptSearchPosition else { return nil }
        return "Match \(selectedTranscriptSearchPosition) of \(transcriptSearchMatches.count)"
    }

    private func announceActiveTranscriptSearchMatch() {
        guard let activeTranscriptSearchMatch,
              let activeTranscriptSearchMatchLabel else { return }
        let preview = activeTranscriptSearchMatch.preview
        let role = activeTranscriptSearchMatch.role.rawValue.capitalized
        let announcement = preview.isEmpty
            ? "\(activeTranscriptSearchMatchLabel), \(role) message"
            : "\(activeTranscriptSearchMatchLabel), \(role) message: \(preview)"
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: announcement]
        )
    }

    private func announceNewTranscriptOutputIfNeeded() {
        guard shouldShowJumpToLatest,
              let latestMessage = visibleMessages.last,
              latestMessage.role == .assistant,
              latestMessage.id != announcedOffscreenMessageID else {
            return
        }
        announcedOffscreenMessageID = latestMessage.id
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: "New assistant message available. Jump to latest."]
        )
    }

    private func resolveToolApproval(_ result: LocalToolExecutionResult, approve: Bool) {
        Task { @MainActor in
            guard let resolved = await store.resolveToolApproval(
                result.id,
                approve: approve,
                webPageCaptureService: WebPageCaptureService()
            ) else { return }
            store.refreshAssistantMessages(forToolResult: resolved)
            let sourceToolCall = store.refreshRequestedToolCall(forToolResult: resolved)
            persist()
            if approve && resolved.status == .completed {
                continueAfterToolResult(resolved, sourceToolCall)
            }
        }
    }

    private func runRequestedToolCall(_ message: AssistantMessage, _ toolCall: AIToolCallRecord) {
        Task { @MainActor in
            guard let result = await store.runRequestedToolCall(
                toolCall.id,
                in: message.id,
                webPageCaptureService: WebPageCaptureService()
            ) else {
                persist()
                return
            }
            let sourceToolCall = store.refreshRequestedToolCall(forToolResult: result) ?? toolCall
            persist()
            if result.status == .completed {
                continueAfterToolResult(result, sourceToolCall)
            }
        }
    }

    private func denyRequestedToolCall(_ message: AssistantMessage, _ toolCall: AIToolCallRecord) {
        _ = store.denyRequestedToolCall(toolCall.id, in: message.id)
        persist()
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard !visibleMessages.isEmpty else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(Self.transcriptBottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func updateTranscriptBottomPosition(_ bottomY: CGFloat) {
        guard transcriptViewportHeight > 0, bottomY.isFinite else { return }
        let bottomDistance = bottomY - transcriptViewportHeight
        let isPinned = FlannelTranscriptFollowPolicy.isPinnedToBottom(bottomDistance: bottomDistance)
        guard isPinned != isTranscriptPinnedToBottom else { return }

        withAnimation(.easeInOut(duration: 0.12)) {
            isTranscriptPinnedToBottom = isPinned
        }
    }

    private func selectPreviousTranscriptSearchMatch() {
        guard !transcriptSearchMatches.isEmpty else { return }
        selectedTranscriptSearchIndex = selectedTranscriptSearchIndex == 0
            ? transcriptSearchMatches.count - 1
            : selectedTranscriptSearchIndex - 1
    }

    private func selectNextTranscriptSearchMatch() {
        guard !transcriptSearchMatches.isEmpty else { return }
        selectedTranscriptSearchIndex = (selectedTranscriptSearchIndex + 1) % transcriptSearchMatches.count
    }

    private func clearTranscriptSearch() {
        transcriptSearchText = ""
        selectedTranscriptSearchIndex = 0
    }

    private func revealTranscriptSearch() {
        withAnimation(.easeOut(duration: 0.14)) {
            isTranscriptSearchVisible = true
        }
        transcriptSearchFocusRequest += 1
    }

    private func closeTranscriptSearch() {
        clearTranscriptSearch()
        withAnimation(.easeOut(duration: 0.12)) {
            isTranscriptSearchVisible = false
        }
        composerFocusNonce = UUID()
    }

    private func clampTranscriptSearchSelection() {
        guard !transcriptSearchMatches.isEmpty else {
            selectedTranscriptSearchIndex = 0
            return
        }
        selectedTranscriptSearchIndex = min(selectedTranscriptSearchIndex, transcriptSearchMatches.count - 1)
    }

    private func scrollToSearchMatch(_ messageID: UUID?, using proxy: ScrollViewProxy) {
        guard let messageID else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(messageID, anchor: .center)
            }
        }
    }
}

private struct ChatThreadHeader: View {
    @Bindable var store: WorkspaceStore
    @Binding var transcriptSearchText: String
    @Binding var isTranscriptSearchVisible: Bool
    var transcriptSearchMatchCount: Int
    var selectedTranscriptSearchPosition: Int?
    var transcriptSearchFocusRequest: Int
    var revealTranscriptSearch: () -> Void
    var selectPreviousTranscriptSearchMatch: () -> Void
    var selectNextTranscriptSearchMatch: () -> Void
    var clearTranscriptSearch: () -> Void

    private var visibleMessageCount: Int {
        store.currentAssistantThread?.messages.filter { $0.role != .system }.count ?? 0
    }

    private var messageCountText: String {
        "\(visibleMessageCount) message\(visibleMessageCount == 1 ? "" : "s")"
    }

    private var activeProvider: ProviderConfiguration? {
        store.activeProvider
    }

    private var routeStatusText: String {
        activeProvider?.providerModeChoiceTitle ?? "Local fallback"
    }

    private var routeStatusIcon: String {
        activeProvider?.accessMode.icon ?? "cpu"
    }

    private var routeStatusTone: FlannelStatusTone {
        guard let activeProvider else {
            return .warning
        }

        switch activeProvider.connectionStatus {
        case .ready:
            return .success
        case .needsAttention, .rateLimited:
            return .warning
        case .syncing:
            return .info
        case .disconnected:
            return .neutral
        }
    }

    private var privacyTitle: String {
        if store.preferences.localOnlyMode ?? true {
            return "Local-only"
        }

        return activeProvider?.privacyScope.title ?? "Private"
    }

    private var privacyIcon: String {
        if store.preferences.localOnlyMode ?? true {
            return "lock.fill"
        }

        switch activeProvider?.privacyScope {
        case .externalAPI:
            return (store.preferences.allowCloudProviders ?? false) ? "network" : "network.slash"
        case .localCLI:
            return "terminal"
        case .bridgeService:
            return "shippingbox"
        case .localOnly:
            return "lock.fill"
        case nil:
            return "lock"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.currentAssistantThread?.title ?? "New Chat")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                FlowLayout(spacing: 6) {
                    CapsuleLabel(privacyTitle, icon: privacyIcon, tint: store.preferences.localOnlyMode ?? true ? .green : nil)
                    CapsuleLabel(messageCountText, icon: "text.bubble")
                    FlannelStatusChip(routeStatusText, systemImage: routeStatusIcon, tone: routeStatusTone)
                        .frame(maxWidth: 250)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(privacyTitle), \(messageCountText), route \(routeStatusText)")
            }

            Spacer(minLength: 12)

            if isTranscriptSearchVisible || !transcriptSearchText.isEmpty {
                ChatTranscriptFindBar(
                    text: $transcriptSearchText,
                    matchCount: transcriptSearchMatchCount,
                    selectedPosition: selectedTranscriptSearchPosition,
                    focusRequest: transcriptSearchFocusRequest,
                    previous: selectPreviousTranscriptSearchMatch,
                    next: selectNextTranscriptSearchMatch,
                    clear: clearTranscriptSearch
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                Button(action: revealTranscriptSearch) {
                    Label("Find in Chat", systemImage: "magnifyingglass")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .frame(width: 30, height: 28)
                .contentShape(Circle())
                .flannelGlassCapsule(.clear, interactive: true)
                .keyboardShortcut("f", modifiers: [.command])
                .help("Find in chat")
                .accessibilityLabel("Find in chat")
            }
        }
        .frame(minHeight: 54)
    }
}

private struct ChatTranscriptFindBar: View {
    @Binding var text: String
    var matchCount: Int
    var selectedPosition: Int?
    var focusRequest: Int
    var previous: () -> Void
    var next: () -> Void
    var clear: () -> Void
    @FocusState private var isFieldFocused: Bool

    private var hasQuery: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resultLabel: String {
        guard hasQuery else { return "" }
        guard matchCount > 0,
              let selectedPosition else {
            return "No results"
        }
        return "\(selectedPosition)/\(matchCount)"
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Find in chat", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
                .focused($isFieldFocused)
                .onSubmit(next)
                .accessibilityLabel("Find in chat")

            if hasQuery {
                Text(resultLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(matchCount == 0 ? .secondary : .primary)
                    .frame(minWidth: 58, alignment: .trailing)

                Button(action: previous) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .frame(width: 26, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .flannelGlassCapsule(.clear, interactive: true)
                .disabled(matchCount == 0)
                .help("Previous match")
                .accessibilityLabel("Previous chat search match")

                Button(action: next) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .frame(width: 26, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .flannelGlassCapsule(.clear, interactive: true)
                .disabled(matchCount == 0)
                .help("Next match")
                .accessibilityLabel("Next chat search match")

                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .frame(width: 26, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .flannelGlassCapsule(.clear, interactive: true)
                .foregroundStyle(.secondary)
                .help("Clear chat search")
                .accessibilityLabel("Clear chat search")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .flannelChromePanel(cornerRadius: 14)
        .onAppear(perform: focusField)
        .onChange(of: focusRequest) { _, _ in
            focusField()
        }
        .onExitCommand(perform: clear)
    }

    private func focusField() {
        guard focusRequest > 0 else { return }
        DispatchQueue.main.async {
            isFieldFocused = true
        }
    }
}

private struct ChatTranscript: View {
    var messages: [AssistantMessage]
    var toolResultsByID: [UUID: LocalToolExecutionResult]
    var pinnedMessageIDs: Set<UUID>
    var searchMatchedMessageIDs: Set<UUID>
    var activeSearchMessageID: UUID?
    var activeSearchMatchLabel: String?
    var hasRunnableProvider: Bool
    var citationPreviews: (AssistantMessage) -> [KnowledgeCitationPreview]
    var chooseSuggestedPrompt: (String) -> Void
    var openModelSetup: () -> Void
    var toggleMessagePin: (AssistantMessage) -> Void
    var copyMessage: (AssistantMessage) -> Void
    var retryFromMessage: (AssistantMessage) -> Void
    var editMessage: (AssistantMessage) -> Void
    var forkThreadFromMessage: (AssistantMessage) -> Void
    var runRequestedToolCall: (AssistantMessage, AIToolCallRecord) -> Void
    var denyRequestedToolCall: (AssistantMessage, AIToolCallRecord) -> Void
    var approveToolResult: (LocalToolExecutionResult) -> Void
    var denyToolResult: (LocalToolExecutionResult) -> Void

    private var pinnedMessages: [AssistantMessage] {
        messages.filter { pinnedMessageIDs.contains($0.id) }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            if messages.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    EmptyState(
                        icon: "bubble.left.and.bubble.right",
                        title: "Start a private chat",
                        detail: hasRunnableProvider
                            ? "Messages are stored locally in SwiftData. Pick a starter or type directly below."
                            : "Configure a local model, API key, or account CLI route before sending model-backed messages."
                    )

                    if hasRunnableProvider {
                        SuggestedPromptGrid(choose: chooseSuggestedPrompt)
                    } else {
                        Button(action: openModelSetup) {
                            Label("Open Model Setup", systemImage: "cpu")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if !pinnedMessages.isEmpty {
                    PinnedMessageRail(
                        messages: Array(pinnedMessages.prefix(4)),
                        choose: copyMessage
                    )
                }

                ForEach(messages) { message in
                    MessageBubble(
                        message: message,
                        toolResults: message.referencedEntityIDs.compactMap { toolResultsByID[$0] },
                        isPinned: pinnedMessageIDs.contains(message.id),
                        isSearchMatch: searchMatchedMessageIDs.contains(message.id),
                        isActiveSearchMatch: activeSearchMessageID == message.id,
                        searchMatchLabel: activeSearchMessageID == message.id ? activeSearchMatchLabel : nil,
                        citationPreviews: citationPreviews(message),
                        togglePin: { toggleMessagePin(message) },
                        copy: { copyMessage(message) },
                        retry: { retryFromMessage(message) },
                        edit: { editMessage(message) },
                        fork: { forkThreadFromMessage(message) },
                        runRequestedToolCall: { runRequestedToolCall(message, $0) },
                        denyRequestedToolCall: { denyRequestedToolCall(message, $0) },
                        approveToolResult: approveToolResult,
                        denyToolResult: denyToolResult
                    )
                    .id(message.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PinnedMessageRail: View {
    var messages: [AssistantMessage]
    var choose: (AssistantMessage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pinned", systemImage: "pin")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(messages) { message in
                        PinnedMessageButton(message: message) {
                            choose(message)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PinnedMessageButton: View {
    var message: AssistantMessage
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(message.role.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(message.role.tint)
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 220, alignment: .topLeading)
            .frame(minHeight: 72, alignment: .topLeading)
            .padding(10)
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Copy pinned message")
    }
}

private struct StreamedToolCallList: View {
    var toolCalls: [AIToolCallRecord]
    var run: (AIToolCallRecord) -> Void
    var deny: (AIToolCallRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(toolCalls) { toolCall in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "function")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.indigo)
                            .frame(width: 18)
                        Text(toolCall.toolName)
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 8)
                        CapsuleLabel(toolCall.permissionScope.title, icon: toolCall.permissionScope.icon)
                        CapsuleLabel(toolCall.statusTitle, icon: toolCall.statusIcon, tint: toolCall.statusTint)
                    }

                    if let providerCallID = toolCall.providerCallID,
                       !providerCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(providerCallID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if !toolCall.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(toolCall.argumentsJSON)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    if let outputPreview = toolCall.outputPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !outputPreview.isEmpty {
                        Text(outputPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    if toolCall.executionStatus == nil {
                        HStack(spacing: 8) {
                            Button {
                                run(toolCall)
                            } label: {
                                Label("Run", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button {
                                deny(toolCall)
                            } label: {
                                Label("Deny", systemImage: "xmark")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer(minLength: 0)
                        }
                        .padding(.top, 1)
                    }
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct MessageBubble: View {
    var message: AssistantMessage
    var toolResults: [LocalToolExecutionResult]
    var isPinned: Bool
    var isSearchMatch: Bool
    var isActiveSearchMatch: Bool
    var searchMatchLabel: String?
    var citationPreviews: [KnowledgeCitationPreview]
    var togglePin: () -> Void
    var copy: () -> Void
    var retry: () -> Void
    var edit: () -> Void
    var fork: () -> Void
    var runRequestedToolCall: (AIToolCallRecord) -> Void
    var denyRequestedToolCall: (AIToolCallRecord) -> Void
    var approveToolResult: (LocalToolExecutionResult) -> Void
    var denyToolResult: (LocalToolExecutionResult) -> Void
    @State private var showsDetails = false
    @State private var showsAttachments = false
    @State private var showsSources = false
    @State private var showsToolCalls = true
    @State private var isMessageRowHovering = false
    @FocusState private var isMessageActionMenuFocused: Bool

    private var isUserMessage: Bool {
        message.role == .user
    }

    private var shouldRevealMessageActions: Bool {
        isMessageRowHovering || isMessageActionMenuFocused || isActiveSearchMatch
    }

    private var messageActionMenuOpacity: Double {
        shouldRevealMessageActions ? 1 : 0.34
    }

    private var trimmedText: String {
        message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleAttachments: [AIChatAttachment] {
        message.attachments.filter { attachment in
            attachment.kind != .toolResult || toolResults.isEmpty
        }
    }

    private var rendersToolResultAsPrimaryContent: Bool {
        message.role == .assistant
            && !toolResults.isEmpty
            && message.attachments.contains { $0.kind == .toolResult }
            && trimmedText.hasPrefix("Tool run:")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUserMessage {
                Spacer(minLength: 80)
            } else {
                messageIcon
                    .opacity(0.62)
            }

            VStack(alignment: .leading, spacing: isUserMessage ? 5 : 7) {
                HStack(alignment: .center, spacing: 8) {
                    Text(message.role.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isUserMessage ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.indigo)
                            .help("Pinned")
                    }
                    if isSearchMatch {
                        if isActiveSearchMatch, let searchMatchLabel {
                            CapsuleLabel(searchMatchLabel, icon: "magnifyingglass", tint: .accentColor)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help("Search match")
                        }
                    }
                    Spacer()
                    MessageActionMenu(
                        message: message,
                        isPinned: isPinned,
                        togglePin: togglePin,
                        copy: copy,
                        retry: retry,
                        edit: edit,
                        fork: fork
                    )
                    .focused($isMessageActionMenuFocused)
                    .opacity(messageActionMenuOpacity)
                    .animation(.easeInOut(duration: 0.12), value: messageActionMenuOpacity)
                }

                if !visibleAttachments.isEmpty {
                    DisclosureGroup(isExpanded: $showsAttachments) {
                        MessageAttachmentList(attachments: visibleAttachments)
                            .padding(.top, 6)
                    } label: {
                        Label("\(visibleAttachments.count) attachment\(visibleAttachments.count == 1 ? "" : "s")", systemImage: "paperclip")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                        .padding(.bottom, 2)
                }

                if !message.toolCalls.isEmpty {
                    DisclosureGroup(isExpanded: $showsToolCalls) {
                        StreamedToolCallList(
                            toolCalls: message.toolCalls,
                            run: runRequestedToolCall,
                            deny: denyRequestedToolCall
                        )
                            .padding(.top, 6)
                    } label: {
                        Label("\(message.toolCalls.count) requested tool call\(message.toolCalls.count == 1 ? "" : "s")", systemImage: "function")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 2)
                }

                if rendersToolResultAsPrimaryContent {
                    ForEach(toolResults) { result in
                        InlineToolResultCard(
                            result: result,
                            approve: { approveToolResult(result) },
                            deny: { denyToolResult(result) }
                        )
                    }
                } else {
                    if trimmedText.isEmpty, message.role == .assistant {
                        StreamingMessagePlaceholder()
                    } else {
                        MarkdownMessageBody(text: message.text)
                    }

                    ForEach(toolResults) { result in
                        InlineToolResultCard(
                            result: result,
                            approve: { approveToolResult(result) },
                            deny: { denyToolResult(result) }
                        )
                    }
                }

                if !message.metadataChips.isEmpty {
                    DisclosureGroup(isExpanded: $showsDetails) {
                        FlowLayout(spacing: 6) {
                            ForEach(message.metadataChips, id: \.self) { chip in
                                CapsuleLabel(chip.title, icon: chip.icon)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Label("Details", systemImage: "info.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 3)
                }

                if !message.citations.isEmpty {
                    DisclosureGroup(isExpanded: $showsSources) {
                        MessageCitationList(previews: citationPreviews)
                            .padding(.top, 6)
                    } label: {
                        Label("\(message.citations.count) source\(message.citations.count == 1 ? "" : "s")", systemImage: "books.vertical")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(isUserMessage ? 12 : 0)
            .frame(maxWidth: isUserMessage ? 680 : .infinity, alignment: .leading)
            .background {
                if isUserMessage {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary.opacity(0.42))
                }
            }
            .contextMenu {
                MessageActionMenuItems(
                    message: message,
                    isPinned: isPinned,
                    togglePin: togglePin,
                    copy: copy,
                    retry: retry,
                    edit: edit,
                    fork: fork
                )
            }

            if isUserMessage {
                messageIcon
            } else {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUserMessage ? .trailing : .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isActiveSearchMatch ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSearchMatch ? Color.accentColor.opacity(isActiveSearchMatch ? 0.55 : 0.22) : Color.clear,
                    lineWidth: isActiveSearchMatch ? 1.5 : 1
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isMessageRowHovering = hovering
        }
        .accessibilityElement(children: .contain)
    }

    private var messageIcon: some View {
        Image(systemName: message.role.symbolName)
            .font(.caption)
            .frame(width: 18)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
    }
}

private struct InlineToolResultCard: View {
    var result: LocalToolExecutionResult
    var approve: () -> Void
    var deny: () -> Void

    private var trimmedQuery: String {
        result.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedOutput: String {
        result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: result.toolKind.icon)
                    .font(.body.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                    if !trimmedQuery.isEmpty {
                        Text(trimmedQuery)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 12)

                StatusBadge(
                    text: result.status.title,
                    icon: result.status.icon,
                    tint: result.status.tint
                )
            }

            if result.requiresApproval || result.status == .requiresApproval {
                HStack(spacing: 8) {
                    Button {
                        approve()
                    } label: {
                        Label("Approve", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        deny()
                    } label: {
                        Label("Deny", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }

            FlowLayout(spacing: 7) {
                CapsuleLabel(result.toolKind.title, icon: result.toolKind.icon)
                CapsuleLabel(result.createdAt.formatted(date: .abbreviated, time: .shortened), icon: "clock")
                if result.usedNetwork {
                    CapsuleLabel("Network", icon: "network", tint: .orange)
                }
                if result.modifiedFiles {
                    CapsuleLabel("File changes", icon: "square.and.pencil", tint: .red)
                }
                if result.requiresApproval {
                    CapsuleLabel("Approval gate", icon: "hand.raised", tint: .orange)
                }
            }

            if !trimmedOutput.isEmpty {
                Text(trimmedOutput)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(result.status.tint.opacity(0.24), lineWidth: 1)
        }
    }
}

private struct StreamingMessagePlaceholder: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Responding...")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct MessageAttachmentList: View {
    var attachments: [AIChatAttachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Attachments")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(attachments) { attachment in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: attachment.symbolName)
                        .frame(width: 18)
                        .foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(attachment.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(attachment.displayDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let excerpt = attachment.excerpt,
                           !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(excerpt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.top, 4)
    }
}

private struct MessageCitationList: View {
    var previews: [KnowledgeCitationPreview]
    var limit: Int = 6
    var snippetLineLimit: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(previews.prefix(limit)) { preview in
                CitationPreviewCard(preview: preview, snippetLineLimit: snippetLineLimit)
            }
        }
    }
}

private struct CitationPreviewCard: View {
    var preview: KnowledgeCitationPreview
    var snippetLineLimit: Int = 3

    private var trimmedSnippet: String {
        preview.citation.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLocation: String? {
        guard let location = preview.displayLocation?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty else {
            return nil
        }
        return location
    }

    private var scoreText: String? {
        guard let score = preview.score else { return nil }
        if score >= 0, score <= 1 {
            return "\(Int((score * 100).rounded()))% match"
        }
        return "Score \(String(format: "%.2f", score))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(preview.displayTitle, systemImage: preview.kind?.icon ?? "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if !preview.isResolved {
                    CapsuleLabel("Unresolved", icon: "questionmark.folder", tint: .orange)
                }
            }

            if !trimmedSnippet.isEmpty {
                Text(trimmedSnippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(snippetLineLimit)
                    .textSelection(.enabled)
            }

            FlowLayout(spacing: 6) {
                if let kind = preview.kind {
                    CapsuleLabel(kind.title, icon: kind.icon)
                }
                if let status = preview.status {
                    CapsuleLabel(status.title, icon: status.icon, tint: status.tint)
                }
                if let chunkLabel = preview.chunkLabel {
                    CapsuleLabel(chunkLabel, icon: "number")
                }
                if let scoreText {
                    CapsuleLabel(scoreText, icon: "scope")
                }
                if let chunkCount = preview.chunkCount, chunkCount > 0 {
                    CapsuleLabel("\(chunkCount) chunks", icon: "square.stack.3d.up")
                }
                if let embeddingRecordCount = preview.embeddingRecordCount, embeddingRecordCount > 0 {
                    CapsuleLabel("\(embeddingRecordCount) vectors", icon: "point.3.connected.trianglepath.dotted")
                }
                if preview.isWatched {
                    CapsuleLabel("Watched", icon: "eye")
                }
            }

            if let trimmedLocation {
                Text(trimmedLocation)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MessageActionMenu: View {
    var message: AssistantMessage
    var isPinned: Bool
    var togglePin: () -> Void
    var copy: () -> Void
    var retry: () -> Void
    var edit: () -> Void
    var fork: () -> Void

    var body: some View {
        Menu {
            MessageActionMenuItems(
                message: message,
                isPinned: isPinned,
                togglePin: togglePin,
                copy: copy,
                retry: retry,
                edit: edit,
                fork: fork
            )
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.semibold))
                .frame(width: 28, height: 24)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .help("Message actions")
        .accessibilityLabel("Message actions")
    }
}

private struct MessageActionMenuItems: View {
    var message: AssistantMessage
    var isPinned: Bool
    var togglePin: () -> Void
    var copy: () -> Void
    var retry: () -> Void
    var edit: () -> Void
    var fork: () -> Void

    var body: some View {
        Button(action: togglePin) {
            Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
        }
        Button(action: copy) {
            Label("Copy", systemImage: "doc.on.doc")
        }
        Button(action: retry) {
            Label(message.role == .assistant ? "Regenerate" : "Retry", systemImage: "arrow.clockwise")
        }
        if message.role == .user {
            Button(action: edit) {
                Label("Edit", systemImage: "pencil")
            }
        }
        Button(action: fork) {
            Label("Fork", systemImage: "arrow.triangle.branch")
        }
    }
}

private struct IconOnlyButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct ChatExportMenu: View {
    var isDisabled: Bool
    var export: (ChatExportFormat) -> Void

    var body: some View {
        Menu {
            ForEach(ChatExportFormat.allCases) { format in
                Button {
                    export(format)
                } label: {
                    Label(format.title, systemImage: format.systemImage)
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .disabled(isDisabled)
        .help("Export the current chat locally")
        .accessibilityLabel("Export chat")
    }
}

private struct Composer: View {
    var contextBudget: ChatContextBudget?
    @Binding var text: String
    @Binding var attachments: [AIChatAttachment]
    var isStreamingResponse: Bool
    var focusNonce: UUID
    var send: () -> Void
    var cancel: () -> Void
    var compare: () -> Void
    @State private var isFileImporterPresented = false
    @State private var isDropTargeted = false
    @State private var attachmentImportError: String?
    @FocusState private var isEditorFocused: Bool

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private var canComparePrompt: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var editorHeight: CGFloat {
        let lineCount = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
        return min(150, max(76, CGFloat(lineCount) * 22 + 34))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                AttachmentChipGrid(
                    attachments: attachments,
                    remove: removeAttachment
                )
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(height: editorHeight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .focused($isEditorFocused)
                    .background(
                        FlannelSystemColor.chromeFill.opacity(isEditorFocused ? 1 : 0.82),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                composerEditorStrokeColor,
                                lineWidth: isDropTargeted ? 2 : FlannelSpacing.hairline
                            )
                    }
                    .accessibilityLabel("Message composer")
                    .accessibilityHint("Type a message to Flannel. Press Command Return to send.")
                    .dropDestination(for: URL.self) { urls, _ in
                        importAttachments(from: urls)
                        return true
                    } isTargeted: { isTargeted in
                        isDropTargeted = isTargeted
                    }

                if text.isEmpty {
                    Text("Message Flannel...")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

            if let attachmentImportError {
                HStack(spacing: 8) {
                    Label(attachmentImportError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(attachmentImportError)
                        .accessibilityAddTraits(.isStaticText)
                    Spacer(minLength: 8)
                    Button {
                        self.attachmentImportError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss attachment error")
                    .accessibilityLabel("Dismiss attachment error")
                }
            }

            HStack(alignment: .center, spacing: 8) {
                ComposerStatusStrip(
                    contextBudget: contextBudget,
                    attachmentCount: attachments.count,
                    isStreamingResponse: isStreamingResponse
                )

                Spacer(minLength: 12)

                Button {
                    isFileImporterPresented = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.body)
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .controlSize(.regular)
                .flannelGlassCapsule(.clear, interactive: true)
                .disabled(isStreamingResponse)
                .help(attachHelpText)
                .accessibilityLabel("Attach files")
                .accessibilityHint(attachHelpText)

                Button {
                    compare()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .controlSize(.regular)
                .flannelGlassCapsule(.clear, interactive: true)
                .disabled(isStreamingResponse || !canComparePrompt)
                .help(compareHelpText)
                .accessibilityLabel("Compare current prompt")
                .accessibilityHint(compareHelpText)

                Button {
                    if isStreamingResponse {
                        cancel()
                    } else {
                        send()
                    }
                } label: {
                    Image(systemName: isStreamingResponse ? "stop.fill" : "arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(isStreamingResponse ? .red : .accentColor)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!isStreamingResponse && !canSubmit)
                .help(primaryActionHelpText)
                .accessibilityLabel(primaryActionLabel)
                .accessibilityHint(primaryActionHelpText)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            importAttachments(from: urls)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .onAppear {
            isEditorFocused = true
        }
        .onChange(of: focusNonce) { _, _ in
            isEditorFocused = true
        }
        .onChange(of: attachmentImportError) { _, newValue in
            if let newValue {
                announceAttachmentImportError(newValue)
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importAttachments(from: urls)
            case .failure(let error):
                attachmentImportError = error.localizedDescription
            }
        }
    }

    private var composerEditorStrokeColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.8)
        }
        if isEditorFocused {
            return Color.accentColor.opacity(0.28)
        }
        return FlannelSystemColor.quietStroke.opacity(0.72)
    }

    private var attachHelpText: String {
        isStreamingResponse ? "Wait for the current response to finish before attaching files." : "Attach files to include in the next message."
    }

    private var compareHelpText: String {
        if isStreamingResponse {
            return "Wait for the current response to finish before comparing models."
        }
        return canComparePrompt ? "Compare the current prompt across multiple runnable models." : "Type a prompt before comparing models."
    }

    private var primaryActionLabel: String {
        isStreamingResponse ? "Stop response" : "Send message"
    }

    private var primaryActionHelpText: String {
        if isStreamingResponse {
            return "Stop the current response. Keyboard shortcut Command Return."
        }
        if canSubmit {
            return "Send the composer text and attachments. Keyboard shortcut Command Return."
        }
        return "Type a message or attach a file to enable Send."
    }

    private func importAttachments(from urls: [URL]) {
        let result = ChatAttachmentService().importAttachments(from: urls)
        if !result.attachments.isEmpty {
            let existingKeys = Set(attachments.map(\.dedupeKey))
            attachments.append(contentsOf: result.attachments.filter { !existingKeys.contains($0.dedupeKey) })
        }

        attachmentImportError = result.failures.first.map {
            "Could not attach \($0.url.lastPathComponent): \($0.message)"
        }
    }

    private func announceAttachmentImportError(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message]
        )
    }

    private func removeAttachment(_ attachment: AIChatAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        if attachments.isEmpty {
            attachmentImportError = nil
        }
    }
}

private struct ComposerStatusStrip: View {
    var contextBudget: ChatContextBudget?
    var attachmentCount: Int
    var isStreamingResponse: Bool

    var body: some View {
        FlowLayout(spacing: 6) {
            if isStreamingResponse {
                CapsuleLabel("Responding", icon: "dot.radiowaves.left.and.right")
            }

            if let contextBudget {
                CapsuleLabel(
                    contextBudget.label,
                    icon: contextBudget.icon,
                    tint: contextBudget.tint
                )
                .help(contextBudget.detail)
                .accessibilityLabel(contextBudget.accessibilityLabel)
            }

            if attachmentCount > 0 {
                CapsuleLabel("\(attachmentCount) attachment\(attachmentCount == 1 ? "" : "s")", icon: "paperclip")
            }
        }
    }
}

private struct ChatContextBudget {
    var estimatedTokens: Int
    var windowTokens: Int?

    private var usageFraction: Double? {
        guard let windowTokens,
              windowTokens > 0 else { return nil }
        return Double(estimatedTokens) / Double(windowTokens)
    }

    var label: String {
        guard let windowTokens,
              windowTokens > 0,
              let usageFraction else {
            return "\(formatCompactTokens(estimatedTokens)) ctx est"
        }

        let percent = Int((usageFraction * 100).rounded())
        return "\(formatCompactTokens(estimatedTokens)) / \(formatCompactTokens(windowTokens)) ctx \(percent)%"
    }

    var detail: String {
        guard let windowTokens,
              windowTokens > 0,
              let usageFraction else {
            return "Estimated chat context tokens. Configure a provider context window to show remaining capacity."
        }

        let percent = Int((usageFraction * 100).rounded())
        return "Estimated prompt context uses \(formatTokens(estimatedTokens)) of \(formatTokens(windowTokens)) tokens (\(percent)%)."
    }

    var accessibilityLabel: String {
        guard let windowTokens,
              windowTokens > 0,
              let usageFraction else {
            return "Estimated context \(formatTokens(estimatedTokens)) tokens"
        }

        let percent = Int((usageFraction * 100).rounded())
        return "Estimated context \(formatTokens(estimatedTokens)) of \(formatTokens(windowTokens)) tokens, \(percent) percent"
    }

    var icon: String {
        guard let usageFraction else { return "gauge.with.dots.needle.33percent" }
        if usageFraction >= 0.9 { return "exclamationmark.triangle" }
        if usageFraction >= 0.72 { return "gauge.with.dots.needle.67percent" }
        return "gauge.with.dots.needle.33percent"
    }

    var tint: Color? {
        guard let usageFraction else { return .secondary }
        if usageFraction >= 0.9 { return .red }
        if usageFraction >= 0.72 { return .orange }
        return .secondary
    }
}

private struct AttachmentChipGrid: View {
    var attachments: [AIChatAttachment]
    var remove: (AIChatAttachment) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(attachments) { attachment in
                HStack(spacing: 6) {
                    Image(systemName: attachment.symbolName)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attachment.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(attachment.displayDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button {
                        remove(attachment)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove attachment")
                    .accessibilityLabel("Remove \(attachment.title)")
                }
                .padding(.vertical, 6)
                .padding(.leading, 9)
                .padding(.trailing, 6)
                .flannelChromePanel(cornerRadius: FlannelRadius.md)
            }
        }
    }
}

private struct SuggestedPromptGrid: View {
    var choose: (String) -> Void

    private let prompts = [
        "Compare the active local model with the best cloud fallback for this task.",
        "Search my local knowledge and answer with citations.",
        "Create a tool permission plan for web search, file reads, and terminal commands.",
        "Design a multi-model comparison run for this prompt."
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
            ForEach(prompts, id: \.self) { prompt in
                Button {
                    choose(prompt)
                } label: {
                    Text(prompt)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private enum ChatHistoryScope: String, CaseIterable, Identifiable {
    case active = "Active"
    case archived = "Archived"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .active:
            "bubble.left.and.bubble.right"
        case .archived:
            "archivebox"
        }
    }
}

private struct ChatHistorySurface: View {
    @Bindable var store: WorkspaceStore
    var persist: () -> Void
    @State private var scope: ChatHistoryScope = .active

    private var query: String {
        store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleThreads: [AssistantThread] {
        switch scope {
        case .active:
            store.activeAssistantThreads
        case .archived:
            store.archivedAssistantThreads
        }
    }

    private var visibleSearchResults: [AssistantChatSearchResult] {
        store.globalChatSearchResults.filter { result in
            switch scope {
            case .active:
                !result.isArchived
            case .archived:
                result.isArchived
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                SectionTitle("Chat history", "Search, pinned messages, archive state, and local-only thread organization.")
                Spacer()

                Menu {
                    ForEach(ChatHistoryScope.allCases) { option in
                        Button {
                            scope = option
                        } label: {
                            Label(option.rawValue, systemImage: option.icon)
                        }
                    }
                } label: {
                    Label(scope.rawValue, systemImage: scope.icon)
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
            }

            if query.isEmpty {
                threadList
            } else {
                searchList
            }
        }
        .panelStyle()
    }

    @ViewBuilder
    private var threadList: some View {
        if visibleThreads.isEmpty {
            EmptyState(
                icon: scope == .archived ? "archivebox" : "bubble.left.and.bubble.right",
                title: scope == .archived ? "No archived threads" : "No active threads",
                detail: scope == .archived
                    ? "Archived conversations will stay searchable here until restored."
                    : "Start a private chat or restore an archived thread to fill this list."
            )
            .frame(minHeight: 180)
        } else {
            VStack(spacing: 10) {
                ForEach(visibleThreads) { thread in
                    ChatThreadRow(
                        thread: thread,
                        isSelected: store.selectedAssistantThreadID == thread.id,
                        isArchived: store.archivedAssistantThreadIDs.contains(thread.id),
                        isPinned: store.pinnedMessages.contains { $0.threadID == thread.id },
                        choose: { open(thread) },
                        archiveToggle: { toggleArchive(thread) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var searchList: some View {
        if visibleSearchResults.isEmpty {
            EmptyState(
                icon: "magnifyingglass",
                title: "No chat matches",
                detail: "Try a thread title, model name, prompt phrase, or message text."
            )
            .frame(minHeight: 180)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(visibleSearchResults.count) matches for \"\(query)\"")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(visibleSearchResults) { result in
                    ChatSearchResultRow(
                        result: result,
                        choose: { openSearchResult(result) },
                        archiveToggle: { toggleArchive(result.threadID) }
                    )
                }
            }
        }
    }

    private func open(_ thread: AssistantThread) {
        store.selectedAssistantThreadID = thread.id
        store.selectedDestination = .home
    }

    private func openSearchResult(_ result: AssistantChatSearchResult) {
        store.selectedAssistantThreadID = result.threadID
        store.selectedDestination = .home
    }

    private func toggleArchive(_ thread: AssistantThread) {
        toggleArchive(thread.id)
    }

    private func toggleArchive(_ threadID: UUID) {
        if store.archivedAssistantThreadIDs.contains(threadID) {
            _ = store.unarchiveThread(threadID)
        } else {
            _ = store.archiveThread(threadID)
        }
        persist()
    }
}

private struct ModelComparisonSurface: View {
    @Bindable var store: WorkspaceStore
    @Binding var prompt: String
    @Binding var selectedProviderIDs: Set<UUID>
    @Binding var selectedRunID: UUID?
    @Binding var selectedResultID: UUID?
    var isRunning: Bool
    var currentChatPrompt: String
    var runComparison: () -> Void
    var cancelComparison: () -> Void
    var copyResult: (ModelComparisonResult) -> Void
    var useResultProvider: (ModelComparisonResult) -> Void
    var persist: () -> Void

    private var runnableProviders: [ProviderConfiguration] {
        store.runnableComparisonProviders
    }

    private var effectiveSelection: Set<UUID> {
        selectedProviderIDs.isEmpty
            ? Set(store.defaultComparisonProviderIDs(limit: min(3, runnableProviders.count)))
            : selectedProviderIDs
    }

    private var selectedCount: Int {
        effectiveSelection.intersection(Set(runnableProviders.map(\.id))).count
    }

    private var canRun: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedCount >= 2
            && !isRunning
    }

    private var selectedRun: ModelComparisonRun? {
        if let selectedRunID,
           let run = store.modelComparisonRuns.first(where: { $0.id == selectedRunID }) {
            return run
        }
        return store.modelComparisonRuns.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SectionTitle("Compare", "Run the same prompt across multiple models and inspect differences.")
                Spacer()
                if isRunning {
                    Button {
                        cancelComparison()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        runComparison()
                    } label: {
                        Label("Run Compare", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRun)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }

            compareSetupPanel
            activeRunPanel
            recentRunsPanel
        }
        .onAppear {
            seedDefaultSelectionIfNeeded()
            if selectedRunID == nil {
                selectedRunID = store.modelComparisonRuns.first?.id
            }
            seedSelectedResultIfNeeded()
        }
        .onChange(of: store.providerConfigurations) {
            reconcileSelectedProviders()
        }
        .onChange(of: selectedRunID) {
            seedSelectedResultForSelectedRun()
        }
    }

    private var compareSetupPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                MetricPill(title: "Runnable", value: "\(runnableProviders.count)", icon: "cpu")
                MetricPill(title: "Selected", value: "\(selectedCount)", icon: "checkmark.circle")
                MetricPill(title: "Saved runs", value: "\(store.modelComparisonRuns.count)", icon: "rectangle.split.3x1")
                MetricPill(title: "Completed", value: "\(store.modelComparisonRuns.filter { $0.status == .completed }.count)", icon: "flag.checkered")
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Prompt", systemImage: "text.bubble")
                    .font(.headline)
                TextEditor(text: $prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 104)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Model comparison prompt")
            }

            providerSelectionPanel

            HStack {
                Label(compareReadinessText, systemImage: compareReadinessIcon)
                    .font(.caption)
                    .foregroundStyle(compareReadinessTint)
                Spacer()
                Button("Use Current Chat Prompt") {
                    let chatPrompt = currentChatPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !chatPrompt.isEmpty else { return }
                    prompt = chatPrompt
                }
                .buttonStyle(.bordered)
                .disabled(isRunning || currentChatPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Select Defaults") {
                    selectedProviderIDs = Set(store.defaultComparisonProviderIDs(limit: min(3, runnableProviders.count)))
                }
                .buttonStyle(.bordered)
                .disabled(isRunning || runnableProviders.isEmpty)

                Button("Open Models") {
                    store.selectedDestination = .models
                }
                .buttonStyle(.bordered)

                if isRunning {
                    Button {
                        cancelComparison()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        runComparison()
                    } label: {
                        Label("Run Compare", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRun)
                }
            }
        }
        .panelStyle()
    }

    @ViewBuilder
    private var providerSelectionPanel: some View {
        if runnableProviders.count < 2 {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compare needs at least two runnable providers")
                        .font(.headline)
                    Text("Enable another local server, configured API key provider, or supported CLI provider before running side-by-side results.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            FlowLayout(spacing: 8) {
                ForEach(runnableProviders) { provider in
                    ComparisonProviderChip(
                        provider: provider,
                        isActive: store.activeProvider?.id == provider.id,
                        isSelected: effectiveSelection.contains(provider.id),
                        isDisabled: isRunning || (!effectiveSelection.contains(provider.id) && selectedCount >= 4)
                    ) { isSelected in
                        updateSelection(providerID: provider.id, isSelected: isSelected)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var activeRunPanel: some View {
        if let run = selectedRun {
            ComparisonRunSurface(
                run: run,
                selectedResultID: selectedResultID,
                citationPreviews: { store.knowledgeCitationPreviews(for: $0) },
                selectResult: { selectedResultID = $0.id },
                copyResult: copyResult,
                useResultProvider: useResultProvider
            )
        } else {
            EmptyState(
                icon: "rectangle.split.3x1",
                title: "Compare two or more models",
                detail: "Choose providers, enter a prompt, and Flannel will store each model response with privacy, latency, token, and cost metadata."
            )
            .panelStyle()
        }
    }

    @ViewBuilder
    private var recentRunsPanel: some View {
        if !store.modelComparisonRuns.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent comparison runs")
                        .font(.headline)
                    Spacer()
                    Text("\(store.modelComparisonRuns.count) saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(store.modelComparisonRuns.prefix(8)) { run in
                    ComparisonRunRow(
                        run: run,
                        isSelected: selectedRunID == run.id || (selectedRunID == nil && store.modelComparisonRuns.first?.id == run.id)
                    ) {
                        selectedRunID = run.id
                        selectedResultID = run.results.first?.id
                    }
                }
            }
            .panelStyle()
        }
    }

    private var compareReadinessText: String {
        if isRunning { return "Streaming each selected provider into its own result card" }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a prompt to compare" }
        if selectedCount < 2 { return "Select at least two providers" }
        return "Ready to compare \(selectedCount) providers"
    }

    private var compareReadinessIcon: String {
        if isRunning { return "dot.radiowaves.left.and.right" }
        return canRun ? "checkmark.circle" : "info.circle"
    }

    private var compareReadinessTint: Color {
        if isRunning { return .indigo }
        return canRun ? .green : .secondary
    }

    private func seedDefaultSelectionIfNeeded() {
        guard selectedProviderIDs.isEmpty else { return }
        selectedProviderIDs = Set(store.defaultComparisonProviderIDs(limit: min(3, runnableProviders.count)))
    }

    private func reconcileSelectedProviders() {
        let runnableIDs = Set(runnableProviders.map(\.id))
        selectedProviderIDs = selectedProviderIDs.intersection(runnableIDs)
        if selectedProviderIDs.isEmpty {
            seedDefaultSelectionIfNeeded()
        }
    }

    private func seedSelectedResultIfNeeded() {
        guard selectedResultID == nil else { return }
        seedSelectedResultForSelectedRun()
    }

    private func seedSelectedResultForSelectedRun() {
        guard let run = selectedRun else {
            selectedResultID = nil
            return
        }
        if let selectedResultID,
           run.results.contains(where: { $0.id == selectedResultID }) {
            return
        }
        selectedResultID = run.results.first?.id
    }

    private func updateSelection(providerID: UUID, isSelected: Bool) {
        if isSelected {
            guard selectedCount < 4 || effectiveSelection.contains(providerID) else { return }
            selectedProviderIDs.insert(providerID)
        } else {
            selectedProviderIDs.remove(providerID)
        }
        persist()
    }
}

private struct ComparisonProviderChip: View {
    var provider: ProviderConfiguration
    var isActive: Bool
    var isSelected: Bool
    var isDisabled: Bool
    var setSelected: (Bool) -> Void

    var body: some View {
        Button {
            setSelected(!isSelected)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .indigo : .secondary)
                Image(systemName: provider.privacyScope.icon)
                    .foregroundStyle(provider.privacyScope == .externalAPI ? .orange : .green)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(provider.displayName)
                            .font(.caption.weight(.semibold))
                        if isActive {
                            Text("Active")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        } else if provider.isLocalPreferred {
                            Text("Preferred Local")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.indigo)
                        }
                    }
                    Text(provider.modelIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? AnyShapeStyle(.indigo.opacity(0.14)) : AnyShapeStyle(.thinMaterial),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? .indigo.opacity(0.45) : .secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled && !isSelected)
        .opacity(isDisabled && !isSelected ? 0.5 : 1)
        .accessibilityLabel("\(isSelected ? "Deselect" : "Select") \(provider.displayName)")
    }
}

private struct ComparisonRunSurface: View {
    var run: ModelComparisonRun
    var selectedResultID: UUID?
    var citationPreviews: ([AIChatCitation]) -> [KnowledgeCitationPreview]
    var selectResult: (ModelComparisonResult) -> Void
    var copyResult: (ModelComparisonResult) -> Void
    var useResultProvider: (ModelComparisonResult) -> Void

    private var completedCount: Int {
        run.results.filter { $0.status == .completed }.count
    }

    private var failedCount: Int {
        run.results.filter { $0.status == .failed }.count
    }

    private var streamingCount: Int {
        run.results.filter { $0.status == .streaming }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.prompt)
                        .font(.headline)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Text(run.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: run.status.title, icon: run.status.icon, tint: run.status.tint)
            }

            FlowLayout(spacing: 8) {
                CapsuleLabel("\(completedCount) completed", icon: "checkmark.circle", tint: completedCount > 0 ? .green : nil)
                CapsuleLabel("\(streamingCount) streaming", icon: "waveform", tint: streamingCount > 0 ? .indigo : nil)
                CapsuleLabel("\(failedCount) failed", icon: "exclamationmark.triangle", tint: failedCount > 0 ? .orange : nil)
                CapsuleLabel("\(run.results.count) providers", icon: "cpu")
            }

            if failedCount == run.results.count && !run.results.isEmpty {
                Label("All providers failed. Check provider setup, model identifiers, local servers, or API keys.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(run.results) { result in
                        ComparisonResultCard(
                            result: result,
                            isSelected: selectedResultID == result.id,
                            select: { selectResult(result) },
                            copy: { copyResult(result) },
                            useForChat: { useResultProvider(result) }
                        )
                            .frame(width: 340)
                    }
                }
                .padding(.bottom, 4)
            }

            if !run.citations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shared citations")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    MessageCitationList(
                        previews: citationPreviews(run.citations),
                        limit: 5,
                        snippetLineLimit: 2
                    )
                }
            }
        }
        .panelStyle()
    }
}

private struct ComparisonResultCard: View {
    var result: ModelComparisonResult
    var isSelected: Bool
    var select: () -> Void
    var copy: () -> Void
    var useForChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.providerDisplayName)
                                .font(.headline)
                            Text(result.modelIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        StatusBadge(text: result.status.title, icon: result.status.icon, tint: result.status.tint)
                    }

                    FlowLayout(spacing: 6) {
                        CapsuleLabel(result.accessMode.title, icon: result.accessMode.icon)
                        CapsuleLabel(result.privacyScope.title, icon: result.privacyScope.icon)
                        if let inputTokenCount = result.inputTokenCount,
                           let outputTokenCount = result.outputTokenCount {
                            CapsuleLabel("\(inputTokenCount) in / \(outputTokenCount) out", icon: "text.word.spacing")
                            if result.tokenCountsAreEstimated {
                                CapsuleLabel("Estimated tokens", icon: "function")
                            }
                        }
                        if let latencyMilliseconds = result.latencyMilliseconds {
                            CapsuleLabel(latencyMilliseconds.formattedLatency, icon: "timer")
                        }
                        if let firstTokenLatencyMilliseconds = result.firstTokenLatencyMilliseconds {
                            CapsuleLabel("First token \(firstTokenLatencyMilliseconds.formattedLatency)", icon: "bolt.horizontal")
                        }
                        if let estimatedCostMicros = result.estimatedCostMicros,
                           estimatedCostMicros > 0 {
                            CapsuleLabel(estimatedCostMicros.formattedMicrosCost, icon: "dollarsign.circle")
                        }
                    }

                    if let error = result.errorMessage,
                       !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    Group {
                        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.secondary.opacity(0.20))
                                    .frame(height: 10)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.secondary.opacity(0.16))
                                    .frame(width: 220, height: 10)
                                Text(result.status == .queued ? "Queued" : "Waiting for tokens")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text(result.text)
                                .font(.body)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                    .padding(10)
                    .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(result.providerDisplayName), \(result.modelIdentifier), \(result.status.title)")
            .accessibilityValue(isSelected ? "Selected" : "")

            HStack(spacing: 4) {
                Label(isSelected ? "Selected result" : "Select result", systemImage: isSelected ? "scope" : "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .indigo : .secondary)
                Spacer(minLength: 8)
                IconOnlyButton(title: "Copy result", systemImage: "doc.on.doc", action: copy)
                    .disabled(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                IconOnlyButton(title: "Use model for chat", systemImage: "checkmark.circle", action: useForChat)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? .indigo.opacity(0.55) : .secondary.opacity(0.10), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ComparisonRunRow: View {
    var run: ModelComparisonRun
    var isSelected: Bool
    var choose: () -> Void

    var body: some View {
        Button {
            choose()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.split.3x1")
                    .foregroundStyle(isSelected ? .indigo : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.prompt)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text("\(run.results.count) providers • \(run.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: run.status.title, icon: run.status.icon, tint: run.status.tint)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? AnyShapeStyle(.indigo.opacity(0.14)) : AnyShapeStyle(.thinMaterial),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? .indigo.opacity(0.45) : .secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ChatThreadRow: View {
    var thread: AssistantThread
    var isSelected: Bool
    var isArchived: Bool
    var isPinned: Bool
    var choose: () -> Void
    var archiveToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: choose) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isArchived ? "archivebox" : "bubble.left.and.bubble.right")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.indigo) : AnyShapeStyle(.secondary))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(thread.title)
                                .font(.headline)
                            if isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundStyle(.indigo)
                            }
                        }

                        Text("\(thread.messages.count) messages • \(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let lastMessage = thread.messages.last {
                            Text(lastMessage.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            IconOnlyButton(
                title: isArchived ? "Restore" : "Archive",
                systemImage: isArchived ? "arrow.up.bin" : "archivebox",
                action: archiveToggle
            )
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? AnyShapeStyle(.indigo.opacity(0.14)) : AnyShapeStyle(.thinMaterial))
        }
    }
}

private struct ChatSearchResultRow: View {
    var result: AssistantChatSearchResult
    var choose: () -> Void
    var archiveToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: choose) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: resultIcon)
                        .font(.title3)
                        .foregroundStyle(result.isArchived ? AnyShapeStyle(.secondary) : AnyShapeStyle(.indigo))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(result.title)
                                .font(.headline)
                            if result.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundStyle(.indigo)
                            }
                            if result.isArchived {
                                CapsuleLabel("Archived", icon: "archivebox", tint: .secondary)
                            }
                        }

                        Text("\(result.matchKind.title) • \(result.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !result.snippet.isEmpty {
                            Text(result.snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            IconOnlyButton(
                title: result.isArchived ? "Restore" : "Archive",
                systemImage: result.isArchived ? "arrow.up.bin" : "archivebox",
                action: archiveToggle
            )
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var resultIcon: String {
        result.matchKind.icon
    }
}

private extension AssistantChatSearchMatchKind {
    var title: String {
        switch self {
        case .threadTitle:
            "Thread"
        case .messageText:
            "Message"
        case .attachment:
            "Attachment"
        case .citation:
            "Citation"
        }
    }

    var icon: String {
        switch self {
        case .threadTitle:
            "bubble.left.and.bubble.right"
        case .messageText:
            "text.bubble"
        case .attachment:
            "paperclip"
        case .citation:
            "quote.bubble"
        }
    }
}

private struct ModelHubSurface: View {
    @Bindable var store: WorkspaceStore
    var isDiscoveringModels: Bool
    var discoverModels: () -> Void
    var persist: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle("Models and providers", "BYOK, local servers, account CLI routes, and optional AI SDK bridge.")
                Spacer()
                Button {
                    discoverModels()
                } label: {
                    Label(isDiscoveringModels ? "Discovering" : "Discover Local", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(isDiscoveringModels)
            }

            modelSummaryPanel
            ProviderModeLegend()

            if store.modelPresets.isEmpty {
                EmptyState(
                    icon: "dial.medium",
                    title: "No model presets",
                    detail: "Create reusable routing defaults from provider setup or imported workspace settings."
                )
                .panelStyle()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Presets", "Reusable model defaults that can be applied onto matching providers.")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                        ForEach(store.modelPresets) { preset in
                            ModelPresetCard(
                                store: store,
                                preset: preset,
                                persist: persist
                            )
                        }
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                ForEach(store.providerConfigurations) { provider in
                    ProviderCard(store: store, providerID: provider.id, persist: persist)
                }
            }

            if !store.localDiscoveryResults.isEmpty {
                SectionTitle("Discovered local models", "Ollama and LM Studio results from this machine.")
                ForEach(store.localDiscoveryResults) { result in
                    LocalDiscoveryCard(result: result)
                }
            }
        }
    }

    private var modelSummaryPanel: some View {
        HStack(spacing: 10) {
            MetricPill(
                title: "Enabled",
                value: "\(store.providerConfigurations.filter(\.isEnabled).count)",
                icon: "checkmark.circle"
            )
            MetricPill(
                title: "Preferred",
                value: store.activeProvider?.displayName ?? "None",
                icon: "bolt.horizontal.circle"
            )
            MetricPill(
                title: "Presets",
                value: "\(store.modelPresets.count)",
                icon: "dial.medium"
            )
            MetricPill(
                title: "Discovered",
                value: "\(store.localDiscoveryResults.flatMap(\.models).count)",
                icon: "antenna.radiowaves.left.and.right"
            )
        }
        .panelStyle()
    }
}

private struct ProviderModeLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            ModePill("API keys live in Keychain", icon: "key")
            ModePill("Account CLI is local command access", icon: "terminal")
            ModePill("Vercel AI SDK is an optional Node bridge", icon: "shippingbox")
        }
    }
}

private struct ProviderCard: View {
    @Bindable var store: WorkspaceStore
    var providerID: UUID
    var persist: () -> Void
    @State private var apiKeyDraft = ""
    @State private var setupNotice: String?

    private var provider: ProviderConfiguration? {
        store.providerConfigurations.first(where: { $0.id == providerID })
    }

    private var setupReport: ProviderSetupReport? {
        guard let provider else { return nil }
        return ProviderSetupService.shared.report(for: provider, preferences: store.preferences)
    }

    private var discoveredModels: [String] {
        guard let provider else { return [] }
        let localModels = store.localDiscoveryResults
            .filter { $0.providerKind == provider.kind && $0.endpoint == provider.endpoint }
            .flatMap(\.models)
            .map(\.name)
        return Array(Set(provider.availableModels + localModels)).sorted()
    }

    var body: some View {
        if let provider {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName)
                            .font(.headline)
                        Text(provider.kind.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(
                        text: provider.connectionStatus.title,
                        icon: provider.connectionStatus.icon,
                        tint: provider.connectionStatus.tint
                    )
                }

                Text(provider.modeBoundaryDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(connectionSectionTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField(endpointFieldTitle, text: endpointBinding(defaultValue: provider.endpoint))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    if provider.accessMode == .localServer, !discoveredModels.isEmpty {
                        Picker("Model", selection: modelBinding(fallback: provider.modelIdentifier)) {
                            ForEach(discoveredModels, id: \.self) { modelName in
                                Text(modelName).tag(modelName)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        TextField(modelFieldTitle, text: modelBinding(fallback: provider.modelIdentifier))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                }

                FlowLayout(spacing: 8) {
                    CapsuleLabel(provider.accessMode.title, icon: provider.accessMode.icon)
                    CapsuleLabel(provider.privacyScope.title, icon: provider.privacyScope.icon)
                    if store.activeProvider?.id == provider.id {
                        CapsuleLabel("Active", icon: "checkmark.circle", tint: .green)
                    }
                    if provider.secretReference != nil {
                        CapsuleLabel("Keychain", icon: "key.fill", tint: .yellow)
                    }
                    if provider.isLocalPreferred {
                        CapsuleLabel("Preferred Local", icon: "bolt.horizontal.circle", tint: .indigo)
                    }
                }

                if !provider.capabilities.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(provider.capabilities.unique().sorted(by: { $0.title < $1.title }), id: \.self) { capability in
                            CapsuleLabel(capability.title, icon: capability.icon)
                        }
                    }
                }

                if setupReport?.canonicalSecretReference != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("API key")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if provider.secretReference != nil {
                                CapsuleLabel("Saved in Keychain", icon: "key.fill", tint: .green)
                            }
                        }

                        SecureField(provider.secretReference == nil ? "Paste API key" : "Replace API key", text: $apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)

                        HStack {
                            if let reference = setupReport?.canonicalSecretReference?.rawValue {
                                Text(reference)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                saveAPIKey()
                            } label: {
                                Label("Save key", systemImage: "key.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Temperature")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(provider.temperature.formatted(.number.precision(.fractionLength(2))))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: temperatureBinding(defaultValue: provider.temperature), in: 0 ... 1, step: 0.05)
                        .accessibilityLabel("\(provider.displayName) temperature")
                }

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        ProviderSwitchControl(
                            title: provider.isEnabled ? "Enabled" : "Disabled",
                            subtitle: "Provider availability",
                            isOn: enabledBinding(defaultValue: provider.isEnabled)
                        )

                        ProviderSwitchControl(
                            title: "Prefer local",
                            subtitle: "Route local chats here",
                            isOn: localPreferenceBinding(defaultValue: provider.isLocalPreferred)
                        )
                    }

                    Button {
                        store.preferences.preferredProviderID = provider.id
                        persist()
                    } label: {
                        Label(routeButtonTitle, systemImage: routeButtonIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canUseForChat || store.activeProvider?.id == provider.id)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    if let chatReadinessMessage {
                        Label(chatReadinessMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if shouldOfferCloudRoutingAction {
                        Button {
                            store.preferences.localOnlyMode = false
                            persist()
                        } label: {
                            Label("Allow Cloud Providers", systemImage: "network")
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack {
                        if let setupNotice {
                            Text(setupNotice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            checkSetup()
                        } label: {
                            Label("Check setup", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack(spacing: 8) {
                    if let contextWindow = provider.contextWindowTokens {
                        CapsuleLabel("\(formatTokens(contextWindow)) context", icon: "text.word.spacing")
                    }
                    if provider.supportsStructuredOutput {
                        CapsuleLabel("Structured", icon: "list.bullet.rectangle")
                    }
                    if provider.supportsVision {
                        CapsuleLabel("Vision", icon: "eye")
                    }
                    if provider.supportsEmbeddings {
                        CapsuleLabel("Embeddings", icon: "square.stack.3d.up")
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let lastValidatedAt = provider.lastValidatedAt {
                        Label(
                            "Last checked \(lastValidatedAt.formatted(date: .abbreviated, time: .shortened))",
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let lastErrorMessage = provider.lastErrorMessage, !lastErrorMessage.isEmpty {
                        Label(lastErrorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let setupReport,
                       !setupReport.diagnostics.isEmpty {
                        ForEach(setupReport.diagnostics.prefix(3)) { diagnostic in
                            Label(diagnostic.message, systemImage: diagnostic.severity.icon)
                                .font(.caption)
                                .foregroundStyle(diagnostic.severity.tint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .panelStyle()
        }
    }

    private func endpointBinding(defaultValue: String) -> Binding<String> {
        Binding {
            store.providerConfigurations.first(where: { $0.id == providerID })?.endpoint ?? defaultValue
        } set: { newValue in
            guard let index = store.providerConfigurations.firstIndex(where: { $0.id == providerID }) else { return }
            store.providerConfigurations[index].endpoint = newValue
            store.providerConfigurations[index].connectionStatus = .disconnected
            store.providerConfigurations[index].lastErrorMessage = nil
            persist()
        }
    }

    private var canUseForChat: Bool {
        guard let provider else { return false }
        return store.isProviderRunnableForChat(provider)
    }

    private var connectionSectionTitle: String {
        guard let provider else { return "Connection" }
        switch provider.accessMode {
        case .localServer:
            return "Local server"
        case .subscriptionCLI:
            return "CLI command"
        case .apiKey:
            return "Provider API"
        case .openAICompatible:
            return "OpenAI-compatible endpoint"
        case .anthropicCompatible:
            return "Anthropic-compatible endpoint"
        case .aiSDKBridge:
            return "Local bridge"
        }
    }

    private var endpointFieldTitle: String {
        guard let provider else { return "Endpoint" }
        switch provider.accessMode {
        case .subscriptionCLI:
            return "Authenticated command"
        case .localServer:
            return "Loopback endpoint"
        case .apiKey, .openAICompatible, .anthropicCompatible:
            return "API endpoint"
        case .aiSDKBridge:
            return "Bridge command or URL"
        }
    }

    private var modelFieldTitle: String {
        guard let provider else { return "Model identifier" }
        switch provider.accessMode {
        case .subscriptionCLI:
            return "Model or CLI profile"
        case .localServer:
            return "Manual model identifier"
        default:
            return "Model identifier"
        }
    }

    private var routeButtonTitle: String {
        guard let provider else { return "No Route" }
        if store.activeProvider?.id == provider.id {
            return "Active Route"
        }
        if !canUseForChat {
            if store.preferences.preferredProviderID == provider.id {
                return "Selected but Blocked"
            }
            return "Cannot Route Yet"
        }
        if store.preferences.preferredProviderID == provider.id {
            return "Selected Route"
        }
        return "Select Preferred Route"
    }

    private var routeButtonIcon: String {
        guard let provider else { return "exclamationmark.triangle" }
        if store.activeProvider?.id == provider.id {
            return "checkmark.circle.fill"
        }
        if !canUseForChat {
            return "lock"
        }
        return "checkmark.circle"
    }

    private var shouldOfferCloudRoutingAction: Bool {
        guard let provider else { return false }
        return provider.privacyScope == .externalAPI && (store.preferences.localOnlyMode ?? true)
    }

    private var chatReadinessMessage: String? {
        guard let provider else { return nil }
        if let blockReason = store.chatRoutingBlockReason(for: provider) {
            return blockReason
        }
        if let blockingDiagnostic = setupReport?.diagnostics.first(where: \.isBlocking) {
            return blockingDiagnostic.message
        }
        if let routingDiagnostic = setupReport?.diagnostics.first(where: { $0.field == "privacyScope" }) {
            return routingDiagnostic.message
        }
        if !provider.supportsStreaming {
            return "Streaming is disabled for this provider configuration."
        }
        return nil
    }

    private func modelBinding(fallback: String) -> Binding<String> {
        Binding {
            store.providerConfigurations.first(where: { $0.id == providerID })?.modelIdentifier ?? fallback
        } set: { newValue in
            guard let index = store.providerConfigurations.firstIndex(where: { $0.id == providerID }) else { return }
            store.providerConfigurations[index].modelIdentifier = newValue
            store.providerConfigurations[index].connectionStatus = .disconnected
            store.providerConfigurations[index].lastErrorMessage = nil
            persist()
        }
    }

    private func enabledBinding(defaultValue: Bool) -> Binding<Bool> {
        Binding {
            store.providerConfigurations.first(where: { $0.id == providerID })?.isEnabled ?? defaultValue
        } set: { newValue in
            guard let index = store.providerConfigurations.firstIndex(where: { $0.id == providerID }) else { return }
            store.providerConfigurations[index].isEnabled = newValue
            if !newValue, store.preferences.preferredProviderID == providerID {
                store.preferences.preferredProviderID = nil
            }
            persist()
        }
    }

    private func localPreferenceBinding(defaultValue: Bool) -> Binding<Bool> {
        Binding {
            store.providerConfigurations.first(where: { $0.id == providerID })?.isLocalPreferred ?? defaultValue
        } set: { newValue in
            guard let index = store.providerConfigurations.firstIndex(where: { $0.id == providerID }) else { return }
            store.providerConfigurations[index].isLocalPreferred = newValue
            persist()
        }
    }

    private func temperatureBinding(defaultValue: Double) -> Binding<Double> {
        Binding {
            store.providerConfigurations.first(where: { $0.id == providerID })?.temperature ?? defaultValue
        } set: { newValue in
            guard let index = store.providerConfigurations.firstIndex(where: { $0.id == providerID }) else { return }
            store.providerConfigurations[index].temperature = newValue
            persist()
        }
    }

    private func saveAPIKey() {
        do {
            let report = try store.saveProviderAPIKey(providerID, secret: apiKeyDraft)
            apiKeyDraft = ""
            if report?.hasBlockingIssues == true {
                setupNotice = "Key saved, but setup still needs attention."
            } else {
                setupNotice = "Key saved and setup looks ready."
            }
            persist()
        } catch {
            setupNotice = "Keychain save failed: \(error.localizedDescription)"
        }
    }

    private func checkSetup() {
        guard let report = store.validateProviderSetup(providerID) else { return }
        if report.hasBlockingIssues {
            setupNotice = "Setup has \(report.diagnostics.filter(\.isBlocking).count) blocking issue(s)."
        } else if report.routingEligibility == .eligible {
            setupNotice = "Setup looks ready."
        } else {
            setupNotice = "Setup is configured, but routing is blocked by privacy preferences."
        }
        persist()
    }
}

private struct ProviderSwitchControl: View {
    var title: String
    var subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 42)
    }
}

private struct ModelPresetCard: View {
    @Bindable var store: WorkspaceStore
    var preset: ModelPreset
    var persist: () -> Void

    private var matchingProviderIndex: Int? {
        store.providerConfigurations.firstIndex {
            $0.kind == preset.providerKind && $0.accessMode == preset.accessMode
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(.headline)
                    Text(preset.providerKind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if preset.isDefault || store.preferences.defaultModelPresetID == preset.id {
                    StatusBadge(text: "Default", icon: "checkmark.circle", tint: .green)
                }
            }

            FlowLayout(spacing: 8) {
                CapsuleLabel(preset.accessMode.title, icon: preset.accessMode.icon)
                CapsuleLabel(preset.privacyScope.title, icon: preset.privacyScope.icon)
                CapsuleLabel(preset.modelIdentifier, icon: "cpu")
            }

            if !preset.capabilities.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(preset.capabilities.unique().sorted(by: { $0.title < $1.title }), id: \.self) { capability in
                        CapsuleLabel(capability.title, icon: capability.icon)
                    }
                }
            }

            HStack {
                Text("Temp \(preset.temperature.formatted(.number.precision(.fractionLength(2))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let contextWindow = preset.contextWindowTokens {
                    Text("• \(formatTokens(contextWindow)) context")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Button("Make Default") {
                    for index in store.modelPresets.indices {
                        store.modelPresets[index].isDefault = store.modelPresets[index].id == preset.id
                    }
                    store.preferences.defaultModelPresetID = preset.id
                    persist()
                }
                .buttonStyle(.bordered)

                Button("Apply") {
                    applyPreset()
                }
                .buttonStyle(.borderedProminent)
                .disabled(matchingProviderIndex == nil)

                Spacer()
            }
        }
        .panelStyle()
    }

    private func applyPreset() {
        guard let index = matchingProviderIndex else { return }
        store.providerConfigurations[index].modelIdentifier = preset.modelIdentifier
        store.providerConfigurations[index].temperature = preset.temperature
        store.providerConfigurations[index].privacyScope = preset.privacyScope
        store.providerConfigurations[index].supportsEmbeddings = preset.capabilities.contains(.embeddings)
        store.providerConfigurations[index].supportsToolCalling = preset.capabilities.contains(.toolCalling)
        store.providerConfigurations[index].supportsStreaming = preset.capabilities.contains(.streaming)
        store.providerConfigurations[index].supportsStructuredOutput = preset.capabilities.contains(.structuredOutput)
        store.providerConfigurations[index].supportsVision = preset.capabilities.contains(.vision)
        store.providerConfigurations[index].contextWindowTokens = preset.contextWindowTokens
        store.providerConfigurations[index].capabilities = preset.capabilities
        store.preferences.defaultModelPresetID = preset.id
        store.preferences.preferredProviderID = store.providerConfigurations[index].id
        persist()
    }
}

private struct LocalDiscoveryCard: View {
    var result: LocalProviderDiscoveryResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(result.providerKind.title, systemImage: result.status == .ready ? "checkmark.circle" : "exclamationmark.triangle")
                Spacer()
                Text(result.endpoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if result.models.isEmpty {
                Text(result.errorMessage ?? "No models returned by this local server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(result.models) { model in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(model.name)
                            Spacer()
                            Text(model.parameterSize ?? model.family ?? "local")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        FlowLayout(spacing: 8) {
                            if let quantization = model.quantization {
                                CapsuleLabel(quantization, icon: "shippingbox")
                            }
                            if let sizeBytes = model.sizeBytes {
                                CapsuleLabel(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .binary), icon: "internaldrive")
                            }
                            ForEach(model.capabilities.unique().sorted(by: { $0.title < $1.title }), id: \.self) { capability in
                                CapsuleLabel(capability.title, icon: capability.icon)
                            }
                        }
                    }
                }
            }
        }
        .panelStyle()
    }
}

private enum KnowledgeFilter: String, CaseIterable, Identifiable {
    case all
    case ready
    case queued
    case watched
    case needsAttention

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .ready:
            "Ready"
        case .queued:
            "Queued"
        case .watched:
            "Watched"
        case .needsAttention:
            "Needs attention"
        }
    }

    func matches(_ source: KnowledgeSource) -> Bool {
        switch self {
        case .all:
            true
        case .ready:
            source.status == .ready
        case .queued:
            source.status == .queued || source.status == .indexing
        case .watched:
            source.isWatched
        case .needsAttention:
            source.status == .failed || source.status == .stale || source.status == .notIndexed
        }
    }
}

private struct KnowledgeSurface: View {
    @Bindable var store: WorkspaceStore
    var persist: () -> Void
    @State private var filter: KnowledgeFilter = .all
    @State private var newSourceKind: KnowledgeSourceKind = .folder
    @State private var newSourceTitle = ""
    @State private var newSourceLocation = ""
    @State private var newSourceWatched = true
    @State private var sourceNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle("Knowledge and RAG", "Local indexes, watched folders, embeddings, citations, and source previews.")
                Spacer()
                Menu {
                    ForEach(KnowledgeFilter.allCases) { option in
                        Button(option.title) {
                            filter = option
                        }
                    }
                } label: {
                    Label(filter.title, systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                Button {
                    Task { @MainActor in
                        await store.rebuildKnowledgeIndexManifestsUsingConfiguredEmbeddings(onlyQueued: true)
                        persist()
                    }
                } label: {
                    Label("Rebuild queued", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                Button {
                    Task { @MainActor in
                        await store.rebuildKnowledgeIndexManifestsUsingConfiguredEmbeddings()
                        persist()
                    }
                } label: {
                    Label("Rebuild all", systemImage: "shippingbox.and.arrow.backward")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 10) {
                MetricPill(title: "Sources", value: "\(store.knowledgeSources.count)", icon: "books.vertical")
                MetricPill(title: "Ready", value: "\(store.knowledgeSources.filter { $0.status == .ready }.count)", icon: "checkmark.circle")
                MetricPill(title: "Queued", value: "\(store.knowledgeSources.filter { $0.status == .queued || $0.status == .indexing }.count)", icon: "arrow.triangle.2.circlepath")
                MetricPill(title: "Watched", value: "\(store.knowledgeSources.filter(\.isWatched).count)", icon: "eye")
                MetricPill(title: "Chunks", value: "\(store.knowledgeSources.reduce(0) { $0 + $1.chunkCount })", icon: "square.stack.3d.up")
                MetricPill(title: "Vectors", value: "\(store.knowledgeSources.reduce(0) { $0 + $1.embeddingRecordCount })", icon: "point.3.connected.trianglepath.dotted")
            }
            .panelStyle()

            addSourcePanel

            if filteredSources.isEmpty {
                EmptyState(
                    icon: "books.vertical",
                    title: "No sources in this view",
                    detail: "Switch the status filter or add a local source to queue retrieval here."
                )
                .panelStyle()
            } else {
                ForEach(filteredSources) { source in
                    KnowledgeSourceCard(
                        store: store,
                        sourceID: source.id,
                        persist: persist
                    )
                }
            }
        }
    }

    private var addSourcePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Label("Add source", systemImage: "plus.rectangle.on.folder")
                    .font(.headline)
                Spacer()
                Toggle("Watched", isOn: $newSourceWatched)
                    .toggleStyle(.switch)
                    .fixedSize()
            }

            HStack(spacing: 10) {
                Picker("Type", selection: $newSourceKind) {
                    ForEach(addableSourceKinds) { kind in
                        Label(kind.title, systemImage: kind.icon).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 190)

                TextField("Title", text: $newSourceTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 150)

                TextField(newSourceKind.locationPlaceholder, text: $newSourceLocation)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)

                Button {
                    addSource()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAddSource)
                .fixedSize()
            }

            if let sourceNotice {
                Label(sourceNotice, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(2)
            }
        }
        .panelStyle()
    }

    private var addableSourceKinds: [KnowledgeSourceKind] {
        [.folder, .file, .codeRepository, .webPage]
    }

    private var canAddSource: Bool {
        !newSourceLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addSource() {
        guard let source = store.addKnowledgeSource(
            title: newSourceTitle,
            kind: newSourceKind,
            location: newSourceLocation,
            watched: newSourceWatched
        ) else {
            sourceNotice = "Add a readable path or URL first."
            return
        }

        newSourceTitle = ""
        newSourceLocation = ""
        sourceNotice = "Queued \(source.title)"
        persist()
    }

    private var filteredSources: [KnowledgeSource] {
        store.knowledgeSources.filter(filter.matches)
    }
}

private enum ToolFilter: String, CaseIterable, Identifiable {
    case all
    case enabled
    case local
    case network
    case writes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .enabled:
            "Enabled"
        case .local:
            "Local"
        case .network:
            "Network"
        case .writes:
            "Writes"
        }
    }

    func matches(_ tool: ToolConfiguration) -> Bool {
        switch self {
        case .all:
            true
        case .enabled:
            tool.isEnabled
        case .local:
            !tool.requiresNetwork && !tool.canModifyFiles
        case .network:
            tool.requiresNetwork
        case .writes:
            tool.canModifyFiles
        }
    }
}

private struct ToolsSurface: View {
    @Bindable var store: WorkspaceStore
    var persist: () -> Void
    @State private var filter: ToolFilter = .all
    @State private var toolQueries: [UUID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle("Tools and permissions", "Every tool has an explicit policy before agents can use it.")
                Spacer()
                Menu {
                    ForEach(ToolFilter.allCases) { option in
                        Button(option.title) {
                            filter = option
                        }
                    }
                } label: {
                    Label(filter.title, systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
            }

            FlowLayout(spacing: 10) {
                MetricPill(title: "Enabled", value: "\(store.toolConfigurations.filter(\.isEnabled).count)", icon: "checkmark.circle")
                MetricPill(title: "Network", value: "\(store.toolConfigurations.filter(\.requiresNetwork).count)", icon: "network")
                MetricPill(title: "Write", value: "\(store.toolConfigurations.filter(\.canModifyFiles).count)", icon: "square.and.pencil")
                MetricPill(title: "Ask", value: "\(store.toolConfigurations.filter { $0.permissionPolicy == .askEveryTime }.count)", icon: "hand.raised")
                MetricPill(title: "Runs", value: "\(store.toolExecutionResults.count)", icon: "play.circle")
                MetricPill(title: "Pending", value: "\(pendingApprovalRuns.count)", icon: "clock.badge.exclamationmark")
            }
            .panelStyle()

            HStack {
                Button("Enable local-safe set") {
                    for index in store.toolConfigurations.indices {
                        let tool = store.toolConfigurations[index]
                        if !tool.requiresNetwork && !tool.canModifyFiles {
                            store.toolConfigurations[index].isEnabled = true
                        }
                    }
                    persist()
                }
                .buttonStyle(.bordered)

                Button("Require approval for network") {
                    for index in store.toolConfigurations.indices where store.toolConfigurations[index].requiresNetwork {
                        store.toolConfigurations[index].permissionPolicy = .askEveryTime
                    }
                    persist()
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent tool runs")
                        .font(.headline)
                    Spacer()
                    Text(recentRuns.isEmpty ? "No history yet" : "\(recentRuns.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if recentRuns.isEmpty {
                    Text("Run a tool to capture approval outcomes, local blocks, and execution output here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(recentRuns.prefix(6)) { result in
                            ToolExecutionHistoryRow(
                                result: result,
                                approve: { resolveToolApproval(result, approve: true) },
                                deny: { resolveToolApproval(result, approve: false) }
                            )
                            if result.id != recentRuns.prefix(6).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .panelStyle()

            if filteredTools.isEmpty {
                EmptyState(
                    icon: "wrench.and.screwdriver",
                    title: "No tools in this view",
                    detail: "Change the tool filter to inspect local-only, networked, or enabled capabilities."
                )
                .panelStyle()
            } else {
                ForEach(filteredTools) { tool in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            Image(systemName: tool.kind.icon)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tool.title)
                                    .font(.headline)
                                Text(tool.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Toggle("Enabled", isOn: enabledBinding(for: tool))
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        HStack(alignment: .center, spacing: 10) {
                            TextField(tool.queryPrompt, text: queryBinding(for: tool), axis: tool.kind.prefersMultilineInput ? .vertical : .horizontal)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(tool.kind.prefersMultilineInput ? 3...8 : 1...1)

                            Button {
                                runTool(tool)
                            } label: {
                                Label("Run", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        FlowLayout(spacing: 8) {
                            if tool.requiresNetwork {
                                CapsuleLabel("Network", icon: "network", tint: .orange)
                            } else {
                                CapsuleLabel("Local", icon: "desktopcomputer", tint: .green)
                            }
                            if tool.canModifyFiles {
                                CapsuleLabel("Writes", icon: "square.and.pencil", tint: .red)
                            } else {
                                CapsuleLabel("Read / query", icon: "doc.text.magnifyingglass")
                            }
                            if store.preferences.localOnlyMode ?? true, tool.requiresNetwork {
                                CapsuleLabel("Blocked in Local-Only", icon: "lock.fill", tint: .orange)
                            }
                        }

                        HStack {
                            Text("Permission")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("Permission", selection: binding(for: tool)) {
                                ForEach(ToolPermissionPolicy.allCases) { policy in
                                    Text(policy.title).tag(policy)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 180)
                        }

                        if let latestResult = latestResult(for: tool) {
                            ToolExecutionResultCard(
                                title: "Latest run",
                                result: latestResult,
                                historyCount: max(0, results(for: tool).count - 1),
                                approve: { resolveToolApproval(latestResult, approve: true) },
                                deny: { resolveToolApproval(latestResult, approve: false) }
                            )
                        } else {
                            Text("No executions recorded for this tool yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .panelStyle()
                }
            }
        }
    }

    private func binding(for tool: ToolConfiguration) -> Binding<ToolPermissionPolicy> {
        Binding {
            store.toolConfigurations.first(where: { $0.id == tool.id })?.permissionPolicy ?? tool.permissionPolicy
        } set: { newValue in
            if let index = store.toolConfigurations.firstIndex(where: { $0.id == tool.id }) {
                store.toolConfigurations[index].permissionPolicy = newValue
                persist()
            }
        }
    }

    private func enabledBinding(for tool: ToolConfiguration) -> Binding<Bool> {
        Binding {
            store.toolConfigurations.first(where: { $0.id == tool.id })?.isEnabled ?? tool.isEnabled
        } set: { newValue in
            if let index = store.toolConfigurations.firstIndex(where: { $0.id == tool.id }) {
                store.toolConfigurations[index].isEnabled = newValue
                persist()
            }
        }
    }

    private var filteredTools: [ToolConfiguration] {
        store.toolConfigurations.filter(filter.matches)
    }

    private var recentRuns: [LocalToolExecutionResult] {
        store.toolExecutionResults.sorted(using: KeyPathComparator(\.createdAt, order: .reverse))
    }

    private var pendingApprovalRuns: [LocalToolExecutionResult] {
        store.toolExecutionResults.filter { $0.status == .requiresApproval || $0.requiresApproval }
    }

    private func queryBinding(for tool: ToolConfiguration) -> Binding<String> {
        Binding {
            if let draft = toolQueries[tool.id] {
                return draft
            }
            return latestResult(for: tool)?.query ?? ""
        } set: { newValue in
            toolQueries[tool.id] = newValue
        }
    }

    private func runTool(_ tool: ToolConfiguration) {
        let query = toolQueries[tool.id] ?? ""
        Task { @MainActor in
            guard let result = await store.runTool(
                tool.id,
                query: query,
                webPageCaptureService: WebPageCaptureService()
            ) else { return }
            toolQueries[tool.id] = result.query
            persist()
        }
    }

    private func resolveToolApproval(_ result: LocalToolExecutionResult, approve: Bool) {
        Task { @MainActor in
            _ = await store.resolveToolApproval(
                result.id,
                approve: approve,
                webPageCaptureService: WebPageCaptureService()
            )
            persist()
        }
    }

    private func latestResult(for tool: ToolConfiguration) -> LocalToolExecutionResult? {
        results(for: tool).first
    }

    private func results(for tool: ToolConfiguration) -> [LocalToolExecutionResult] {
        store.toolExecutionResults
            .filter { result in
                if let toolID = result.toolID {
                    return toolID == tool.id
                }
                return result.toolKind == tool.kind && result.title == tool.title
            }
            .sorted(using: KeyPathComparator(\.createdAt, order: .reverse))
    }
}

private struct ToolExecutionResultCard: View {
    var title: String
    var result: LocalToolExecutionResult
    var historyCount: Int
    var approve: () -> Void
    var deny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if !result.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(result.query)
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                    }
                }
                Spacer()
                StatusBadge(
                    text: result.status.title,
                    icon: result.status.icon,
                    tint: result.status.tint
                )
            }

            if result.requiresApproval || result.status == .requiresApproval {
                HStack(spacing: 8) {
                    Button {
                        approve()
                    } label: {
                        Label("Approve", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        deny()
                    } label: {
                        Label("Deny", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }

            FlowLayout(spacing: 8) {
                CapsuleLabel(result.createdAt.formatted(date: .abbreviated, time: .shortened), icon: "clock")
                if result.usedNetwork {
                    CapsuleLabel("Used network", icon: "network", tint: .orange)
                }
                if result.modifiedFiles {
                    CapsuleLabel("Modified files", icon: "square.and.pencil", tint: .red)
                }
                if result.requiresApproval {
                    CapsuleLabel("Approval required", icon: "hand.raised", tint: .orange)
                }
                if historyCount > 0 {
                    CapsuleLabel("\(historyCount) earlier run\(historyCount == 1 ? "" : "s")", icon: "clock.arrow.trianglehead.counterclockwise")
                }
            }

            Text(result.output)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct ToolExecutionHistoryRow: View {
    var result: LocalToolExecutionResult
    var approve: () -> Void
    var deny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                    Text(result.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(
                    text: result.status.title,
                    icon: result.status.icon,
                    tint: result.status.tint
                )
            }

            if result.requiresApproval || result.status == .requiresApproval {
                HStack(spacing: 8) {
                    Button {
                        approve()
                    } label: {
                        Label("Approve", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        deny()
                    } label: {
                        Label("Deny", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !result.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(result.query)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }

            Text(result.output)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            FlowLayout(spacing: 8) {
                CapsuleLabel(result.toolKind.title, icon: result.toolKind.icon)
                if result.usedNetwork {
                    CapsuleLabel("Network", icon: "network", tint: .orange)
                }
                if result.modifiedFiles {
                    CapsuleLabel("Writes", icon: "square.and.pencil", tint: .red)
                }
                if result.requiresApproval {
                    CapsuleLabel("Approval", icon: "hand.raised", tint: .orange)
                }
            }
        }
    }
}

private struct AgentsSurface: View {
    @Bindable var store: WorkspaceStore
    @Binding var composerText: String
    var persist: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Agents", "Multi-step workflows use model presets, tools, knowledge, and approval gates.")
            if let currentThread = store.currentAssistantThread {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentThread.title)
                                .font(.headline)
                            Text("\(currentThread.messages.count) messages in the active thread")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ProviderBadge(provider: store.activeProvider)
                    }
                }
                .panelStyle()
            } else {
                EmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "No active thread",
                    detail: "Start a chat to assign an assistant mode and run workflow-oriented prompts."
                )
                .panelStyle()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                AgentWorkflowCard(
                    title: "Research Loop",
                    detail: "Summarize indexed sources and draft a cited answer inside the current thread.",
                    icon: "magnifyingglass",
                    status: store.knowledgeSources.isEmpty ? "Missing knowledge" : "Ready",
                    tint: store.knowledgeSources.isEmpty ? .orange : .green,
                    actionTitle: "Open Knowledge"
                ) {
                    store.selectedDestination = .knowledge
                }

                AgentWorkflowCard(
                    title: "Coding Assistant",
                    detail: "Review workspace files and terminal permissions before code-focused tasks.",
                    icon: "chevron.left.forwardslash.chevron.right",
                    status: store.toolConfigurations.contains(where: { $0.kind == .localFileRead && $0.isEnabled }) ? "Ready" : "Needs file read",
                    tint: store.toolConfigurations.contains(where: { $0.kind == .localFileRead && $0.isEnabled }) ? .green : .orange,
                    actionTitle: "Open Tools"
                ) {
                    store.selectedDestination = .tools
                }

                AgentWorkflowCard(
                    title: "Model Judge",
                    detail: "Compare more than one enabled provider or apply a preset before evaluation.",
                    icon: "rectangle.split.3x1",
                    status: store.providerConfigurations.filter(\.isEnabled).count > 1 ? "Ready" : "Need 2 providers",
                    tint: store.providerConfigurations.filter(\.isEnabled).count > 1 ? .green : .orange,
                    actionTitle: "Open Models"
                ) {
                    store.selectedDestination = .models
                }

                AgentWorkflowCard(
                    title: "Prompt Runner",
                    detail: "Load a saved system prompt into chat and iterate without leaving the workspace.",
                    icon: "text.cursor",
                    status: store.promptProfiles.isEmpty ? "No prompts" : "Ready",
                    tint: store.promptProfiles.isEmpty ? .orange : .green,
                    actionTitle: "Open Prompts"
                ) {
                    store.selectedDestination = .prompts
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Safe local actions")
                        .font(.headline)
                    Spacer()
                    Text("\(store.safeLocalActions.count) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if store.safeLocalActions.isEmpty {
                    EmptyState(
                        icon: "shield.lefthalf.filled",
                        title: "No safe actions queued",
                        detail: "Select an asset or draft elsewhere in the workspace to expose local transcript, summary, linking, or scheduling actions."
                    )
                    .frame(minHeight: 140)
                } else {
                    ForEach(store.safeLocalActions) { action in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(action.title)
                                    .font(.headline)
                                Text(action.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Run") {
                                runSafeAction(action.kind)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .panelStyle()

            HStack {
                Button("Load research prompt") {
                    composerText = "Search my indexed knowledge, summarize the strongest findings, and answer with explicit local citations."
                    store.selectedDestination = .home
                }
                .buttonStyle(.bordered)

                Button("Load model comparison prompt") {
                    composerText = "Compare the enabled providers for cost, privacy, and tool support, then recommend the best default preset."
                    store.selectedDestination = .home
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func runSafeAction(_ kind: LocalActionKind) {
        switch kind {
        case .captureURL:
            store.linkSelectedAssetToCurrentProject()
        case .importTranscript:
            store.queueTranscriptImport()
        case .generateSummary:
            store.summarizeSelectedAsset()
        case .createDraft:
            store.draftFromSelectedAsset()
        case .scheduleDraft:
            store.scheduleSelectedDraft()
        case .runAutomation, .runTool, .exportDraft:
            break
        }
        persist()
    }
}

private enum PromptFilter: String, CaseIterable, Identifiable {
    case all
    case `default`
    case tagged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .default:
            "Default"
        case .tagged:
            "Tagged"
        }
    }

    func matches(_ profile: SystemPromptProfile) -> Bool {
        switch self {
        case .all:
            true
        case .default:
            profile.isDefault
        case .tagged:
            !profile.tags.isEmpty
        }
    }
}

private struct PromptSurface: View {
    @Bindable var store: WorkspaceStore
    @Binding var composerText: String
    var persist: () -> Void
    @State private var filter: PromptFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle("Prompt library", "System profiles, prompt variables, and saved chains.")
                Spacer()
                Menu {
                    ForEach(PromptFilter.allCases) { option in
                        Button(option.title) {
                            filter = option
                        }
                    }
                } label: {
                    Label(filter.title, systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                MetricPill(title: "Profiles", value: "\(store.promptProfiles.count)", icon: "text.cursor")
                MetricPill(title: "Tagged", value: "\(store.promptProfiles.filter { !$0.tags.isEmpty }.count)", icon: "tag")
                MetricPill(title: "Default", value: defaultPromptTitle, icon: "checkmark.circle")
            }
            .panelStyle()

            if filteredPrompts.isEmpty {
                EmptyState(
                    icon: "text.cursor",
                    title: "No prompts in this view",
                    detail: "Switch the prompt filter or add saved system profiles from the Prompts surface."
                )
                .panelStyle()
            } else {
                ForEach(filteredPrompts) { profile in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.title)
                                    .font(.headline)
                                Text(profile.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if profile.isDefault || store.preferences.defaultSystemPromptProfileID == profile.id {
                                StatusBadge(text: "Default", icon: "checkmark.circle", tint: .green)
                            }
                        }

                        if !profile.tags.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(profile.tags.unique(), id: \.self) { tag in
                                    CapsuleLabel(tag, icon: "tag")
                                }
                            }
                        }

                        Text(profile.prompt)
                            .font(.caption)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Use in Chat") {
                                composerText = store.renderPromptProfile(profile)
                                store.selectedDestination = .home
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Set Default") {
                                for index in store.promptProfiles.indices {
                                    store.promptProfiles[index].isDefault = store.promptProfiles[index].id == profile.id
                                }
                                store.preferences.defaultSystemPromptProfileID = profile.id
                                persist()
                            }
                            .buttonStyle(.bordered)

                            Spacer()
                        }
                    }
                    .panelStyle()
                }
            }
        }
    }

    private var filteredPrompts: [SystemPromptProfile] {
        store.promptProfiles.filter(filter.matches)
    }

    private var defaultPromptTitle: String {
        store.promptProfiles.first(where: { $0.id == store.preferences.defaultSystemPromptProfileID })?.title
            ?? store.promptProfiles.first(where: \.isDefault)?.title
            ?? "None"
    }
}

private struct LegacySettingsSurface: View {
    @Bindable var store: WorkspaceStore
    var persist: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Settings", "Privacy, storage, defaults, and developer bridge configuration.")

            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy and approvals")
                    .font(.headline)

                Toggle("Local-only mode", isOn: Binding(
                    get: { store.preferences.localOnlyMode ?? true },
                    set: {
                        store.preferences.localOnlyMode = $0
                        if !$0 {
                            store.preferences.allowCloudProviders = true
                        }
                        persist()
                    }
                ))

                Toggle("Allow cloud providers", isOn: Binding(
                    get: { store.preferences.allowCloudProviders ?? false },
                    set: {
                        store.preferences.allowCloudProviders = $0
                        if !$0 {
                            store.preferences.localOnlyMode = true
                        }
                        persist()
                    }
                ))

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
            .panelStyle()

            VStack(alignment: .leading, spacing: 12) {
                Text("Defaults")
                    .font(.headline)

                Picker("Default destination", selection: Binding(
                    get: { store.preferences.defaultDestination },
                    set: {
                        store.preferences.defaultDestination = $0
                        persist()
                    }
                )) {
                    ForEach([WorkspaceDestination.home, .models, .knowledge, .tools, .agents, .prompts, .settings], id: \.self) { destination in
                        Text(destination.title).tag(destination)
                    }
                }

                Picker("Transcript language", selection: Binding(
                    get: { store.preferences.defaultTranscriptLanguageCode ?? "en" },
                    set: {
                        store.preferences.defaultTranscriptLanguageCode = $0
                        persist()
                    }
                )) {
                    ForEach(["en", "es", "fr", "de", "ja"], id: \.self) { code in
                        Text(code.uppercased()).tag(code)
                    }
                }

                Picker("Default prompt", selection: Binding(
                    get: { store.preferences.defaultSystemPromptProfileID },
                    set: {
                        store.preferences.defaultSystemPromptProfileID = $0
                        for index in store.promptProfiles.indices {
                            store.promptProfiles[index].isDefault = store.promptProfiles[index].id == $0
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

                Picker("Default model preset", selection: Binding(
                    get: { store.preferences.defaultModelPresetID },
                    set: {
                        store.preferences.defaultModelPresetID = $0
                        persist()
                    }
                )) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(store.modelPresets) { preset in
                        Text(preset.title).tag(Optional(preset.id))
                    }
                }
                .disabled(store.modelPresets.isEmpty)
            }
            .panelStyle()

            VStack(alignment: .leading, spacing: 12) {
                Text("Workspace behavior")
                    .font(.headline)

                Toggle("Show inspector by default", isOn: Binding(
                    get: { store.preferences.showsRightSidebar },
                    set: {
                        store.preferences.showsRightSidebar = $0
                        persist()
                    }
                ))

                Toggle("Automations enabled", isOn: Binding(
                    get: { store.preferences.automationsEnabled ?? true },
                    set: {
                        store.preferences.automationsEnabled = $0
                        persist()
                    }
                ))
            }
            .panelStyle()

            VStack(alignment: .leading, spacing: 12) {
                Text("Storage")
                    .font(.headline)

                TextField("Draft export directory", text: Binding(
                    get: { store.preferences.draftExportDirectory ?? "" },
                    set: {
                        store.preferences.draftExportDirectory = $0
                        persist()
                    }
                ))
                .textFieldStyle(.roundedBorder)

                TextField("Local storage label", text: Binding(
                    get: { store.preferences.localStorageLabel ?? "" },
                    set: {
                        store.preferences.localStorageLabel = $0
                        persist()
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
            .panelStyle()

            VStack(alignment: .leading, spacing: 8) {
                Text("Secrets")
                    .font(.headline)
                Text("API keys are represented in SwiftData only by Keychain references. The key material itself belongs in macOS Keychain through `KeychainSecretStore`.")
                    .foregroundStyle(.secondary)
            }
            .panelStyle()

            VStack(alignment: .leading, spacing: 8) {
                Text("AI SDK bridge")
                    .font(.headline)
                Text("The current Vercel AI SDK is TypeScript/Node focused. Flannel treats it as an optional localhost bridge for workflow agents, not as embedded Swift runtime code.")
                    .foregroundStyle(.secondary)
            }
            .panelStyle()
        }
    }
}

private struct KnowledgeSourceCard: View {
    @Bindable var store: WorkspaceStore
    var sourceID: UUID
    var persist: () -> Void
    @State private var isCapturingPage = false

    private var source: KnowledgeSource? {
        store.knowledgeSources.first(where: { $0.id == sourceID })
    }

    private var capturedWebAsset: LibraryAsset? {
        guard let source,
              source.kind == .webPage else { return nil }
        return store.libraryAssets.first {
            $0.sourceURL?.absoluteString == source.location || $0.sourceIdentifier == source.location
        }
    }

    private var hasCapturedPageText: Bool {
        capturedWebAsset?.transcript?.status == .available
            && capturedWebAsset?.transcript?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var manifest: KnowledgeIndexManifest? {
        store.knowledgeIndexManifests.first { $0.sourceID == sourceID }
    }

    private var modelOptions: [String] {
        let discovered = store.localDiscoveryResults.flatMap(\.models).map(\.name)
        let configured = store.providerConfigurations.flatMap(\.availableModels)
        return Array(Set([LocalEmbeddingService.deterministicModelIdentifier] + discovered + configured)).sorted()
    }

    var body: some View {
        if let source {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(source.title, systemImage: source.kind.icon)
                            .font(.headline)
                        Text(source.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    Spacer()
                    StatusBadge(text: source.status.title, icon: source.status.icon, tint: source.status.tint)
                }

                FlowLayout(spacing: 8) {
                    CapsuleLabel("\(source.chunkCount) chunks", icon: "square.stack.3d.up")
                    if source.documentCount > 0 {
                        CapsuleLabel("\(source.documentCount) docs", icon: "doc.text")
                    }
                    if source.embeddingRecordCount > 0 {
                        CapsuleLabel("\(source.embeddingRecordCount) vectors", icon: "point.3.connected.trianglepath.dotted")
                    }
                    CapsuleLabel(source.isWatched ? "Watched" : "Manual", icon: source.isWatched ? "eye" : "hand.point.up.left")
                    if !source.exclusionRules.isEmpty {
                        CapsuleLabel("\(source.exclusionRules.count) excludes", icon: "line.3.horizontal.decrease.circle")
                    }
                    if let embeddingModel = source.embeddingModelIdentifier, !embeddingModel.isEmpty {
                        CapsuleLabel(embeddingModel, icon: "cpu")
                    }
                    if source.kind == .webPage {
                        CapsuleLabel(
                            hasCapturedPageText ? "Captured text" : "Needs capture",
                            icon: hasCapturedPageText ? "doc.text.magnifyingglass" : "network",
                            tint: hasCapturedPageText ? .green : .orange
                        )
                    }
                }

                if source.kind == .webPage,
                   let transcript = capturedWebAsset?.transcript,
                   transcript.status == .available,
                   !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(String(transcript.text.prefix(520)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let manifest {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Index manifest")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            CapsuleLabel(manifest.embeddingState.title, icon: manifest.embeddingState.icon)
                            if let vectorDimension = manifest.vectorDimension {
                                CapsuleLabel("\(vectorDimension)d", icon: "ruler")
                            }
                            if let provider = manifest.embeddingProviderKind {
                                CapsuleLabel(provider.title, icon: "cpu")
                            }
                        }
                        Text(manifest.storageLocation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                        if let fingerprint = manifest.contentFingerprint {
                            Text("Fingerprint \(String(fingerprint.prefix(16)))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let error = source.lastErrorMessage ?? manifest?.lastErrorMessage,
                   !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                HStack {
                    Toggle("Watch for updates", isOn: watchedBinding(defaultValue: source.isWatched))
                    Spacer()
                    if let lastIndexedAt = source.lastIndexedAt {
                        Text("Indexed \(lastIndexedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Embedding model")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Embedding model", selection: embeddingBinding(defaultValue: source.embeddingModelIdentifier ?? "")) {
                        Text("None").tag("")
                        ForEach(modelOptions, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }

                HStack {
                    Button("Rebuild Now") {
                        guard let index = store.knowledgeSources.firstIndex(where: { $0.id == sourceID }) else { return }
                        store.knowledgeSources[index].status = .queued
                        Task { @MainActor in
                            await store.rebuildKnowledgeIndexManifestsUsingConfiguredEmbeddings(onlyQueued: true)
                            persist()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button(source.status == .queued || source.status == .indexing ? "Reset Queue" : "Queue Index") {
                        guard let index = store.knowledgeSources.firstIndex(where: { $0.id == sourceID }) else { return }
                        if store.knowledgeSources[index].status == .queued || store.knowledgeSources[index].status == .indexing {
                            store.knowledgeSources[index].status = .notIndexed
                        } else {
                            store.knowledgeSources[index].status = .queued
                        }
                        persist()
                    }
                    .buttonStyle(.bordered)

                    if source.kind == .webPage {
                        Button {
                            capturePage()
                        } label: {
                            Label(
                                hasCapturedPageText ? "Refresh Capture" : "Capture Page",
                                systemImage: isCapturingPage ? "arrow.triangle.2.circlepath" : "doc.text.magnifyingglass"
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCapturingPage)
                    }

                    if source.status == .ready {
                        Button("Mark Stale") {
                            guard let index = store.knowledgeSources.firstIndex(where: { $0.id == sourceID }) else { return }
                            store.knowledgeSources[index].status = .stale
                            persist()
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                }

                if !source.exclusionRules.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Exclusions")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(source.exclusionRules.unique(), id: \.self) { rule in
                                CapsuleLabel(rule, icon: "minus.circle")
                            }
                        }
                    }
                }
            }
            .panelStyle()
        }
    }

    private func watchedBinding(defaultValue: Bool) -> Binding<Bool> {
        Binding {
            store.knowledgeSources.first(where: { $0.id == sourceID })?.isWatched ?? defaultValue
        } set: { newValue in
            guard let index = store.knowledgeSources.firstIndex(where: { $0.id == sourceID }) else { return }
            store.knowledgeSources[index].isWatched = newValue
            persist()
        }
    }

    private func embeddingBinding(defaultValue: String) -> Binding<String> {
        Binding {
            store.knowledgeSources.first(where: { $0.id == sourceID })?.embeddingModelIdentifier ?? defaultValue
        } set: { newValue in
            guard let index = store.knowledgeSources.firstIndex(where: { $0.id == sourceID }) else { return }
            store.knowledgeSources[index].embeddingModelIdentifier = newValue.isEmpty ? nil : newValue
            persist()
        }
    }

    private func capturePage() {
        guard !isCapturingPage else { return }
        isCapturingPage = true
        Task { @MainActor in
            _ = await store.captureWebPageKnowledgeSource(sourceID)
            persist()
            isCapturingPage = false
        }
    }
}

private struct AgentWorkflowCard: View {
    var title: String
    var detail: String
    var icon: String
    var status: String
    var tint: Color
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.title3)
                Spacer()
                StatusBadge(text: status, icon: "circle.fill", tint: tint)
            }

            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
        .panelStyle()
    }
}

private struct FlowLayout<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        _FlowWrapLayout(spacing: spacing) {
            content()
        }
    }
}

private struct _FlowWrapLayout: Layout {
    var spacing: CGFloat
    private static let fallbackMaxWidth: CGFloat = 640

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = resolvedMaxWidth(proposalWidth: proposal.width)
        let itemSpacing = sanitizedSpacing
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = measuredSize(for: subview, maxWidth: maxWidth)
            let proposedRowWidth = rowWidth == 0 ? size.width : rowWidth + itemSpacing + size.width

            if proposedRowWidth > maxWidth, rowWidth > 0 {
                widestRow = max(widestRow, rowWidth)
                totalHeight += rowHeight + itemSpacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = proposedRowWidth
                rowHeight = max(rowHeight, size.height)
            }
        }

        widestRow = max(widestRow, rowWidth)
        totalHeight += rowHeight

        return CGSize(
            width: resolvedOutputWidth(proposalWidth: proposal.width, widestRow: widestRow),
            height: max(0, totalHeight)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = resolvedMaxWidth(proposalWidth: proposal.width, boundsWidth: bounds.width)
        let itemSpacing = sanitizedSpacing
        let rowMaxX = bounds.minX + maxWidth
        var point = bounds.origin
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = measuredSize(for: subview, maxWidth: maxWidth)
            let nextX = point.x == bounds.minX ? point.x + size.width : point.x + itemSpacing + size.width

            if nextX > rowMaxX, point.x > bounds.minX {
                point.x = bounds.minX
                point.y += lineHeight + itemSpacing
                lineHeight = 0
            } else if point.x > bounds.minX {
                point.x += itemSpacing
            }

            subview.place(
                at: point,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            point.x += size.width
            lineHeight = max(lineHeight, size.height)
        }
    }

    private var sanitizedSpacing: CGFloat {
        guard spacing.isFinite, spacing > 0 else { return 0 }
        return spacing
    }

    private func resolvedMaxWidth(proposalWidth: CGFloat?, boundsWidth: CGFloat? = nil) -> CGFloat {
        if let boundsWidth, boundsWidth.isFinite, boundsWidth > 0 {
            return boundsWidth
        }

        if let proposalWidth, proposalWidth.isFinite, proposalWidth > 0 {
            return proposalWidth
        }

        return Self.fallbackMaxWidth
    }

    private func resolvedOutputWidth(proposalWidth: CGFloat?, widestRow: CGFloat) -> CGFloat {
        if let proposalWidth, proposalWidth.isFinite, proposalWidth > 0 {
            return proposalWidth
        }

        return max(0, min(widestRow, Self.fallbackMaxWidth))
    }

    private func measuredSize(for subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let rawIdealSize = subview.sizeThatFits(.unspecified)
        let idealSize = sanitizedSize(rawIdealSize, maxWidth: maxWidth)

        guard !rawIdealSize.width.isFinite || !rawIdealSize.height.isFinite || idealSize.width >= maxWidth else {
            return idealSize
        }

        return sanitizedSize(
            subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil)),
            maxWidth: maxWidth
        )
    }

    private func sanitizedSize(_ size: CGSize, maxWidth: CGFloat) -> CGSize {
        let width = size.width.isFinite ? max(0, min(size.width, maxWidth)) : maxWidth
        let height = size.height.isFinite ? max(0, size.height) : 0
        return CGSize(width: width, height: height)
    }
}

private struct MigrationSurface: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Workspace data", "Existing creator-workspace records remain available as local knowledge inputs.")
            Text("The previous capture, draft, and calendar entities are preserved for migration and can be indexed into Flannel knowledge sources. New work should start from Chat, Models, Knowledge, Tools, Agents, and Prompts.")
                .foregroundStyle(.secondary)
            Button("Return to Chat") {
                store.selectedDestination = .home
            }
        }
        .panelStyle()
    }
}

private struct InspectorSurface: View {
    @Bindable var store: WorkspaceStore
    var selectedComparisonRunID: UUID?
    var selectedComparisonResultID: UUID?
    var isDiscoveringModels: Bool
    var isRunningComparison: Bool
    var focusRequest: Int
    var discoverModels: () -> Void
    var collapseArtifacts: () -> Void
    var copyComparisonResult: (ModelComparisonResult) -> Void
    var useComparisonResultProvider: (ModelComparisonResult) -> Void
    var openSettingsTab: (SettingsTab) -> Void
    var persist: () -> Void
    @SceneStorage("flannel.inspector.activeSection") private var activeSectionRawValue = FlannelInspectorSection.chatDetail.rawValue
    @FocusState private var isCollapseButtonFocused: Bool

    private var hasCompareArtifacts: Bool {
        selectedComparisonRunID != nil || !store.modelComparisonRuns.isEmpty || isRunningComparison
    }

    private var hasSourceArtifacts: Bool {
        !currentCitations.isEmpty
    }

    private var hasToolArtifacts: Bool {
        !currentThreadToolResults.isEmpty
    }

    private var hasContextualArtifacts: Bool {
        hasCompareArtifacts || hasSourceArtifacts || hasToolArtifacts
    }

    private var availableSections: [FlannelInspectorSection] {
        FlannelInspectorSection.availableSections(
            hasCompareArtifacts: hasCompareArtifacts,
            hasSourceArtifacts: hasSourceArtifacts,
            hasToolArtifacts: hasToolArtifacts
        )
    }

    private var availableSectionIDs: [String] {
        availableSections.map(\.rawValue)
    }

    private var fallbackSection: FlannelInspectorSection {
        FlannelInspectorSection.defaultSection(
            hasCompareArtifacts: hasCompareArtifacts,
            hasSourceArtifacts: hasSourceArtifacts,
            hasToolArtifacts: hasToolArtifacts
        )
    }

    private var activeSection: FlannelInspectorSection {
        get {
            let storedSection = FlannelInspectorSection(rawValue: activeSectionRawValue) ?? fallbackSection
            return availableSections.contains(storedSection) ? storedSection : fallbackSection
        }
        nonmutating set {
            activeSectionRawValue = newValue.rawValue
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Artifacts")
                            .font(.headline)
                        Text("Thread detail, sources, tool traces, and comparisons")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Button(action: collapseArtifacts) {
                        Label("Collapse Artifacts", systemImage: "sidebar.right")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .flannelGlassCapsule(.clear, interactive: true)
                    .focused($isCollapseButtonFocused)
                    .help("Collapse Artifacts")
                    .accessibilityLabel("Collapse Artifacts")
                }

                if availableSections.count > 1 {
                    InspectorSectionSelector(
                        sections: availableSections,
                        activeSection: activeSection,
                        count: sectionCount,
                        select: { activeSection = $0 }
                    )
                }

                if !hasContextualArtifacts {
                    InspectorCompactEmptySummary(
                        text: "Compare runs, cited sources, and tool traces will appear here as this chat creates them."
                    )
                }

                activeSectionContent
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .onAppear(perform: ensureActiveSectionIsAvailable)
        .onAppear(perform: focusCollapseButtonIfRequested)
        .onChange(of: availableSectionIDs) { _, _ in
            ensureActiveSectionIsAvailable()
        }
        .onChange(of: focusRequest) { _, _ in
            focusCollapseButtonIfRequested()
        }
    }

    private var currentCitations: [AIChatCitation] {
        store.currentAssistantThread?.messages.flatMap(\.citations) ?? []
    }

    private var currentCitationPreviews: [KnowledgeCitationPreview] {
        store.knowledgeCitationPreviews(for: currentCitations)
    }

    private var currentThreadToolResultIDs: Set<UUID> {
        Set(store.currentAssistantThread?.messages.flatMap(\.referencedEntityIDs) ?? [])
    }

    private var currentThreadToolResults: [LocalToolExecutionResult] {
        store.toolExecutionResults
            .filter { currentThreadToolResultIDs.contains($0.id) }
            .sorted(using: KeyPathComparator(\.createdAt, order: .reverse))
    }

    @ViewBuilder
    private var activeSectionContent: some View {
        switch activeSection {
        case .chatDetail:
            ChatDetailInspectorSection(
                store: store,
                openSettingsTab: openSettingsTab,
                persist: persist
            )
        case .sources:
            if hasSourceArtifacts {
                MessageCitationList(
                    previews: currentCitationPreviews,
                    limit: 8,
                    snippetLineLimit: 4
                )
                .panelStyle()
            } else {
                InspectorEmptySection(
                    icon: FlannelInspectorSection.sources.icon,
                    title: "No sources yet",
                    detail: "Citations from local RAG and indexed knowledge will appear here."
                )
            }
        case .compare:
            CompareInspectorSurface(
                store: store,
                selectedRunID: selectedComparisonRunID,
                selectedResultID: selectedComparisonResultID,
                isRunningComparison: isRunningComparison,
                copyResult: copyComparisonResult,
                useResultProvider: useComparisonResultProvider,
                openSettingsTab: openSettingsTab
            )
        case .tools:
            if hasToolArtifacts {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(currentThreadToolResults.prefix(8)) { result in
                        InspectorToolTraceRow(result: result)
                    }
                }
                .panelStyle()
            } else {
                InspectorEmptySection(
                    icon: FlannelInspectorSection.tools.icon,
                    title: "No tool traces yet",
                    detail: "Approved local tool runs and command results will appear here."
                )
            }
        }
    }

    private func ensureActiveSectionIsAvailable() {
        guard let storedSection = FlannelInspectorSection(rawValue: activeSectionRawValue),
              availableSections.contains(storedSection) else {
            activeSection = fallbackSection
            return
        }
    }

    private func focusCollapseButtonIfRequested() {
        guard focusRequest > 0 else { return }
        DispatchQueue.main.async {
            isCollapseButtonFocused = true
        }
    }

    private func sectionCount(_ section: FlannelInspectorSection) -> Int {
        switch section {
        case .chatDetail:
            store.currentAssistantThread == nil ? 0 : 1
        case .sources:
            currentCitations.count
        case .compare:
            max(store.modelComparisonRuns.count, isRunningComparison ? 1 : 0)
        case .tools:
            currentThreadToolResults.count
        }
    }

}

private struct InspectorSectionSelector: View {
    var sections: [FlannelInspectorSection]
    var activeSection: FlannelInspectorSection
    var count: (FlannelInspectorSection) -> Int
    var select: (FlannelInspectorSection) -> Void

    private var selection: Binding<FlannelInspectorSection> {
        Binding(
            get: { activeSection },
            set: select
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Artifact section", selection: selection) {
                ForEach(sections) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel("Artifact section")
        }
        .padding(4)
        .flannelChromePanel(cornerRadius: 14)
    }
}

private struct ChatDetailInspectorSection: View {
    @Bindable var store: WorkspaceStore
    var openSettingsTab: (SettingsTab) -> Void
    var persist: () -> Void
    @SceneStorage("flannel.inspector.chatDetail.scopeEditor") private var isEditingKnowledgeScope = false

    private var thread: AssistantThread? {
        store.currentAssistantThread
    }

    private var sortedSources: [KnowledgeSource] {
        store.knowledgeSources.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var selectedSourceIDs: Set<UUID>? {
        store.threadKnowledgeSourceScope(for: thread)
    }

    private var activeSourceSummary: String {
        guard !store.knowledgeSources.isEmpty else {
            return "No sources configured"
        }
        guard let selectedSourceIDs else {
            return "All \(store.knowledgeSources.count) workspace source\(store.knowledgeSources.count == 1 ? "" : "s")"
        }
        return "\(selectedSourceIDs.count) selected source\(selectedSourceIDs.count == 1 ? "" : "s")"
    }

    var body: some View {
        if let thread {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Chat title", text: titleBinding(for: thread.id))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Chat title")

                HStack(spacing: 6) {
                    CapsuleLabel("\(thread.messages.count) messages", icon: "text.bubble")
                    if thread.isPinned {
                        CapsuleLabel("Pinned", icon: "pin")
                    }
                    if thread.isArchived {
                        CapsuleLabel("Archived", icon: "archivebox")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Knowledge Scope")
                                .font(.caption.weight(.semibold))
                            Text(activeSourceSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)

                        Button {
                            withAnimation(.snappy(duration: 0.16)) {
                                isEditingKnowledgeScope.toggle()
                            }
                        } label: {
                            Label(isEditingKnowledgeScope ? "Done" : "Edit Scope", systemImage: isEditingKnowledgeScope ? "checkmark" : "slider.horizontal.3")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(store.knowledgeSources.isEmpty)
                    }

                    if store.knowledgeSources.isEmpty {
                        InspectorEmptySection(
                            icon: "books.vertical",
                            title: "No knowledge sources",
                            detail: "Add files, folders, notes, or chat history sources in Knowledge settings."
                        )
                    } else if isEditingKnowledgeScope {
                        Toggle("Use custom source set", isOn: customScopeBinding(for: thread.id))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(store.knowledgeSources.isEmpty)
                            .help("Use a custom source set for this chat")

                        ForEach(sortedSources.prefix(8)) { source in
                            Toggle(isOn: sourceBinding(for: source, threadID: thread.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(source.title, systemImage: source.kind.icon)
                                        .font(.caption.weight(.semibold))
                                    Text(source.kind.title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .disabled(selectedSourceIDs == nil)
                        }

                        if sortedSources.count > 8 {
                            Text("+\(sortedSources.count - 8) more sources available in Knowledge settings")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Retrieval will use \(activeSourceSummary.lowercased()).", systemImage: selectedSourceIDs == nil ? "books.vertical" : "checklist")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        openSettingsTab(.knowledge)
                    } label: {
                        Label("Manage Knowledge", systemImage: "books.vertical")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        } else {
            InspectorEmptySection(
                icon: "bubble.left.and.text.bubble.right",
                title: "No selected chat",
                detail: "Select or start a chat to configure its local context."
            )
        }
    }

    private func titleBinding(for threadID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.assistantThreads.first(where: { $0.id == threadID })?.title ?? ""
            },
            set: { newValue in
                _ = store.renameAssistantThread(threadID, to: newValue)
                persist()
            }
        )
    }

    private func customScopeBinding(for threadID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedSourceIDs != nil },
            set: { isCustom in
                let allIDs = Set(store.knowledgeSources.map(\.id))
                _ = store.setThreadKnowledgeSourceScope(isCustom ? allIDs : [], threadID: threadID)
                persist()
            }
        )
    }

    private func sourceBinding(for source: KnowledgeSource, threadID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                selectedSourceIDs?.contains(source.id) ?? true
            },
            set: { isSelected in
                let allIDs = Set(store.knowledgeSources.map(\.id))
                var scope = selectedSourceIDs ?? allIDs
                if isSelected {
                    scope.insert(source.id)
                } else {
                    scope.remove(source.id)
                }
                _ = store.setThreadKnowledgeSourceScope(scope == allIDs ? [] : scope, threadID: threadID)
                persist()
            }
        )
    }
}

private struct InspectorCompactEmptySummary: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "tray")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .flannelChromePanel(cornerRadius: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

private struct InspectorEmptySection: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InspectorToolTraceRow: View {
    var result: LocalToolExecutionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Label(result.title, systemImage: result.toolKind.icon)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                StatusBadge(text: result.status.title, icon: result.status.icon, tint: result.status.tint)
            }

            if !result.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(result.query)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Text(result.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LocalDiscoveryResultRow: View {
    var result: LocalProviderDiscoveryResult

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.providerKind.title)
                        .font(.caption.weight(.semibold))
                    Text(result.endpoint)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                StatusBadge(text: result.status.title, icon: result.status.icon, tint: result.status.tint)
            }

            if result.models.isEmpty {
                Text(result.errorMessage ?? "No models returned by this endpoint.")
                    .font(.caption)
                    .foregroundStyle(result.status == .ready ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(result.models.prefix(4)) { model in
                        CapsuleLabel(model.name, icon: model.capabilities.contains(.vision) ? "eye" : "cpu")
                    }
                    if result.models.count > 4 {
                        CapsuleLabel("+\(result.models.count - 4) more", icon: "ellipsis")
                    }
                }
            }

            Label(result.discoveredAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CompareInspectorSurface: View {
    @Bindable var store: WorkspaceStore
    var selectedRunID: UUID?
    var selectedResultID: UUID?
    var isRunningComparison: Bool
    var copyResult: (ModelComparisonResult) -> Void
    var useResultProvider: (ModelComparisonResult) -> Void
    var openSettingsTab: (SettingsTab) -> Void

    private var selectedRun: ModelComparisonRun? {
        if let selectedRunID,
           let run = store.modelComparisonRuns.first(where: { $0.id == selectedRunID }) {
            return run
        }
        return store.modelComparisonRuns.first
    }

    private var selectedResult: ModelComparisonResult? {
        guard let run = selectedRun else { return nil }
        if let selectedResultID,
           let result = run.results.first(where: { $0.id == selectedResultID }) {
            return result
        }
        return run.results.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Compare run")
                    .font(.headline)
                Spacer()
                if let selectedRun {
                    StatusBadge(text: selectedRun.status.title, icon: selectedRun.status.icon, tint: selectedRun.status.tint)
                }
            }

            if let selectedRun {
                Text(selectedRun.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .textSelection(.enabled)

                FlowLayout(spacing: 8) {
                    CapsuleLabel("\(selectedRun.results.count) providers", icon: "cpu")
                    CapsuleLabel("\(selectedRun.citations.count) sources", icon: "books.vertical")
                    CapsuleLabel(selectedRun.createdAt.formatted(date: .abbreviated, time: .shortened), icon: "clock")
                }

                if let selectedResult {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedResult.providerDisplayName)
                                    .font(.headline)
                                Text(selectedResult.modelIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            StatusBadge(text: selectedResult.status.title, icon: selectedResult.status.icon, tint: selectedResult.status.tint)
                        }

                        FlowLayout(spacing: 8) {
                            CapsuleLabel(selectedResult.accessMode.title, icon: selectedResult.accessMode.icon)
                            CapsuleLabel(selectedResult.privacyScope.title, icon: selectedResult.privacyScope.icon)
                            if let inputTokenCount = selectedResult.inputTokenCount,
                               let outputTokenCount = selectedResult.outputTokenCount {
                                CapsuleLabel("\(inputTokenCount) in / \(outputTokenCount) out", icon: "text.word.spacing")
                                if selectedResult.tokenCountsAreEstimated {
                                    CapsuleLabel("Estimated tokens", icon: "function")
                                }
                            }
                            if let latencyMilliseconds = selectedResult.latencyMilliseconds {
                                CapsuleLabel(latencyMilliseconds.formattedLatency, icon: "timer")
                            }
                            if let firstTokenLatencyMilliseconds = selectedResult.firstTokenLatencyMilliseconds {
                                CapsuleLabel("First token \(firstTokenLatencyMilliseconds.formattedLatency)", icon: "bolt.horizontal")
                            }
                            if let estimatedCostMicros = selectedResult.estimatedCostMicros,
                               estimatedCostMicros > 0 {
                                CapsuleLabel(estimatedCostMicros.formattedMicrosCost, icon: "dollarsign.circle")
                            }
                        }

                        if let error = selectedResult.errorMessage,
                           !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !selectedResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(selectedResult.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(7)
                                .textSelection(.enabled)
                        }

                        HStack {
                            Button {
                                copyResult(selectedResult)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button {
                                useResultProvider(selectedResult)
                            } label: {
                                Label("Use Model", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!store.providerConfigurations.contains(where: { $0.id == selectedResult.providerID }))
                        }
                    }
                } else {
                    Text("Select a result card to inspect provider output, latency, cost, and privacy details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Button {
                        openSettingsTab(.models)
                    } label: {
                        Label("Models", systemImage: "cpu")
                    }
                    .buttonStyle(.bordered)
                    .help("Open Models settings")
                }
            } else {
                if isRunningComparison {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Running comparison")
                                .font(.caption.weight(.semibold))
                            Text("Model responses will appear here as soon as they finish.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    InspectorEmptySection(
                        icon: "rectangle.split.3x1",
                        title: "No comparison selected",
                        detail: "Run a side-by-side prompt to inspect model behavior, privacy scope, latency, tokens, and cost here."
                    )
                }
            }
        }
        .panelStyle()
    }
}

private struct SectionTitle: View {
    var title: String
    var subtitle: String

    init(_ title: String, _ subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InspectorSectionHeader: View {
    var title: String
    var count: Int
    var icon: String

    init(_ title: String, count: Int, icon: String) {
        self.title = title
        self.count = count
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count) \(count == 1 ? "item" : "items")")
    }
}

private struct MetricPill: View {
    var title: String
    var value: String
    var icon: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.headline)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProviderBadge: View {
    var provider: ProviderConfiguration?

    var body: some View {
        if let provider {
            Label(provider.displayName, systemImage: provider.privacyScope == .localOnly ? "lock" : "network")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: Capsule())
        } else {
            Label("No provider", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}

private struct ProviderRouteReadiness {
    var text: String
    var icon: String
    var tint: Color
}

private struct ProviderRoutingPicker: View {
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
                    return (lhs.displayName ?? lhs.name).localizedCaseInsensitiveCompare(rhs.displayName ?? rhs.name) == .orderedAscending
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
                    ProviderRoutingCurrentMenuRow(
                        selectedProvider: selectedProvider,
                        routingPolicy: store.preferences.providerRoutingPolicy,
                        readiness: selectedReadiness,
                        isDiscoveringModels: isDiscoveringModels
                    )
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
                            LocalModelRoutingMenuRow(
                                model: model,
                                isSelected: isSelected(model)
                            )
                        }
                    }
                }
            }

            ForEach(ProviderModeFamily.allCases) { family in
                let familyProviders = providers(in: family)
                if !familyProviders.isEmpty {
                    Section(family.title) {
                        if let prompt = family.modeChoicePrompt {
                            Button { } label: {
                                ProviderModeFamilyPromptMenuRow(
                                    prompt: prompt,
                                    icon: family.icon
                                )
                            }
                            .disabled(true)
                        }

                        ForEach(familyProviders) { provider in
                            let modelNames = selectableModelNames(for: provider)
                            if modelNames.isEmpty {
                                Button {
                                    select(provider)
                                } label: {
                                    ProviderRoutingMenuRow(
                                        provider: provider,
                                        readiness: readiness(for: provider),
                                        isPreferred: preferredProvider?.id == provider.id,
                                        isActive: store.activeProvider?.id == provider.id
                                    )
                                }
                            } else {
                                Menu {
                                    Button {
                                        select(provider)
                                    } label: {
                                        Label(
                                            currentModelMenuTitle(for: provider),
                                            systemImage: preferredProvider?.id == provider.id ? "checkmark" : provider.privacyScope.icon
                                        )
                                    }

                                    Section("Models") {
                                        ForEach(modelNames, id: \.self) { modelName in
                                            Button {
                                                select(provider, modelIdentifier: modelName)
                                            } label: {
                                                ProviderModelRoutingMenuRow(
                                                    modelName: modelName,
                                                    provider: provider,
                                                    isSelected: provider.modelIdentifier == modelName,
                                                    isActive: store.activeProvider?.id == provider.id
                                                        && store.activeProvider?.modelIdentifier == modelName
                                                )
                                            }
                                        }
                                    }
                                } label: {
                                    ProviderRoutingMenuRow(
                                        provider: provider,
                                        readiness: readiness(for: provider),
                                        isPreferred: preferredProvider?.id == provider.id,
                                        isActive: store.activeProvider?.id == provider.id
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
                Text(model.displayName ?? model.name)
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
        var parts: [String] = []
        if (model.loadedInstanceCount ?? 0) > 0 {
            parts.append("Loaded")
        }
        if let contextWindowTokens = model.contextWindowTokens {
            parts.append("\(contextWindowTokens.formatted()) context")
        }
        if let parameterSize = model.parameterSize {
            parts.append(parameterSize)
        }
        if let quantization = model.quantization {
            parts.append(quantization)
        }
        if model.capabilities.contains(.toolCalling) {
            parts.append("Tools")
        }
        if model.capabilities.contains(.vision) {
            parts.append("Vision")
        }
        if model.capabilities.contains(.reasoning) {
            parts.append("Reasoning")
        }
        return parts.isEmpty ? "\(model.providerKind.title) local chat model" : parts.joined(separator: " - ")
    }

    private var subtitle: String {
        var parts = [model.providerKind.title]
        if let displayName = model.displayName,
           displayName.localizedCaseInsensitiveCompare(model.name) != .orderedSame {
            parts.append(model.name)
        }
        parts.append(detail.replacingOccurrences(of: " - ", with: " • "))
        return parts.joined(separator: " • ")
    }
}

private struct StatusBadge: View {
    var text: String
    var icon: String
    var tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct CapsuleLabel: View {
    var text: String
    var icon: String
    var tint: Color?

    init(_ text: String, icon: String, tint: Color? = nil) {
        self.text = text
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(tint ?? .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background((tint ?? .secondary).opacity(tint == nil ? 0.10 : 0.14), in: Capsule())
    }
}

private extension ModelComparisonStatus {
    var title: String {
        switch self {
        case .queued:
            "Queued"
        case .streaming:
            "Streaming"
        case .completed:
            "Complete"
        case .failed:
            "Failed"
        }
    }

    var icon: String {
        switch self {
        case .queued:
            "clock"
        case .streaming:
            "waveform"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .queued:
            .secondary
        case .streaming:
            .indigo
        case .completed:
            .green
        case .failed:
            .orange
        }
    }
}

private extension ProviderSetupDiagnosticSeverity {
    var icon: String {
        switch self {
        case .error:
            "exclamationmark.triangle.fill"
        case .warning:
            "exclamationmark.circle"
        case .info:
            "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .error:
            .red
        case .warning:
            .orange
        case .info:
            .secondary
        }
    }
}

private struct ModePill: View {
    var text: String
    var icon: String

    init(_ text: String, icon: String) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
    }
}

private struct EmptyState: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flannelPaneSurface(.subtle, cornerRadius: FlannelRadius.lg)
    }
}

private extension AssistantRole {
    var title: String {
        switch self {
        case .system:
            "System"
        case .user:
            "You"
        case .assistant:
            "Flannel"
        }
    }

    var symbolName: String {
        switch self {
        case .system:
            "gearshape"
        case .user:
            "person"
        case .assistant:
            "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .system:
            .secondary
        case .user:
            .blue
        case .assistant:
            .indigo
        }
    }
}

private struct MessageMetadataChip: Hashable {
    var title: String
    var icon: String
}

private extension AssistantMessageRunStatus {
    var icon: String {
        switch self {
        case .queued:
            "clock"
        case .streaming:
            "waveform"
        case .completed:
            "checkmark.circle"
        case .fallback:
            "arrow.triangle.2.circlepath"
        case .failed:
            "exclamationmark.triangle"
        case .stopped:
            "stop.circle"
        }
    }
}

private extension AIToolPermissionScope {
    var title: String {
        switch self {
        case .readWorkspace:
            "Read Workspace"
        case .writeWorkspace:
            "Write Workspace"
        case .runShellCommand:
            "Shell"
        case .makeNetworkRequest:
            "Network"
        case .queryRAGIndex:
            "Query RAG"
        case .mutateRAGIndex:
            "Mutate RAG"
        }
    }

    var icon: String {
        switch self {
        case .readWorkspace:
            "doc.text.magnifyingglass"
        case .writeWorkspace:
            "square.and.pencil"
        case .runShellCommand:
            "terminal"
        case .makeNetworkRequest:
            "network"
        case .queryRAGIndex:
            "books.vertical"
        case .mutateRAGIndex:
            "square.stack.3d.up"
        }
    }
}

private extension AIToolCallRecord {
    var statusTitle: String {
        switch executionStatus {
        case .none:
            "Pending"
        case .completed:
            "Executed"
        case .requiresApproval:
            "Approval"
        case .denied:
            "Denied"
        case .blocked:
            "Blocked"
        case .unavailable:
            "Unavailable"
        }
    }

    var statusIcon: String {
        switch executionStatus {
        case .none:
            "clock"
        case .completed:
            "checkmark.circle"
        case .requiresApproval:
            "hand.raised"
        case .denied:
            "xmark.circle"
        case .blocked:
            "lock"
        case .unavailable:
            "exclamationmark.triangle"
        }
    }

    var statusTint: Color {
        switch executionStatus {
        case .none:
            .secondary
        case .completed:
            .green
        case .requiresApproval:
            .orange
        case .denied:
            .red
        case .blocked:
            .orange
        case .unavailable:
            .secondary
        }
    }
}

private extension AssistantMessage {
    var shareText: String {
        var sections = [text.trimmingCharacters(in: .whitespacesAndNewlines)]

        if !toolCalls.isEmpty {
            let toolCallText = toolCalls.map { toolCall in
                var lines = [
                    "- \(toolCall.toolName) [\(toolCall.permissionScope.title); \(toolCall.statusTitle)]"
                ]
                if let providerCallID = toolCall.providerCallID,
                   !providerCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("  Provider call ID: \(providerCallID)")
                }
                if let executionResultID = toolCall.executionResultID {
                    lines.append("  Tool result ID: \(executionResultID.uuidString)")
                }
                if let outputPreview = toolCall.outputPreview,
                   !outputPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("  Output preview: \(outputPreview)")
                }
                if !toolCall.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("  Arguments: \(toolCall.argumentsJSON)")
                }
                return lines.joined(separator: "\n")
            }.joined(separator: "\n")
            sections.append("Requested tool calls:\n\(toolCallText)")
        }

        if !attachments.isEmpty {
            let attachmentText = attachments.map { attachment in
                var lines = [
                    "- \(attachment.title) (\(attachment.displayDetail))"
                ]
                if let localPath = attachment.localPath {
                    lines.append("  Path: \(localPath)")
                }
                if let excerpt = attachment.excerpt,
                   !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("  Excerpt: \(excerpt)")
                }
                return lines.joined(separator: "\n")
            }.joined(separator: "\n")
            sections.append("Attachments:\n\(attachmentText)")
        }

        return sections
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    var metadataChips: [MessageMetadataChip] {
        var chips: [MessageMetadataChip] = []

        if let runStatus {
            chips.append(MessageMetadataChip(title: runStatus.title, icon: runStatus.icon))
        }

        if let providerDisplayName,
           !providerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chips.append(MessageMetadataChip(title: providerDisplayName, icon: "cpu"))
        }

        if let providerAccessMode {
            chips.append(MessageMetadataChip(title: providerAccessMode.title, icon: providerAccessMode.icon))
        }

        if let providerPrivacyScope {
            chips.append(MessageMetadataChip(title: providerPrivacyScope.title, icon: providerPrivacyScope.icon))
        }

        if let modelIdentifier,
           !modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chips.append(MessageMetadataChip(title: modelIdentifier, icon: "memorychip"))
        }

        if let inputTokenCount, let outputTokenCount {
            chips.append(MessageMetadataChip(title: "\(inputTokenCount) in / \(outputTokenCount) out", icon: "text.word.spacing"))
        } else if let outputTokenCount {
            chips.append(MessageMetadataChip(title: "\(outputTokenCount) tokens", icon: "text.word.spacing"))
        }

        if let contextChipTitle {
            chips.append(MessageMetadataChip(title: contextChipTitle, icon: "gauge.with.dots.needle.33percent"))
        }

        if !toolCalls.isEmpty {
            chips.append(MessageMetadataChip(title: "\(toolCalls.count) tool call\(toolCalls.count == 1 ? "" : "s")", icon: "function"))
        }

        if tokenCountsAreEstimated, inputTokenCount != nil || outputTokenCount != nil {
            chips.append(MessageMetadataChip(title: "Estimated tokens", icon: "function"))
        }

        if let latencyMilliseconds {
            chips.append(MessageMetadataChip(title: latencyMilliseconds.formattedLatency, icon: "timer"))
        }

        if let firstTokenLatencyMilliseconds {
            chips.append(MessageMetadataChip(title: "First token \(firstTokenLatencyMilliseconds.formattedLatency)", icon: "bolt.horizontal"))
        }

        if let estimatedCostMicros, estimatedCostMicros > 0 {
            chips.append(MessageMetadataChip(title: estimatedCostMicros.formattedMicrosCost, icon: "dollarsign.circle"))
        }

        if let fallbackReason = fallbackReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallbackReason.isEmpty {
            chips.append(MessageMetadataChip(title: fallbackReason.shortMetadataReason, icon: "exclamationmark.circle"))
        }

        return chips
    }

    private var contextChipTitle: String? {
        guard let contextTokenCount else { return nil }
        if let contextWindowTokens, contextWindowTokens > 0 {
            let percent = Int((Double(contextTokenCount) / Double(contextWindowTokens) * 100).rounded())
            return "\(formatTokens(contextTokenCount)) / \(formatTokens(contextWindowTokens)) ctx (\(percent)%)"
        }
        return "\(formatTokens(contextTokenCount)) ctx"
    }
}

private extension String {
    var shortMetadataReason: String {
        if count <= 54 { return self }
        let end = index(startIndex, offsetBy: 51)
        return "\(self[..<end])..."
    }
}

private extension AIChatAttachment {
    var dedupeKey: String {
        localPath ?? remoteURL?.absoluteString ?? id.uuidString
    }

    var symbolName: String {
        switch kind {
        case .textSnippet:
            "doc.text"
        case .image:
            "photo"
        case .document:
            "doc"
        case .audio:
            "waveform"
        case .workspaceAsset:
            "books.vertical"
        case .externalURL:
            "link"
        case .ragChunk:
            "quote.bubble"
        case .toolResult:
            "wrench.and.screwdriver"
        }
    }
}

private extension Int {
    var formattedLatency: String {
        if self < 1_000 {
            return "\(self) ms"
        }
        let seconds = Double(self) / 1_000
        return "\(seconds.formatted(.number.precision(.fractionLength(1)))) s"
    }

    var formattedMicrosCost: String {
        let dollars = Double(self) / 1_000_000
        return dollars.formatted(.currency(code: "USD").precision(.fractionLength(4)))
    }
}

private extension IntegrationConnectionStatus {
    var title: String {
        switch self {
        case .disconnected:
            "Disconnected"
        case .ready:
            "Ready"
        case .syncing:
            "Syncing"
        case .needsAttention:
            "Needs setup"
        case .rateLimited:
            "Rate limited"
        }
    }

    var icon: String {
        switch self {
        case .ready:
            "checkmark.circle"
        case .syncing:
            "arrow.triangle.2.circlepath"
        case .needsAttention, .rateLimited:
            "exclamationmark.triangle"
        case .disconnected:
            "circle"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            .green
        case .syncing:
            .blue
        case .needsAttention, .rateLimited:
            .orange
        case .disconnected:
            .secondary
        }
    }
}

private extension ProviderAccessMode {
    var icon: String {
        switch self {
        case .localServer:
            "desktopcomputer"
        case .apiKey:
            "key"
        case .subscriptionCLI:
            "terminal"
        case .openAICompatible:
            "arrow.left.arrow.right"
        case .anthropicCompatible:
            "text.bubble"
        case .aiSDKBridge:
            "shippingbox"
        }
    }
}

private extension ChatExportFormat {
    var systemImage: String {
        switch self {
        case .markdown:
            "doc.plaintext"
        case .json:
            "curlybraces"
        case .html:
            "chevron.left.forwardslash.chevron.right"
        case .pdf:
            "doc.richtext"
        }
    }
}

private extension ProviderPrivacyScope {
    var icon: String {
        switch self {
        case .localOnly:
            "lock"
        case .externalAPI:
            "network"
        case .localCLI:
            "terminal"
        case .bridgeService:
            "point.3.connected.trianglepath.dotted"
        }
    }
}

private extension ModelCapability {
    var icon: String {
        switch self {
        case .chat:
            "bubble.left.and.bubble.right"
        case .streaming:
            "waveform"
        case .toolCalling:
            "wrench.and.screwdriver"
        case .embeddings:
            "square.stack.3d.up"
        case .vision:
            "eye"
        case .reasoning:
            "brain"
        case .webSearch:
            "globe"
        case .imageGeneration:
            "photo"
        case .structuredOutput:
            "list.bullet.rectangle"
        case .openAICompatible:
            "arrow.left.arrow.right"
        case .anthropicCompatible:
            "text.bubble"
        }
    }
}

private extension KnowledgeSourceKind {
    var title: String {
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

    var locationPlaceholder: String {
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

    var icon: String {
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
}

private extension KnowledgeIndexStatus {
    var title: String {
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

    var icon: String {
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

    var tint: Color {
        switch self {
        case .ready:
            .green
        case .queued, .indexing:
            .blue
        case .failed:
            .red
        case .notIndexed, .stale:
            .orange
        }
    }
}

private extension KnowledgeEmbeddingState {
    var title: String {
        switch self {
        case .disabled:
            "Keyword only"
        case .configured:
            "Embeddings configured"
        case .generated:
            "Embeddings ready"
        case .failed:
            "Embedding failed"
        }
    }

    var icon: String {
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

private extension AIToolKind {
    var title: String {
        switch self {
        case .webSearch:
            "Web Search"
        case .webPageReader:
            "Web Reader"
        case .localFileRead:
            "File Read"
        case .localFileWrite:
            "File Write"
        case .terminal:
            "Terminal"
        case .codeExecution:
            "Code Exec"
        case .browserAutomation:
            "Browser"
        case .workspaceSearch:
            "Workspace"
        case .ragRetrieval:
            "RAG"
        case .github:
            "GitHub"
        case .notion:
            "Notion"
        case .youtube:
            "YouTube"
        case .x:
            "X"
        }
    }

    var queryPrompt: String {
        switch self {
        case .webSearch:
            "Search query"
        case .webPageReader:
            "Page URL or capture to inspect"
        case .localFileRead:
            "File path or read request"
        case .localFileWrite:
            "First line: file path. Remaining lines: content to write."
        case .terminal:
            "Optional cwd: line, then command"
        case .codeExecution:
            "First line: language, then script"
        case .browserAutomation:
            "Browser task"
        case .workspaceSearch:
            "Workspace query"
        case .ragRetrieval:
            "RAG question"
        case .github:
            "Repo or issue query"
        case .notion:
            "Notion search, page URL, or data_source: ID"
        case .youtube:
            "Video or channel query"
        case .x:
            "Post or account query"
        }
    }

    var chatFunctionName: String {
        switch self {
        case .webSearch:
            "web_search"
        case .webPageReader:
            "web_page_reader"
        case .localFileRead:
            "local_file_read"
        case .localFileWrite:
            "local_file_write"
        case .terminal:
            "terminal"
        case .codeExecution:
            "code_execution"
        case .browserAutomation:
            "browser_automation"
        case .workspaceSearch:
            "workspace_search"
        case .ragRetrieval:
            "rag_retrieval"
        case .github:
            "github"
        case .notion:
            "notion"
        case .youtube:
            "youtube"
        case .x:
            "x_lookup"
        }
    }

    var icon: String {
        switch self {
        case .webSearch:
            "globe"
        case .webPageReader:
            "doc.text.magnifyingglass"
        case .localFileRead:
            "doc"
        case .localFileWrite:
            "square.and.pencil"
        case .terminal:
            "terminal"
        case .codeExecution:
            "play.square"
        case .browserAutomation:
            "safari"
        case .workspaceSearch:
            "magnifyingglass"
        case .ragRetrieval:
            "books.vertical"
        case .github:
            "chevron.left.forwardslash.chevron.right"
        case .notion:
            "doc.richtext"
        case .youtube:
            "play.rectangle"
        case .x:
            "text.bubble"
        }
    }

    var prefersMultilineInput: Bool {
        switch self {
        case .localFileWrite, .terminal, .codeExecution:
            true
        case .webSearch, .webPageReader, .localFileRead, .browserAutomation, .workspaceSearch, .ragRetrieval, .github, .notion, .youtube, .x:
            false
        }
    }
}

private extension ToolPermissionPolicy {
    var title: String {
        switch self {
        case .alwaysAllow:
            "Always"
        case .askEveryTime:
            "Ask"
        case .deny:
            "Deny"
        case .localOnly:
            "Local"
        }
    }
}

private extension ToolConfiguration {
    var queryPrompt: String {
        kind.queryPrompt
    }

    var chatToolDescription: String {
        let policyText: String
        switch permissionPolicy {
        case .alwaysAllow:
            policyText = "This tool is enabled for local execution."
        case .askEveryTime:
            policyText = "This tool requires explicit approval before Flannel runs it."
        case .deny:
            policyText = "This tool is denied and should not be selected."
        case .localOnly:
            policyText = "This tool is available only when it does not require external network access."
        }

        let effects = [
            requiresNetwork ? "may use network access" : nil,
            canModifyFiles ? "may modify local files" : nil
        ]
        .compactMap(\.self)
        .joined(separator: " and ")

        let effectText = effects.isEmpty ? "It is read/query oriented." : "It \(effects)."
        return "\(title): \(detail) \(effectText) \(policyText)"
    }

    var chatToolArgumentDescription: String {
        switch kind {
        case .localFileWrite:
            "UTF-8 write request. Put the target path on the first line, optionally add '---', then the content to write."
        case .terminal:
            "Shell command request. Optionally start with 'cwd: /path', then include the command to run after user approval."
        case .codeExecution:
            "Code execution request. Put the language on the first line, then the code to run after user approval."
        case .webPageReader:
            "HTTP or HTTPS URL to read, plus any extraction focus."
        case .browserAutomation:
            "HTTP/HTTPS URL to open or a search: query for the default browser."
        case .github:
            "GitHub repository, issue, pull request, or search query."
        case .notion:
            "Notion search query, page URL, or data_source: identifier."
        case .youtube:
            "YouTube video URL, video id, channel, or search query."
        case .x:
            "X/Twitter post URL/id, username, or recent-search query."
        case .webSearch, .localFileRead, .workspaceSearch, .ragRetrieval:
            queryPrompt
        }
    }

    var chatToolInputSchema: ChatToolInputSchema {
        switch kind {
        case .webSearch:
            ChatToolInputSchema(
                properties: [
                    "query": .string("Search query to run through the configured web search provider."),
                    "limit": .integer("Optional maximum number of results to return.")
                ],
                required: ["query"]
            )
        case .webPageReader:
            ChatToolInputSchema(
                properties: [
                    "url": .string("HTTP or HTTPS URL to fetch or a previously captured page URL to inspect."),
                    "focus": .string("Optional extraction focus, question, or section to prioritize.")
                ],
                required: ["url"]
            )
        case .localFileRead:
            ChatToolInputSchema(
                properties: [
                    "path": .string("Local file path or file URL to read after permission checks."),
                    "purpose": .string("Optional reason this file is needed for the answer.")
                ],
                required: ["path"]
            )
        case .localFileWrite:
            ChatToolInputSchema(
                properties: [
                    "path": .string("Local destination file path. The parent folder must already exist."),
                    "content": .string("Complete UTF-8 file content to write."),
                    "mode": .stringEnum(["overwrite"], description: "Write behavior. Flannel currently supports overwrite only.")
                ],
                required: ["path", "content"]
            )
        case .terminal:
            ChatToolInputSchema(
                properties: [
                    "command": .string("Shell command to run after explicit user approval."),
                    "cwd": .string("Optional working directory for the command.")
                ],
                required: ["command"]
            )
        case .codeExecution:
            ChatToolInputSchema(
                properties: [
                    "language": .string("Runtime language, for example swift, python, javascript, bash, or zsh."),
                    "code": .string("Complete source code to run after explicit user approval."),
                    "cwd": .string("Optional working directory for the execution.")
                ],
                required: ["language", "code"]
            )
        case .browserAutomation:
            ChatToolInputSchema(
                properties: [
                    "url": .string("Optional HTTP or HTTPS URL to open in the default browser."),
                    "query": .string("Optional browser search query when no URL is supplied."),
                    "task": .string("Short description of the requested browser action.")
                ],
                required: ["task"]
            )
        case .workspaceSearch:
            ChatToolInputSchema(
                properties: [
                    "query": .string("Query over current workspace context, chat history, and local entities."),
                    "limit": .integer("Optional maximum number of workspace matches.")
                ],
                required: ["query"]
            )
        case .ragRetrieval:
            ChatToolInputSchema(
                properties: [
                    "query": .string("Question to answer from indexed local knowledge sources."),
                    "limit": .integer("Optional maximum number of retrieval chunks.")
                ],
                required: ["query"]
            )
        case .github:
            ChatToolInputSchema(
                properties: [
                    "query": .string("GitHub repository, issue, pull request, or search query."),
                    "repository": .string("Optional owner/name repository scope.")
                ],
                required: ["query"]
            )
        case .notion:
            ChatToolInputSchema(
                properties: [
                    "query": .string("Notion search query, page URL, or data source request."),
                    "page_url": .string("Optional Notion page URL to fetch."),
                    "data_source_id": .string("Optional Notion data source identifier.")
                ],
                required: ["query"]
            )
        case .youtube:
            ChatToolInputSchema(
                properties: [
                    "query": .string("YouTube video URL/id, channel, or search query."),
                    "video_id": .string("Optional YouTube video identifier."),
                    "channel_id": .string("Optional YouTube channel identifier.")
                ],
                required: ["query"]
            )
        case .x:
            ChatToolInputSchema(
                properties: [
                    "query": .string("X/Twitter post URL/id, username, or recent-search query."),
                    "username": .string("Optional X username without the @ prefix."),
                    "post_url": .string("Optional X post URL.")
                ],
                required: ["query"]
            )
        }
    }
}

private extension LocalToolExecutionStatus {
    var title: String {
        switch self {
        case .completed:
            "Completed"
        case .requiresApproval:
            "Needs Approval"
        case .denied:
            "Denied"
        case .blocked:
            "Blocked"
        case .unavailable:
            "Unavailable"
        }
    }

    var icon: String {
        switch self {
        case .completed:
            "checkmark.circle.fill"
        case .requiresApproval:
            "hand.raised.fill"
        case .denied:
            "xmark.circle.fill"
        case .blocked:
            "lock.fill"
        case .unavailable:
            "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .completed:
            .green
        case .requiresApproval:
            .orange
        case .denied:
            .red
        case .blocked:
            .yellow
        case .unavailable:
            .secondary
        }
    }
}

private extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private func formatTokens(_ count: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
}

private func formatCompactTokens(_ count: Int) -> String {
    let absoluteCount = abs(count)
    let sign = count < 0 ? "-" : ""

    if absoluteCount >= 1_000_000 {
        let value = Double(absoluteCount) / 1_000_000.0
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(value >= 10 ? 0 : 1))))M"
    }

    if absoluteCount >= 1_000 {
        let value = Double(absoluteCount) / 1_000.0
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(value >= 10 ? 0 : 1))))K"
    }

    return "\(count)"
}

#Preview {
    ContentView(store: WorkspaceStore())
        .modelContainer(for: Item.self, inMemory: true)
}
