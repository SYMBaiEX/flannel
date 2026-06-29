//
//  AIWorkspaceDomain.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

enum AIToolPermissionScope: String, Codable, CaseIterable, Sendable {
    case readWorkspace
    case writeWorkspace
    case runShellCommand
    case makeNetworkRequest
    case queryRAGIndex
    case mutateRAGIndex
}

enum AIToolPermissionMode: String, Codable, CaseIterable, Sendable {
    case denied
    case askEveryTime
    case allowDuringThread
    case alwaysAllow
}

struct AIToolPermission: Identifiable, Codable, Hashable, Sendable {
    var scope: AIToolPermissionScope
    var mode: AIToolPermissionMode
    var appliesToProviders: Set<AIProviderKind>
    var note: String?

    var id: String { scope.rawValue }

    init(
        scope: AIToolPermissionScope,
        mode: AIToolPermissionMode,
        appliesToProviders: Set<AIProviderKind> = [],
        note: String? = nil
    ) {
        self.scope = scope
        self.mode = mode
        self.appliesToProviders = appliesToProviders
        self.note = note
    }
}

enum AIRAGIndexStatus: String, Codable, CaseIterable, Sendable {
    case notBuilt
    case building
    case ready
    case stale
    case failed
}

enum AIRAGIndexScope: String, Codable, CaseIterable, Sendable {
    case workspace
    case project
    case thread
}

struct AIRAGIndexMetadata: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var scope: AIRAGIndexScope
    var embeddingProviderKind: AIProviderKind?
    var embeddingModelIdentifier: String
    var storageLocation: String
    var vectorDimension: Int?
    var documentCount: Int
    var chunkCount: Int
    var lastIndexedAt: Date?
    var sourceRevision: String?
    var status: AIRAGIndexStatus
    var lastErrorMessage: String?

    init(
        id: UUID = UUID(),
        name: String,
        scope: AIRAGIndexScope,
        embeddingProviderKind: AIProviderKind? = nil,
        embeddingModelIdentifier: String,
        storageLocation: String,
        vectorDimension: Int? = nil,
        documentCount: Int = 0,
        chunkCount: Int = 0,
        lastIndexedAt: Date? = nil,
        sourceRevision: String? = nil,
        status: AIRAGIndexStatus = .notBuilt,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.scope = scope
        self.embeddingProviderKind = embeddingProviderKind
        self.embeddingModelIdentifier = embeddingModelIdentifier
        self.storageLocation = storageLocation
        self.vectorDimension = vectorDimension
        self.documentCount = documentCount
        self.chunkCount = chunkCount
        self.lastIndexedAt = lastIndexedAt
        self.sourceRevision = sourceRevision
        self.status = status
        self.lastErrorMessage = lastErrorMessage
    }
}

struct AILocalProviderDiscoverySettings: Codable, Hashable, Sendable {
    var ollamaBaseURL: URL
    var lmStudioBaseURL: URL
    var autoDiscoverOnLaunch: Bool
    var requestTimeoutSeconds: Double

    init(
        ollamaBaseURL: URL = URL(string: "http://localhost:11434")!,
        lmStudioBaseURL: URL = URL(string: "http://localhost:1234")!,
        autoDiscoverOnLaunch: Bool = true,
        requestTimeoutSeconds: Double = 5
    ) {
        self.ollamaBaseURL = ollamaBaseURL
        self.lmStudioBaseURL = lmStudioBaseURL
        self.autoDiscoverOnLaunch = autoDiscoverOnLaunch
        self.requestTimeoutSeconds = requestTimeoutSeconds
    }
}

struct AIWorkspaceSettings: Codable, Hashable, Sendable {
    var preferredProviderKind: AIProviderKind
    var preferredProviderMode: AIProviderMode
    var preferredChatModelIdentifier: String?
    var preferredEmbeddingModelIdentifier: String?
    var defaultThreadMode: AIChatThreadMode
    var allowsCloudFallback: Bool
    var storesHistoryLocallyOnly: Bool
    var maxContextTokens: Int
    var maxRetrievedChunks: Int
    var discovery: AILocalProviderDiscoverySettings
    var toolPermissions: [AIToolPermission]
    var ragIndexes: [AIRAGIndexMetadata]

    init(
        preferredProviderKind: AIProviderKind = .ollama,
        preferredProviderMode: AIProviderMode = .nativeAPI,
        preferredChatModelIdentifier: String? = nil,
        preferredEmbeddingModelIdentifier: String? = nil,
        defaultThreadMode: AIChatThreadMode = .assistant,
        allowsCloudFallback: Bool = false,
        storesHistoryLocallyOnly: Bool = true,
        maxContextTokens: Int = 8_192,
        maxRetrievedChunks: Int = 8,
        discovery: AILocalProviderDiscoverySettings = AILocalProviderDiscoverySettings(),
        toolPermissions: [AIToolPermission] = AIWorkspaceSettings.defaultToolPermissions,
        ragIndexes: [AIRAGIndexMetadata] = []
    ) {
        self.preferredProviderKind = preferredProviderKind
        self.preferredProviderMode = preferredProviderMode
        self.preferredChatModelIdentifier = preferredChatModelIdentifier
        self.preferredEmbeddingModelIdentifier = preferredEmbeddingModelIdentifier
        self.defaultThreadMode = defaultThreadMode
        self.allowsCloudFallback = allowsCloudFallback
        self.storesHistoryLocallyOnly = storesHistoryLocallyOnly
        self.maxContextTokens = maxContextTokens
        self.maxRetrievedChunks = maxRetrievedChunks
        self.discovery = discovery
        self.toolPermissions = toolPermissions
        self.ragIndexes = ragIndexes
    }

    static var defaultToolPermissions: [AIToolPermission] {
        [
            AIToolPermission(scope: .readWorkspace, mode: .alwaysAllow),
            AIToolPermission(scope: .queryRAGIndex, mode: .alwaysAllow),
            AIToolPermission(scope: .writeWorkspace, mode: .askEveryTime),
            AIToolPermission(scope: .mutateRAGIndex, mode: .askEveryTime),
            AIToolPermission(scope: .makeNetworkRequest, mode: .askEveryTime),
            AIToolPermission(scope: .runShellCommand, mode: .denied)
        ]
    }
}
