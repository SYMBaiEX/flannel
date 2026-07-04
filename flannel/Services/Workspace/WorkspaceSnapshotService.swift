//
//  WorkspaceSnapshotService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation

struct WorkspaceSnapshotPayload: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var exportedAt: Date
    var workspace: WorkspaceSnapshot
}

struct WorkspaceSnapshot: Codable, Hashable, Sendable {
    var workspaceID: UUID
    var sourceSchemaVersion: Int
    var createdAt: Date
    var updatedAt: Date
    var selectedDestination: WorkspaceDestination
    var selectedProjectID: UUID?
    var selectedDraftID: UUID?
    var selectedAssetID: UUID?
    var selectedCalendarEntryID: UUID?
    var selectedAssistantThreadID: UUID?
    var accounts: [CreatorAccount]
    var providerConfigurations: [ProviderConfiguration]
    var libraryAssets: [LibraryAsset]
    var projects: [WorkspaceProject]
    var drafts: [DraftDocument]
    var calendarEntries: [PublishingCalendarEntry]
    var assistantThreads: [AssistantThread]
    var automations: [WorkspaceAutomation]
    var localActionHistory: [LocalActionRecord]
    var tags: [WorkspaceTag]
    var chatFolders: [ChatFolder]
    var promptProfiles: [SystemPromptProfile]
    var chatTemplates: [ChatTemplate]
    var promptChains: [PromptChain]?
    var modelPresets: [ModelPreset]
    var knowledgeSources: [KnowledgeSource]
    var knowledgeIndexManifests: [KnowledgeIndexManifest]
    var toolConfigurations: [ToolConfiguration]
    var toolConfigurationPresets: [ToolConfigurationPreset]?
    var toolExecutionResults: [LocalToolExecutionResult]
    var modelComparisonRuns: [ModelComparisonRun]
    var localDiscoveryResults: [LocalProviderDiscoveryResult]?
    var pinnedMessages: [PinnedAssistantMessage]
    var archivedAssistantThreadIDs: [UUID]
    var localMemories: [LocalMemoryRecord]
    var preferences: WorkspacePreferences

    init(
        workspaceID: UUID,
        sourceSchemaVersion: Int,
        createdAt: Date,
        updatedAt: Date,
        selectedDestination: WorkspaceDestination,
        selectedProjectID: UUID?,
        selectedDraftID: UUID?,
        selectedAssetID: UUID?,
        selectedCalendarEntryID: UUID?,
        selectedAssistantThreadID: UUID?,
        accounts: [CreatorAccount],
        providerConfigurations: [ProviderConfiguration],
        libraryAssets: [LibraryAsset],
        projects: [WorkspaceProject],
        drafts: [DraftDocument],
        calendarEntries: [PublishingCalendarEntry],
        assistantThreads: [AssistantThread],
        automations: [WorkspaceAutomation],
        localActionHistory: [LocalActionRecord],
        tags: [WorkspaceTag],
        chatFolders: [ChatFolder],
        promptProfiles: [SystemPromptProfile],
        chatTemplates: [ChatTemplate],
        promptChains: [PromptChain] = [],
        modelPresets: [ModelPreset],
        knowledgeSources: [KnowledgeSource],
        knowledgeIndexManifests: [KnowledgeIndexManifest],
        toolConfigurations: [ToolConfiguration],
        toolConfigurationPresets: [ToolConfigurationPreset] = [],
        toolExecutionResults: [LocalToolExecutionResult],
        modelComparisonRuns: [ModelComparisonRun],
        localDiscoveryResults: [LocalProviderDiscoveryResult] = [],
        pinnedMessages: [PinnedAssistantMessage],
        archivedAssistantThreadIDs: [UUID],
        localMemories: [LocalMemoryRecord],
        preferences: WorkspacePreferences
    ) {
        self.workspaceID = workspaceID
        self.sourceSchemaVersion = sourceSchemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.selectedDestination = selectedDestination
        self.selectedProjectID = selectedProjectID
        self.selectedDraftID = selectedDraftID
        self.selectedAssetID = selectedAssetID
        self.selectedCalendarEntryID = selectedCalendarEntryID
        self.selectedAssistantThreadID = selectedAssistantThreadID
        self.accounts = accounts
        self.providerConfigurations = providerConfigurations
        self.libraryAssets = libraryAssets
        self.projects = projects
        self.drafts = drafts
        self.calendarEntries = calendarEntries
        self.assistantThreads = assistantThreads
        self.automations = automations
        self.localActionHistory = localActionHistory
        self.tags = tags
        self.chatFolders = chatFolders
        self.promptProfiles = promptProfiles
        self.chatTemplates = chatTemplates
        self.promptChains = promptChains
        self.modelPresets = modelPresets
        self.knowledgeSources = knowledgeSources
        self.knowledgeIndexManifests = knowledgeIndexManifests
        self.toolConfigurations = toolConfigurations
        self.toolConfigurationPresets = toolConfigurationPresets
        self.toolExecutionResults = toolExecutionResults
        self.modelComparisonRuns = modelComparisonRuns
        self.localDiscoveryResults = localDiscoveryResults
        self.pinnedMessages = pinnedMessages
        self.archivedAssistantThreadIDs = archivedAssistantThreadIDs
        self.localMemories = localMemories
        self.preferences = preferences
    }
}

enum WorkspaceSnapshotError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Flannel cannot import workspace snapshot schema version \(version)."
        }
    }
}

struct WorkspaceSnapshotImportResult {
    var item: Item
    var originalWorkspaceID: UUID
    var importedAt: Date
}

struct WorkspaceSnapshotService: Sendable {
    static let schemaVersion = 1

    func export(store: WorkspaceStore, exportedAt: Date = .now) throws -> Data {
        let snapshot = WorkspaceSnapshot(
            workspaceID: store.workspace?.workspaceID ?? UUID(),
            sourceSchemaVersion: store.workspace?.schemaVersion ?? 6,
            createdAt: store.workspace?.timestamp ?? exportedAt,
            updatedAt: store.workspace?.updatedAt ?? exportedAt,
            selectedDestination: store.selectedDestination,
            selectedProjectID: store.selectedProjectID,
            selectedDraftID: store.selectedDraftID,
            selectedAssetID: store.selectedAssetID,
            selectedCalendarEntryID: store.selectedCalendarEntryID,
            selectedAssistantThreadID: store.selectedAssistantThreadID,
            accounts: store.accounts,
            providerConfigurations: store.providerConfigurations,
            libraryAssets: store.libraryAssets,
            projects: store.projects,
            drafts: store.drafts,
            calendarEntries: store.calendarEntries,
            assistantThreads: store.assistantThreads,
            automations: store.automations,
            localActionHistory: store.localActionHistory,
            tags: store.tags,
            chatFolders: store.chatFolders,
            promptProfiles: store.promptProfiles,
            chatTemplates: store.chatTemplates,
            promptChains: store.promptChains,
            modelPresets: store.modelPresets,
            knowledgeSources: store.knowledgeSources,
            knowledgeIndexManifests: store.knowledgeIndexManifests,
            toolConfigurations: store.toolConfigurations,
            toolConfigurationPresets: store.toolConfigurationPresets,
            toolExecutionResults: store.toolExecutionResults,
            modelComparisonRuns: store.modelComparisonRuns,
            localDiscoveryResults: store.localDiscoveryResults,
            pinnedMessages: store.pinnedMessages,
            archivedAssistantThreadIDs: Array(store.archivedAssistantThreadIDs),
            localMemories: store.localMemories,
            preferences: store.preferences
        )

        let payload = WorkspaceSnapshotPayload(
            schemaVersion: Self.schemaVersion,
            exportedAt: exportedAt,
            workspace: snapshot
        )
        return try Self.encoder.encode(payload)
    }

    func importWorkspace(from data: Data, importedAt: Date = .now) throws -> WorkspaceSnapshotImportResult {
        let payload = try Self.decoder.decode(WorkspaceSnapshotPayload.self, from: data)
        guard payload.schemaVersion == Self.schemaVersion else {
            throw WorkspaceSnapshotError.unsupportedSchemaVersion(payload.schemaVersion)
        }

        let item = makeLocalWorkspaceCopy(from: payload.workspace, importedAt: importedAt)
        return WorkspaceSnapshotImportResult(
            item: item,
            originalWorkspaceID: payload.workspace.workspaceID,
            importedAt: importedAt
        )
    }

    func defaultFilename(for store: WorkspaceStore, exportedAt: Date = .now) -> String {
        let title = store.currentAssistantThread?.title
            ?? store.assistantThreads.first?.title
            ?? "Flannel Workspace"
        let date = Self.filenameDateFormatter.string(from: exportedAt)
        return "\(Self.slug(title))-workspace-\(date).flannelworkspace.json"
    }

    private func makeLocalWorkspaceCopy(from snapshot: WorkspaceSnapshot, importedAt: Date) -> Item {
        var preferences = snapshot.preferences
        preferences.lastOpenedAt = importedAt
        preferences.preferredProviderID = nil
        preferences.providerRoutingPolicy = .selectedProvider
        preferences.allowCloudProviders = false
        preferences.localOnlyMode = true
        preferences.safeMode = true
        preferences.confirmBeforeExternalActions = true
        preferences.automationsEnabled = false

        let localProviderIDs = Set(
            snapshot.providerConfigurations
                .filter { $0.privacyScope == .localOnly }
                .map(\.id)
        )
        let safeProjects = snapshot.projects.map { project in
            var copy = project
            if let preferredProviderID = copy.aiProfile.preferredProviderID,
               !localProviderIDs.contains(preferredProviderID) {
                copy.aiProfile.preferredProviderID = nil
            }
            if copy.aiProfile.cloudAccessPolicy == .allowCloudProviders {
                copy.aiProfile.cloudAccessPolicy = .localOnly
            }
            return copy
        }

        return Item(
            workspaceID: UUID(),
            schemaVersion: 6,
            timestamp: importedAt,
            updatedAt: importedAt,
            selectedDestination: snapshot.selectedDestination,
            selectedProjectID: safeProjects.contains(where: { $0.id == snapshot.selectedProjectID }) ? snapshot.selectedProjectID : nil,
            selectedDraftID: snapshot.drafts.contains(where: { $0.id == snapshot.selectedDraftID }) ? snapshot.selectedDraftID : nil,
            selectedAssetID: snapshot.libraryAssets.contains(where: { $0.id == snapshot.selectedAssetID }) ? snapshot.selectedAssetID : nil,
            selectedCalendarEntryID: snapshot.calendarEntries.contains(where: { $0.id == snapshot.selectedCalendarEntryID }) ? snapshot.selectedCalendarEntryID : nil,
            selectedAssistantThreadID: snapshot.assistantThreads.contains(where: { $0.id == snapshot.selectedAssistantThreadID }) ? snapshot.selectedAssistantThreadID : snapshot.assistantThreads.first?.id,
            accounts: snapshot.accounts,
            providerConfigurations: sanitizedProviderConfigurations(snapshot.providerConfigurations),
            libraryAssets: snapshot.libraryAssets,
            projects: safeProjects,
            drafts: snapshot.drafts,
            calendarEntries: snapshot.calendarEntries,
            assistantThreads: snapshot.assistantThreads,
            automations: sanitizedAutomations(snapshot.automations),
            localActionHistory: snapshot.localActionHistory,
            tags: snapshot.tags,
            chatFolders: snapshot.chatFolders,
            promptProfiles: snapshot.promptProfiles,
            chatTemplates: snapshot.chatTemplates,
            promptChains: snapshot.promptChains ?? [],
            modelPresets: snapshot.modelPresets,
            knowledgeSources: snapshot.knowledgeSources,
            knowledgeIndexManifests: snapshot.knowledgeIndexManifests,
            toolConfigurations: sanitizedToolConfigurations(snapshot.toolConfigurations),
            toolConfigurationPresets: sanitizedToolConfigurationPresets(snapshot.toolConfigurationPresets ?? []),
            toolExecutionResults: snapshot.toolExecutionResults,
            modelComparisonRuns: snapshot.modelComparisonRuns,
            localDiscoveryResults: snapshot.localDiscoveryResults ?? [],
            pinnedMessages: snapshot.pinnedMessages,
            archivedAssistantThreadIDs: snapshot.archivedAssistantThreadIDs,
            localMemories: snapshot.localMemories,
            preferences: preferences
        )
    }

    private func sanitizedProviderConfigurations(_ providers: [ProviderConfiguration]) -> [ProviderConfiguration] {
        providers.map { provider in
            var sanitized = provider
            sanitized.secretReference = nil
            sanitized.lastValidatedAt = nil
            sanitized.connectionStatus = provider.accessMode == .localServer ? .disconnected : .needsAttention
            sanitized.lastErrorMessage = "Imported workspace: recheck this route and save credentials on this Mac before chat can use it."
            return sanitized
        }
    }

    private func sanitizedToolConfigurations(_ tools: [ToolConfiguration]) -> [ToolConfiguration] {
        tools.map { tool in
            var sanitized = tool
            sanitized.permissionPolicy = .askEveryTime
            sanitized.isEnabled = false
            sanitized.endpoint = nil
            sanitized.secretReference = nil
            return sanitized
        }
    }

    private func sanitizedToolConfigurationPresets(_ presets: [ToolConfigurationPreset]) -> [ToolConfigurationPreset] {
        presets.map { preset in
            var sanitized = preset
            sanitized.isBuiltIn = false
            sanitized.entries = preset.entries.map { entry in
                ToolConfigurationPresetEntry(
                    kind: entry.kind,
                    permissionPolicy: .askEveryTime,
                    isEnabled: false
                )
            }
            return sanitized
        }
    }

    private func sanitizedAutomations(_ automations: [WorkspaceAutomation]) -> [WorkspaceAutomation] {
        automations.map { automation in
            var sanitized = automation
            sanitized.isEnabled = false
            sanitized.requiresConfirmation = true
            sanitized.nextRunAt = nil
            sanitized.lastRunState = .idle
            sanitized.lastResultMessage = "Imported workspace: review and re-enable this automation before it can run."
            return sanitized
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func slug(_ value: String) -> String {
        let cleaned = value
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : "-" }
        let slug = String(cleaned)
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return slug.isEmpty ? "flannel" : slug
    }
}
