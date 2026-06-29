//
//  Item.swift
//  flannel
//
//  Created by SYMBiEX on 6/28/26.
//

import Foundation
import SwiftData

enum WorkspaceDestination: String, Codable, CaseIterable, Identifiable, Sendable {
    case home
    case chats
    case compare
    case models
    case knowledge
    case tools
    case agents
    case prompts
    case inbox
    case youtube
    case x
    case library
    case projects
    case drafts
    case calendar
    case automations
    case search
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "Chat"
        case .chats:
            "History"
        case .compare:
            "Compare"
        case .models:
            "Models"
        case .knowledge:
            "Knowledge"
        case .tools:
            "Tools"
        case .agents:
            "Agents"
        case .prompts:
            "Prompts"
        case .inbox:
            "Inbox"
        case .youtube:
            "YouTube"
        case .x:
            "X"
        case .library:
            "Library"
        case .projects:
            "Projects"
        case .drafts:
            "Drafts"
        case .calendar:
            "Calendar"
        case .automations:
            "Automations"
        case .search:
            "Search"
        case .settings:
            "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .home:
            "Private chat"
        case .chats:
            "Folders and threads"
        case .compare:
            "Multi-model runs"
        case .models:
            "Providers and routing"
        case .knowledge:
            "RAG and indexing"
        case .tools:
            "Permissions and tools"
        case .agents:
            "Workflows and traces"
        case .prompts:
            "Profiles and templates"
        case .inbox:
            "Unreviewed captures"
        case .youtube:
            "Videos and channels"
        case .x:
            "Posts and threads"
        case .library:
            "Local knowledge"
        case .projects:
            "Research workspaces"
        case .drafts:
            "Writing desk"
        case .calendar:
            "Publishing plan"
        case .automations:
            "Local routines"
        case .search:
            "Find anything"
        case .settings:
            "Models and privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "sparkles"
        case .chats:
            "bubble.left.and.bubble.right"
        case .compare:
            "rectangle.split.3x1"
        case .models:
            "cpu"
        case .knowledge:
            "books.vertical"
        case .tools:
            "wrench.and.screwdriver"
        case .agents:
            "flowchart"
        case .prompts:
            "text.cursor"
        case .inbox:
            "tray"
        case .youtube:
            "play.rectangle"
        case .x:
            "text.bubble"
        case .library:
            "books.vertical"
        case .projects:
            "folder"
        case .drafts:
            "square.and.pencil"
        case .calendar:
            "calendar"
        case .automations:
            "wand.and.stars"
        case .search:
            "magnifyingglass"
        case .settings:
            "gearshape"
        }
    }
}

enum ContentPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case youtube
    case x
    case internalNote

    var id: String { rawValue }
}

enum DraftStatus: String, Codable, CaseIterable, Sendable {
    case idea
    case inProgress
    case review
    case scheduled
    case published
}

enum ProjectStatus: String, Codable, CaseIterable, Sendable {
    case active
    case incubating
    case paused
    case archived
}

enum LibraryAssetKind: String, Codable, CaseIterable, Sendable {
    case note
    case link
    case transcript
    case research
    case prompt
}

enum AssistantRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

enum AssistantMessageRunStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case queued
    case streaming
    case completed
    case fallback
    case failed
    case stopped

    nonisolated var title: String {
        switch self {
        case .queued:
            "Queued"
        case .streaming:
            "Streaming"
        case .completed:
            "Completed"
        case .fallback:
            "Fallback"
        case .failed:
            "Failed"
        case .stopped:
            "Stopped"
        }
    }
}

enum AssistantMode: String, Codable, CaseIterable, Sendable {
    case workspaceCopilot
    case research
    case drafting
}

enum LLMProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case ollama
    case lmStudio
    case openAI
    case anthropic
    case gemini
    case xAI
    case mistral
    case groq
    case openRouter
    case perplexity
    case customOpenAICompatible
    case chatGPTCLI
    case claudeCodeCLI
    case vercelAISDKBridge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ollama:
            "Ollama"
        case .lmStudio:
            "LM Studio"
        case .openAI:
            "OpenAI"
        case .anthropic:
            "Anthropic"
        case .gemini:
            "Google Gemini"
        case .xAI:
            "xAI"
        case .mistral:
            "Mistral"
        case .groq:
            "Groq"
        case .openRouter:
            "OpenRouter"
        case .perplexity:
            "Perplexity"
        case .customOpenAICompatible:
            "Custom Endpoint"
        case .chatGPTCLI:
            "ChatGPT/Codex CLI"
        case .claudeCodeCLI:
            "Claude Code CLI"
        case .vercelAISDKBridge:
            "Vercel AI SDK Bridge"
        }
    }
}

enum ProviderReasoningEffort: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }
}

enum IntegrationConnectionStatus: String, Codable, CaseIterable, Sendable {
    case disconnected
    case ready
    case syncing
    case needsAttention
    case rateLimited
}

enum WorkspaceSyncStatus: String, Codable, CaseIterable, Sendable {
    case idle
    case queued
    case syncing
    case succeeded
    case failed
}

enum TranscriptStatus: String, Codable, CaseIterable, Sendable {
    case notRequested
    case queued
    case available
    case failed
}

enum SummaryStatus: String, Codable, CaseIterable, Sendable {
    case missing
    case queued
    case ready
    case stale
    case failed
}

enum CalendarEntryStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case scheduled
    case completed
    case skipped
}

enum AutomationCadence: String, Codable, CaseIterable, Sendable {
    case manual
    case hourly
    case daily
    case weekly
}

enum AutomationRunState: String, Codable, CaseIterable, Sendable {
    case idle
    case queued
    case running
    case succeeded
    case needsConfirmation
    case failed
}

enum LocalActionKind: String, Codable, CaseIterable, Sendable {
    case captureURL
    case importTranscript
    case generateSummary
    case createDraft
    case scheduleDraft
    case runAutomation
    case runTool
    case exportDraft
}

enum LocalActionStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case completed
    case requiresConfirmation
    case failed
}

struct SummaryRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var text: String
    var bulletPoints: [String]
    var status: SummaryStatus
    var sourceLabel: String
    var modelLabel: String?
    var createdAt: Date

    nonisolated init(
        id: UUID = UUID(),
        title: String,
        text: String,
        bulletPoints: [String] = [],
        status: SummaryStatus = .ready,
        sourceLabel: String = "Local workspace",
        modelLabel: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.bulletPoints = bulletPoints
        self.status = status
        self.sourceLabel = sourceLabel
        self.modelLabel = modelLabel
        self.createdAt = createdAt
    }
}

struct TranscriptRecord: Codable, Hashable, Sendable {
    var status: TranscriptStatus
    var text: String
    var languageCode: String
    var sourceLabel: String
    var importedAt: Date
    var updatedAt: Date
    var lastErrorMessage: String?

    init(
        status: TranscriptStatus = .notRequested,
        text: String = "",
        languageCode: String = "en",
        sourceLabel: String = "Local workspace",
        importedAt: Date = .now,
        updatedAt: Date = .now,
        lastErrorMessage: String? = nil
    ) {
        self.status = status
        self.text = text
        self.languageCode = languageCode
        self.sourceLabel = sourceLabel
        self.importedAt = importedAt
        self.updatedAt = updatedAt
        self.lastErrorMessage = lastErrorMessage
    }
}

struct WorkspaceTag: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var colorName: String
    var usageCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorName: String = "gray",
        usageCount: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.usageCount = usageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct ProviderRequestOverrides: Codable, Hashable, Sendable {
    var maxOutputTokens: Int?
    var topP: Double?
    var topK: Int?
    var stopSequences: [String]
    var seed: Int?
    var presencePenalty: Double?
    var frequencyPenalty: Double?
    var repeatPenalty: Double?
    var reasoningEffort: ProviderReasoningEffort?

    init(
        maxOutputTokens: Int? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        stopSequences: [String] = [],
        seed: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        repeatPenalty: Double? = nil,
        reasoningEffort: ProviderReasoningEffort? = nil
    ) {
        self.maxOutputTokens = maxOutputTokens
        self.topP = topP
        self.topK = topK
        self.stopSequences = stopSequences
        self.seed = seed
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.repeatPenalty = repeatPenalty
        self.reasoningEffort = reasoningEffort
    }
}

nonisolated struct ProviderConfiguration: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: LLMProviderKind
    var accessMode: ProviderAccessMode
    var privacyScope: ProviderPrivacyScope
    var displayName: String
    var endpoint: String
    var modelIdentifier: String
    var secretReference: String?
    var organizationIdentifier: String?
    var isEnabled: Bool
    var temperature: Double
    var lastValidatedAt: Date?
    var connectionStatus: IntegrationConnectionStatus
    var lastErrorMessage: String?
    var isLocalPreferred: Bool
    var availableModels: [String]
    var discoveredModelNames: [String]
    var staleDiscoveredModelNames: [String]
    var capabilities: [ModelCapability]
    var supportsStreaming: Bool
    var supportsToolCalling: Bool
    var supportsEmbeddings: Bool
    var supportsVision: Bool
    var contextWindowTokens: Int?
    var inputCostPerMillionTokens: Double?
    var outputCostPerMillionTokens: Double?
    var supportsStructuredOutput: Bool
    var requestOverrides: ProviderRequestOverrides

    init(
        id: UUID = UUID(),
        kind: LLMProviderKind,
        accessMode: ProviderAccessMode? = nil,
        privacyScope: ProviderPrivacyScope? = nil,
        displayName: String,
        endpoint: String,
        modelIdentifier: String,
        secretReference: String? = nil,
        organizationIdentifier: String? = nil,
        isEnabled: Bool = true,
        temperature: Double = 0.2,
        lastValidatedAt: Date? = nil,
        connectionStatus: IntegrationConnectionStatus = .disconnected,
        lastErrorMessage: String? = nil,
        isLocalPreferred: Bool = false,
        availableModels: [String] = [],
        discoveredModelNames: [String] = [],
        staleDiscoveredModelNames: [String] = [],
        capabilities: [ModelCapability] = [.chat, .streaming],
        supportsStreaming: Bool = true,
        supportsToolCalling: Bool = false,
        supportsEmbeddings: Bool = false,
        supportsVision: Bool = false,
        contextWindowTokens: Int? = nil,
        inputCostPerMillionTokens: Double? = nil,
        outputCostPerMillionTokens: Double? = nil,
        supportsStructuredOutput: Bool = false,
        requestOverrides: ProviderRequestOverrides = ProviderRequestOverrides()
    ) {
        self.id = id
        self.kind = kind
        self.accessMode = accessMode ?? kind.defaultAccessMode
        self.privacyScope = privacyScope ?? kind.defaultPrivacyScope
        self.displayName = displayName
        self.endpoint = endpoint
        self.modelIdentifier = modelIdentifier
        self.secretReference = secretReference
        self.organizationIdentifier = organizationIdentifier
        self.isEnabled = isEnabled
        self.temperature = temperature
        self.lastValidatedAt = lastValidatedAt
        self.connectionStatus = connectionStatus
        self.lastErrorMessage = lastErrorMessage
        self.isLocalPreferred = isLocalPreferred
        self.availableModels = availableModels
        self.discoveredModelNames = discoveredModelNames
        self.staleDiscoveredModelNames = staleDiscoveredModelNames
        self.capabilities = capabilities
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.supportsEmbeddings = supportsEmbeddings
        self.supportsVision = supportsVision
        self.contextWindowTokens = contextWindowTokens
        self.inputCostPerMillionTokens = inputCostPerMillionTokens
        self.outputCostPerMillionTokens = outputCostPerMillionTokens
        self.supportsStructuredOutput = supportsStructuredOutput
        self.requestOverrides = requestOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(LLMProviderKind.self, forKey: .kind)
        accessMode = try container.decode(ProviderAccessMode.self, forKey: .accessMode, default: kind.defaultAccessMode)
        privacyScope = try container.decode(ProviderPrivacyScope.self, forKey: .privacyScope, default: kind.defaultPrivacyScope)
        displayName = try container.decode(String.self, forKey: .displayName)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        modelIdentifier = try container.decode(String.self, forKey: .modelIdentifier)
        secretReference = try container.decodeIfPresent(String.self, forKey: .secretReference)
        organizationIdentifier = try container.decodeIfPresent(String.self, forKey: .organizationIdentifier)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled, default: true)
        temperature = try container.decode(Double.self, forKey: .temperature, default: 0.2)
        lastValidatedAt = try container.decodeIfPresent(Date.self, forKey: .lastValidatedAt)
        connectionStatus = try container.decode(
            IntegrationConnectionStatus.self,
            forKey: .connectionStatus,
            default: .disconnected
        )
        lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
        isLocalPreferred = try container.decode(Bool.self, forKey: .isLocalPreferred, default: kind == .ollama)
        availableModels = try container.decode([String].self, forKey: .availableModels, default: [])
        discoveredModelNames = try container.decode([String].self, forKey: .discoveredModelNames, default: [])
        staleDiscoveredModelNames = try container.decode([String].self, forKey: .staleDiscoveredModelNames, default: [])
        capabilities = try container.decode([ModelCapability].self, forKey: .capabilities, default: [.chat, .streaming])
        supportsStreaming = try container.decode(Bool.self, forKey: .supportsStreaming, default: true)
        supportsToolCalling = try container.decode(Bool.self, forKey: .supportsToolCalling, default: false)
        supportsEmbeddings = try container.decode(Bool.self, forKey: .supportsEmbeddings, default: false)
        supportsVision = try container.decode(Bool.self, forKey: .supportsVision, default: false)
        contextWindowTokens = try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens)
        inputCostPerMillionTokens = try container.decodeIfPresent(Double.self, forKey: .inputCostPerMillionTokens)
        outputCostPerMillionTokens = try container.decodeIfPresent(Double.self, forKey: .outputCostPerMillionTokens)
        supportsStructuredOutput = try container.decode(Bool.self, forKey: .supportsStructuredOutput, default: false)
        requestOverrides = try container.decode(
            ProviderRequestOverrides.self,
            forKey: .requestOverrides,
            default: ProviderRequestOverrides()
        )
    }
}

extension LLMProviderKind {
    nonisolated var defaultAccessMode: ProviderAccessMode {
        switch self {
        case .ollama, .lmStudio:
            .localServer
        case .chatGPTCLI, .claudeCodeCLI:
            .subscriptionCLI
        case .customOpenAICompatible:
            .openAICompatible
        case .vercelAISDKBridge:
            .aiSDKBridge
        case .openAI, .anthropic, .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity:
            .apiKey
        }
    }

    nonisolated var defaultPrivacyScope: ProviderPrivacyScope {
        switch self {
        case .ollama, .lmStudio:
            .localOnly
        case .chatGPTCLI, .claudeCodeCLI:
            .localCLI
        case .vercelAISDKBridge:
            .bridgeService
        case .openAI, .anthropic, .gemini, .xAI, .mistral, .groq, .openRouter, .perplexity, .customOpenAICompatible:
            .externalAPI
        }
    }
}

struct CreatorAccount: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var platform: ContentPlatform
    var handle: String
    var displayName: String
    var profileURL: URL?
    var followerCount: Int?
    var lastSyncedAt: Date?
    var platformAccountID: String?
    var connectionStatus: IntegrationConnectionStatus
    var syncStatus: WorkspaceSyncStatus
    var lastSyncErrorMessage: String?
    var pendingImportCount: Int
    var readAccessGranted: Bool
    var publishAccessGranted: Bool
    var tags: [String]

    init(
        id: UUID = UUID(),
        platform: ContentPlatform,
        handle: String,
        displayName: String,
        profileURL: URL? = nil,
        followerCount: Int? = nil,
        lastSyncedAt: Date? = nil,
        platformAccountID: String? = nil,
        connectionStatus: IntegrationConnectionStatus = .disconnected,
        syncStatus: WorkspaceSyncStatus = .idle,
        lastSyncErrorMessage: String? = nil,
        pendingImportCount: Int = 0,
        readAccessGranted: Bool = true,
        publishAccessGranted: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.platform = platform
        self.handle = handle
        self.displayName = displayName
        self.profileURL = profileURL
        self.followerCount = followerCount
        self.lastSyncedAt = lastSyncedAt
        self.platformAccountID = platformAccountID
        self.connectionStatus = connectionStatus
        self.syncStatus = syncStatus
        self.lastSyncErrorMessage = lastSyncErrorMessage
        self.pendingImportCount = pendingImportCount
        self.readAccessGranted = readAccessGranted
        self.publishAccessGranted = publishAccessGranted
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        platform = try container.decode(ContentPlatform.self, forKey: .platform)
        handle = try container.decode(String.self, forKey: .handle)
        displayName = try container.decode(String.self, forKey: .displayName)
        profileURL = try container.decodeIfPresent(URL.self, forKey: .profileURL)
        followerCount = try container.decodeIfPresent(Int.self, forKey: .followerCount)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        platformAccountID = try container.decodeIfPresent(String.self, forKey: .platformAccountID)
        connectionStatus = try container.decode(
            IntegrationConnectionStatus.self,
            forKey: .connectionStatus,
            default: .disconnected
        )
        syncStatus = try container.decode(WorkspaceSyncStatus.self, forKey: .syncStatus, default: .idle)
        lastSyncErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastSyncErrorMessage)
        pendingImportCount = try container.decode(Int.self, forKey: .pendingImportCount, default: 0)
        readAccessGranted = try container.decode(Bool.self, forKey: .readAccessGranted, default: true)
        publishAccessGranted = try container.decode(Bool.self, forKey: .publishAccessGranted, default: false)
        tags = try container.decode([String].self, forKey: .tags, default: [])
    }
}

struct LibraryAsset: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var kind: LibraryAssetKind
    var platform: ContentPlatform?
    var sourceURL: URL?
    var sourceIdentifier: String?
    var summary: String
    var summaryStatus: SummaryStatus
    var summaryRecords: [SummaryRecord]
    var tags: [String]
    var projectID: UUID?
    var draftID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var capturedAt: Date
    var publishedAt: Date?
    var authorName: String?
    var channelTitle: String?
    var transcript: TranscriptRecord?
    var notes: String
    var durationSeconds: Int?
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        title: String,
        kind: LibraryAssetKind,
        platform: ContentPlatform? = nil,
        sourceURL: URL? = nil,
        sourceIdentifier: String? = nil,
        summary: String = "",
        summaryStatus: SummaryStatus = .missing,
        summaryRecords: [SummaryRecord] = [],
        tags: [String] = [],
        projectID: UUID? = nil,
        draftID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        capturedAt: Date = .now,
        publishedAt: Date? = nil,
        authorName: String? = nil,
        channelTitle: String? = nil,
        transcript: TranscriptRecord? = nil,
        notes: String = "",
        durationSeconds: Int? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.platform = platform
        self.sourceURL = sourceURL
        self.sourceIdentifier = sourceIdentifier
        self.summary = summary
        self.summaryStatus = summaryStatus
        self.summaryRecords = summaryRecords
        self.tags = tags
        self.projectID = projectID
        self.draftID = draftID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.capturedAt = capturedAt
        self.publishedAt = publishedAt
        self.authorName = authorName
        self.channelTitle = channelTitle
        self.transcript = transcript
        self.notes = notes
        self.durationSeconds = durationSeconds
        self.isArchived = isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(LibraryAssetKind.self, forKey: .kind)
        platform = try container.decodeIfPresent(ContentPlatform.self, forKey: .platform)
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
        sourceIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceIdentifier)
        summary = try container.decode(String.self, forKey: .summary, default: "")
        summaryStatus = try container.decode(SummaryStatus.self, forKey: .summaryStatus, default: .missing)
        summaryRecords = try container.decode([SummaryRecord].self, forKey: .summaryRecords, default: [])
        tags = try container.decode([String].self, forKey: .tags, default: [])
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        draftID = try container.decodeIfPresent(UUID.self, forKey: .draftID)
        createdAt = try container.decode(Date.self, forKey: .createdAt, default: .now)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt, default: createdAt)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt, default: createdAt)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
        channelTitle = try container.decodeIfPresent(String.self, forKey: .channelTitle)
        transcript = try container.decodeIfPresent(TranscriptRecord.self, forKey: .transcript)
        notes = try container.decode(String.self, forKey: .notes, default: "")
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        isArchived = try container.decode(Bool.self, forKey: .isArchived, default: false)
    }
}

struct WorkspaceProject: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var summary: String
    var notes: String
    var status: ProjectStatus
    var linkedAccountIDs: [UUID]
    var assetIDs: [UUID]
    var draftIDs: [UUID]
    var calendarEntryIDs: [UUID]
    var automationIDs: [UUID]
    var publishTargets: [ContentPlatform]
    var tagNames: [String]
    var dueDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var lastActivityAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        summary: String = "",
        notes: String = "",
        status: ProjectStatus = .active,
        linkedAccountIDs: [UUID] = [],
        assetIDs: [UUID] = [],
        draftIDs: [UUID] = [],
        calendarEntryIDs: [UUID] = [],
        automationIDs: [UUID] = [],
        publishTargets: [ContentPlatform] = [],
        tagNames: [String] = [],
        dueDate: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastActivityAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.notes = notes
        self.status = status
        self.linkedAccountIDs = linkedAccountIDs
        self.assetIDs = assetIDs
        self.draftIDs = draftIDs
        self.calendarEntryIDs = calendarEntryIDs
        self.automationIDs = automationIDs
        self.publishTargets = publishTargets
        self.tagNames = tagNames
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActivityAt = lastActivityAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary, default: "")
        notes = try container.decode(String.self, forKey: .notes, default: "")
        status = try container.decode(ProjectStatus.self, forKey: .status, default: .active)
        linkedAccountIDs = try container.decode([UUID].self, forKey: .linkedAccountIDs, default: [])
        assetIDs = try container.decode([UUID].self, forKey: .assetIDs, default: [])
        draftIDs = try container.decode([UUID].self, forKey: .draftIDs, default: [])
        calendarEntryIDs = try container.decode([UUID].self, forKey: .calendarEntryIDs, default: [])
        automationIDs = try container.decode([UUID].self, forKey: .automationIDs, default: [])
        publishTargets = try container.decode([ContentPlatform].self, forKey: .publishTargets, default: [])
        tagNames = try container.decode([String].self, forKey: .tagNames, default: [])
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        createdAt = try container.decode(Date.self, forKey: .createdAt, default: .now)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt, default: createdAt)
        lastActivityAt = try container.decode(Date.self, forKey: .lastActivityAt, default: updatedAt)
    }
}

struct DraftDocument: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var platform: ContentPlatform
    var status: DraftStatus
    var body: String
    var summary: String
    var projectID: UUID?
    var scheduledFor: Date?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var sourceAssetIDs: [UUID]
    var outline: [String]
    var publishNotes: String
    var summaryRecords: [SummaryRecord]
    var lastExportedAt: Date?
    var wordCountEstimate: Int
    var requiresReview: Bool

    init(
        id: UUID = UUID(),
        title: String,
        platform: ContentPlatform,
        status: DraftStatus = .idea,
        body: String = "",
        summary: String = "",
        projectID: UUID? = nil,
        scheduledFor: Date? = nil,
        tags: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sourceAssetIDs: [UUID] = [],
        outline: [String] = [],
        publishNotes: String = "",
        summaryRecords: [SummaryRecord] = [],
        lastExportedAt: Date? = nil,
        wordCountEstimate: Int = 0,
        requiresReview: Bool = false
    ) {
        self.id = id
        self.title = title
        self.platform = platform
        self.status = status
        self.body = body
        self.summary = summary
        self.projectID = projectID
        self.scheduledFor = scheduledFor
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceAssetIDs = sourceAssetIDs
        self.outline = outline
        self.publishNotes = publishNotes
        self.summaryRecords = summaryRecords
        self.lastExportedAt = lastExportedAt
        self.wordCountEstimate = wordCountEstimate
        self.requiresReview = requiresReview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        platform = try container.decode(ContentPlatform.self, forKey: .platform)
        status = try container.decode(DraftStatus.self, forKey: .status, default: .idea)
        body = try container.decode(String.self, forKey: .body, default: "")
        summary = try container.decode(String.self, forKey: .summary, default: "")
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        scheduledFor = try container.decodeIfPresent(Date.self, forKey: .scheduledFor)
        tags = try container.decode([String].self, forKey: .tags, default: [])
        createdAt = try container.decode(Date.self, forKey: .createdAt, default: .now)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt, default: createdAt)
        sourceAssetIDs = try container.decode([UUID].self, forKey: .sourceAssetIDs, default: [])
        outline = try container.decode([String].self, forKey: .outline, default: [])
        publishNotes = try container.decode(String.self, forKey: .publishNotes, default: "")
        summaryRecords = try container.decode([SummaryRecord].self, forKey: .summaryRecords, default: [])
        lastExportedAt = try container.decodeIfPresent(Date.self, forKey: .lastExportedAt)
        wordCountEstimate = try container.decode(Int.self, forKey: .wordCountEstimate, default: body.split(whereSeparator: \.isWhitespace).count)
        requiresReview = try container.decode(Bool.self, forKey: .requiresReview, default: false)
    }
}

struct PublishingCalendarEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var startAt: Date
    var endAt: Date?
    var destination: WorkspaceDestination
    var projectID: UUID?
    var draftID: UUID?
    var notes: String
    var platform: ContentPlatform?
    var status: CalendarEntryStatus
    var reminderMinutesBefore: Int?
    var automationID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        startAt: Date,
        endAt: Date? = nil,
        destination: WorkspaceDestination,
        projectID: UUID? = nil,
        draftID: UUID? = nil,
        notes: String = "",
        platform: ContentPlatform? = nil,
        status: CalendarEntryStatus = .draft,
        reminderMinutesBefore: Int? = nil,
        automationID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.destination = destination
        self.projectID = projectID
        self.draftID = draftID
        self.notes = notes
        self.platform = platform
        self.status = status
        self.reminderMinutesBefore = reminderMinutesBefore
        self.automationID = automationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startAt = try container.decode(Date.self, forKey: .startAt)
        endAt = try container.decodeIfPresent(Date.self, forKey: .endAt)
        destination = try container.decode(WorkspaceDestination.self, forKey: .destination)
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        draftID = try container.decodeIfPresent(UUID.self, forKey: .draftID)
        notes = try container.decode(String.self, forKey: .notes, default: "")
        platform = try container.decodeIfPresent(ContentPlatform.self, forKey: .platform)
        status = try container.decode(CalendarEntryStatus.self, forKey: .status, default: .draft)
        reminderMinutesBefore = try container.decodeIfPresent(Int.self, forKey: .reminderMinutesBefore)
        automationID = try container.decodeIfPresent(UUID.self, forKey: .automationID)
        createdAt = try container.decode(Date.self, forKey: .createdAt, default: startAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt, default: createdAt)
    }
}

enum LocalMemoryCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case preference
    case profile
    case project
    case workflow
    case writingStyle
    case fact
    case instruction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preference:
            "Preference"
        case .profile:
            "Profile"
        case .project:
            "Project"
        case .workflow:
            "Workflow"
        case .writingStyle:
            "Writing Style"
        case .fact:
            "Fact"
        case .instruction:
            "Instruction"
        }
    }

    var detail: String {
        switch self {
        case .preference:
            "User choices, defaults, and model behavior preferences."
        case .profile:
            "Stable personal, role, or audience context."
        case .project:
            "Persistent project details and constraints."
        case .workflow:
            "Repeatable process or tool-use habits."
        case .writingStyle:
            "Tone, voice, style, and formatting preferences."
        case .fact:
            "General durable facts the assistant should keep in mind."
        case .instruction:
            "Standing instructions for future chats."
        }
    }

    var systemImage: String {
        switch self {
        case .preference:
            "slider.horizontal.3"
        case .profile:
            "person.crop.circle"
        case .project:
            "folder"
        case .workflow:
            "flowchart"
        case .writingStyle:
            "text.quote"
        case .fact:
            "text.book.closed"
        case .instruction:
            "checklist"
        }
    }
}

struct LocalMemoryRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var detail: String
    var category: LocalMemoryCategory
    var tagNames: [String]
    var sourceThreadID: UUID?
    var sourceMessageID: UUID?
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var useCount: Int

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        category: LocalMemoryCategory = .fact,
        tagNames: [String] = [],
        sourceThreadID: UUID? = nil,
        sourceMessageID: UUID? = nil,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastUsedAt: Date? = nil,
        useCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.category = category
        self.tagNames = tagNames
        self.sourceThreadID = sourceThreadID
        self.sourceMessageID = sourceMessageID
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id, default: UUID())
        title = try container.decode(String.self, forKey: .title, default: "")
        detail = try container.decode(String.self, forKey: .detail, default: "")
        category = try container.decode(LocalMemoryCategory.self, forKey: .category, default: .fact)
        tagNames = try container.decode([String].self, forKey: .tagNames, default: [])
        sourceThreadID = try container.decodeIfPresent(UUID.self, forKey: .sourceThreadID)
        sourceMessageID = try container.decodeIfPresent(UUID.self, forKey: .sourceMessageID)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled, default: true)
        createdAt = try container.decode(Date.self, forKey: .createdAt, default: .now)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt, default: createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        useCount = try container.decode(Int.self, forKey: .useCount, default: 0)
    }
}

nonisolated struct LocalMemorySettings: Codable, Hashable, Sendable {
    var isEnabled: Bool
    var includeInChatContext: Bool
    var maximumContextMemories: Int
    var requireExplicitSave: Bool

    init(
        isEnabled: Bool = true,
        includeInChatContext: Bool = true,
        maximumContextMemories: Int = 8,
        requireExplicitSave: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.includeInChatContext = includeInChatContext
        self.maximumContextMemories = maximumContextMemories
        self.requireExplicitSave = requireExplicitSave
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled, default: true)
        includeInChatContext = try container.decode(Bool.self, forKey: .includeInChatContext, default: true)
        maximumContextMemories = try container.decode(Int.self, forKey: .maximumContextMemories, default: 8)
        requireExplicitSave = try container.decode(Bool.self, forKey: .requireExplicitSave, default: true)
    }
}

nonisolated struct AssistantMessage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var role: AssistantRole
    var text: String
    var attachments: [AIChatAttachment]
    var createdAt: Date
    var updatedAt: Date?
    var isPinned: Bool
    var referencedEntityIDs: [UUID]
    var citations: [AIChatCitation]
    var providerDisplayName: String?
    var modelIdentifier: String?
    var inputTokenCount: Int?
    var outputTokenCount: Int?
    var latencyMilliseconds: Int?
    var firstTokenLatencyMilliseconds: Int?
    var estimatedCostMicros: Int?
    var providerAccessMode: ProviderAccessMode?
    var providerPrivacyScope: ProviderPrivacyScope?
    var runStatus: AssistantMessageRunStatus?
    var startedAt: Date?
    var completedAt: Date?
    var contextTokenCount: Int?
    var contextWindowTokens: Int?
    var tokenCountsAreEstimated: Bool
    var fallbackReason: String?
    var toolCalls: [AIToolCallRecord]

    nonisolated init(
        id: UUID = UUID(),
        role: AssistantRole,
        text: String,
        attachments: [AIChatAttachment] = [],
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        isPinned: Bool = false,
        referencedEntityIDs: [UUID] = [],
        citations: [AIChatCitation] = [],
        providerDisplayName: String? = nil,
        modelIdentifier: String? = nil,
        inputTokenCount: Int? = nil,
        outputTokenCount: Int? = nil,
        latencyMilliseconds: Int? = nil,
        firstTokenLatencyMilliseconds: Int? = nil,
        estimatedCostMicros: Int? = nil,
        providerAccessMode: ProviderAccessMode? = nil,
        providerPrivacyScope: ProviderPrivacyScope? = nil,
        runStatus: AssistantMessageRunStatus? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        contextTokenCount: Int? = nil,
        contextWindowTokens: Int? = nil,
        tokenCountsAreEstimated: Bool = false,
        fallbackReason: String? = nil,
        toolCalls: [AIToolCallRecord] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.referencedEntityIDs = referencedEntityIDs
        self.citations = citations
        self.providerDisplayName = providerDisplayName
        self.modelIdentifier = modelIdentifier
        self.inputTokenCount = inputTokenCount
        self.outputTokenCount = outputTokenCount
        self.latencyMilliseconds = latencyMilliseconds
        self.firstTokenLatencyMilliseconds = firstTokenLatencyMilliseconds
        self.estimatedCostMicros = estimatedCostMicros
        self.providerAccessMode = providerAccessMode
        self.providerPrivacyScope = providerPrivacyScope
        self.runStatus = runStatus
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.contextTokenCount = contextTokenCount
        self.contextWindowTokens = contextWindowTokens
        self.tokenCountsAreEstimated = tokenCountsAreEstimated
        self.fallbackReason = fallbackReason
        self.toolCalls = toolCalls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(AssistantRole.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        attachments = try container.decode([AIChatAttachment].self, forKey: .attachments, default: [])
        createdAt = try container.decode(Date.self, forKey: .createdAt, default: .now)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        isPinned = try container.decode(Bool.self, forKey: .isPinned, default: false)
        referencedEntityIDs = try container.decode([UUID].self, forKey: .referencedEntityIDs, default: [])
        citations = try container.decode([AIChatCitation].self, forKey: .citations, default: [])
        providerDisplayName = try container.decodeIfPresent(String.self, forKey: .providerDisplayName)
        modelIdentifier = try container.decodeIfPresent(String.self, forKey: .modelIdentifier)
        inputTokenCount = try container.decodeIfPresent(Int.self, forKey: .inputTokenCount)
        outputTokenCount = try container.decodeIfPresent(Int.self, forKey: .outputTokenCount)
        latencyMilliseconds = try container.decodeIfPresent(Int.self, forKey: .latencyMilliseconds)
        firstTokenLatencyMilliseconds = try container.decodeIfPresent(Int.self, forKey: .firstTokenLatencyMilliseconds)
        estimatedCostMicros = try container.decodeIfPresent(Int.self, forKey: .estimatedCostMicros)
        providerAccessMode = try container.decodeIfPresent(ProviderAccessMode.self, forKey: .providerAccessMode)
        providerPrivacyScope = try container.decodeIfPresent(ProviderPrivacyScope.self, forKey: .providerPrivacyScope)
        runStatus = try container.decodeIfPresent(AssistantMessageRunStatus.self, forKey: .runStatus)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        contextTokenCount = try container.decodeIfPresent(Int.self, forKey: .contextTokenCount)
        contextWindowTokens = try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens)
        tokenCountsAreEstimated = try container.decode(Bool.self, forKey: .tokenCountsAreEstimated, default: false)
        fallbackReason = try container.decodeIfPresent(String.self, forKey: .fallbackReason)
        toolCalls = try container.decode([AIToolCallRecord].self, forKey: .toolCalls, default: [])
    }
}

nonisolated struct AssistantThread: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var mode: AssistantMode
    var messages: [AssistantMessage]
    var isPinned: Bool
    var isArchived: Bool
    var tagNames: [String]
    var knowledgeSourceIDs: [UUID]
    var folderID: UUID?
    var pinnedProjectID: UUID?
    var pinnedDraftID: UUID?
    var pinnedAssetID: UUID?
    var pinnedCalendarEntryID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        mode: AssistantMode = .workspaceCopilot,
        messages: [AssistantMessage] = [],
        isPinned: Bool = false,
        isArchived: Bool = false,
        tagNames: [String] = [],
        knowledgeSourceIDs: [UUID] = [],
        folderID: UUID? = nil,
        pinnedProjectID: UUID? = nil,
        pinnedDraftID: UUID? = nil,
        pinnedAssetID: UUID? = nil,
        pinnedCalendarEntryID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.messages = messages
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.tagNames = tagNames
        self.knowledgeSourceIDs = knowledgeSourceIDs
        self.folderID = folderID
        self.pinnedProjectID = pinnedProjectID
        self.pinnedDraftID = pinnedDraftID
        self.pinnedAssetID = pinnedAssetID
        self.pinnedCalendarEntryID = pinnedCalendarEntryID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        mode = try container.decode(AssistantMode.self, forKey: .mode, default: .workspaceCopilot)
        messages = try container.decode([AssistantMessage].self, forKey: .messages, default: [])
        isPinned = try container.decode(Bool.self, forKey: .isPinned, default: false)
        isArchived = try container.decode(Bool.self, forKey: .isArchived, default: false)
        tagNames = try container.decode([String].self, forKey: .tagNames, default: [])
        knowledgeSourceIDs = try container.decode([UUID].self, forKey: .knowledgeSourceIDs, default: [])
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        pinnedProjectID = try container.decodeIfPresent(UUID.self, forKey: .pinnedProjectID)
        pinnedDraftID = try container.decodeIfPresent(UUID.self, forKey: .pinnedDraftID)
        pinnedAssetID = try container.decodeIfPresent(UUID.self, forKey: .pinnedAssetID)
        pinnedCalendarEntryID = try container.decodeIfPresent(UUID.self, forKey: .pinnedCalendarEntryID)
        createdAt = try container.decode(Date.self, forKey: .createdAt, default: .now)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt, default: createdAt)
    }
}

struct WorkspaceAutomation: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var detail: String
    var cadence: AutomationCadence
    var isEnabled: Bool
    var requiresConfirmation: Bool
    var linkedDestination: WorkspaceDestination
    var linkedProjectID: UUID?
    var actionKind: LocalActionKind
    var lastRunState: AutomationRunState
    var lastRunAt: Date?
    var nextRunAt: Date?
    var lastResultMessage: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        cadence: AutomationCadence,
        isEnabled: Bool = true,
        requiresConfirmation: Bool,
        linkedDestination: WorkspaceDestination,
        linkedProjectID: UUID? = nil,
        actionKind: LocalActionKind,
        lastRunState: AutomationRunState = .idle,
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil,
        lastResultMessage: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.cadence = cadence
        self.isEnabled = isEnabled
        self.requiresConfirmation = requiresConfirmation
        self.linkedDestination = linkedDestination
        self.linkedProjectID = linkedProjectID
        self.actionKind = actionKind
        self.lastRunState = lastRunState
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
        self.lastResultMessage = lastResultMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct LocalActionRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: LocalActionKind
    var title: String
    var detail: String
    var status: LocalActionStatus
    var destination: WorkspaceDestination
    var relatedProjectID: UUID?
    var relatedDraftID: UUID?
    var relatedAssetID: UUID?
    var automationID: UUID?
    var requiresConfirmation: Bool
    var createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        kind: LocalActionKind,
        title: String,
        detail: String,
        status: LocalActionStatus = .queued,
        destination: WorkspaceDestination,
        relatedProjectID: UUID? = nil,
        relatedDraftID: UUID? = nil,
        relatedAssetID: UUID? = nil,
        automationID: UUID? = nil,
        requiresConfirmation: Bool = false,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.status = status
        self.destination = destination
        self.relatedProjectID = relatedProjectID
        self.relatedDraftID = relatedDraftID
        self.relatedAssetID = relatedAssetID
        self.automationID = automationID
        self.requiresConfirmation = requiresConfirmation
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

nonisolated struct WorkspacePreferences: Codable, Hashable, Sendable {
    var preferredProviderID: UUID?
    var providerRoutingPolicy: ProviderRoutingPolicy
    var lastOpenedAt: Date
    var defaultDestination: WorkspaceDestination
    var showsRightSidebar: Bool
    var leftSidebarWidth: Double
    var rightSidebarWidth: Double
    var automationsEnabled: Bool?
    var confirmBeforeExternalActions: Bool?
    var allowCloudProviders: Bool?
    var defaultTranscriptLanguageCode: String?
    var draftExportDirectory: String?
    var localStorageLabel: String?
    var safeMode: Bool?
    var localOnlyMode: Bool?
    var defaultSystemPromptProfileID: UUID?
    var defaultModelPresetID: UUID?
    var localMemory: LocalMemorySettings?

    init(
        preferredProviderID: UUID? = nil,
        providerRoutingPolicy: ProviderRoutingPolicy = .selectedProvider,
        lastOpenedAt: Date = .now,
        defaultDestination: WorkspaceDestination = .home,
        showsRightSidebar: Bool = true,
        leftSidebarWidth: Double = 220,
        rightSidebarWidth: Double = 360,
        automationsEnabled: Bool = true,
        confirmBeforeExternalActions: Bool = true,
        allowCloudProviders: Bool = false,
        defaultTranscriptLanguageCode: String = "en",
        draftExportDirectory: String = "~/Documents/Flannel/Exports",
        localStorageLabel: String = "~/Library/Application Support/Flannel",
        safeMode: Bool = true,
        localOnlyMode: Bool = true,
        defaultSystemPromptProfileID: UUID? = nil,
        defaultModelPresetID: UUID? = nil,
        localMemory: LocalMemorySettings = LocalMemorySettings()
    ) {
        self.preferredProviderID = preferredProviderID
        self.providerRoutingPolicy = providerRoutingPolicy
        self.lastOpenedAt = lastOpenedAt
        self.defaultDestination = defaultDestination
        self.showsRightSidebar = showsRightSidebar
        self.leftSidebarWidth = leftSidebarWidth
        self.rightSidebarWidth = rightSidebarWidth
        self.automationsEnabled = automationsEnabled
        self.confirmBeforeExternalActions = confirmBeforeExternalActions
        self.allowCloudProviders = allowCloudProviders
        self.defaultTranscriptLanguageCode = defaultTranscriptLanguageCode
        self.draftExportDirectory = draftExportDirectory
        self.localStorageLabel = localStorageLabel
        self.safeMode = safeMode
        self.localOnlyMode = localOnlyMode
        self.defaultSystemPromptProfileID = defaultSystemPromptProfileID
        self.defaultModelPresetID = defaultModelPresetID
        self.localMemory = localMemory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredProviderID = try container.decodeIfPresent(UUID.self, forKey: .preferredProviderID)
        providerRoutingPolicy = try container.decode(
            ProviderRoutingPolicy.self,
            forKey: .providerRoutingPolicy,
            default: .selectedProvider
        )
        lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt, default: .now)
        defaultDestination = try container.decode(
            WorkspaceDestination.self,
            forKey: .defaultDestination,
            default: .home
        )
        showsRightSidebar = try container.decode(Bool.self, forKey: .showsRightSidebar, default: true)
        leftSidebarWidth = try container.decode(Double.self, forKey: .leftSidebarWidth, default: 220)
        rightSidebarWidth = try container.decode(Double.self, forKey: .rightSidebarWidth, default: 360)
        automationsEnabled = try container.decode(Bool.self, forKey: .automationsEnabled, default: true)
        confirmBeforeExternalActions = try container.decode(
            Bool.self,
            forKey: .confirmBeforeExternalActions,
            default: true
        )
        allowCloudProviders = try container.decode(Bool.self, forKey: .allowCloudProviders, default: false)
        defaultTranscriptLanguageCode = try container.decode(
            String.self,
            forKey: .defaultTranscriptLanguageCode,
            default: "en"
        )
        draftExportDirectory = try container.decode(
            String.self,
            forKey: .draftExportDirectory,
            default: "~/Documents/Flannel/Exports"
        )
        localStorageLabel = try container.decode(
            String.self,
            forKey: .localStorageLabel,
            default: "~/Library/Application Support/Flannel"
        )
        safeMode = try container.decode(Bool.self, forKey: .safeMode, default: true)
        localOnlyMode = try container.decode(Bool.self, forKey: .localOnlyMode, default: true)
        defaultSystemPromptProfileID = try container.decodeIfPresent(UUID.self, forKey: .defaultSystemPromptProfileID)
        defaultModelPresetID = try container.decodeIfPresent(UUID.self, forKey: .defaultModelPresetID)
        localMemory = try container.decode(LocalMemorySettings.self, forKey: .localMemory, default: LocalMemorySettings())
    }
}

@Model
final class Item {
    @Attribute(.unique) var workspaceID: UUID
    var schemaVersion: Int
    var timestamp: Date
    var updatedAt: Date
    var selectedDestinationRawValue: String
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
    var automations: [WorkspaceAutomation]?
    var localActionHistory: [LocalActionRecord]?
    var tags: [WorkspaceTag]?
    var chatFolders: [ChatFolder]?
    var promptProfiles: [SystemPromptProfile]?
    var chatTemplates: [ChatTemplate]?
    var modelPresets: [ModelPreset]?
    var knowledgeSources: [KnowledgeSource]?
    var knowledgeIndexManifests: [KnowledgeIndexManifest]?
    var toolConfigurations: [ToolConfiguration]?
    var toolExecutionResults: [LocalToolExecutionResult]?
    var modelComparisonRuns: [ModelComparisonRun]?
    var pinnedMessages: [PinnedAssistantMessage]?
    var archivedAssistantThreadIDs: [UUID]?
    var localMemories: [LocalMemoryRecord]?
    var preferences: WorkspacePreferences

    init(
        workspaceID: UUID = UUID(),
        schemaVersion: Int = 4,
        timestamp: Date = .now,
        updatedAt: Date = .now,
        selectedDestination: WorkspaceDestination = .home,
        selectedProjectID: UUID? = nil,
        selectedDraftID: UUID? = nil,
        selectedAssetID: UUID? = nil,
        selectedCalendarEntryID: UUID? = nil,
        selectedAssistantThreadID: UUID? = nil,
        accounts: [CreatorAccount] = [],
        providerConfigurations: [ProviderConfiguration] = [],
        libraryAssets: [LibraryAsset] = [],
        projects: [WorkspaceProject] = [],
        drafts: [DraftDocument] = [],
        calendarEntries: [PublishingCalendarEntry] = [],
        assistantThreads: [AssistantThread] = [],
        automations: [WorkspaceAutomation] = [],
        localActionHistory: [LocalActionRecord] = [],
        tags: [WorkspaceTag] = [],
        chatFolders: [ChatFolder] = [],
        promptProfiles: [SystemPromptProfile] = [],
        chatTemplates: [ChatTemplate] = [],
        modelPresets: [ModelPreset] = [],
        knowledgeSources: [KnowledgeSource] = [],
        knowledgeIndexManifests: [KnowledgeIndexManifest] = [],
        toolConfigurations: [ToolConfiguration] = [],
        toolExecutionResults: [LocalToolExecutionResult] = [],
        modelComparisonRuns: [ModelComparisonRun] = [],
        pinnedMessages: [PinnedAssistantMessage] = [],
        archivedAssistantThreadIDs: [UUID] = [],
        localMemories: [LocalMemoryRecord] = [],
        preferences: WorkspacePreferences = WorkspacePreferences()
    ) {
        self.workspaceID = workspaceID
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.updatedAt = updatedAt
        self.selectedDestinationRawValue = selectedDestination.rawValue
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
        self.modelPresets = modelPresets
        self.knowledgeSources = knowledgeSources
        self.knowledgeIndexManifests = knowledgeIndexManifests
        self.toolConfigurations = toolConfigurations
        self.toolExecutionResults = toolExecutionResults
        self.modelComparisonRuns = modelComparisonRuns
        self.pinnedMessages = pinnedMessages
        self.archivedAssistantThreadIDs = archivedAssistantThreadIDs
        self.localMemories = localMemories
        self.preferences = preferences
    }

    var selectedDestination: WorkspaceDestination {
        get { WorkspaceDestination(rawValue: selectedDestinationRawValue) ?? .home }
        set { selectedDestinationRawValue = newValue.rawValue }
    }

    func touch() {
        updatedAt = .now
        preferences.lastOpenedAt = updatedAt
    }
}

private extension KeyedDecodingContainer {
    nonisolated func decode<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) throws -> T {
        try decodeIfPresent(type, forKey: key) ?? defaultValue
    }
}
