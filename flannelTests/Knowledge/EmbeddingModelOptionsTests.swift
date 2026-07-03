//
//  EmbeddingModelOptionsTests.swift
//  flannelTests
//

import Foundation
import SwiftData
import Testing
@testable import flannel

struct EmbeddingModelOptionsTests {
    @MainActor
    @Test("Embedding model options exclude discovered local chat-only models")
    func embeddingModelOptionsExcludeDiscoveredLocalChatOnlyModels() throws {
        let (_, store) = try makeLoadedStore()
        let endpoint = "http://localhost:1234"
        configureMixedLMStudioCatalog(on: store, endpoint: endpoint)

        #expect(store.embeddingModelOptions.contains(LocalEmbeddingService.deterministicModelIdentifier))
        #expect(store.embeddingModelOptions.contains("embed-local"))
        #expect(store.embeddingModelOptions.contains("plain-chat") == false)
    }

    @MainActor
    @Test("Provider backed indexing rejects discovered local chat-only embedding choice")
    func providerBackedIndexingRejectsDiscoveredLocalChatOnlyEmbeddingChoice() async throws {
        let (_, store) = try makeLoadedStore()
        let endpoint = "http://localhost:1234"
        configureMixedLMStudioCatalog(on: store, endpoint: endpoint)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-chat-only-embedding-\(UUID().uuidString).txt")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "This source should not index with a chat-only model.".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
        store.knowledgeSources = [
            KnowledgeSource(
                title: "Chat-only embedding source",
                kind: .file,
                location: fileURL.path,
                status: .queued,
                embeddingModelIdentifier: "plain-chat"
            )
        ]
        store.knowledgeIndexManifests = []

        await store.rebuildKnowledgeIndexManifestsUsingConfiguredEmbeddings()

        let source = try #require(store.knowledgeSources.first)
        #expect(source.status == .failed)
        #expect(source.lastErrorMessage?.contains("No enabled embedding provider is configured for plain-chat") == true)
        #expect(store.knowledgeIndexManifests.first?.status == .failed)
    }

    @MainActor
    private func makeLoadedStore() throws -> (ModelContainer, WorkspaceStore) {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let store = WorkspaceStore()
        try store.loadOrCreate(in: ModelContext(container))
        return (container, store)
    }

    @MainActor
    private func configureMixedLMStudioCatalog(on store: WorkspaceStore, endpoint: String) {
        store.providerConfigurations = [
            ProviderConfiguration(
                kind: .lmStudio,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "LM Studio",
                endpoint: endpoint,
                modelIdentifier: "plain-chat",
                availableModels: ["plain-chat", "embed-local"],
                discoveredModelNames: ["plain-chat", "embed-local"],
                capabilities: [.chat, .streaming, .embeddings],
                supportsStreaming: true,
                supportsEmbeddings: true
            )
        ]
        store.localDiscoveryResults = [
            LocalProviderDiscoveryResult(
                providerKind: .lmStudio,
                endpoint: endpoint,
                status: .ready,
                models: [
                    LocalModelDescriptor(
                        name: "plain-chat",
                        providerKind: .lmStudio,
                        endpoint: endpoint,
                        capabilities: [.chat, .streaming, .openAICompatible]
                    ),
                    LocalModelDescriptor(
                        name: "embed-local",
                        providerKind: .lmStudio,
                        endpoint: endpoint,
                        capabilities: [.embeddings, .openAICompatible]
                    )
                ]
            )
        ]
    }
}
