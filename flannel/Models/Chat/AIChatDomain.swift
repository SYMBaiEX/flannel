//
//  AIChatDomain.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

enum AIChatThreadMode: String, Codable, CaseIterable, Sendable {
    case assistant
    case workspace
    case research
    case drafting
    case retrieval
}

enum AIChatRole: String, Codable, CaseIterable, Sendable {
    case system
    case user
    case assistant
    case tool
}

enum AIChatMessageState: String, Codable, CaseIterable, Sendable {
    case queued
    case streaming
    case completed
    case failed
    case cancelled
}

enum AIChatAttachmentKind: String, Codable, CaseIterable, Sendable {
    case textSnippet
    case image
    case document
    case audio
    case workspaceAsset
    case externalURL
    case ragChunk
    case toolResult
}

nonisolated struct AIChatAttachment: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: AIChatAttachmentKind
    var title: String
    var mimeType: String?
    var localPath: String?
    var remoteURL: URL?
    var byteCount: Int64?
    var excerpt: String?
    var securityScopedBookmarkData: Data?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: AIChatAttachmentKind,
        title: String,
        mimeType: String? = nil,
        localPath: String? = nil,
        remoteURL: URL? = nil,
        byteCount: Int64? = nil,
        excerpt: String? = nil,
        securityScopedBookmarkData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.mimeType = mimeType
        self.localPath = localPath
        self.remoteURL = remoteURL
        self.byteCount = byteCount
        self.excerpt = excerpt
        self.securityScopedBookmarkData = securityScopedBookmarkData
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(AIChatAttachmentKind.self, forKey: .kind) ?? .document
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Attachment"
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        localPath = try container.decodeIfPresent(String.self, forKey: .localPath)
        remoteURL = try container.decodeIfPresent(URL.self, forKey: .remoteURL)
        byteCount = try container.decodeIfPresent(Int64.self, forKey: .byteCount)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
        securityScopedBookmarkData = try container.decodeIfPresent(Data.self, forKey: .securityScopedBookmarkData)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }
}

nonisolated struct AIChatCitation: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var snippet: String
    var indexID: UUID?
    var sourceIdentifier: String?
    var sourceLocation: String?
    var score: Double?

    init(
        id: UUID = UUID(),
        title: String,
        snippet: String,
        indexID: UUID? = nil,
        sourceIdentifier: String? = nil,
        sourceLocation: String? = nil,
        score: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.indexID = indexID
        self.sourceIdentifier = sourceIdentifier
        self.sourceLocation = sourceLocation
        self.score = score
    }
}

nonisolated struct AIToolCallRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var providerCallID: String?
    var toolName: String
    var permissionScope: AIToolPermissionScope
    var argumentsJSON: String
    var wasApproved: Bool
    var executionStatus: LocalToolExecutionStatus?
    var executionResultID: UUID?
    var outputPreview: String?
    var startedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        providerCallID: String? = nil,
        toolName: String,
        permissionScope: AIToolPermissionScope,
        argumentsJSON: String,
        wasApproved: Bool = false,
        executionStatus: LocalToolExecutionStatus? = nil,
        executionResultID: UUID? = nil,
        outputPreview: String? = nil,
        startedAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.providerCallID = providerCallID
        self.toolName = toolName
        self.permissionScope = permissionScope
        self.argumentsJSON = argumentsJSON
        self.wasApproved = wasApproved
        self.executionStatus = executionStatus
        self.executionResultID = executionResultID
        self.outputPreview = outputPreview
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

nonisolated struct AIChatMessage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var role: AIChatRole
    var text: String
    var state: AIChatMessageState
    var modelIdentifier: String?
    var attachments: [AIChatAttachment]
    var citations: [AIChatCitation]
    var toolCalls: [AIToolCallRecord]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        role: AIChatRole,
        text: String,
        state: AIChatMessageState = .completed,
        modelIdentifier: String? = nil,
        attachments: [AIChatAttachment] = [],
        citations: [AIChatCitation] = [],
        toolCalls: [AIToolCallRecord] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.state = state
        self.modelIdentifier = modelIdentifier
        self.attachments = attachments
        self.citations = citations
        self.toolCalls = toolCalls
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct AIChatThread: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var mode: AIChatThreadMode
    var providerKind: AIProviderKind?
    var providerMode: AIProviderMode?
    var modelIdentifier: String?
    var systemPrompt: String
    var messages: [AIChatMessage]
    var relatedProjectID: UUID?
    var relatedDraftID: UUID?
    var relatedAssetID: UUID?
    var createdAt: Date
    var updatedAt: Date

    var lastMessagePreview: String {
        messages.last?.text ?? ""
    }

    init(
        id: UUID = UUID(),
        title: String,
        mode: AIChatThreadMode = .assistant,
        providerKind: AIProviderKind? = nil,
        providerMode: AIProviderMode? = nil,
        modelIdentifier: String? = nil,
        systemPrompt: String = "",
        messages: [AIChatMessage] = [],
        relatedProjectID: UUID? = nil,
        relatedDraftID: UUID? = nil,
        relatedAssetID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.providerKind = providerKind
        self.providerMode = providerMode
        self.modelIdentifier = modelIdentifier
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.relatedProjectID = relatedProjectID
        self.relatedDraftID = relatedDraftID
        self.relatedAssetID = relatedAssetID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
