//
//  WorkspaceSnapshotServiceTests.swift
//  flannelTests
//

import Foundation
import Testing
@testable import flannel

@MainActor
struct WorkspaceSnapshotServiceTests {
    @Test("Workspace snapshot export includes durable local-first app state")
    func workspaceSnapshotExportIncludesDurableState() throws {
        let store = sampleStore()
        let exportedAt = Date(timeIntervalSince1970: 1_782_730_800)
        let data = try WorkspaceSnapshotService().export(store: store, exportedAt: exportedAt)

        let payload = try JSONDecoder.flannelSnapshot.decode(WorkspaceSnapshotPayload.self, from: data)

        #expect(payload.schemaVersion == WorkspaceSnapshotService.schemaVersion)
        #expect(payload.exportedAt == exportedAt)
        #expect(payload.workspace.selectedDestination == .home)
        #expect(payload.workspace.providerConfigurations.map(\.displayName) == ["OpenAI API", "Local Ollama"])
        #expect(payload.workspace.providerConfigurations.first?.secretReference == "keychain://openai")
        #expect(payload.workspace.providerConfigurations.first?.secretReference != "sk-test-secret")
        #expect(payload.workspace.assistantThreads.map(\.title) == ["Local RAG Thread"])
        #expect(payload.workspace.chatFolders.map(\.title) == ["Research"])
        #expect(payload.workspace.promptProfiles.map(\.title) == ["Careful Local Assistant"])
        #expect(payload.workspace.chatTemplates.map(\.title) == ["Private Research"])
        #expect(payload.workspace.modelPresets.map(\.title) == ["Local fast"])
        #expect(payload.workspace.knowledgeSources.map(\.title) == ["Docs"])
        #expect(payload.workspace.toolConfigurations.map(\.kind) == [.ragRetrieval])
        #expect(payload.workspace.toolExecutionResults.map(\.title) == ["RAG lookup"])
        #expect(payload.workspace.modelComparisonRuns.map(\.prompt) == ["Compare local and hosted routes"])
        #expect(payload.workspace.localDiscoveryResults?.first?.providerKind == .ollama)
        #expect(payload.workspace.localDiscoveryResults?.first?.models.map(\.name) == ["llama3.1", "nomic-embed-text"])
        #expect(payload.workspace.localMemories.map(\.title) == ["Project rule"])
        #expect(payload.workspace.archivedAssistantThreadIDs == [sampleThreadID])
    }

    @Test("Workspace snapshot import creates a local copy with fresh workspace identity")
    func workspaceSnapshotImportCreatesLocalCopy() throws {
        let service = WorkspaceSnapshotService()
        let exportedData = try service.export(
            store: sampleStore(),
            exportedAt: Date(timeIntervalSince1970: 1_782_730_800)
        )
        let importedAt = Date(timeIntervalSince1970: 1_782_731_200)

        let result = try service.importWorkspace(from: exportedData, importedAt: importedAt)

        #expect(result.originalWorkspaceID != result.item.workspaceID)
        #expect(result.importedAt == importedAt)
        #expect(result.item.timestamp == importedAt)
        #expect(result.item.updatedAt == importedAt)
        #expect(result.item.preferences.lastOpenedAt == importedAt)
        #expect(result.item.assistantThreads.first?.id == sampleThreadID)
        #expect(result.item.selectedAssistantThreadID == sampleThreadID)
        #expect(result.item.providerConfigurations.first?.displayName == "OpenAI API")
        #expect(result.item.providerConfigurations.first?.secretReference == "keychain://openai")
        #expect(result.item.knowledgeSources?.first?.isWatched == true)
        #expect(result.item.toolExecutionResults?.first?.status == .completed)
        #expect(result.item.modelComparisonRuns?.first?.results.first?.providerDisplayName == "OpenAI API")
        #expect(result.item.localDiscoveryResults?.first?.models.map(\.name) == ["llama3.1", "nomic-embed-text"])
    }

    @Test("Workspace snapshot import rejects unsupported schemas")
    func workspaceSnapshotImportRejectsUnsupportedSchemas() throws {
        let payload = WorkspaceSnapshotPayload(
            schemaVersion: 999,
            exportedAt: Date(timeIntervalSince1970: 1_782_730_800),
            workspace: try JSONDecoder.flannelSnapshot.decode(
                WorkspaceSnapshotPayload.self,
                from: WorkspaceSnapshotService().export(store: sampleStore())
            ).workspace
        )
        let data = try JSONEncoder.flannelSnapshot.encode(payload)

        #expect(throws: WorkspaceSnapshotError.unsupportedSchemaVersion(999)) {
            _ = try WorkspaceSnapshotService().importWorkspace(from: data)
        }
    }

    @Test("Workspace snapshot filenames are stable and explicit")
    func workspaceSnapshotFilenameIsStable() {
        let filename = WorkspaceSnapshotService().defaultFilename(
            for: sampleStore(),
            exportedAt: Date(timeIntervalSince1970: 1_782_730_800)
        )

        #expect(filename == "local-rag-thread-workspace-20260629-110000.flannelworkspace.json")
    }

    private var sampleThreadID: UUID {
        UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    }

    private var sampleProviderID: UUID {
        UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    }

    private var sampleKnowledgeSourceID: UUID {
        UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    }

    private func sampleStore() -> WorkspaceStore {
        let store = WorkspaceStore()
        let now = Date(timeIntervalSince1970: 1_782_730_700)
        let thread = AssistantThread(
            id: sampleThreadID,
            title: "Local RAG Thread",
            mode: .research,
            messages: [
                AssistantMessage(role: .user, text: "Search my private docs", createdAt: now),
                AssistantMessage(
                    role: .assistant,
                    text: "Use local notes first.",
                    createdAt: now,
                    citations: [
                        AIChatCitation(
                            title: "Docs",
                            snippet: "Private launch notes",
                            indexID: sampleKnowledgeSourceID
                        )
                    ],
                    providerDisplayName: "Local Ollama",
                    modelIdentifier: "llama3.1",
                    providerAccessMode: .localServer,
                    providerPrivacyScope: .localOnly,
                    runStatus: .completed,
                    toolCalls: [
                        AIToolCallRecord(
                            toolName: "rag_retrieval",
                            permissionScope: .queryRAGIndex,
                            argumentsJSON: #"{"query":"private docs"}"#,
                            wasApproved: true,
                            executionStatus: .completed,
                            startedAt: now
                        )
                    ]
                )
            ],
            tagNames: ["research"],
            createdAt: now,
            updatedAt: now
        )

        store.selectedDestination = .home
        store.selectedAssistantThreadID = thread.id
        store.providerConfigurations = [
            ProviderConfiguration(
                id: sampleProviderID,
                kind: .openAI,
                accessMode: .apiKey,
                privacyScope: .externalAPI,
                displayName: "OpenAI API",
                endpoint: "https://api.openai.com/v1",
                modelIdentifier: "gpt-5.2",
                secretReference: "keychain://openai",
                capabilities: [.chat, .streaming, .toolCalling, .vision],
                supportsToolCalling: true,
                supportsVision: true,
                contextWindowTokens: 128_000
            ),
            ProviderConfiguration(
                kind: .ollama,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "Local Ollama",
                endpoint: "http://localhost:11434",
                modelIdentifier: "llama3.1",
                isLocalPreferred: true,
                availableModels: ["llama3.1"],
                capabilities: [.chat, .streaming, .toolCalling, .embeddings],
                supportsToolCalling: true,
                supportsEmbeddings: true
            )
        ]
        store.assistantThreads = [thread]
        store.chatFolders = [ChatFolder(id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!, title: "Research")]
        store.promptProfiles = [
            SystemPromptProfile(
                title: "Careful Local Assistant",
                detail: "Prefer local context.",
                prompt: "Stay local unless asked."
            )
        ]
        store.chatTemplates = [
            ChatTemplate(
                title: "Private Research",
                detail: "Grounded private RAG workflow.",
                systemPrompt: "Cite local sources.",
                starterPrompt: "Search my docs.",
                mode: .research,
                knowledgeSourceIDs: [sampleKnowledgeSourceID],
                isPinned: true
            )
        ]
        store.modelPresets = [
            ModelPreset(
                title: "Local fast",
                providerKind: .ollama,
                accessMode: .localServer,
                modelIdentifier: "llama3.1",
                capabilities: [.chat, .streaming],
                privacyScope: .localOnly
            )
        ]
        store.knowledgeSources = [
            KnowledgeSource(
                id: sampleKnowledgeSourceID,
                title: "Docs",
                kind: .folder,
                location: "/Users/example/Documents",
                status: .ready,
                chunkCount: 12,
                embeddingModelIdentifier: "nomic-embed-text",
                isWatched: true,
                exclusionRules: ["node_modules"],
                documentCount: 3,
                embeddingRecordCount: 12,
                vectorDimension: 768
            )
        ]
        store.toolConfigurations = [
            ToolConfiguration(
                kind: .ragRetrieval,
                title: "RAG Retrieval",
                detail: "Search local indexes.",
                permissionPolicy: .alwaysAllow,
                requiresNetwork: false,
                canModifyFiles: false
            )
        ]
        store.toolExecutionResults = [
            LocalToolExecutionResult(
                toolKind: .ragRetrieval,
                title: "RAG lookup",
                query: "private docs",
                status: .completed,
                output: "Private launch notes",
                requiresApproval: false,
                usedNetwork: false,
                modifiedFiles: false,
                createdAt: now
            )
        ]
        store.modelComparisonRuns = [
            ModelComparisonRun(
                prompt: "Compare local and hosted routes",
                providerIDs: [sampleProviderID],
                results: [
                    ModelComparisonResult(
                        provider: store.providerConfigurations[0],
                        status: .completed,
                        text: "Hosted route is best for reasoning."
                    )
                ]
            )
        ]
        store.localDiscoveryResults = [
            LocalProviderDiscoveryResult(
                providerKind: .ollama,
                endpoint: "http://localhost:11434",
                status: .ready,
                models: [
                    LocalModelDescriptor(
                        name: "llama3.1",
                        providerKind: .ollama,
                        endpoint: "http://localhost:11434",
                        contextWindowTokens: 8_192,
                        loadedInstanceCount: 1,
                        capabilities: [.chat, .streaming, .toolCalling]
                    ),
                    LocalModelDescriptor(
                        name: "nomic-embed-text",
                        providerKind: .ollama,
                        endpoint: "http://localhost:11434",
                        capabilities: [.embeddings]
                    )
                ],
                discoveredAt: now
            )
        ]
        store.localMemories = [
            LocalMemoryRecord(
                title: "Project rule",
                detail: "Keep private docs local.",
                category: .preference,
                sourceThreadID: sampleThreadID
            )
        ]
        store.archiveThread(sampleThreadID)
        return store
    }
}

private extension JSONEncoder {
    static var flannelSnapshot: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

private extension JSONDecoder {
    static var flannelSnapshot: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
