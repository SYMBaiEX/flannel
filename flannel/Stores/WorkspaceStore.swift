//
//  WorkspaceStore.swift
//  flannel
//
//  Created by Codex on 6/28/26.
//

import Foundation
import Observation
import SwiftData

typealias ToolSecretReader = @Sendable (KeychainSecretReference) throws -> String

enum WorkspaceKnowledgeEmbeddingError: LocalizedError, Equatable {
    case missingProvider(String)

    var errorDescription: String? {
        switch self {
        case .missingProvider(let model):
            "No enabled embedding provider is configured for \(model)."
        }
    }
}

struct WorkspaceDashboardSnapshot: Sendable {
    let sourceCount: Int
    let draftCount: Int
    let projectCount: Int
    let automationCount: Int
    let pendingTranscriptCount: Int
    let pendingSummaryCount: Int
    let scheduledDraftCount: Int
    let confirmationCount: Int
}

struct WatchedWebPageRefreshRunSummary: Hashable, Sendable {
    var queuedSourceIDs: [UUID]
    var refreshedSourceIDs: [UUID]
    var failedSourceIDs: [UUID]
    var skippedReason: String?

    static func skipped(_ reason: String) -> WatchedWebPageRefreshRunSummary {
        WatchedWebPageRefreshRunSummary(
            queuedSourceIDs: [],
            refreshedSourceIDs: [],
            failedSourceIDs: [],
            skippedReason: reason
        )
    }
}

struct IntegrationStatusRow: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let status: IntegrationConnectionStatus
}

struct ChatToolCommand: Hashable, Sendable {
    var kind: AIToolKind
    var query: String
}

struct AutoApprovedToolExecution: Hashable, Sendable {
    var result: LocalToolExecutionResult
    var toolCall: AIToolCallRecord
}

nonisolated struct ProviderReadinessBatchSummary: Hashable, Sendable {
    var checkedCount: Int
    var readyCount: Int
    var needsAttentionCount: Int

    var message: String {
        guard checkedCount > 0 else {
            return "No provider routes were checked."
        }

        return "Checked \(checkedCount) route\(checkedCount == 1 ? "" : "s"). \(readyCount) ready; \(needsAttentionCount) need attention."
    }
}

nonisolated enum ProviderAPIKeyRetentionReason: Hashable, Sendable {
    case missingReference
    case noncanonicalReference
    case sharedReference(routeCount: Int)
}

nonisolated struct ProviderAPIKeyDeletionResult: Hashable, Sendable {
    var report: ProviderSetupReport
    var keychainSecretDeleted: Bool
    var clearedReference: KeychainSecretReference?
    var retentionReason: ProviderAPIKeyRetentionReason?

    var message: String {
        if keychainSecretDeleted {
            return "API key removed from Keychain."
        }

        switch retentionReason {
        case .missingReference:
            return "No Keychain key was saved for this route."
        case .noncanonicalReference:
            return "Key reference cleared from this route. The Keychain item was kept because the reference is not canonical for this provider."
        case .sharedReference(let routeCount):
            let routeLabel = routeCount == 1 ? "route" : "routes"
            return "Key reference cleared from this route. The Keychain item was kept because \(routeCount) other \(routeLabel) still use it."
        case nil:
            return report.hasBlockingIssues
                ? report.diagnostics.first(where: \.isBlocking)?.message ?? "API key removed from this route."
                : "API key removed from this route."
        }
    }
}

struct SafeLocalAction: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let kind: LocalActionKind
    let requiresConfirmation: Bool
}

struct PinnedAssistantMessage: Identifiable, Codable, Hashable, Sendable {
    let threadID: UUID
    let messageID: UUID
    let pinnedAt: Date

    var id: String {
        "\(threadID.uuidString)-\(messageID.uuidString)"
    }
}

enum AssistantChatSearchMatchKind: String, Codable, Sendable {
    case threadTitle
    case messageText
    case attachment
    case citation
}

struct AssistantChatSearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let threadID: UUID
    let messageID: UUID?
    let title: String
    let snippet: String
    let matchKind: AssistantChatSearchMatchKind
    let role: AssistantRole?
    let createdAt: Date
    let isArchived: Bool
    let isPinned: Bool
}

enum ChatHistoryDateFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case today
    case previousSevenDays
    case previousThirtyDays
    case previousNinetyDays

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .all:
            "Any Date"
        case .today:
            "Today"
        case .previousSevenDays:
            "Previous 7 Days"
        case .previousThirtyDays:
            "Previous 30 Days"
        case .previousNinetyDays:
            "Previous 90 Days"
        }
    }

    nonisolated var icon: String {
        switch self {
        case .all:
            "calendar"
        case .today:
            "calendar.day.timeline.left"
        case .previousSevenDays:
            "calendar.badge.clock"
        case .previousThirtyDays:
            "calendar"
        case .previousNinetyDays:
            "calendar.circle"
        }
    }
}

struct ChatHistoryFilters: Hashable, Sendable {
    var providerDisplayName: String?
    var modelIdentifier: String?
    var projectID: UUID?
    var dateFilter: ChatHistoryDateFilter

    nonisolated init(
        providerDisplayName: String? = nil,
        modelIdentifier: String? = nil,
        projectID: UUID? = nil,
        dateFilter: ChatHistoryDateFilter = .all
    ) {
        self.providerDisplayName = Self.normalized(providerDisplayName)
        self.modelIdentifier = Self.normalized(modelIdentifier)
        self.projectID = projectID
        self.dateFilter = dateFilter
    }

    nonisolated var isActive: Bool {
        providerDisplayName != nil
            || modelIdentifier != nil
            || projectID != nil
            || dateFilter != .all
    }

    nonisolated private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum WorkspacePersistenceOperation: String, Codable, Hashable, Sendable {
    case containerSetup
    case load
    case save

    var title: String {
        switch self {
        case .containerSetup:
            "Storage setup failed"
        case .load:
            "Workspace load failed"
        case .save:
            "Workspace save failed"
        }
    }
}

struct WorkspacePersistenceIssue: Identifiable, Hashable, Sendable {
    var id: UUID
    var operation: WorkspacePersistenceOperation
    var message: String
    var recoverySuggestion: String
    var occurredAt: Date

    init(
        id: UUID = UUID(),
        operation: WorkspacePersistenceOperation,
        message: String,
        recoverySuggestion: String,
        occurredAt: Date = .now
    ) {
        self.id = id
        self.operation = operation
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.occurredAt = occurredAt
    }

    init(operation: WorkspacePersistenceOperation, error: Error, recoverySuggestion: String? = nil) {
        self.init(
            operation: operation,
            message: error.localizedDescription,
            recoverySuggestion: recoverySuggestion ?? Self.defaultRecoverySuggestion(for: operation)
        )
    }

    var detailText: String {
        [message, recoverySuggestion]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func defaultRecoverySuggestion(for operation: WorkspacePersistenceOperation) -> String {
        switch operation {
        case .containerSetup:
            "Flannel is running with temporary in-memory storage. Export anything important before quitting, then check disk space and app data permissions."
        case .load:
            "Flannel could not open the local workspace database. Check disk space and app data permissions, then restart the app."
        case .save:
            "Recent changes may not be durable yet. Check disk space and app data permissions, then retry saving."
        }
    }
}

struct AssistantContextSnapshot: Sendable {
    let destination: WorkspaceDestination
    let provider: ProviderConfiguration?
    let project: WorkspaceProject?
    let draft: DraftDocument?
    let libraryAsset: LibraryAsset?
    let calendarEntry: PublishingCalendarEntry?
    let thread: AssistantThread?
    let dashboard: WorkspaceDashboardSnapshot
    let integrationRows: [IntegrationStatusRow]
    let pendingConfirmationCount: Int

    var promptPreamble: String {
        var lines = ["Destination: \(destination.title)"]

        if let provider {
            lines.append("Provider: \(provider.displayName) (\(provider.modelIdentifier)) [\(provider.connectionStatus.rawValue)]")
        }

        if let project {
            lines.append("Project: \(project.title)")
            if !project.summary.isEmpty {
                lines.append("Project Summary: \(project.summary)")
            }
            if !project.tagNames.isEmpty {
                lines.append("Project Tags: \(project.tagNames.joined(separator: ", "))")
            }
            if project.aiProfile.hasSystemPromptOverride {
                lines.append("Project AI Prompt: configured")
            }
            if project.aiProfile.preferredProviderID != nil || project.aiProfile.defaultModelPresetID != nil {
                lines.append("Project AI Routing: project default configured")
            }
            if project.aiProfile.hasScopedKnowledge {
                lines.append("Project Knowledge Scope: \(project.aiProfile.knowledgeSourceIDs.count) source(s)")
            }
            if project.aiProfile.hasScopedTools {
                lines.append("Project Tool Scope: \(project.aiProfile.toolConfigurationIDs.count) tool(s)")
            }
            if project.aiProfile.cloudAccessPolicy != .inherit {
                lines.append("Project Privacy: \(project.aiProfile.cloudAccessPolicy.title)")
            }
        }

        if let draft {
            lines.append("Draft: \(draft.title) [\(draft.status.rawValue)]")
            if !draft.summary.isEmpty {
                lines.append("Draft Summary: \(draft.summary)")
            }
            if !draft.sourceAssetIDs.isEmpty {
                lines.append("Draft Source Count: \(draft.sourceAssetIDs.count)")
            }
        }

        if let libraryAsset {
            lines.append("Library Asset: \(libraryAsset.title) [\(libraryAsset.kind.rawValue)]")
            lines.append("Asset Summary Status: \(libraryAsset.summaryStatus.rawValue)")
            if let transcript = libraryAsset.transcript {
                lines.append("Transcript Status: \(transcript.status.rawValue)")
            }
            if !libraryAsset.summary.isEmpty {
                lines.append("Asset Summary: \(libraryAsset.summary)")
            }
        }

        if let calendarEntry {
            lines.append("Calendar: \(calendarEntry.title) at \(calendarEntry.startAt.formatted(date: .abbreviated, time: .shortened)) [\(calendarEntry.status.rawValue)]")
        }

        if let thread {
            lines.append("Assistant Thread: \(thread.title)")
        }

        lines.append("Workspace Counts: \(dashboard.sourceCount) sources, \(dashboard.draftCount) drafts, \(dashboard.projectCount) projects")
        lines.append("Pending Work: \(dashboard.pendingTranscriptCount) transcripts, \(dashboard.pendingSummaryCount) summaries, \(pendingConfirmationCount) confirmations")

        if !integrationRows.isEmpty {
            let integrationSummary = integrationRows
                .prefix(3)
                .map { "\($0.title): \($0.status.rawValue)" }
                .joined(separator: " | ")
            lines.append("Integrations: \(integrationSummary)")
        }

        return lines.joined(separator: "\n")
    }
}

@MainActor
@Observable
final class WorkspaceStore {
    private static let maximumKnowledgeDirectoryFiles = 160
    private static let maximumKnowledgeFileBytes = 2_500_000
    nonisolated static let agentReadyLocalContextWindowTokens = 64_000
    nonisolated private static let defaultToolSecretReader: ToolSecretReader = { reference in
        try KeychainSecretStore().read(reference)
    }
    private static let defaultKnowledgeDirectoryExclusions: Set<String> = [
        ".build",
        ".dart_tool",
        ".git",
        ".next",
        ".pnpm-store",
        ".swiftpm",
        ".venv",
        ".yarn",
        "build",
        "coverage",
        "deriveddata",
        "dist",
        "node_modules",
        "target",
        "vendor"
    ]
    private static let defaultKnowledgeFileExclusions: [String] = [
        ".DS_Store",
        ".lock",
        ".min.js",
        ".xcuserstate",
        "Package.resolved",
        "pnpm-lock.yaml",
        "yarn.lock"
    ]
    nonisolated static let defaultWatchedWebPageRefreshInterval: TimeInterval = 86_400

    private(set) var workspace: Item?
    var selectedDestination: WorkspaceDestination = .home
    var selectedProjectID: UUID?
    var selectedDraftID: UUID?
    var selectedAssetID: UUID?
    var selectedCalendarEntryID: UUID?
    var selectedAssistantThreadID: UUID?

    var accounts: [CreatorAccount] = []
    var providerConfigurations: [ProviderConfiguration] = []
    var libraryAssets: [LibraryAsset] = []
    var projects: [WorkspaceProject] = []
    var drafts: [DraftDocument] = []
    var calendarEntries: [PublishingCalendarEntry] = []
    var assistantThreads: [AssistantThread] = []
    var automations: [WorkspaceAutomation] = []
    var localActionHistory: [LocalActionRecord] = []
    var tags: [WorkspaceTag] = []
    var chatFolders: [ChatFolder] = []
    var promptProfiles: [SystemPromptProfile] = []
    var chatTemplates: [ChatTemplate] = []
    var promptChains: [PromptChain] = []
    var modelPresets: [ModelPreset] = []
    var knowledgeSources: [KnowledgeSource] = []
    var knowledgeIndexManifests: [KnowledgeIndexManifest] = []
    var toolConfigurations: [ToolConfiguration] = []
    var toolExecutionResults: [LocalToolExecutionResult] = []
    var modelComparisonRuns: [ModelComparisonRun] = []
    var localDiscoveryResults: [LocalProviderDiscoveryResult] = []
    var localMemories: [LocalMemoryRecord] = []
    var preferences = WorkspacePreferences()
    var searchText = ""
    var persistenceIssue: WorkspacePersistenceIssue?
    private(set) var pinnedMessages: [PinnedAssistantMessage] = []
    private(set) var archivedAssistantThreadIDs: Set<UUID> = []

    init(initialPersistenceIssue: WorkspacePersistenceIssue? = nil) {
        persistenceIssue = initialPersistenceIssue
    }

    func recordPersistenceFailure(
        _ error: Error,
        operation: WorkspacePersistenceOperation,
        recoverySuggestion: String? = nil
    ) {
        persistenceIssue = WorkspacePersistenceIssue(
            operation: operation,
            error: error,
            recoverySuggestion: recoverySuggestion
        )
    }

    func recordPersistenceIssue(_ issue: WorkspacePersistenceIssue) {
        persistenceIssue = issue
    }

    func clearPersistenceIssue(matching operation: WorkspacePersistenceOperation? = nil) {
        guard operation == nil || persistenceIssue?.operation == operation else { return }
        persistenceIssue = nil
    }

    func loadOrCreate(in modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\Item.updatedAt, order: .reverse)]
        )

        if let existing = try modelContext.fetch(descriptor).first {
            workspace = existing
            hydrate(from: existing)
            normalizeWorkspace()
            return
        }

        let seed = WorkspaceSeed.starterWorkspace()
        modelContext.insert(seed)
        try modelContext.save()

        workspace = seed
        hydrate(from: seed)
        normalizeWorkspace()
    }

    func persist(in modelContext: ModelContext) throws {
        normalizeWorkspace()

        let root = workspace ?? WorkspaceSeed.starterWorkspace()
        root.schemaVersion = 6
        root.selectedDestination = selectedDestination
        root.selectedProjectID = selectedProjectID
        root.selectedDraftID = selectedDraftID
        root.selectedAssetID = selectedAssetID
        root.selectedCalendarEntryID = selectedCalendarEntryID
        root.selectedAssistantThreadID = selectedAssistantThreadID
        root.accounts = accounts
        root.providerConfigurations = providerConfigurations
        root.libraryAssets = libraryAssets
        root.projects = projects
        root.drafts = drafts
        root.calendarEntries = calendarEntries
        root.assistantThreads = assistantThreads
        root.automations = automations
        root.localActionHistory = localActionHistory
        root.tags = tags
        root.chatFolders = chatFolders
        root.promptProfiles = promptProfiles
        root.chatTemplates = chatTemplates
        root.promptChains = promptChains
        root.modelPresets = modelPresets
        root.knowledgeSources = knowledgeSources
        root.knowledgeIndexManifests = knowledgeIndexManifests
        root.toolConfigurations = toolConfigurations
        root.toolExecutionResults = toolExecutionResults
        root.modelComparisonRuns = modelComparisonRuns
        root.localDiscoveryResults = localDiscoveryResults
        root.pinnedMessages = pinnedMessages
        root.archivedAssistantThreadIDs = Array(archivedAssistantThreadIDs)
        root.localMemories = localMemories
        root.preferences = preferences
        root.touch()

        if workspace == nil {
            modelContext.insert(root)
            workspace = root
        }

        try modelContext.save()
    }

    func adoptWorkspace(_ item: Item) {
        workspace = item
        hydrate(from: item)
        normalizeWorkspace()
    }

    @discardableResult
    func resetLocalWorkspace(now: Date = .now) -> UUID {
        let root = workspace ?? Item()
        root.workspaceID = UUID()
        root.schemaVersion = 6
        root.timestamp = now
        root.updatedAt = now
        root.selectedDestination = .home
        root.selectedProjectID = nil
        root.selectedDraftID = nil
        root.selectedAssetID = nil
        root.selectedCalendarEntryID = nil
        root.selectedAssistantThreadID = nil
        root.accounts = []
        root.providerConfigurations = []
        root.libraryAssets = []
        root.projects = []
        root.drafts = []
        root.calendarEntries = []
        root.assistantThreads = []
        root.automations = []
        root.localActionHistory = []
        root.tags = []
        root.chatFolders = []
        root.promptProfiles = []
        root.chatTemplates = []
        root.promptChains = []
        root.modelPresets = []
        root.knowledgeSources = []
        root.knowledgeIndexManifests = []
        root.toolConfigurations = []
        root.toolExecutionResults = []
        root.modelComparisonRuns = []
        root.localDiscoveryResults = []
        root.pinnedMessages = []
        root.archivedAssistantThreadIDs = []
        root.localMemories = []
        root.preferences = WorkspacePreferences(lastOpenedAt: now)

        workspace = root
        hydrate(from: root)
        normalizeWorkspace()
        return root.workspaceID
    }

    func select(_ destination: WorkspaceDestination) {
        let normalizedDestination = normalizedPrimaryDestination(destination)
        selectedDestination = normalizedDestination
        preferences.defaultDestination = normalizedDestination
    }

    func upsert(_ project: WorkspaceProject) {
        projects.upsert(project, matching: \.id)
        selectedProjectID = project.id
        normalizeWorkspace()
    }

    func upsert(_ draft: DraftDocument) {
        drafts.upsert(draft, matching: \.id)
        selectedDraftID = draft.id
        normalizeWorkspace()
    }

    func upsert(_ asset: LibraryAsset) {
        libraryAssets.upsert(asset, matching: \.id)
        selectedAssetID = asset.id
        normalizeWorkspace()
    }

    func upsert(_ automation: WorkspaceAutomation) {
        automations.upsert(automation, matching: \.id)
        normalizeWorkspace()
    }

    func upsert(_ provider: ProviderConfiguration) {
        providerConfigurations.upsert(provider, matching: \.id)
    }

    @discardableResult
    func createProviderRoute(
        kind: LLMProviderKind,
        accessMode: ProviderAccessMode? = nil,
        privacyScope: ProviderPrivacyScope? = nil
    ) -> ProviderConfiguration {
        let resolvedAccessMode = accessMode ?? kind.defaultAccessMode
        let resolvedPrivacyScope = privacyScope ?? kind.defaultPrivacyScope
        let provider = defaultProviderRoute(
            kind: kind,
            accessMode: resolvedAccessMode,
            privacyScope: resolvedPrivacyScope
        )
        providerConfigurations.append(provider)
        return provider
    }

    @discardableResult
    func ensureProviderRouteForChat(
        kind: LLMProviderKind,
        accessMode: ProviderAccessMode? = nil,
        privacyScope: ProviderPrivacyScope? = nil
    ) -> ProviderConfiguration {
        let resolvedAccessMode = accessMode ?? kind.defaultAccessMode
        if let existingIndex = providerConfigurations.firstIndex(where: {
            $0.kind == kind && $0.accessMode == resolvedAccessMode
        }) {
            let providerID = providerConfigurations[existingIndex].id
            _ = selectPreferredProviderForChat(providerID)
            return providerConfigurations[existingIndex]
        }

        let provider = createProviderRoute(
            kind: kind,
            accessMode: resolvedAccessMode,
            privacyScope: privacyScope
        )
        _ = selectPreferredProviderForChat(provider.id)
        return providerConfigurations.first(where: { $0.id == provider.id }) ?? provider
    }

    @discardableResult
    func duplicateProviderRoute(_ providerID: UUID) -> ProviderConfiguration? {
        guard let provider = providerConfigurations.first(where: { $0.id == providerID }) else {
            return nil
        }

        var duplicate = provider
        duplicate.id = UUID()
        duplicate.displayName = uniqueProviderDisplayName(
            baseName: "\(provider.displayName) Copy"
        )
        duplicate.isEnabled = false
        duplicate.connectionStatus = .needsAttention
        duplicate.lastValidatedAt = nil
        duplicate.lastErrorMessage = "Review duplicated route settings before enabling."
        providerConfigurations.append(duplicate)
        return duplicate
    }

    @discardableResult
    func deleteProviderRoute(_ providerID: UUID) -> Bool {
        guard let index = providerConfigurations.firstIndex(where: { $0.id == providerID }) else {
            return false
        }

        providerConfigurations.remove(at: index)

        if preferences.preferredProviderID == providerID {
            preferences.preferredProviderID = runnableChatProviders.first?.id
                ?? providerConfigurations.first(where: \.isEnabled)?.id
        }

        return true
    }

    func apply(_ discoveryResults: [LocalProviderDiscoveryResult]) {
        localDiscoveryResults = discoveryResults

        for result in discoveryResults {
            guard result.status == .ready else {
                applyLocalDiscoveryFailure(result)
                continue
            }

            let modelNames = Self.sortedUniqueModelNames(result.models.map(\.name))
            let discoveredCapabilities = Array(Set(result.models.flatMap(\.capabilities))).sorted { $0.rawValue < $1.rawValue }
            let chatModels = result.models.filter { $0.capabilities.contains(.chat) }
            let preferredModel = chatModels.first?.name ?? modelNames.first
            let hasStreamingModel = discoveredCapabilities.contains(.streaming)
            let hasToolModel = discoveredCapabilities.contains(.toolCalling)
            let hasEmbeddingModel = discoveredCapabilities.contains(.embeddings)
            let hasVisionModel = discoveredCapabilities.contains(.vision)
            let discoveredContextWindow = chatModels.first(where: { $0.contextWindowTokens != nil })?.contextWindowTokens
                ?? result.models.first(where: { $0.contextWindowTokens != nil })?.contextWindowTokens
            if let index = providerConfigurations.firstIndex(where: {
                $0.kind == result.providerKind && $0.endpoint == result.endpoint
            }) {
                let currentModel = providerConfigurations[index].modelIdentifier
                let previousDiscoveredModelNames = Set(providerConfigurations[index].discoveredModelNames)
                let currentDiscoveredModelNames = Set(modelNames)
                let manualModelNames = providerConfigurations[index].availableModels.filter {
                    !previousDiscoveredModelNames.contains($0)
                }
                let currentModelIsManual = !currentModel.isEmpty
                    && !previousDiscoveredModelNames.contains(currentModel)
                let currentModelIsStaleDiscovery = previousDiscoveredModelNames.contains(currentModel)
                    && !currentDiscoveredModelNames.contains(currentModel)
                let preservedCurrentModel = currentModelIsManual ? [currentModel] : []
                let staleDiscoveredModelNames = previousDiscoveredModelNames.subtracting(currentDiscoveredModelNames)

                providerConfigurations[index].availableModels = Self.sortedUniqueModelNames(
                    manualModelNames + modelNames + preservedCurrentModel
                )
                providerConfigurations[index].discoveredModelNames = modelNames
                providerConfigurations[index].staleDiscoveredModelNames = Self.sortedUniqueModelNames(
                    Array(staleDiscoveredModelNames)
                )
                if providerConfigurations[index].modelIdentifier.isEmpty || currentModelIsStaleDiscovery {
                    providerConfigurations[index].modelIdentifier = preferredModel ?? (currentModelIsManual ? currentModel : "")
                }
                providerConfigurations[index].connectionStatus = .ready
                providerConfigurations[index].lastValidatedAt = result.discoveredAt
                providerConfigurations[index].lastErrorMessage = nil
                if let selectedModel = Self.localModelDescriptor(
                    named: providerConfigurations[index].modelIdentifier,
                    in: result.models
                ) {
                    let currentModelWasPreviouslyDiscovered = previousDiscoveredModelNames
                        .contains(providerConfigurations[index].modelIdentifier)
                    applySelectedLocalModelRuntime(
                        selectedModel,
                        allDiscoveredModels: result.models,
                        toProviderAt: index,
                        preserveExistingContextWhenMissing: true,
                        preserveExistingContextValue: currentModelWasPreviouslyDiscovered
                    )
                } else {
                    providerConfigurations[index].capabilities = Array(Set(providerConfigurations[index].capabilities + discoveredCapabilities))
                    providerConfigurations[index].supportsStreaming = providerConfigurations[index].supportsStreaming || hasStreamingModel
                    providerConfigurations[index].supportsToolCalling = providerConfigurations[index].supportsToolCalling || hasToolModel
                    providerConfigurations[index].supportsEmbeddings = providerConfigurations[index].supportsEmbeddings || hasEmbeddingModel
                    providerConfigurations[index].supportsVision = providerConfigurations[index].supportsVision || hasVisionModel
                }
                if providerConfigurations[index].contextWindowTokens == nil {
                    let selectedModel = providerConfigurations[index].modelIdentifier
                    let selectedModelDescriptor = result.models.first(where: { $0.name == selectedModel })
                    providerConfigurations[index].contextWindowTokens = selectedModelDescriptor?.contextWindowTokens
                        ?? discoveredContextWindow
                }
            } else {
                let provider = ProviderConfiguration(
                    kind: result.providerKind,
                    accessMode: .localServer,
                    privacyScope: .localOnly,
                    displayName: result.providerKind.title,
                    endpoint: result.endpoint,
                    modelIdentifier: preferredModel ?? "",
                    isEnabled: true,
                    lastValidatedAt: result.discoveredAt,
                    connectionStatus: .ready,
                    isLocalPreferred: true,
                    availableModels: modelNames,
                    discoveredModelNames: modelNames,
                    staleDiscoveredModelNames: [],
                    capabilities: discoveredCapabilities,
                    supportsStreaming: hasStreamingModel,
                    supportsToolCalling: hasToolModel,
                    supportsEmbeddings: hasEmbeddingModel,
                    supportsVision: hasVisionModel,
                    contextWindowTokens: discoveredContextWindow
                )
                providerConfigurations.append(provider)
            }
        }
    }

    var localModelCatalog: [LocalModelDescriptor] {
        localDiscoveryResults
            .flatMap(\.models)
            .sorted { lhs, rhs in
                let lhsProvider = lhs.providerKind.title
                let rhsProvider = rhs.providerKind.title
                if lhsProvider != rhsProvider {
                    return lhsProvider.localizedCaseInsensitiveCompare(rhsProvider) == .orderedAscending
                }

                let lhsTitle = lhs.displayName ?? lhs.name
                let rhsTitle = rhs.displayName ?? rhs.name
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
    }

    var localAIModelRegistry: [AIModelDescriptor] {
        localDiscoveryResults
            .flatMap { result in
                result.models.map { model in
                    Self.aiModelDescriptor(for: model, discoveredAt: result.discoveredAt)
                }
            }
            .sorted { lhs, rhs in
                let lhsProvider = lhs.providerKind.displayName
                let rhsProvider = rhs.providerKind.displayName
                if lhsProvider != rhsProvider {
                    return lhsProvider.localizedCaseInsensitiveCompare(rhsProvider) == .orderedAscending
                }

                let lhsEndpoint = lhs.sourceEndpoint ?? ""
                let rhsEndpoint = rhs.sourceEndpoint ?? ""
                if lhsEndpoint != rhsEndpoint {
                    return lhsEndpoint.localizedCaseInsensitiveCompare(rhsEndpoint) == .orderedAscending
                }

                if lhs.displayName != rhs.displayName {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }

                return lhs.identifier.localizedCaseInsensitiveCompare(rhs.identifier) == .orderedAscending
            }
    }

    var localChatModelRegistry: [AIModelDescriptor] {
        localAIModelRegistry.filter { $0.capabilities.contains(.chat) }
    }

    var localEmbeddingModelRegistry: [AIModelDescriptor] {
        localAIModelRegistry.filter { $0.capabilities.contains(.embeddings) }
    }

    var loadedLocalModelRegistry: [AIModelDescriptor] {
        localAIModelRegistry.filter { $0.loadedInstanceCount > 0 }
    }

    var agentReadyLocalModelRegistry: [AIModelDescriptor] {
        localChatModelRegistry.filter {
            ($0.contextWindow ?? 0) >= Self.agentReadyLocalContextWindowTokens
        }
    }

    var embeddingModelOptions: [String] {
        var candidates = [LocalEmbeddingService.deterministicModelIdentifier]
        candidates += localModelCatalog
            .filter { $0.capabilities.contains(.embeddings) }
            .map(\.name)

        for provider in providerConfigurations where provider.supportsEmbeddings {
            let discoveredEmbeddingNames = discoveredEmbeddingModels(for: provider).map(\.name)
            let catalogEmbeddingNames = catalogEmbeddingModelIdentifiers(for: provider)
            if provider.accessMode == .localServer, !discoveredEmbeddingNames.isEmpty {
                candidates += discoveredEmbeddingNames
            } else if !catalogEmbeddingNames.isEmpty {
                candidates += catalogEmbeddingNames
            } else {
                candidates.append(provider.modelIdentifier)
                candidates += provider.availableModels
                candidates += provider.discoveredModelNames
            }
        }

        return Self.sortedUniqueModelNames(candidates)
    }

    private func catalogEmbeddingModelIdentifiers(for provider: ProviderConfiguration) -> [String] {
        AIKnownProviderCatalog.entry(for: provider.kind)?.normalizedEmbeddingModelIdentifiers ?? []
    }

    var localProviderHealthSnapshots: [AIProviderHealth] {
        localDiscoveryResults.map(Self.localProviderHealthSnapshot)
            .sorted {
                $0.providerKind.displayName.localizedCaseInsensitiveCompare($1.providerKind.displayName) == .orderedAscending
            }
    }

    private static func localProviderHealthSnapshot(
        for result: LocalProviderDiscoveryResult
    ) -> AIProviderHealth {
        let warning = result.status == .ready ? result.errorMessage : nil
        let failure = result.status == .ready ? nil : result.errorMessage
        return AIProviderHealth(
            providerKind: AIProviderKind(result.providerKind),
            providerMode: AIKnownProviderCatalog.entry(for: result.providerKind)?.providerMode ?? .nativeAPI,
            endpoint: URL(string: result.endpoint),
            status: localProviderHealthStatus(for: result),
            checkedAt: result.discoveredAt,
            lastSuccessfulCheckAt: result.status == .ready ? result.discoveredAt : nil,
            discoveredModelCount: result.models.count,
            loadedModelCount: result.models.reduce(0) { partial, model in
                partial + max(0, model.loadedInstanceCount ?? 0)
            },
            warningMessage: warning,
            failureMessage: failure
        )
    }

    private static func aiModelDescriptor(
        for model: LocalModelDescriptor,
        discoveredAt: Date
    ) -> AIModelDescriptor {
        let providerKind = AIProviderKind(model.providerKind)
        let providerMode = AIKnownProviderCatalog.entry(for: model.providerKind)?.providerMode ?? .nativeAPI

        return AIModelDescriptor(
            providerKind: providerKind,
            providerMode: providerMode,
            identifier: model.name,
            displayName: model.displayName ?? model.name,
            publisher: model.publisher ?? providerKind.displayName,
            family: model.family,
            parameterCountLabel: model.parameterSize,
            quantizationLabel: model.quantization,
            contextWindow: model.contextWindowTokens,
            installedSizeBytes: model.sizeBytes,
            sourceEndpoint: model.endpoint,
            isAvailableLocally: true,
            loadedInstanceCount: max(0, model.loadedInstanceCount ?? 0),
            capabilities: Set(model.capabilities.compactMap(Self.aiModelCapability)),
            lastDiscoveredAt: discoveredAt
        )
    }

    private static func aiModelCapability(for capability: ModelCapability) -> AIModelCapability? {
        switch capability {
        case .chat:
            return .chat
        case .streaming:
            return .streaming
        case .toolCalling:
            return .toolUse
        case .embeddings:
            return .embeddings
        case .vision:
            return .vision
        case .reasoning:
            return .reasoning
        case .webSearch:
            return .retrieval
        case .structuredOutput:
            return .structuredOutput
        case .imageGeneration, .openAICompatible, .anthropicCompatible:
            return nil
        }
    }

    private static func localProviderHealthStatus(
        for result: LocalProviderDiscoveryResult
    ) -> AIProviderHealthStatus {
        switch result.status {
        case .ready:
            if let warning = result.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
               !warning.isEmpty {
                return .degraded
            }
            return .ready
        case .needsAttention:
            return .unavailable
        case .disconnected:
            return .unknown
        case .syncing:
            return .unknown
        case .rateLimited:
            return .degraded
        }
    }

    private func applyLocalDiscoveryFailure(_ result: LocalProviderDiscoveryResult) {
        guard let index = providerConfigurations.firstIndex(where: {
            $0.kind == result.providerKind && $0.endpoint == result.endpoint
        }) else { return }

        providerConfigurations[index].connectionStatus = result.status
        providerConfigurations[index].lastValidatedAt = result.discoveredAt
        providerConfigurations[index].lastErrorMessage = Self.localDiscoveryFailureMessage(for: result)
    }

    func localProviderDiscoveryTargets(extraOllamaEndpoint: String? = nil) -> [(LLMProviderKind, String)] {
        var targets = providerConfigurations.compactMap { provider -> (LLMProviderKind, String)? in
            guard provider.kind == .ollama || provider.kind == .lmStudio else { return nil }
            let endpoint = provider.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !endpoint.isEmpty else { return nil }
            return (provider.kind, endpoint)
        }

        if !targets.contains(where: { $0.0 == .ollama }) {
            targets.append((.ollama, "http://localhost:11434"))
        }

        if !targets.contains(where: { $0.0 == .lmStudio }) {
            targets.append((.lmStudio, "http://localhost:1234"))
        }

        if let extraOllamaEndpoint {
            let endpoint = extraOllamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !endpoint.isEmpty {
                targets.append((.ollama, endpoint))
            }
        }

        return targets
    }

    @discardableResult
    func selectDiscoveredLocalModelForChat(_ model: LocalModelDescriptor) -> UUID? {
        guard model.capabilities.contains(.chat) else {
            return nil
        }

        if let index = providerConfigurations.firstIndex(where: {
            $0.kind == model.providerKind && $0.endpoint == model.endpoint
        }) {
            providerConfigurations[index].modelIdentifier = model.name
            providerConfigurations[index].isEnabled = true
            providerConfigurations[index].connectionStatus = .ready
            providerConfigurations[index].lastErrorMessage = nil
            providerConfigurations[index].lastValidatedAt = .now
            providerConfigurations[index].isLocalPreferred = true
            providerConfigurations[index].availableModels = Array(
                Set(providerConfigurations[index].availableModels + [model.name])
            ).sorted()
            providerConfigurations[index].discoveredModelNames = Self.sortedUniqueModelNames(
                providerConfigurations[index].discoveredModelNames + [model.name]
            )
            providerConfigurations[index].staleDiscoveredModelNames.removeAll { $0 == model.name }
            applySelectedLocalModelRuntime(
                model,
                allDiscoveredModels: discoveredModelsForLocalProvider(
                    kind: model.providerKind,
                    endpoint: model.endpoint
                ),
                toProviderAt: index,
                preserveExistingContextWhenMissing: false
            )

            let providerID = providerConfigurations[index].id
            _ = selectPreferredProviderForChat(providerID)
            return providerID
        }

        let provider = ProviderConfiguration(
            kind: model.providerKind,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: model.providerKind.title,
            endpoint: model.endpoint,
            modelIdentifier: model.name,
            isEnabled: true,
            lastValidatedAt: .now,
            connectionStatus: .ready,
            isLocalPreferred: true,
            availableModels: [model.name],
            discoveredModelNames: [model.name],
            staleDiscoveredModelNames: [],
            capabilities: model.capabilities,
            supportsStreaming: model.capabilities.contains(.streaming),
            supportsToolCalling: model.capabilities.contains(.toolCalling),
            supportsEmbeddings: model.capabilities.contains(.embeddings),
            supportsVision: model.capabilities.contains(.vision),
            contextWindowTokens: model.contextWindowTokens
        )
        providerConfigurations.append(provider)
        _ = selectPreferredProviderForChat(provider.id)
        return provider.id
    }

    private func discoveredModelsForLocalProvider(
        kind: LLMProviderKind,
        endpoint: String
    ) -> [LocalModelDescriptor] {
        localDiscoveryResults.first {
            $0.providerKind == kind && $0.endpoint == endpoint
        }?.models ?? []
    }

    private func discoveredEmbeddingModels(for provider: ProviderConfiguration) -> [LocalModelDescriptor] {
        discoveredModelsForLocalProvider(kind: provider.kind, endpoint: provider.endpoint)
            .filter { $0.capabilities.contains(.embeddings) }
    }

    private func applySelectedLocalModelRuntime(
        _ model: LocalModelDescriptor,
        allDiscoveredModels: [LocalModelDescriptor],
        toProviderAt index: Int,
        preserveExistingContextWhenMissing: Bool,
        preserveExistingContextValue: Bool = false
    ) {
        let providerSupportsEmbeddings = if allDiscoveredModels.isEmpty {
            providerConfigurations[index].supportsEmbeddings
        } else {
            allDiscoveredModels.contains { $0.capabilities.contains(.embeddings) }
        }
        var routeCapabilities = Set(model.capabilities)
        if providerSupportsEmbeddings {
            routeCapabilities.insert(.embeddings)
        }

        providerConfigurations[index].capabilities = Self.sortedUniqueCapabilities(Array(routeCapabilities))
        providerConfigurations[index].supportsStreaming = model.capabilities.contains(.streaming)
        providerConfigurations[index].supportsToolCalling = model.capabilities.contains(.toolCalling)
        providerConfigurations[index].supportsEmbeddings = providerSupportsEmbeddings
            || model.capabilities.contains(.embeddings)
        providerConfigurations[index].supportsVision = model.capabilities.contains(.vision)
        providerConfigurations[index].supportsStructuredOutput = model.capabilities.contains(.structuredOutput)

        if let contextWindowTokens = model.contextWindowTokens,
           !preserveExistingContextValue || providerConfigurations[index].contextWindowTokens == nil {
            providerConfigurations[index].contextWindowTokens = contextWindowTokens
        } else if !preserveExistingContextWhenMissing {
            providerConfigurations[index].contextWindowTokens = nil
        }
    }

    private static func localModelDescriptor(
        named rawModelName: String,
        in models: [LocalModelDescriptor]
    ) -> LocalModelDescriptor? {
        let modelName = rawModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else { return nil }
        return models.first {
            $0.name == modelName || $0.displayName == modelName
        }
    }

    private static func sortedUniqueModelNames(_ modelNames: [String]) -> [String] {
        Array(
            Set(
                modelNames
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func sortedUniqueCapabilities(_ capabilities: [ModelCapability]) -> [ModelCapability] {
        Array(Set(capabilities)).sorted { $0.rawValue < $1.rawValue }
    }

    private func canApplyPrivacyScope(
        _ privacyScope: ProviderPrivacyScope,
        to provider: ProviderConfiguration
    ) -> Bool {
        guard privacyScope == .localOnly else { return true }

        switch provider.accessMode {
        case .localServer:
            return true
        case .openAICompatible, .anthropicCompatible:
            return Self.isLoopbackEndpoint(provider.endpoint)
        case .apiKey, .aiSDKBridge, .subscriptionCLI:
            return false
        }
    }

    private static func isLoopbackEndpoint(_ rawEndpoint: String) -> Bool {
        let endpoint = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: endpoint),
              let host = components.host?.lowercased() else {
            return false
        }

        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func modelPresetApplicationNeedsReadinessCheck(
        original: ProviderConfiguration,
        updated: ProviderConfiguration
    ) -> Bool {
        guard updated.runtimePolicy.readinessStrategy != .staticConfiguration else {
            return false
        }

        return original.modelIdentifier != updated.modelIdentifier
            || original.privacyScope != updated.privacyScope
            || original.endpoint != updated.endpoint
            || original.capabilities != updated.capabilities
            || original.supportsStreaming != updated.supportsStreaming
            || original.supportsToolCalling != updated.supportsToolCalling
            || original.supportsEmbeddings != updated.supportsEmbeddings
            || original.supportsVision != updated.supportsVision
            || original.supportsStructuredOutput != updated.supportsStructuredOutput
    }

    private static func localDiscoveryFailureMessage(for result: LocalProviderDiscoveryResult) -> String {
        let detail = result.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            return detail
        }

        return "Could not discover \(result.providerKind.title) models at \(result.endpoint)."
    }

    func upsert(_ account: CreatorAccount) {
        accounts.upsert(account, matching: \.id)
    }

    @discardableResult
    func appendAssistantMessage(
        _ text: String,
        role: AssistantRole,
        attachments: [AIChatAttachment] = [],
        citations: [AIChatCitation] = [],
        extraReferencedEntityIDs: [UUID] = [],
        promptChainStepID: UUID? = nil
    ) -> UUID {
        var thread = currentAssistantThread ?? AssistantThread(title: "Workspace Copilot")
        thread.pinnedProjectID = selectedProjectID
        thread.pinnedDraftID = selectedDraftID
        thread.pinnedAssetID = selectedAssetID
        thread.pinnedCalendarEntryID = selectedCalendarEntryID
        let message = AssistantMessage(
            role: role,
            text: text,
            attachments: attachments,
            referencedEntityIDs: [
                selectedProjectID,
                selectedDraftID,
                selectedAssetID,
                selectedCalendarEntryID
            ].compactMap { $0 } + extraReferencedEntityIDs,
            promptChainStepID: promptChainStepID,
            citations: citations
        )
        thread.messages.append(message)

        if role == .user,
           thread.messages.filter({ $0.role == .user }).count == 1 {
            thread.title = Self.threadTitle(from: text)
        }

        thread.updatedAt = .now
        assistantThreads.upsert(thread, matching: \.id)
        selectedAssistantThreadID = thread.id
        return message.id
    }

    @discardableResult
    func appendAssistantMessage(
        _ text: String,
        role: AssistantRole,
        in threadID: UUID,
        attachments: [AIChatAttachment] = [],
        citations: [AIChatCitation] = [],
        extraReferencedEntityIDs: [UUID] = [],
        promptChainStepID: UUID? = nil
    ) -> UUID? {
        guard let threadIndex = assistantThreads.firstIndex(where: { $0.id == threadID }) else {
            return nil
        }

        let thread = assistantThreads[threadIndex]
        let message = AssistantMessage(
            role: role,
            text: text,
            attachments: attachments,
            referencedEntityIDs: [
                thread.pinnedProjectID,
                thread.pinnedDraftID,
                thread.pinnedAssetID,
                thread.pinnedCalendarEntryID
            ].compactMap { $0 } + extraReferencedEntityIDs,
            promptChainStepID: promptChainStepID,
            citations: citations
        )
        assistantThreads[threadIndex].messages.append(message)

        if role == .user,
           assistantThreads[threadIndex].messages.filter({ $0.role == .user }).count == 1 {
            assistantThreads[threadIndex].title = Self.threadTitle(from: text)
        }

        assistantThreads[threadIndex].updatedAt = .now
        return message.id
    }

    func parseChatToolCommand(_ rawText: String) -> ChatToolCommand? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("/tool") else { return nil }

        let remainder = trimmed
            .dropFirst("/tool".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return nil }

        let pieces = remainder.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let name = pieces.first,
              let kind = AIToolKind(chatToolName: String(name)) else { return nil }

        let query = pieces.count > 1
            ? String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return ChatToolCommand(kind: kind, query: query)
    }

    @discardableResult
    func runChatToolCommand(_ command: ChatToolCommand) -> LocalToolExecutionResult {
        runTool(command.kind, query: command.query)
    }

    func parseRememberCommand(_ rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        if lowered.hasPrefix("/remember") {
            let remainder = trimmed
                .dropFirst("/remember".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return remainder.isEmpty ? nil : remainder
        }

        if lowered.hasPrefix("remember:") {
            let remainder = trimmed
                .dropFirst("remember:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return remainder.isEmpty ? nil : remainder
        }

        return nil
    }

    @discardableResult
    func addLocalMemory(
        title rawTitle: String,
        detail rawDetail: String,
        category: LocalMemoryCategory = .fact,
        tagNames: [String] = [],
        sourceThreadID: UUID? = nil,
        sourceMessageID: UUID? = nil,
        isEnabled: Bool = true
    ) -> LocalMemoryRecord? {
        let detail = rawDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return nil }

        let title = Self.memoryTitle(from: rawTitle, fallbackText: detail)
        let memory = LocalMemoryRecord(
            title: title,
            detail: detail,
            category: category,
            tagNames: canonicalTags(tagNames),
            sourceThreadID: sourceThreadID,
            sourceMessageID: sourceMessageID,
            isEnabled: isEnabled
        )
        localMemories.insert(memory, at: 0)
        return memory
    }

    @discardableResult
    func rememberFromCurrentThread(_ detail: String, category: LocalMemoryCategory = .fact) -> LocalMemoryRecord? {
        addLocalMemory(
            title: "",
            detail: detail,
            category: category,
            tagNames: currentAssistantThread?.tagNames ?? [],
            sourceThreadID: selectedAssistantThreadID,
            sourceMessageID: currentAssistantThread?.messages.last?.id
        )
    }

    func updateLocalMemory(_ memory: LocalMemoryRecord) {
        var updated = memory
        updated.title = Self.memoryTitle(from: updated.title, fallbackText: updated.detail)
        updated.detail = updated.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.tagNames = canonicalTags(updated.tagNames)
        updated.updatedAt = .now

        guard !updated.detail.isEmpty else {
            deleteLocalMemory(memory.id)
            return
        }

        localMemories.upsert(updated, matching: \.id)
    }

    func deleteLocalMemory(_ memoryID: UUID) {
        localMemories.removeAll { $0.id == memoryID }
    }

    func setLocalMemoryEnabled(_ memoryID: UUID, isEnabled: Bool) {
        guard let index = localMemories.firstIndex(where: { $0.id == memoryID }) else { return }
        localMemories[index].isEnabled = isEnabled
        localMemories[index].updatedAt = .now
    }

    func enabledToolConfigurations(for thread: AssistantThread? = nil) -> [ToolConfiguration] {
        let scopedToolIDs = projectAIProfile(for: thread).map { Set($0.toolConfigurationIDs) } ?? []
        return toolConfigurations.filter { tool in
            tool.isEnabled
                && (scopedToolIDs.isEmpty || scopedToolIDs.contains(tool.id))
        }
    }

    func localMemoryPromptContext(
        for query: String,
        thread: AssistantThread? = nil,
        now: Date = .now
    ) -> String? {
        if projectAIProfile(for: thread)?.localMemoryPolicy == .exclude {
            return nil
        }

        let settings = preferences.localMemory ?? LocalMemorySettings()
        guard settings.isEnabled,
              settings.includeInChatContext else { return nil }

        let memories = relevantLocalMemories(
            for: query,
            limit: max(1, min(settings.maximumContextMemories, 24))
        )
        guard !memories.isEmpty else { return nil }

        let memoryIDs = Set(memories.map(\.id))
        for index in localMemories.indices where memoryIDs.contains(localMemories[index].id) {
            localMemories[index].lastUsedAt = now
            localMemories[index].useCount += 1
        }

        let lines = memories.map { memory in
            "- [\(memory.category.title)] \(memory.title): \(memory.detail)"
        }
        return """
        Local Memories:
        Use these user-saved local memories when relevant. They are stored on this Mac and may be edited or disabled by the user.
        \(lines.joined(separator: "\n"))
        """
    }

    func relevantLocalMemories(for query: String, limit: Int? = nil) -> [LocalMemoryRecord] {
        let settings = preferences.localMemory ?? LocalMemorySettings()
        guard settings.isEnabled else { return [] }

        let queryTerms = Self.memoryTerms(in: query)
        let scored = localMemories
            .filter { $0.isEnabled && !$0.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { memory -> (memory: LocalMemoryRecord, score: Int) in
                let memoryTerms = Self.memoryTerms(
                    in: ([memory.title, memory.detail] + memory.tagNames).joined(separator: " ")
                )
                let overlap = queryTerms.isEmpty ? 0 : queryTerms.intersection(memoryTerms).count
                let recencyBoost = memory.lastUsedAt == nil ? 1 : 0
                return (memory, overlap * 10 + min(memory.useCount, 4) + recencyBoost)
            }
            .filter { queryTerms.isEmpty || $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.memory.updatedAt > rhs.memory.updatedAt
                }
                return lhs.score > rhs.score
            }
            .map(\.memory)

        if let limit {
            return Array(scored.prefix(max(0, limit)))
        }
        return scored
    }

    @discardableResult
    func runChatToolCommand(
        _ command: ChatToolCommand,
        webPageCaptureService: WebPageCaptureService,
        browserAutomationService: BrowserAutomationService = BrowserAutomationService()
    ) async -> LocalToolExecutionResult {
        await runTool(
            command.kind,
            query: command.query,
            webPageCaptureService: webPageCaptureService,
            browserAutomationService: browserAutomationService
        )
    }

    func chatToolCommand(for toolCall: AIToolCallRecord) -> ChatToolCommand? {
        guard let kind = AIToolKind(chatToolName: toolCall.toolName) else { return nil }
        return ChatToolCommand(
            kind: kind,
            query: Self.queryFromToolArguments(toolCall.argumentsJSON, toolKind: kind)
        )
    }

    func autoApprovedRequestedToolCalls(in messageID: UUID) -> [AIToolCallRecord] {
        guard let location = resolveMessageLocation(messageID) else { return [] }

        return assistantThreads[location.threadIndex]
            .messages[location.messageIndex]
            .toolCalls
            .filter(isAutoApprovedRequestedToolCall)
    }

    @discardableResult
    func runAutoApprovedRequestedToolCalls(
        in messageID: UUID,
        webPageCaptureService: WebPageCaptureService,
        browserAutomationService: BrowserAutomationService = BrowserAutomationService()
    ) async -> [AutoApprovedToolExecution] {
        let toolCalls = autoApprovedRequestedToolCalls(in: messageID)
        guard !toolCalls.isEmpty else { return [] }

        var executions: [AutoApprovedToolExecution] = []
        for toolCall in toolCalls {
            guard let result = await runRequestedToolCall(
                toolCall.id,
                in: messageID,
                webPageCaptureService: webPageCaptureService,
                browserAutomationService: browserAutomationService
            ) else {
                continue
            }

            let refreshedToolCall = refreshRequestedToolCall(forToolResult: result)
                ?? requestedToolCall(toolCall.id, in: messageID)
                ?? toolCall
            executions.append(
                AutoApprovedToolExecution(
                    result: result,
                    toolCall: refreshedToolCall
                )
            )
        }

        return executions
    }

    @discardableResult
    func denyRequestedToolCall(_ toolCallID: UUID, in messageID: UUID) -> AIToolCallRecord? {
        markRequestedToolCall(
            toolCallID,
            in: messageID,
            wasApproved: false,
            executionStatus: .denied,
            executionResultID: nil,
            outputPreview: "Denied locally. No tool action was run.",
            completedAt: .now
        )
    }

    @discardableResult
    func runRequestedToolCall(
        _ toolCallID: UUID,
        in messageID: UUID,
        webPageCaptureService: WebPageCaptureService,
        browserAutomationService: BrowserAutomationService = BrowserAutomationService()
    ) async -> LocalToolExecutionResult? {
        guard let messageLocation = resolveMessageLocation(messageID),
              let toolCall = requestedToolCall(toolCallID, in: messageID) else { return nil }
        let threadID = assistantThreads[messageLocation.threadIndex].id

        guard let command = chatToolCommand(for: toolCall) else {
            markRequestedToolCall(
                toolCallID,
                in: messageID,
                wasApproved: false,
                executionStatus: .unavailable,
                executionResultID: nil,
                outputPreview: "\(toolCall.toolName) is not mapped to a configured Flannel tool.",
                completedAt: .now
            )
            return nil
        }

        let result = await runChatToolCommand(
            command,
            webPageCaptureService: webPageCaptureService,
            browserAutomationService: browserAutomationService
        )
        _ = appendToolResultMessage(result, in: threadID)
        markRequestedToolCall(
            toolCallID,
            in: messageID,
            wasApproved: result.status == .completed,
            executionStatus: result.status,
            executionResultID: result.id,
            outputPreview: result.output.truncatedForToolCallPreview,
            completedAt: result.createdAt
        )
        return result
    }

    private func isAutoApprovedRequestedToolCall(_ toolCall: AIToolCallRecord) -> Bool {
        guard toolCall.executionStatus == nil,
              toolCall.executionResultID == nil,
              let command = chatToolCommand(for: toolCall),
              let tool = toolConfigurations.first(where: { $0.kind == command.kind }) else {
            return false
        }

        return tool.isEnabled && tool.permissionPolicy == .alwaysAllow
    }

    @discardableResult
    func appendToolResultMessage(_ result: LocalToolExecutionResult) -> UUID {
        appendAssistantMessage(
            Self.toolResultMessageText(for: result),
            role: .assistant,
            attachments: [Self.toolResultAttachment(for: result)],
            extraReferencedEntityIDs: [result.id]
        )
    }

    @discardableResult
    func appendToolResultMessage(_ result: LocalToolExecutionResult, in threadID: UUID) -> UUID? {
        appendAssistantMessage(
            Self.toolResultMessageText(for: result),
            role: .assistant,
            in: threadID,
            attachments: [Self.toolResultAttachment(for: result)],
            extraReferencedEntityIDs: [result.id]
        )
    }

    func refreshAssistantMessages(forToolResult result: LocalToolExecutionResult) {
        let attachment = Self.toolResultAttachment(for: result)
        let messageText = Self.toolResultMessageText(for: result)

        for threadIndex in assistantThreads.indices {
            var didUpdateThread = false
            for messageIndex in assistantThreads[threadIndex].messages.indices {
                guard assistantThreads[threadIndex].messages[messageIndex].referencedEntityIDs.contains(result.id) else {
                    continue
                }

                assistantThreads[threadIndex].messages[messageIndex].text = messageText
                assistantThreads[threadIndex].messages[messageIndex].attachments.removeAll { $0.kind == .toolResult }
                assistantThreads[threadIndex].messages[messageIndex].attachments.append(attachment)
                assistantThreads[threadIndex].messages[messageIndex].updatedAt = .now
                didUpdateThread = true
            }

            if didUpdateThread {
                assistantThreads[threadIndex].updatedAt = .now
            }
        }
    }

    @discardableResult
    func refreshRequestedToolCall(forToolResult result: LocalToolExecutionResult) -> AIToolCallRecord? {
        for threadIndex in assistantThreads.indices {
            for messageIndex in assistantThreads[threadIndex].messages.indices {
                guard let toolCallIndex = assistantThreads[threadIndex].messages[messageIndex].toolCalls.firstIndex(where: {
                    $0.executionResultID == result.id
                }) else {
                    continue
                }

                assistantThreads[threadIndex].messages[messageIndex].toolCalls[toolCallIndex].wasApproved = result.status == .completed
                assistantThreads[threadIndex].messages[messageIndex].toolCalls[toolCallIndex].executionStatus = result.status
                assistantThreads[threadIndex].messages[messageIndex].toolCalls[toolCallIndex].outputPreview = result.output.truncatedForToolCallPreview
                assistantThreads[threadIndex].messages[messageIndex].toolCalls[toolCallIndex].completedAt = result.createdAt
                assistantThreads[threadIndex].messages[messageIndex].updatedAt = .now
                assistantThreads[threadIndex].updatedAt = .now
                return assistantThreads[threadIndex].messages[messageIndex].toolCalls[toolCallIndex]
            }
        }
        return nil
    }

    func updateAssistantMessage(
        _ id: UUID,
        text: String,
        citations: [AIChatCitation]? = nil
    ) {
        guard var thread = currentAssistantThread,
              let messageIndex = thread.messages.firstIndex(where: { $0.id == id }) else { return }

        thread.messages[messageIndex].text = text
        if let citations {
            thread.messages[messageIndex].citations = citations
        }
        thread.updatedAt = .now
        assistantThreads.upsert(thread, matching: \.id)
        selectedAssistantThreadID = thread.id
    }

    func updateAssistantMessage(
        _ id: UUID,
        in threadID: UUID,
        text: String,
        citations: [AIChatCitation]? = nil
    ) {
        guard let location = resolveMessageLocation(id, in: threadID) else { return }

        assistantThreads[location.threadIndex].messages[location.messageIndex].text = text
        if let citations {
            assistantThreads[location.threadIndex].messages[location.messageIndex].citations = citations
        }
        assistantThreads[location.threadIndex].messages[location.messageIndex].updatedAt = .now
        assistantThreads[location.threadIndex].updatedAt = .now
    }

    func assistantMessageText(_ id: UUID, in threadID: UUID) -> String? {
        guard let location = resolveMessageLocation(id, in: threadID) else { return nil }
        return assistantThreads[location.threadIndex].messages[location.messageIndex].text
    }

    @discardableResult
    func rewindThreadForRetry(
        from messageID: UUID,
        in threadID: UUID? = nil
    ) -> (prompt: String, attachments: [AIChatAttachment], promptChainStepID: UUID?)? {
        guard let location = resolveMessageLocation(messageID, in: threadID) else { return nil }
        let thread = assistantThreads[location.threadIndex]
        let retryMessageIndex: Int

        switch thread.messages[location.messageIndex].role {
        case .user:
            retryMessageIndex = location.messageIndex
        case .assistant:
            let previousUserIndex = thread.messages[..<location.messageIndex]
                .lastIndex { message in
                    message.role == .user
                        && (!message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !message.attachments.isEmpty)
                }
            guard let previousUserIndex else { return nil }
            retryMessageIndex = previousUserIndex
        case .system:
            return nil
        }

        let retryMessage = thread.messages[retryMessageIndex]
        let prompt = retryMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty || !retryMessage.attachments.isEmpty else { return nil }

        assistantThreads[location.threadIndex].messages = Array(thread.messages.prefix(retryMessageIndex))
        reopenPromptChainStepForRetry(retryMessage, inThreadAt: location.threadIndex)
        assistantThreads[location.threadIndex].updatedAt = .now
        selectedAssistantThreadID = thread.id
        selectedDestination = .home
        normalizeWorkspace()

        return (prompt, retryMessage.attachments, retryMessage.promptChainStepID)
    }

    private func reopenPromptChainStepForRetry(_ retryMessage: AssistantMessage, inThreadAt threadIndex: Int) {
        guard let promptChainStepID = retryMessage.promptChainStepID,
              let promptChainID = assistantThreads[threadIndex].promptChainID,
              let chain = promptChains.first(where: { $0.id == promptChainID }) else {
            return
        }

        let enabledStepIDs = chain.enabledSteps.map(\.id)
        guard let stepIndex = enabledStepIDs.firstIndex(of: promptChainStepID) else { return }

        let reopenedStepIDs = Set(enabledStepIDs[stepIndex...])
        assistantThreads[threadIndex].completedPromptChainStepIDs.removeAll {
            reopenedStepIDs.contains($0)
        }
        assistantThreads[threadIndex].activePromptChainStepID = promptChainStepID
    }

    @discardableResult
    func pinMessage(_ messageID: UUID, in threadID: UUID? = nil) -> PinnedAssistantMessage? {
        guard let location = resolveMessageLocation(messageID, in: threadID) else { return nil }
        let resolvedThreadID = assistantThreads[location.threadIndex].id

        if let existingPin = pinnedMessages.first(where: {
            $0.threadID == resolvedThreadID && $0.messageID == messageID
        }) {
            return existingPin
        }

        let pin = PinnedAssistantMessage(
            threadID: resolvedThreadID,
            messageID: messageID,
            pinnedAt: .now
        )
        pinnedMessages.insert(pin, at: 0)
        assistantThreads[location.threadIndex].updatedAt = .now
        return pin
    }

    func unpinMessage(_ messageID: UUID, in threadID: UUID? = nil) {
        let resolvedThreadID = resolveMessageLocation(messageID, in: threadID).map {
            assistantThreads[$0.threadIndex].id
        } ?? threadID

        pinnedMessages.removeAll { pin in
            pin.messageID == messageID && (resolvedThreadID == nil || pin.threadID == resolvedThreadID)
        }

        if let resolvedThreadID,
           let threadIndex = assistantThreads.firstIndex(where: { $0.id == resolvedThreadID }) {
            assistantThreads[threadIndex].updatedAt = .now
        }
    }

    func isMessagePinned(_ messageID: UUID, in threadID: UUID? = nil) -> Bool {
        guard let location = resolveMessageLocation(messageID, in: threadID) else { return false }
        let resolvedThreadID = assistantThreads[location.threadIndex].id
        return pinnedMessages.contains {
            $0.threadID == resolvedThreadID && $0.messageID == messageID
        }
    }

    @discardableResult
    func importAssistantThread(_ thread: AssistantThread) -> AssistantThread {
        assistantThreads.removeAll { $0.id == thread.id }
        archivedAssistantThreadIDs.remove(thread.id)
        pinnedMessages.removeAll { $0.threadID == thread.id }

        assistantThreads.insert(thread, at: 0)
        selectedAssistantThreadID = thread.id
        selectedDestination = .home
        normalizePromptChainThreadState()

        for message in thread.messages where message.isPinned {
            pinnedMessages.insert(
                PinnedAssistantMessage(
                    threadID: thread.id,
                    messageID: message.id,
                    pinnedAt: .now
                ),
                at: 0
            )
        }

        normalizeWorkspace()
        return thread
    }

    @discardableResult
    func pinThread(_ threadID: UUID? = nil) -> Bool {
        setThreadPinned(threadID, isPinned: true)
    }

    @discardableResult
    func unpinThread(_ threadID: UUID? = nil) -> Bool {
        setThreadPinned(threadID, isPinned: false)
    }

    @discardableResult
    func setThreadPinned(_ threadID: UUID? = nil, isPinned: Bool) -> Bool {
        guard let resolvedThreadID = threadID ?? selectedAssistantThreadID,
              let threadIndex = assistantThreads.firstIndex(where: { $0.id == resolvedThreadID }) else {
            return false
        }

        assistantThreads[threadIndex].isPinned = isPinned
        assistantThreads[threadIndex].updatedAt = .now
        return true
    }

    func upsert(_ template: ChatTemplate) {
        var updated = template
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.detail = updated.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.systemPrompt = updated.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.tagNames = canonicalTags(updated.tagNames)
        updated.updatedAt = .now

        guard !updated.title.isEmpty else { return }
        chatTemplates.upsert(updated, matching: \.id)
        normalizeChatTemplateState()
    }

    func deleteChatTemplate(_ templateID: UUID) {
        chatTemplates.removeAll { $0.id == templateID }
    }

    func upsert(_ chain: PromptChain) {
        var updated = chain
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.detail = updated.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.systemPrompt = updated.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.tagNames = canonicalTags(updated.tagNames)
        updated.updatedAt = .now

        guard !updated.title.isEmpty else { return }
        promptChains.upsert(updated, matching: \.id)
        normalizePromptChainState()
    }

    func deletePromptChain(_ chainID: UUID) {
        promptChains.removeAll { $0.id == chainID }
    }

    func upsert(_ profile: SystemPromptProfile) {
        var updated = profile
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.detail = updated.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.prompt = updated.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.tags = canonicalTags(updated.tags)

        guard !updated.title.isEmpty else { return }

        if updated.isDefault {
            for index in promptProfiles.indices {
                promptProfiles[index].isDefault = promptProfiles[index].id == updated.id
            }
            preferences.defaultSystemPromptProfileID = updated.id
        }

        promptProfiles.upsert(updated, matching: \.id)
        normalizePromptProfileState()
    }

    func deletePromptProfile(_ profileID: UUID) {
        promptProfiles.removeAll { $0.id == profileID }
        if preferences.defaultSystemPromptProfileID == profileID {
            preferences.defaultSystemPromptProfileID = promptProfiles.first(where: \.isDefault)?.id
                ?? promptProfiles.last?.id
        }
        normalizePromptProfileState()
    }

    func renderChatTemplateSystemPrompt(
        _ template: ChatTemplate,
        for thread: AssistantThread? = nil,
        now: Date = .now
    ) -> String {
        let rendered = renderPromptTemplate(
            template.systemPrompt,
            now: now,
            thread: thread,
            knowledgeSourceIDs: template.knowledgeSourceIDs
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if rendered.isEmpty {
            return defaultSystemPrompt(for: thread, now: now)
                ?? "You are Flannel, a local-first macOS AI assistant."
        }
        return rendered
    }

    func renderChatTemplateStarterPrompt(
        _ template: ChatTemplate,
        for thread: AssistantThread? = nil,
        now: Date = .now
    ) -> String {
        let rendered = renderPromptTemplate(
            template.starterPrompt,
            now: now,
            thread: thread,
            knowledgeSourceIDs: template.knowledgeSourceIDs
        )
        return rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : rendered
    }

    func renderPromptChainSystemPrompt(
        _ chain: PromptChain,
        for thread: AssistantThread? = nil,
        now: Date = .now
    ) -> String {
        let basePrompt = renderPromptTemplate(
            chain.systemPrompt,
            now: now,
            thread: thread,
            knowledgeSourceIDs: chain.knowledgeSourceIDs
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackPrompt = defaultSystemPrompt(for: thread, now: now)
            ?? "You are Flannel, a local-first macOS AI assistant."
        let planPrompt = renderPromptChainPlanPrompt(chain, for: thread, now: now)

        return [basePrompt.isEmpty ? fallbackPrompt : basePrompt, planPrompt]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    func renderPromptChainStarterPrompt(
        _ chain: PromptChain,
        for thread: AssistantThread? = nil,
        now: Date = .now
    ) -> String {
        guard let firstStep = chain.enabledSteps.first else { return "" }
        let rendered = renderPromptTemplate(
            firstStep.instruction,
            now: now,
            thread: thread,
            knowledgeSourceIDs: chain.knowledgeSourceIDs
        )
        return rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : rendered
    }

    func promptChainState(for thread: AssistantThread? = nil) -> PromptChainThreadState? {
        guard let thread = thread ?? currentAssistantThread,
              let chainID = thread.promptChainID,
              let chain = promptChains.first(where: { $0.id == chainID }) else {
            return nil
        }

        let enabledSteps = chain.enabledSteps
        guard !enabledSteps.isEmpty else { return nil }

        let enabledStepIDs = Set(enabledSteps.map(\.id))
        let completedStepIDs = stableUnique(thread.completedPromptChainStepIDs)
            .filter { enabledStepIDs.contains($0) }
        let completedSet = Set(completedStepIDs)
        let activeIndex = thread.activePromptChainStepID.flatMap { activeStepID in
            enabledSteps.firstIndex { $0.id == activeStepID && !completedSet.contains($0.id) }
        } ?? enabledSteps.firstIndex { !completedSet.contains($0.id) }
        let activeStep = activeIndex.map { enabledSteps[$0] }

        return PromptChainThreadState(
            chain: chain,
            enabledSteps: enabledSteps,
            completedStepIDs: completedStepIDs,
            activeStep: activeStep,
            activeStepIndex: activeIndex
        )
    }

    func renderActivePromptChainStepPrompt(
        for thread: AssistantThread? = nil,
        now: Date = .now
    ) -> String {
        let resolvedThread = thread ?? currentAssistantThread
        guard let state = promptChainState(for: resolvedThread),
              let activeStep = state.activeStep else {
            return ""
        }

        let rendered = renderPromptTemplate(
            activeStep.instruction,
            now: now,
            thread: resolvedThread,
            knowledgeSourceIDs: state.chain.knowledgeSourceIDs
        )
        return rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : rendered
    }

    @discardableResult
    func markActivePromptChainStepSubmitted(
        in threadID: UUID? = nil,
        stepID: UUID? = nil
    ) -> PromptChainThreadState? {
        guard let resolvedThreadID = threadID ?? selectedAssistantThreadID,
              let threadIndex = assistantThreads.firstIndex(where: { $0.id == resolvedThreadID }),
              let state = promptChainState(for: assistantThreads[threadIndex]) else {
            return nil
        }

        let enabledStepIDs = Set(state.enabledSteps.map(\.id))
        let submittedStepID = stepID ?? state.activeStep?.id
        if let submittedStepID,
           enabledStepIDs.contains(submittedStepID),
           !assistantThreads[threadIndex].completedPromptChainStepIDs.contains(submittedStepID) {
            assistantThreads[threadIndex].completedPromptChainStepIDs.append(submittedStepID)
        }

        let completedSet = Set(assistantThreads[threadIndex].completedPromptChainStepIDs)
        let nextStep = state.enabledSteps.first { !completedSet.contains($0.id) }
        assistantThreads[threadIndex].activePromptChainStepID = nextStep?.id
        assistantThreads[threadIndex].updatedAt = .now
        normalizePromptChainThreadState()
        return promptChainState(for: assistantThreads[threadIndex])
    }

    func renderPromptChainPlanPrompt(
        _ chain: PromptChain,
        for thread: AssistantThread? = nil,
        now: Date = .now
    ) -> String {
        let renderedDetail = renderPromptTemplate(
            chain.detail,
            now: now,
            thread: thread,
            knowledgeSourceIDs: chain.knowledgeSourceIDs
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let stepLines = chain.enabledSteps.enumerated().map { offset, step in
            let renderedInstruction = renderPromptTemplate(
                step.instruction,
                now: now,
                thread: thread,
                knowledgeSourceIDs: chain.knowledgeSourceIDs
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            let expectedOutput = renderPromptTemplate(
                step.expectedOutput,
                now: now,
                thread: thread,
                knowledgeSourceIDs: chain.knowledgeSourceIDs
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let heading = title.isEmpty ? "Step \(offset + 1)" : title
            if expectedOutput.isEmpty {
                return "\(offset + 1). \(heading): \(renderedInstruction)"
            }
            return "\(offset + 1). \(heading): \(renderedInstruction)\n   Expected output: \(expectedOutput)"
        }
        .joined(separator: "\n")

        let objective = renderedDetail.isEmpty ? "" : "\nObjective: \(renderedDetail)"
        let steps = stepLines.isEmpty ? "No enabled steps are saved yet." : stepLines
        return """
        Saved prompt chain: \(chain.title)\(objective)
        Follow this workflow one step at a time. After each response, identify the next step and wait for the user unless they explicitly ask to continue.
        Steps:
        \(steps)
        """
    }

    @discardableResult
    func createAssistantThread(from template: ChatTemplate? = nil, folderID: UUID? = nil) -> AssistantThread {
        let resolvedFolderID = folderID.flatMap { candidate in
            chatFolders.contains(where: { $0.id == candidate }) ? candidate : nil
        }
        let title = template?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let knowledgeSourceIDs = validatedKnowledgeSourceIDs(template?.knowledgeSourceIDs ?? [])
        var thread = AssistantThread(
            title: title?.isEmpty == false ? title! : "New AI Chat",
            mode: template?.mode ?? .workspaceCopilot,
            messages: [],
            tagNames: canonicalTags(template?.tagNames ?? []),
            knowledgeSourceIDs: knowledgeSourceIDs,
            folderID: resolvedFolderID,
            pinnedProjectID: selectedProjectID,
            pinnedDraftID: selectedDraftID,
            pinnedAssetID: selectedAssetID,
            pinnedCalendarEntryID: selectedCalendarEntryID
        )
        let systemPrompt = template.map { renderChatTemplateSystemPrompt($0, for: thread) }
            ?? defaultSystemPrompt(for: thread)
            ?? "You are Flannel, a local-first macOS AI assistant."
        thread.messages = [
            AssistantMessage(role: .system, text: systemPrompt)
        ]

        assistantThreads.insert(thread, at: 0)
        selectedAssistantThreadID = thread.id
        selectedDestination = .home

        if let template,
           let provider = preferredProvider(for: template) {
            preferences.preferredProviderID = provider.id
            preferences.providerRoutingPolicy = .selectedProvider
        }

        return thread
    }

    @discardableResult
    func createAssistantThread(from chain: PromptChain, folderID: UUID? = nil) -> AssistantThread {
        let resolvedFolderID = folderID.flatMap { candidate in
            chatFolders.contains(where: { $0.id == candidate }) ? candidate : nil
        }
        let title = chain.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let knowledgeSourceIDs = validatedKnowledgeSourceIDs(chain.knowledgeSourceIDs)
        var thread = AssistantThread(
            title: title.isEmpty ? "Prompt Chain Chat" : title,
            mode: chain.mode,
            messages: [],
            tagNames: canonicalTags(chain.tagNames + ["prompt-chain"]),
            knowledgeSourceIDs: knowledgeSourceIDs,
            folderID: resolvedFolderID,
            pinnedProjectID: selectedProjectID,
            pinnedDraftID: selectedDraftID,
            pinnedAssetID: selectedAssetID,
            pinnedCalendarEntryID: selectedCalendarEntryID,
            promptChainID: chain.id,
            activePromptChainStepID: chain.enabledSteps.first?.id
        )
        thread.messages = [
            AssistantMessage(
                role: .system,
                text: renderPromptChainSystemPrompt(chain, for: thread)
            )
        ]

        assistantThreads.insert(thread, at: 0)
        selectedAssistantThreadID = thread.id
        selectedDestination = .home

        if let provider = preferredProvider(for: chain) {
            preferences.preferredProviderID = provider.id
            preferences.providerRoutingPolicy = .selectedProvider
        }

        return thread
    }

    @discardableResult
    func duplicateThread(from messageID: UUID, in threadID: UUID? = nil) -> AssistantThread? {
        guard let location = resolveMessageLocation(messageID, in: threadID) else { return nil }
        let sourceThread = assistantThreads[location.threadIndex]
        let duplicatedThread = AssistantThread(
            title: "Copy of \(sourceThread.title)",
            mode: sourceThread.mode,
            messages: sourceThread.messages.map { Self.copyMessageForNewThread($0) },
            tagNames: sourceThread.tagNames,
            knowledgeSourceIDs: sourceThread.knowledgeSourceIDs,
            folderID: sourceThread.folderID,
            pinnedProjectID: sourceThread.pinnedProjectID,
            pinnedDraftID: sourceThread.pinnedDraftID,
            pinnedAssetID: sourceThread.pinnedAssetID,
            pinnedCalendarEntryID: sourceThread.pinnedCalendarEntryID,
            promptChainID: sourceThread.promptChainID,
            activePromptChainStepID: sourceThread.activePromptChainStepID,
            completedPromptChainStepIDs: sourceThread.completedPromptChainStepIDs,
            createdAt: .now,
            updatedAt: .now
        )

        assistantThreads.insert(duplicatedThread, at: 0)
        selectedAssistantThreadID = duplicatedThread.id
        selectedDestination = .home
        return duplicatedThread
    }

    @discardableResult
    func forkThread(from messageID: UUID, in threadID: UUID? = nil) -> AssistantThread? {
        guard let location = resolveMessageLocation(messageID, in: threadID) else { return nil }
        let sourceThread = assistantThreads[location.threadIndex]
        let sourceMessage = sourceThread.messages[location.messageIndex]
        let forkedMessages = sourceThread.messages
            .prefix(location.messageIndex + 1)
            .map { Self.copyMessageForNewThread($0) }
        let promptChainProgress = promptChainProgress(for: forkedMessages, sourceThread: sourceThread)
        let forkedThread = AssistantThread(
            title: "Fork: \(Self.threadTitle(from: sourceMessage.text.isEmpty ? sourceThread.title : sourceMessage.text))",
            mode: sourceThread.mode,
            messages: forkedMessages,
            tagNames: sourceThread.tagNames,
            knowledgeSourceIDs: sourceThread.knowledgeSourceIDs,
            folderID: sourceThread.folderID,
            pinnedProjectID: sourceThread.pinnedProjectID,
            pinnedDraftID: sourceThread.pinnedDraftID,
            pinnedAssetID: sourceThread.pinnedAssetID,
            pinnedCalendarEntryID: sourceThread.pinnedCalendarEntryID,
            promptChainID: sourceThread.promptChainID,
            activePromptChainStepID: promptChainProgress.activeStepID,
            completedPromptChainStepIDs: promptChainProgress.completedStepIDs,
            createdAt: .now,
            updatedAt: .now
        )

        assistantThreads.insert(forkedThread, at: 0)
        selectedAssistantThreadID = forkedThread.id
        selectedDestination = .home
        return forkedThread
    }

    private func promptChainProgress(
        for messages: [AssistantMessage],
        sourceThread: AssistantThread
    ) -> (activeStepID: UUID?, completedStepIDs: [UUID]) {
        guard let promptChainID = sourceThread.promptChainID,
              let chain = promptChains.first(where: { $0.id == promptChainID }) else {
            return (sourceThread.activePromptChainStepID, sourceThread.completedPromptChainStepIDs)
        }

        let enabledStepIDs = chain.enabledSteps.map(\.id)
        guard !enabledStepIDs.isEmpty else { return (nil, []) }
        let enabledStepIDSet = Set(enabledStepIDs)
        let sourceCompletedStepIDSet = Set(sourceThread.completedPromptChainStepIDs)
        let branchCompletedStepIDs = stableUnique(messages.compactMap(\.promptChainStepID))
            .filter { enabledStepIDSet.contains($0) && sourceCompletedStepIDSet.contains($0) }
        let branchCompletedSet = Set(branchCompletedStepIDs)
        let activeStepID = enabledStepIDs.first { !branchCompletedSet.contains($0) }
        return (activeStepID, branchCompletedStepIDs)
    }

    @discardableResult
    func archiveThread(_ threadID: UUID? = nil) -> Bool {
        guard let resolvedThreadID = threadID ?? selectedAssistantThreadID,
              let index = assistantThreads.firstIndex(where: { $0.id == resolvedThreadID }) else {
            return false
        }

        archivedAssistantThreadIDs.insert(resolvedThreadID)
        assistantThreads[index].isArchived = true

        if selectedAssistantThreadID == resolvedThreadID {
            selectedAssistantThreadID = activeAssistantThreads.first?.id
        }

        return true
    }

    @discardableResult
    func unarchiveThread(_ threadID: UUID) -> Bool {
        guard let index = assistantThreads.firstIndex(where: { $0.id == threadID }),
              archivedAssistantThreadIDs.remove(threadID) != nil else {
            return false
        }

        assistantThreads[index].isArchived = false
        selectedAssistantThreadID = threadID
        selectedDestination = .home
        return true
    }

    @discardableResult
    func addChatFolder(
        title rawTitle: String,
        parentID: UUID? = nil,
        symbolName: String = "folder"
    ) -> ChatFolder? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let folder = ChatFolder(
            parentID: parentID.flatMap { parentID in
                chatFolders.contains(where: { $0.id == parentID }) ? parentID : nil
            },
            title: title,
            symbolName: symbolName
        )
        chatFolders.append(folder)
        return folder
    }

    @discardableResult
    func updateChatFolder(_ folderID: UUID, title rawTitle: String, symbolName: String? = nil) -> Bool {
        guard let index = chatFolders.firstIndex(where: { $0.id == folderID }) else { return false }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        chatFolders[index].title = title
        if let symbolName,
           !symbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chatFolders[index].symbolName = symbolName
        }
        chatFolders[index].updatedAt = .now
        return true
    }

    @discardableResult
    func moveChatFolder(_ folderID: UUID, toParent parentID: UUID?) -> Bool {
        guard let index = chatFolders.firstIndex(where: { $0.id == folderID }) else { return false }

        if let parentID {
            guard chatFolders.contains(where: { $0.id == parentID }),
                  parentID != folderID,
                  !descendantFolderIDs(of: folderID).contains(parentID) else {
                return false
            }
        }

        guard chatFolders[index].parentID != parentID else { return true }
        chatFolders[index].parentID = parentID
        chatFolders[index].updatedAt = .now
        return true
    }

    @discardableResult
    func deleteChatFolder(_ folderID: UUID) -> Bool {
        guard chatFolders.contains(where: { $0.id == folderID }) else { return false }
        let removedIDs = descendantFolderIDs(of: folderID).union([folderID])
        chatFolders.removeAll { removedIDs.contains($0.id) }
        for index in assistantThreads.indices where assistantThreads[index].folderID.map(removedIDs.contains) == true {
            assistantThreads[index].folderID = nil
            assistantThreads[index].updatedAt = .now
        }
        return true
    }

    @discardableResult
    func assignThread(_ threadID: UUID? = nil, toFolder folderID: UUID?) -> Bool {
        guard let resolvedThreadID = threadID ?? selectedAssistantThreadID,
              let index = assistantThreads.firstIndex(where: { $0.id == resolvedThreadID }) else {
            return false
        }

        if let folderID,
           !chatFolders.contains(where: { $0.id == folderID }) {
            return false
        }

        assistantThreads[index].folderID = folderID
        assistantThreads[index].updatedAt = .now
        return true
    }

    func folder(for thread: AssistantThread) -> ChatFolder? {
        guard let folderID = thread.folderID else { return nil }
        return chatFolders.first(where: { $0.id == folderID })
    }

    @discardableResult
    func renameAssistantThread(_ threadID: UUID? = nil, to rawTitle: String) -> Bool {
        guard let resolvedThreadID = threadID ?? selectedAssistantThreadID,
              let index = assistantThreads.firstIndex(where: { $0.id == resolvedThreadID }) else {
            return false
        }

        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        assistantThreads[index].title = title.isEmpty ? "New AI Chat" : title
        assistantThreads[index].updatedAt = .now
        return true
    }

    func threadKnowledgeSources(for thread: AssistantThread?) -> [KnowledgeSource] {
        knowledgeSourcesForScope(threadKnowledgeSourceScope(for: thread))
    }

    func currentThreadKnowledgeSourceScope() -> Set<UUID>? {
        threadKnowledgeSourceScope(for: currentAssistantThread)
    }

    func threadKnowledgeSourceScope(for thread: AssistantThread?) -> Set<UUID>? {
        if let thread,
           !thread.knowledgeSourceIDs.isEmpty {
            return Set(thread.knowledgeSourceIDs)
        }

        guard let profile = projectAIProfile(for: thread),
              profile.hasScopedKnowledge else {
            return nil
        }

        return Set(profile.knowledgeSourceIDs)
    }

    @discardableResult
    func setThreadKnowledgeSourceScope(_ sourceIDs: Set<UUID>, threadID: UUID? = nil) -> Bool {
        guard let resolvedThreadID = threadID ?? selectedAssistantThreadID,
              let index = assistantThreads.firstIndex(where: { $0.id == resolvedThreadID }) else {
            return false
        }

        assistantThreads[index].knowledgeSourceIDs = validatedKnowledgeSourceIDs(Array(sourceIDs))
        assistantThreads[index].updatedAt = .now
        return true
    }

    @discardableResult
    func toggleThreadKnowledgeSource(_ sourceID: UUID, threadID: UUID? = nil) -> Bool {
        guard knowledgeSources.contains(where: { $0.id == sourceID }),
              let resolvedThreadID = threadID ?? selectedAssistantThreadID,
              let index = assistantThreads.firstIndex(where: { $0.id == resolvedThreadID }) else {
            return false
        }

        var scopedIDs = Set(assistantThreads[index].knowledgeSourceIDs)
        if scopedIDs.contains(sourceID) {
            scopedIDs.remove(sourceID)
        } else {
            scopedIDs.insert(sourceID)
        }
        assistantThreads[index].knowledgeSourceIDs = validatedKnowledgeSourceIDs(Array(scopedIDs))
        assistantThreads[index].updatedAt = .now
        return true
    }

    func threadCount(inFolder folderID: UUID?) -> Int {
        assistantThreads.filter { $0.folderID == folderID }.count
    }

    func threadCount(inFolder folderID: UUID?, includingDescendants: Bool) -> Int {
        guard includingDescendants,
              let folderID else {
            return threadCount(inFolder: folderID)
        }

        let folderIDs = folderIDsIncludingDescendants(of: folderID)
        return assistantThreads.filter { thread in
            thread.folderID.map(folderIDs.contains) == true
        }.count
    }

    func chatHistoryThreads(
        includeArchived: Bool = true,
        filters: ChatHistoryFilters = ChatHistoryFilters(),
        now: Date = .now
    ) -> [AssistantThread] {
        assistantThreads
            .filter { includeArchived || !archivedAssistantThreadIDs.contains($0.id) }
            .filter { chatHistoryFilters(filters, match: $0, now: now) }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func descendantFolderIDs(of folderID: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var stack = chatFolders.filter { $0.parentID == folderID }.map(\.id)
        while let childID = stack.popLast() {
            guard result.insert(childID).inserted else { continue }
            stack.append(contentsOf: chatFolders.filter { $0.parentID == childID }.map(\.id))
        }
        return result
    }

    func folderIDsIncludingDescendants(of folderID: UUID) -> Set<UUID> {
        guard chatFolders.contains(where: { $0.id == folderID }) else {
            return []
        }

        return descendantFolderIDs(of: folderID).union([folderID])
    }

    func folderPathTitle(for folderID: UUID?, separator: String = " / ") -> String? {
        guard let folderID,
              let folder = chatFolders.first(where: { $0.id == folderID }) else {
            return nil
        }

        return folderPathTitle(for: folder, separator: separator)
    }

    func folderPathTitle(for folder: ChatFolder, separator: String = " / ") -> String {
        var titles = [folder.title]
        var visitedIDs = Set([folder.id])
        var parentID = folder.parentID

        while let currentParentID = parentID,
              !visitedIDs.contains(currentParentID),
              let parent = chatFolders.first(where: { $0.id == currentParentID }) {
            titles.append(parent.title)
            visitedIDs.insert(currentParentID)
            parentID = parent.parentID
        }

        return titles.reversed().joined(separator: separator)
    }

    func searchChats(
        _ rawQuery: String,
        includeArchived: Bool = true,
        limit: Int = 50,
        filters: ChatHistoryFilters = ChatHistoryFilters(),
        now: Date = .now
    ) -> [AssistantChatSearchResult] {
        guard limit > 0 else { return [] }

        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let threads = chatHistoryThreads(
            includeArchived: includeArchived,
            filters: filters,
            now: now
        )

        guard !query.isEmpty else {
            return Array(threads.prefix(limit)).map { thread in
                AssistantChatSearchResult(
                    id: "thread-\(thread.id.uuidString)",
                    threadID: thread.id,
                    messageID: nil,
                    title: thread.title,
                    snippet: thread.messages.last?.text ?? "",
                    matchKind: .threadTitle,
                    role: nil,
                    createdAt: thread.updatedAt,
                    isArchived: archivedAssistantThreadIDs.contains(thread.id),
                    isPinned: thread.isPinned || pinnedMessages.contains { $0.threadID == thread.id }
                )
            }
        }

        var results: [AssistantChatSearchResult] = []
        for thread in threads {
            let folder = folder(for: thread)
            let folderPath = folderPathTitle(for: thread.folderID)
            if thread.title.localizedCaseInsensitiveContains(query)
                || thread.tagNames.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                || folder?.title.localizedCaseInsensitiveContains(query) == true
                || folderPath?.localizedCaseInsensitiveContains(query) == true {
                results.append(
                    AssistantChatSearchResult(
                        id: "thread-\(thread.id.uuidString)",
                        threadID: thread.id,
                        messageID: nil,
                        title: thread.title,
                        snippet: thread.messages.last?.text ?? "",
                        matchKind: .threadTitle,
                        role: nil,
                        createdAt: thread.updatedAt,
                        isArchived: archivedAssistantThreadIDs.contains(thread.id),
                        isPinned: thread.isPinned || pinnedMessages.contains { $0.threadID == thread.id }
                    )
                )
            }

            for message in thread.messages {
                if message.text.localizedCaseInsensitiveContains(query)
                || message.role.rawValue.localizedCaseInsensitiveContains(query) {
                    results.append(
                        chatSearchResult(
                            thread: thread,
                            message: message,
                            query: query,
                            matchKind: .messageText
                        )
                    )
                }

                if let attachment = message.attachments.first(where: {
                    $0.title.localizedCaseInsensitiveContains(query)
                        || $0.excerpt?.localizedCaseInsensitiveContains(query) == true
                        || $0.localPath?.localizedCaseInsensitiveContains(query) == true
                }) {
                    results.append(
                        chatSearchResult(
                            thread: thread,
                            message: message,
                            query: query,
                            matchKind: .attachment,
                            citationSnippet: attachment.excerpt?.isEmpty == false ? attachment.excerpt : attachment.title
                        )
                    )
                }

                if let citation = message.citations.first(where: {
                    $0.title.localizedCaseInsensitiveContains(query)
                        || $0.snippet.localizedCaseInsensitiveContains(query)
                }) {
                    results.append(
                        chatSearchResult(
                            thread: thread,
                            message: message,
                            query: query,
                            matchKind: .citation,
                            citationSnippet: citation.snippet.isEmpty ? citation.title : citation.snippet
                        )
                    )
                }

                if results.count >= limit {
                    return Array(results.prefix(limit))
                }
            }

            if results.count >= limit {
                return Array(results.prefix(limit))
            }
        }

        return Array(results.prefix(limit))
    }

    private func chatHistoryFilters(
        _ filters: ChatHistoryFilters,
        match thread: AssistantThread,
        now: Date
    ) -> Bool {
        if let providerDisplayName = filters.providerDisplayName,
           !thread.messages.contains(where: { message in
               message.providerDisplayName?.caseInsensitiveCompare(providerDisplayName) == .orderedSame
           }) {
            return false
        }

        if let modelIdentifier = filters.modelIdentifier,
           !thread.messages.contains(where: { message in
               message.modelIdentifier?.caseInsensitiveCompare(modelIdentifier) == .orderedSame
           }) {
            return false
        }

        if let projectID = filters.projectID,
           thread.pinnedProjectID != projectID,
           !thread.messages.contains(where: { $0.referencedEntityIDs.contains(projectID) }) {
            return false
        }

        return chatHistoryDateFilter(filters.dateFilter, matches: thread.updatedAt, now: now)
    }

    private func chatHistoryDateFilter(
        _ filter: ChatHistoryDateFilter,
        matches date: Date,
        now: Date
    ) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        let startOfToday = calendar.startOfDay(for: now)

        switch filter {
        case .all:
            return true
        case .today:
            return date >= startOfToday
        case .previousSevenDays:
            let start = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
            return date >= start
        case .previousThirtyDays:
            let start = calendar.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday
            return date >= start
        case .previousNinetyDays:
            let start = calendar.date(byAdding: .day, value: -90, to: startOfToday) ?? startOfToday
            return date >= start
        }
    }

    @discardableResult
    func captureManualURL(
        _ rawValue: String,
        title: String? = nil,
        notes: String = "",
        tags extraTags: [String] = []
    ) -> UUID? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let url = URL(string: trimmed)
        let platform = inferPlatform(from: url)
        let assetTitle = title ?? inferredCaptureTitle(for: url)
        let mergedTags = canonicalTags(defaultTags(for: platform, url: url) + extraTags + ["manual", "inbox"])
        let transcript: TranscriptRecord?

        if platform == .youtube {
            transcript = TranscriptRecord(
                status: .queued,
                text: "",
                languageCode: preferences.defaultTranscriptLanguageCode ?? "en",
                sourceLabel: "Awaiting local import",
                importedAt: .now,
                updatedAt: .now
            )
        } else {
            transcript = nil
        }

        let asset = LibraryAsset(
            title: assetTitle,
            kind: .link,
            platform: platform,
            sourceURL: url,
            summary: "Saved locally from a pasted URL. Metadata import stays opt-in and local actions remain explicit.",
            summaryStatus: .missing,
            tags: mergedTags,
            projectID: selectedProjectID,
            createdAt: .now,
            updatedAt: .now,
            capturedAt: .now,
            transcript: transcript,
            notes: notes
        )

        libraryAssets.insert(asset, at: 0)
        selectedAssetID = asset.id
        selectedDestination = .home
        attachAssetToCurrentProjectIfPossible(assetID: asset.id)
        adjustPendingImportCount(for: platform, delta: transcript == nil ? 0 : 1)
        recordLocalAction(
            kind: .captureURL,
            title: "Saved local capture",
            detail: "Stored \(asset.title) locally without performing any network import.",
            status: .completed,
            destination: .inbox,
            relatedAssetID: asset.id,
            completedAt: .now
        )
        appendAssistantMessage("I saved that URL locally. It is in Inbox and can be linked, summarized, or queued for transcript import without touching an external API.", role: .assistant)
        normalizeWorkspace()
        return asset.id
    }

    func saveManualURL(_ rawValue: String) {
        _ = captureManualURL(rawValue)
    }

    func draftFromSelectedAsset() {
        guard let asset = currentLibraryAsset else {
            appendAssistantMessage("Select a saved source first, then I can create a linked draft from it.", role: .assistant)
            return
        }

        let platform = asset.platform ?? inferPlatform(from: asset.sourceURL)
        let outline = asset.summaryRecords.first?.bulletPoints ?? generatedBulletPoints(for: asset)
        let projectID = asset.projectID ?? selectedProjectID
        let mergedTags = canonicalTags(asset.tags + (currentProject?.tagNames ?? []))
        let body = buildDraftBody(from: asset, outline: outline)
        let draft = DraftDocument(
            title: "Draft from \(asset.title)",
            platform: platform ?? .internalNote,
            status: .inProgress,
            body: body,
            summary: asset.summary.isEmpty ? "Source-linked draft generated from \(asset.title)." : asset.summary,
            projectID: projectID,
            scheduledFor: nil,
            tags: mergedTags,
            createdAt: .now,
            updatedAt: .now,
            sourceAssetIDs: [asset.id],
            outline: outline,
            publishNotes: "Keep as a local draft until review is complete.",
            summaryRecords: asset.summaryRecords,
            wordCountEstimate: body.split(whereSeparator: \.isWhitespace).count,
            requiresReview: true
        )

        drafts.insert(draft, at: 0)
        selectedDraftID = draft.id
        selectedDestination = .home

        if let assetIndex = libraryAssets.firstIndex(where: { $0.id == asset.id }) {
            libraryAssets[assetIndex].draftID = draft.id
            libraryAssets[assetIndex].updatedAt = .now
        }

        attachDraftToCurrentProjectIfPossible(draftID: draft.id, projectID: projectID)
        recordLocalAction(
            kind: .createDraft,
            title: "Created local draft",
            detail: "Generated \(draft.title) from \(asset.title) and preserved the source link locally.",
            status: .completed,
            destination: .drafts,
            relatedDraftID: draft.id,
            relatedAssetID: asset.id,
            completedAt: .now
        )
        appendAssistantMessage("I created a source-linked draft from \(asset.title). The transcript, summary, and tags stay attached to the draft context.", role: .assistant)
        normalizeWorkspace()
    }

    func summarizeSelectedAsset() {
        guard let asset = currentLibraryAsset else {
            appendAssistantMessage("Select a video, thread, note, or link and I can summarize it with local context.", role: .assistant)
            return
        }

        let summaryText = generatedSummaryText(for: asset)
        let bullets = generatedBulletPoints(for: asset)
        storeSummary(
            for: asset.id,
            title: "Local summary",
            text: summaryText,
            bulletPoints: bullets,
            modelLabel: activeProvider?.displayName
        )

        appendAssistantMessage(
            """
            Summary for \(asset.title):

            \(summaryText)

            Useful tags: \(canonicalTags(asset.tags).joined(separator: ", ")).
            Best next move: \(draftRecommendation(for: asset))
            """,
            role: .assistant
        )
    }

    func queueTranscriptImport(for assetID: UUID? = nil) {
        guard let assetIndex = indexOfAsset(assetID) else {
            appendAssistantMessage("Select a source before queuing transcript import.", role: .assistant)
            return
        }

        let asset = libraryAssets[assetIndex]
        let languageCode = preferences.defaultTranscriptLanguageCode ?? "en"
        let existingTranscript = asset.transcript
        libraryAssets[assetIndex].platform = asset.platform ?? inferPlatform(from: asset.sourceURL)
        libraryAssets[assetIndex].transcript = TranscriptRecord(
            status: .queued,
            text: existingTranscript?.text ?? "",
            languageCode: existingTranscript?.languageCode ?? languageCode,
            sourceLabel: "Awaiting local import",
            importedAt: existingTranscript?.importedAt ?? .now,
            updatedAt: .now,
            lastErrorMessage: nil
        )
        libraryAssets[assetIndex].updatedAt = .now
        adjustPendingImportCount(for: libraryAssets[assetIndex].platform, delta: 1)
        recordLocalAction(
            kind: .importTranscript,
            title: "Queued transcript import",
            detail: "Marked \(asset.title) for local transcript import.",
            status: .completed,
            destination: .youtube,
            relatedAssetID: asset.id,
            completedAt: .now
        )
        normalizeWorkspace()
    }

    func storeTranscript(
        for assetID: UUID? = nil,
        text: String,
        languageCode: String? = nil,
        sourceLabel: String = "Local import"
    ) {
        guard let assetIndex = indexOfAsset(assetID) else { return }

        libraryAssets[assetIndex].transcript = TranscriptRecord(
            status: .available,
            text: text,
            languageCode: languageCode ?? preferences.defaultTranscriptLanguageCode ?? "en",
            sourceLabel: sourceLabel,
            importedAt: libraryAssets[assetIndex].transcript?.importedAt ?? .now,
            updatedAt: .now,
            lastErrorMessage: nil
        )
        libraryAssets[assetIndex].summaryStatus = libraryAssets[assetIndex].summaryRecords.isEmpty ? .missing : .stale
        libraryAssets[assetIndex].updatedAt = .now
        adjustPendingImportCount(for: libraryAssets[assetIndex].platform, delta: -1)
        recordLocalAction(
            kind: .importTranscript,
            title: "Stored transcript locally",
            detail: "Saved a transcript snapshot for \(libraryAssets[assetIndex].title).",
            status: .completed,
            destination: .youtube,
            relatedAssetID: libraryAssets[assetIndex].id,
            completedAt: .now
        )
        normalizeWorkspace()
    }

    func storeSummary(
        for assetID: UUID? = nil,
        title: String = "Local summary",
        text: String,
        bulletPoints: [String] = [],
        modelLabel: String? = nil
    ) {
        guard let assetIndex = indexOfAsset(assetID) else { return }

        let record = SummaryRecord(
            title: title,
            text: text,
            bulletPoints: bulletPoints,
            status: .ready,
            sourceLabel: "Flannel local workspace",
            modelLabel: modelLabel,
            createdAt: .now
        )

        if libraryAssets[assetIndex].summaryRecords.first?.text != text {
            libraryAssets[assetIndex].summaryRecords.insert(record, at: 0)
        }
        libraryAssets[assetIndex].summary = text
        libraryAssets[assetIndex].summaryStatus = .ready
        libraryAssets[assetIndex].updatedAt = .now

        for draftIndex in drafts.indices where drafts[draftIndex].sourceAssetIDs.contains(libraryAssets[assetIndex].id) {
            drafts[draftIndex].summary = text
            if drafts[draftIndex].summaryRecords.first?.text != text {
                drafts[draftIndex].summaryRecords.insert(record, at: 0)
            }
            drafts[draftIndex].updatedAt = .now
        }

        recordLocalAction(
            kind: .generateSummary,
            title: "Generated local summary",
            detail: "Updated the summary state for \(libraryAssets[assetIndex].title).",
            status: .completed,
            destination: .library,
            relatedAssetID: libraryAssets[assetIndex].id,
            completedAt: .now
        )
        normalizeWorkspace()
    }

    func linkSelectedAssetToCurrentProject() {
        guard let assetID = selectedAssetID else { return }
        attachAssetToCurrentProjectIfPossible(assetID: assetID)
        recordLocalAction(
            kind: .captureURL,
            title: "Linked source to project",
            detail: "Attached the selected source to the active project.",
            status: .completed,
            destination: .projects,
            relatedAssetID: assetID,
            completedAt: .now
        )
        normalizeWorkspace()
    }

    func applyTags(
        _ rawNames: [String],
        toAssetID assetID: UUID? = nil,
        draftID: UUID? = nil,
        projectID: UUID? = nil,
        threadID: UUID? = nil
    ) {
        let tagNames = canonicalTags(rawNames)
        guard !tagNames.isEmpty else { return }

        if let threadID, let index = assistantThreads.firstIndex(where: { $0.id == threadID }) {
            assistantThreads[index].tagNames = canonicalTags(assistantThreads[index].tagNames + tagNames)
            assistantThreads[index].updatedAt = .now
        }

        if let assetID, let index = libraryAssets.firstIndex(where: { $0.id == assetID }) {
            libraryAssets[index].tags = canonicalTags(libraryAssets[index].tags + tagNames)
            libraryAssets[index].updatedAt = .now
        }

        if let draftID, let index = drafts.firstIndex(where: { $0.id == draftID }) {
            drafts[index].tags = canonicalTags(drafts[index].tags + tagNames)
            drafts[index].updatedAt = .now
        }

        if let projectID, let index = projects.firstIndex(where: { $0.id == projectID }) {
            projects[index].tagNames = canonicalTags(projects[index].tagNames + tagNames)
            projects[index].updatedAt = .now
        }

        normalizeWorkspace()
    }

    @discardableResult
    func removeTag(_ rawName: String, fromThread threadID: UUID? = nil) -> Bool {
        let tagName = normalizeTag(rawName)
        guard !tagName.isEmpty,
              let resolvedThreadID = threadID ?? selectedAssistantThreadID,
              let threadIndex = assistantThreads.firstIndex(where: { $0.id == resolvedThreadID }) else {
            return false
        }

        let originalCount = assistantThreads[threadIndex].tagNames.count
        assistantThreads[threadIndex].tagNames.removeAll { normalizeTag($0) == tagName }
        guard assistantThreads[threadIndex].tagNames.count != originalCount else {
            return false
        }

        assistantThreads[threadIndex].updatedAt = .now
        normalizeWorkspace()
        return true
    }

    func scheduleSelectedDraft(
        on date: Date = .now,
        notes: String = "",
        destination: WorkspaceDestination = .calendar
    ) {
        guard let draft = currentDraft else {
            appendAssistantMessage("Select a draft before adding it to the local calendar.", role: .assistant)
            return
        }

        if let draftIndex = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[draftIndex].scheduledFor = date
            drafts[draftIndex].status = .scheduled
            drafts[draftIndex].updatedAt = .now
        }

        let projectID = draft.projectID ?? selectedProjectID
        var entry = PublishingCalendarEntry(
            title: draft.title,
            startAt: date,
            destination: destination,
            projectID: projectID,
            draftID: draft.id,
            notes: notes.isEmpty ? "Scheduled locally from the Drafts workspace." : notes,
            platform: draft.platform,
            status: .scheduled,
            reminderMinutesBefore: 60,
            createdAt: .now,
            updatedAt: .now
        )

        if let existingIndex = calendarEntries.firstIndex(where: { $0.draftID == draft.id }) {
            entry.id = calendarEntries[existingIndex].id
            entry.createdAt = calendarEntries[existingIndex].createdAt
            calendarEntries[existingIndex] = entry
        } else {
            calendarEntries.insert(entry, at: 0)
        }

        selectedCalendarEntryID = entry.id
        selectedDestination = .home
        attachDraftToCurrentProjectIfPossible(draftID: draft.id, projectID: projectID)
        recordLocalAction(
            kind: .scheduleDraft,
            title: "Scheduled local calendar entry",
            detail: "Placed \(draft.title) on the local content calendar.",
            status: .completed,
            destination: .calendar,
            relatedDraftID: draft.id,
            completedAt: .now
        )
        normalizeWorkspace()
    }

    func toggleAutomation(_ automationID: UUID, isEnabled: Bool? = nil) {
        guard let index = automations.firstIndex(where: { $0.id == automationID }) else { return }
        automations[index].isEnabled = isEnabled ?? !automations[index].isEnabled
        automations[index].updatedAt = .now
    }

    func runAutomation(_ automationID: UUID) {
        guard let index = automations.firstIndex(where: { $0.id == automationID }) else { return }
        let now = Date()
        guard preferences.automationsEnabled ?? true else {
            automations[index].lastRunState = .failed
            automations[index].lastResultMessage = "Automations are disabled in Settings."
            automations[index].updatedAt = now
            recordLocalAction(
                kind: .runAutomation,
                title: automations[index].title,
                detail: "Automations are disabled in Settings.",
                status: .failed,
                destination: .automations,
                automationID: automations[index].id
            )
            return
        }

        automations[index].lastRunAt = now
        automations[index].updatedAt = now

        if automations[index].requiresConfirmation {
            automations[index].lastRunState = .needsConfirmation
            automations[index].lastResultMessage = "Awaiting local confirmation."
            recordLocalAction(
                kind: .runAutomation,
                title: automations[index].title,
                detail: automations[index].detail,
                status: .requiresConfirmation,
                destination: .automations,
                automationID: automations[index].id,
                requiresConfirmation: true
            )
            return
        }

        let automation = automations[index]
        let action = automation.resolvedAction
        let resultMessage: String
        let resultState: AutomationRunState
        let actionStatus: LocalActionStatus
        let requiresConfirmation: Bool

        switch action.kind {
        case .generateSummary:
            if let asset = currentLibraryAsset ?? assetsNeedingSummary.first {
                selectedAssetID = asset.id
                summarizeSelectedAsset()
                resultMessage = "Summarized \(asset.title)."
                resultState = .succeeded
                actionStatus = .completed
                requiresConfirmation = false
            } else {
                resultMessage = "No sources currently need a summary."
                resultState = .succeeded
                actionStatus = .completed
                requiresConfirmation = false
            }
        case .importTranscript:
            if let asset = pendingTranscriptAssets.first {
                queueTranscriptImport(for: asset.id)
                resultMessage = "Queued transcript import for \(asset.title)."
                resultState = .succeeded
                actionStatus = .completed
                requiresConfirmation = false
            } else {
                resultMessage = "No pending transcript work was found."
                resultState = .succeeded
                actionStatus = .completed
                requiresConfirmation = false
            }
        case .createDraft:
            if let asset = currentLibraryAsset ?? libraryAssets.first {
                selectedAssetID = asset.id
                draftFromSelectedAsset()
                resultMessage = "Created a draft from \(asset.title)."
                resultState = .succeeded
                actionStatus = .completed
                requiresConfirmation = false
            } else {
                resultMessage = "No source is available to draft from."
                resultState = .succeeded
                actionStatus = .completed
                requiresConfirmation = false
            }
        case .scheduleDraft:
            if let draft = unscheduledDrafts.first {
                selectedDraftID = draft.id
                scheduleSelectedDraft(
                    on: defaultScheduleDate(from: .now),
                    notes: "Scheduled locally by automation.",
                    destination: .calendar
                )
                resultMessage = "Scheduled \(draft.title) locally."
                resultState = .succeeded
                actionStatus = .completed
                requiresConfirmation = false
            } else {
                resultMessage = "No unscheduled draft is ready."
                resultState = .succeeded
                actionStatus = .completed
                requiresConfirmation = false
            }
        case .exportDraft:
            if let draftIndex = drafts.firstIndex(where: { $0.id == (selectedDraftID ?? drafts.first?.id) }) {
                drafts[draftIndex].lastExportedAt = now
                drafts[draftIndex].updatedAt = now
                recordLocalAction(
                    kind: .exportDraft,
                    title: "Prepared draft export metadata",
                    detail: "Recorded a local export event for \(drafts[draftIndex].title).",
                    status: .completed,
                    destination: .drafts,
                    relatedDraftID: drafts[draftIndex].id,
                    completedAt: now
                )
                resultMessage = "Marked \(drafts[draftIndex].title) as exported locally."
                resultState = .succeeded
                actionStatus = .completed
                requiresConfirmation = false
            } else {
                resultMessage = "No draft is selected for export."
                resultState = .succeeded
                actionStatus = .completed
                requiresConfirmation = false
            }
        case .runTool:
            if let toolKind = action.toolKind,
               isAutomationSafeToolKind(toolKind) {
                let result = runTool(toolKind, query: action.query ?? "")
                resultMessage = automationResultMessage(for: result)
                resultState = automationRunState(for: result)
                actionStatus = result.localActionStatus
                requiresConfirmation = result.requiresApproval
            } else if let toolKind = action.toolKind {
                resultMessage = "\(toolKind.rawValue) is not allowed to run autonomously. Use Tools for approval-gated network, browser, shell, code, or file-write actions."
                resultState = .failed
                actionStatus = .failed
                requiresConfirmation = false
            } else {
                resultMessage = "This automation is missing a tool kind."
                resultState = .failed
                actionStatus = .failed
                requiresConfirmation = false
            }
        case .captureURL, .runAutomation:
            resultMessage = "This automation type is not configured for autonomous local execution."
            resultState = .failed
            actionStatus = .failed
            requiresConfirmation = false
        }

        automations[index].lastRunState = resultState
        if resultState == .succeeded {
            automations[index].nextRunAt = nextRunDate(for: automations[index].cadence, from: now)
        }
        automations[index].lastResultMessage = resultMessage
        automations[index].updatedAt = now
        recordLocalAction(
            kind: .runAutomation,
            title: automation.title,
            detail: resultMessage,
            status: actionStatus,
            destination: .automations,
            automationID: automation.id,
            requiresConfirmation: requiresConfirmation,
            completedAt: resultState == .succeeded ? now : nil
        )
    }

    private func isAutomationSafeToolKind(_ toolKind: AIToolKind) -> Bool {
        switch toolKind {
        case .workspaceSearch, .ragRetrieval:
            true
        case .webSearch, .webPageReader, .localFileRead, .localFileWrite, .terminal,
             .codeExecution, .browserAutomation, .github, .notion, .youtube, .x:
            false
        }
    }

    private func automationRunState(for result: LocalToolExecutionResult) -> AutomationRunState {
        switch result.status {
        case .completed:
            .succeeded
        case .requiresApproval:
            .needsConfirmation
        case .denied, .blocked, .unavailable:
            .failed
        }
    }

    private func automationResultMessage(for result: LocalToolExecutionResult) -> String {
        let status = result.status.rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
        let query = result.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryLine = query.isEmpty ? "" : " Query: \(query)."
        return "\(result.title) finished with \(status).\(queryLine)\n\n\(result.output)"
    }

    func confirmLocalAction(_ actionID: UUID) {
        guard let index = localActionHistory.firstIndex(where: { $0.id == actionID }) else { return }
        localActionHistory[index].status = .completed
        localActionHistory[index].completedAt = .now

        if let automationID = localActionHistory[index].automationID,
           let automationIndex = automations.firstIndex(where: { $0.id == automationID }) {
            automations[automationIndex].lastRunState = .succeeded
            automations[automationIndex].lastRunAt = .now
            automations[automationIndex].nextRunAt = nextRunDate(for: automations[automationIndex].cadence, from: .now)
            automations[automationIndex].lastResultMessage = "Confirmed locally."
            automations[automationIndex].updatedAt = .now
        }
    }

    func markProviderStatus(
        _ providerID: UUID,
        status: IntegrationConnectionStatus,
        lastErrorMessage: String? = nil,
        validatedAt: Date? = nil
    ) {
        guard let index = providerConfigurations.firstIndex(where: { $0.id == providerID }) else { return }
        providerConfigurations[index].connectionStatus = status
        providerConfigurations[index].lastErrorMessage = lastErrorMessage
        providerConfigurations[index].lastValidatedAt = validatedAt ?? providerConfigurations[index].lastValidatedAt
    }

    @discardableResult
    func runTool(_ toolID: UUID, query rawQuery: String = "") -> LocalToolExecutionResult? {
        guard let tool = toolConfigurations.first(where: { $0.id == toolID }) else { return nil }

        let query = normalizedToolQuery(for: tool, rawQuery: rawQuery)
        let result = LocalToolExecutionService().run(toolExecutionContext(for: tool, query: query))
        recordToolExecutionResult(result)
        return result
    }

    @discardableResult
    func runTool(
        _ toolID: UUID,
        query rawQuery: String = "",
        webPageCaptureService: WebPageCaptureService,
        webSearchService: WebSearchService = WebSearchService(),
        gitHubToolService: GitHubToolService = GitHubToolService(),
        notionToolService: NotionToolService = NotionToolService(),
        youTubeToolService: YouTubeToolService = YouTubeToolService(),
        xToolService: XToolService = XToolService(),
        browserAutomationService: BrowserAutomationService = BrowserAutomationService(),
        secretReader: @escaping ToolSecretReader = WorkspaceStore.defaultToolSecretReader
    ) async -> LocalToolExecutionResult? {
        guard let tool = toolConfigurations.first(where: { $0.id == toolID }) else { return nil }

        let query = normalizedToolQuery(for: tool, rawQuery: rawQuery)
        let result = await executeTool(
            tool,
            query: query,
            webPageCaptureService: webPageCaptureService,
            webSearchService: webSearchService,
            gitHubToolService: gitHubToolService,
            notionToolService: notionToolService,
            youTubeToolService: youTubeToolService,
            xToolService: xToolService,
            browserAutomationService: browserAutomationService,
            secretReader: secretReader
        )
        recordToolExecutionResult(result)
        return result
    }

    @discardableResult
    func resolveToolApproval(_ resultID: UUID, approve: Bool) -> LocalToolExecutionResult? {
        guard let index = toolExecutionResults.firstIndex(where: { $0.id == resultID }) else { return nil }
        guard toolExecutionResults[index].status == .requiresApproval || toolExecutionResults[index].requiresApproval else {
            return toolExecutionResults[index]
        }

        let original = toolExecutionResults[index]

        guard approve else {
            var denied = original
            denied.status = .denied
            denied.requiresApproval = false
            denied.output = "Denied locally. No tool action was run.\n\n\(original.output)"
            denied.createdAt = .now
            toolExecutionResults[index] = denied
            recordToolResolution(denied)
            return denied
        }

        guard var tool = toolConfiguration(for: original) else {
            var unavailable = original
            unavailable.status = .unavailable
            unavailable.requiresApproval = false
            unavailable.output = "Approved locally, but the tool configuration is no longer available. No action was run."
            unavailable.usedNetwork = false
            unavailable.modifiedFiles = false
            unavailable.createdAt = .now
            toolExecutionResults[index] = unavailable
            recordToolResolution(unavailable)
            return unavailable
        }

        if tool.kind.requiresDedicatedRunnerAfterApproval {
            var unavailable = original
            unavailable.status = .unavailable
            unavailable.requiresApproval = false
            unavailable.usedNetwork = false
            unavailable.modifiedFiles = false
            unavailable.createdAt = .now
            unavailable.output = "Approved locally, but \(tool.title) does not have a live execution runner in this build. No changes were made."
            toolExecutionResults[index] = unavailable
            recordToolResolution(unavailable)
            return unavailable
        }

        tool.permissionPolicy = .alwaysAllow
        var approved = LocalToolExecutionService().run(
            toolExecutionContext(for: tool, query: original.query)
        )
        approved.id = original.id
        approved.createdAt = .now
        approved.requiresApproval = false
        if approved.status == .completed {
            approved.output = "Approved locally and executed.\n\n\(approved.output)"
        } else {
            approved.output = "Approved locally, then resolved to \(approved.status.rawValue).\n\n\(approved.output)"
        }
        toolExecutionResults[index] = approved
        recordToolResolution(approved)
        return approved
    }

    @discardableResult
    func resolveToolApproval(
        _ resultID: UUID,
        approve: Bool,
        webPageCaptureService: WebPageCaptureService,
        webSearchService: WebSearchService = WebSearchService(),
        gitHubToolService: GitHubToolService = GitHubToolService(),
        notionToolService: NotionToolService = NotionToolService(),
        youTubeToolService: YouTubeToolService = YouTubeToolService(),
        xToolService: XToolService = XToolService(),
        browserAutomationService: BrowserAutomationService = BrowserAutomationService(),
        secretReader: @escaping ToolSecretReader = WorkspaceStore.defaultToolSecretReader
    ) async -> LocalToolExecutionResult? {
        guard let index = toolExecutionResults.firstIndex(where: { $0.id == resultID }) else { return nil }
        guard toolExecutionResults[index].status == .requiresApproval || toolExecutionResults[index].requiresApproval else {
            return toolExecutionResults[index]
        }

        let original = toolExecutionResults[index]

        guard approve else {
            return resolveToolApproval(resultID, approve: false)
        }

        guard var tool = toolConfiguration(for: original) else {
            var unavailable = original
            unavailable.status = .unavailable
            unavailable.requiresApproval = false
            unavailable.output = "Approved locally, but the tool configuration is no longer available. No action was run."
            unavailable.usedNetwork = false
            unavailable.modifiedFiles = false
            unavailable.createdAt = .now
            toolExecutionResults[index] = unavailable
            recordToolResolution(unavailable)
            return unavailable
        }

        if tool.kind.requiresDedicatedRunnerAfterApproval {
            var unavailable = original
            unavailable.status = .unavailable
            unavailable.requiresApproval = false
            unavailable.usedNetwork = false
            unavailable.modifiedFiles = false
            unavailable.createdAt = .now
            unavailable.output = "Approved locally, but \(tool.title) does not have a live execution runner in this build. No changes were made."
            toolExecutionResults[index] = unavailable
            recordToolResolution(unavailable)
            return unavailable
        }

        tool.permissionPolicy = .alwaysAllow
        var approved = await executeTool(
            tool,
            query: original.query,
            webPageCaptureService: webPageCaptureService,
            webSearchService: webSearchService,
            gitHubToolService: gitHubToolService,
            notionToolService: notionToolService,
            youTubeToolService: youTubeToolService,
            xToolService: xToolService,
            browserAutomationService: browserAutomationService,
            secretReader: secretReader
        )
        approved.id = original.id
        approved.createdAt = .now
        approved.requiresApproval = false
        if approved.status == .completed {
            approved.output = "Approved locally and executed.\n\n\(approved.output)"
        } else {
            approved.output = "Approved locally, then resolved to \(approved.status.rawValue).\n\n\(approved.output)"
        }
        toolExecutionResults[index] = approved
        recordToolResolution(approved)
        return approved
    }

    @discardableResult
    func runTool(_ toolKind: AIToolKind, query rawQuery: String = "") -> LocalToolExecutionResult {
        if let tool = toolConfigurations.first(where: { $0.kind == toolKind }),
           let result = runTool(tool.id, query: rawQuery) {
            return result
        }

        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = LocalToolExecutionResult(
            toolKind: toolKind,
            title: toolKind.rawValue,
            query: query,
            status: .unavailable,
            output: "\(toolKind.rawValue) is not configured in this workspace.",
            usedNetwork: false,
            modifiedFiles: false
        )
        toolExecutionResults.insert(result, at: 0)
        recordLocalAction(
            kind: .runTool,
            title: result.title,
            detail: result.output,
            status: result.localActionStatus,
            destination: .tools
        )
        return result
    }

    @discardableResult
    func runTool(
        _ toolKind: AIToolKind,
        query rawQuery: String = "",
        webPageCaptureService: WebPageCaptureService,
        webSearchService: WebSearchService = WebSearchService(),
        gitHubToolService: GitHubToolService = GitHubToolService(),
        notionToolService: NotionToolService = NotionToolService(),
        youTubeToolService: YouTubeToolService = YouTubeToolService(),
        xToolService: XToolService = XToolService(),
        browserAutomationService: BrowserAutomationService = BrowserAutomationService(),
        secretReader: @escaping ToolSecretReader = WorkspaceStore.defaultToolSecretReader
    ) async -> LocalToolExecutionResult {
        if let tool = toolConfigurations.first(where: { $0.kind == toolKind }),
           let result = await runTool(
                tool.id,
                query: rawQuery,
                webPageCaptureService: webPageCaptureService,
                webSearchService: webSearchService,
                gitHubToolService: gitHubToolService,
                notionToolService: notionToolService,
                youTubeToolService: youTubeToolService,
                xToolService: xToolService,
                browserAutomationService: browserAutomationService,
                secretReader: secretReader
           ) {
            return result
        }

        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = LocalToolExecutionResult(
            toolKind: toolKind,
            title: toolKind.rawValue,
            query: query,
            status: .unavailable,
            output: "\(toolKind.rawValue) is not configured in this workspace.",
            usedNetwork: false,
            modifiedFiles: false
        )
        recordToolExecutionResult(result)
        return result
    }

    func updateAccountStatus(
        _ accountID: UUID,
        connectionStatus: IntegrationConnectionStatus? = nil,
        syncStatus: WorkspaceSyncStatus? = nil,
        pendingImportCount: Int? = nil,
        lastErrorMessage: String? = nil
    ) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        if let connectionStatus {
            accounts[index].connectionStatus = connectionStatus
        }
        if let syncStatus {
            accounts[index].syncStatus = syncStatus
        }
        if let pendingImportCount {
            accounts[index].pendingImportCount = max(0, pendingImportCount)
        }
        if let lastErrorMessage {
            accounts[index].lastSyncErrorMessage = lastErrorMessage
        }
        accounts[index].lastSyncedAt = .now
    }

    @discardableResult
    func validateProviderSetup(_ providerID: UUID) -> ProviderSetupReport? {
        guard let index = providerConfigurations.firstIndex(where: { $0.id == providerID }) else { return nil }

        let report = ProviderSetupService.shared.report(
            for: providerConfigurations[index],
            preferences: preferences
        )

        if let normalizedEndpoint = report.normalizedEndpoint {
            providerConfigurations[index].endpoint = normalizedEndpoint
        }
        providerConfigurations[index].modelIdentifier = report.normalizedModelIdentifier
        providerConfigurations[index].lastValidatedAt = .now

        if let blockingIssue = report.diagnostics.first(where: \.isBlocking) {
            providerConfigurations[index].connectionStatus = .needsAttention
            providerConfigurations[index].lastErrorMessage = blockingIssue.message
        } else if report.routingEligibility == .eligible {
            providerConfigurations[index].connectionStatus = .ready
            providerConfigurations[index].lastErrorMessage = nil
        } else if let routingIssue = report.diagnostics.first {
            providerConfigurations[index].connectionStatus = .needsAttention
            providerConfigurations[index].lastErrorMessage = routingIssue.message
        }

        return report
    }

    @discardableResult
    func applyProviderReadinessValidation(
        _ validation: ProviderReadinessValidation,
        providerID: UUID
    ) -> ProviderConfiguration? {
        guard let index = providerConfigurations.firstIndex(where: { $0.id == providerID }) else { return nil }

        if let normalizedEndpoint = validation.report.normalizedEndpoint {
            providerConfigurations[index].endpoint = normalizedEndpoint
        }
        providerConfigurations[index].modelIdentifier = validation.selectedModelIdentifier
        providerConfigurations[index].connectionStatus = validation.connectionStatus
        providerConfigurations[index].lastValidatedAt = validation.checkedAt
        providerConfigurations[index].lastErrorMessage = validation.errorMessage

        if !validation.availableModels.isEmpty {
            providerConfigurations[index].availableModels = Array(
                Set(providerConfigurations[index].availableModels + validation.availableModels)
            )
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        return providerConfigurations[index]
    }

    @discardableResult
    func applyProviderReadinessValidations(
        _ validations: [(providerID: UUID, validation: ProviderReadinessValidation)]
    ) -> ProviderReadinessBatchSummary {
        var checkedCount = 0
        var readyCount = 0
        var needsAttentionCount = 0

        for item in validations {
            guard applyProviderReadinessValidation(item.validation, providerID: item.providerID) != nil else {
                continue
            }

            checkedCount += 1
            if item.validation.isReady {
                readyCount += 1
            } else {
                needsAttentionCount += 1
            }
        }

        return ProviderReadinessBatchSummary(
            checkedCount: checkedCount,
            readyCount: readyCount,
            needsAttentionCount: needsAttentionCount
        )
    }

    @discardableResult
    func saveProviderAPIKey(_ providerID: UUID, secret rawSecret: String) throws -> ProviderSetupReport? {
        guard let index = providerConfigurations.firstIndex(where: { $0.id == providerID }) else { return nil }

        let secret = rawSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let setupService = ProviderSetupService.shared
        guard !secret.isEmpty,
              let reference = setupService.canonicalSecretReference(for: providerConfigurations[index]) else {
            return validateProviderSetup(providerID)
        }

        let savedReference = try KeychainSecretStore().save(
            secret,
            account: reference.account,
            service: reference.service
        )
        providerConfigurations[index].secretReference = savedReference.rawValue
        providerConfigurations[index].lastErrorMessage = nil
        return validateProviderSetup(providerID)
    }

    @discardableResult
    func deleteProviderAPIKey(_ providerID: UUID) throws -> ProviderAPIKeyDeletionResult? {
        guard let index = providerConfigurations.firstIndex(where: { $0.id == providerID }) else { return nil }

        let setupService = ProviderSetupService.shared
        let reference = setupService.parseSecretReference(providerConfigurations[index].secretReference)
        let canonicalReference = setupService.canonicalSecretReference(for: providerConfigurations[index])
        let sharedRouteCount = reference.map { reference in
            providerConfigurations.enumerated().filter { offset, provider in
                offset != index && setupService.parseSecretReference(provider.secretReference) == reference
            }.count
        } ?? 0
        var keychainSecretDeleted = false
        var retentionReason: ProviderAPIKeyRetentionReason?

        if let reference,
           reference.service == KeychainSecretStore.defaultService,
           reference == canonicalReference,
           sharedRouteCount == 0 {
            try KeychainSecretStore().delete(reference)
            keychainSecretDeleted = true
        } else if reference == nil {
            retentionReason = .missingReference
        } else if reference != canonicalReference || reference?.service != KeychainSecretStore.defaultService {
            retentionReason = .noncanonicalReference
        } else if sharedRouteCount > 0 {
            retentionReason = .sharedReference(routeCount: sharedRouteCount)
        }

        providerConfigurations[index].secretReference = nil
        providerConfigurations[index].connectionStatus = .disconnected
        providerConfigurations[index].lastErrorMessage = nil
        guard let report = validateProviderSetup(providerID) else { return nil }
        return ProviderAPIKeyDeletionResult(
            report: report,
            keychainSecretDeleted: keychainSecretDeleted,
            clearedReference: reference,
            retentionReason: retentionReason
        )
    }

    @discardableResult
    func saveToolAPIKey(_ toolID: UUID, secret rawSecret: String) throws -> ToolConfiguration? {
        guard let index = toolConfigurations.firstIndex(where: { $0.id == toolID }) else { return nil }

        let secret = rawSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            return toolConfigurations[index]
        }

        let reference = canonicalToolSecretReference(for: toolConfigurations[index])
        let savedReference = try KeychainSecretStore().save(
            secret,
            account: reference.account,
            service: reference.service
        )
        toolConfigurations[index].secretReference = savedReference.rawValue
        return toolConfigurations[index]
    }

    var currentProject: WorkspaceProject? {
        projects.first(where: { $0.id == selectedProjectID })
    }

    func project(for thread: AssistantThread?) -> WorkspaceProject? {
        if let projectID = thread?.pinnedProjectID,
           let project = projects.first(where: { $0.id == projectID }) {
            return project
        }

        return currentProject
    }

    func projectAIProfile(for thread: AssistantThread? = nil) -> WorkspaceAIProfile? {
        project(for: thread)?.aiProfile
    }

    var currentDraft: DraftDocument? {
        drafts.first(where: { $0.id == selectedDraftID })
    }

    var currentLibraryAsset: LibraryAsset? {
        libraryAssets.first(where: { $0.id == selectedAssetID })
    }

    var currentCalendarEntry: PublishingCalendarEntry? {
        calendarEntries.first(where: { $0.id == selectedCalendarEntryID })
    }

    var currentAssistantThread: AssistantThread? {
        assistantThreads.first(where: { $0.id == selectedAssistantThreadID })
    }

    var activeAssistantThreads: [AssistantThread] {
        assistantThreads.filter { !archivedAssistantThreadIDs.contains($0.id) }
    }

    var archivedAssistantThreads: [AssistantThread] {
        assistantThreads.filter { archivedAssistantThreadIDs.contains($0.id) }
    }

    var globalChatSearchResults: [AssistantChatSearchResult] {
        searchChats(searchText)
    }

    var activeProvider: ProviderConfiguration? {
        chatProviderFallbackChain(for: currentAssistantThread).first
    }

    var runnableChatProviders: [ProviderConfiguration] {
        runnableChatProviders(for: currentAssistantThread)
    }

    func runnableChatProviders(for thread: AssistantThread?) -> [ProviderConfiguration] {
        let profile = projectAIProfile(for: thread)
        return providerConfigurations.filter { provider in
            isProviderRunnableForChat(provider)
                && projectProfileAllows(provider, profile: profile)
        }
    }

    func chatProviderFallbackChain(
        for thread: AssistantThread? = nil,
        excluding excludedProviderIDs: Set<UUID> = []
    ) -> [ProviderConfiguration] {
        let profile = projectAIProfile(for: thread)
        let enabledProviders = runnableChatProviders(for: thread).filter { provider in
            !excludedProviderIDs.contains(provider.id)
        }
        guard !enabledProviders.isEmpty else { return [] }

        return orderedChatProviders(
            for: preferences.providerRoutingPolicy,
            from: enabledProviders,
            profile: profile
        )
    }

    private func preferredProvider(for template: ChatTemplate) -> ProviderConfiguration? {
        preferredProvider(
            kind: template.preferredProviderKind,
            accessMode: template.preferredAccessMode,
            modelIdentifier: template.preferredModelIdentifier
        )
    }

    private func preferredProvider(for chain: PromptChain) -> ProviderConfiguration? {
        preferredProvider(
            kind: chain.preferredProviderKind,
            accessMode: chain.preferredAccessMode,
            modelIdentifier: chain.preferredModelIdentifier
        )
    }

    private func preferredProvider(
        kind: LLMProviderKind?,
        accessMode: ProviderAccessMode?,
        modelIdentifier: String?
    ) -> ProviderConfiguration? {
        let candidates = runnableChatProviders.filter { provider in
            if let kind,
               provider.kind != kind {
                return false
            }
            if let accessMode,
               provider.accessMode != accessMode {
                return false
            }
            return true
        }

        let requestedModel = modelIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let requestedModel,
           !requestedModel.isEmpty,
           let modelMatch = candidates.first(where: { provider in
               provider.modelIdentifier == requestedModel
                   || provider.availableModels.contains(requestedModel)
                   || provider.discoveredModelNames.contains(requestedModel)
           }) {
            return modelMatch
        }

        return candidates.first
    }

    private func selectedProviderRoute(
        from enabledProviders: [ProviderConfiguration],
        profile: WorkspaceAIProfile?
    ) -> ProviderConfiguration? {
        if let preferredID = profile?.preferredProviderID,
           let provider = enabledProviders.first(where: { $0.id == preferredID }) {
            return provider
        }

        if let preferredID = preferences.preferredProviderID,
           let provider = enabledProviders.first(where: { $0.id == preferredID }) {
            return provider
        }

        if let defaultPresetRoute = defaultModelPresetRoute(from: enabledProviders, profile: profile) {
            return defaultPresetRoute
        }

        return enabledProviders.first(where: \.isLocalPreferred) ?? enabledProviders.first
    }

    private func defaultModelPresetRoute(
        from enabledProviders: [ProviderConfiguration],
        profile: WorkspaceAIProfile?
    ) -> ProviderConfiguration? {
        guard let preset = modelPreset(for: profile) else { return nil }
        let candidates = enabledProviders.filter {
            $0.kind == preset.providerKind && $0.accessMode == preset.accessMode
        }
        guard !candidates.isEmpty else { return nil }

        let modelIdentifier = preset.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelIdentifier.isEmpty else { return candidates.first }

        return candidates.first {
            $0.modelIdentifier == modelIdentifier
                || $0.availableModels.contains(modelIdentifier)
                || $0.discoveredModelNames.contains(modelIdentifier)
        } ?? candidates.first
    }

    private func orderedChatProviders(
        for policy: ProviderRoutingPolicy,
        from enabledProviders: [ProviderConfiguration],
        profile: WorkspaceAIProfile?
    ) -> [ProviderConfiguration] {
        switch policy {
        case .selectedProvider:
            guard let selectedProvider = selectedProviderRoute(from: enabledProviders, profile: profile) else {
                return enabledProviders.sorted(by: localFirstRouteSort)
            }
            let fallbackProviders = enabledProviders
                .filter { $0.id != selectedProvider.id }
                .sorted(by: localFirstRouteSort)
            return [selectedProvider] + fallbackProviders
        case .localFirst:
            return enabledProviders.sorted(by: localFirstRouteSort)
        case .bestAvailable:
            return enabledProviders.sorted(by: bestAvailableRouteSort)
        case .cheapest:
            return enabledProviders.sorted(by: cheapestRouteSort)
        case .fastest:
            return enabledProviders.sorted(by: fastestRouteSort)
        }
    }

    private func projectProfileAllows(_ provider: ProviderConfiguration, profile: WorkspaceAIProfile?) -> Bool {
        guard let profile else { return true }
        return profile.cloudAccessPolicy.allows(provider)
    }

    var preferredProviderConfiguration: ProviderConfiguration? {
        guard let preferredID = preferences.preferredProviderID else { return nil }
        return providerConfigurations.first(where: { $0.id == preferredID })
    }

    var defaultModelPreset: ModelPreset? {
        if let defaultPresetID = preferences.defaultModelPresetID,
           let preset = modelPresets.first(where: { $0.id == defaultPresetID }) {
            return preset
        }

        return modelPresets.first(where: \.isDefault)
    }

    private func modelPreset(for profile: WorkspaceAIProfile?) -> ModelPreset? {
        if let presetID = profile?.defaultModelPresetID,
           let preset = modelPresets.first(where: { $0.id == presetID }) {
            return preset
        }

        return defaultModelPreset
    }

    func matchingProviders(for preset: ModelPreset) -> [ProviderConfiguration] {
        providerConfigurations.filter {
            $0.kind == preset.providerKind && $0.accessMode == preset.accessMode
        }
    }

    func providerRoutesCompatibleWithModelPreset(_ presetID: UUID) -> [ProviderConfiguration] {
        guard let preset = modelPresets.first(where: { $0.id == presetID }) else {
            return []
        }
        return matchingProviders(for: preset)
    }

    @discardableResult
    func setDefaultModelPreset(_ presetID: UUID?) -> Bool {
        if let presetID,
           !modelPresets.contains(where: { $0.id == presetID }) {
            return false
        }

        preferences.defaultModelPresetID = presetID
        for index in modelPresets.indices {
            modelPresets[index].isDefault = modelPresets[index].id == presetID
        }
        return true
    }

    @discardableResult
    func applyModelPreset(
        _ presetID: UUID,
        providerID: UUID? = nil,
        makeDefault: Bool = true,
        selectForChat: Bool = true
    ) -> Bool {
        guard let preset = modelPresets.first(where: { $0.id == presetID }) else {
            return false
        }

        let providerIndex: Int?
        if let providerID {
            providerIndex = providerConfigurations.firstIndex {
                $0.id == providerID
                    && $0.kind == preset.providerKind
                    && $0.accessMode == preset.accessMode
            }
        } else {
            providerIndex = providerConfigurations.firstIndex {
                $0.kind == preset.providerKind && $0.accessMode == preset.accessMode
            }
        }

        guard let providerIndex,
              canApplyPrivacyScope(preset.privacyScope, to: providerConfigurations[providerIndex]) else {
            return false
        }

        let originalProvider = providerConfigurations[providerIndex]
        var updatedProvider = originalProvider
        let modelIdentifier = preset.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortedCapabilities = Self.sortedUniqueCapabilities(preset.capabilities)

        updatedProvider.modelIdentifier = modelIdentifier
        updatedProvider.temperature = preset.temperature
        updatedProvider.privacyScope = preset.privacyScope
        updatedProvider.contextWindowTokens = preset.contextWindowTokens
        updatedProvider.capabilities = sortedCapabilities
        updatedProvider.supportsEmbeddings = sortedCapabilities.contains(.embeddings)
        updatedProvider.supportsToolCalling = sortedCapabilities.contains(.toolCalling)
        updatedProvider.supportsStreaming = sortedCapabilities.contains(.streaming)
        updatedProvider.supportsStructuredOutput = sortedCapabilities.contains(.structuredOutput)
        updatedProvider.supportsVision = sortedCapabilities.contains(.vision)
        updatedProvider.isEnabled = true

        if !modelIdentifier.isEmpty {
            updatedProvider.availableModels = Self.sortedUniqueModelNames(
                updatedProvider.availableModels + [modelIdentifier]
            )
        }

        let setupReport = ProviderSetupService.shared.report(
            for: updatedProvider,
            preferences: preferences
        )
        if let normalizedEndpoint = setupReport.normalizedEndpoint {
            updatedProvider.endpoint = normalizedEndpoint
        }
        updatedProvider.modelIdentifier = setupReport.normalizedModelIdentifier

        let needsReadinessCheck = modelPresetApplicationNeedsReadinessCheck(
            original: originalProvider,
            updated: updatedProvider
        )
        if let blockingIssue = setupReport.diagnostics.first(where: \.isBlocking) {
            updatedProvider.connectionStatus = .needsAttention
            updatedProvider.lastValidatedAt = nil
            updatedProvider.lastErrorMessage = blockingIssue.message
        } else if setupReport.routingEligibility != .eligible,
                  let routingIssue = setupReport.diagnostics.first {
            updatedProvider.connectionStatus = .needsAttention
            updatedProvider.lastValidatedAt = nil
            updatedProvider.lastErrorMessage = routingIssue.message
        } else if needsReadinessCheck {
            updatedProvider.connectionStatus = .needsAttention
            updatedProvider.lastValidatedAt = nil
            updatedProvider.lastErrorMessage = "Run provider readiness after applying this model preset."
        } else if updatedProvider.runtimePolicy.readinessStrategy == .staticConfiguration {
            updatedProvider.connectionStatus = .ready
            updatedProvider.lastValidatedAt = .now
            updatedProvider.lastErrorMessage = nil
        }

        providerConfigurations[providerIndex] = updatedProvider

        if makeDefault {
            _ = setDefaultModelPreset(preset.id)
        }
        if selectForChat {
            preferences.preferredProviderID = updatedProvider.id
            preferences.providerRoutingPolicy = .selectedProvider
        }

        return isProviderRunnableForChat(updatedProvider)
    }

    @discardableResult
    func selectPreferredProviderForChat(_ providerID: UUID) -> Bool {
        guard let index = providerConfigurations.firstIndex(where: { $0.id == providerID }) else {
            return false
        }

        providerConfigurations[index].isEnabled = true
        preferences.preferredProviderID = providerID
        preferences.providerRoutingPolicy = .selectedProvider
        return isProviderRunnableForChat(providerConfigurations[index])
    }

    @discardableResult
    func selectPreferredProviderModelForChat(
        providerID: UUID,
        modelIdentifier rawModelIdentifier: String
    ) -> Bool {
        guard let index = providerConfigurations.firstIndex(where: { $0.id == providerID }) else {
            return false
        }

        let modelIdentifier = rawModelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelIdentifier.isEmpty else { return false }

        providerConfigurations[index].modelIdentifier = modelIdentifier
        providerConfigurations[index].availableModels = Self.sortedUniqueModelNames(
            providerConfigurations[index].availableModels + [modelIdentifier]
        )
        let discoveredLocalModels = discoveredModelsForLocalProvider(
            kind: providerConfigurations[index].kind,
            endpoint: providerConfigurations[index].endpoint
        )
        if let localModel = Self.localModelDescriptor(
            named: modelIdentifier,
            in: discoveredLocalModels
        ) {
            applySelectedLocalModelRuntime(
                localModel,
                allDiscoveredModels: discoveredLocalModels,
                toProviderAt: index,
                preserveExistingContextWhenMissing: false
            )
        }
        providerConfigurations[index].isEnabled = true
        preferences.preferredProviderID = providerID
        preferences.providerRoutingPolicy = .selectedProvider
        return isProviderRunnableForChat(providerConfigurations[index])
    }

    var runnableComparisonProviders: [ProviderConfiguration] {
        let profile = projectAIProfile(for: currentAssistantThread)
        return providerConfigurations
            .filter {
                isProviderRunnableForChat($0)
                    && projectProfileAllows($0, profile: profile)
            }
            .sorted { lhs, rhs in
                if let preferredProjectProviderID = profile?.preferredProviderID {
                    if lhs.id == preferredProjectProviderID { return true }
                    if rhs.id == preferredProjectProviderID { return false }
                }
                if lhs.id == preferences.preferredProviderID { return true }
                if rhs.id == preferences.preferredProviderID { return false }
                if lhs.isLocalPreferred != rhs.isLocalPreferred {
                    return lhs.isLocalPreferred && !rhs.isLocalPreferred
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    func defaultComparisonProviderIDs(limit: Int = 3) -> [UUID] {
        Array(runnableComparisonProviders.prefix(max(0, limit)).map(\.id))
    }

    func defaultSystemPrompt(now: Date = .now) -> String? {
        defaultSystemPrompt(for: currentAssistantThread, now: now)
    }

    func defaultSystemPrompt(for thread: AssistantThread?, now: Date = .now) -> String? {
        if let projectPrompt = projectSystemPrompt(for: thread, now: now) {
            return projectPrompt
        }

        let profile = promptProfiles.first { $0.id == preferences.defaultSystemPromptProfileID }
            ?? promptProfiles.first(where: \.isDefault)
        guard let profile else { return nil }

        let rendered = renderPromptProfile(profile, for: thread, now: now)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rendered.isEmpty ? nil : rendered
    }

    func effectiveSystemPrompt(for thread: AssistantThread? = nil, now: Date = .now) -> String? {
        let targetThread = thread ?? currentAssistantThread
        if let threadPrompt = targetThread?.messages.first(where: { $0.role == .system })?.text,
           !threadPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let rendered = renderPromptTemplate(
                threadPrompt,
                now: now,
                thread: targetThread,
                knowledgeSourceIDs: threadKnowledgeSourceIDsForPrompt(targetThread)
            )
            let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return defaultSystemPrompt(for: targetThread, now: now)
    }

    func renderPromptProfile(_ profile: SystemPromptProfile, now: Date = .now) -> String {
        renderPromptProfile(profile, for: currentAssistantThread, now: now)
    }

    func renderPromptProfile(
        _ profile: SystemPromptProfile,
        for thread: AssistantThread?,
        now: Date = .now
    ) -> String {
        renderPromptTemplate(
            profile.prompt,
            now: now,
            thread: thread,
            knowledgeSourceIDs: threadKnowledgeSourceIDsForPrompt(thread)
        )
    }

    func renderPromptTemplate(_ template: String, now: Date = .now) -> String {
        renderPromptTemplate(template, now: now, thread: currentAssistantThread, knowledgeSourceIDs: nil)
    }

    private func renderPromptTemplate(
        _ template: String,
        now: Date = .now,
        thread: AssistantThread?,
        knowledgeSourceIDs: [UUID]?
    ) -> String {
        guard !template.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"\{\{\s*([A-Za-z0-9_]+)\s*\}\}"#) else {
            return template
        }

        let variables = promptVariableValues(now: now, thread: thread, knowledgeSourceIDs: knowledgeSourceIDs)
        let source = template as NSString
        let matches = regex.matches(
            in: template,
            range: NSRange(location: 0, length: source.length)
        )
        var rendered = template
        for match in matches.reversed() {
            guard match.numberOfRanges == 2 else { continue }
            let key = source.substring(with: match.range(at: 1)).lowercased()
            guard let value = variables[key],
                  let replacementRange = Range(match.range(at: 0), in: rendered) else {
                continue
            }
            rendered.replaceSubrange(replacementRange, with: value)
        }
        return rendered
    }

    private func projectSystemPrompt(for thread: AssistantThread?, now: Date) -> String? {
        guard let profile = projectAIProfile(for: thread) else { return nil }
        let knowledgeSourceIDs = threadKnowledgeSourceIDsForPrompt(thread)

        let customPrompt = profile.customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customPrompt.isEmpty {
            let rendered = renderPromptTemplate(
                customPrompt,
                now: now,
                thread: thread,
                knowledgeSourceIDs: knowledgeSourceIDs
            )
            let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        guard let profileID = profile.defaultSystemPromptProfileID,
              let promptProfile = promptProfiles.first(where: { $0.id == profileID }) else {
            return nil
        }

        let rendered = renderPromptTemplate(
            promptProfile.prompt,
            now: now,
            thread: thread,
            knowledgeSourceIDs: knowledgeSourceIDs
        )
        let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func threadKnowledgeSourceIDsForPrompt(_ thread: AssistantThread?) -> [UUID]? {
        if let thread,
           !thread.knowledgeSourceIDs.isEmpty {
            return thread.knowledgeSourceIDs
        }

        guard let profile = projectAIProfile(for: thread),
              profile.hasScopedKnowledge else {
            return thread?.knowledgeSourceIDs
        }

        return profile.knowledgeSourceIDs
    }

    func promptVariableValues(now: Date = .now) -> [String: String] {
        promptVariableValues(now: now, thread: currentAssistantThread, knowledgeSourceIDs: nil)
    }

    private func promptVariableValues(
        now: Date = .now,
        thread: AssistantThread?,
        knowledgeSourceIDs: [UUID]?
    ) -> [String: String] {
        let provider = activeProvider
        let thread = thread ?? currentAssistantThread
        let project = currentProject
        let scopedIDs = knowledgeSourceIDs ?? thread?.knowledgeSourceIDs
        let sourceScope = scopedIDs?.isEmpty == false ? Set(scopedIDs ?? []) : nil
        let scopedKnowledgeSources = knowledgeSourcesForScope(sourceScope)
        let knowledgeTitles = scopedKnowledgeSources
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .prefix(5)
            .map(\.title)
            .joined(separator: ", ")
        let threadTags = thread?.tagNames.joined(separator: ", ") ?? ""

        return [
            "date": Self.isoDateString(now),
            "datetime": Self.isoDateTimeString(now),
            "provider": provider?.displayName ?? "Local fallback",
            "model": provider?.modelIdentifier ?? "none",
            "provider_mode": provider?.accessMode.title ?? "Local fallback",
            "privacy": provider?.privacyScope.title ?? "Local Only",
            "routing_policy": preferences.providerRoutingPolicy.title,
            "local_only": (preferences.localOnlyMode ?? true) ? "enabled" : "disabled",
            "thread_title": thread?.title ?? "New Chat",
            "thread_tags": threadTags.isEmpty ? "none" : threadTags,
            "project": project?.title ?? "No project selected",
            "knowledge_source_count": "\(scopedKnowledgeSources.count)",
            "knowledge_sources": knowledgeTitles.isEmpty ? "none" : knowledgeTitles
        ]
    }

    private static func isoDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func isoDateTimeString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: date)
    }

    private func localFirstRouteSort(_ lhs: ProviderConfiguration, _ rhs: ProviderConfiguration) -> Bool {
        let lhsPrivacyRank = privacyRouteRank(lhs)
        let rhsPrivacyRank = privacyRouteRank(rhs)
        if lhsPrivacyRank != rhsPrivacyRank {
            return lhsPrivacyRank < rhsPrivacyRank
        }
        return stableRouteTieBreak(lhs, rhs)
    }

    private func bestAvailableRouteSort(_ lhs: ProviderConfiguration, _ rhs: ProviderConfiguration) -> Bool {
        let lhsScore = bestAvailableScore(lhs)
        let rhsScore = bestAvailableScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        return stableRouteTieBreak(lhs, rhs)
    }

    private func cheapestRouteSort(_ lhs: ProviderConfiguration, _ rhs: ProviderConfiguration) -> Bool {
        let lhsCost = marginalCostPerMillionTokens(lhs)
        let rhsCost = marginalCostPerMillionTokens(rhs)
        if lhsCost != rhsCost {
            return lhsCost < rhsCost
        }
        return stableRouteTieBreak(lhs, rhs)
    }

    private func fastestRouteSort(_ lhs: ProviderConfiguration, _ rhs: ProviderConfiguration) -> Bool {
        let lhsLatency = latencyScore(lhs)
        let rhsLatency = latencyScore(rhs)
        if lhsLatency != rhsLatency {
            return lhsLatency < rhsLatency
        }
        return stableRouteTieBreak(lhs, rhs)
    }

    private func stableRouteTieBreak(_ lhs: ProviderConfiguration, _ rhs: ProviderConfiguration) -> Bool {
        if lhs.id == preferences.preferredProviderID { return true }
        if rhs.id == preferences.preferredProviderID { return false }
        if lhs.isLocalPreferred != rhs.isLocalPreferred {
            return lhs.isLocalPreferred && !rhs.isLocalPreferred
        }
        let lhsPrivacyRank = privacyRouteRank(lhs)
        let rhsPrivacyRank = privacyRouteRank(rhs)
        if lhsPrivacyRank != rhsPrivacyRank {
            return lhsPrivacyRank < rhsPrivacyRank
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func privacyRouteRank(_ provider: ProviderConfiguration) -> Int {
        switch provider.privacyScope {
        case .localOnly:
            0
        case .localCLI:
            1
        case .bridgeService:
            2
        case .externalAPI:
            3
        }
    }

    private func marginalCostPerMillionTokens(_ provider: ProviderConfiguration) -> Double {
        ProviderCostEstimator.shared.marginalCostPerMillionTokens(provider)
    }

    private func bestAvailableScore(_ provider: ProviderConfiguration) -> Double {
        var score = 0.0
        if provider.id == preferences.preferredProviderID { score += 2 }
        if provider.isLocalPreferred { score += 4 }

        switch provider.kind {
        case .openAI, .anthropic:
            score += 32
        case .gemini, .xAI:
            score += 26
        case .openRouter, .mistral:
            score += 18
        case .lmStudio:
            score += 16
        case .ollama:
            score += 14
        case .groq:
            score += 12
        case .perplexity:
            score += 10
        case .customOpenAICompatible, .chatGPTCLI, .claudeCodeCLI, .vercelAISDKBridge:
            score += 8
        }

        if provider.capabilities.contains(.reasoning) { score += 24 }
        if provider.capabilities.contains(.toolCalling) { score += 14 }
        if provider.capabilities.contains(.vision) { score += 12 }
        if provider.capabilities.contains(.structuredOutput) { score += 10 }
        if provider.capabilities.contains(.webSearch) { score += 8 }
        if provider.capabilities.contains(.embeddings) { score += 4 }

        if let contextWindowTokens = provider.contextWindowTokens,
           contextWindowTokens > 0 {
            score += min(18, log2(Double(contextWindowTokens)))
        }

        switch provider.privacyScope {
        case .localOnly:
            score += 8
        case .localCLI:
            score += 5
        case .bridgeService:
            score += 3
        case .externalAPI:
            score += 1
        }

        return score
    }

    private func latencyScore(_ provider: ProviderConfiguration) -> Double {
        if let recentLatency = recentComparisonLatencyMilliseconds(for: provider.id) {
            return Double(recentLatency)
        }

        switch provider.accessMode {
        case .localServer:
            return provider.isLocalPreferred ? 250 : 350
        case .subscriptionCLI:
            return 650
        case .openAICompatible, .anthropicCompatible:
            return provider.privacyScope == .localOnly ? 420 : 900
        case .aiSDKBridge:
            return 750
        case .apiKey:
            switch provider.kind {
            case .groq:
                return 450
            case .perplexity:
                return 850
            case .mistral:
                return 950
            default:
                return 1_100
            }
        }
    }

    private func recentComparisonLatencyMilliseconds(for providerID: UUID) -> Int? {
        modelComparisonRuns
            .sorted { $0.createdAt > $1.createdAt }
            .lazy
            .flatMap(\.results)
            .first { result in
                result.providerID == providerID
                    && result.status == .completed
                    && result.latencyMilliseconds != nil
            }?
            .latencyMilliseconds
    }

    @discardableResult
    func createModelComparisonRun(
        prompt rawPrompt: String,
        providerIDs: [UUID],
        systemPrompt: String? = nil,
        citations: [AIChatCitation] = [],
        now: Date = .now
    ) -> UUID? {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }

        let providersByID = Dictionary(uniqueKeysWithValues: runnableComparisonProviders.map { ($0.id, $0) })
        var seenProviderIDs = Set<UUID>()
        let providerIDsInOrder = providerIDs.compactMap { providerID -> UUID? in
            guard providersByID[providerID] != nil,
                  seenProviderIDs.insert(providerID).inserted else {
                return nil
            }
            return providerID
        }
        guard providerIDsInOrder.count >= 2 else { return nil }

        let results = providerIDsInOrder.compactMap { providerID in
            providersByID[providerID].map {
                ModelComparisonResult(provider: $0)
            }
        }

        let run = ModelComparisonRun(
            prompt: prompt,
            systemPrompt: systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
            providerIDs: providerIDsInOrder,
            results: results,
            citations: citations,
            createdAt: now,
            updatedAt: now
        )
        modelComparisonRuns.insert(run, at: 0)
        if modelComparisonRuns.count > 30 {
            modelComparisonRuns.removeLast(modelComparisonRuns.count - 30)
        }
        return run.id
    }

    func updateModelComparisonResult(
        runID: UUID,
        providerID: UUID,
        status: ModelComparisonStatus,
        text: String? = nil,
        errorMessage: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        inputTokenCount: Int? = nil,
        outputTokenCount: Int? = nil,
        latencyMilliseconds: Int? = nil,
        firstTokenLatencyMilliseconds: Int? = nil,
        tokenCountsAreEstimated: Bool? = nil
    ) {
        guard let runIndex = modelComparisonRuns.firstIndex(where: { $0.id == runID }),
              let resultIndex = modelComparisonRuns[runIndex].results.firstIndex(where: { $0.providerID == providerID }) else {
            return
        }

        let prompt = modelComparisonRuns[runIndex].prompt
        let existing = modelComparisonRuns[runIndex].results[resultIndex]
        let provider = providerConfigurations.first(where: { $0.id == providerID })
        let newText = text ?? existing.text
        let finishedAt = completedAt ?? (status == .completed || status == .failed ? Date() : nil)
        let started = startedAt ?? existing.startedAt
        let inputTokens = inputTokenCount ?? estimatedTokenCount(for: prompt)
        let outputTokens = outputTokenCount ?? estimatedTokenCount(for: newText)
        let tokensAreEstimated = tokenCountsAreEstimated ?? !(inputTokenCount != nil && outputTokenCount != nil)

        modelComparisonRuns[runIndex].results[resultIndex].status = status
        modelComparisonRuns[runIndex].results[resultIndex].text = newText
        modelComparisonRuns[runIndex].results[resultIndex].errorMessage = errorMessage
        modelComparisonRuns[runIndex].results[resultIndex].startedAt = started
        modelComparisonRuns[runIndex].results[resultIndex].completedAt = finishedAt
        modelComparisonRuns[runIndex].results[resultIndex].inputTokenCount = inputTokens
        modelComparisonRuns[runIndex].results[resultIndex].outputTokenCount = outputTokens
        modelComparisonRuns[runIndex].results[resultIndex].tokenCountsAreEstimated = tokensAreEstimated
        if let started,
           let finishedAt {
            modelComparisonRuns[runIndex].results[resultIndex].latencyMilliseconds = latencyMilliseconds
                ?? max(0, Int(finishedAt.timeIntervalSince(started) * 1_000))
        } else if let latencyMilliseconds {
            modelComparisonRuns[runIndex].results[resultIndex].latencyMilliseconds = latencyMilliseconds
        }
        if let firstTokenLatencyMilliseconds {
            modelComparisonRuns[runIndex].results[resultIndex].firstTokenLatencyMilliseconds = firstTokenLatencyMilliseconds
        }
        modelComparisonRuns[runIndex].results[resultIndex].estimatedCostMicros = estimatedCostMicros(
            provider: provider,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
        modelComparisonRuns[runIndex].updatedAt = .now
        if modelComparisonRuns[runIndex].results.allSatisfy({ $0.status == .completed || $0.status == .failed }) {
            modelComparisonRuns[runIndex].completedAt = finishedAt ?? .now
        }
    }

    @discardableResult
    func appendComparisonResultToCurrentChat(
        runID: UUID,
        resultID: UUID,
        now: Date = .now
    ) -> UUID? {
        guard let run = modelComparisonRuns.first(where: { $0.id == runID }),
              let result = run.results.first(where: { $0.id == resultID }) else {
            return nil
        }

        let responseText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !responseText.isEmpty else { return nil }

        var thread = currentAssistantThread ?? AssistantThread(
            title: Self.threadTitle(from: run.prompt),
            mode: .workspaceCopilot,
            createdAt: now,
            updatedAt: now
        )
        thread.pinnedProjectID = selectedProjectID
        thread.pinnedDraftID = selectedDraftID
        thread.pinnedAssetID = selectedAssetID
        thread.pinnedCalendarEntryID = selectedCalendarEntryID

        if thread.messages.isEmpty {
            thread.messages.append(
                AssistantMessage(
                    role: .user,
                    text: run.prompt,
                    createdAt: now,
                    updatedAt: now,
                    referencedEntityIDs: [
                        thread.pinnedProjectID,
                        thread.pinnedDraftID,
                        thread.pinnedAssetID,
                        thread.pinnedCalendarEntryID
                    ].compactMap { $0 },
                    citations: run.citations
                )
            )
        }

        let runStatus: AssistantMessageRunStatus = switch result.status {
        case .completed:
            .completed
        case .failed:
            .failed
        case .queued, .streaming:
            .stopped
        }
        let message = AssistantMessage(
            role: .assistant,
            text: responseText,
            createdAt: result.completedAt ?? now,
            updatedAt: result.completedAt ?? now,
            referencedEntityIDs: [
                thread.pinnedProjectID,
                thread.pinnedDraftID,
                thread.pinnedAssetID,
                thread.pinnedCalendarEntryID
            ].compactMap { $0 },
            citations: run.citations,
            providerDisplayName: result.providerDisplayName,
            modelIdentifier: result.modelIdentifier,
            inputTokenCount: result.inputTokenCount,
            outputTokenCount: result.outputTokenCount,
            latencyMilliseconds: result.latencyMilliseconds,
            firstTokenLatencyMilliseconds: result.firstTokenLatencyMilliseconds,
            estimatedCostMicros: result.estimatedCostMicros,
            providerAccessMode: result.accessMode,
            providerPrivacyScope: result.privacyScope,
            runStatus: runStatus,
            startedAt: result.startedAt,
            completedAt: result.completedAt ?? now,
            tokenCountsAreEstimated: result.tokenCountsAreEstimated
        )
        thread.messages.append(message)
        thread.updatedAt = now
        assistantThreads.upsert(thread, matching: \.id)
        selectedAssistantThreadID = thread.id
        return message.id
    }

    func isProviderAllowedByPreferences(_ provider: ProviderConfiguration) -> Bool {
        guard provider.isEnabled else { return false }
        return ProviderSetupService.shared.isEligibleForActivation(
            provider,
            preferences: preferences
        )
    }

    func isProviderRunnableForChat(_ provider: ProviderConfiguration) -> Bool {
        guard isProviderAllowedByPreferences(provider),
              provider.capabilities.contains(.chat),
              provider.supportsStreaming,
              provider.runtimePolicy.supportsChatTransport else {
            return false
        }

        guard cachedProviderReadinessAllowsChat(provider) else { return false }

        let setupReport = ProviderSetupService.shared.report(
            for: provider,
            preferences: preferences
        )
        guard !setupReport.hasBlockingIssues else { return false }

        if provider.accessMode == .subscriptionCLI {
            let request = ChatStreamingRequest(
                provider: provider,
                messages: [
                    AssistantMessage(role: .user, text: "Provider readiness check")
                ],
                systemPrompt: nil
            )
            return (try? CLIProviderTransport().makePreparedCommand(for: request)) != nil
        }

        return true
    }

    func chatRoutingBlockReason(for provider: ProviderConfiguration) -> String? {
        guard !isProviderRunnableForChat(provider) else { return nil }

        if !provider.isEnabled {
            return "Enable this provider before routing chat to it."
        }

        let setupReport = ProviderSetupService.shared.report(
            for: provider,
            preferences: preferences
        )
        if let blockingDiagnostic = setupReport.diagnostics.first(where: \.isBlocking) {
            return blockingDiagnostic.message
        }
        if let routingDiagnostic = setupReport.diagnostics.first(where: { $0.field == "privacyScope" }) {
            return routingDiagnostic.message
        }

        if !provider.capabilities.contains(.chat) {
            return "Chat capability is disabled for this provider configuration."
        }
        if !provider.supportsStreaming {
            return "Streaming is disabled for this provider configuration."
        }
        if !provider.runtimePolicy.supportsChatTransport {
            return "This provider route is not connected to a Flannel chat streaming transport."
        }

        switch provider.connectionStatus {
        case .needsAttention:
            return provider.lastErrorMessage ?? "This provider needs a successful readiness check before chat routing."
        case .rateLimited:
            return provider.lastErrorMessage ?? "This provider is rate limited; try again after the provider recovers."
        case .syncing:
            return "Provider readiness is still checking. Try routing after the check completes."
        case .ready:
            break
        case .disconnected:
            if provider.runtimePolicy.readinessStrategy != .staticConfiguration {
                return provider.lastErrorMessage ?? "Run provider readiness before routing chat to this provider."
            }
        }

        if provider.accessMode == .subscriptionCLI,
           let cliDiagnostic = ProviderSetupService.shared.subscriptionCLIDiagnostic(for: provider) {
            return cliDiagnostic.message
        }

        return "Run provider readiness again or review this route before using it for chat."
    }

    private func cachedProviderReadinessAllowsChat(_ provider: ProviderConfiguration) -> Bool {
        switch provider.connectionStatus {
        case .ready:
            return true
        case .disconnected:
            return provider.runtimePolicy.readinessStrategy == .staticConfiguration
        case .needsAttention, .rateLimited, .syncing:
            return false
        }
    }

    func localKnowledgeRetrievalPacket(
        for query: String,
        limit: Int = 5,
        knowledgeSourceIDs: Set<UUID>? = nil
    ) -> LocalKnowledgeRetrievalPacket {
        let inputs = localKnowledgeDocumentInputs(
            excludingPrompt: query,
            knowledgeSourceIDs: knowledgeSourceIDs
        )
        guard !inputs.isEmpty else {
            return .empty(query: query)
        }

        do {
            let indexingService = LocalKnowledgeIndexingService()
            let index = try indexingService.buildIndex(for: inputs)
            let vectorGroups = LocalKnowledgeVectorStore().loadRecordGroups(
                from: knowledgeIndexManifests,
                matching: index
            )
            let vectorRecords = vectorGroups
                .filter { $0.modelIdentifier == LocalEmbeddingService.deterministicModelIdentifier }
                .flatMap(\.records)
            return indexingService.retrievalPacket(
                for: query,
                index: index,
                vectorRecords: vectorRecords,
                limit: limit
            )
        } catch {
            return .empty(query: query)
        }
    }

    func localKnowledgeRetrievalPacketUsingConfiguredEmbeddings(
        for query: String,
        limit: Int = 5,
        knowledgeSourceIDs: Set<UUID>? = nil,
        vectorStore: LocalKnowledgeVectorStore = LocalKnowledgeVectorStore()
    ) async -> LocalKnowledgeRetrievalPacket {
        let inputs = localKnowledgeDocumentInputs(
            excludingPrompt: query,
            knowledgeSourceIDs: knowledgeSourceIDs
        )
        guard !inputs.isEmpty else {
            return .empty(query: query)
        }

        do {
            let indexingService = LocalKnowledgeIndexingService()
            let index = try indexingService.buildIndex(for: inputs)
            let vectorGroups = vectorStore.loadRecordGroups(
                from: knowledgeIndexManifests,
                matching: index
            )

            guard !vectorGroups.isEmpty else {
                return indexingService.retrievalPacket(for: query, index: index, limit: limit)
            }

            var resultsByChunkID: [String: LocalKnowledgeSearchResult] = [:]
            for group in vectorGroups {
                let queryVector = try await queryVector(
                    for: query,
                    modelIdentifier: group.modelIdentifier,
                    vectorDimension: group.vectorDimension,
                    embeddingProviderKind: group.embeddingProviderKind,
                    vectorStore: vectorStore
                )
                let groupResults = indexingService.hybridSearch(
                    query,
                    in: index,
                    vectorRecords: group.records,
                    queryVector: queryVector,
                    limit: index.chunkCount
                )

                for result in groupResults {
                    if let existing = resultsByChunkID[result.chunk.id] {
                        if result.score > existing.score {
                            resultsByChunkID[result.chunk.id] = result
                        }
                    } else {
                        resultsByChunkID[result.chunk.id] = result
                    }
                }
            }

            let results = indexingService.rerankResults(
                Array(resultsByChunkID.values),
                for: query,
                limit: limit
            )
            return LocalKnowledgeRetrievalPacket(query: query, results: results)
        } catch {
            return localKnowledgeRetrievalPacket(
                for: query,
                limit: limit,
                knowledgeSourceIDs: knowledgeSourceIDs
            )
        }
    }

    func knowledgeCitationPreviews(for citations: [AIChatCitation]) -> [KnowledgeCitationPreview] {
        citations.map { knowledgeCitationPreview(for: $0) }
    }

    func knowledgeCitationPreview(for citation: AIChatCitation) -> KnowledgeCitationPreview {
        let source = resolvedKnowledgeSource(for: citation)
        let manifest = resolvedKnowledgeManifest(for: citation, source: source)
        return KnowledgeCitationPreview(
            citation: citation,
            source: source,
            manifest: manifest,
            chunkIdentifier: citation.sourceIdentifier
        )
    }

    var hasKnowledgeSourcesNeedingIndexRebuild: Bool {
        knowledgeSources.contains { source in
            source.status == .queued
                || source.status == .stale
                || source.status == .notIndexed
        }
    }

    @discardableResult
    func addKnowledgeSource(
        title rawTitle: String,
        kind: KnowledgeSourceKind,
        location rawLocation: String,
        watched: Bool = true
    ) -> KnowledgeSource? {
        let location = normalizedKnowledgeSourceLocation(rawLocation, kind: kind)
        guard !location.isEmpty else { return nil }

        let providedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = providedTitle.isEmpty
            ? defaultKnowledgeSourceTitle(kind: kind, location: location)
            : providedTitle

        if let existingIndex = knowledgeSources.firstIndex(where: { source in
            source.kind == kind
                && normalizedKnowledgeSourceLocation(source.location, kind: source.kind)
                .localizedCaseInsensitiveCompare(location) == .orderedSame
        }) {
            knowledgeSources[existingIndex].title = resolvedTitle
            knowledgeSources[existingIndex].location = location
            knowledgeSources[existingIndex].status = .queued
            knowledgeSources[existingIndex].isWatched = watched
            knowledgeSources[existingIndex].lastErrorMessage = nil
            if knowledgeSources[existingIndex].embeddingModelIdentifier == nil {
                knowledgeSources[existingIndex].embeddingModelIdentifier = LocalEmbeddingService.deterministicModelIdentifier
            }
            ensureLocalWebPageCaptureIfNeeded(title: resolvedTitle, location: location, kind: kind)
            return knowledgeSources[existingIndex]
        }

        let source = KnowledgeSource(
            title: resolvedTitle,
            kind: kind,
            location: location,
            status: .queued,
            embeddingModelIdentifier: LocalEmbeddingService.deterministicModelIdentifier,
            isWatched: watched
        )

        knowledgeSources.insert(source, at: 0)
        ensureLocalWebPageCaptureIfNeeded(title: resolvedTitle, location: location, kind: kind)
        return source
    }

    func rebuildKnowledgeIndexManifests(
        onlyQueued: Bool = false,
        now: Date = .now
    ) {
        let indexingService = LocalKnowledgeIndexingService()
        var rebuiltSources = knowledgeSources
        var manifestsBySourceID = Dictionary(
            uniqueKeysWithValues: knowledgeIndexManifests.compactMap { manifest in
                manifest.sourceID.map { ($0, manifest) }
            }
        )

        for sourceIndex in rebuiltSources.indices {
            let source = rebuiltSources[sourceIndex]
            if onlyQueued,
               source.status != .queued,
               source.status != .stale,
               source.status != .notIndexed {
                continue
            }

            let inputs = localKnowledgeDocumentInputs(for: source)
            guard !inputs.isEmpty else {
                rebuiltSources[sourceIndex].status = .failed
                rebuiltSources[sourceIndex].documentCount = 0
                rebuiltSources[sourceIndex].chunkCount = 0
                rebuiltSources[sourceIndex].embeddingRecordCount = 0
                rebuiltSources[sourceIndex].vectorDimension = nil
                rebuiltSources[sourceIndex].lastErrorMessage = "No readable local documents were found for this source."

                manifestsBySourceID[source.id] = KnowledgeIndexManifest(
                    sourceID: source.id,
                    title: source.title,
                    kind: source.kind,
                    location: source.location,
                    status: .failed,
                    embeddingModelIdentifier: source.embeddingModelIdentifier,
                    embeddingProviderKind: embeddingProviderKind(for: source),
                    embeddingState: .failed,
                    storageLocation: storageLocation(forKnowledgeSource: source),
                    lastBuiltAt: now,
                    lastErrorMessage: rebuiltSources[sourceIndex].lastErrorMessage
                )
                continue
            }

            do {
                let index = try indexingService.buildIndex(for: inputs)
                let embeddingModel = source.embeddingModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
                let vectorDimension = (embeddingModel?.isEmpty == false) ? LocalEmbeddingService.defaultLocalVectorDimension : nil
                let fingerprint = indexingService.contentFingerprint(for: index)
                let storageLocation = storageLocation(forKnowledgeSource: source)
                let embeddingCount: Int
                if let vectorDimension,
                   let embeddingModel,
                   !embeddingModel.isEmpty {
                    let vectorIndexFile = LocalKnowledgeVectorStore().buildVectorIndexFile(
                        for: index,
                        sourceID: source.id,
                        title: source.title,
                        modelIdentifier: embeddingModel,
                        contentFingerprint: fingerprint,
                        builtAt: now,
                        vectorDimension: vectorDimension
                    )
                    try LocalKnowledgeVectorStore().write(vectorIndexFile, to: storageLocation)
                    embeddingCount = vectorIndexFile.records.count
                } else {
                    embeddingCount = 0
                }

                rebuiltSources[sourceIndex].status = .ready
                rebuiltSources[sourceIndex].documentCount = index.sources.count
                rebuiltSources[sourceIndex].chunkCount = index.chunkCount
                rebuiltSources[sourceIndex].embeddingRecordCount = embeddingCount
                rebuiltSources[sourceIndex].vectorDimension = vectorDimension
                rebuiltSources[sourceIndex].contentFingerprint = fingerprint
                rebuiltSources[sourceIndex].lastIndexedAt = now
                rebuiltSources[sourceIndex].lastErrorMessage = nil

                manifestsBySourceID[source.id] = KnowledgeIndexManifest(
                    sourceID: source.id,
                    title: source.title,
                    kind: source.kind,
                    location: source.location,
                    status: .ready,
                    documentCount: index.sources.count,
                    chunkCount: index.chunkCount,
                    embeddingRecordCount: embeddingCount,
                    vectorDimension: vectorDimension,
                    embeddingModelIdentifier: embeddingModel?.isEmpty == false ? embeddingModel : nil,
                    embeddingProviderKind: embeddingProviderKind(for: source),
                    embeddingState: vectorDimension == nil ? .disabled : .generated,
                    contentFingerprint: fingerprint,
                    storageLocation: storageLocation,
                    lastBuiltAt: now
                )
            } catch {
                rebuiltSources[sourceIndex].status = .failed
                rebuiltSources[sourceIndex].lastErrorMessage = error.localizedDescription
                manifestsBySourceID[source.id] = KnowledgeIndexManifest(
                    sourceID: source.id,
                    title: source.title,
                    kind: source.kind,
                    location: source.location,
                    status: .failed,
                    embeddingModelIdentifier: source.embeddingModelIdentifier,
                    embeddingProviderKind: embeddingProviderKind(for: source),
                    embeddingState: .failed,
                    storageLocation: storageLocation(forKnowledgeSource: source),
                    lastBuiltAt: now,
                    lastErrorMessage: error.localizedDescription
                )
            }
        }

        knowledgeSources = rebuiltSources
        knowledgeIndexManifests = Array(manifestsBySourceID.values).sorted { (lhs: KnowledgeIndexManifest, rhs: KnowledgeIndexManifest) in
            if lhs.status != rhs.status {
                return lhs.status.sortPriority < rhs.status.sortPriority
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func rebuildKnowledgeIndexManifestsUsingConfiguredEmbeddings(
        onlyQueued: Bool = false,
        now: Date = .now,
        vectorStore: LocalKnowledgeVectorStore = LocalKnowledgeVectorStore()
    ) async {
        let indexingService = LocalKnowledgeIndexingService()
        var rebuiltSources = knowledgeSources
        var manifestsBySourceID = Dictionary(
            uniqueKeysWithValues: knowledgeIndexManifests.compactMap { manifest in
                manifest.sourceID.map { ($0, manifest) }
            }
        )

        for sourceIndex in rebuiltSources.indices {
            let source = rebuiltSources[sourceIndex]
            if onlyQueued,
               source.status != .queued,
               source.status != .stale,
               source.status != .notIndexed {
                continue
            }

            let inputs = localKnowledgeDocumentInputs(for: source)
            guard !inputs.isEmpty else {
                rebuiltSources[sourceIndex].status = .failed
                rebuiltSources[sourceIndex].documentCount = 0
                rebuiltSources[sourceIndex].chunkCount = 0
                rebuiltSources[sourceIndex].embeddingRecordCount = 0
                rebuiltSources[sourceIndex].vectorDimension = nil
                rebuiltSources[sourceIndex].lastErrorMessage = "No readable local documents were found for this source."

                manifestsBySourceID[source.id] = KnowledgeIndexManifest(
                    sourceID: source.id,
                    title: source.title,
                    kind: source.kind,
                    location: source.location,
                    status: .failed,
                    embeddingModelIdentifier: source.embeddingModelIdentifier,
                    embeddingProviderKind: embeddingProviderKind(for: source),
                    embeddingState: .failed,
                    storageLocation: storageLocation(forKnowledgeSource: source),
                    lastBuiltAt: now,
                    lastErrorMessage: rebuiltSources[sourceIndex].lastErrorMessage
                )
                continue
            }

            do {
                rebuiltSources[sourceIndex].status = .indexing
                let index = try indexingService.buildIndex(for: inputs)
                let rawEmbeddingModel = source.embeddingModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
                let embeddingModel = rawEmbeddingModel?.isEmpty == false ? rawEmbeddingModel : nil
                let embeddingProvider = embeddingProvider(for: source, modelIdentifier: embeddingModel)
                let shouldBuildVectors = embeddingModel != nil
                let fingerprint = indexingService.contentFingerprint(for: index)
                let storageLocation = storageLocation(forKnowledgeSource: source)
                let vectorIndexFile: LocalKnowledgeVectorIndexFile?

                if shouldBuildVectors {
                    if embeddingModel != LocalEmbeddingService.deterministicModelIdentifier,
                       embeddingProvider == nil {
                        throw WorkspaceKnowledgeEmbeddingError.missingProvider(
                            embeddingModel ?? "the selected embedding model"
                        )
                    }
                    vectorIndexFile = try await vectorStore.buildVectorIndexFile(
                        for: index,
                        sourceID: source.id,
                        title: source.title,
                        modelIdentifier: embeddingModel ?? LocalEmbeddingService.deterministicModelIdentifier,
                        embeddingProvider: embeddingProvider,
                        contentFingerprint: fingerprint,
                        builtAt: now
                    )
                    if let vectorIndexFile {
                        try vectorStore.write(vectorIndexFile, to: storageLocation)
                    }
                } else {
                    vectorIndexFile = nil
                }

                let embeddingCount = vectorIndexFile?.records.count ?? 0
                let vectorDimension = vectorIndexFile?.vectorDimension
                let generatedModel = vectorIndexFile?.modelIdentifier
                let embeddingState: KnowledgeEmbeddingState
                if !shouldBuildVectors {
                    embeddingState = .disabled
                } else {
                    embeddingState = .generated
                }

                rebuiltSources[sourceIndex].status = .ready
                rebuiltSources[sourceIndex].documentCount = index.sources.count
                rebuiltSources[sourceIndex].chunkCount = index.chunkCount
                rebuiltSources[sourceIndex].embeddingRecordCount = embeddingCount
                rebuiltSources[sourceIndex].vectorDimension = vectorDimension
                rebuiltSources[sourceIndex].contentFingerprint = fingerprint
                rebuiltSources[sourceIndex].lastIndexedAt = now
                rebuiltSources[sourceIndex].lastErrorMessage = nil

                manifestsBySourceID[source.id] = KnowledgeIndexManifest(
                    sourceID: source.id,
                    title: source.title,
                    kind: source.kind,
                    location: source.location,
                    status: .ready,
                    documentCount: index.sources.count,
                    chunkCount: index.chunkCount,
                    embeddingRecordCount: embeddingCount,
                    vectorDimension: vectorDimension,
                    embeddingModelIdentifier: generatedModel,
                    embeddingProviderKind: embeddingProvider?.kind ?? embeddingProviderKind(for: source),
                    embeddingState: embeddingState,
                    contentFingerprint: fingerprint,
                    storageLocation: storageLocation,
                    lastBuiltAt: now
                )
            } catch {
                rebuiltSources[sourceIndex].status = .failed
                rebuiltSources[sourceIndex].lastErrorMessage = error.localizedDescription
                manifestsBySourceID[source.id] = KnowledgeIndexManifest(
                    sourceID: source.id,
                    title: source.title,
                    kind: source.kind,
                    location: source.location,
                    status: .failed,
                    embeddingModelIdentifier: source.embeddingModelIdentifier,
                    embeddingProviderKind: embeddingProviderKind(for: source),
                    embeddingState: .failed,
                    storageLocation: storageLocation(forKnowledgeSource: source),
                    lastBuiltAt: now,
                    lastErrorMessage: error.localizedDescription
                )
            }
        }

        knowledgeSources = rebuiltSources
        knowledgeIndexManifests = Array(manifestsBySourceID.values).sorted { (lhs: KnowledgeIndexManifest, rhs: KnowledgeIndexManifest) in
            if lhs.status != rhs.status {
                return lhs.status.sortPriority < rhs.status.sortPriority
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    @discardableResult
    func queueWatchedKnowledgeSources(
        _ sourceIDs: Set<UUID>,
        now: Date = .now
    ) -> [UUID] {
        guard !sourceIDs.isEmpty else { return [] }

        var queuedSourceIDs: [UUID] = []
        for index in knowledgeSources.indices {
            let source = knowledgeSources[index]
            guard sourceIDs.contains(source.id),
                  source.isWatched,
                  source.kind.supportsFileSystemWatching else {
                continue
            }

            knowledgeSources[index].status = .queued
            knowledgeSources[index].lastErrorMessage = nil
            queuedSourceIDs.append(source.id)
        }

        return queuedSourceIDs
    }

    @discardableResult
    func queueStaleWatchedWebPageKnowledgeSources(
        olderThan maximumAge: TimeInterval = WorkspaceStore.defaultWatchedWebPageRefreshInterval,
        maximumSourceCount: Int = 8,
        now: Date = .now
    ) -> [UUID] {
        guard maximumAge > 0,
              maximumSourceCount > 0 else { return [] }

        let cutoff = now.addingTimeInterval(-maximumAge)
        let candidates = Array(knowledgeSources.indices.compactMap { index -> (index: Int, id: UUID, freshnessDate: Date, assetIndex: Int?, capturedAt: Date?)? in
            let source = knowledgeSources[index]
            guard source.kind == .webPage,
                  source.isWatched,
                  source.status != .queued,
                  source.status != .indexing,
                  let freshnessDate = webPageKnowledgeFreshnessDate(for: source),
                  freshnessDate <= cutoff else {
                return nil
            }

            let assetIndex = capturedWebPageAssetIndex(for: source)
            let capturedAt = assetIndex.flatMap { usableWebPageCaptureDate(for: libraryAssets[$0]) }
            return (index, source.id, freshnessDate, assetIndex, capturedAt)
        }
        .sorted { lhs, rhs in
            if lhs.freshnessDate == rhs.freshnessDate {
                return lhs.index < rhs.index
            }
            return lhs.freshnessDate < rhs.freshnessDate
        }
        .prefix(maximumSourceCount))

        for candidate in candidates {
            knowledgeSources[candidate.index].status = .queued
            knowledgeSources[candidate.index].lastErrorMessage = nil

            if let assetIndex = candidate.assetIndex,
               let capturedAt = candidate.capturedAt,
               capturedAt <= cutoff {
                libraryAssets[assetIndex].summaryStatus = .stale
                libraryAssets[assetIndex].updatedAt = now
                libraryAssets[assetIndex].notes = webPageStalenessNotes(
                    existingNotes: libraryAssets[assetIndex].notes,
                    capturedAt: capturedAt,
                    now: now
                )
            }
        }

        return candidates.map(\.id)
    }

    @discardableResult
    func runScheduledWatchedWebPageRefresh(
        now: Date = .now,
        force: Bool = false,
        webPageCaptureService: WebPageCaptureService = WebPageCaptureService()
    ) async -> WatchedWebPageRefreshRunSummary {
        var schedule = preferences.watchedWebPageRefreshSchedule ?? WatchedWebPageRefreshSchedule()

        func skip(_ reason: String) -> WatchedWebPageRefreshRunSummary {
            schedule.lastSkippedReason = reason
            preferences.watchedWebPageRefreshSchedule = schedule
            return .skipped(reason)
        }

        guard schedule.isEnabled else {
            return skip("Automatic watched web-page refresh is disabled.")
        }

        guard preferences.automationsEnabled ?? true else {
            return skip("Local automations are disabled.")
        }

        guard !(preferences.localOnlyMode ?? true) else {
            return skip("Local-only mode is active.")
        }

        guard knowledgeSources.contains(where: { $0.kind == .webPage && $0.isWatched }) else {
            return skip("No watched web pages are configured.")
        }

        guard force || schedule.isDue(now: now) else {
            return skip("The watched web-page refresh interval has not elapsed.")
        }

        schedule.lastRefreshStartedAt = now
        schedule.lastSkippedReason = nil
        preferences.watchedWebPageRefreshSchedule = schedule

        let alreadyQueuedIDs = knowledgeSources
            .filter { $0.kind == .webPage && $0.isWatched && $0.status == .queued }
            .map(\.id)
        let newlyQueuedIDs = queueStaleWatchedWebPageKnowledgeSources(
            olderThan: schedule.boundedRefreshInterval,
            maximumSourceCount: schedule.boundedMaximumBatchSize,
            now: now
        )
        var queuedSourceIDs: [UUID] = []
        for sourceID in alreadyQueuedIDs + newlyQueuedIDs {
            guard queuedSourceIDs.contains(sourceID) == false else { continue }
            queuedSourceIDs.append(sourceID)
            if queuedSourceIDs.count == schedule.boundedMaximumBatchSize {
                break
            }
        }

        var refreshedSourceIDs: [UUID] = []
        var failedSourceIDs: [UUID] = []

        for sourceID in queuedSourceIDs {
            let refreshedSource = await captureWebPageKnowledgeSource(
                sourceID,
                now: now,
                webPageCaptureService: webPageCaptureService
            )
            if refreshedSource?.status == .ready {
                refreshedSourceIDs.append(sourceID)
            } else {
                failedSourceIDs.append(sourceID)
            }
        }

        schedule = preferences.watchedWebPageRefreshSchedule ?? schedule
        schedule.lastRefreshCompletedAt = now
        schedule.lastQueuedSourceIDs = queuedSourceIDs
        schedule.lastSkippedReason = queuedSourceIDs.isEmpty
            ? "No watched web captures were older than the refresh interval."
            : nil
        preferences.watchedWebPageRefreshSchedule = schedule

        return WatchedWebPageRefreshRunSummary(
            queuedSourceIDs: queuedSourceIDs,
            refreshedSourceIDs: refreshedSourceIDs,
            failedSourceIDs: failedSourceIDs,
            skippedReason: schedule.lastSkippedReason
        )
    }

    func localKnowledgeDocumentInputs(
        excludingPrompt prompt: String? = nil,
        knowledgeSourceIDs: Set<UUID>? = nil
    ) -> [LocalKnowledgeDocumentInput] {
        var inputs: [LocalKnowledgeDocumentInput] = []
        for source in knowledgeSourcesForScope(knowledgeSourceIDs) {
            inputs.append(contentsOf: localKnowledgeDocumentInputs(for: source, excludingPrompt: prompt))
        }
        return inputs
    }

    var youtubeAssets: [LibraryAsset] {
        libraryAssets.filter { ($0.platform ?? inferPlatform(from: $0.sourceURL)) == .youtube }
    }

    var xAssets: [LibraryAsset] {
        libraryAssets.filter { ($0.platform ?? inferPlatform(from: $0.sourceURL)) == .x }
    }

    var inboxAssets: [LibraryAsset] {
        libraryAssets.filter { $0.tags.contains("inbox") || $0.tags.contains("manual") }
    }

    var filteredAssets: [LibraryAsset] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return libraryAssets }
        return libraryAssets.filter {
            $0.title.localizedCaseInsensitiveContains(query)
            || $0.summary.localizedCaseInsensitiveContains(query)
            || $0.notes.localizedCaseInsensitiveContains(query)
            || $0.tags.joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }

    var pendingTranscriptAssets: [LibraryAsset] {
        libraryAssets.filter {
            guard let transcript = $0.transcript else { return false }
            return transcript.status == .queued || transcript.status == .notRequested
        }
    }

    var assetsNeedingSummary: [LibraryAsset] {
        libraryAssets.filter { $0.summaryStatus == .missing || $0.summaryStatus == .stale }
    }

    var unscheduledDrafts: [DraftDocument] {
        drafts.filter { $0.scheduledFor == nil && $0.status != .published }
    }

    var enabledAutomations: [WorkspaceAutomation] {
        automations.filter(\.isEnabled)
    }

    var recentLocalActions: [LocalActionRecord] {
        Array(localActionHistory.prefix(8))
    }

    var integrationStatusRows: [IntegrationStatusRow] {
        let providerRows = providerConfigurations.map {
            IntegrationStatusRow(
                id: "provider-\($0.id.uuidString)",
                title: $0.displayName,
                detail: $0.lastErrorMessage ?? $0.endpoint,
                status: $0.connectionStatus
            )
        }

        let accountRows = accounts.map {
            IntegrationStatusRow(
                id: "account-\($0.id.uuidString)",
                title: $0.displayName,
                detail: $0.lastSyncErrorMessage ?? "\($0.pendingImportCount) pending imports",
                status: $0.connectionStatus
            )
        }

        return providerRows + accountRows
    }

    var dashboardSnapshot: WorkspaceDashboardSnapshot {
        WorkspaceDashboardSnapshot(
            sourceCount: libraryAssets.count,
            draftCount: drafts.count,
            projectCount: projects.count,
            automationCount: automations.count,
            pendingTranscriptCount: pendingTranscriptAssets.count,
            pendingSummaryCount: assetsNeedingSummary.count,
            scheduledDraftCount: drafts.filter { $0.scheduledFor != nil }.count,
            confirmationCount: localActionHistory.filter { $0.status == .requiresConfirmation }.count
        )
    }

    var safeLocalActions: [SafeLocalAction] {
        var actions: [SafeLocalAction] = []

        if let asset = currentLibraryAsset {
            if asset.transcript?.status != .available, (asset.platform ?? inferPlatform(from: asset.sourceURL)) == .youtube {
                actions.append(
                    SafeLocalAction(
                        id: "queue-transcript-\(asset.id.uuidString)",
                        title: "Queue transcript import",
                        detail: "Marks the selected YouTube item for local transcript intake only.",
                        kind: .importTranscript,
                        requiresConfirmation: false
                    )
                )
            }

            if asset.summaryStatus == .missing || asset.summaryStatus == .stale {
                actions.append(
                    SafeLocalAction(
                        id: "summarize-\(asset.id.uuidString)",
                        title: "Generate local summary",
                        detail: "Refreshes the selected asset summary from local context.",
                        kind: .generateSummary,
                        requiresConfirmation: false
                    )
                )
            }

            if asset.projectID == nil && currentProject != nil {
                actions.append(
                    SafeLocalAction(
                        id: "link-project-\(asset.id.uuidString)",
                        title: "Attach to active project",
                        detail: "Links the selected source to the current project.",
                        kind: .captureURL,
                        requiresConfirmation: false
                    )
                )
            }
        }

        if let draft = currentDraft, draft.scheduledFor == nil {
            actions.append(
                SafeLocalAction(
                    id: "schedule-draft-\(draft.id.uuidString)",
                    title: "Schedule locally",
                    detail: "Creates or updates a local calendar entry for the selected draft.",
                    kind: .scheduleDraft,
                    requiresConfirmation: false
                )
            )
        }

        return actions
    }

    var assistantContext: AssistantContextSnapshot {
        AssistantContextSnapshot(
            destination: selectedDestination,
            provider: activeProvider,
            project: currentProject,
            draft: currentDraft,
            libraryAsset: currentLibraryAsset,
            calendarEntry: currentCalendarEntry,
            thread: currentAssistantThread,
            dashboard: dashboardSnapshot,
            integrationRows: integrationStatusRows,
            pendingConfirmationCount: dashboardSnapshot.confirmationCount
        )
    }

    private func hydrate(from item: Item) {
        selectedDestination = normalizedPrimaryDestination(item.selectedDestination)
        selectedProjectID = item.selectedProjectID
        selectedDraftID = item.selectedDraftID
        selectedAssetID = item.selectedAssetID
        selectedCalendarEntryID = item.selectedCalendarEntryID
        selectedAssistantThreadID = item.selectedAssistantThreadID
        searchText = ""
        accounts = item.accounts
        providerConfigurations = item.providerConfigurations
        libraryAssets = item.libraryAssets
        projects = item.projects
        drafts = item.drafts
        calendarEntries = item.calendarEntries
        assistantThreads = item.assistantThreads
        automations = item.automations ?? []
        localActionHistory = item.localActionHistory ?? []
        tags = item.tags ?? []
        chatFolders = item.chatFolders ?? []
        promptProfiles = item.promptProfiles ?? []
        chatTemplates = item.chatTemplates ?? []
        promptChains = item.promptChains ?? []
        modelPresets = item.modelPresets ?? []
        knowledgeSources = item.knowledgeSources ?? []
        knowledgeIndexManifests = item.knowledgeIndexManifests ?? []
        toolConfigurations = item.toolConfigurations ?? []
        toolExecutionResults = item.toolExecutionResults ?? []
        modelComparisonRuns = item.modelComparisonRuns ?? []
        localDiscoveryResults = item.localDiscoveryResults ?? []
        pinnedMessages = item.pinnedMessages ?? []
        archivedAssistantThreadIDs = Set(item.archivedAssistantThreadIDs ?? [])
        localMemories = item.localMemories ?? []
        preferences = item.preferences
        preferences.defaultDestination = normalizedPrimaryDestination(preferences.defaultDestination)
    }

    private func normalizeWorkspace() {
        ensureAssistantThread()
        ensureAIChatDefaultsIfNeeded()
        ensureDefaultAutomationsIfNeeded()
        normalizeAssetPlatforms()
        rebuildProjectReferences()
        normalizePromptProfileState()
        normalizeChatTemplateState()
        normalizePromptChainState()
        normalizePromptChainThreadState()
        normalizeModelPresetState()
        normalizeProjectAIProfileState()
        tags = buildTagRegistry()
        pruneChatOrganizationState()
        normalizeLocalMemoryState()
        cleanSelections()
    }

    private func ensureAssistantThread() {
        if assistantThreads.isEmpty {
            let thread = AssistantThread(
                title: "New AI Chat",
                messages: [
                    AssistantMessage(
                        role: .system,
                        text: "You are Flannel, a local-first macOS AI chat app. Keep chat history and context local unless the user explicitly selects a cloud or CLI provider mode."
                    )
                ],
                pinnedProjectID: selectedProjectID,
                pinnedDraftID: selectedDraftID,
                pinnedAssetID: selectedAssetID,
                pinnedCalendarEntryID: selectedCalendarEntryID
            )
            assistantThreads = [thread]
            selectedAssistantThreadID = thread.id
        }
    }

    private func ensureAIChatDefaultsIfNeeded() {
        ensureProviderMatrix()

        if chatFolders.isEmpty {
            chatFolders = [
                ChatFolder(title: "Pinned", symbolName: "pin", isPinned: true),
                ChatFolder(title: "Research", symbolName: "magnifyingglass"),
                ChatFolder(title: "Coding", symbolName: "chevron.left.forwardslash.chevron.right"),
                ChatFolder(title: "Writing", symbolName: "text.quote")
            ]
        }

        if promptProfiles.isEmpty {
            promptProfiles = [
                SystemPromptProfile(
                    title: "Local-first assistant",
                    detail: "Default private assistant profile for everyday work.",
                    prompt: "You are Flannel, a precise local-first AI assistant. Prefer local context, cite sources when retrieval is used, and ask before network, file-write, or terminal actions.",
                    tags: ["default", "privacy"],
                    isDefault: true
                ),
                SystemPromptProfile(
                    title: "Research analyst",
                    detail: "Turns retrieved context into sourced findings and open questions.",
                    prompt: "Act as a research analyst. Separate known facts, citations, uncertainty, and next research tasks.",
                    tags: ["research", "rag"]
                ),
                SystemPromptProfile(
                    title: "Code copilot",
                    detail: "Plans and reviews code while requiring approval before edits or shell commands.",
                    prompt: "Act as a careful coding assistant. Explain intended file edits and request approval before write or terminal tools.",
                    tags: ["coding", "tools"]
                )
            ]
            preferences.defaultSystemPromptProfileID = promptProfiles.first(where: \.isDefault)?.id
        }

        if chatTemplates.isEmpty {
            chatTemplates = [
                ChatTemplate(
                    title: "Private Local Chat",
                    detail: "Local-first conversation with retrieval-aware citations and approval gates.",
                    systemPrompt: "You are Flannel, a precise local-first AI assistant. Prefer local context, cite sources when retrieval is used, and ask before network, file-write, or terminal actions.",
                    mode: .workspaceCopilot,
                    tagNames: ["default", "local", "privacy"],
                    preferredProviderKind: .ollama,
                    preferredAccessMode: .localServer,
                    preferredModelIdentifier: "llama3.1",
                    requiredToolKinds: [.workspaceSearch, .ragRetrieval],
                    isPinned: true
                ),
                ChatTemplate(
                    title: "Research Brief",
                    detail: "Turns local knowledge into sourced findings, unknowns, and next research moves.",
                    systemPrompt: "Act as a research analyst. Use local indexed knowledge first. Separate known facts, citations, uncertainty, contradictions, and next research tasks. Ask before external network requests.",
                    starterPrompt: "Research this topic using local knowledge first, then identify gaps that need approved web or tool work:\n\n",
                    mode: .research,
                    tagNames: ["research", "rag"],
                    requiredToolKinds: [.workspaceSearch, .ragRetrieval, .webSearch, .webPageReader]
                ),
                ChatTemplate(
                    title: "Code Review",
                    detail: "Prioritizes bugs, regressions, missing tests, and safe implementation steps.",
                    systemPrompt: "Act as a careful coding assistant. Prioritize bugs, regressions, missing tests, and maintainable fixes. Explain intended edits before file writes and ask before terminal commands.",
                    starterPrompt: "Review this code, design, or plan. Lead with concrete risks, then suggest the smallest safe implementation path:\n\n",
                    mode: .workspaceCopilot,
                    tagNames: ["coding", "review"],
                    requiredToolKinds: [.localFileRead, .workspaceSearch, .terminal, .codeExecution]
                )
            ]
        }

        if promptChains.isEmpty {
            promptChains = [
                PromptChain(
                    title: "Private Research Chain",
                    detail: "Scope the question, retrieve local evidence, synthesize findings, and produce a next-action checklist.",
                    systemPrompt: "Act as a careful local-first research partner. Use local knowledge first, cite retrieved sources, and ask before external network or file-write actions.",
                    steps: [
                        PromptChainStep(
                            title: "Scope",
                            instruction: "Clarify the research question, success criteria, constraints, and whether cloud providers or external web search are allowed for this thread.",
                            expectedOutput: "A concise research brief with assumptions and allowed data boundaries."
                        ),
                        PromptChainStep(
                            title: "Retrieve",
                            instruction: "Search the selected local knowledge sources for the topic and list the strongest relevant sources with short notes.",
                            expectedOutput: "A source-backed evidence list with citations or file references."
                        ),
                        PromptChainStep(
                            title: "Synthesize",
                            instruction: "Turn the evidence into findings, contradictions, unknowns, and a recommendation that preserves the user's privacy mode.",
                            expectedOutput: "A structured answer with findings, uncertainty, and a safe next step."
                        )
                    ],
                    mode: .research,
                    tagNames: ["research", "rag", "privacy"],
                    preferredProviderKind: .ollama,
                    preferredAccessMode: .localServer,
                    preferredModelIdentifier: "llama3.1",
                    requiredToolKinds: [.workspaceSearch, .ragRetrieval],
                    isPinned: true
                ),
                PromptChain(
                    title: "Code Change Chain",
                    detail: "Map the code, plan the smallest safe change, implement, then verify with focused tests.",
                    systemPrompt: "Act as a senior coding assistant. Explain intended edits before writes, keep changes scoped, and run focused validation before summarizing.",
                    steps: [
                        PromptChainStep(
                            title: "Map",
                            instruction: "Inspect the relevant files and identify the exact ownership boundaries, data flow, and tests for this change.",
                            expectedOutput: "A short implementation map with concrete files and risks."
                        ),
                        PromptChainStep(
                            title: "Implement",
                            instruction: "Make the smallest coherent code change that satisfies the request while preserving existing patterns.",
                            expectedOutput: "Changed files and the behavior each change enables."
                        ),
                        PromptChainStep(
                            title: "Verify",
                            instruction: "Run the focused build or test commands that prove the changed behavior and report any remaining risk.",
                            expectedOutput: "Validation commands and pass/fail results."
                        )
                    ],
                    mode: .workspaceCopilot,
                    tagNames: ["coding", "tools", "verification"],
                    requiredToolKinds: [.localFileRead, .workspaceSearch, .terminal, .codeExecution]
                )
            ]
        }

        if modelPresets.isEmpty {
            modelPresets = [
                ModelPreset(
                    title: "Local private chat",
                    providerKind: .ollama,
                    accessMode: .localServer,
                    modelIdentifier: "llama3.1",
                    contextWindowTokens: 8_192,
                    capabilities: [.chat, .streaming, .toolCalling],
                    privacyScope: .localOnly,
                    isDefault: true
                ),
                ModelPreset(
                    title: "LM Studio local router",
                    providerKind: .lmStudio,
                    accessMode: .localServer,
                    modelIdentifier: "",
                    contextWindowTokens: 8_192,
                    capabilities: [.chat, .streaming, .toolCalling, .embeddings, .openAICompatible],
                    privacyScope: .localOnly
                ),
                ModelPreset(
                    title: "Official OpenAI API",
                    providerKind: .openAI,
                    accessMode: .apiKey,
                    modelIdentifier: "gpt-5.5",
                    capabilities: [.chat, .streaming, .toolCalling, .vision, .reasoning, .structuredOutput],
                    privacyScope: .externalAPI
                ),
                ModelPreset(
                    title: "Official Anthropic API",
                    providerKind: .anthropic,
                    accessMode: .apiKey,
                    modelIdentifier: "claude-opus-4.7",
                    capabilities: [.chat, .streaming, .toolCalling, .vision, .reasoning],
                    privacyScope: .externalAPI
                )
            ]
            preferences.defaultModelPresetID = modelPresets.first(where: \.isDefault)?.id
        }
        normalizeModelPresetState()

        if knowledgeSources.isEmpty {
            knowledgeSources = [
                KnowledgeSource(
                    title: "Chat history",
                    kind: .chatHistory,
                    location: "flannel://chat-history",
                    status: .queued,
                    embeddingModelIdentifier: LocalEmbeddingService.deterministicModelIdentifier,
                    isWatched: true
                ),
                KnowledgeSource(
                    title: "Workspace notes",
                    kind: .workspaceNotes,
                    location: "flannel://workspace",
                    status: .queued,
                    embeddingModelIdentifier: LocalEmbeddingService.deterministicModelIdentifier,
                    isWatched: true
                )
            ]
        }

        ensureToolMatrix()
    }

    private func ensureToolMatrix() {
        let defaults = Self.defaultToolConfigurations()
        guard !toolConfigurations.isEmpty else {
            toolConfigurations = defaults
            return
        }

        for tool in defaults {
            if let index = toolConfigurations.firstIndex(where: { $0.kind == tool.kind }) {
                if toolConfigurations[index].endpoint == nil {
                    toolConfigurations[index].endpoint = tool.endpoint
                }
            } else {
                toolConfigurations.append(tool)
            }
        }
    }

    private static func defaultToolConfigurations() -> [ToolConfiguration] {
        [
            ToolConfiguration(
                kind: .workspaceSearch,
                title: "Workspace Search",
                detail: "Search local chats, prompts, and indexed workspace material.",
                permissionPolicy: .alwaysAllow,
                isEnabled: true
            ),
            ToolConfiguration(
                kind: .ragRetrieval,
                title: "RAG Retrieval",
                detail: "Retrieve local snippets with citations from enabled knowledge sources.",
                permissionPolicy: .alwaysAllow,
                isEnabled: true
            ),
            ToolConfiguration(
                kind: .webSearch,
                title: "Web Search",
                detail: "Search the web through a BYOK Brave or Perplexity connector optimized for agents and RAG.",
                permissionPolicy: .askEveryTime,
                requiresNetwork: true,
                endpoint: WebSearchService.defaultEndpoint
            ),
            ToolConfiguration(
                kind: .webPageReader,
                title: "Web Page Reader",
                detail: "Fetch an http or https page, extract readable text, and return it as auditable tool context.",
                permissionPolicy: .askEveryTime,
                requiresNetwork: true
            ),
            ToolConfiguration(
                kind: .localFileRead,
                title: "Read Files",
                detail: "Read explicit local file paths after approval.",
                permissionPolicy: .askEveryTime
            ),
            ToolConfiguration(
                kind: .localFileWrite,
                title: "Write Files",
                detail: "Create or edit files after explicit approval.",
                permissionPolicy: .askEveryTime,
                canModifyFiles: true
            ),
            ToolConfiguration(
                kind: .terminal,
                title: "Terminal",
                detail: "Run shell commands only when explicitly approved.",
                permissionPolicy: .deny,
                canModifyFiles: true
            ),
            ToolConfiguration(
                kind: .codeExecution,
                title: "Code Execution",
                detail: "Run short local scripts after explicit approval.",
                permissionPolicy: .deny,
                canModifyFiles: true
            ),
            ToolConfiguration(
                kind: .browserAutomation,
                title: "Browser Automation",
                detail: "Open URLs or privacy-preserving searches in the default browser after explicit approval.",
                permissionPolicy: .askEveryTime,
                requiresNetwork: true
            ),
            ToolConfiguration(
                kind: .github,
                title: "GitHub",
                detail: "Search GitHub repositories, issues, and pull requests with optional BYOK token access.",
                permissionPolicy: .askEveryTime,
                requiresNetwork: true,
                endpoint: GitHubToolService.defaultEndpoint
            ),
            ToolConfiguration(
                kind: .notion,
                title: "Notion",
                detail: "Search Notion pages, fetch page markdown, and query data sources with a BYOK integration token.",
                permissionPolicy: .askEveryTime,
                requiresNetwork: true,
                endpoint: NotionToolService.defaultEndpoint
            ),
            ToolConfiguration(
                kind: .youtube,
                title: "YouTube",
                detail: "Search YouTube videos and read video metadata through a BYOK YouTube Data API key.",
                permissionPolicy: .askEveryTime,
                requiresNetwork: true,
                endpoint: YouTubeToolService.defaultEndpoint
            ),
            ToolConfiguration(
                kind: .x,
                title: "X",
                detail: "Search recent X posts and read post or profile metadata through a BYOK X API bearer token.",
                permissionPolicy: .askEveryTime,
                requiresNetwork: true,
                endpoint: XToolService.defaultEndpoint
            )
        ]
    }

    private func ensureProviderMatrix() {
        var seededRouteKeys = Set(providerConfigurations.map(providerRouteSeedKey))

        func addIfMissing(_ provider: ProviderConfiguration) {
            let routeKey = providerRouteSeedKey(provider)
            guard !seededRouteKeys.contains(routeKey) else { return }
            providerConfigurations.append(provider)
            seededRouteKeys.insert(routeKey)
        }

        addIfMissing(
            ProviderConfiguration(
                kind: .ollama,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "Local Ollama",
                endpoint: defaultProviderEndpoint(for: .ollama),
                modelIdentifier: defaultProviderModelIdentifier(for: .ollama),
                isEnabled: true,
                connectionStatus: .disconnected,
                isLocalPreferred: true,
                availableModels: defaultProviderAvailableModels(for: .ollama),
                capabilities: providerRuntimeCapabilityDefaults(for: .ollama),
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsEmbeddings: true
            )
        )

        addIfMissing(
            ProviderConfiguration(
                kind: .lmStudio,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "LM Studio",
                endpoint: defaultProviderEndpoint(for: .lmStudio),
                modelIdentifier: defaultProviderModelIdentifier(for: .lmStudio),
                isEnabled: true,
                connectionStatus: .disconnected,
                isLocalPreferred: true,
                capabilities: providerRuntimeCapabilityDefaults(for: .lmStudio),
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsEmbeddings: true
            )
        )

        addIfMissing(
            ProviderConfiguration(
                kind: .openAI,
                accessMode: .apiKey,
                privacyScope: .externalAPI,
                displayName: "OpenAI API",
                endpoint: defaultProviderEndpoint(for: .openAI),
                modelIdentifier: defaultProviderModelIdentifier(for: .openAI),
                isEnabled: true,
                connectionStatus: .needsAttention,
                lastErrorMessage: "API key must be saved in Keychain before use.",
                availableModels: defaultProviderAvailableModels(for: .openAI),
                capabilities: providerRuntimeCapabilityDefaults(for: .openAI),
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsVision: true,
                supportsStructuredOutput: true
            )
        )

        addIfMissing(
            ProviderConfiguration(
                kind: .anthropic,
                accessMode: .apiKey,
                privacyScope: .externalAPI,
                displayName: "Anthropic API",
                endpoint: defaultProviderEndpoint(for: .anthropic),
                modelIdentifier: defaultProviderModelIdentifier(for: .anthropic),
                isEnabled: false,
                connectionStatus: .needsAttention,
                lastErrorMessage: "API key must be saved in Keychain before use.",
                availableModels: defaultProviderAvailableModels(for: .anthropic),
                capabilities: providerRuntimeCapabilityDefaults(for: .anthropic),
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsVision: true
            )
        )

        for kind in [LLMProviderKind.gemini, .xAI, .mistral, .groq, .openRouter, .perplexity, .customOpenAICompatible] {
            let capabilities = providerRuntimeCapabilityDefaults(for: kind)
            addIfMissing(
                ProviderConfiguration(
                    kind: kind,
                    accessMode: kind == .customOpenAICompatible ? .openAICompatible : .apiKey,
                    privacyScope: .externalAPI,
                    displayName: AIKnownProviderCatalog.entry(for: kind)?.displayName ?? "\(kind.title) API",
                    endpoint: defaultProviderEndpoint(for: kind),
                    modelIdentifier: defaultProviderModelIdentifier(for: kind),
                    isEnabled: false,
                    connectionStatus: .needsAttention,
                    lastErrorMessage: "Configure credentials before enabling.",
                    availableModels: defaultProviderAvailableModels(for: kind),
                    capabilities: capabilities,
                    supportsStreaming: capabilities.contains(.streaming),
                    supportsToolCalling: capabilities.contains(.toolCalling),
                    supportsEmbeddings: capabilities.contains(.embeddings),
                    supportsVision: capabilities.contains(.vision),
                    supportsStructuredOutput: capabilities.contains(.structuredOutput)
                )
            )
        }
        reconcileHostedProviderRuntimeDefaults()

        addIfMissing(
            ProviderConfiguration(
                kind: .chatGPTCLI,
                accessMode: .subscriptionCLI,
                privacyScope: .localCLI,
                displayName: "ChatGPT/Codex CLI",
                endpoint: "codex exec --json -",
                modelIdentifier: defaultProviderModelIdentifier(for: .chatGPTCLI),
                isEnabled: false,
                connectionStatus: .needsAttention,
                lastErrorMessage: "Requires a locally authenticated Codex or ChatGPT CLI.",
                availableModels: defaultProviderAvailableModels(for: .chatGPTCLI),
                capabilities: providerRuntimeCapabilityDefaults(for: .chatGPTCLI),
                supportsStreaming: true,
                supportsToolCalling: false
            )
        )

        addIfMissing(
            ProviderConfiguration(
                kind: .claudeCodeCLI,
                accessMode: .subscriptionCLI,
                privacyScope: .localCLI,
                displayName: "Claude Code CLI",
                endpoint: "claude -p --output-format stream-json --verbose",
                modelIdentifier: defaultProviderModelIdentifier(for: .claudeCodeCLI),
                isEnabled: false,
                connectionStatus: .needsAttention,
                lastErrorMessage: "Requires a locally authenticated Claude Code install.",
                availableModels: defaultProviderAvailableModels(for: .claudeCodeCLI),
                capabilities: providerRuntimeCapabilityDefaults(for: .claudeCodeCLI),
                supportsStreaming: true,
                supportsToolCalling: false
            )
        )

        addIfMissing(
            ProviderConfiguration(
                kind: .vercelAISDKBridge,
                accessMode: .aiSDKBridge,
                privacyScope: .bridgeService,
                displayName: "Vercel AI SDK Bridge",
                endpoint: defaultProviderEndpoint(for: .vercelAISDKBridge),
                modelIdentifier: defaultProviderModelIdentifier(for: .vercelAISDKBridge),
                isEnabled: false,
                connectionStatus: .needsAttention,
                lastErrorMessage: "Optional Node 22+ local bridge. Not embedded in the Swift app.",
                capabilities: providerRuntimeCapabilityDefaults(for: .vercelAISDKBridge),
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsStructuredOutput: true
            )
        )
    }

    private func providerRouteSeedKey(_ provider: ProviderConfiguration) -> String {
        "\(provider.kind.rawValue)::\(provider.accessMode.rawValue)"
    }

    private func defaultProviderRoute(
        kind: LLMProviderKind,
        accessMode: ProviderAccessMode,
        privacyScope: ProviderPrivacyScope
    ) -> ProviderConfiguration {
        let displayName = uniqueProviderDisplayName(
            baseName: defaultProviderRouteDisplayName(kind: kind, accessMode: accessMode, privacyScope: privacyScope)
        )

        switch kind {
        case .ollama:
            return ProviderConfiguration(
                kind: .ollama,
                accessMode: .localServer,
                privacyScope: privacyScope,
                displayName: displayName,
                endpoint: defaultProviderEndpoint(for: .ollama),
                modelIdentifier: "",
                isEnabled: true,
                connectionStatus: .needsAttention,
                lastErrorMessage: "Run local discovery or enter an installed Ollama chat model.",
                isLocalPreferred: true,
                capabilities: providerRuntimeCapabilityDefaults(for: .ollama),
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsEmbeddings: true
            )
        case .lmStudio:
            return ProviderConfiguration(
                kind: .lmStudio,
                accessMode: .localServer,
                privacyScope: privacyScope,
                displayName: displayName,
                endpoint: defaultProviderEndpoint(for: .lmStudio),
                modelIdentifier: "",
                isEnabled: true,
                connectionStatus: .needsAttention,
                lastErrorMessage: "Start the LM Studio server, run discovery, then select a model.",
                isLocalPreferred: true,
                capabilities: providerRuntimeCapabilityDefaults(for: .lmStudio),
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsEmbeddings: true
            )
        case .openAI:
            return ProviderConfiguration(
                kind: .openAI,
                accessMode: .apiKey,
                privacyScope: privacyScope,
                displayName: displayName,
                endpoint: defaultProviderEndpoint(for: .openAI),
                modelIdentifier: defaultProviderModelIdentifier(for: .openAI),
                isEnabled: false,
                connectionStatus: .needsAttention,
                lastErrorMessage: "Save an OpenAI Platform API key in Keychain before enabling this route.",
                availableModels: defaultProviderAvailableModels(for: .openAI),
                capabilities: providerRuntimeCapabilityDefaults(for: .openAI),
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsVision: true,
                supportsStructuredOutput: true
            )
        case .anthropic:
            return ProviderConfiguration(
                kind: .anthropic,
                accessMode: .apiKey,
                privacyScope: privacyScope,
                displayName: displayName,
                endpoint: defaultProviderEndpoint(for: .anthropic),
                modelIdentifier: defaultProviderModelIdentifier(for: .anthropic),
                isEnabled: false,
                connectionStatus: .needsAttention,
                lastErrorMessage: "Save an Anthropic Console API key in Keychain before enabling this route.",
                availableModels: defaultProviderAvailableModels(for: .anthropic),
                capabilities: providerRuntimeCapabilityDefaults(for: .anthropic),
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsVision: true
            )
        case .chatGPTCLI:
            return ProviderConfiguration(
                kind: .chatGPTCLI,
                accessMode: .subscriptionCLI,
                privacyScope: .localCLI,
                displayName: displayName,
                endpoint: "codex exec --json -",
                modelIdentifier: defaultProviderModelIdentifier(for: .chatGPTCLI),
                isEnabled: false,
                connectionStatus: .needsAttention,
                lastErrorMessage: "Requires a locally authenticated Codex or ChatGPT CLI.",
                availableModels: defaultProviderAvailableModels(for: .chatGPTCLI),
                capabilities: providerRuntimeCapabilityDefaults(for: .chatGPTCLI),
                supportsStreaming: true
            )
        case .claudeCodeCLI:
            return ProviderConfiguration(
                kind: .claudeCodeCLI,
                accessMode: .subscriptionCLI,
                privacyScope: .localCLI,
                displayName: displayName,
                endpoint: "claude -p --output-format stream-json --verbose",
                modelIdentifier: defaultProviderModelIdentifier(for: .claudeCodeCLI),
                isEnabled: false,
                connectionStatus: .needsAttention,
                lastErrorMessage: "Requires a locally authenticated Claude Code install.",
                availableModels: defaultProviderAvailableModels(for: .claudeCodeCLI),
                capabilities: providerRuntimeCapabilityDefaults(for: .claudeCodeCLI),
                supportsStreaming: true
            )
        case .customOpenAICompatible:
            return ProviderConfiguration(
                kind: .customOpenAICompatible,
                accessMode: .openAICompatible,
                privacyScope: privacyScope,
                displayName: displayName,
                endpoint: privacyScope == .localOnly ? "http://localhost:8080/v1" : "https://api.example.com/v1",
                modelIdentifier: "",
                isEnabled: privacyScope == .localOnly,
                connectionStatus: .needsAttention,
                lastErrorMessage: "Enter the endpoint, model id, and optional API key before routing chat.",
                capabilities: providerRuntimeCapabilityDefaults(for: .customOpenAICompatible),
                supportsStreaming: true,
                supportsToolCalling: true
            )
        case .vercelAISDKBridge:
            return ProviderConfiguration(
                kind: .vercelAISDKBridge,
                accessMode: .aiSDKBridge,
                privacyScope: .bridgeService,
                displayName: displayName,
                endpoint: defaultProviderEndpoint(for: .vercelAISDKBridge),
                modelIdentifier: defaultProviderModelIdentifier(for: .vercelAISDKBridge),
                isEnabled: false,
                connectionStatus: .needsAttention,
                lastErrorMessage: "Run the local AI SDK bridge, then check readiness.",
                capabilities: providerRuntimeCapabilityDefaults(for: .vercelAISDKBridge),
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsStructuredOutput: true
            )
        case .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            let defaults = hostedProviderRouteDefaults(for: kind)
            return ProviderConfiguration(
                kind: kind,
                accessMode: .apiKey,
                privacyScope: privacyScope,
                displayName: displayName,
                endpoint: defaults.endpoint,
                modelIdentifier: defaults.modelIdentifier,
                isEnabled: false,
                connectionStatus: .needsAttention,
                lastErrorMessage: "Save this provider's API key in Keychain before enabling this route.",
                availableModels: defaultProviderAvailableModels(for: kind),
                capabilities: defaults.capabilities,
                supportsStreaming: defaults.capabilities.contains(.streaming),
                supportsToolCalling: defaults.capabilities.contains(.toolCalling),
                supportsEmbeddings: defaults.capabilities.contains(.embeddings),
                supportsVision: defaults.capabilities.contains(.vision),
                supportsStructuredOutput: defaults.capabilities.contains(.structuredOutput)
            )
        }
    }

    private func defaultProviderRouteDisplayName(
        kind: LLMProviderKind,
        accessMode: ProviderAccessMode,
        privacyScope: ProviderPrivacyScope
    ) -> String {
        switch kind {
        case .ollama:
            "Ollama"
        case .lmStudio:
            "LM Studio"
        case .openAI:
            "OpenAI API"
        case .anthropic:
            "Anthropic API"
        case .chatGPTCLI:
            "ChatGPT/Codex CLI"
        case .claudeCodeCLI:
            "Claude Code CLI"
        case .customOpenAICompatible:
            privacyScope == .localOnly ? "Custom Local Endpoint" : "Custom OpenAI-compatible"
        case .vercelAISDKBridge:
            "Vercel AI SDK Bridge"
        case .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            "\(kind.title) API"
        }
    }

    private func uniqueProviderDisplayName(baseName: String) -> String {
        let matchingNames = Set(providerConfigurations.map(\.displayName))
        guard matchingNames.contains(baseName) else { return baseName }

        for index in 2...200 {
            let candidate = "\(baseName) \(index)"
            if !matchingNames.contains(candidate) {
                return candidate
            }
        }

        return "\(baseName) \(UUID().uuidString.prefix(6))"
    }

    private func defaultProviderEndpoint(for kind: LLMProviderKind) -> String {
        AIKnownProviderCatalog.entry(for: kind)?.endpoint ?? ""
    }

    private func defaultProviderModelIdentifier(for kind: LLMProviderKind) -> String {
        AIKnownProviderCatalog.entry(for: kind)?.defaultModelIdentifier ?? ""
    }

    private func defaultProviderAvailableModels(for kind: LLMProviderKind) -> [String] {
        guard let entry = AIKnownProviderCatalog.entry(for: kind) else { return [] }
        if entry.requestBoundary == .localServer {
            return entry.defaultModelIdentifier.isEmpty ? [] : [entry.defaultModelIdentifier]
        }
        return entry.normalizedRecommendedModelIdentifiers
    }

    private func hostedProviderRouteDefaults(
        for kind: LLMProviderKind
    ) -> (endpoint: String, modelIdentifier: String, capabilities: [ModelCapability]) {
        guard let entry = AIKnownProviderCatalog.entry(for: kind) else {
            return ("", "", [.chat, .streaming])
        }
        return (entry.endpoint ?? "", entry.defaultModelIdentifier, entry.capabilities)
    }

    private func reconcileHostedProviderRuntimeDefaults() {
        for index in providerConfigurations.indices {
            switch providerConfigurations[index].kind {
            case .openAI, .anthropic, .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
                if providerConfigurations[index].endpoint == "https://generativelanguage.googleapis.com" {
                    providerConfigurations[index].endpoint = "https://generativelanguage.googleapis.com/v1beta/openai"
                }
                reconcileProviderCapabilities(
                    providerRuntimeCapabilityDefaults(for: providerConfigurations[index].kind),
                    toProviderAt: index
                )
            case .chatGPTCLI:
                let command = providerConfigurations[index].endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                if command == "codex" || command == "codex exec --json {stdin}" {
                    providerConfigurations[index].endpoint = "codex exec --json -"
                }
                normalizeSubscriptionCLIProvider(at: index)
            case .claudeCodeCLI:
                if providerConfigurations[index].endpoint.trimmingCharacters(in: .whitespacesAndNewlines) == "claude -p" {
                    providerConfigurations[index].endpoint = "claude -p --output-format stream-json --verbose"
                }
                normalizeSubscriptionCLIProvider(at: index)
            case .vercelAISDKBridge:
                normalizeAISDKBridgeProvider(at: index)
            case .ollama, .lmStudio, .customOpenAICompatible:
                break
            }
        }
    }

    private func providerRuntimeCapabilityDefaults(for kind: LLMProviderKind) -> [ModelCapability] {
        AIKnownProviderCatalog.entry(for: kind)?.capabilities ?? [.chat, .streaming]
    }

    private func reconcileProviderCapabilities(
        _ defaults: [ModelCapability],
        toProviderAt index: Int
    ) {
        for capability in defaults {
            appendCapability(capability, toProviderAt: index)
        }

        providerConfigurations[index].supportsStreaming = providerConfigurations[index].supportsStreaming
            || defaults.contains(.streaming)
        providerConfigurations[index].supportsToolCalling = providerConfigurations[index].supportsToolCalling
            || defaults.contains(.toolCalling)
        providerConfigurations[index].supportsEmbeddings = providerConfigurations[index].supportsEmbeddings
            || defaults.contains(.embeddings)
        providerConfigurations[index].supportsVision = providerConfigurations[index].supportsVision
            || defaults.contains(.vision)
        providerConfigurations[index].supportsStructuredOutput = providerConfigurations[index].supportsStructuredOutput
            || defaults.contains(.structuredOutput)
    }

    private func normalizeSubscriptionCLIProvider(at index: Int) {
        providerConfigurations[index].capabilities.removeAll { capability in
            capability != .chat && capability != .streaming
        }
        appendCapability(.chat, toProviderAt: index)
        appendCapability(.streaming, toProviderAt: index)
        providerConfigurations[index].supportsStreaming = true
        providerConfigurations[index].supportsToolCalling = false
        providerConfigurations[index].supportsEmbeddings = false
        providerConfigurations[index].supportsVision = false
        providerConfigurations[index].supportsStructuredOutput = false
    }

    private func normalizeAISDKBridgeProvider(at index: Int) {
        providerConfigurations[index].capabilities.removeAll { capability in
            switch capability {
            case .chat, .streaming, .toolCalling, .structuredOutput:
                false
            case .embeddings, .vision, .reasoning, .webSearch, .imageGeneration, .openAICompatible, .anthropicCompatible:
                true
            }
        }
        appendCapability(.chat, toProviderAt: index)
        appendCapability(.streaming, toProviderAt: index)
        appendCapability(.toolCalling, toProviderAt: index)
        appendCapability(.structuredOutput, toProviderAt: index)
        providerConfigurations[index].supportsStreaming = true
        providerConfigurations[index].supportsToolCalling = true
        providerConfigurations[index].supportsEmbeddings = false
        providerConfigurations[index].supportsVision = false
        providerConfigurations[index].supportsStructuredOutput = true
    }

    private func appendCapability(_ capability: ModelCapability, toProviderAt index: Int) {
        guard !providerConfigurations[index].capabilities.contains(capability) else { return }
        providerConfigurations[index].capabilities.append(capability)
    }

    private func ensureDefaultAutomationsIfNeeded() {
        guard automations.isEmpty else { return }
        automations = [
            WorkspaceAutomation(
                title: "Daily research digest",
                detail: "Summarize newly captured sources locally each morning.",
                cadence: .daily,
                requiresConfirmation: false,
                linkedDestination: .library,
                linkedProjectID: selectedProjectID,
                actionKind: .generateSummary
            ),
            WorkspaceAutomation(
                title: "Transcript queue sweep",
                detail: "Find YouTube captures that still need transcript import.",
                cadence: .hourly,
                requiresConfirmation: false,
                linkedDestination: .youtube,
                linkedProjectID: selectedProjectID,
                actionKind: .importTranscript
            ),
            WorkspaceAutomation(
                title: "Weekly content calendar",
                detail: "Prepare a posting plan from local drafts and summaries.",
                cadence: .weekly,
                requiresConfirmation: true,
                linkedDestination: .calendar,
                linkedProjectID: selectedProjectID,
                actionKind: .scheduleDraft
            ),
            WorkspaceAutomation(
                title: "Local workspace scout",
                detail: "Run a permission-gated local workspace search for current project context.",
                cadence: .manual,
                requiresConfirmation: false,
                linkedDestination: .automations,
                linkedProjectID: selectedProjectID,
                actionKind: .runTool,
                action: WorkspaceAutomationAction(
                    kind: .runTool,
                    toolKind: .workspaceSearch,
                    query: "current workspace risks and next actions"
                )
            )
        ]
    }

    private func normalizeAssetPlatforms() {
        for index in libraryAssets.indices {
            if libraryAssets[index].platform == nil {
                libraryAssets[index].platform = inferPlatform(from: libraryAssets[index].sourceURL)
            }
        }
    }

    @discardableResult
    func captureWebPageKnowledgeSource(
        _ sourceID: UUID,
        now: Date = .now,
        webPageCaptureService: WebPageCaptureService = WebPageCaptureService()
    ) async -> KnowledgeSource? {
        guard let sourceIndex = knowledgeSources.firstIndex(where: { $0.id == sourceID }) else { return nil }
        let source = knowledgeSources[sourceIndex]
        guard source.kind == .webPage else { return source }

        guard !(preferences.localOnlyMode ?? true) else {
            markKnowledgeSourceCaptureFailed(
                sourceID,
                message: "Local-only mode is active. Turn it off before capturing page text from the network.",
                now: now
            )
            return knowledgeSources.first(where: { $0.id == sourceID })
        }

        guard let url = URL(string: source.location),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            markKnowledgeSourceCaptureFailed(
                sourceID,
                message: "Enter an http or https URL before capturing page text.",
                now: now
            )
            return knowledgeSources.first(where: { $0.id == sourceID })
        }

        knowledgeSources[sourceIndex].status = .indexing
        knowledgeSources[sourceIndex].lastErrorMessage = nil
        updateWebPageAssetCaptureState(
            source: source,
            transcript: TranscriptRecord(
                status: .queued,
                sourceLabel: "Web page capture",
                importedAt: now,
                updatedAt: now
            ),
            summary: "Capturing readable page text locally.",
            summaryStatus: .queued,
            notes: "Capture started from \(source.location).",
            now: now
        )

        do {
            let capturedPage = try await webPageCaptureService.capture(url: url, capturedAt: now)
            return storeCapturedWebPage(capturedPage, for: sourceID, rebuild: true)
        } catch {
            markKnowledgeSourceCaptureFailed(
                sourceID,
                message: error.localizedDescription,
                now: now
            )
            return knowledgeSources.first(where: { $0.id == sourceID })
        }
    }

    @discardableResult
    func storeCapturedWebPage(
        _ capturedPage: CapturedWebPage,
        for sourceID: UUID,
        rebuild: Bool = false
    ) -> KnowledgeSource? {
        guard let sourceIndex = knowledgeSources.firstIndex(where: { $0.id == sourceID }) else { return nil }
        let source = knowledgeSources[sourceIndex]
        guard source.kind == .webPage else { return source }

        let transcript = TranscriptRecord(
            status: .available,
            text: capturedPage.text,
            languageCode: "und",
            sourceLabel: "Web page capture",
            importedAt: capturedPage.capturedAt,
            updatedAt: capturedPage.capturedAt
        )
        let details = [
            "Captured readable page text from \(capturedPage.url.absoluteString).",
            capturedPage.statusCode.map { "HTTP status: \($0)." },
            capturedPage.contentType.map { "Content-Type: \($0)." }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        updateWebPageAssetCaptureState(
            source: source,
            capturedTitle: capturedPage.title,
            transcript: transcript,
            summary: capturedPage.excerpt,
            summaryStatus: .ready,
            notes: details,
            now: capturedPage.capturedAt
        )

        knowledgeSources[sourceIndex].status = .queued
        knowledgeSources[sourceIndex].lastErrorMessage = nil

        if rebuild {
            rebuildKnowledgeIndexManifests(onlyQueued: true, now: capturedPage.capturedAt)
        }

        return knowledgeSources.first(where: { $0.id == sourceID })
    }

    private func rebuildProjectReferences() {
        guard !projects.isEmpty else { return }

        var rebuiltProjects = projects
        for index in rebuiltProjects.indices {
            rebuiltProjects[index].assetIDs = []
            rebuiltProjects[index].draftIDs = []
            rebuiltProjects[index].calendarEntryIDs = []
            rebuiltProjects[index].automationIDs = []
            rebuiltProjects[index].updatedAt = max(rebuiltProjects[index].updatedAt, rebuiltProjects[index].lastActivityAt)
        }

        for asset in libraryAssets {
            guard let projectID = asset.projectID,
                  let index = rebuiltProjects.firstIndex(where: { $0.id == projectID }) else { continue }
            rebuiltProjects[index].assetIDs.appendUnique(asset.id)
            rebuiltProjects[index].tagNames = canonicalTags(rebuiltProjects[index].tagNames + asset.tags)
            rebuiltProjects[index].lastActivityAt = max(rebuiltProjects[index].lastActivityAt, asset.updatedAt)
        }

        for draft in drafts {
            guard let projectID = draft.projectID,
                  let index = rebuiltProjects.firstIndex(where: { $0.id == projectID }) else { continue }
            rebuiltProjects[index].draftIDs.appendUnique(draft.id)
            rebuiltProjects[index].tagNames = canonicalTags(rebuiltProjects[index].tagNames + draft.tags)
            rebuiltProjects[index].lastActivityAt = max(rebuiltProjects[index].lastActivityAt, draft.updatedAt)
        }

        for entry in calendarEntries {
            guard let projectID = entry.projectID,
                  let index = rebuiltProjects.firstIndex(where: { $0.id == projectID }) else { continue }
            rebuiltProjects[index].calendarEntryIDs.appendUnique(entry.id)
            rebuiltProjects[index].lastActivityAt = max(rebuiltProjects[index].lastActivityAt, entry.updatedAt)
        }

        for automation in automations {
            guard let projectID = automation.linkedProjectID,
                  let index = rebuiltProjects.firstIndex(where: { $0.id == projectID }) else { continue }
            rebuiltProjects[index].automationIDs.appendUnique(automation.id)
            rebuiltProjects[index].lastActivityAt = max(rebuiltProjects[index].lastActivityAt, automation.updatedAt)
        }

        projects = rebuiltProjects
    }

    private func buildTagRegistry() -> [WorkspaceTag] {
        var counts: [String: Int] = [:]
        var allTags: [String] = []
        allTags.append(contentsOf: assistantThreads.flatMap(\.tagNames))
        allTags.append(contentsOf: libraryAssets.flatMap(\.tags))
        allTags.append(contentsOf: drafts.flatMap(\.tags))
        allTags.append(contentsOf: projects.flatMap(\.tagNames))
        allTags.append(contentsOf: promptProfiles.flatMap(\.tags))
        allTags.append(contentsOf: chatTemplates.flatMap(\.tagNames))
        allTags.append(contentsOf: promptChains.flatMap(\.tagNames))
        allTags.append(contentsOf: localMemories.flatMap(\.tagNames))

        for tag in allTags.map(normalizeTag).filter({ !$0.isEmpty }) {
            counts[tag, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map { name, usageCount in
                WorkspaceTag(
                    name: name,
                    colorName: inferredTagColor(for: name),
                    usageCount: usageCount,
                    createdAt: .now,
                    updatedAt: .now
                )
            }
    }

    private func cleanSelections() {
        selectedDestination = normalizedPrimaryDestination(selectedDestination)
        preferences.defaultDestination = normalizedPrimaryDestination(preferences.defaultDestination)
        if !projects.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectID = projects.first?.id
        }
        if !drafts.contains(where: { $0.id == selectedDraftID }) {
            selectedDraftID = drafts.first?.id
        }
        if !libraryAssets.contains(where: { $0.id == selectedAssetID }) {
            selectedAssetID = libraryAssets.first?.id
        }
        if !calendarEntries.contains(where: { $0.id == selectedCalendarEntryID }) {
            selectedCalendarEntryID = calendarEntries.first?.id
        }
        if !assistantThreads.contains(where: { $0.id == selectedAssistantThreadID }) {
            selectedAssistantThreadID = assistantThreads.first?.id
        }
    }

    private func normalizeLocalMemoryState() {
        var settings = preferences.localMemory ?? LocalMemorySettings()
        settings.maximumContextMemories = max(1, min(settings.maximumContextMemories, 24))
        preferences.localMemory = settings

        let threadIDs = Set(assistantThreads.map(\.id))
        for index in localMemories.indices {
            localMemories[index].title = Self.memoryTitle(
                from: localMemories[index].title,
                fallbackText: localMemories[index].detail
            )
            localMemories[index].detail = localMemories[index].detail
                .trimmingCharacters(in: .whitespacesAndNewlines)
            localMemories[index].tagNames = canonicalTags(localMemories[index].tagNames)
            localMemories[index].useCount = max(0, localMemories[index].useCount)

            if let sourceThreadID = localMemories[index].sourceThreadID,
               !threadIDs.contains(sourceThreadID) {
                localMemories[index].sourceThreadID = nil
                localMemories[index].sourceMessageID = nil
            }
        }

        localMemories.removeAll { $0.detail.isEmpty }
    }

    private func normalizePromptProfileState() {
        var seenProfileIDs = Set<UUID>()
        promptProfiles = promptProfiles.filter { profile in
            seenProfileIDs.insert(profile.id).inserted
        }

        for index in promptProfiles.indices {
            promptProfiles[index].title = promptProfiles[index].title
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if promptProfiles[index].title.isEmpty {
                promptProfiles[index].title = "Prompt Profile"
            }

            promptProfiles[index].detail = promptProfiles[index].detail
                .trimmingCharacters(in: .whitespacesAndNewlines)
            promptProfiles[index].prompt = promptProfiles[index].prompt
                .trimmingCharacters(in: .whitespacesAndNewlines)
            promptProfiles[index].tags = canonicalTags(promptProfiles[index].tags)
        }

        if let preferredProfileID = preferences.defaultSystemPromptProfileID,
           !promptProfiles.contains(where: { $0.id == preferredProfileID }) {
            preferences.defaultSystemPromptProfileID = nil
        }

        if let preferredProfileID = preferences.defaultSystemPromptProfileID {
            for index in promptProfiles.indices {
                promptProfiles[index].isDefault = promptProfiles[index].id == preferredProfileID
            }
        } else if let defaultIndex = promptProfiles.firstIndex(where: \.isDefault) {
            let defaultID = promptProfiles[defaultIndex].id
            preferences.defaultSystemPromptProfileID = defaultID
            for index in promptProfiles.indices {
                promptProfiles[index].isDefault = index == defaultIndex
            }
        }
    }

    private func normalizeChatTemplateState() {
        var seenTemplateIDs = Set<UUID>()
        chatTemplates = chatTemplates.filter { template in
            seenTemplateIDs.insert(template.id).inserted
        }

        let knowledgeSourceIDs = Set(knowledgeSources.map(\.id))
        for index in chatTemplates.indices {
            chatTemplates[index].title = chatTemplates[index].title
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if chatTemplates[index].title.isEmpty {
                chatTemplates[index].title = "Chat Template"
            }

            chatTemplates[index].detail = chatTemplates[index].detail
                .trimmingCharacters(in: .whitespacesAndNewlines)
            chatTemplates[index].systemPrompt = chatTemplates[index].systemPrompt
                .trimmingCharacters(in: .whitespacesAndNewlines)
            chatTemplates[index].tagNames = canonicalTags(chatTemplates[index].tagNames)

            let modelIdentifier = chatTemplates[index].preferredModelIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            chatTemplates[index].preferredModelIdentifier = modelIdentifier?.isEmpty == false ? modelIdentifier : nil

            chatTemplates[index].requiredToolKinds = stableUnique(chatTemplates[index].requiredToolKinds)
            chatTemplates[index].knowledgeSourceIDs = stableUnique(chatTemplates[index].knowledgeSourceIDs)
                .filter { knowledgeSourceIDs.contains($0) }
        }
    }

    private func normalizePromptChainState() {
        var seenChainIDs = Set<UUID>()
        promptChains = promptChains.filter { chain in
            seenChainIDs.insert(chain.id).inserted
        }

        let knowledgeSourceIDs = Set(knowledgeSources.map(\.id))
        for index in promptChains.indices {
            promptChains[index].title = promptChains[index].title
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if promptChains[index].title.isEmpty {
                promptChains[index].title = "Prompt Chain"
            }

            promptChains[index].detail = promptChains[index].detail
                .trimmingCharacters(in: .whitespacesAndNewlines)
            promptChains[index].systemPrompt = promptChains[index].systemPrompt
                .trimmingCharacters(in: .whitespacesAndNewlines)
            promptChains[index].tagNames = canonicalTags(promptChains[index].tagNames)

            let modelIdentifier = promptChains[index].preferredModelIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            promptChains[index].preferredModelIdentifier = modelIdentifier?.isEmpty == false ? modelIdentifier : nil

            promptChains[index].requiredToolKinds = stableUnique(promptChains[index].requiredToolKinds)
            promptChains[index].knowledgeSourceIDs = stableUnique(promptChains[index].knowledgeSourceIDs)
                .filter { knowledgeSourceIDs.contains($0) }

            var seenStepIDs = Set<UUID>()
            promptChains[index].steps = promptChains[index].steps.filter { step in
                seenStepIDs.insert(step.id).inserted
            }

            for stepIndex in promptChains[index].steps.indices {
                promptChains[index].steps[stepIndex].title = promptChains[index].steps[stepIndex].title
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if promptChains[index].steps[stepIndex].title.isEmpty {
                    promptChains[index].steps[stepIndex].title = "Step \(stepIndex + 1)"
                }
                promptChains[index].steps[stepIndex].instruction = promptChains[index].steps[stepIndex].instruction
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                promptChains[index].steps[stepIndex].expectedOutput = promptChains[index].steps[stepIndex].expectedOutput
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func normalizePromptChainThreadState() {
        let chainsByID = Dictionary(uniqueKeysWithValues: promptChains.map { ($0.id, $0) })
        for index in assistantThreads.indices {
            guard let chainID = assistantThreads[index].promptChainID,
                  let chain = chainsByID[chainID] else {
                assistantThreads[index].promptChainID = nil
                assistantThreads[index].activePromptChainStepID = nil
                assistantThreads[index].completedPromptChainStepIDs = []
                continue
            }

            let enabledSteps = chain.enabledSteps
            let enabledStepIDs = Set(enabledSteps.map(\.id))
            assistantThreads[index].completedPromptChainStepIDs = stableUnique(
                assistantThreads[index].completedPromptChainStepIDs
            )
            .filter { enabledStepIDs.contains($0) }

            let completedStepIDs = Set(assistantThreads[index].completedPromptChainStepIDs)
            if let activeStepID = assistantThreads[index].activePromptChainStepID,
               enabledStepIDs.contains(activeStepID),
               !completedStepIDs.contains(activeStepID) {
                continue
            }

            assistantThreads[index].activePromptChainStepID = enabledSteps
                .first { !completedStepIDs.contains($0.id) }?
                .id
        }
    }

    private func normalizeModelPresetState() {
        var seenPresetIDs = Set<UUID>()
        modelPresets = modelPresets.filter { preset in
            seenPresetIDs.insert(preset.id).inserted
        }

        for index in modelPresets.indices {
            modelPresets[index].title = modelPresets[index].title
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if modelPresets[index].title.isEmpty {
                modelPresets[index].title = "Model Preset"
            }
            modelPresets[index].modelIdentifier = modelPresets[index].modelIdentifier
                .trimmingCharacters(in: .whitespacesAndNewlines)
            modelPresets[index].capabilities = Self.sortedUniqueCapabilities(modelPresets[index].capabilities)
        }

        if let defaultPresetID = preferences.defaultModelPresetID,
           !modelPresets.contains(where: { $0.id == defaultPresetID }) {
            preferences.defaultModelPresetID = nil
        }

        if let defaultPresetID = preferences.defaultModelPresetID {
            for index in modelPresets.indices {
                modelPresets[index].isDefault = modelPresets[index].id == defaultPresetID
            }
        } else if let defaultIndex = modelPresets.firstIndex(where: \.isDefault) {
            let defaultID = modelPresets[defaultIndex].id
            preferences.defaultModelPresetID = defaultID
            for index in modelPresets.indices {
                modelPresets[index].isDefault = index == defaultIndex
            }
        }
    }

    private func normalizeProjectAIProfileState() {
        let providerIDs = Set(providerConfigurations.map(\.id))
        let promptProfileIDs = Set(promptProfiles.map(\.id))
        let modelPresetIDs = Set(modelPresets.map(\.id))
        let knowledgeSourceIDs = Set(knowledgeSources.map(\.id))
        let toolConfigurationIDs = Set(toolConfigurations.map(\.id))

        for index in projects.indices {
            projects[index].aiProfile.customSystemPrompt = projects[index].aiProfile.customSystemPrompt
                .trimmingCharacters(in: .whitespacesAndNewlines)
            projects[index].aiProfile.indexingRuleNotes = projects[index].aiProfile.indexingRuleNotes
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let providerID = projects[index].aiProfile.preferredProviderID,
               !providerIDs.contains(providerID) {
                projects[index].aiProfile.preferredProviderID = nil
            }

            if let profileID = projects[index].aiProfile.defaultSystemPromptProfileID,
               !promptProfileIDs.contains(profileID) {
                projects[index].aiProfile.defaultSystemPromptProfileID = nil
            }

            if let presetID = projects[index].aiProfile.defaultModelPresetID,
               !modelPresetIDs.contains(presetID) {
                projects[index].aiProfile.defaultModelPresetID = nil
            }

            projects[index].aiProfile.knowledgeSourceIDs = stableUnique(projects[index].aiProfile.knowledgeSourceIDs)
                .filter { knowledgeSourceIDs.contains($0) }
            projects[index].aiProfile.toolConfigurationIDs = stableUnique(projects[index].aiProfile.toolConfigurationIDs)
                .filter { toolConfigurationIDs.contains($0) }
        }
    }

    private func normalizedPrimaryDestination(_ destination: WorkspaceDestination) -> WorkspaceDestination {
        switch destination {
        case .home, .chats:
            return .home
        default:
            return .home
        }
    }

    private func pruneChatOrganizationState() {
        let threadIDs = Set(assistantThreads.map(\.id))
        let folderIDs = Set(chatFolders.map(\.id))
        let knowledgeSourceIDs = Set(knowledgeSources.map(\.id))
        let legacyArchivedThreadIDs = Set(
            assistantThreads
                .filter(\.isArchived)
                .map(\.id)
        )
        archivedAssistantThreadIDs = archivedAssistantThreadIDs
            .union(legacyArchivedThreadIDs)
            .intersection(threadIDs)
        for index in assistantThreads.indices {
            assistantThreads[index].isArchived = archivedAssistantThreadIDs.contains(assistantThreads[index].id)
            if let folderID = assistantThreads[index].folderID,
               !folderIDs.contains(folderID) {
                assistantThreads[index].folderID = nil
            }
            assistantThreads[index].knowledgeSourceIDs = stableUnique(assistantThreads[index].knowledgeSourceIDs)
                .filter { knowledgeSourceIDs.contains($0) }
        }
        pinnedMessages.removeAll { pin in
            guard threadIDs.contains(pin.threadID),
                  let thread = assistantThreads.first(where: { $0.id == pin.threadID }) else {
                return true
            }
            return !thread.messages.contains(where: { $0.id == pin.messageID })
        }
    }

    private func attachAssetToCurrentProjectIfPossible(assetID: UUID) {
        guard let assetIndex = libraryAssets.firstIndex(where: { $0.id == assetID }) else { return }
        guard let projectID = libraryAssets[assetIndex].projectID ?? selectedProjectID else { return }
        libraryAssets[assetIndex].projectID = projectID

        if let projectIndex = projects.firstIndex(where: { $0.id == projectID }) {
            projects[projectIndex].assetIDs.appendUnique(assetID)
            projects[projectIndex].tagNames = canonicalTags(projects[projectIndex].tagNames + libraryAssets[assetIndex].tags)
            projects[projectIndex].lastActivityAt = .now
            projects[projectIndex].updatedAt = .now
        }
    }

    private func attachDraftToCurrentProjectIfPossible(draftID: UUID, projectID: UUID?) {
        guard let draftIndex = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        let resolvedProjectID = projectID ?? drafts[draftIndex].projectID ?? selectedProjectID
        drafts[draftIndex].projectID = resolvedProjectID

        guard let resolvedProjectID,
              let projectIndex = projects.firstIndex(where: { $0.id == resolvedProjectID }) else { return }

        projects[projectIndex].draftIDs.appendUnique(draftID)
        projects[projectIndex].tagNames = canonicalTags(projects[projectIndex].tagNames + drafts[draftIndex].tags)
        projects[projectIndex].lastActivityAt = .now
        projects[projectIndex].updatedAt = .now
    }

    private func adjustPendingImportCount(for platform: ContentPlatform?, delta: Int) {
        guard let platform else { return }
        guard let accountIndex = accounts.firstIndex(where: { $0.platform == platform }) else { return }
        accounts[accountIndex].pendingImportCount = max(0, accounts[accountIndex].pendingImportCount + delta)
        accounts[accountIndex].syncStatus = accounts[accountIndex].pendingImportCount == 0 ? .idle : .queued
        accounts[accountIndex].lastSyncedAt = .now
    }

    private func recordLocalAction(
        kind: LocalActionKind,
        title: String,
        detail: String,
        status: LocalActionStatus,
        destination: WorkspaceDestination,
        relatedProjectID: UUID? = nil,
        relatedDraftID: UUID? = nil,
        relatedAssetID: UUID? = nil,
        automationID: UUID? = nil,
        requiresConfirmation: Bool = false,
        completedAt: Date? = nil
    ) {
        let action = LocalActionRecord(
            kind: kind,
            title: title,
            detail: detail,
            status: status,
            destination: destination,
            relatedProjectID: relatedProjectID ?? selectedProjectID,
            relatedDraftID: relatedDraftID ?? selectedDraftID,
            relatedAssetID: relatedAssetID ?? selectedAssetID,
            automationID: automationID,
            requiresConfirmation: requiresConfirmation,
            createdAt: .now,
            completedAt: completedAt
        )
        localActionHistory.insert(action, at: 0)
        if localActionHistory.count > 80 {
            localActionHistory.removeLast(localActionHistory.count - 80)
        }
    }

    private func resolveMessageLocation(
        _ messageID: UUID,
        in threadID: UUID? = nil
    ) -> (threadIndex: Int, messageIndex: Int)? {
        let threadIndices: [Int]
        if let threadID,
           let threadIndex = assistantThreads.firstIndex(where: { $0.id == threadID }) {
            threadIndices = [threadIndex]
        } else if let selectedAssistantThreadID,
                  let selectedIndex = assistantThreads.firstIndex(where: { $0.id == selectedAssistantThreadID }) {
            threadIndices = [selectedIndex] + assistantThreads.indices.filter { $0 != selectedIndex }
        } else {
            threadIndices = Array(assistantThreads.indices)
        }

        for threadIndex in threadIndices {
            if let messageIndex = assistantThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }) {
                return (threadIndex, messageIndex)
            }
        }

        return nil
    }

    private func chatSearchResult(
        thread: AssistantThread,
        message: AssistantMessage,
        query: String,
        matchKind: AssistantChatSearchMatchKind,
        citationSnippet: String? = nil
    ) -> AssistantChatSearchResult {
        AssistantChatSearchResult(
            id: "\(matchKind.rawValue)-\(thread.id.uuidString)-\(message.id.uuidString)",
            threadID: thread.id,
            messageID: message.id,
            title: thread.title,
            snippet: Self.snippet(from: citationSnippet ?? message.text, matching: query),
            matchKind: matchKind,
            role: message.role,
            createdAt: message.createdAt,
            isArchived: archivedAssistantThreadIDs.contains(thread.id),
            isPinned: thread.isPinned || pinnedMessages.contains { $0.threadID == thread.id && $0.messageID == message.id }
        )
    }

    private func indexOfAsset(_ assetID: UUID?) -> Int? {
        let resolvedID = assetID ?? selectedAssetID
        guard let resolvedID else { return nil }
        return libraryAssets.firstIndex(where: { $0.id == resolvedID })
    }

    private func buildDraftBody(from asset: LibraryAsset, outline: [String]) -> String {
        let sourceURL = asset.sourceURL?.absoluteString ?? "Local source"
        let bullets = outline.isEmpty ? generatedBulletPoints(for: asset) : outline
        let outlineSection = bullets.map { "- \($0)" }.joined(separator: "\n")

        return """
        # \(asset.title)

        Source: \(sourceURL)

        ## Working Summary
        \(asset.summary.isEmpty ? "Add a summary after review." : asset.summary)

        ## Structure
        \(outlineSection)

        ## Source Notes
        \(asset.notes.isEmpty ? "No additional local notes yet." : asset.notes)

        ## Transcript Excerpt
        \(asset.transcript?.text.prefix(220) ?? "")
        """
    }

    private func generatedSummaryText(for asset: LibraryAsset) -> String {
        if !asset.summary.isEmpty, asset.summaryStatus == .ready {
            return asset.summary
        }

        if let transcript = asset.transcript, !transcript.text.isEmpty {
            let sentence = transcript.text
                .split(whereSeparator: \.isNewline)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return sentence?.isEmpty == false
                ? sentence!
                : "Local summary prepared from transcript context for \(asset.title)."
        }

        if !asset.notes.isEmpty {
            return asset.notes
        }

        return "Local summary prepared for \(asset.title). Review tags and source notes before publishing."
    }

    private func generatedBulletPoints(for asset: LibraryAsset) -> [String] {
        if let record = asset.summaryRecords.first, !record.bulletPoints.isEmpty {
            return record.bulletPoints
        }

        var bullets: [String] = []
        if let platform = asset.platform ?? inferPlatform(from: asset.sourceURL) {
            bullets.append("Adapt the angle for \(platform.rawValue.capitalized).")
        }
        if !asset.tags.isEmpty {
            bullets.append("Preserve tags: \(canonicalTags(asset.tags).joined(separator: ", ")).")
        }
        if let transcript = asset.transcript, transcript.status == .available {
            bullets.append("Use transcript-backed quotes and timestamps where helpful.")
        }
        bullets.append("Convert the source into a locally reviewed draft before any external action.")
        return bullets
    }

    private func draftRecommendation(for asset: LibraryAsset) -> String {
        if asset.draftID == nil {
            return "create a linked draft next"
        }
        if currentDraft?.scheduledFor == nil {
            return "schedule the linked draft on the local calendar"
        }
        return "review the scheduled draft and confirm external actions only when ready"
    }

    private func inferPlatform(from url: URL?) -> ContentPlatform? {
        let value = url?.absoluteString.lowercased() ?? ""
        if value.contains("youtube.com") || value.contains("youtu.be") {
            return .youtube
        }
        if value.contains("x.com") || value.contains("twitter.com") {
            return .x
        }
        if value.hasPrefix("flannel://") {
            return .internalNote
        }
        return nil
    }

    private func inferredCaptureTitle(for url: URL?) -> String {
        guard let platform = inferPlatform(from: url) else {
            return "Manual web capture"
        }

        switch platform {
        case .youtube:
            return "Manual YouTube capture"
        case .x:
            return "Manual X capture"
        case .internalNote:
            return "Manual local note"
        }
    }

    private func defaultTags(for platform: ContentPlatform?, url: URL?) -> [String] {
        var values: [String] = []
        if let platform {
            values.append(platform.rawValue)
        }
        if url?.absoluteString.localizedCaseInsensitiveContains("developer") == true {
            values.append("reference")
        }
        return values
    }

    private func canonicalTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for value in values.map(normalizeTag) where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            ordered.append(value)
        }

        return ordered
    }

    private func stableUnique<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen = Set<Value>()
        return values.filter { seen.insert($0).inserted }
    }

    private func validatedKnowledgeSourceIDs(_ ids: [UUID]) -> [UUID] {
        let availableIDs = Set(knowledgeSources.map(\.id))
        return stableUnique(ids).filter { availableIDs.contains($0) }
    }

    private func knowledgeSourcesForScope(_ sourceIDs: Set<UUID>?) -> [KnowledgeSource] {
        knowledgeSources.filter { source in
            sourceIDs?.contains(source.id) ?? true
        }
    }

    private func normalizeTag(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    private func inferredTagColor(for tag: String) -> String {
        switch tag {
        case "youtube":
            "red"
        case "x":
            "blue"
        case "privacy", "local-ai":
            "green"
        case "launch", "product":
            "orange"
        default:
            "gray"
        }
    }

    private func defaultScheduleDate(from date: Date) -> Date {
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: nextDay) ?? nextDay
    }

    private func nextRunDate(for cadence: AutomationCadence, from date: Date) -> Date? {
        let calendar = Calendar.current
        switch cadence {
        case .manual:
            return nil
        case .hourly:
            return calendar.date(byAdding: .hour, value: 1, to: date)
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        }
    }

    private func appendInlineInput(
        _ inputs: inout [LocalKnowledgeDocumentInput],
        source: KnowledgeSource,
        text: String
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputs.append(.knowledgeSource(source, text: trimmed))
    }

    private func localKnowledgeDocumentInputs(
        for source: KnowledgeSource,
        excludingPrompt prompt: String? = nil
    ) -> [LocalKnowledgeDocumentInput] {
        var inputs: [LocalKnowledgeDocumentInput] = []
        let trimmedPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch source.kind {
        case .chatHistory:
            inputs.append(
                contentsOf: assistantThreads.compactMap { thread -> LocalKnowledgeDocumentInput? in
                    let messages = thread.messages.compactMap { message -> String? in
                        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty,
                              text != trimmedPrompt else { return nil }
                        return "\(message.role.rawValue): \(text)"
                    }
                    guard !messages.isEmpty else { return nil }
                    let title = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayTitle = title.isEmpty ? "Untitled Chat" : title
                    let location = "flannel://chat-history/thread/\(thread.id.uuidString.lowercased())"
                    let text = """
                    Thread: \(displayTitle)
                    Thread ID: \(thread.id.uuidString)

                    \(messages.joined(separator: "\n"))
                    """
                    return LocalKnowledgeDocumentInput(
                        title: "Chat: \(displayTitle)",
                        kind: source.kind,
                        location: location,
                        knowledgeSourceID: source.id,
                        storage: .inlineText(text)
                    )
                }
            )

        case .workspaceNotes:
            appendInlineInput(&inputs, source: source, text: workspaceKnowledgeText())

        case .file:
            if let url = readableFileURL(from: source.location) {
                inputs.append(.file(url, title: source.title, kind: .file, knowledgeSourceID: source.id))
            }

        case .folder, .codeRepository:
            inputs.append(contentsOf: readableFileInputs(for: source))

        case .webPage:
            appendInlineInput(&inputs, source: source, text: localWebPageText(for: source))
        }

        return inputs
    }

    private func embeddingProviderKind(for source: KnowledgeSource) -> LLMProviderKind? {
        let model = source.embeddingModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model?.isEmpty == false else { return nil }

        if let provider = embeddingProvider(for: source, modelIdentifier: model) {
            return provider.kind
        }

        return providerConfigurations.first(where: { $0.supportsEmbeddings && $0.isLocalPreferred })?.kind
            ?? providerConfigurations.first(where: { $0.supportsEmbeddings })?.kind
    }

    private func embeddingProvider(
        for _: KnowledgeSource,
        modelIdentifier rawModelIdentifier: String?
    ) -> ProviderConfiguration? {
        guard let modelIdentifier = rawModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !modelIdentifier.isEmpty,
              modelIdentifier != LocalEmbeddingService.deterministicModelIdentifier else {
            return nil
        }

        return providerConfigurations.first { provider in
            isProviderRunnableForEmbeddings(provider, modelIdentifier: modelIdentifier)
        }
    }

    private func embeddingProvider(
        modelIdentifier: String,
        providerKind: LLMProviderKind?
    ) -> ProviderConfiguration? {
        providerConfigurations.first { provider in
            if let providerKind,
               provider.kind != providerKind {
                return false
            }
            return isProviderRunnableForEmbeddings(provider, modelIdentifier: modelIdentifier)
        } ?? providerConfigurations.first { provider in
            isProviderRunnableForEmbeddings(provider, modelIdentifier: modelIdentifier)
        }
    }

    private func isProviderRunnableForEmbeddings(
        _ provider: ProviderConfiguration,
        modelIdentifier: String
    ) -> Bool {
        guard provider.supportsEmbeddings,
              provider.isEnabled,
              ProviderSetupService.shared.isEligibleForActivation(provider, preferences: preferences),
              ProviderSetupService.shared.report(for: provider, preferences: preferences).hasBlockingIssues == false else {
            return false
        }

        if provider.accessMode == .localServer {
            let discoveredModels = discoveredModelsForLocalProvider(kind: provider.kind, endpoint: provider.endpoint)
            if !discoveredModels.isEmpty {
                return discoveredModels.contains { model in
                    model.name == modelIdentifier && model.capabilities.contains(.embeddings)
                }
            }
        }

        return provider.modelIdentifier == modelIdentifier
            || provider.availableModels.contains(modelIdentifier)
            || provider.discoveredModelNames.contains(modelIdentifier)
            || catalogEmbeddingModelIdentifiers(for: provider).contains(modelIdentifier)
    }

    private func queryVector(
        for query: String,
        modelIdentifier: String,
        vectorDimension: Int,
        embeddingProviderKind: LLMProviderKind?,
        vectorStore: LocalKnowledgeVectorStore
    ) async throws -> [Double] {
        if modelIdentifier == LocalEmbeddingService.deterministicModelIdentifier {
            return LocalEmbeddingService().deterministicLocalVector(
                for: query,
                dimensions: vectorDimension
            )
        }

        guard let provider = embeddingProvider(
            modelIdentifier: modelIdentifier,
            providerKind: embeddingProviderKind
        ) else {
            throw WorkspaceKnowledgeEmbeddingError.missingProvider(modelIdentifier)
        }

        let result = try await vectorStore.providerEmbeddingGenerator(
            provider,
            modelIdentifier,
            [query]
        )
        guard let vector = result.vectors.first,
              vector.count == vectorDimension else {
            throw LocalKnowledgeVectorStoreError.inconsistentEmbeddingDimensions
        }
        return vector
    }

    private func resolvedKnowledgeSource(for citation: AIChatCitation) -> KnowledgeSource? {
        if let sourceID = citation.indexID,
           let source = knowledgeSources.first(where: { $0.id == sourceID }) {
            return source
        }

        let citationTitle = Self.knowledgeCitationSourceTitle(from: citation.title)
        return knowledgeSources.first {
            $0.title.localizedCaseInsensitiveCompare(citationTitle) == .orderedSame
        }
    }

    private func resolvedKnowledgeManifest(
        for citation: AIChatCitation,
        source: KnowledgeSource?
    ) -> KnowledgeIndexManifest? {
        if let source {
            return knowledgeIndexManifests.first {
                $0.sourceID == source.id || $0.id == source.id
            }
        }

        if let sourceID = citation.indexID,
           let manifest = knowledgeIndexManifests.first(where: {
               $0.sourceID == sourceID || $0.id == sourceID
           }) {
            return manifest
        }

        let citationTitle = Self.knowledgeCitationSourceTitle(from: citation.title)
        return knowledgeIndexManifests.first {
            $0.title.localizedCaseInsensitiveCompare(citationTitle) == .orderedSame
        }
    }

    private static func knowledgeCitationSourceTitle(from title: String) -> String {
        guard let range = title.range(of: " • chunk ", options: .backwards) else {
            return title
        }
        return String(title[..<range.lowerBound])
    }

    private func storageLocation(forKnowledgeSource source: KnowledgeSource) -> String {
        let sourceSlug = source.id.uuidString.lowercased()
        return "\(preferences.localStorageLabel ?? "~/Library/Application Support/Flannel")/Knowledge/\(sourceSlug).json"
    }

    private func normalizedKnowledgeSourceLocation(_ rawValue: String, kind: KnowledgeSourceKind) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        switch kind {
        case .webPage:
            return URL(string: trimmed)?.absoluteString ?? trimmed
        case .file, .folder, .codeRepository:
            return (trimmed as NSString).expandingTildeInPath
        case .chatHistory, .workspaceNotes:
            return trimmed
        }
    }

    private func defaultKnowledgeSourceTitle(kind: KnowledgeSourceKind, location: String) -> String {
        switch kind {
        case .folder:
            return fallbackFileTitle(location: location, fallback: "Local folder")
        case .file:
            return fallbackFileTitle(location: location, fallback: "Local file")
        case .webPage:
            guard let url = URL(string: location),
                  let host = url.host(percentEncoded: false),
                  !host.isEmpty else {
                return "Web page"
            }
            let lastPath = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            return lastPath.isEmpty ? host : "\(host) \(lastPath)"
        case .chatHistory:
            return "Chat history"
        case .workspaceNotes:
            return "Workspace notes"
        case .codeRepository:
            return fallbackFileTitle(location: location, fallback: "Code repository")
        }
    }

    private func fallbackFileTitle(location: String, fallback: String) -> String {
        let path = (location as NSString).expandingTildeInPath
        let title = URL(fileURLWithPath: path).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? fallback : title
    }

    private func ensureLocalWebPageCaptureIfNeeded(
        title: String,
        location: String,
        kind: KnowledgeSourceKind
    ) {
        guard kind == .webPage,
              let url = URL(string: location),
              libraryAssets.contains(where: {
                  $0.sourceURL?.absoluteString == location || $0.sourceIdentifier == location
              }) == false else { return }

        let platform = inferPlatform(from: url)
        let asset = LibraryAsset(
            title: title,
            kind: .link,
            platform: platform,
            sourceURL: url,
            summary: "User-added knowledge source. Page content remains local until an import or reader tool captures it.",
            summaryStatus: .missing,
            tags: canonicalTags(defaultTags(for: platform, url: url) + ["knowledge", "manual"]),
            projectID: selectedProjectID,
            notes: "Queued for local knowledge indexing from \(location)."
        )

        libraryAssets.insert(asset, at: 0)
        attachAssetToCurrentProjectIfPossible(assetID: asset.id)
    }

    private func updateWebPageAssetCaptureState(
        source: KnowledgeSource,
        capturedTitle: String? = nil,
        transcript: TranscriptRecord,
        summary: String,
        summaryStatus: SummaryStatus,
        notes: String,
        now: Date
    ) {
        let url = URL(string: source.location)
        let title = capturedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let assetTitle = title?.isEmpty == false ? title ?? source.title : source.title

        if let assetIndex = libraryAssets.firstIndex(where: {
            $0.sourceURL?.absoluteString == source.location || $0.sourceIdentifier == source.location
        }) {
            libraryAssets[assetIndex].title = assetTitle
            libraryAssets[assetIndex].kind = .link
            libraryAssets[assetIndex].sourceURL = url ?? libraryAssets[assetIndex].sourceURL
            libraryAssets[assetIndex].sourceIdentifier = source.location
            libraryAssets[assetIndex].summary = summary
            libraryAssets[assetIndex].summaryStatus = summaryStatus
            libraryAssets[assetIndex].transcript = transcript
            libraryAssets[assetIndex].notes = notes
            libraryAssets[assetIndex].updatedAt = now
            libraryAssets[assetIndex].capturedAt = now
            libraryAssets[assetIndex].tags = canonicalTags(
                libraryAssets[assetIndex].tags + ["knowledge", "web-capture"]
            )
            return
        }

        let platform = inferPlatform(from: url)
        let asset = LibraryAsset(
            title: assetTitle,
            kind: .link,
            platform: platform,
            sourceURL: url,
            sourceIdentifier: source.location,
            summary: summary,
            summaryStatus: summaryStatus,
            tags: canonicalTags(defaultTags(for: platform, url: url) + ["knowledge", "web-capture"]),
            projectID: selectedProjectID,
            updatedAt: now,
            capturedAt: now,
            transcript: transcript,
            notes: notes
        )

        libraryAssets.insert(asset, at: 0)
        attachAssetToCurrentProjectIfPossible(assetID: asset.id)
    }

    private func markKnowledgeSourceCaptureFailed(
        _ sourceID: UUID,
        message: String,
        now: Date
    ) {
        guard let sourceIndex = knowledgeSources.firstIndex(where: { $0.id == sourceID }) else { return }
        let source = knowledgeSources[sourceIndex]
        knowledgeSources[sourceIndex].status = .failed
        knowledgeSources[sourceIndex].documentCount = 0
        knowledgeSources[sourceIndex].chunkCount = 0
        knowledgeSources[sourceIndex].embeddingRecordCount = 0
        knowledgeSources[sourceIndex].vectorDimension = nil
        knowledgeSources[sourceIndex].lastIndexedAt = now
        knowledgeSources[sourceIndex].lastErrorMessage = message

        updateWebPageAssetCaptureState(
            source: source,
            transcript: TranscriptRecord(
                status: .failed,
                sourceLabel: "Web page capture",
                importedAt: now,
                updatedAt: now,
                lastErrorMessage: message
            ),
            summary: message,
            summaryStatus: .failed,
            notes: "Capture failed for \(source.location).",
            now: now
        )
    }

    private func workspaceKnowledgeText() -> String {
        var sections: [String] = []

        sections.append(
            projects.map { project in
                """
                Project: \(project.title)
                Status: \(project.status.rawValue)
                Summary: \(project.summary)
                Notes: \(project.notes)
                Tags: \(project.tagNames.joined(separator: ", "))
                """
            }
            .joined(separator: "\n\n")
        )

        sections.append(
            drafts.map { draft in
                """
                Draft: \(draft.title)
                Status: \(draft.status.rawValue)
                Summary: \(draft.summary)
                Outline: \(draft.outline.joined(separator: "; "))
                Body: \(draft.body)
                Publish notes: \(draft.publishNotes)
                Tags: \(draft.tags.joined(separator: ", "))
                """
            }
            .joined(separator: "\n\n")
        )

        sections.append(
            libraryAssets.map { asset in
                """
                Source: \(asset.title)
                Kind: \(asset.kind.rawValue)
                URL: \(asset.sourceURL?.absoluteString ?? asset.sourceIdentifier ?? "")
                Summary: \(asset.summary)
                Transcript: \(asset.transcript?.text ?? "")
                Notes: \(asset.notes)
                Tags: \(asset.tags.joined(separator: ", "))
                """
            }
            .joined(separator: "\n\n")
        )

        sections.append(
            promptProfiles.map { profile in
                """
                Prompt profile: \(profile.title)
                Detail: \(profile.detail)
                Prompt: \(profile.prompt)
                Tags: \(profile.tags.joined(separator: ", "))
                """
            }
            .joined(separator: "\n\n")
        )

        sections.append(
            chatTemplates.map { template in
                """
                Chat template: \(template.title)
                Detail: \(template.detail)
                Route: \(template.routeSummary)
                Tools: \(template.requiredToolKinds.map(\.rawValue).joined(separator: ", "))
                Tags: \(template.tagNames.joined(separator: ", "))
                """
            }
            .joined(separator: "\n\n")
        )

        sections.append(
            promptChains.map { chain in
                let steps = chain.steps.enumerated().map { offset, step in
                    "\(offset + 1). \(step.title): \(step.instruction)"
                }
                .joined(separator: "\n")
                return """
                Prompt chain: \(chain.title)
                Detail: \(chain.detail)
                Route: \(chain.routeSummary)
                Tools: \(chain.requiredToolKinds.map(\.rawValue).joined(separator: ", "))
                Tags: \(chain.tagNames.joined(separator: ", "))
                Steps:
                \(steps)
                """
            }
            .joined(separator: "\n\n")
        )

        sections.append(
            toolConfigurations.map { tool in
                """
                Tool: \(tool.title)
                Detail: \(tool.detail)
                Policy: \(tool.permissionPolicy.rawValue)
                Enabled: \(tool.isEnabled)
                """
            }
            .joined(separator: "\n\n")
        )

        return sections
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private func localWebPageText(for source: KnowledgeSource) -> String {
        libraryAssets
            .filter { $0.sourceURL?.absoluteString == source.location || $0.sourceIdentifier == source.location }
            .compactMap { asset -> String? in
                guard let transcript = asset.transcript,
                      transcript.status == .available else { return nil }
                let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return """
                Web source: \(asset.title)
                URL: \(asset.sourceURL?.absoluteString ?? source.location)
                Summary: \(asset.summary)
                Captured page text:
                \(text)
                """
            }
            .joined(separator: "\n\n")
    }

    private func capturedWebPageAssetIndex(for source: KnowledgeSource) -> Int? {
        libraryAssets.firstIndex {
            $0.sourceURL?.absoluteString == source.location || $0.sourceIdentifier == source.location
        }
    }

    private func webPageKnowledgeFreshnessDate(for source: KnowledgeSource) -> Date? {
        let captureDate = capturedWebPageAssetIndex(for: source).flatMap {
            usableWebPageCaptureDate(for: libraryAssets[$0])
        }
        let indexDate = webPageKnowledgeIndexDate(for: source)
        return [captureDate, indexDate].compactMap { $0 }.min()
    }

    private func webPageKnowledgeIndexDate(for source: KnowledgeSource) -> Date? {
        let manifestDate = knowledgeIndexManifests.first {
            $0.sourceID == source.id || $0.id == source.id
        }?.lastBuiltAt
        return [source.lastIndexedAt, manifestDate].compactMap { $0 }.max()
    }

    private func usableWebPageCaptureDate(for asset: LibraryAsset) -> Date? {
        guard let transcript = asset.transcript,
              transcript.status == .available,
              !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return max(asset.capturedAt, transcript.updatedAt)
    }

    private func webPageStalenessNotes(
        existingNotes: String,
        capturedAt: Date,
        now: Date
    ) -> String {
        let marker = "Capture marked stale"
        let freshnessNote = "\(marker) \(now.formatted(date: .abbreviated, time: .shortened)); previous capture \(capturedAt.formatted(date: .abbreviated, time: .shortened))."
        let filteredNotes = existingNotes
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix(marker) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !filteredNotes.isEmpty else { return freshnessNote }
        return "\(filteredNotes)\n\(freshnessNote)"
    }

    private func readableFileURL(from rawValue: String) -> URL? {
        let expandedPath = (rawValue as NSString).expandingTildeInPath
        let url: URL
        if let parsedURL = URL(string: expandedPath),
           parsedURL.isFileURL {
            url = parsedURL
        } else {
            url = URL(fileURLWithPath: expandedPath)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: url.path),
              isWithinKnowledgeFileSizeLimit(url),
              isSupportedKnowledgeFile(url) else {
            return nil
        }
        return url.standardizedFileURL
    }

    private func readableFileInputs(for source: KnowledgeSource) -> [LocalKnowledgeDocumentInput] {
        let expandedPath = (source.location as NSString).expandingTildeInPath
        let rootURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isReadableKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            return []
        }

        let exclusionRules = combinedExclusionRules(for: source)
        var fileURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            if resourceValues?.isDirectory == true {
                if isExcluded(fileURL, by: exclusionRules) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard !isExcluded(fileURL, by: exclusionRules),
                  isSupportedKnowledgeFile(fileURL),
                  isWithinKnowledgeFileSizeLimit(fileURL, resourceValues: resourceValues),
                  resourceValues?.isRegularFile == true,
                  FileManager.default.isReadableFile(atPath: fileURL.path) else {
                continue
            }

            fileURLs.append(fileURL.standardizedFileURL)
        }

        return fileURLs
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .prefix(Self.maximumKnowledgeDirectoryFiles)
            .map {
                .file(
                    $0,
                    title: relativeKnowledgeTitle(for: $0, rootURL: rootURL),
                    kind: source.kind == .codeRepository ? .codeRepository : .file,
                    knowledgeSourceID: source.id
                )
            }
    }

    private func combinedExclusionRules(for source: KnowledgeSource) -> [String] {
        Array(Self.defaultKnowledgeDirectoryExclusions)
            + Self.defaultKnowledgeFileExclusions
            + source.exclusionRules
    }

    private func isExcluded(_ fileURL: URL, by rules: [String]) -> Bool {
        let path = fileURL.path.lowercased()
        let pathComponents = fileURL.pathComponents.map { $0.lowercased() }
        return rules
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .contains { rule in
                let normalizedRule = rule.replacingOccurrences(of: "*", with: "")
                return pathComponents.contains(rule) || path.contains(normalizedRule)
            }
    }

    private func isWithinKnowledgeFileSizeLimit(
        _ fileURL: URL,
        resourceValues: URLResourceValues? = nil
    ) -> Bool {
        let values = resourceValues ?? (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))
        guard let fileSize = values?.fileSize else {
            return false
        }
        return fileSize <= Self.maximumKnowledgeFileBytes
    }

    private func relativeKnowledgeTitle(for fileURL: URL, rootURL: URL) -> String {
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        let filePath = fileURL.path
        guard filePath.hasPrefix(rootPath) else {
            return fileURL.lastPathComponent
        }
        let relativePath = String(filePath.dropFirst(rootPath.count))
        return relativePath.isEmpty ? fileURL.lastPathComponent : relativePath
    }

    private func isSupportedKnowledgeFile(_ url: URL) -> Bool {
        let allowedExtensions: Set<String> = [
            "txt", "md", "markdown", "json", "csv", "html", "htm", "pdf", "docx",
            "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs",
            "java", "kt", "c", "cc", "cpp", "h", "hpp", "m", "mm", "sh",
            "zsh", "yaml", "yml", "toml", "xml"
        ]
        return allowedExtensions.contains(url.pathExtension.lowercased())
    }

    private func defaultToolQuery(for tool: ToolConfiguration) -> String {
        let candidates = [
            searchText,
            currentDraft?.title,
            currentProject?.title,
            currentLibraryAsset?.title,
            tool.kind == .ragRetrieval ? "current local knowledge" : nil
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "current workspace"
    }

    private func normalizedToolQuery(for tool: ToolConfiguration, rawQuery: String) -> String {
        let trimmedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedQuery.isEmpty ? defaultToolQuery(for: tool) : trimmedQuery
    }

    private func recordToolExecutionResult(_ result: LocalToolExecutionResult) {
        toolExecutionResults.insert(result, at: 0)
        if toolExecutionResults.count > 80 {
            toolExecutionResults.removeLast(toolExecutionResults.count - 80)
        }

        recordLocalAction(
            kind: .runTool,
            title: result.title,
            detail: result.output,
            status: result.localActionStatus,
            destination: .tools,
            requiresConfirmation: result.requiresApproval,
            completedAt: result.status == .completed ? result.createdAt : nil
        )
    }

    private func executeTool(
        _ tool: ToolConfiguration,
        query: String,
        webPageCaptureService: WebPageCaptureService,
        webSearchService: WebSearchService,
        gitHubToolService: GitHubToolService,
        notionToolService: NotionToolService,
        youTubeToolService: YouTubeToolService,
        xToolService: XToolService,
        browserAutomationService: BrowserAutomationService,
        secretReader: @escaping ToolSecretReader
    ) async -> LocalToolExecutionResult {
        let context = toolExecutionContext(for: tool, query: query)
        let executionService = LocalToolExecutionService()

        if tool.kind == .webSearch {
            if let gate = executionService.permissionGate(for: context) {
                return gate
            }

            return await runLiveWebSearch(
                tool,
                query: query,
                webSearchService: webSearchService,
                secretReader: secretReader
            )
        }

        if tool.kind == .github {
            if let gate = executionService.permissionGate(for: context) {
                return gate
            }

            return await runGitHubTool(
                tool,
                query: query,
                gitHubToolService: gitHubToolService,
                secretReader: secretReader
            )
        }

        if tool.kind == .notion {
            if let gate = executionService.permissionGate(for: context) {
                return gate
            }

            return await runNotionTool(
                tool,
                query: query,
                notionToolService: notionToolService,
                secretReader: secretReader
            )
        }

        if tool.kind == .youtube {
            if let gate = executionService.permissionGate(for: context) {
                return gate
            }

            return await runYouTubeTool(
                tool,
                query: query,
                youTubeToolService: youTubeToolService,
                secretReader: secretReader
            )
        }

        if tool.kind == .x {
            if let gate = executionService.permissionGate(for: context) {
                return gate
            }

            return await runXTool(
                tool,
                query: query,
                xToolService: xToolService,
                secretReader: secretReader
            )
        }

        if tool.kind == .browserAutomation {
            if let gate = executionService.permissionGate(for: context) {
                return gate
            }

            return await runBrowserAutomation(
                tool,
                query: query,
                browserAutomationService: browserAutomationService
            )
        }

        if tool.kind == .webPageReader,
           let url = liveWebPageReaderURL(from: query) {
            if let gate = executionService.permissionGate(for: context) {
                return gate
            }

            do {
                let capturedPage = try await webPageCaptureService.capture(url: url)
                return executionService.run(
                    toolExecutionContext(for: tool, query: query, capturedWebPage: capturedPage)
                )
            } catch {
                return LocalToolExecutionResult(
                    toolID: tool.id,
                    toolKind: tool.kind,
                    title: tool.title,
                    query: query,
                    status: .unavailable,
                    output: "Live web page reader could not fetch \(url.absoluteString): \(error.localizedDescription)",
                    usedNetwork: true,
                    modifiedFiles: false
                )
            }
        }

        return executionService.run(context)
    }

    private func runNotionTool(
        _ tool: ToolConfiguration,
        query: String,
        notionToolService: NotionToolService,
        secretReader: @escaping ToolSecretReader
    ) async -> LocalToolExecutionResult {
        let endpoint = tool.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEndpoint = endpoint?.isEmpty == false ? endpoint! : NotionToolService.defaultEndpoint

        guard let secretReference = trustedToolSecretReference(for: tool) else {
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .unavailable,
                output: "Notion needs a Notion integration token saved in Keychain before Flannel can make live workspace context requests.",
                usedNetwork: false,
                modifiedFiles: false
            )
        }

        do {
            let token = try secretReader(secretReference).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                return LocalToolExecutionResult(
                    toolID: tool.id,
                    toolKind: tool.kind,
                    title: tool.title,
                    query: query,
                    status: .unavailable,
                    output: "Notion found an empty Keychain secret for \(secretReference.rawValue). Save a valid Notion integration token.",
                    usedNetwork: false,
                    modifiedFiles: false
                )
            }

            let response = try await notionToolService.fetch(
                NotionToolRequest(
                    query: query,
                    endpoint: resolvedEndpoint,
                    token: token,
                    resultLimit: 8
                )
            )
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .completed,
                output: response.formattedToolOutput,
                usedNetwork: true,
                modifiedFiles: false
            )
        } catch {
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .unavailable,
                output: "Notion could not complete through \(resolvedEndpoint): \(error.localizedDescription)",
                usedNetwork: true,
                modifiedFiles: false
            )
        }
    }

    private func runBrowserAutomation(
        _ tool: ToolConfiguration,
        query: String,
        browserAutomationService: BrowserAutomationService
    ) async -> LocalToolExecutionResult {
        let searchEndpoint = tool.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSearchEndpoint = searchEndpoint?.isEmpty == false
            ? searchEndpoint!
            : BrowserAutomationService.defaultSearchEndpoint

        do {
            let response = try await browserAutomationService.run(
                BrowserAutomationRequest(
                    query: query,
                    searchEndpoint: resolvedSearchEndpoint
                )
            )
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .completed,
                output: response.formattedToolOutput,
                usedNetwork: true,
                modifiedFiles: false
            )
        } catch let error as BrowserAutomationServiceError {
            let status: LocalToolExecutionStatus = {
                switch error {
                case .openRejected:
                    return .unavailable
                case .emptyQuery, .invalidURL, .unsupportedScheme, .invalidSearchEndpoint:
                    return .blocked
                }
            }()
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: status,
                output: "Browser Automation did not open a browser: \(error.localizedDescription)",
                usedNetwork: false,
                modifiedFiles: false
            )
        } catch {
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .unavailable,
                output: "Browser Automation could not complete: \(error.localizedDescription)",
                usedNetwork: false,
                modifiedFiles: false
            )
        }
    }

    private func runXTool(
        _ tool: ToolConfiguration,
        query: String,
        xToolService: XToolService,
        secretReader: @escaping ToolSecretReader
    ) async -> LocalToolExecutionResult {
        let endpoint = tool.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEndpoint = endpoint?.isEmpty == false ? endpoint! : XToolService.defaultEndpoint

        guard let secretReference = trustedToolSecretReference(for: tool) else {
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .unavailable,
                output: "X needs an X API bearer token saved in Keychain before Flannel can make live post or profile metadata requests.",
                usedNetwork: false,
                modifiedFiles: false
            )
        }

        do {
            let bearerToken = try secretReader(secretReference).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bearerToken.isEmpty else {
                return LocalToolExecutionResult(
                    toolID: tool.id,
                    toolKind: tool.kind,
                    title: tool.title,
                    query: query,
                    status: .unavailable,
                    output: "X found an empty Keychain secret for \(secretReference.rawValue). Save a valid X API bearer token.",
                    usedNetwork: false,
                    modifiedFiles: false
                )
            }

            let response = try await xToolService.fetch(
                XToolRequest(
                    query: query,
                    endpoint: resolvedEndpoint,
                    bearerToken: bearerToken,
                    resultLimit: 10
                )
            )
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .completed,
                output: response.formattedToolOutput,
                usedNetwork: true,
                modifiedFiles: false
            )
        } catch {
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .unavailable,
                output: "X could not complete through \(resolvedEndpoint): \(error.localizedDescription)",
                usedNetwork: true,
                modifiedFiles: false
            )
        }
    }

    private func runYouTubeTool(
        _ tool: ToolConfiguration,
        query: String,
        youTubeToolService: YouTubeToolService,
        secretReader: @escaping ToolSecretReader
    ) async -> LocalToolExecutionResult {
        let endpoint = tool.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEndpoint = endpoint?.isEmpty == false ? endpoint! : YouTubeToolService.defaultEndpoint

        guard let secretReference = trustedToolSecretReference(for: tool) else {
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .unavailable,
                output: "YouTube needs a YouTube Data API key saved in Keychain before Flannel can make live video metadata requests.",
                usedNetwork: false,
                modifiedFiles: false
            )
        }

        do {
            let apiKey = try secretReader(secretReference).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                return LocalToolExecutionResult(
                    toolID: tool.id,
                    toolKind: tool.kind,
                    title: tool.title,
                    query: query,
                    status: .unavailable,
                    output: "YouTube found an empty Keychain secret for \(secretReference.rawValue). Save a valid YouTube Data API key.",
                    usedNetwork: false,
                    modifiedFiles: false
                )
            }

            let response = try await youTubeToolService.fetch(
                YouTubeToolRequest(
                    query: query,
                    endpoint: resolvedEndpoint,
                    apiKey: apiKey,
                    resultLimit: 8
                )
            )
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .completed,
                output: response.formattedToolOutput,
                usedNetwork: true,
                modifiedFiles: false
            )
        } catch {
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .unavailable,
                output: "YouTube could not complete through \(resolvedEndpoint): \(error.localizedDescription)",
                usedNetwork: true,
                modifiedFiles: false
            )
        }
    }

    private func runLiveWebSearch(
        _ tool: ToolConfiguration,
        query: String,
        webSearchService: WebSearchService,
        secretReader: @escaping ToolSecretReader
    ) async -> LocalToolExecutionResult {
        let endpoint = tool.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEndpoint = endpoint?.isEmpty == false ? endpoint! : WebSearchService.defaultEndpoint

        guard let secretReference = trustedToolSecretReference(for: tool) else {
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .unavailable,
                output: "Web Search needs a web search API key saved in Keychain before Flannel can make live network requests.",
                usedNetwork: false,
                modifiedFiles: false
            )
        }

        do {
            let apiKey = try secretReader(secretReference).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                return LocalToolExecutionResult(
                    toolID: tool.id,
                    toolKind: tool.kind,
                    title: tool.title,
                    query: query,
                    status: .unavailable,
                    output: "Web Search found an empty Keychain secret for \(secretReference.rawValue). Save a valid web search API key.",
                    usedNetwork: false,
                    modifiedFiles: false
                )
            }

            let response = try await webSearchService.search(
                WebSearchRequest(
                    query: query,
                    endpoint: resolvedEndpoint,
                    apiKey: apiKey,
                    resultLimit: 8
                )
            )
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .completed,
                output: response.formattedToolOutput,
                usedNetwork: true,
                modifiedFiles: false
            )
        } catch {
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .unavailable,
                output: "Web Search could not complete through \(resolvedEndpoint): \(error.localizedDescription)",
                usedNetwork: true,
                modifiedFiles: false
            )
        }
    }

    private func runGitHubTool(
        _ tool: ToolConfiguration,
        query: String,
        gitHubToolService: GitHubToolService,
        secretReader: @escaping ToolSecretReader
    ) async -> LocalToolExecutionResult {
        let endpoint = tool.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEndpoint = endpoint?.isEmpty == false ? endpoint! : GitHubToolService.defaultEndpoint

        let token: String?
        if let secretReference = trustedToolSecretReference(for: tool) {
            do {
                token = try secretReader(secretReference).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return LocalToolExecutionResult(
                    toolID: tool.id,
                    toolKind: tool.kind,
                    title: tool.title,
                    query: query,
                    status: .unavailable,
                    output: "GitHub could not read the saved Keychain token \(secretReference.rawValue): \(error.localizedDescription)",
                    usedNetwork: false,
                    modifiedFiles: false
                )
            }
        } else {
            token = nil
        }

        do {
            let response = try await gitHubToolService.fetch(
                GitHubToolRequest(
                    query: query,
                    endpoint: resolvedEndpoint,
                    token: token?.isEmpty == false ? token : nil,
                    resultLimit: 8
                )
            )
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .completed,
                output: response.formattedToolOutput,
                usedNetwork: true,
                modifiedFiles: false
            )
        } catch {
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: query,
                status: .unavailable,
                output: "GitHub could not complete through \(resolvedEndpoint): \(error.localizedDescription)",
                usedNetwork: true,
                modifiedFiles: false
            )
        }
    }

    private func liveWebPageReaderURL(from query: String) -> URL? {
        let normalizedLines = query
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard var candidate = normalizedLines.first(where: { !$0.isEmpty }) else {
            return nil
        }

        for prefix in ["url:", "page:", "read:"] where candidate.lowercased().hasPrefix(prefix) {
            candidate = String(candidate.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let url = URL(string: candidate),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return url
        }

        guard candidate.contains("."),
              candidate.range(of: "\0") == nil,
              let url = URL(string: "https://\(candidate)") else {
            return nil
        }

        return url
    }

    private func canonicalToolSecretReference(for tool: ToolConfiguration) -> KeychainSecretReference {
        let endpointHost = tool.endpoint
            .flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines))?.host }
            ?? "default"
        let normalizedHost = endpointHost
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        return KeychainSecretReference(
            service: KeychainSecretStore.defaultService,
            account: "tool/\(tool.kind.rawValue)/\(normalizedHost.isEmpty ? "default" : normalizedHost)"
        )
    }

    private func trustedToolSecretReference(for tool: ToolConfiguration) -> KeychainSecretReference? {
        guard let storedReference = ProviderSetupService.shared.parseSecretReference(tool.secretReference),
              storedReference == canonicalToolSecretReference(for: tool) else {
            return nil
        }
        return storedReference
    }

    private func toolExecutionContext(
        for tool: ToolConfiguration,
        query: String,
        capturedWebPage: CapturedWebPage? = nil
    ) -> LocalToolExecutionContext {
        let retrievalPacket: LocalKnowledgeRetrievalPacket?
        if tool.kind == .ragRetrieval || tool.kind == .workspaceSearch {
            retrievalPacket = localKnowledgeRetrievalPacket(
                for: query,
                limit: 5,
                knowledgeSourceIDs: currentThreadKnowledgeSourceScope()
            )
        } else {
            retrievalPacket = nil
        }

        return LocalToolExecutionContext(
            tool: tool,
            query: query,
            localOnlyMode: preferences.localOnlyMode ?? true,
            workspaceSummary: toolWorkspaceSummary(for: query, retrievalPacket: retrievalPacket),
            retrievalPacket: retrievalPacket,
            webPageText: selectedWebPageToolText(),
            capturedWebPage: capturedWebPage,
            fileText: selectedFileToolText()
        )
    }

    private func requestedToolCall(_ toolCallID: UUID, in messageID: UUID) -> AIToolCallRecord? {
        for thread in assistantThreads {
            guard let message = thread.messages.first(where: { $0.id == messageID }),
                  let toolCall = message.toolCalls.first(where: { $0.id == toolCallID }) else {
                continue
            }
            return toolCall
        }
        return nil
    }

    @discardableResult
    private func markRequestedToolCall(
        _ toolCallID: UUID,
        in messageID: UUID,
        wasApproved: Bool,
        executionStatus: LocalToolExecutionStatus?,
        executionResultID: UUID?,
        outputPreview: String,
        completedAt: Date
    ) -> AIToolCallRecord? {
        for threadIndex in assistantThreads.indices {
            guard let messageIndex = assistantThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }),
                  let toolCallIndex = assistantThreads[threadIndex].messages[messageIndex].toolCalls.firstIndex(where: { $0.id == toolCallID }) else {
                continue
            }

            assistantThreads[threadIndex].messages[messageIndex].toolCalls[toolCallIndex].wasApproved = wasApproved
            assistantThreads[threadIndex].messages[messageIndex].toolCalls[toolCallIndex].executionStatus = executionStatus
            assistantThreads[threadIndex].messages[messageIndex].toolCalls[toolCallIndex].executionResultID = executionResultID
            assistantThreads[threadIndex].messages[messageIndex].toolCalls[toolCallIndex].outputPreview = outputPreview
            assistantThreads[threadIndex].messages[messageIndex].toolCalls[toolCallIndex].completedAt = completedAt
            assistantThreads[threadIndex].messages[messageIndex].updatedAt = .now
            assistantThreads[threadIndex].updatedAt = .now
            return assistantThreads[threadIndex].messages[messageIndex].toolCalls[toolCallIndex]
        }
        return nil
    }

    private func toolConfiguration(for result: LocalToolExecutionResult) -> ToolConfiguration? {
        if let toolID = result.toolID,
           let tool = toolConfigurations.first(where: { $0.id == toolID }) {
            return tool
        }

        return toolConfigurations.first {
            $0.kind == result.toolKind && $0.title == result.title
        } ?? toolConfigurations.first {
            $0.kind == result.toolKind
        }
    }

    private static func queryFromToolArguments(_ argumentsJSON: String, toolKind: AIToolKind) -> String {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return trimmed
        }

        switch toolKind {
        case .terminal:
            if let command = stringValue(in: dictionary, keys: ["command", "cmd", "shell", "script"]) {
                if let cwd = stringValue(in: dictionary, keys: ["cwd", "working_directory", "workingDirectory"]) {
                    return "cwd: \(cwd)\n\(command)"
                }
                return command
            }
        case .codeExecution:
            if let code = stringValue(in: dictionary, keys: ["code", "source"]),
               let language = stringValue(in: dictionary, keys: ["language", "lang", "runtime"]) {
                if let cwd = stringValue(in: dictionary, keys: ["cwd", "working_directory", "workingDirectory"]) {
                    return "cwd: \(cwd)\n\(language)\n\(code)"
                }
                return "\(language)\n\(code)"
            }
            if let code = stringValue(in: dictionary, keys: ["code", "source"]) {
                return code
            }
        case .localFileWrite:
            if let path = stringValue(in: dictionary, keys: ["path", "file", "filename"]),
               let content = stringValue(in: dictionary, keys: ["content", "text", "body"]) {
                return "\(path)\n---\n\(content)"
            }
        case .webPageReader, .browserAutomation:
            if let url = stringValue(in: dictionary, keys: ["url", "href", "link"]) {
                if let focus = stringValue(in: dictionary, keys: ["focus", "question", "task"]) {
                    return "\(url)\n\(focus)"
                }
                return url
            }
            if toolKind == .browserAutomation,
               let task = stringValue(in: dictionary, keys: ["task", "instruction", "goal"]) {
                return task
            }
        case .localFileRead:
            if let path = stringValue(in: dictionary, keys: ["path", "file", "filename", "url"]) {
                return path
            }
        case .webSearch, .workspaceSearch, .ragRetrieval, .github, .notion, .youtube, .x:
            break
        }

        if let query = stringValue(
            in: dictionary,
            keys: ["query", "search", "prompt", "request", "question", "input", "text", "term", "topic"]
        ) {
            return query
        }

        return prettyJSONString(from: dictionary) ?? trimmed
    }

    private static func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            } else if JSONSerialization.isValidJSONObject(value),
                      let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                      let json = String(data: data, encoding: .utf8) {
                return json
            } else {
                let description = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
                if !description.isEmpty {
                    return description
                }
            }
        }
        return nil
    }

    private static func prettyJSONString(from object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func recordToolResolution(_ result: LocalToolExecutionResult) {
        recordLocalAction(
            kind: .runTool,
            title: result.title,
            detail: result.output,
            status: result.localActionStatus,
            destination: .tools,
            requiresConfirmation: false,
            completedAt: result.status == .completed ? result.createdAt : nil
        )
    }

    private func estimatedTokenCount(for text: String) -> Int {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard characterCount > 0 else { return 0 }
        return max(1, Int(ceil(Double(characterCount) / 4.0)))
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

    private func toolWorkspaceSummary(
        for query: String,
        retrievalPacket: LocalKnowledgeRetrievalPacket?
    ) -> String {
        var sections = [
            assistantContext.promptPreamble
        ]

        if let retrievalPacket, !retrievalPacket.isEmpty {
            sections.append(
                retrievalPacket.results.prefix(3).enumerated().map { index, result in
                    "[\(index + 1)] \(result.chunk.citationTitle): \(result.snippet)"
                }
                .joined(separator: "\n")
            )
        }

        sections.append(String(workspaceKnowledgeText().prefix(12_000)))
        return sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func selectedWebPageToolText() -> String? {
        if let asset = currentLibraryAsset,
           asset.sourceURL != nil || asset.kind == .link {
            return """
            Web source: \(asset.title)
            URL: \(asset.sourceURL?.absoluteString ?? asset.sourceIdentifier ?? "")
            Summary: \(asset.summary)
            Notes: \(asset.notes)
            Transcript: \(String((asset.transcript?.text ?? "").prefix(8_000)))
            """
        }

        if let source = knowledgeSources.first(where: { $0.kind == .webPage }) {
            let capturedText = localWebPageText(for: source)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !capturedText.isEmpty {
                return String(capturedText.prefix(10_000))
            }
            return """
            Web knowledge source: \(source.title)
            URL: \(source.location)
            Status: \(source.status.rawValue)
            """
        }

        return libraryAssets.first(where: { $0.sourceURL != nil }).map { asset in
            """
            Web source: \(asset.title)
            URL: \(asset.sourceURL?.absoluteString ?? "")
            Summary: \(asset.summary)
            Notes: \(asset.notes)
            """
        }
    }

    private func selectedFileToolText(maximumBytes: Int = 12_000) -> String? {
        guard let url = firstReadableFileToolURL(),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: maximumBytes)
        guard let text = decodedToolText(from: data)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? data.count
        let truncationNote = fileSize > maximumBytes
            ? "\nTruncated to the first \(maximumBytes) bytes."
            : ""
        return """
        File: \(url.path)\(truncationNote)

        \(text)
        """
    }

    private func firstReadableFileToolURL() -> URL? {
        if let source = knowledgeSources.first(where: { $0.kind == .file }),
           let url = readableFileURL(from: source.location) {
            return url
        }

        return knowledgeSources
            .lazy
            .compactMap { self.readableFileURL(from: $0.location) }
            .first
    }

    private func decodedToolText(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .ascii)
    }

    private static func copyMessageForNewThread(_ message: AssistantMessage) -> AssistantMessage {
        AssistantMessage(
            role: message.role,
            text: message.text,
            attachments: message.attachments,
            createdAt: message.createdAt,
            updatedAt: message.updatedAt,
            isPinned: false,
            referencedEntityIDs: message.referencedEntityIDs,
            promptChainStepID: message.promptChainStepID,
            citations: message.citations,
            providerDisplayName: message.providerDisplayName,
            modelIdentifier: message.modelIdentifier,
            inputTokenCount: message.inputTokenCount,
            outputTokenCount: message.outputTokenCount,
            latencyMilliseconds: message.latencyMilliseconds,
            estimatedCostMicros: message.estimatedCostMicros
        )
    }

    private static func snippet(from text: String, matching query: String, radius: Int = 72) -> String {
        let collapsed = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return "" }
        guard !query.isEmpty,
              let range = collapsed.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(collapsed.prefix(radius * 2))
        }

        let lowerBound = collapsed.index(
            range.lowerBound,
            offsetBy: -radius,
            limitedBy: collapsed.startIndex
        ) ?? collapsed.startIndex
        let upperBound = collapsed.index(
            range.upperBound,
            offsetBy: radius,
            limitedBy: collapsed.endIndex
        ) ?? collapsed.endIndex
        let prefix = lowerBound == collapsed.startIndex ? "" : "..."
        let suffix = upperBound == collapsed.endIndex ? "" : "..."
        return prefix + String(collapsed[lowerBound..<upperBound]) + suffix
    }

    private static func threadTitle(from prompt: String) -> String {
        let collapsed = prompt
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return "New AI Chat" }
        return String(collapsed.prefix(64))
    }

    private static func memoryTitle(from rawTitle: String, fallbackText: String) -> String {
        let explicitTitle = rawTitle
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if !explicitTitle.isEmpty {
            return String(explicitTitle.prefix(72))
        }

        let firstLine = fallbackText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .first?
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ") ?? ""

        guard !firstLine.isEmpty else { return "Saved Memory" }
        return String(firstLine.prefix(72))
    }

    private static func memoryTerms(in text: String) -> Set<String> {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let terms = normalized.split { character in
            !(character.isLetter || character.isNumber)
        }
        return Set(terms.map(String.init).filter { $0.count > 2 })
    }

    private static func toolResultAttachment(for result: LocalToolExecutionResult) -> AIChatAttachment {
        AIChatAttachment(
            kind: .toolResult,
            title: result.title,
            mimeType: "text/plain",
            excerpt: result.output.truncatedForToolAttachment,
            createdAt: result.createdAt
        )
    }

    private static func toolResultMessageText(for result: LocalToolExecutionResult) -> String {
        let statusLine: String
        switch result.status {
        case .completed:
            statusLine = "Completed locally."
        case .requiresApproval:
            statusLine = "Approval required before this tool can run."
        case .denied:
            statusLine = "Denied locally. No tool action was run."
        case .blocked:
            statusLine = "Blocked by the current privacy or permission policy."
        case .unavailable:
            statusLine = "Unavailable in the current workspace."
        }

        let queryLine = result.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\nQuery: \(result.query)"
        return """
        Tool run: \(result.title)
        Status: \(statusLine)\(queryLine)

        \(result.output)
        """
    }
}

private extension LocalToolExecutionResult {
    var localActionStatus: LocalActionStatus {
        switch status {
        case .completed:
            .completed
        case .requiresApproval:
            .requiresConfirmation
        case .denied, .blocked, .unavailable:
            .failed
        }
    }
}

private extension AIToolKind {
    init?(chatToolName rawName: String) {
        let normalizedName = rawName.normalizedToolName
        let aliases: [String: AIToolKind] = [
            "search": .workspaceSearch,
            "workspace": .workspaceSearch,
            "workspacesearch": .workspaceSearch,
            "rag": .ragRetrieval,
            "retrieval": .ragRetrieval,
            "ragretrieval": .ragRetrieval,
            "web": .webSearch,
            "websearch": .webSearch,
            "page": .webPageReader,
            "reader": .webPageReader,
            "webpagereader": .webPageReader,
            "file": .localFileRead,
            "read": .localFileRead,
            "localfileread": .localFileRead,
            "write": .localFileWrite,
            "localfilewrite": .localFileWrite,
            "terminal": .terminal,
            "shell": .terminal,
            "code": .codeExecution,
            "codeexecution": .codeExecution,
            "browser": .browserAutomation,
            "browserautomation": .browserAutomation,
            "github": .github,
            "notion": .notion,
            "youtube": .youtube,
            "x": .x,
            "twitter": .x
        ]

        if let aliasedKind = aliases[normalizedName] {
            self = aliasedKind
            return
        }

        guard let kind = AIToolKind.allCases.first(where: { $0.rawValue.normalizedToolName == normalizedName }) else {
            return nil
        }
        self = kind
    }

    var requiresDedicatedRunnerAfterApproval: Bool {
        switch self {
        case .webSearch, .webPageReader, .localFileRead, .localFileWrite, .terminal, .codeExecution, .browserAutomation, .workspaceSearch, .ragRetrieval, .github, .notion, .youtube, .x:
            false
        }
    }
}

private extension String {
    var normalizedToolName: String {
        lowercased().filter { $0.isLetter || $0.isNumber }
    }

    var truncatedForToolAttachment: String {
        let maxLength = 1_200
        guard count > maxLength else { return self }
        return "\(prefix(maxLength))..."
    }

    var truncatedForToolCallPreview: String {
        let maxLength = 480
        guard count > maxLength else { return self }
        return "\(prefix(maxLength))..."
    }
}

private extension Array {
    mutating func upsert<Value: Equatable>(_ value: Element, matching keyPath: KeyPath<Element, Value>) {
        if let index = firstIndex(where: { $0[keyPath: keyPath] == value[keyPath: keyPath] }) {
            self[index] = value
        } else {
            append(value)
        }
    }
}

private extension KnowledgeIndexStatus {
    var sortPriority: Int {
        switch self {
        case .failed:
            0
        case .stale:
            1
        case .queued, .indexing:
            2
        case .notIndexed:
            3
        case .ready:
            4
        }
    }
}

private extension Array where Element: Equatable {
    mutating func appendUnique(_ value: Element) {
        guard !contains(value) else { return }
        append(value)
    }
}
