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
    @Test("OpenAI catalog embedding models are selectable without chat model pollution")
    func openAICatalogEmbeddingModelsAreSelectableWithoutChatModelPollution() throws {
        let (_, store) = try makeLoadedStore()
        let openAIProvider = try #require(store.providerConfigurations.first { $0.kind == .openAI && $0.accessMode == .apiKey })

        #expect(openAIProvider.supportsEmbeddings)
        #expect(openAIProvider.capabilities.contains(.embeddings))
        #expect(store.embeddingModelOptions.contains("text-embedding-3-small"))
        #expect(store.embeddingModelOptions.contains("text-embedding-3-large"))
        #expect(store.embeddingModelOptions.contains(openAIProvider.modelIdentifier) == false)
    }

    @MainActor
    @Test("Gemini catalog embedding models are selectable without chat model pollution")
    func geminiCatalogEmbeddingModelsAreSelectableWithoutChatModelPollution() throws {
        let (_, store) = try makeLoadedStore()
        let geminiProvider = try #require(store.providerConfigurations.first { $0.kind == .gemini && $0.accessMode == .apiKey })

        #expect(geminiProvider.supportsEmbeddings)
        #expect(geminiProvider.capabilities.contains(.embeddings))
        #expect(store.embeddingModelOptions.contains("gemini-embedding-2"))
        #expect(store.embeddingModelOptions.contains("gemini-embedding-001"))
        #expect(store.embeddingModelOptions.contains(geminiProvider.modelIdentifier) == false)
    }

    @MainActor
    @Test("Mistral and Perplexity catalog embedding models are selectable")
    func mistralAndPerplexityCatalogEmbeddingModelsAreSelectable() throws {
        let (_, store) = try makeLoadedStore()
        let mistralProvider = try #require(store.providerConfigurations.first { $0.kind == .mistral && $0.accessMode == .apiKey })
        let perplexityProvider = try #require(store.providerConfigurations.first { $0.kind == .perplexity && $0.accessMode == .apiKey })

        #expect(mistralProvider.supportsEmbeddings)
        #expect(perplexityProvider.supportsEmbeddings)
        #expect(mistralProvider.capabilities.contains(.embeddings))
        #expect(perplexityProvider.capabilities.contains(.embeddings))
        #expect(store.embeddingModelOptions.contains("mistral-embed"))
        #expect(store.embeddingModelOptions.contains("pplx-embed-v1-0.6b"))
        #expect(store.embeddingModelOptions.contains("pplx-embed-v1-4b"))
        #expect(store.embeddingModelOptions.contains(mistralProvider.modelIdentifier) == false)
        #expect(store.embeddingModelOptions.contains(perplexityProvider.modelIdentifier) == false)
    }

    @MainActor
    @Test("Provider backed indexing can use OpenAI catalog embedding model")
    func providerBackedIndexingCanUseOpenAICatalogEmbeddingModel() async throws {
        let (_, store) = try makeLoadedStore()
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true

        let providerIndex = try #require(store.providerConfigurations.firstIndex { $0.kind == .openAI && $0.accessMode == .apiKey })
        let providerID = store.providerConfigurations[providerIndex].id
        _ = try #require(try store.saveProviderAPIKey(providerID, secret: "fixture-openai-embedding-secret"))
        let savedReference = try #require(
            ProviderSetupService.shared.parseSecretReference(store.providerConfigurations[providerIndex].secretReference)
        )
        defer { try? KeychainSecretStore().delete(savedReference) }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-openai-catalog-embedding-\(UUID().uuidString).txt")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "OpenAI catalog embeddings should persist semantic vectors for local RAG.".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
        store.knowledgeSources = [
            KnowledgeSource(
                title: "OpenAI embedding source",
                kind: .file,
                location: fileURL.path,
                status: .queued,
                embeddingModelIdentifier: "text-embedding-3-small"
            )
        ]
        store.knowledgeIndexManifests = []

        let embeddingService = LocalEmbeddingService()
        let vectorStore = LocalKnowledgeVectorStore(providerEmbeddingGenerator: { provider, modelIdentifier, inputs in
            #expect(provider.kind == .openAI)
            #expect(modelIdentifier == "text-embedding-3-small")
            return LocalEmbeddingResult(
                modelIdentifier: modelIdentifier,
                vectors: inputs.map {
                    embeddingService.deterministicLocalVector(for: $0)
                }
            )
        })

        await store.rebuildKnowledgeIndexManifestsUsingConfiguredEmbeddings(vectorStore: vectorStore)

        let source = try #require(store.knowledgeSources.first)
        let manifest = try #require(store.knowledgeIndexManifests.first)
        #expect(source.status == .ready)
        #expect(source.embeddingRecordCount == source.chunkCount)
        #expect(source.embeddingModelIdentifier == "text-embedding-3-small")
        #expect(manifest.embeddingState == .generated)
        #expect(manifest.embeddingProviderKind == .openAI)
        #expect(manifest.embeddingModelIdentifier == "text-embedding-3-small")
    }

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
