//
//  WorkspaceStoreTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation
import AppKit
import SwiftData
import Testing
@testable import flannel

struct WorkspaceStoreTests {
    @MainActor
    @Test("Seeded workspace loads the full local app slice")
    func seededWorkspaceLoadsCompletedSlice() throws {
        let (_, store) = try makeLoadedStore()

        #expect(store.selectedDestination == .home)
        #expect(store.accounts.count == 2)
        #expect(store.providerConfigurations.count >= 12)
        #expect(store.promptProfiles.isEmpty == false)
        #expect(store.chatTemplates.isEmpty == false)
        #expect(store.modelPresets.isEmpty == false)
        #expect(store.knowledgeSources.isEmpty == false)
        #expect(store.toolConfigurations.isEmpty == false)
        #expect(store.libraryAssets.count == 5)
        #expect(store.projects.count == 1)
        #expect(store.drafts.count == 2)
        #expect(store.calendarEntries.count == 2)
        #expect(store.assistantThreads.count == 1)
        #expect(store.currentProject?.title == "Creator OS Launch")
        #expect(store.currentDraft?.title == "Why local-first creator tooling matters")
        #expect(store.currentLibraryAsset?.title == "YouTube: Local AI Workflows for Creators")
        #expect(store.currentAssistantThread?.title == "Workspace Copilot")
        #expect(store.activeProvider?.displayName == "Local Ollama")
        #expect(store.assistantContext.promptPreamble.contains("Project: Creator OS Launch"))
        #expect(store.assistantContext.promptPreamble.contains("Library Asset: YouTube: Local AI Workflows for Creators"))
        #expect(store.assistantContext.promptPreamble.contains("Assistant Thread: Workspace Copilot"))
        #expect(store.assistantContext.promptPreamble.contains("Provider: Local Ollama"))
    }

    @MainActor
    @Test("Chat templates create reusable starter threads")
    func chatTemplatesCreateReusableStarterThreads() throws {
        let (_, store) = try makeLoadedStore()
        let template = try #require(store.chatTemplates.first { $0.title == "Research Brief" })
        let folder = try #require(store.addChatFolder(title: "Template Runs"))
        let baselineThreadCount = store.assistantThreads.count

        let thread = store.createAssistantThread(from: template, folderID: folder.id)
        let starterPrompt = store.renderChatTemplateStarterPrompt(template)

        #expect(store.assistantThreads.count == baselineThreadCount + 1)
        #expect(store.selectedAssistantThreadID == thread.id)
        #expect(thread.title == "Research Brief")
        #expect(thread.mode == .research)
        #expect(thread.folderID == folder.id)
        #expect(thread.tagNames.contains("research"))
        #expect(thread.messages.count == 1)
        #expect(thread.messages.first?.role == .system)
        #expect(thread.messages.first?.text.contains("research analyst") == true)
        #expect(starterPrompt.contains("Research this topic"))
        #expect(store.tags.contains { $0.name == "research" })
    }

    @MainActor
    @Test("Chat templates seed thread knowledge source scope")
    func chatTemplatesSeedThreadKnowledgeSourceScope() throws {
        let (_, store) = try makeLoadedStore()
        let sourceIDs = Array(store.knowledgeSources.prefix(2).map(\.id))
        let firstSourceID = try #require(sourceIDs.first)
        let secondSourceID = try #require(sourceIDs.dropFirst().first)
        let template = ChatTemplate(
            title: "Scoped Research",
            detail: "Starts with explicit local sources.",
            systemPrompt: "Use only selected sources.",
            starterPrompt: "Research this with scoped context:\n\n",
            mode: .research,
            tagNames: ["Scoped"],
            knowledgeSourceIDs: [secondSourceID, firstSourceID, UUID()]
        )

        let thread = store.createAssistantThread(from: template)

        #expect(thread.knowledgeSourceIDs == [secondSourceID, firstSourceID])
        #expect(store.currentAssistantThread?.knowledgeSourceIDs == [secondSourceID, firstSourceID])
        #expect(store.threadKnowledgeSources(for: thread).map(\.id) == [firstSourceID, secondSourceID])
    }

    @MainActor
    @Test("Template system prompt beats default profile")
    func templateSystemPromptBeatsDefaultProfile() throws {
        let (_, store) = try makeLoadedStore()
        store.promptProfiles = [
            SystemPromptProfile(
                title: "Global Default",
                detail: "Should not override template chats.",
                prompt: "GLOBAL DEFAULT PROMPT",
                isDefault: true
            )
        ]
        store.preferences.defaultSystemPromptProfileID = store.promptProfiles[0].id
        let template = ChatTemplate(
            title: "Template Runtime",
            detail: "Uses a dedicated system prompt.",
            systemPrompt: "TEMPLATE PROMPT for {{thread_title}}.",
            starterPrompt: "Starter for {{thread_title}}."
        )

        let thread = store.createAssistantThread(from: template)

        #expect(thread.messages.first?.role == .system)
        #expect(thread.messages.first?.text == "TEMPLATE PROMPT for Template Runtime.")
        #expect(store.effectiveSystemPrompt(for: thread) == "TEMPLATE PROMPT for Template Runtime.")
        #expect(store.renderChatTemplateStarterPrompt(template, for: thread) == "Starter for Template Runtime.")
    }

    @MainActor
    @Test("Template variables render against new thread and source scope")
    func templateVariablesRenderAgainstNewThreadAndSourceScope() throws {
        let (_, store) = try makeLoadedStore()
        let selectedSources = Array(store.knowledgeSources.prefix(2))
        let selectedSourceIDs = selectedSources.map(\.id)
        let expectedSourceTitles = selectedSources.map(\.title).sorted().joined(separator: ", ")
        let template = ChatTemplate(
            title: "Scoped Variable Research",
            detail: "Renders against the target thread.",
            systemPrompt: "Thread {{thread_title}} tags {{thread_tags}} sources {{knowledge_source_count}}: {{knowledge_sources}}.",
            starterPrompt: "Start {{thread_title}} with {{knowledge_source_count}} sources.",
            tagNames: ["RAG", "Local"],
            knowledgeSourceIDs: selectedSourceIDs
        )

        let thread = store.createAssistantThread(from: template)

        #expect(thread.messages.first?.text == "Thread Scoped Variable Research tags rag, local sources 2: \(expectedSourceTitles).")
        #expect(store.renderChatTemplateStarterPrompt(template, for: thread) == "Start Scoped Variable Research with 2 sources.")
    }

    @MainActor
    @Test("Chat template upsert preserves valid scoped knowledge sources")
    func chatTemplateUpsertPreservesValidScopedKnowledgeSources() throws {
        let (_, store) = try makeLoadedStore()
        let sourceIDs = Array(store.knowledgeSources.prefix(2).map(\.id))
        let firstSourceID = try #require(sourceIDs.first)
        let secondSourceID = try #require(sourceIDs.dropFirst().first)
        let staleSourceID = UUID()

        store.upsert(ChatTemplate(
            title: "  Scoped Knowledge Template  ",
            detail: "Uses selected local sources.",
            systemPrompt: "Stay grounded.",
            knowledgeSourceIDs: [secondSourceID, staleSourceID, firstSourceID, firstSourceID]
        ))

        let template = try #require(store.chatTemplates.first { $0.title == "Scoped Knowledge Template" })
        #expect(template.knowledgeSourceIDs == [secondSourceID, firstSourceID])
    }

    @MainActor
    @Test("Thread-scoped retrieval only returns selected knowledge sources")
    func threadScopedRetrievalFiltersKnowledgeSources() throws {
        let (_, store) = try makeLoadedStore()
        let firstURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-scope-alpha-\(UUID().uuidString).txt")
            .standardizedFileURL
        let secondURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-scope-beta-\(UUID().uuidString).txt")
            .standardizedFileURL
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        try "SCOPE NEEDLE alpha source is allowed for this private thread.".write(
            to: firstURL,
            atomically: true,
            encoding: .utf8
        )
        try "SCOPE NEEDLE beta source must stay outside this private thread.".write(
            to: secondURL,
            atomically: true,
            encoding: .utf8
        )
        let alphaSource = KnowledgeSource(title: "Alpha Scope", kind: .file, location: firstURL.path)
        let betaSource = KnowledgeSource(title: "Beta Scope", kind: .file, location: secondURL.path)
        store.knowledgeSources = [alphaSource, betaSource]

        let unscopedPacket = store.localKnowledgeRetrievalPacket(for: "SCOPE NEEDLE", limit: 4)
        let scopedPacket = store.localKnowledgeRetrievalPacket(
            for: "SCOPE NEEDLE",
            limit: 4,
            knowledgeSourceIDs: [alphaSource.id]
        )

        #expect(unscopedPacket.results.contains { $0.chunk.knowledgeSourceID == alphaSource.id })
        #expect(unscopedPacket.results.contains { $0.chunk.knowledgeSourceID == betaSource.id })
        #expect(scopedPacket.results.isEmpty == false)
        #expect(scopedPacket.results.allSatisfy { $0.chunk.knowledgeSourceID == alphaSource.id })
        #expect(scopedPacket.citations.allSatisfy { $0.title.contains("Alpha Scope") })
    }

    @MainActor
    @Test("Knowledge citation previews resolve source and manifest metadata")
    func knowledgeCitationPreviewsResolveSourceAndManifestMetadata() throws {
        let (_, store) = try makeLoadedStore()
        let sourceID = UUID(uuidString: "2B7157B4-628F-4E94-B447-9EB29B4F96A2")!
        let indexedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let source = KnowledgeSource(
            id: sourceID,
            title: "Launch Notes",
            kind: .file,
            location: "/tmp/flannel-launch-notes.md",
            status: .ready,
            chunkCount: 4,
            embeddingModelIdentifier: "nomic-embed-text",
            lastIndexedAt: indexedAt,
            isWatched: true,
            documentCount: 1,
            embeddingRecordCount: 4,
            vectorDimension: 768
        )
        let manifest = KnowledgeIndexManifest(
            sourceID: sourceID,
            title: "Launch Notes",
            kind: .file,
            location: source.location,
            status: .ready,
            documentCount: 1,
            chunkCount: 4,
            embeddingRecordCount: 4,
            vectorDimension: 768,
            embeddingModelIdentifier: "nomic-embed-text",
            embeddingProviderKind: .ollama,
            embeddingState: .generated,
            storageLocation: "~/Library/Application Support/Flannel/Knowledge/source.json",
            lastBuiltAt: indexedAt
        )
        store.knowledgeSources = [source]
        store.knowledgeIndexManifests = [manifest]

        let citation = AIChatCitation(
            title: "Launch Notes • chunk 2",
            snippet: "Source previews should expose local source metadata.",
            indexID: sourceID,
            sourceIdentifier: "launch-notes-chunk-2",
            score: 0.82
        )

        let preview = store.knowledgeCitationPreview(for: citation)

        #expect(preview.source?.id == sourceID)
        #expect(preview.manifest?.sourceID == sourceID)
        #expect(preview.displayTitle == "Launch Notes")
        #expect(preview.displayLocation == source.location)
        #expect(preview.kind == .file)
        #expect(preview.status == .ready)
        #expect(preview.chunkLabel == "Chunk 2")
        #expect(preview.chunkCount == 4)
        #expect(preview.embeddingRecordCount == 4)
        #expect(preview.vectorDimension == 768)
        #expect(preview.embeddingModelIdentifier == "nomic-embed-text")
        #expect(preview.lastIndexedAt == indexedAt)
        #expect(preview.isWatched)
        #expect(preview.isResolved)
    }

    @MainActor
    @Test("Chat templates persist prompt variables and provider hints")
    func chatTemplatesPersistPromptVariablesAndProviderHints() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)

        let template = ChatTemplate(
            title: "Bug Triage",
            detail: "Turns a report into repro steps and likely fixes.",
            systemPrompt: "Date: {{date}}. Triage bugs with local context first.",
            starterPrompt: "Summarize this bug on {{date}}:\n\n",
            mode: .workspaceCopilot,
            tagNames: ["Bugs", "Local"],
            preferredProviderKind: .lmStudio,
            preferredAccessMode: .localServer,
            preferredModelIdentifier: "local-debugger",
            requiredToolKinds: [.workspaceSearch, .localFileRead]
        )
        store.upsert(template)
        try store.persist(in: context)

        let reloadedStore = WorkspaceStore()
        try reloadedStore.loadOrCreate(in: context)
        let reloadedTemplate = try #require(reloadedStore.chatTemplates.first { $0.id == template.id })

        #expect(reloadedTemplate.title == "Bug Triage")
        #expect(reloadedTemplate.tagNames == ["bugs", "local"])
        #expect(reloadedTemplate.preferredProviderKind == .lmStudio)
        #expect(reloadedTemplate.preferredAccessMode == .localServer)
        #expect(reloadedTemplate.requiredToolKinds == [.workspaceSearch, .localFileRead])
        #expect(reloadedStore.renderChatTemplateSystemPrompt(
            reloadedTemplate,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        ).contains("Date: 2023-11-14"))
    }

    @MainActor
    @Test("Prompt profile upsert normalizes tags switches defaults and persists")
    func promptProfileUpsertNormalizesTagsSwitchesDefaultsAndPersists() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)

        let firstProfile = SystemPromptProfile(
            title: "  Local Research Voice  ",
            detail: "  Use local sources first.  ",
            prompt: "Today is {{date}}. Stay local.",
            tags: ["Local AI", "Research", "local ai"],
            isDefault: true
        )
        let secondProfile = SystemPromptProfile(
            title: "Cloud Review",
            detail: "Escalates when the workspace allows it.",
            prompt: "Use the selected provider boundary.",
            tags: ["Cloud"],
            isDefault: true
        )

        store.upsert(firstProfile)
        try store.persist(in: context)

        let reloadedStore = WorkspaceStore()
        try reloadedStore.loadOrCreate(in: context)
        let reloadedFirstProfile = try #require(reloadedStore.promptProfiles.first { $0.id == firstProfile.id })
        let rendered = try #require(reloadedStore.defaultSystemPrompt(now: Date(timeIntervalSince1970: 1_700_000_000)))

        #expect(reloadedFirstProfile.title == "Local Research Voice")
        #expect(reloadedFirstProfile.detail == "Use local sources first.")
        #expect(reloadedFirstProfile.tags == ["local-ai", "research"])
        #expect(reloadedStore.preferences.defaultSystemPromptProfileID == firstProfile.id)
        #expect(rendered.contains("Today is 2023-11-14"))
        #expect(reloadedStore.tags.contains { $0.name == "local-ai" })

        reloadedStore.upsert(secondProfile)
        #expect(reloadedStore.preferences.defaultSystemPromptProfileID == secondProfile.id)
        #expect(reloadedStore.promptProfiles.first { $0.id == firstProfile.id }?.isDefault == false)
        #expect(reloadedStore.promptProfiles.first { $0.id == secondProfile.id }?.isDefault == true)

        reloadedStore.deletePromptProfile(secondProfile.id)
        #expect(reloadedStore.preferences.defaultSystemPromptProfileID == firstProfile.id)
        #expect(reloadedStore.promptProfiles.contains { $0.id == secondProfile.id } == false)
    }

    @MainActor
    @Test("Persistence issues keep failure details until the matching operation clears")
    func persistenceIssuesRecordAndClearByOperation() {
        let store = WorkspaceStore()
        let error = NSError(
            domain: "FlannelTests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "The local database is temporarily unavailable."]
        )

        store.recordPersistenceFailure(error, operation: .save)

        #expect(store.persistenceIssue?.operation == .save)
        #expect(store.persistenceIssue?.message == "The local database is temporarily unavailable.")
        #expect(store.persistenceIssue?.recoverySuggestion.contains("Recent changes may not be durable yet") == true)

        store.clearPersistenceIssue(matching: .load)
        #expect(store.persistenceIssue != nil)

        store.clearPersistenceIssue(matching: .save)
        #expect(store.persistenceIssue == nil)
    }

    @MainActor
    @Test("Local workspace reset clears user data and restores clean defaults")
    func localWorkspaceResetClearsUserDataAndRestoresCleanDefaults() throws {
        let (_, store) = try makeLoadedStore()
        let originalWorkspaceID = try #require(store.workspace?.workspaceID)
        store.providerConfigurations[0].secretReference = "Flannel:OpenAI"
        store.localMemories = [
            LocalMemoryRecord(title: "Private rule", detail: "Do not export drafts.", category: .preference)
        ]
        store.toolExecutionResults = [
            LocalToolExecutionResult(
                toolKind: .ragRetrieval,
                title: "Private lookup",
                query: "secret",
                status: .completed,
                output: "Private lookup result"
            )
        ]
        store.modelComparisonRuns = [
            ModelComparisonRun(prompt: "Compare private models", providerIDs: [], results: [])
        ]
        _ = store.addChatFolder(title: "Sensitive")

        let resetAt = Date(timeIntervalSince1970: 1_782_900_000)
        let newWorkspaceID = store.resetLocalWorkspace(now: resetAt)

        #expect(newWorkspaceID != originalWorkspaceID)
        #expect(store.workspace?.workspaceID == newWorkspaceID)
        #expect(store.workspace?.timestamp == resetAt)
        #expect(store.workspace?.updatedAt == resetAt)
        #expect(store.accounts.isEmpty)
        #expect(store.projects.isEmpty)
        #expect(store.drafts.isEmpty)
        #expect(store.libraryAssets.isEmpty)
        #expect(store.calendarEntries.isEmpty)
        #expect(store.localActionHistory.isEmpty)
        #expect(store.localMemories.isEmpty)
        #expect(store.toolExecutionResults.isEmpty)
        #expect(store.modelComparisonRuns.isEmpty)
        #expect(store.pinnedMessages.isEmpty)
        #expect(store.archivedAssistantThreadIDs.isEmpty)
        #expect(store.providerConfigurations.contains { $0.kind == .ollama && $0.accessMode == .localServer })
        #expect(store.providerConfigurations.allSatisfy { $0.secretReference == nil })
        #expect(store.assistantThreads.count == 1)
        #expect(store.currentAssistantThread?.title == "New AI Chat")
        #expect(store.preferences.localOnlyMode == true)
        #expect(store.preferences.allowCloudProviders == false)
        #expect(store.preferences.defaultDestination == .home)
        #expect(store.knowledgeSources.map(\.kind).contains(.chatHistory))
        #expect(store.toolConfigurations.contains { $0.kind == .workspaceSearch })
        #expect(store.chatTemplates.contains { $0.title == "Private Local Chat" })
    }

    @MainActor
    @Test("Draft creation from the selected source links source context while staying in Chat")
    func draftCreationFromSelectedSourceCreatesLinkedDraft() throws {
        let (_, store) = try makeLoadedStore()
        let originalDraftCount = store.drafts.count
        let selectedAsset = try #require(store.currentLibraryAsset)
        let selectedProjectID = store.selectedProjectID

        store.draftFromSelectedAsset()

        let draft = try #require(store.currentDraft)
        let thread = try #require(store.currentAssistantThread)

        #expect(store.drafts.count == originalDraftCount + 1)
        #expect(store.selectedDestination == .home)
        #expect(draft.title == "Draft from \(selectedAsset.title)")
        #expect(draft.projectID == selectedProjectID)
        for tag in selectedAsset.tags {
            #expect(draft.tags.contains(tag))
        }
        #expect(draft.body.contains(selectedAsset.sourceURL?.absoluteString ?? ""))
        #expect(draft.summary == selectedAsset.summary)
        #expect(thread.messages.last?.text.contains("I created a source-linked draft from \(selectedAsset.title).") == true)
    }

    @MainActor
    @Test("Draft creation without a selected source keeps draft state unchanged and explains the failure")
    func draftCreationWithoutSelectionAppendsGuidance() throws {
        let (_, store) = try makeLoadedStore()
        let originalDraftCount = store.drafts.count
        let originalSelectedDraftID = store.selectedDraftID
        store.selectedAssetID = nil

        store.draftFromSelectedAsset()

        let thread = try #require(store.currentAssistantThread)

        #expect(store.drafts.count == originalDraftCount)
        #expect(store.selectedDraftID == originalSelectedDraftID)
        #expect(thread.messages.last?.text == "Select a saved source first, then I can create a linked draft from it.")
    }

    @MainActor
    @Test("Manual pasted URLs stay local, classify by source, and keep Chat focused")
    func manualURLCaptureClassifiesAndSelectsInboxAsset() throws {
        let testCases: [(rawValue: String, expectedTitle: String, expectedURLFragment: String)] = [
            (" https://youtube.com/watch?v=local-ai-workflows ", "Manual YouTube capture", "youtube.com"),
            ("https://x.com/symbiex/status/100", "Manual X capture", "x.com"),
            ("https://example.com/reference", "Manual web capture", "example.com"),
        ]

        for testCase in testCases {
            let (_, store) = try makeLoadedStore()
            let originalCount = store.libraryAssets.count

            store.saveManualURL(testCase.rawValue)

            let asset = try #require(store.currentLibraryAsset)
            let thread = try #require(store.currentAssistantThread)

            #expect(store.libraryAssets.count == originalCount + 1)
            #expect(store.selectedDestination == .home)
            #expect(asset.title == testCase.expectedTitle)
            #expect(asset.kind == .link)
            #expect(asset.sourceURL?.absoluteString.contains(testCase.expectedURLFragment) == true)
            #expect(asset.tags.contains("manual"))
            #expect(asset.tags.contains("inbox"))
            #expect(thread.messages.last?.text == "I saved that URL locally. It is in Inbox and can be linked, summarized, or queued for transcript import without touching an external API.")
        }
    }

    @MainActor
    @Test("Active provider falls back to the next enabled provider when the preferred one is unavailable")
    func activeProviderFallsBackToEnabledConfiguration() throws {
        let (_, store) = try makeLoadedStore()
        let preferred = try #require(store.providerConfigurations.first)
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true
        store.preferences.preferredProviderID = preferred.id
        store.providerConfigurations[0].isEnabled = false
        let lmStudioIndex = try #require(store.providerConfigurations.firstIndex { $0.kind == .lmStudio })
        store.providerConfigurations[lmStudioIndex].modelIdentifier = "local-model"
        store.providerConfigurations[lmStudioIndex].connectionStatus = .ready

        let provider = try #require(store.activeProvider)

        #expect(provider.id != preferred.id)
        #expect(provider.kind == .lmStudio)
        #expect(provider.privacyScope == .localOnly)
    }

    @MainActor
    @Test("Provider matrix preserves multiple user routes per provider family")
    func providerMatrixPreservesMultipleUserRoutesPerFamily() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let openAIPrimary = ProviderConfiguration(
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "OpenAI API - Personal",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-5.5",
            secretReference: "keychain-openai-personal",
            isEnabled: true,
            connectionStatus: .ready,
            capabilities: [.chat, .streaming, .toolCalling, .vision, .reasoning],
            supportsToolCalling: true,
            supportsVision: true
        )
        let openAIProxy = ProviderConfiguration(
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "OpenAI API - Work Proxy",
            endpoint: "https://openai-proxy.example.test/v1",
            modelIdentifier: "gpt-5.5-mini",
            secretReference: "keychain-openai-work",
            isEnabled: false,
            connectionStatus: .needsAttention,
            capabilities: [.chat, .streaming, .toolCalling],
            supportsToolCalling: true
        )
        let localGateway = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .localOnly,
            displayName: "Local Gateway",
            endpoint: "http://localhost:8080/v1",
            modelIdentifier: "gateway-local",
            isEnabled: true,
            connectionStatus: .ready,
            capabilities: [.chat, .streaming, .toolCalling, .openAICompatible],
            supportsToolCalling: true
        )
        let remoteGateway = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .externalAPI,
            displayName: "Remote Gateway",
            endpoint: "https://gateway.example.test/v1",
            modelIdentifier: "gateway-remote",
            secretReference: "keychain-gateway-remote",
            isEnabled: false,
            connectionStatus: .needsAttention,
            capabilities: [.chat, .streaming, .openAICompatible]
        )
        let item = Item(
            providerConfigurations: [openAIPrimary, openAIProxy, localGateway, remoteGateway],
            assistantThreads: [AssistantThread(title: "Existing Chat")]
        )
        context.insert(item)
        try context.save()

        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)

        let openAIRoutes = store.providerConfigurations.filter {
            $0.kind == .openAI && $0.accessMode == .apiKey
        }
        let customRoutes = store.providerConfigurations.filter {
            $0.kind == .customOpenAICompatible && $0.accessMode == .openAICompatible
        }

        #expect(Set(openAIRoutes.map(\.id)) == Set([openAIPrimary.id, openAIProxy.id]))
        #expect(openAIRoutes.map(\.displayName).contains("OpenAI API - Work Proxy"))
        #expect(Set(customRoutes.map(\.id)) == Set([localGateway.id, remoteGateway.id]))
        #expect(customRoutes.map(\.endpoint).contains("https://gateway.example.test/v1"))
        #expect(store.providerConfigurations.contains {
            $0.kind == .chatGPTCLI && $0.accessMode == .subscriptionCLI
        })
        #expect(store.providerConfigurations.contains {
            $0.kind == .anthropic && $0.accessMode == .apiKey
        })
        #expect(store.providerConfigurations.contains {
            $0.kind == .claudeCodeCLI && $0.accessMode == .subscriptionCLI
        })
        #expect(store.providerConfigurations.contains {
            $0.kind == .ollama && $0.accessMode == .localServer
        })
    }

    @MainActor
    @Test("Provider route creation adds editable API CLI and local endpoint routes")
    func providerRouteCreationAddsEditableRoutes() throws {
        let (_, store) = try makeLoadedStore()
        let originalOpenAIRouteCount = store.providerConfigurations.filter {
            $0.kind == .openAI && $0.accessMode == .apiKey
        }.count
        let existingProviderDisplayNames = Set(store.providerConfigurations.map(\.displayName))

        let openAIRoute = store.createProviderRoute(kind: .openAI, accessMode: .apiKey)
        let chatGPTRoute = store.createProviderRoute(kind: .chatGPTCLI, accessMode: .subscriptionCLI)
        let customLocalRoute = store.createProviderRoute(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .localOnly
        )

        #expect(store.providerConfigurations.filter {
            $0.kind == .openAI && $0.accessMode == .apiKey
        }.count == originalOpenAIRouteCount + 1)
        #expect(!openAIRoute.displayName.isEmpty)
        #expect(existingProviderDisplayNames.contains(openAIRoute.displayName) == false)
        #expect(openAIRoute.privacyScope == .externalAPI)
        #expect(openAIRoute.isEnabled == false)
        #expect(chatGPTRoute.accessMode == .subscriptionCLI)
        #expect(chatGPTRoute.privacyScope == .localCLI)
        #expect(chatGPTRoute.endpoint.contains("codex exec"))
        #expect(customLocalRoute.accessMode == .openAICompatible)
        #expect(customLocalRoute.privacyScope == .localOnly)
        #expect(customLocalRoute.endpoint == "http://localhost:8080/v1")
    }

    @MainActor
    @Test("Provider route duplicate creates disabled editable copy")
    func providerRouteDuplicateCreatesDisabledEditableCopy() throws {
        let (_, store) = try makeLoadedStore()
        var route = store.createProviderRoute(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .localOnly
        )
        let routeIndex = try #require(store.providerConfigurations.firstIndex { $0.id == route.id })
        store.providerConfigurations[routeIndex].displayName = "Local Gateway"
        store.providerConfigurations[routeIndex].endpoint = "http://localhost:7777/v1"
        store.providerConfigurations[routeIndex].modelIdentifier = "local-gateway-model"
        route = store.providerConfigurations[routeIndex]

        let duplicate = try #require(store.duplicateProviderRoute(route.id))

        #expect(duplicate.id != route.id)
        #expect(duplicate.displayName == "Local Gateway Copy")
        #expect(duplicate.kind == route.kind)
        #expect(duplicate.accessMode == route.accessMode)
        #expect(duplicate.endpoint == route.endpoint)
        #expect(duplicate.modelIdentifier == route.modelIdentifier)
        #expect(duplicate.isEnabled == false)
        #expect(duplicate.connectionStatus == .needsAttention)
        #expect(duplicate.lastValidatedAt == nil)
        #expect(duplicate.lastErrorMessage?.contains("Review duplicated route") == true)
        #expect(store.providerConfigurations.contains { $0.id == duplicate.id })
    }

    @MainActor
    @Test("Applying a model preset updates only the targeted route and records selection")
    func applyingModelPresetUpdatesOnlyTargetedRoute() throws {
        let (_, store) = try makeLoadedStore()
        let firstRoute = ProviderConfiguration(
            id: UUID(uuidString: "a89b60d1-0c3a-49c4-a3e8-e6f4e8f91f12")!,
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .localOnly,
            displayName: "Local Gateway A",
            endpoint: "http://localhost:7777/v1",
            modelIdentifier: "old-a",
            isEnabled: true,
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            connectionStatus: .ready,
            availableModels: ["old-a"],
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )
        let targetRoute = ProviderConfiguration(
            id: UUID(uuidString: "3a0f3226-763b-4a7c-990f-a0f553c0e0e4")!,
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .localOnly,
            displayName: "Local Gateway B",
            endpoint: "http://localhost:8888/v1",
            modelIdentifier: "old-b",
            isEnabled: true,
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_010),
            connectionStatus: .ready,
            availableModels: ["old-b"],
            capabilities: [.chat, .streaming],
            supportsStreaming: true
        )
        let preset = ModelPreset(
            id: UUID(uuidString: "34a2b828-11ff-4e93-a2ab-e435c48f1581")!,
            title: "Qwen local gateway",
            providerKind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            modelIdentifier: "qwen3:14b",
            temperature: 0.35,
            contextWindowTokens: 65_536,
            capabilities: [.chat, .streaming, .toolCalling, .vision, .streaming],
            privacyScope: .localOnly
        )
        store.providerConfigurations = [firstRoute, targetRoute]
        store.modelPresets = [preset]
        store.preferences.defaultModelPresetID = nil
        store.preferences.preferredProviderID = nil

        let runnable = store.applyModelPreset(preset.id, providerID: targetRoute.id)

        let untouchedRoute = try #require(store.providerConfigurations.first { $0.id == firstRoute.id })
        let updatedRoute = try #require(store.providerConfigurations.first { $0.id == targetRoute.id })

        #expect(runnable == false)
        #expect(untouchedRoute.modelIdentifier == "old-a")
        #expect(untouchedRoute.temperature == firstRoute.temperature)
        #expect(untouchedRoute.connectionStatus == .ready)
        #expect(untouchedRoute.lastValidatedAt == firstRoute.lastValidatedAt)
        #expect(updatedRoute.modelIdentifier == "qwen3:14b")
        #expect(updatedRoute.temperature == 0.35)
        #expect(updatedRoute.privacyScope == .localOnly)
        #expect(updatedRoute.contextWindowTokens == 65_536)
        #expect(updatedRoute.availableModels == ["old-b", "qwen3:14b"])
        #expect(updatedRoute.capabilities == [.chat, .streaming, .toolCalling, .vision])
        #expect(updatedRoute.supportsToolCalling)
        #expect(updatedRoute.supportsVision)
        #expect(updatedRoute.connectionStatus == .needsAttention)
        #expect(updatedRoute.lastValidatedAt == nil)
        #expect(updatedRoute.lastErrorMessage?.contains("Run provider readiness") == true)
        #expect(store.preferences.preferredProviderID == targetRoute.id)
        #expect(store.preferences.providerRoutingPolicy == .selectedProvider)
        #expect(store.preferences.defaultModelPresetID == preset.id)
        #expect(store.modelPresets.filter(\.isDefault).map(\.id) == [preset.id])
    }

    @MainActor
    @Test("Default model preset normalizes across persistence")
    func defaultModelPresetNormalizesAcrossPersistence() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)
        let firstPreset = ModelPreset(
            id: UUID(uuidString: "f65dc659-87fd-4f90-88ec-3f43a4236686")!,
            title: "  Local Default  ",
            providerKind: .ollama,
            accessMode: .localServer,
            modelIdentifier: " llama3.1 ",
            capabilities: [.streaming, .chat, .streaming],
            privacyScope: .localOnly,
            isDefault: true
        )
        let selectedPreset = ModelPreset(
            id: UUID(uuidString: "772e83db-0064-4c6c-af84-3eea5b0155c4")!,
            title: "Cloud Review",
            providerKind: .openAI,
            accessMode: .apiKey,
            modelIdentifier: "gpt-5.5",
            capabilities: [.chat, .streaming, .reasoning],
            privacyScope: .externalAPI,
            isDefault: true
        )
        store.modelPresets = [firstPreset, selectedPreset]
        store.preferences.defaultModelPresetID = selectedPreset.id

        try store.persist(in: context)

        let reloadedStore = WorkspaceStore()
        try reloadedStore.loadOrCreate(in: context)

        #expect(reloadedStore.preferences.defaultModelPresetID == selectedPreset.id)
        #expect(reloadedStore.defaultModelPreset?.id == selectedPreset.id)
        #expect(reloadedStore.modelPresets.filter(\.isDefault).map(\.id) == [selectedPreset.id])
        #expect(reloadedStore.modelPresets.first { $0.id == firstPreset.id }?.title == "Local Default")
        #expect(reloadedStore.modelPresets.first { $0.id == firstPreset.id }?.modelIdentifier == "llama3.1")
        #expect(reloadedStore.modelPresets.first { $0.id == firstPreset.id }?.capabilities == [.chat, .streaming])
    }

    @MainActor
    @Test("Provider route deletion clears stale preferred provider")
    func providerRouteDeletionClearsStalePreferredProvider() throws {
        let (_, store) = try makeLoadedStore()
        let route = store.createProviderRoute(kind: .openAI, accessMode: .apiKey)
        store.preferences.preferredProviderID = route.id

        let deleted = store.deleteProviderRoute(route.id)

        #expect(deleted)
        #expect(store.providerConfigurations.contains { $0.id == route.id } == false)
        #expect(store.preferences.preferredProviderID != route.id)
        #expect(store.deleteProviderRoute(route.id) == false)
    }

    @MainActor
    @Test("Workspace retrieval packet uses local workspace knowledge as chat context")
    func workspaceRetrievalPacketUsesLocalWorkspaceKnowledge() throws {
        let (_, store) = try makeLoadedStore()

        let packet = store.localKnowledgeRetrievalPacket(
            for: "local-first creator tooling",
            limit: 3
        )

        #expect(packet.results.isEmpty == false)
        #expect(packet.citations.isEmpty == false)
        #expect(packet.promptContext.contains("Local knowledge retrieval for: local-first creator tooling"))
        #expect(packet.responseCitationBlock.contains("Sources"))
        #expect(packet.results.contains { $0.chunk.sourceTitle == "Workspace notes" || $0.chunk.sourceTitle == "Chat history" })
    }

    @MainActor
    @Test("Chat history retrieval cites the matching thread")
    func chatHistoryRetrievalCitesMatchingThread() throws {
        let (_, store) = try makeLoadedStore()
        let source = KnowledgeSource(
            title: "Chat history",
            kind: .chatHistory,
            location: "flannel://chat-history",
            status: .queued,
            embeddingModelIdentifier: LocalEmbeddingService.deterministicModelIdentifier,
            isWatched: true
        )
        let alphaThread = AssistantThread(
            title: "Alpha Market Notes",
            messages: [
                AssistantMessage(role: .user, text: "ALPHA NEEDLE belongs to market sizing only.")
            ]
        )
        let betaThread = AssistantThread(
            title: "Beta Architecture Plan",
            messages: [
                AssistantMessage(role: .assistant, text: "BETA NEEDLE validates the private RAG citation path.")
            ]
        )
        store.knowledgeSources = [source]
        store.assistantThreads = [alphaThread, betaThread]

        let packet = store.localKnowledgeRetrievalPacket(
            for: "BETA NEEDLE private RAG",
            limit: 1,
            knowledgeSourceIDs: [source.id]
        )
        let result = try #require(packet.results.first)
        let citation = try #require(packet.citations.first)
        let preview = store.knowledgeCitationPreview(for: citation)
        let expectedLocation = "flannel://chat-history/thread/\(betaThread.id.uuidString.lowercased())"

        #expect(result.chunk.sourceTitle == "Chat: Beta Architecture Plan")
        #expect(result.chunk.sourceLocation == expectedLocation)
        #expect(citation.title.contains("Chat: Beta Architecture Plan"))
        #expect(citation.sourceLocation == expectedLocation)
        #expect(preview.source?.id == source.id)
        #expect(preview.displayTitle == "Chat: Beta Architecture Plan")
        #expect(preview.displayLocation == expectedLocation)
        #expect(preview.kind == .chatHistory)
    }

    @MainActor
    @Test("Prompt profile variables render from current workspace context")
    func promptProfileVariablesRenderFromCurrentWorkspaceContext() throws {
        let (_, store) = try makeLoadedStore()
        let thread = AssistantThread(
            title: "Variable Thread",
            messages: [AssistantMessage(role: .user, text: "Use the template.")],
            tagNames: ["rag", "local"]
        )
        let profile = SystemPromptProfile(
            title: "Templated profile",
            detail: "Renders local workspace variables.",
            prompt: """
            Today {{ date }} use {{ provider }} / {{ model }} in {{ privacy }} mode.
            Route: {{ routing_policy }}. Thread: {{ thread_title }} [{{ thread_tags }}].
            Project: {{ project }}. Sources: {{ knowledge_source_count }} - {{ knowledge_sources }}.
            Unknown variables stay literal: {{ unknown_variable }}.
            """
        )
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12)))

        store.assistantThreads = [thread]
        store.selectedAssistantThreadID = thread.id
        store.knowledgeSources = [
            KnowledgeSource(title: "Private Notes", kind: .workspaceNotes, location: "notes"),
            KnowledgeSource(title: "Specs", kind: .file, location: "/tmp/spec.md")
        ]
        store.promptProfiles = [
            SystemPromptProfile(
                title: "Ignored default",
                detail: "The explicit preference should win.",
                prompt: "Do not render this.",
                isDefault: true
            ),
            profile
        ]
        store.preferences.defaultSystemPromptProfileID = profile.id

        let activeProvider = try #require(store.activeProvider)
        let rendered = try #require(store.defaultSystemPrompt(now: now))

        #expect(rendered.contains("Today 2026-06-29"))
        #expect(rendered.contains(activeProvider.displayName))
        #expect(rendered.contains(activeProvider.modelIdentifier))
        #expect(rendered.contains("Local Only mode"))
        #expect(rendered.contains("Route: Selected Provider"))
        #expect(rendered.contains("Thread: Variable Thread [rag, local]"))
        #expect(rendered.contains("Project: Creator OS Launch"))
        #expect(rendered.contains("Sources: 2 - Private Notes, Specs"))
        #expect(rendered.contains("{{ unknown_variable }}"))
        #expect(rendered.contains("Do not render this.") == false)
    }

    @MainActor
    @Test("Knowledge rebuild creates durable manifests and updates source indexing metadata")
    func knowledgeRebuildCreatesManifests() throws {
        let (_, store) = try makeLoadedStore()
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-vector-store-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: storageURL) }
        store.preferences.localStorageLabel = storageURL.path

        let sourceID = try #require(store.knowledgeSources.first(where: { $0.kind == .workspaceNotes })?.id)
        let sourceIndex = try #require(store.knowledgeSources.firstIndex(where: { $0.id == sourceID }))
        store.knowledgeSources[sourceIndex].embeddingModelIdentifier = LocalEmbeddingService.deterministicModelIdentifier

        store.rebuildKnowledgeIndexManifests()

        let source = try #require(store.knowledgeSources.first(where: { $0.id == sourceID }))
        let manifest = try #require(store.knowledgeIndexManifests.first(where: { $0.sourceID == sourceID }))
        let vectorFile = try LocalKnowledgeVectorStore().read(from: manifest.storageLocation)

        #expect(source.status == .ready)
        #expect(source.documentCount > 0)
        #expect(source.chunkCount > 0)
        #expect(source.embeddingRecordCount == source.chunkCount)
        #expect(source.vectorDimension == LocalEmbeddingService.defaultLocalVectorDimension)
        #expect(source.contentFingerprint?.isEmpty == false)
        #expect(manifest.status == .ready)
        #expect(manifest.embeddingState == .generated)
        #expect(manifest.storageLocation.contains(sourceID.uuidString.lowercased()))
        #expect(manifest.contentFingerprint == source.contentFingerprint)
        #expect(vectorFile.records.count == source.chunkCount)
        #expect(vectorFile.modelIdentifier == LocalEmbeddingService.deterministicModelIdentifier)
        #expect(FileManager.default.fileExists(atPath: (manifest.storageLocation as NSString).expandingTildeInPath))
    }

    @MainActor
    @Test("Knowledge rebuild writes failed manifest metadata for unreadable source")
    func knowledgeRebuildWritesFailedManifestMetadataForUnreadableSource() throws {
        let (_, store) = try makeLoadedStore()
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-failed-vector-store-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-unreadable-source-\(UUID().uuidString).txt")
            .standardizedFileURL
        defer {
            try? FileManager.default.removeItem(at: storageURL)
            try? FileManager.default.removeItem(at: sourceURL)
        }

        try "Index source that will disappear before rebuild.".write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )
        store.preferences.localStorageLabel = storageURL.path
        store.knowledgeSources = [
            KnowledgeSource(
                title: "Unreadable source",
                kind: .file,
                location: sourceURL.path,
                status: .queued,
                embeddingModelIdentifier: LocalEmbeddingService.deterministicModelIdentifier,
                isWatched: true
            )
        ]
        store.knowledgeIndexManifests = []
        try FileManager.default.removeItem(at: sourceURL)

        store.rebuildKnowledgeIndexManifests(now: Date(timeIntervalSince1970: 2_000_000))

        let source = try #require(store.knowledgeSources.first)
        let manifest = try #require(store.knowledgeIndexManifests.first(where: { $0.sourceID == source.id }))

        #expect(source.status == .failed)
        #expect(source.documentCount == 0)
        #expect(source.chunkCount == 0)
        #expect(source.embeddingRecordCount == 0)
        #expect(source.vectorDimension == nil)
        #expect(source.lastErrorMessage == "No readable local documents were found for this source.")
        #expect(manifest.status == .failed)
        #expect(manifest.embeddingState == .failed)
        #expect(manifest.lastErrorMessage == source.lastErrorMessage)
        #expect(manifest.sourceID == source.id)
    }

    @MainActor
    @Test("Knowledge rebuild can persist provider-backed embeddings and retrieve with matching query vectors")
    func knowledgeRebuildUsesProviderBackedEmbeddings() async throws {
        let (_, store) = try makeLoadedStore()
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-provider-vector-store-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-provider-source-\(UUID().uuidString).txt")
            .standardizedFileURL
        defer {
            try? FileManager.default.removeItem(at: storageURL)
            try? FileManager.default.removeItem(at: fileURL)
        }
        try "Provider embeddings persist a hidden semantic target without keyword overlap.".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio Embeddings",
            endpoint: "http://localhost:1234",
            modelIdentifier: "text-embedding-local",
            availableModels: ["text-embedding-local"],
            capabilities: [.embeddings],
            supportsEmbeddings: true
        )
        let source = KnowledgeSource(
            title: "Provider-backed file",
            kind: .file,
            location: fileURL.path,
            status: .queued,
            embeddingModelIdentifier: "text-embedding-local"
        )

        store.preferences.localStorageLabel = storageURL.path
        store.providerConfigurations = [provider]
        store.knowledgeSources = [source]
        store.knowledgeIndexManifests = []

        let vectorStore = LocalKnowledgeVectorStore(providerEmbeddingGenerator: { _, modelIdentifier, inputs in
            let vectors = inputs.map { input in
                input.localizedCaseInsensitiveContains("blue orbit") ? [1.0, 0.0] : [1.0, 0.0]
            }
            return LocalEmbeddingResult(modelIdentifier: modelIdentifier, vectors: vectors)
        })

        await store.rebuildKnowledgeIndexManifestsUsingConfiguredEmbeddings(vectorStore: vectorStore)

        let rebuilt = try #require(store.knowledgeSources.first)
        let manifest = try #require(store.knowledgeIndexManifests.first)
        let vectorFile = try LocalKnowledgeVectorStore().read(from: manifest.storageLocation)
        let packet = await store.localKnowledgeRetrievalPacketUsingConfiguredEmbeddings(
            for: "blue orbit",
            limit: 1,
            vectorStore: vectorStore
        )

        #expect(rebuilt.status == .ready)
        #expect(rebuilt.embeddingRecordCount == rebuilt.chunkCount)
        #expect(rebuilt.vectorDimension == 2)
        #expect(manifest.embeddingState == .generated)
        #expect(manifest.embeddingProviderKind == .lmStudio)
        #expect(manifest.embeddingModelIdentifier == "text-embedding-local")
        #expect(vectorFile.modelIdentifier == "text-embedding-local")
        #expect(vectorFile.vectorDimension == 2)
        #expect(packet.results.first?.chunk.knowledgeSourceID == source.id)
        #expect(packet.results.first?.matchedTerms == ["semantic"])
    }

    @MainActor
    @Test("Local tool success records result and appends local action history")
    func localToolSuccessRecordsResultAndLocalActionHistory() throws {
        let (_, store) = try makeLoadedStore()
        let initialActionCount = store.localActionHistory.count
        let initialToolResultCount = store.toolExecutionResults.count
        let localSearchIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .workspaceSearch }))
        store.toolConfigurations[localSearchIndex].isEnabled = true

        let result = store.runTool(.workspaceSearch, query: "local tool workflow")

        #expect(result.status == .completed)
        #expect(result.toolKind == .workspaceSearch)
        #expect(result.query == "local tool workflow")
        #expect(result.output.contains("Workspace search for \"local tool workflow\""))
        #expect(store.toolExecutionResults.count == initialToolResultCount + 1)
        #expect(store.toolExecutionResults.contains { $0.toolKind == .workspaceSearch && $0.status == .completed && $0.query == "local tool workflow" })
        #expect(store.localActionHistory.count == initialActionCount + 1)
        #expect(store.localActionHistory.first?.kind == .runTool)
    }

    @MainActor
    @Test("Run tool automation executes workspace search and records traces")
    func runToolAutomationExecutesWorkspaceSearchAndRecordsTraces() throws {
        let (_, store) = try makeLoadedStore()
        let automation = WorkspaceAutomation(
            title: "Scout workspace",
            detail: "Search local context for the next safe action.",
            cadence: .manual,
            requiresConfirmation: false,
            linkedDestination: .automations,
            actionKind: .runTool,
            action: WorkspaceAutomationAction(
                kind: .runTool,
                toolKind: .workspaceSearch,
                query: "local tool workflow"
            )
        )
        store.automations = [automation]
        let initialActionCount = store.localActionHistory.count
        let initialToolResultCount = store.toolExecutionResults.count

        store.runAutomation(automation.id)

        let updatedAutomation = try #require(store.automations.first)
        #expect(updatedAutomation.lastRunState == .succeeded)
        #expect(updatedAutomation.lastResultMessage?.contains("Workspace search for \"local tool workflow\"") == true)
        #expect(store.toolExecutionResults.count == initialToolResultCount + 1)
        #expect(store.toolExecutionResults.first?.toolKind == .workspaceSearch)
        #expect(store.toolExecutionResults.first?.status == .completed)
        #expect(store.toolExecutionResults.first?.query == "local tool workflow")
        #expect(store.localActionHistory.count == initialActionCount + 2)
        #expect(store.localActionHistory.first?.kind == .runAutomation)
        #expect(store.localActionHistory.first?.status == .completed)
        #expect(store.localActionHistory.dropFirst().first?.kind == .runTool)
    }

    @MainActor
    @Test("Run tool automation honors disabled local tool policy")
    func runToolAutomationHonorsDisabledLocalToolPolicy() throws {
        let (_, store) = try makeLoadedStore()
        let searchIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .workspaceSearch }))
        store.toolConfigurations[searchIndex].isEnabled = false
        let automation = WorkspaceAutomation(
            title: "Disabled scout",
            detail: "Attempts to search with a disabled tool.",
            cadence: .manual,
            requiresConfirmation: false,
            linkedDestination: .automations,
            actionKind: .runTool,
            action: WorkspaceAutomationAction(
                kind: .runTool,
                toolKind: .workspaceSearch,
                query: "disabled workspace search"
            )
        )
        store.automations = [automation]

        store.runAutomation(automation.id)

        let updatedAutomation = try #require(store.automations.first)
        #expect(updatedAutomation.lastRunState == .failed)
        #expect(updatedAutomation.lastResultMessage?.contains("disabled") == true)
        #expect(store.toolExecutionResults.first?.toolKind == .workspaceSearch)
        #expect(store.toolExecutionResults.first?.status == .blocked)
        #expect(store.localActionHistory.first?.kind == .runAutomation)
        #expect(store.localActionHistory.first?.status == .failed)
    }

    @MainActor
    @Test("Run tool automation rejects network and write tools")
    func runToolAutomationRejectsNetworkAndWriteTools() throws {
        let (_, store) = try makeLoadedStore()
        let automation = WorkspaceAutomation(
            title: "Network scout",
            detail: "Attempts to run a network tool autonomously.",
            cadence: .manual,
            requiresConfirmation: false,
            linkedDestination: .automations,
            actionKind: .runTool,
            action: WorkspaceAutomationAction(
                kind: .runTool,
                toolKind: .webSearch,
                query: "latest provider docs"
            )
        )
        store.automations = [automation]
        let initialToolResultCount = store.toolExecutionResults.count

        store.runAutomation(automation.id)

        let updatedAutomation = try #require(store.automations.first)
        #expect(updatedAutomation.lastRunState == .failed)
        #expect(updatedAutomation.lastResultMessage?.contains("not allowed to run autonomously") == true)
        #expect(store.toolExecutionResults.count == initialToolResultCount)
        #expect(store.localActionHistory.first?.kind == .runAutomation)
        #expect(store.localActionHistory.first?.status == .failed)
    }

    @MainActor
    @Test("Run tool automation honors global automations disabled")
    func runToolAutomationHonorsGlobalAutomationsDisabled() throws {
        let (_, store) = try makeLoadedStore()
        store.preferences.automationsEnabled = false
        let automation = WorkspaceAutomation(
            title: "Disabled automations scout",
            detail: "Should not run while automations are disabled.",
            cadence: .manual,
            requiresConfirmation: false,
            linkedDestination: .automations,
            actionKind: .runTool,
            action: WorkspaceAutomationAction(
                kind: .runTool,
                toolKind: .workspaceSearch,
                query: "local tool workflow"
            )
        )
        store.automations = [automation]
        let initialToolResultCount = store.toolExecutionResults.count

        store.runAutomation(automation.id)

        let updatedAutomation = try #require(store.automations.first)
        #expect(updatedAutomation.lastRunState == .failed)
        #expect(updatedAutomation.lastResultMessage == "Automations are disabled in Settings.")
        #expect(store.toolExecutionResults.count == initialToolResultCount)
        #expect(store.localActionHistory.first?.kind == .runAutomation)
        #expect(store.localActionHistory.first?.status == .failed)
    }

    @MainActor
    @Test("Chat tool command parses workspace search alias")
    func chatToolCommandParsesWorkspaceSearchAlias() throws {
        let store = WorkspaceStore()

        let command = try #require(store.parseChatToolCommand("/tool workspace local tool workflow"))

        #expect(command.kind == .workspaceSearch)
        #expect(command.query == "local tool workflow")
    }

    @MainActor
    @Test("Provider requested tool call maps JSON arguments to chat tool command")
    func providerRequestedToolCallMapsJSONArguments() throws {
        let store = WorkspaceStore()

        let workspaceCommand = try #require(store.chatToolCommand(for: AIToolCallRecord(
            toolName: "workspace_search",
            permissionScope: .readWorkspace,
            argumentsJSON: #"{"query":"local tool workflow","limit":3}"#
        )))
        let codeCommand = try #require(store.chatToolCommand(for: AIToolCallRecord(
            toolName: "code_execution",
            permissionScope: .runShellCommand,
            argumentsJSON: #"{"language":"swift","code":"print(\"hi\")","cwd":"/tmp/flannel"}"#
        )))
        let terminalCommand = try #require(store.chatToolCommand(for: AIToolCallRecord(
            toolName: "terminal",
            permissionScope: .runShellCommand,
            argumentsJSON: #"{"command":"pwd","cwd":"/tmp/flannel"}"#
        )))
        let writeCommand = try #require(store.chatToolCommand(for: AIToolCallRecord(
            toolName: "local_file_write",
            permissionScope: .writeWorkspace,
            argumentsJSON: #"{"path":"/tmp/flannel-note.txt","content":"hello"}"#
        )))
        let browserCommand = try #require(store.chatToolCommand(for: AIToolCallRecord(
            toolName: "browser_automation",
            permissionScope: .makeNetworkRequest,
            argumentsJSON: #"{"task":"open the current project dashboard"}"#
        )))

        #expect(workspaceCommand.kind == .workspaceSearch)
        #expect(workspaceCommand.query == "local tool workflow")
        #expect(codeCommand.kind == .codeExecution)
        #expect(codeCommand.query == "cwd: /tmp/flannel\nswift\nprint(\"hi\")")
        #expect(terminalCommand.kind == .terminal)
        #expect(terminalCommand.query == "cwd: /tmp/flannel\npwd")
        #expect(writeCommand.kind == .localFileWrite)
        #expect(writeCommand.query == "/tmp/flannel-note.txt\n---\nhello")
        #expect(browserCommand.kind == .browserAutomation)
        #expect(browserCommand.query == "open the current project dashboard")
    }

    @MainActor
    @Test("Explicit thread message updates do not follow sidebar selection")
    func explicitThreadMessageUpdatesDoNotFollowSidebarSelection() throws {
        let (_, store) = try makeLoadedStore()
        let sourceThreadID = try #require(store.selectedAssistantThreadID)
        let messageID = store.appendAssistantMessage("Streaming placeholder", role: .assistant)
        let otherThread = store.createAssistantThread()

        #expect(store.selectedAssistantThreadID == otherThread.id)

        store.updateAssistantMessage(
            messageID,
            in: sourceThreadID,
            text: "Streaming token from the original chat"
        )

        let sourceThread = try #require(store.assistantThreads.first { $0.id == sourceThreadID })
        let updatedMessage = try #require(sourceThread.messages.first { $0.id == messageID })
        let selectedThread = try #require(store.currentAssistantThread)

        #expect(updatedMessage.text == "Streaming token from the original chat")
        #expect(selectedThread.id == otherThread.id)
        #expect(selectedThread.messages.contains { $0.id == messageID } == false)
    }

    @MainActor
    @Test("Explicit thread tool result append does not follow sidebar selection")
    func explicitThreadToolResultAppendDoesNotFollowSidebarSelection() throws {
        let (_, store) = try makeLoadedStore()
        let sourceThreadID = try #require(store.selectedAssistantThreadID)
        let result = LocalToolExecutionResult(
            toolID: nil,
            toolKind: .workspaceSearch,
            title: "Workspace Search",
            query: "original chat",
            status: .completed,
            output: "Search output belongs to the original chat."
        )
        let otherThread = store.createAssistantThread()

        #expect(store.selectedAssistantThreadID == otherThread.id)

        let messageID = try #require(store.appendToolResultMessage(result, in: sourceThreadID))
        let sourceThread = try #require(store.assistantThreads.first { $0.id == sourceThreadID })
        let appendedMessage = try #require(sourceThread.messages.first { $0.id == messageID })
        let selectedThread = try #require(store.currentAssistantThread)

        #expect(appendedMessage.referencedEntityIDs.contains(result.id))
        #expect(appendedMessage.text.contains("Tool run: Workspace Search"))
        #expect(selectedThread.id == otherThread.id)
        #expect(selectedThread.messages.contains { $0.id == messageID } == false)
    }

    @MainActor
    @Test("Provider requested workspace tool runs through local execution pipeline")
    func providerRequestedWorkspaceToolRunsThroughLocalExecutionPipeline() async throws {
        let (_, store) = try makeLoadedStore()
        let workspaceIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .workspaceSearch }))
        store.toolConfigurations[workspaceIndex].isEnabled = true
        store.toolConfigurations[workspaceIndex].permissionPolicy = .alwaysAllow
        let messageID = store.appendAssistantMessage("Provider requested a local workspace search.", role: .assistant)
        let toolCall = AIToolCallRecord(
            toolName: "workspace_search",
            permissionScope: .readWorkspace,
            argumentsJSON: #"{"query":"local tool workflow","limit":3}"#
        )
        let threadIndex = try #require(store.assistantThreads.firstIndex(where: { $0.id == store.selectedAssistantThreadID }))
        let messageIndex = try #require(store.assistantThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }))
        store.assistantThreads[threadIndex].messages[messageIndex].toolCalls = [toolCall]

        let result = try #require(await store.runRequestedToolCall(
            toolCall.id,
            in: messageID,
            webPageCaptureService: WebPageCaptureService()
        ))
        let updatedMessage = try #require(store.assistantThreads[threadIndex].messages.first(where: { $0.id == messageID }))
        let updatedToolCall = try #require(updatedMessage.toolCalls.first)
        let resultMessage = try #require(store.currentAssistantThread?.messages.first {
            $0.referencedEntityIDs.contains(result.id)
        })

        #expect(result.status == .completed)
        #expect(result.toolKind == .workspaceSearch)
        #expect(result.query == "local tool workflow")
        #expect(updatedToolCall.executionStatus == .completed)
        #expect(updatedToolCall.executionResultID == result.id)
        #expect(updatedToolCall.wasApproved)
        #expect(updatedToolCall.outputPreview?.contains("Workspace search for \"local tool workflow\"") == true)
        #expect(resultMessage.text.contains("Tool run: Workspace Search"))
    }

    @MainActor
    @Test("Provider requested always-allow tool calls auto-run through local execution pipeline")
    func providerRequestedAlwaysAllowToolCallsAutoRunThroughLocalExecutionPipeline() async throws {
        let (_, store) = try makeLoadedStore()
        let initialToolResultCount = store.toolExecutionResults.count
        let workspaceIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .workspaceSearch }))
        store.toolConfigurations[workspaceIndex].isEnabled = true
        store.toolConfigurations[workspaceIndex].permissionPolicy = .alwaysAllow
        let messageID = store.appendAssistantMessage("Provider requested local context.", role: .assistant)
        let toolCall = AIToolCallRecord(
            toolName: "workspace_search",
            permissionScope: .readWorkspace,
            argumentsJSON: #"{"query":"local tool workflow","limit":3}"#
        )
        let threadIndex = try #require(store.assistantThreads.firstIndex(where: { $0.id == store.selectedAssistantThreadID }))
        let messageIndex = try #require(store.assistantThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }))
        store.assistantThreads[threadIndex].messages[messageIndex].toolCalls = [toolCall]

        let runnable = store.autoApprovedRequestedToolCalls(in: messageID)
        let executions = await store.runAutoApprovedRequestedToolCalls(
            in: messageID,
            webPageCaptureService: WebPageCaptureService()
        )

        #expect(runnable.map(\.id) == [toolCall.id])
        #expect(executions.count == 1)
        let execution = try #require(executions.first)
        #expect(execution.result.status == .completed)
        #expect(execution.result.toolKind == .workspaceSearch)
        #expect(execution.result.query == "local tool workflow")
        #expect(execution.toolCall.executionStatus == .completed)
        #expect(execution.toolCall.executionResultID == execution.result.id)
        #expect(execution.toolCall.wasApproved)
        #expect(store.toolExecutionResults.count == initialToolResultCount + 1)
        #expect(store.currentAssistantThread?.messages.contains {
            $0.referencedEntityIDs.contains(execution.result.id)
        } == true)
    }

    @MainActor
    @Test("Provider requested ask-every-time tool calls do not auto-run")
    func providerRequestedAskEveryTimeToolCallsDoNotAutoRun() async throws {
        let (_, store) = try makeLoadedStore()
        let initialToolResultCount = store.toolExecutionResults.count
        let workspaceIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .workspaceSearch }))
        store.toolConfigurations[workspaceIndex].isEnabled = true
        store.toolConfigurations[workspaceIndex].permissionPolicy = .askEveryTime
        let messageID = store.appendAssistantMessage("Provider requested local context.", role: .assistant)
        let toolCall = AIToolCallRecord(
            toolName: "workspace_search",
            permissionScope: .readWorkspace,
            argumentsJSON: #"{"query":"manual approval required","limit":3}"#
        )
        let threadIndex = try #require(store.assistantThreads.firstIndex(where: { $0.id == store.selectedAssistantThreadID }))
        let messageIndex = try #require(store.assistantThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }))
        store.assistantThreads[threadIndex].messages[messageIndex].toolCalls = [toolCall]

        let runnable = store.autoApprovedRequestedToolCalls(in: messageID)
        let executions = await store.runAutoApprovedRequestedToolCalls(
            in: messageID,
            webPageCaptureService: WebPageCaptureService()
        )
        let unchangedMessage = try #require(store.assistantThreads[threadIndex].messages.first(where: { $0.id == messageID }))
        let unchangedToolCall = try #require(unchangedMessage.toolCalls.first)

        #expect(runnable.isEmpty)
        #expect(executions.isEmpty)
        #expect(unchangedToolCall.executionStatus == nil)
        #expect(unchangedToolCall.executionResultID == nil)
        #expect(store.toolExecutionResults.count == initialToolResultCount)
    }

    @MainActor
    @Test("Provider requested tool call can be denied without creating tool result")
    func providerRequestedToolCallCanBeDenied() throws {
        let (_, store) = try makeLoadedStore()
        let initialToolResultCount = store.toolExecutionResults.count
        let messageID = store.appendAssistantMessage("Provider requested a network search.", role: .assistant)
        let toolCall = AIToolCallRecord(
            toolName: "web_search",
            permissionScope: .makeNetworkRequest,
            argumentsJSON: #"{"query":"latest docs"}"#
        )
        let threadIndex = try #require(store.assistantThreads.firstIndex(where: { $0.id == store.selectedAssistantThreadID }))
        let messageIndex = try #require(store.assistantThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }))
        store.assistantThreads[threadIndex].messages[messageIndex].toolCalls = [toolCall]

        let denied = try #require(store.denyRequestedToolCall(toolCall.id, in: messageID))

        #expect(denied.executionStatus == .denied)
        #expect(denied.wasApproved == false)
        #expect(denied.outputPreview?.contains("Denied locally") == true)
        #expect(denied.completedAt != nil)
        #expect(store.toolExecutionResults.count == initialToolResultCount)
    }

    @MainActor
    @Test("Provider requested pending tool call refreshes after approval")
    func providerRequestedPendingToolCallRefreshesAfterApproval() async throws {
        let (_, store) = try makeLoadedStore()
        let terminalIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .terminal }))
        store.toolConfigurations[terminalIndex].isEnabled = true
        store.toolConfigurations[terminalIndex].permissionPolicy = .askEveryTime
        let messageID = store.appendAssistantMessage("Provider requested a local command.", role: .assistant)
        let toolCall = AIToolCallRecord(
            toolName: "terminal",
            permissionScope: .runShellCommand,
            argumentsJSON: #"{"command":"printf FLANNEL_PROVIDER_TOOL"}"#
        )
        let threadIndex = try #require(store.assistantThreads.firstIndex(where: { $0.id == store.selectedAssistantThreadID }))
        let messageIndex = try #require(store.assistantThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }))
        store.assistantThreads[threadIndex].messages[messageIndex].toolCalls = [toolCall]

        let queued = try #require(await store.runRequestedToolCall(
            toolCall.id,
            in: messageID,
            webPageCaptureService: WebPageCaptureService()
        ))
        let queuedMessage = try #require(store.assistantThreads[threadIndex].messages.first(where: { $0.id == messageID }))
        let queuedToolCall = try #require(queuedMessage.toolCalls.first)

        #expect(queued.status == .requiresApproval)
        #expect(queuedToolCall.executionStatus == .requiresApproval)
        #expect(queuedToolCall.executionResultID == queued.id)
        #expect(queuedToolCall.wasApproved == false)

        let approved = try #require(await store.resolveToolApproval(
            queued.id,
            approve: true,
            webPageCaptureService: WebPageCaptureService()
        ))
        let refreshedToolCall = try #require(store.refreshRequestedToolCall(forToolResult: approved))

        #expect(approved.status == .completed)
        #expect(approved.output.contains("FLANNEL_PROVIDER_TOOL"))
        #expect(refreshedToolCall.executionStatus == .completed)
        #expect(refreshedToolCall.executionResultID == queued.id)
        #expect(refreshedToolCall.wasApproved)
        #expect(refreshedToolCall.outputPreview?.contains("FLANNEL_PROVIDER_TOOL") == true)
    }

    @MainActor
    @Test("Chat workspace tool appends assistant result attachment")
    func chatWorkspaceToolAppendsAssistantResultAttachment() throws {
        let (_, store) = try makeLoadedStore()
        let initialMessageCount = try #require(store.currentAssistantThread?.messages.count)
        let command = try #require(store.parseChatToolCommand("/tool workspace local tool workflow"))

        let result = store.runChatToolCommand(command)
        let messageID = store.appendToolResultMessage(result)
        let thread = try #require(store.currentAssistantThread)
        let message = try #require(thread.messages.first(where: { $0.id == messageID }))
        let attachment = try #require(message.attachments.first(where: { $0.kind == .toolResult }))

        #expect(result.status == .completed)
        #expect(result.toolKind == .workspaceSearch)
        #expect(result.query == "local tool workflow")
        #expect(result.output.contains("Workspace search for \"local tool workflow\""))
        #expect(store.toolExecutionResults.contains { $0.id == result.id })
        #expect(thread.messages.count == initialMessageCount + 1)
        #expect(message.role == .assistant)
        #expect(message.referencedEntityIDs.contains(result.id))
        #expect(message.text.contains("Tool run: Workspace Search"))
        #expect(message.text.contains("Status: Completed locally."))
        #expect(message.text.contains("Query: local tool workflow"))
        #expect(attachment.kind == .toolResult)
        #expect(attachment.title == result.title)
        #expect(attachment.mimeType == "text/plain")
        #expect(attachment.excerpt?.contains("Workspace search for \"local tool workflow\"") == true)
    }

    @MainActor
    @Test("Local-only mode blocks network tools before attempting execution")
    func localOnlyModeBlocksNetworkTools() throws {
        let (_, store) = try makeLoadedStore()
        let initialToolResultCount = store.toolExecutionResults.count
        let webSearchIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .webSearch }))
        store.toolConfigurations[webSearchIndex].isEnabled = true
        store.toolConfigurations[webSearchIndex].permissionPolicy = .alwaysAllow
        store.preferences.localOnlyMode = true

        let result = store.runTool(.webSearch, query: "network lookup")

        #expect(result.status == .blocked)
        #expect(result.usedNetwork == false)
        #expect(result.output.contains("requires network access and is blocked while Local-Only mode is on"))
        #expect(store.toolExecutionResults.count == initialToolResultCount + 1)
        #expect(store.toolExecutionResults.contains { $0.toolKind == .webSearch && $0.status == .blocked })
    }

    @MainActor
    @Test("Seeded tool matrix exposes all supported tool kinds")
    func seededToolMatrixExposesAllSupportedToolKinds() throws {
        let (_, store) = try makeLoadedStore()

        let configuredKinds = Set(store.toolConfigurations.map(\.kind))

        #expect(configuredKinds == Set(AIToolKind.allCases))
        #expect(store.toolConfigurations.first(where: { $0.kind == .webPageReader })?.requiresNetwork == true)
        #expect(store.toolConfigurations.first(where: { $0.kind == .workspaceSearch })?.isEnabled == true)
        #expect(store.toolConfigurations.first(where: { $0.kind == .ragRetrieval })?.isEnabled == true)
    }

    @MainActor
    @Test("Live web page reader fetches readable text when network is allowed")
    func liveWebPageReaderFetchesReadableTextWhenNetworkAllowed() async throws {
        let (_, store) = try makeLoadedStore()
        let initialToolResultCount = store.toolExecutionResults.count
        let readerIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .webPageReader }))
        store.toolConfigurations[readerIndex].isEnabled = true
        store.toolConfigurations[readerIndex].permissionPolicy = .alwaysAllow
        store.preferences.localOnlyMode = false
        let expectedURL = URL(string: "https://example.com/flannel-live-reader")!
        let service = WebPageCaptureService { url, capturedAt, _ in
            CapturedWebPage(
                url: url,
                title: "Flannel Live Reader",
                text: "Readable network page text for SUNSTONE TOOL checks.",
                excerpt: "Readable network page text",
                statusCode: 200,
                contentType: "text/html; charset=utf-8",
                capturedAt: capturedAt
            )
        }

        let result = await store.runTool(
            .webPageReader,
            query: expectedURL.absoluteString,
            webPageCaptureService: service
        )

        #expect(result.status == .completed)
        #expect(result.usedNetwork == true)
        #expect(result.modifiedFiles == false)
        #expect(result.output.contains("Live web page reader"))
        #expect(result.output.contains("Flannel Live Reader"))
        #expect(result.output.contains(expectedURL.absoluteString))
        #expect(result.output.contains("SUNSTONE TOOL"))
        #expect(store.toolExecutionResults.count == initialToolResultCount + 1)
        #expect(store.toolExecutionResults.first?.id == result.id)
    }

    @MainActor
    @Test("Approved live web page reader executes after ask-every-time approval")
    func approvedLiveWebPageReaderExecutesAfterApproval() async throws {
        let (_, store) = try makeLoadedStore()
        let readerIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .webPageReader }))
        store.toolConfigurations[readerIndex].isEnabled = true
        store.toolConfigurations[readerIndex].permissionPolicy = .askEveryTime
        store.preferences.localOnlyMode = false
        let service = WebPageCaptureService { url, capturedAt, _ in
            CapturedWebPage(
                url: url,
                title: "Approved Reader",
                text: "Approved network read content for VIOLET NEEDLE checks.",
                excerpt: "Approved network read content",
                statusCode: 200,
                contentType: "text/html",
                capturedAt: capturedAt
            )
        }

        let queued = await store.runTool(
            .webPageReader,
            query: "url: https://example.com/approved-reader",
            webPageCaptureService: service
        )
        let approved = try #require(await store.resolveToolApproval(
            queued.id,
            approve: true,
            webPageCaptureService: service
        ))

        #expect(queued.status == .requiresApproval)
        #expect(queued.requiresApproval == true)
        #expect(queued.usedNetwork == true)
        #expect(approved.id == queued.id)
        #expect(approved.status == .completed)
        #expect(approved.requiresApproval == false)
        #expect(approved.usedNetwork == true)
        #expect(approved.output.contains("Approved locally and executed"))
        #expect(approved.output.contains("VIOLET NEEDLE"))
    }

    @MainActor
    @Test("Web search requires a Keychain API key before network execution")
    func webSearchRequiresKeychainAPIKeyBeforeNetworkExecution() async throws {
        let (_, store) = try makeLoadedStore()
        let webSearchIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .webSearch }))
        store.toolConfigurations[webSearchIndex].isEnabled = true
        store.toolConfigurations[webSearchIndex].permissionPolicy = .alwaysAllow
        store.preferences.localOnlyMode = false
        let service = WebSearchService { _ in
            Issue.record("Web search should not touch the network without a Keychain reference.")
            return (Data(), nil)
        }

        let result = await store.runTool(
            .webSearch,
            query: "local-first macOS AI chat",
            webPageCaptureService: WebPageCaptureService(),
            webSearchService: service
        )

        #expect(result.status == .unavailable)
        #expect(result.usedNetwork == false)
        #expect(result.output.contains("Brave Search API key"))
    }

    @MainActor
    @Test("Web search runs Brave connector with injected transport")
    func webSearchRunsBraveConnectorWithInjectedTransport() async throws {
        let (_, store) = try makeLoadedStore()
        let webSearchIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .webSearch }))
        store.toolConfigurations[webSearchIndex].isEnabled = true
        store.toolConfigurations[webSearchIndex].permissionPolicy = .alwaysAllow
        store.toolConfigurations[webSearchIndex].endpoint = WebSearchService.defaultEndpoint
        store.toolConfigurations[webSearchIndex].secretReference = "flannel.test:web-search"
        store.preferences.localOnlyMode = false
        let recorder = ToolRequestRecorder()
        let service = WebSearchService { request in
            await recorder.record(request)
            let payload = """
            {
              "results": [
                {
                  "title": "Brave Search API",
                  "url": "https://api-dashboard.search.brave.com/documentation/quickstart",
                  "snippets": ["Use X-Subscription-Token for authenticated search requests."]
                }
              ],
              "context": "Brave Search API documentation describes authenticated web search and LLM context responses for agent and retrieval augmented generation workflows."
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let result = await store.runTool(
            .webSearch,
            query: "Brave Search API agents",
            webPageCaptureService: WebPageCaptureService(),
            webSearchService: service,
            secretReader: { reference in
                #expect(reference.rawValue == "flannel.test:web-search")
                return "test-brave-key"
            }
        )
        let requests = await recorder.requests
        let request = try #require(requests.first)

        #expect(result.status == .completed)
        #expect(result.usedNetwork == true)
        #expect(result.output.contains("Live web search"))
        #expect(result.output.contains("Brave Search API"))
        #expect(result.output.contains("X-Subscription-Token"))
        #expect(result.output.contains("LLM context"))
        #expect(request.value(forHTTPHeaderField: "X-Subscription-Token") == "test-brave-key")
        #expect(request.url?.absoluteString.contains("/res/v1/llm/context") == true)
        #expect(request.url?.query?.contains("q=Brave%20Search%20API%20agents") == true)
    }

    @MainActor
    @Test("Approved web search executes after ask-every-time approval")
    func approvedWebSearchExecutesAfterAskEveryTimeApproval() async throws {
        let (_, store) = try makeLoadedStore()
        let webSearchIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .webSearch }))
        store.toolConfigurations[webSearchIndex].isEnabled = true
        store.toolConfigurations[webSearchIndex].permissionPolicy = .askEveryTime
        store.toolConfigurations[webSearchIndex].secretReference = "flannel.test:web-search"
        store.preferences.localOnlyMode = false
        let service = WebSearchService { request in
            let payload = """
            {
              "web": {
                "results": [
                  {
                    "title": "Local-first AI chat",
                    "url": "https://example.com/flannel-search",
                    "description": "A result returned after explicit local approval."
                  }
                ]
              }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let queued = await store.runTool(
            .webSearch,
            query: "approval gated search",
            webPageCaptureService: WebPageCaptureService(),
            webSearchService: service,
            secretReader: { _ in "unused-before-approval" }
        )
        let approved = try #require(await store.resolveToolApproval(
            queued.id,
            approve: true,
            webPageCaptureService: WebPageCaptureService(),
            webSearchService: service,
            secretReader: { _ in "approved-key" }
        ))

        #expect(queued.status == .requiresApproval)
        #expect(queued.requiresApproval == true)
        #expect(queued.usedNetwork == true)
        #expect(approved.id == queued.id)
        #expect(approved.status == .completed)
        #expect(approved.requiresApproval == false)
        #expect(approved.usedNetwork == true)
        #expect(approved.output.contains("Approved locally and executed"))
        #expect(approved.output.contains("https://example.com/flannel-search"))
    }

    @MainActor
    @Test("GitHub tool fetches public repository context without a token")
    func githubToolFetchesPublicRepositoryContextWithoutToken() async throws {
        let (_, store) = try makeLoadedStore()
        let githubIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .github }))
        store.toolConfigurations[githubIndex].isEnabled = true
        store.toolConfigurations[githubIndex].permissionPolicy = .alwaysAllow
        store.preferences.localOnlyMode = false
        let recorder = ToolRequestRecorder()
        let service = GitHubToolService { request in
            await recorder.record(request)
            let payload = """
            {
              "full_name": "openai/codex",
              "html_url": "https://github.com/openai/codex",
              "description": "A local coding agent.",
              "stargazers_count": 12000,
              "forks_count": 900,
              "open_issues_count": 120,
              "language": "Rust"
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let result = await store.runTool(
            .github,
            query: "openai/codex",
            webPageCaptureService: WebPageCaptureService(),
            gitHubToolService: service
        )
        let request = try #require(await recorder.requests.first)

        #expect(result.status == .completed)
        #expect(result.usedNetwork == true)
        #expect(result.output.contains("GitHub context"))
        #expect(result.output.contains("openai/codex"))
        #expect(result.output.contains("12000 stars"))
        #expect(request.url?.path == "/repos/openai/codex")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == GitHubToolService.apiVersion)
    }

    @MainActor
    @Test("GitHub tool uses saved Keychain token when configured")
    func githubToolUsesSavedKeychainTokenWhenConfigured() async throws {
        let (_, store) = try makeLoadedStore()
        let githubIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .github }))
        store.toolConfigurations[githubIndex].isEnabled = true
        store.toolConfigurations[githubIndex].permissionPolicy = .alwaysAllow
        store.toolConfigurations[githubIndex].secretReference = "flannel.test:github"
        store.preferences.localOnlyMode = false
        let recorder = ToolRequestRecorder()
        let service = GitHubToolService { request in
            await recorder.record(request)
            let payload = """
            {
              "items": [
                {
                  "title": "Add local-first chat history",
                  "html_url": "https://github.com/symbiex/flannel/issues/42",
                  "number": 42,
                  "state": "open",
                  "body": "Track local history, folders, and search.",
                  "user": { "login": "symbiex" }
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let result = await store.runTool(
            .github,
            query: "issues: repo:symbiex/flannel chat history",
            webPageCaptureService: WebPageCaptureService(),
            gitHubToolService: service,
            secretReader: { reference in
                #expect(reference.rawValue == "flannel.test:github")
                return "ghp_test_token"
            }
        )
        let request = try #require(await recorder.requests.first)

        #expect(result.status == .completed)
        #expect(result.output.contains("Add local-first chat history"))
        #expect(result.output.contains("#42"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_test_token")
        #expect(request.url?.path == "/search/issues")
        #expect(request.url?.query?.contains("type:issue") == true)
    }

    @MainActor
    @Test("Approved GitHub tool executes after ask-every-time approval")
    func approvedGithubToolExecutesAfterAskEveryTimeApproval() async throws {
        let (_, store) = try makeLoadedStore()
        let githubIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .github }))
        store.toolConfigurations[githubIndex].isEnabled = true
        store.toolConfigurations[githubIndex].permissionPolicy = .askEveryTime
        store.preferences.localOnlyMode = false
        let service = GitHubToolService { request in
            let payload = """
            {
              "items": [
                {
                  "full_name": "symbiex/flannel",
                  "html_url": "https://github.com/symbiex/flannel",
                  "description": "Native local-first AI chat.",
                  "stargazers_count": 7,
                  "forks_count": 1,
                  "open_issues_count": 2,
                  "language": "Swift"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let queued = await store.runTool(
            .github,
            query: "flannel local-first ai chat",
            webPageCaptureService: WebPageCaptureService(),
            gitHubToolService: service
        )
        let approved = try #require(await store.resolveToolApproval(
            queued.id,
            approve: true,
            webPageCaptureService: WebPageCaptureService(),
            gitHubToolService: service
        ))

        #expect(queued.status == .requiresApproval)
        #expect(queued.requiresApproval == true)
        #expect(queued.usedNetwork == true)
        #expect(approved.id == queued.id)
        #expect(approved.status == .completed)
        #expect(approved.requiresApproval == false)
        #expect(approved.usedNetwork == true)
        #expect(approved.output.contains("Approved locally and executed"))
        #expect(approved.output.contains("https://github.com/symbiex/flannel"))
    }

    @MainActor
    @Test("Notion tool requires a Keychain token before network execution")
    func notionToolRequiresKeychainTokenBeforeNetworkExecution() async throws {
        let (_, store) = try makeLoadedStore()
        let notionIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .notion }))
        store.toolConfigurations[notionIndex].isEnabled = true
        store.toolConfigurations[notionIndex].permissionPolicy = .alwaysAllow
        store.preferences.localOnlyMode = false
        let service = NotionToolService { _ in
            Issue.record("Notion should not touch the network without a Keychain token reference.")
            return (Data(), nil)
        }

        let result = await store.runTool(
            .notion,
            query: "launch plan",
            webPageCaptureService: WebPageCaptureService(),
            notionToolService: service
        )

        #expect(result.status == .unavailable)
        #expect(result.usedNetwork == false)
        #expect(result.output.contains("Notion integration token"))
    }

    @MainActor
    @Test("Notion search uses the /v1/search route with current API headers")
    func notionSearchUsesSearchRouteWithCurrentHeaders() async throws {
        let (_, store) = try makeLoadedStore()
        let notionIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .notion }))
        store.toolConfigurations[notionIndex].isEnabled = true
        store.toolConfigurations[notionIndex].permissionPolicy = .alwaysAllow
        store.toolConfigurations[notionIndex].secretReference = "flannel.test:notion"
        store.preferences.localOnlyMode = false
        let recorder = ToolRequestRecorder()
        let service = NotionToolService { request in
            await recorder.record(request)
            let payload = """
            {
              "object": "list",
              "results": [
                {
                  "object": "page",
                  "id": "01234567-89ab-cdef-0123-456789abcdef",
                  "url": "https://www.notion.so/Launch-0123456789abcdef0123456789abcdef",
                  "created_time": "2026-06-01T10:00:00.000Z",
                  "last_edited_time": "2026-06-29T10:00:00.000Z",
                  "properties": {
                    "Name": {
                      "type": "title",
                      "title": [{"plain_text": "Launch plan"}]
                    },
                    "Status": {
                      "type": "status",
                      "status": {"name": "Ready"}
                    }
                  }
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let result = await store.runTool(
            .notion,
            query: "launch plan",
            webPageCaptureService: WebPageCaptureService(),
            notionToolService: service,
            secretReader: { reference in
                #expect(reference.rawValue == "flannel.test:notion")
                return "secret_notion_token"
            }
        )
        let request = try #require(await recorder.requests.first)
        let body = try #require(request.httpBody)
        let bodyObject = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(result.status == .completed)
        #expect(result.usedNetwork == true)
        #expect(result.output.contains("Notion context"))
        #expect(result.output.contains("Launch plan"))
        #expect(result.output.contains("Status: Ready"))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/search")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret_notion_token")
        #expect(request.value(forHTTPHeaderField: "Notion-Version") == NotionToolService.apiVersion)
        #expect(bodyObject["query"] as? String == "launch plan")
    }

    @MainActor
    @Test("Notion page URL fetches page markdown context")
    func notionPageURLFetchesMarkdownRoute() async throws {
        let (_, store) = try makeLoadedStore()
        let notionIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .notion }))
        store.toolConfigurations[notionIndex].isEnabled = true
        store.toolConfigurations[notionIndex].permissionPolicy = .alwaysAllow
        store.toolConfigurations[notionIndex].secretReference = "flannel.test:notion"
        store.preferences.localOnlyMode = false
        let recorder = ToolRequestRecorder()
        let service = NotionToolService { request in
            await recorder.record(request)
            let payload = """
            {
              "object": "page",
              "id": "01234567-89ab-cdef-0123-456789abcdef",
              "title": "Launch plan",
              "url": "https://www.notion.so/Launch-0123456789abcdef0123456789abcdef",
              "markdown": "# Launch plan\\nPrivate workspace notes for the release."
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let result = await store.runTool(
            .notion,
            query: "https://www.notion.so/Launch-0123456789abcdef0123456789abcdef?pvs=4",
            webPageCaptureService: WebPageCaptureService(),
            notionToolService: service,
            secretReader: { _ in "secret_notion_token" }
        )
        let request = try #require(await recorder.requests.first)

        #expect(result.status == .completed)
        #expect(result.output.contains("Page markdown"))
        #expect(result.output.contains("Private workspace notes"))
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/pages/01234567-89ab-cdef-0123-456789abcdef/markdown")
        #expect(request.value(forHTTPHeaderField: "Notion-Version") == NotionToolService.apiVersion)
    }

    @MainActor
    @Test("Notion data source query posts to data source query route")
    func notionDataSourceQueryUsesDataSourceRoute() async throws {
        let (_, store) = try makeLoadedStore()
        let notionIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .notion }))
        store.toolConfigurations[notionIndex].isEnabled = true
        store.toolConfigurations[notionIndex].permissionPolicy = .alwaysAllow
        store.toolConfigurations[notionIndex].secretReference = "flannel.test:notion"
        store.preferences.localOnlyMode = false
        let recorder = ToolRequestRecorder()
        let service = NotionToolService { request in
            await recorder.record(request)
            let payload = """
            {
              "object": "list",
              "results": [
                {
                  "object": "page",
                  "id": "11111111-2222-3333-4444-555555555555",
                  "properties": {
                    "Task": {
                      "type": "title",
                      "title": [{"plain_text": "Ship Notion connector"}]
                    },
                    "Priority": {
                      "type": "select",
                      "select": {"name": "High"}
                    }
                  }
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let result = await store.runTool(
            .notion,
            query: "data_source: 01234567-89ab-cdef-0123-456789abcdef",
            webPageCaptureService: WebPageCaptureService(),
            notionToolService: service,
            secretReader: { _ in "secret_notion_token" }
        )
        let request = try #require(await recorder.requests.first)
        let body = try #require(request.httpBody)
        let bodyObject = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(result.status == .completed)
        #expect(result.output.contains("Data source query"))
        #expect(result.output.contains("Ship Notion connector"))
        #expect(result.output.contains("Priority: High"))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/data_sources/01234567-89ab-cdef-0123-456789abcdef/query")
        #expect(bodyObject["page_size"] as? Int == 8)
    }

    @MainActor
    @Test("Approved Notion tool executes after ask-every-time approval")
    func approvedNotionToolExecutesAfterAskEveryTimeApproval() async throws {
        let (_, store) = try makeLoadedStore()
        let notionIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .notion }))
        store.toolConfigurations[notionIndex].isEnabled = true
        store.toolConfigurations[notionIndex].permissionPolicy = .askEveryTime
        store.toolConfigurations[notionIndex].secretReference = "flannel.test:notion"
        store.preferences.localOnlyMode = false
        let service = NotionToolService { request in
            let payload = """
            {
              "object": "list",
              "results": [
                {
                  "object": "page",
                  "id": "99999999-8888-7777-6666-555555555555",
                  "properties": {
                    "Name": {
                      "type": "title",
                      "title": [{"plain_text": "Approved Notion context"}]
                    }
                  }
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let queued = await store.runTool(
            .notion,
            query: "approval gated notion",
            webPageCaptureService: WebPageCaptureService(),
            notionToolService: service,
            secretReader: { _ in "unused-before-approval" }
        )
        let approved = try #require(await store.resolveToolApproval(
            queued.id,
            approve: true,
            webPageCaptureService: WebPageCaptureService(),
            notionToolService: service,
            secretReader: { _ in "approved-notion-token" }
        ))

        #expect(queued.status == .requiresApproval)
        #expect(queued.requiresApproval == true)
        #expect(queued.usedNetwork == true)
        #expect(approved.id == queued.id)
        #expect(approved.status == .completed)
        #expect(approved.requiresApproval == false)
        #expect(approved.usedNetwork == true)
        #expect(approved.output.contains("Approved locally and executed"))
        #expect(approved.output.contains("Approved Notion context"))
    }

    @MainActor
    @Test("YouTube tool reports missing API key as unavailable without network")
    func youTubeToolWithoutAPIKeyIsUnavailable() async throws {
        let (_, store) = try makeLoadedStore()
        let youTubeIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .youtube }))
        store.toolConfigurations[youTubeIndex].isEnabled = true
        store.toolConfigurations[youTubeIndex].permissionPolicy = .alwaysAllow
        store.toolConfigurations[youTubeIndex].secretReference = "flannel.test:youtube"
        store.toolConfigurations[youTubeIndex].endpoint = YouTubeToolService.defaultEndpoint
        store.preferences.localOnlyMode = false
        let service = YouTubeToolService { _ in
            Issue.record("YouTube should not use network transport when API key is unavailable.")
            return (Data(), nil)
        }

        let result = await store.runTool(
            .youtube,
            query: "local-first video production",
            webPageCaptureService: WebPageCaptureService(),
            youTubeToolService: service,
            secretReader: { reference in
                #expect(reference.rawValue == "flannel.test:youtube")
                return ""
            }
        )

        #expect(result.status == .unavailable)
        #expect(result.usedNetwork == false)
        #expect(result.output.lowercased().contains("youtube"))
    }

    @MainActor
    @Test("YouTube search uses the /search endpoint with type=video and query")
    func youTubeSearchUsesSearchEndpointWithTypeVideo() async throws {
        let (_, store) = try makeLoadedStore()
        let youTubeIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .youtube }))
        store.toolConfigurations[youTubeIndex].isEnabled = true
        store.toolConfigurations[youTubeIndex].permissionPolicy = .alwaysAllow
        store.toolConfigurations[youTubeIndex].secretReference = "flannel.test:youtube"
        store.toolConfigurations[youTubeIndex].endpoint = YouTubeToolService.defaultEndpoint
        store.preferences.localOnlyMode = false
        let recorder = ToolRequestRecorder()
        let service = YouTubeToolService { request in
            await recorder.record(request)
            let payload = """
            {
              "items": [
                {
                  "id": {
                    "kind": "youtube#video",
                    "videoId": "dQw4w9WgXcQ"
                  },
                  "snippet": {
                    "title": "Creator first principles",
                    "description": "An interview on creator workflows.",
                    "channelTitle": "OpenAI Codex"
                  }
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let result = await store.runTool(
            .youtube,
            query: "creator focused tutorial",
            webPageCaptureService: WebPageCaptureService(),
            youTubeToolService: service,
            secretReader: { _ in "test-youtube-key" }
        )
        let request = try #require(await recorder.requests.first)
        let requestComponents = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))

        #expect(result.status == .completed)
        #expect(result.usedNetwork == true)
        #expect(result.output.contains("YouTube context"))
        #expect(result.output.contains("creator focused tutorial"))
        #expect(requestComponents.path == "/youtube/v3/search")
        #expect(requestComponents.queryItems?.contains { $0.name == "type" && $0.value == "video" } == true)
        #expect(requestComponents.queryItems?.contains { $0.name == "q" && $0.value == "creator focused tutorial" } == true)
        #expect(requestComponents.queryItems?.contains { $0.name == "key" && $0.value == "test-youtube-key" } == true)
    }

    @MainActor
    @Test("YouTube video URL uses /videos with id and rich parts")
    func youTubeVideoURLUsesVideosEndpoint() async throws {
        let (_, store) = try makeLoadedStore()
        let youTubeIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .youtube }))
        store.toolConfigurations[youTubeIndex].isEnabled = true
        store.toolConfigurations[youTubeIndex].permissionPolicy = .alwaysAllow
        store.toolConfigurations[youTubeIndex].secretReference = "flannel.test:youtube"
        store.toolConfigurations[youTubeIndex].endpoint = YouTubeToolService.defaultEndpoint
        store.preferences.localOnlyMode = false
        let recorder = ToolRequestRecorder()
        let service = YouTubeToolService { request in
            await recorder.record(request)
            let payload = """
            {
              "items": [
                {
                  "id": "dQw4w9WgXcQ",
                  "snippet": {
                    "title": "Video Detail Flow",
                    "description": "Route-level validation for YouTube detail.",
                    "channelTitle": "OpenAI Codex"
                  },
                  "contentDetails": {
                    "duration": "PT3M45S"
                  },
                  "statistics": {
                    "viewCount": "1001",
                    "likeCount": "88"
                  }
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let result = await store.runTool(
            .youtube,
            query: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            webPageCaptureService: WebPageCaptureService(),
            youTubeToolService: service,
            secretReader: { _ in "test-youtube-key" }
        )
        let request = try #require(await recorder.requests.first)
        let requestComponents = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))

        #expect(result.status == .completed)
        #expect(result.usedNetwork == true)
        #expect(result.output.contains("Video Detail Flow"))
        #expect(requestComponents.path == "/youtube/v3/videos")
        #expect(requestComponents.queryItems?.contains { $0.name == "id" && $0.value == "dQw4w9WgXcQ" } == true)
        #expect(
            requestComponents.queryItems?.contains {
                $0.name == "part" && $0.value == "snippet,contentDetails,statistics"
            } == true
        )
    }

    @MainActor
    @Test("Approved YouTube tool executes after ask-every-time approval")
    func approvedYouTubeToolExecutesAfterAskEveryTimeApproval() async throws {
        let (_, store) = try makeLoadedStore()
        let youTubeIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .youtube }))
        store.toolConfigurations[youTubeIndex].isEnabled = true
        store.toolConfigurations[youTubeIndex].permissionPolicy = .askEveryTime
        store.toolConfigurations[youTubeIndex].secretReference = "flannel.test:youtube"
        store.toolConfigurations[youTubeIndex].endpoint = YouTubeToolService.defaultEndpoint
        store.preferences.localOnlyMode = false
        let service = YouTubeToolService { request in
            let payload = """
            {
              "items": [
                {
                  "id": {
                    "kind": "youtube#video",
                    "videoId": "tAGnKpE4NCI"
                  },
                  "snippet": {
                    "title": "Approval Flow Validation",
                    "description": "Runs after explicit approval.",
                    "channelTitle": "OpenAI Codex"
                  }
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let queued = await store.runTool(
            .youtube,
            query: "creator approval validation",
            webPageCaptureService: WebPageCaptureService(),
            youTubeToolService: service,
            secretReader: { _ in "unused-before-approval" }
        )
        let approved = try #require(await store.resolveToolApproval(
            queued.id,
            approve: true,
            webPageCaptureService: WebPageCaptureService(),
            youTubeToolService: service,
            secretReader: { _ in "approved-youtube-key" }
        ))

        #expect(queued.status == .requiresApproval)
        #expect(queued.requiresApproval == true)
        #expect(queued.usedNetwork == true)
        #expect(approved.id == queued.id)
        #expect(approved.status == .completed)
        #expect(approved.requiresApproval == false)
        #expect(approved.usedNetwork == true)
        #expect(approved.output.contains("Approved locally and executed"))
        #expect(approved.output.contains("Approval Flow Validation"))
    }

    @MainActor
    @Test("X tool reports missing bearer token as unavailable without network")
    func xToolReportsMissingBearerTokenAsUnavailableWithoutNetwork() async throws {
        let (_, store) = try makeLoadedStore()
        let xIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .x }))
        store.toolConfigurations[xIndex].isEnabled = true
        store.toolConfigurations[xIndex].permissionPolicy = .alwaysAllow
        store.toolConfigurations[xIndex].secretReference = "flannel.test:x"
        store.toolConfigurations[xIndex].endpoint = XToolService.defaultEndpoint
        store.preferences.localOnlyMode = false
        let service = XToolService { _ in
            Issue.record("X should not use network transport when bearer token is unavailable.")
            return (Data(), nil)
        }

        let result = await store.runTool(
            .x,
            query: "@symbiex",
            webPageCaptureService: WebPageCaptureService(),
            xToolService: service,
            secretReader: { reference in
                #expect(reference.rawValue == "flannel.test:x")
                return ""
            }
        )

        #expect(result.status == .unavailable)
        #expect(result.usedNetwork == false)
    }

    @MainActor
    @Test("X search query hits recent tweets endpoint with expected query parameters and bearer auth")
    func xSearchQueryTargetsRecentTweetsEndpointWithQueryParameters() async throws {
        let (_, store) = try makeLoadedStore()
        let xIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .x }))
        store.toolConfigurations[xIndex].isEnabled = true
        store.toolConfigurations[xIndex].permissionPolicy = .alwaysAllow
        store.toolConfigurations[xIndex].secretReference = "flannel.test:x"
        store.toolConfigurations[xIndex].endpoint = XToolService.defaultEndpoint
        store.preferences.localOnlyMode = false
        let recorder = ToolRequestRecorder()
        let service = XToolService { request in
            await recorder.record(request)
            let payload = """
            {
              "data": [
                {
                  "id": "1849222021",
                  "text": "Network contract check for X query path",
                  "author_id": "u100"
                }
              ],
              "includes": {
                "users": [
                  {
                    "id": "u100",
                    "name": "Symbiex",
                    "username": "symbiex"
                  }
                ]
              }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let result = await store.runTool(
            .x,
            query: "local first ai workflow",
            webPageCaptureService: WebPageCaptureService(),
            xToolService: service,
            secretReader: { _ in "test-x-bearer" }
        )
        let request = try #require(await recorder.requests.first)
        let requestComponents = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))

        #expect(result.status == .completed)
        #expect(result.usedNetwork == true)
        #expect(requestComponents.path == "/2/tweets/search/recent")
        #expect(
            requestComponents.queryItems?.contains {
                $0.name == "query" && $0.value == "local first ai workflow"
            } == true
        )
        #expect(requestComponents.queryItems?.contains { $0.name == "max_results" } == true)
        #expect(requestComponents.queryItems?.contains { $0.name == "tweet.fields" } == true)
        #expect(requestComponents.queryItems?.contains { $0.name == "expansions" } == true)
        #expect(requestComponents.queryItems?.contains { $0.name == "user.fields" } == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-x-bearer")
        #expect(result.output.contains("local first ai workflow"))
    }

    @MainActor
    @Test("X post URL hits tweet detail endpoint with required query fields")
    func xPostURLTargetsTweetDetailEndpoint() async throws {
        let (_, store) = try makeLoadedStore()
        let xIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .x }))
        store.toolConfigurations[xIndex].isEnabled = true
        store.toolConfigurations[xIndex].permissionPolicy = .alwaysAllow
        store.toolConfigurations[xIndex].secretReference = "flannel.test:x"
        store.toolConfigurations[xIndex].endpoint = XToolService.defaultEndpoint
        store.preferences.localOnlyMode = false
        let recorder = ToolRequestRecorder()
        let service = XToolService { request in
            await recorder.record(request)
            let payload = """
            {
              "data": {
                "id": "1849222022",
                "text": "X post route contract test",
                "author_id": "u200"
              },
              "includes": {
                "users": [
                  {
                    "id": "u200",
                    "name": "Example User",
                    "username": "openai"
                  }
                ]
              }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let result = await store.runTool(
            .x,
            query: "https://x.com/openai/status/1849222022",
            webPageCaptureService: WebPageCaptureService(),
            xToolService: service,
            secretReader: { _ in "test-x-bearer" }
        )
        let request = try #require(await recorder.requests.first)
        let requestComponents = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))

        #expect(result.status == .completed)
        #expect(result.usedNetwork == true)
        #expect(requestComponents.path == "/2/tweets/1849222022")
        #expect(requestComponents.queryItems?.contains { $0.name == "tweet.fields" } == true)
        #expect(requestComponents.queryItems?.contains { $0.name == "expansions" } == true)
        #expect(requestComponents.queryItems?.contains { $0.name == "user.fields" } == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-x-bearer")
    }

    @MainActor
    @Test("X username input and profile URL route to users/by/username endpoint")
    func xUsernameAndProfileRouteToUsersByUsernameEndpoint() async throws {
        let cases: [(String, String)] = [
            ("@symbiex", "symbiex"),
            ("https://x.com/symbiex", "symbiex"),
        ]

        for (queryInput, username) in cases {
            let (_, store) = try makeLoadedStore()
            let xIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .x }))
            store.toolConfigurations[xIndex].isEnabled = true
            store.toolConfigurations[xIndex].permissionPolicy = .alwaysAllow
            store.toolConfigurations[xIndex].secretReference = "flannel.test:x"
            store.toolConfigurations[xIndex].endpoint = XToolService.defaultEndpoint
            store.preferences.localOnlyMode = false
            let recorder = ToolRequestRecorder()
            let service = XToolService { request in
                await recorder.record(request)
                let payload = """
                {
                  "data": {
                    "id": "u300",
                    "name": "Symbiex",
                    "username": "\(username)",
                    "description": "X contract sample account."
                  }
                }
                """
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
                return (Data(payload.utf8), response)
            }

            let result = await store.runTool(
                .x,
                query: queryInput,
                webPageCaptureService: WebPageCaptureService(),
                xToolService: service,
                secretReader: { _ in "test-x-bearer" }
            )
            let request = try #require(await recorder.requests.first)
            let requestComponents = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))

            #expect(result.status == .completed)
            #expect(result.usedNetwork == true)
            #expect(requestComponents.path == "/2/users/by/username/\(username)")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-x-bearer")
        }
    }

    @MainActor
    @Test("X tool queues on ask-every-time and executes after approval")
    func xToolExecutesAfterAskEveryTimeApproval() async throws {
        let (_, store) = try makeLoadedStore()
        let xIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .x }))
        store.toolConfigurations[xIndex].isEnabled = true
        store.toolConfigurations[xIndex].permissionPolicy = .askEveryTime
        store.toolConfigurations[xIndex].secretReference = "flannel.test:x"
        store.toolConfigurations[xIndex].endpoint = XToolService.defaultEndpoint
        store.preferences.localOnlyMode = false
        let service = XToolService { request in
            let payload = """
            {
              "data": [
                {
                  "id": "1849222023",
                  "text": "Executed after approval.",
                  "author_id": "u700"
                }
              ],
              "includes": {
                "users": [
                  {
                    "id": "u700",
                    "name": "Symbiex",
                    "username": "symbiex"
                  }
                ]
              }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(payload.utf8), response)
        }

        let queued = await store.runTool(
            .x,
            query: "local-first x post review",
            webPageCaptureService: WebPageCaptureService(),
            xToolService: service,
            secretReader: { _ in "unused-before-approval" }
        )
        let approved = try #require(await store.resolveToolApproval(
            queued.id,
            approve: true,
            webPageCaptureService: WebPageCaptureService(),
            xToolService: service,
            secretReader: { _ in "approved-x-bearer" }
        ))

        #expect(queued.status == .requiresApproval)
        #expect(queued.requiresApproval == true)
        #expect(queued.usedNetwork == true)
        #expect(approved.id == queued.id)
        #expect(approved.status == .completed)
        #expect(approved.requiresApproval == false)
        #expect(approved.usedNetwork == true)
        #expect(approved.output.contains("Approved locally and executed"))
        #expect(approved.output.contains("Executed after approval"))
    }

    @MainActor
    @Test("Browser automation opens an explicit URL through the injected launcher")
    func browserAutomationOpensURLWithInjectedLauncher() async throws {
        let (_, store) = try makeLoadedStore()
        let browserIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .browserAutomation }))
        store.toolConfigurations[browserIndex].isEnabled = true
        store.toolConfigurations[browserIndex].permissionPolicy = .alwaysAllow
        store.preferences.localOnlyMode = false
        let recorder = OpenedURLRecorder()
        let service = BrowserAutomationService { url in
            await recorder.open(url)
        }

        let result = await store.runTool(
            .browserAutomation,
            query: "open: https://example.com/flannel/docs",
            webPageCaptureService: WebPageCaptureService(),
            browserAutomationService: service
        )
        let openedURL = try #require(await recorder.urls.first)

        #expect(result.status == .completed)
        #expect(result.usedNetwork == true)
        #expect(result.modifiedFiles == false)
        #expect(result.output.contains("default browser"))
        #expect(result.output.contains("did not read page contents"))
        #expect(openedURL.absoluteString == "https://example.com/flannel/docs")
    }

    @MainActor
    @Test("Browser automation opens search queries with the privacy search endpoint")
    func browserAutomationSearchUsesPrivacyEndpoint() async throws {
        let (_, store) = try makeLoadedStore()
        let browserIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .browserAutomation }))
        store.toolConfigurations[browserIndex].isEnabled = true
        store.toolConfigurations[browserIndex].permissionPolicy = .alwaysAllow
        store.preferences.localOnlyMode = false
        let recorder = OpenedURLRecorder()
        let service = BrowserAutomationService { url in
            await recorder.open(url)
        }

        let result = await store.runTool(
            .browserAutomation,
            query: "search: local-first macOS AI chat",
            webPageCaptureService: WebPageCaptureService(),
            browserAutomationService: service
        )
        let openedURL = try #require(await recorder.urls.first)
        let components = try #require(URLComponents(url: openedURL, resolvingAgainstBaseURL: false))

        #expect(result.status == .completed)
        #expect(result.usedNetwork == true)
        #expect(components.scheme == "https")
        #expect(components.host == "duckduckgo.com")
        #expect(components.queryItems?.contains(URLQueryItem(name: "q", value: "local-first macOS AI chat")) == true)
        #expect(result.output.contains("web search"))
    }

    @MainActor
    @Test("Browser automation rejects unsafe URL schemes without opening the browser")
    func browserAutomationRejectsUnsafeURLWithoutOpening() async throws {
        let (_, store) = try makeLoadedStore()
        let browserIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .browserAutomation }))
        store.toolConfigurations[browserIndex].isEnabled = true
        store.toolConfigurations[browserIndex].permissionPolicy = .alwaysAllow
        store.preferences.localOnlyMode = false
        let recorder = OpenedURLRecorder()
        let service = BrowserAutomationService { url in
            await recorder.open(url)
        }

        let result = await store.runTool(
            .browserAutomation,
            query: "open: file:///Users/symbiex/.ssh/id_rsa",
            webPageCaptureService: WebPageCaptureService(),
            browserAutomationService: service
        )

        #expect(result.status == .blocked)
        #expect(result.usedNetwork == false)
        #expect(result.output.contains("only opens http and https URLs"))
        #expect(await recorder.urls.isEmpty)
    }

    @MainActor
    @Test("Browser automation queues on ask-every-time and opens after approval")
    func browserAutomationExecutesAfterAskEveryTimeApproval() async throws {
        let (_, store) = try makeLoadedStore()
        let browserIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .browserAutomation }))
        store.toolConfigurations[browserIndex].isEnabled = true
        store.toolConfigurations[browserIndex].permissionPolicy = .askEveryTime
        store.preferences.localOnlyMode = false
        let recorder = OpenedURLRecorder()
        let service = BrowserAutomationService { url in
            await recorder.open(url)
        }

        let queued = await store.runTool(
            .browserAutomation,
            query: "https://example.com/approved-browser",
            webPageCaptureService: WebPageCaptureService(),
            browserAutomationService: service
        )
        #expect(await recorder.urls.isEmpty)

        let approved = try #require(await store.resolveToolApproval(
            queued.id,
            approve: true,
            webPageCaptureService: WebPageCaptureService(),
            browserAutomationService: service
        ))
        let openedURL = try #require(await recorder.urls.first)

        #expect(queued.status == .requiresApproval)
        #expect(queued.requiresApproval == true)
        #expect(queued.usedNetwork == true)
        #expect(approved.id == queued.id)
        #expect(approved.status == .completed)
        #expect(approved.requiresApproval == false)
        #expect(approved.usedNetwork == true)
        #expect(approved.output.contains("Approved locally and executed"))
        #expect(openedURL.absoluteString == "https://example.com/approved-browser")
    }

    @MainActor
    @Test("Ask-every-time policy returns approval result")
    func askEveryTimePolicyCreatesApprovalResult() throws {
        let (_, store) = try makeLoadedStore()
        let initialToolResultCount = store.toolExecutionResults.count
        let fileReadIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .localFileRead }))
        store.toolConfigurations[fileReadIndex].isEnabled = true
        store.toolConfigurations[fileReadIndex].permissionPolicy = .askEveryTime
        store.preferences.localOnlyMode = false

        let result = store.runTool(.localFileRead, query: "README.md")

        #expect(result.status == .requiresApproval)
        #expect(result.requiresApproval == true)
        #expect(result.output.contains("requires explicit approval"))
        #expect(store.toolExecutionResults.count == initialToolResultCount + 1)
        #expect(store.toolExecutionResults.contains { $0.toolKind == .localFileRead && $0.status == .requiresApproval })
    }

    @MainActor
    @Test("Denied chat terminal approval refreshes assistant tool result")
    func deniedChatTerminalApprovalRefreshesAssistantToolResult() throws {
        let (_, store) = try makeLoadedStore()
        let terminalIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .terminal }))
        store.toolConfigurations[terminalIndex].isEnabled = true
        store.toolConfigurations[terminalIndex].permissionPolicy = .askEveryTime
        let command = try #require(store.parseChatToolCommand("/tool terminal printf FLANNEL_SHOULD_NOT_RUN"))

        let queued = store.runChatToolCommand(command)
        let messageID = store.appendToolResultMessage(queued)
        let queuedMessage = try #require(store.currentAssistantThread?.messages.first(where: { $0.id == messageID }))
        let queuedAttachment = try #require(queuedMessage.attachments.first(where: { $0.kind == .toolResult }))

        #expect(queued.status == .requiresApproval)
        #expect(queued.requiresApproval)
        #expect(queued.query == "printf FLANNEL_SHOULD_NOT_RUN")
        #expect(queued.output.contains("requires explicit approval"))
        #expect(queuedMessage.referencedEntityIDs.contains(queued.id))
        #expect(queuedMessage.text.contains("Approval required before this tool can run."))
        #expect(queuedAttachment.kind == .toolResult)
        #expect(queuedAttachment.excerpt?.contains("requires explicit approval") == true)

        let denied = try #require(store.resolveToolApproval(queued.id, approve: false))
        store.refreshAssistantMessages(forToolResult: denied)
        let refreshedMessage = try #require(store.currentAssistantThread?.messages.first(where: { $0.id == messageID }))
        let refreshedAttachment = try #require(refreshedMessage.attachments.first(where: { $0.kind == .toolResult }))

        #expect(denied.id == queued.id)
        #expect(denied.status == .denied)
        #expect(denied.requiresApproval == false)
        #expect(refreshedMessage.referencedEntityIDs.contains(denied.id))
        #expect(refreshedMessage.text.contains("Status: Denied locally. No tool action was run."))
        #expect(refreshedMessage.text.contains("Approval required before this tool can run.") == false)
        #expect(refreshedAttachment.kind == .toolResult)
        #expect(refreshedAttachment.title == denied.title)
        #expect(refreshedAttachment.excerpt?.contains("Denied locally") == true)
    }

    @MainActor
    @Test("Tool approvals resolve pending runs and rerun local approved tools")
    func toolApprovalsResolvePendingRuns() throws {
        let (_, store) = try makeLoadedStore()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-approved-tool-\(UUID().uuidString).txt")
            .standardizedFileURL
        try "Approved local file read content".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileReadIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .localFileRead }))
        store.toolConfigurations[fileReadIndex].isEnabled = true
        store.toolConfigurations[fileReadIndex].permissionPolicy = .askEveryTime

        let queuedRead = store.runTool(.localFileRead, query: fileURL.path)
        let approvedRead = try #require(store.resolveToolApproval(queuedRead.id, approve: true))

        #expect(approvedRead.id == queuedRead.id)
        #expect(approvedRead.status == .completed)
        #expect(approvedRead.requiresApproval == false)
        #expect(approvedRead.output.contains("Approved locally and executed"))
        #expect(approvedRead.output.contains("Approved local file read content"))

        let queuedDeny = store.runTool(.localFileRead, query: "deny fixture")
        let deniedRead = try #require(store.resolveToolApproval(queuedDeny.id, approve: false))

        #expect(deniedRead.id == queuedDeny.id)
        #expect(deniedRead.status == .denied)
        #expect(deniedRead.requiresApproval == false)
        #expect(deniedRead.output.contains("Denied locally"))
    }

    @MainActor
    @Test("Approved local file write changes the requested file")
    func approvedLocalFileWriteChangesRequestedFile() throws {
        let (_, store) = try makeLoadedStore()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-approved-write-\(UUID().uuidString).md")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileWriteIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .localFileWrite }))
        store.toolConfigurations[fileWriteIndex].isEnabled = true
        store.toolConfigurations[fileWriteIndex].permissionPolicy = .askEveryTime

        let writeContent = "Approved local file write content"
        let queuedWrite = store.runTool(.localFileWrite, query: "\(fileURL.path)\n---\n\(writeContent)")
        let approvedWrite = try #require(store.resolveToolApproval(queuedWrite.id, approve: true))

        #expect(queuedWrite.status == .requiresApproval)
        #expect(approvedWrite.id == queuedWrite.id)
        #expect(approvedWrite.status == .completed)
        #expect(approvedWrite.requiresApproval == false)
        #expect(approvedWrite.modifiedFiles == true)
        #expect(approvedWrite.output.contains("Approved locally and executed"))
        #expect(approvedWrite.output.contains("Wrote"))
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == writeContent)
    }

    @MainActor
    @Test("Local file write rejects missing content without changing files")
    func localFileWriteRejectsMissingContentWithoutChangingFiles() throws {
        let (_, store) = try makeLoadedStore()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-empty-write-\(UUID().uuidString).md")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileWriteIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .localFileWrite }))
        store.toolConfigurations[fileWriteIndex].isEnabled = true
        store.toolConfigurations[fileWriteIndex].permissionPolicy = .alwaysAllow

        let result = store.runTool(.localFileWrite, query: fileURL.path)

        #expect(result.status == .blocked)
        #expect(result.modifiedFiles == false)
        #expect(result.output.contains("requires content"))
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @MainActor
    @Test("Approved terminal command executes locally and records output")
    func approvedTerminalCommandExecutesLocallyAndRecordsOutput() throws {
        let (_, store) = try makeLoadedStore()
        let terminalIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .terminal }))
        store.toolConfigurations[terminalIndex].isEnabled = true
        store.toolConfigurations[terminalIndex].permissionPolicy = .askEveryTime

        let queuedCommand = store.runTool(.terminal, query: "printf FLANNEL_TERMINAL_OK")
        let approvedCommand = try #require(store.resolveToolApproval(queuedCommand.id, approve: true))

        #expect(queuedCommand.status == .requiresApproval)
        #expect(approvedCommand.id == queuedCommand.id)
        #expect(approvedCommand.status == .completed)
        #expect(approvedCommand.requiresApproval == false)
        #expect(approvedCommand.output.contains("Approved locally and executed"))
        #expect(approvedCommand.output.contains("Exit code: 0"))
        #expect(approvedCommand.output.contains("FLANNEL_TERMINAL_OK"))
    }

    @MainActor
    @Test("Approved code execution runs local script snippets")
    func approvedCodeExecutionRunsLocalScriptSnippets() throws {
        let (_, store) = try makeLoadedStore()
        let codeIndex = try #require(store.toolConfigurations.firstIndex(where: { $0.kind == .codeExecution }))
        store.toolConfigurations[codeIndex].isEnabled = true
        store.toolConfigurations[codeIndex].permissionPolicy = .askEveryTime

        let queuedRun = store.runTool(.codeExecution, query: "zsh\nprintf FLANNEL_CODE_OK")
        let approvedRun = try #require(store.resolveToolApproval(queuedRun.id, approve: true))

        #expect(queuedRun.status == .requiresApproval)
        #expect(approvedRun.id == queuedRun.id)
        #expect(approvedRun.status == .completed)
        #expect(approvedRun.requiresApproval == false)
        #expect(approvedRun.output.contains("Approved locally and executed"))
        #expect(approvedRun.output.contains("Code execution (zsh)"))
        #expect(approvedRun.output.contains("FLANNEL_CODE_OK"))
    }

    @MainActor
    @Test("Provider setup validation normalizes endpoint and records blocking diagnostics")
    func providerSetupValidationNormalizesEndpoint() throws {
        let (_, store) = try makeLoadedStore()
        let provider = ProviderConfiguration(
            kind: .openAI,
            displayName: "OpenAI",
            endpoint: " https://api.openai.com/v1 ",
            modelIdentifier: "gpt-4.1",
            secretReference: nil,
            isEnabled: true
        )
        store.providerConfigurations = [provider]
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true

        let report = try #require(store.validateProviderSetup(provider.id))
        let updated = try #require(store.providerConfigurations.first)

        #expect(report.normalizedEndpoint == "https://api.openai.com/v1")
        #expect(report.diagnostics.contains { $0.code == .missingKeychainReference })
        #expect(updated.endpoint == "https://api.openai.com/v1")
        #expect(updated.connectionStatus == .needsAttention)
        #expect(updated.lastErrorMessage?.contains("API key") == true)
        #expect(updated.lastValidatedAt != nil)
    }

    @MainActor
    @Test("Local provider setup validation can mark ready without API key")
    func localProviderSetupValidationMarksReady() throws {
        let (_, store) = try makeLoadedStore()
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: " http://localhost:1234 ",
            modelIdentifier: "local-model",
            isEnabled: true
        )
        store.providerConfigurations = [provider]
        store.preferences.localOnlyMode = true
        store.preferences.allowCloudProviders = false

        let report = try #require(store.validateProviderSetup(provider.id))
        let updated = try #require(store.providerConfigurations.first)

        #expect(report.hasBlockingIssues == false)
        #expect(updated.endpoint == "http://localhost:1234")
        #expect(updated.connectionStatus == .ready)
        #expect(updated.lastErrorMessage == nil)
        #expect(updated.lastValidatedAt != nil)
    }

    @MainActor
    @Test("Provider readiness validation updates status and merges discovered models")
    func providerReadinessValidationUpdatesStatusAndModels() throws {
        let (_, store) = try makeLoadedStore()
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: " http://localhost:1234 ",
            modelIdentifier: "local-model",
            connectionStatus: .disconnected,
            lastErrorMessage: "Needs validation",
            availableModels: ["manual-model"]
        )
        store.providerConfigurations = [provider]

        let report = ProviderSetupService.shared.report(for: provider, preferences: store.preferences)
        let checkedAt = Date(timeIntervalSince1970: 1_800)
        let validation = ProviderReadinessValidation(
            report: report,
            connectionStatus: .ready,
            availableModels: ["local-model", "vision-model"],
            selectedModelIdentifier: "local-model",
            selectedModelIsAvailable: true,
            checkedAt: checkedAt,
            errorMessage: nil
        )

        let updated = try #require(store.applyProviderReadinessValidation(validation, providerID: provider.id))

        #expect(updated.endpoint == "http://localhost:1234")
        #expect(updated.modelIdentifier == "local-model")
        #expect(updated.connectionStatus == .ready)
        #expect(updated.lastErrorMessage == nil)
        #expect(updated.lastValidatedAt == checkedAt)
        #expect(updated.availableModels == ["local-model", "manual-model", "vision-model"])
    }

    @MainActor
    @Test("Failed provider readiness validation preserves known models")
    func failedProviderReadinessValidationPreservesKnownModels() throws {
        let (_, store) = try makeLoadedStore()
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "local-model",
            connectionStatus: .ready,
            availableModels: ["manual-model"]
        )
        store.providerConfigurations = [provider]

        let report = ProviderSetupService.shared.report(for: provider, preferences: store.preferences)
        let checkedAt = Date(timeIntervalSince1970: 1_900)
        let validation = ProviderReadinessValidation(
            report: report,
            connectionStatus: .needsAttention,
            availableModels: [],
            selectedModelIdentifier: "local-model",
            selectedModelIsAvailable: false,
            checkedAt: checkedAt,
            errorMessage: "Provider did not respond."
        )

        let updated = try #require(store.applyProviderReadinessValidation(validation, providerID: provider.id))

        #expect(updated.connectionStatus == .needsAttention)
        #expect(updated.lastErrorMessage == "Provider did not respond.")
        #expect(updated.lastValidatedAt == checkedAt)
        #expect(updated.availableModels == ["manual-model"])
    }

    @MainActor
    @Test("Provider readiness batch applies multiple results and summarizes status")
    func providerReadinessBatchAppliesResultsAndSummarizesStatus() throws {
        let (_, store) = try makeLoadedStore()
        let readyProvider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: " http://localhost:1234 ",
            modelIdentifier: "local-model",
            connectionStatus: .disconnected,
            availableModels: ["manual-model"]
        )
        let blockedProvider = ProviderConfiguration(
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "OpenAI API",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-5.5",
            connectionStatus: .ready
        )
        store.providerConfigurations = [readyProvider, blockedProvider]

        let readyReport = ProviderSetupService.shared.report(for: readyProvider, preferences: store.preferences)
        let blockedReport = ProviderSetupService.shared.report(for: blockedProvider, preferences: store.preferences)
        let checkedAt = Date(timeIntervalSince1970: 2_000)
        let summary = store.applyProviderReadinessValidations([
            (
                providerID: readyProvider.id,
                validation: ProviderReadinessValidation(
                    report: readyReport,
                    connectionStatus: .ready,
                    availableModels: ["local-model", "vision-model"],
                    selectedModelIdentifier: "local-model",
                    selectedModelIsAvailable: true,
                    checkedAt: checkedAt,
                    errorMessage: nil
                )
            ),
            (
                providerID: blockedProvider.id,
                validation: ProviderReadinessValidation(
                    report: blockedReport,
                    connectionStatus: .needsAttention,
                    availableModels: [],
                    selectedModelIdentifier: "gpt-5.5",
                    selectedModelIsAvailable: false,
                    checkedAt: checkedAt,
                    errorMessage: "API key missing."
                )
            ),
            (
                providerID: UUID(),
                validation: ProviderReadinessValidation(
                    report: readyReport,
                    connectionStatus: .ready,
                    availableModels: ["ignored"],
                    selectedModelIdentifier: "ignored",
                    selectedModelIsAvailable: true,
                    checkedAt: checkedAt,
                    errorMessage: nil
                )
            )
        ])

        let updatedReady = try #require(store.providerConfigurations.first { $0.id == readyProvider.id })
        let updatedBlocked = try #require(store.providerConfigurations.first { $0.id == blockedProvider.id })

        #expect(summary.checkedCount == 2)
        #expect(summary.readyCount == 1)
        #expect(summary.needsAttentionCount == 1)
        #expect(summary.message == "Checked 2 routes. 1 ready; 1 need attention.")
        #expect(updatedReady.endpoint == "http://localhost:1234")
        #expect(updatedReady.availableModels == ["local-model", "manual-model", "vision-model"])
        #expect(updatedReady.connectionStatus == .ready)
        #expect(updatedBlocked.connectionStatus == .needsAttention)
        #expect(updatedBlocked.lastErrorMessage == "API key missing.")
        #expect(updatedBlocked.lastValidatedAt == checkedAt)
    }

    @MainActor
    @Test("Local discovery propagates vision model capability into provider routing")
    func localDiscoveryPropagatesVisionProviderCapability() throws {
        let (_, store) = try makeLoadedStore()
        let endpoint = "http://localhost:11434"
        store.providerConfigurations = [
            ProviderConfiguration(
                kind: .ollama,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "Ollama",
                endpoint: endpoint,
                modelIdentifier: "llava",
                supportsVision: false
            )
        ]

        store.apply([
            LocalProviderDiscoveryResult(
                providerKind: .ollama,
                endpoint: endpoint,
                status: .ready,
                models: [
                    LocalModelDescriptor(
                        name: "llava",
                        providerKind: .ollama,
                        endpoint: endpoint,
                        capabilities: [.chat, .streaming, .vision]
                    )
                ]
            )
        ])

        let provider = try #require(store.providerConfigurations.first)
        #expect(provider.supportsVision)
        #expect(provider.capabilities.contains(.vision))
    }

    @MainActor
    @Test("Failed local discovery marks configured route as needing attention")
    func localDiscoveryFailureMarksConfiguredRouteAsNeedsAttention() throws {
        let (_, store) = try makeLoadedStore()
        let endpoint = "http://localhost:11434"
        let checkedAt = Date(timeIntervalSince1970: 1_806_000_000)
        store.providerConfigurations = [
            ProviderConfiguration(
                kind: .ollama,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "Ollama",
                endpoint: endpoint,
                modelIdentifier: "llama3.1",
                isEnabled: true,
                lastValidatedAt: Date(timeIntervalSince1970: 1_805_000_000),
                connectionStatus: .ready,
                lastErrorMessage: nil,
                availableModels: ["llama3.1"],
                discoveredModelNames: ["llama3.1"],
                capabilities: [.chat, .streaming],
                supportsStreaming: true
            )
        ]

        store.apply([
            LocalProviderDiscoveryResult(
                providerKind: .ollama,
                endpoint: endpoint,
                status: .needsAttention,
                errorMessage: "Connection refused.",
                discoveredAt: checkedAt
            )
        ])

        let provider = try #require(store.providerConfigurations.first)
        #expect(provider.connectionStatus == .needsAttention)
        #expect(provider.lastErrorMessage == "Connection refused.")
        #expect(provider.lastValidatedAt == checkedAt)
        #expect(provider.modelIdentifier == "llama3.1")
        #expect(provider.availableModels == ["llama3.1"])
    }

    @MainActor
    @Test("Local discovery merges model lists without dropping manual entries")
    func localDiscoveryMergesModelListsWithoutDroppingManualEntries() throws {
        let (_, store) = try makeLoadedStore()
        let endpoint = "http://localhost:11434"
        store.providerConfigurations = [
            ProviderConfiguration(
                kind: .ollama,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "Ollama",
                endpoint: endpoint,
                modelIdentifier: "llama2",
                availableModels: ["gpt-manual", "llama2"]
            )
        ]

        store.apply([
            LocalProviderDiscoveryResult(
                providerKind: .ollama,
                endpoint: endpoint,
                status: .ready,
                models: [
                    LocalModelDescriptor(name: "qwen2.5", providerKind: .ollama, endpoint: endpoint),
                    LocalModelDescriptor(name: "llama2", providerKind: .ollama, endpoint: endpoint)
                ]
            )
        ])

        let provider = try #require(store.providerConfigurations.first)
        #expect(Set(provider.availableModels) == Set(["gpt-manual", "llama2", "qwen2.5"]))
        #expect(provider.availableModels.count == 3)
        #expect(provider.discoveredModelNames == ["llama2", "qwen2.5"])
        #expect(provider.staleDiscoveredModelNames.isEmpty)
        #expect(provider.modelIdentifier == "llama2")
    }

    @MainActor
    @Test("Local discovery prunes stale discovered models while preserving manual entries")
    func localDiscoveryPrunesStaleDiscoveredModelsWhilePreservingManualEntries() throws {
        let (_, store) = try makeLoadedStore()
        let endpoint = "http://localhost:11434"
        store.providerConfigurations = [
            ProviderConfiguration(
                kind: .ollama,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "Ollama",
                endpoint: endpoint,
                modelIdentifier: "old-local",
                availableModels: ["manual-model", "old-local"],
                discoveredModelNames: ["old-local"]
            )
        ]

        store.apply([
            LocalProviderDiscoveryResult(
                providerKind: .ollama,
                endpoint: endpoint,
                status: .ready,
                models: [
                    LocalModelDescriptor(name: "new-local", providerKind: .ollama, endpoint: endpoint)
                ]
            )
        ])

        let provider = try #require(store.providerConfigurations.first)
        #expect(Set(provider.availableModels) == Set(["manual-model", "new-local"]))
        #expect(provider.discoveredModelNames == ["new-local"])
        #expect(provider.staleDiscoveredModelNames == ["old-local"])
        #expect(provider.modelIdentifier == "new-local")
    }

    @MainActor
    @Test("Local discovery backfills model identifier only when empty")
    func localDiscoveryBackfillsModelIdentifierOnlyWhenEmpty() throws {
        let (_, store) = try makeLoadedStore()
        let endpoint = "http://localhost:1234"
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: endpoint,
            modelIdentifier: "",
            availableModels: []
        )
        store.providerConfigurations = [provider]

        let firstDiscovery = LocalProviderDiscoveryResult(
            providerKind: .lmStudio,
            endpoint: endpoint,
            status: .ready,
            models: [
                LocalModelDescriptor(name: "local-alpha", providerKind: .lmStudio, endpoint: endpoint),
                LocalModelDescriptor(name: "local-beta", providerKind: .lmStudio, endpoint: endpoint)
            ]
        )
        store.apply([firstDiscovery])
        #expect(store.providerConfigurations.first?.modelIdentifier == "local-alpha")

        store.providerConfigurations[0].modelIdentifier = "manual-choice"
        store.apply([firstDiscovery])
        #expect(store.providerConfigurations.first?.modelIdentifier == "manual-choice")
    }

    @MainActor
    @Test("Local discovery backfills context window only when empty")
    func localDiscoveryBackfillsContextWindowOnlyWhenEmpty() throws {
        let (_, store) = try makeLoadedStore()
        let endpoint = "http://localhost:1234"
        store.providerConfigurations = [
            ProviderConfiguration(
                kind: .lmStudio,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "LM Studio",
                endpoint: endpoint,
                modelIdentifier: "local-alpha",
                contextWindowTokens: nil
            )
        ]

        store.apply([
            LocalProviderDiscoveryResult(
                providerKind: .lmStudio,
                endpoint: endpoint,
                status: .ready,
                models: [
                    LocalModelDescriptor(
                        name: "local-alpha",
                        providerKind: .lmStudio,
                        endpoint: endpoint,
                        contextWindowTokens: 8192
                    )
                ]
            )
        ])
        #expect(store.providerConfigurations.first?.contextWindowTokens == 8192)

        store.providerConfigurations[0].contextWindowTokens = 4096
        store.apply([
            LocalProviderDiscoveryResult(
                providerKind: .lmStudio,
                endpoint: endpoint,
                status: .ready,
                models: [
                    LocalModelDescriptor(
                        name: "local-alpha",
                        providerKind: .lmStudio,
                        endpoint: endpoint,
                        contextWindowTokens: 131_072
                    )
                ]
            )
        ])
        #expect(store.providerConfigurations.first?.contextWindowTokens == 4096)
    }

    @MainActor
    @Test("Embedding-only local discovery does not become runnable for chat")
    func embeddingOnlyLocalDiscoveryDoesNotBecomeRunnableForChat() throws {
        let (_, store) = try makeLoadedStore()
        let endpoint = "http://localhost:1234"
        store.providerConfigurations = []

        store.apply([
            LocalProviderDiscoveryResult(
                providerKind: .lmStudio,
                endpoint: endpoint,
                status: .ready,
                models: [
                    LocalModelDescriptor(
                        name: "text-embedding-nomic-embed-text-v1.5",
                        displayName: "Nomic Embed Text v1.5",
                        providerKind: .lmStudio,
                        endpoint: endpoint,
                        contextWindowTokens: 2048,
                        capabilities: [.embeddings]
                    )
                ]
            )
        ])

        let provider = try #require(store.providerConfigurations.first)
        #expect(provider.availableModels == ["text-embedding-nomic-embed-text-v1.5"])
        #expect(provider.supportsEmbeddings)
        #expect(!provider.supportsStreaming)
        #expect(provider.capabilities == [.embeddings])
        #expect(store.isProviderRunnableForChat(provider) == false)
    }

    @MainActor
    @Test("Local discovery propagates tool embedding and reasoning capabilities additively")
    func localDiscoveryPropagatesCapabilitiesAdditively() throws {
        let (_, store) = try makeLoadedStore()
        let endpoint = "http://localhost:1234"
        store.providerConfigurations = [
            ProviderConfiguration(
                kind: .lmStudio,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "LM Studio",
                endpoint: endpoint,
                modelIdentifier: "local-reasoner",
                capabilities: [.chat, .streaming],
                supportsToolCalling: false,
                supportsEmbeddings: false
            )
        ]

        store.apply([
            LocalProviderDiscoveryResult(
                providerKind: .lmStudio,
                endpoint: endpoint,
                status: .ready,
                models: [
                    LocalModelDescriptor(
                        name: "local-reasoner",
                        providerKind: .lmStudio,
                        endpoint: endpoint,
                        capabilities: [.chat, .streaming, .toolCalling, .embeddings, .reasoning]
                    )
                ]
            )
        ])

        let provider = try #require(store.providerConfigurations.first)
        #expect(provider.capabilities.contains(.chat))
        #expect(provider.capabilities.contains(.toolCalling))
        #expect(provider.capabilities.contains(.embeddings))
        #expect(provider.capabilities.contains(.reasoning))
        #expect(provider.supportsToolCalling)
        #expect(provider.supportsEmbeddings)
    }

    @MainActor
    @Test("Selecting discovered local chat model makes it the preferred route")
    func selectingDiscoveredLocalChatModelMakesItPreferred() throws {
        let (_, store) = try makeLoadedStore()
        let endpoint = "http://localhost:11434"
        store.providerConfigurations = [
            ProviderConfiguration(
                kind: .ollama,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "Ollama",
                endpoint: endpoint,
                modelIdentifier: "llama3.1",
                availableModels: ["llama3.1"],
                capabilities: [.chat, .streaming],
                supportsToolCalling: false,
                supportsVision: false,
                contextWindowTokens: nil
            )
        ]

        let providerID = store.selectDiscoveredLocalModelForChat(
            LocalModelDescriptor(
                name: "qwen3:14b",
                displayName: "Qwen 3 14B",
                providerKind: .ollama,
                endpoint: endpoint,
                contextWindowTokens: 65_536,
                capabilities: [.chat, .streaming, .toolCalling, .vision, .reasoning]
            )
        )

        let selectedID = try #require(providerID)
        let provider = try #require(store.providerConfigurations.first(where: { $0.id == selectedID }))

        #expect(provider.modelIdentifier == "qwen3:14b")
        #expect(provider.availableModels == ["llama3.1", "qwen3:14b"])
        #expect(provider.discoveredModelNames == ["qwen3:14b"])
        #expect(provider.staleDiscoveredModelNames.isEmpty)
        #expect(provider.isEnabled)
        #expect(provider.isLocalPreferred)
        #expect(provider.connectionStatus == .ready)
        #expect(provider.contextWindowTokens == 65_536)
        #expect(provider.supportsToolCalling)
        #expect(provider.supportsVision)
        #expect(provider.capabilities.contains(.reasoning))
        #expect(store.preferences.preferredProviderID == selectedID)
        #expect(store.preferences.providerRoutingPolicy == .selectedProvider)
        #expect(store.activeProvider?.id == selectedID)
    }

    @MainActor
    @Test("Selecting discovered embedding model does not create chat route")
    func selectingDiscoveredEmbeddingModelDoesNotCreateChatRoute() throws {
        let (_, store) = try makeLoadedStore()
        let originalPreferredProviderID = store.preferences.preferredProviderID
        let originalActiveProviderID = store.activeProvider?.id
        store.providerConfigurations = []

        let providerID = store.selectDiscoveredLocalModelForChat(
            LocalModelDescriptor(
                name: "nomic-embed-text",
                providerKind: .ollama,
                endpoint: "http://localhost:11434",
                capabilities: [.embeddings]
            )
        )

        #expect(providerID == nil)
        #expect(store.providerConfigurations.isEmpty)
        #expect(store.preferences.preferredProviderID == originalPreferredProviderID)
        #expect(store.activeProvider == nil)
        #expect(store.activeProvider?.id != originalActiveProviderID)
    }

    @MainActor
    @Test("Selecting preferred provider preserves explicit privacy preferences")
    func selectingPreferredProviderPreservesExplicitPrivacyPreferences() throws {
        let (_, store) = try makeLoadedStore()
        let cloud = ProviderConfiguration(
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "OpenAI",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-5.5",
            secretReference: ProviderSetupService.shared.canonicalSecretReferenceString(for: ProviderConfiguration(
                kind: .openAI,
                accessMode: .apiKey,
                privacyScope: .externalAPI,
                displayName: "OpenAI",
                endpoint: "https://api.openai.com/v1",
                modelIdentifier: "gpt-5.5"
            )),
            isEnabled: false
        )
        let cli = ProviderConfiguration(
            kind: .claudeCodeCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "Claude Code CLI",
            endpoint: "claude -p",
            modelIdentifier: "claude-subscription",
            isEnabled: false
        )
        store.providerConfigurations = [cloud, cli]
        store.preferences.localOnlyMode = true
        store.preferences.allowCloudProviders = false

        let cloudIsRunnable = store.selectPreferredProviderForChat(cloud.id)
        #expect(store.preferences.preferredProviderID == cloud.id)
        #expect(store.preferences.localOnlyMode == true)
        #expect(store.preferences.allowCloudProviders == false)
        #expect(store.providerConfigurations.first?.isEnabled == true)
        #expect(cloudIsRunnable == false)

        store.preferences.localOnlyMode = true
        store.preferences.allowCloudProviders = false
        let cliIsRunnable = store.selectPreferredProviderForChat(cli.id)
        #expect(store.preferences.preferredProviderID == cli.id)
        #expect(store.preferences.localOnlyMode == true)
        #expect(store.preferences.allowCloudProviders == false)
        #expect(store.providerConfigurations.last?.isEnabled == true)
        #expect(cliIsRunnable == false)

        store.preferences.localOnlyMode = false
        _ = store.selectPreferredProviderForChat(cli.id)
        #expect(store.preferences.localOnlyMode == false)
        #expect(store.preferences.allowCloudProviders == false)
    }

    @MainActor
    @Test("Knowledge source onboarding queues user-provided folder source")
    func knowledgeSourceOnboardingQueuesUserProvidedFolder() throws {
        let (_, store) = try makeLoadedStore()
        let originalSourceCount = store.knowledgeSources.count
        let tempFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-knowledge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        let source = try #require(store.addKnowledgeSource(
            title: "Local research",
            kind: .folder,
            location: tempFolder.path,
            watched: true
        ))

        #expect(store.knowledgeSources.count == originalSourceCount + 1)
        #expect(source.title == "Local research")
        #expect(source.kind == .folder)
        #expect(source.location == tempFolder.path)
        #expect(source.status == .queued)
        #expect(source.isWatched == true)
        #expect(source.embeddingModelIdentifier == LocalEmbeddingService.deterministicModelIdentifier)
    }

    @MainActor
    @Test("Watched file-system source events queue only eligible local roots")
    func watchedFileSystemSourceEventsQueueOnlyEligibleLocalRoots() throws {
        let (_, store) = try makeLoadedStore()
        let folderSource = KnowledgeSource(
            title: "Watched folder",
            kind: .folder,
            location: "/tmp/flannel-watched",
            status: .ready,
            isWatched: true,
            documentCount: 1
        )
        let manualFolderSource = KnowledgeSource(
            title: "Manual folder",
            kind: .folder,
            location: "/tmp/flannel-manual",
            status: .ready,
            isWatched: false,
            documentCount: 1
        )
        let watchedWebSource = KnowledgeSource(
            title: "Watched page",
            kind: .webPage,
            location: "https://example.com",
            status: .ready,
            isWatched: true,
            documentCount: 1
        )

        store.knowledgeSources = [folderSource, manualFolderSource, watchedWebSource]

        let queuedIDs = store.queueWatchedKnowledgeSources([
            folderSource.id,
            manualFolderSource.id,
            watchedWebSource.id
        ])

        #expect(queuedIDs == [folderSource.id])
        #expect(store.knowledgeSources.first(where: { $0.id == folderSource.id })?.status == .queued)
        #expect(store.knowledgeSources.first(where: { $0.id == folderSource.id })?.lastErrorMessage == nil)
        #expect(store.knowledgeSources.first(where: { $0.id == manualFolderSource.id })?.status == .ready)
        #expect(store.knowledgeSources.first(where: { $0.id == watchedWebSource.id })?.status == .ready)
    }

    @MainActor
    @Test("Watched web page knowledge sources queue refresh by capture or index age")
    func watchedWebPageKnowledgeSourcesQueueRefreshByCaptureOrIndexAge() throws {
        let (_, store) = try makeLoadedStore()
        let now = Date(timeIntervalSince1970: 1_788_200_000)
        let oldCaptureDate = now.addingTimeInterval(-172_800)
        let oldIndexDate = now.addingTimeInterval(-259_200)
        let freshCaptureDate = now.addingTimeInterval(-900)
        let url = "https://example.com/docs/stale-page"
        let indexURL = "https://example.com/docs/stale-index"
        let source = KnowledgeSource(
            title: "Stale reference",
            kind: .webPage,
            location: url,
            status: .ready,
            chunkCount: 4,
            lastIndexedAt: freshCaptureDate,
            isWatched: true,
            documentCount: 1,
            embeddingRecordCount: 4,
            lastErrorMessage: "Previous transient warning"
        )
        let indexStaleSource = KnowledgeSource(
            title: "Stale index reference",
            kind: .webPage,
            location: indexURL,
            status: .ready,
            chunkCount: 3,
            lastIndexedAt: oldIndexDate,
            isWatched: true,
            documentCount: 1,
            embeddingRecordCount: 3,
            lastErrorMessage: "Previous index warning"
        )
        let asset = LibraryAsset(
            title: "Stale reference",
            kind: .link,
            sourceURL: URL(string: url)!,
            sourceIdentifier: url,
            summary: "Captured docs page.",
            summaryStatus: .ready,
            updatedAt: oldCaptureDate,
            capturedAt: oldCaptureDate,
            transcript: TranscriptRecord(
                status: .available,
                text: "Old but usable page body text for local RAG.",
                sourceLabel: "Web page capture",
                importedAt: oldCaptureDate,
                updatedAt: oldCaptureDate
            ),
            notes: "Original capture notes."
        )
        let indexFreshAsset = webPageAsset(
            title: indexStaleSource.title,
            url: indexURL,
            capturedAt: freshCaptureDate,
            text: "Fresh page body with an old local RAG index."
        )
        store.knowledgeSources = [source, indexStaleSource]
        store.libraryAssets = [asset, indexFreshAsset]

        let queuedIDs = store.queueStaleWatchedWebPageKnowledgeSources(now: now)

        let rebuiltSource = try #require(store.knowledgeSources.first(where: { $0.id == source.id }))
        let rebuiltIndexSource = try #require(store.knowledgeSources.first(where: { $0.id == indexStaleSource.id }))
        let rebuiltAsset = try #require(store.libraryAssets.first(where: { $0.sourceIdentifier == url }))
        let rebuiltIndexAsset = try #require(store.libraryAssets.first(where: { $0.sourceIdentifier == indexURL }))
        #expect(queuedIDs == [indexStaleSource.id, source.id])
        #expect(rebuiltSource.status == .queued)
        #expect(rebuiltSource.lastErrorMessage == nil)
        #expect(rebuiltSource.documentCount == 1)
        #expect(rebuiltSource.chunkCount == 4)
        #expect(rebuiltSource.embeddingRecordCount == 4)
        #expect(rebuiltIndexSource.status == .queued)
        #expect(rebuiltIndexSource.lastErrorMessage == nil)
        #expect(rebuiltAsset.summaryStatus == .stale)
        #expect(rebuiltIndexAsset.summaryStatus == .ready)
        #expect(rebuiltAsset.notes.contains("Original capture notes."))
        #expect(rebuiltAsset.notes.contains("Capture marked stale"))
    }

    @MainActor
    @Test("Web page staleness skips fresh manual queued and uncaptured sources")
    func webPageStalenessSkipsFreshManualQueuedAndUncapturedSources() throws {
        let (_, store) = try makeLoadedStore()
        let now = Date(timeIntervalSince1970: 1_788_200_000)
        let oldCaptureDate = now.addingTimeInterval(-172_800)
        let freshCaptureDate = now.addingTimeInterval(-900)
        let freshURL = "https://example.com/docs/fresh-page"
        let manualURL = "https://example.com/docs/manual-page"
        let queuedURL = "https://example.com/docs/queued-page"
        let placeholderURL = "https://example.com/docs/placeholder-page"
        let freshSource = KnowledgeSource(
            title: "Fresh reference",
            kind: .webPage,
            location: freshURL,
            status: .ready,
            lastIndexedAt: freshCaptureDate,
            isWatched: true,
            documentCount: 1
        )
        let manualSource = KnowledgeSource(
            title: "Manual reference",
            kind: .webPage,
            location: manualURL,
            status: .ready,
            lastIndexedAt: oldCaptureDate,
            isWatched: false,
            documentCount: 1
        )
        let queuedSource = KnowledgeSource(
            title: "Queued reference",
            kind: .webPage,
            location: queuedURL,
            status: .queued,
            lastIndexedAt: oldCaptureDate,
            isWatched: true,
            documentCount: 1
        )
        let placeholderSource = KnowledgeSource(
            title: "Placeholder reference",
            kind: .webPage,
            location: placeholderURL,
            status: .ready,
            isWatched: true
        )
        store.knowledgeSources = [freshSource, manualSource, queuedSource, placeholderSource]
        store.libraryAssets = [
            webPageAsset(
                title: freshSource.title,
                url: freshURL,
                capturedAt: freshCaptureDate,
                text: "Fresh captured text."
            ),
            webPageAsset(
                title: manualSource.title,
                url: manualURL,
                capturedAt: oldCaptureDate,
                text: "Manual captured text."
            ),
            webPageAsset(
                title: queuedSource.title,
                url: queuedURL,
                capturedAt: oldCaptureDate,
                text: "Queued captured text."
            ),
            LibraryAsset(
                title: placeholderSource.title,
                kind: .link,
                sourceURL: URL(string: placeholderURL)!,
                sourceIdentifier: placeholderURL,
                summary: "Placeholder only.",
                summaryStatus: .missing,
                updatedAt: oldCaptureDate,
                capturedAt: oldCaptureDate,
                transcript: TranscriptRecord(
                    status: .notRequested,
                    sourceLabel: "Web page capture",
                    importedAt: oldCaptureDate,
                    updatedAt: oldCaptureDate
                )
            )
        ]

        let staleIDs = store.queueStaleWatchedWebPageKnowledgeSources(now: now)

        #expect(staleIDs.isEmpty)
        #expect(store.knowledgeSources.first(where: { $0.id == freshSource.id })?.status == .ready)
        #expect(store.knowledgeSources.first(where: { $0.id == manualSource.id })?.status == .ready)
        #expect(store.knowledgeSources.first(where: { $0.id == queuedSource.id })?.status == .queued)
        #expect(store.knowledgeSources.first(where: { $0.id == placeholderSource.id })?.status == .ready)
    }

    @MainActor
    @Test("Watched web page freshness respects the refresh batch bound")
    func watchedWebPageFreshnessRespectsRefreshBatchBound() throws {
        let (_, store) = try makeLoadedStore()
        let now = Date(timeIntervalSince1970: 1_788_200_000)
        let oldestDate = now.addingTimeInterval(-5 * WorkspaceStore.defaultWatchedWebPageRefreshInterval)
        let middleDate = now.addingTimeInterval(-4 * WorkspaceStore.defaultWatchedWebPageRefreshInterval)
        let newestDate = now.addingTimeInterval(-3 * WorkspaceStore.defaultWatchedWebPageRefreshInterval)
        let oldestSource = KnowledgeSource(
            title: "Oldest page",
            kind: .webPage,
            location: "https://example.com/oldest",
            status: .ready,
            lastIndexedAt: oldestDate,
            isWatched: true,
            documentCount: 1
        )
        let middleSource = KnowledgeSource(
            title: "Middle page",
            kind: .webPage,
            location: "https://example.com/middle",
            status: .ready,
            lastIndexedAt: middleDate,
            isWatched: true,
            documentCount: 1
        )
        let newestSource = KnowledgeSource(
            title: "Newest stale page",
            kind: .webPage,
            location: "https://example.com/newest",
            status: .ready,
            lastIndexedAt: newestDate,
            isWatched: true,
            documentCount: 1
        )
        store.knowledgeSources = [middleSource, newestSource, oldestSource]
        store.libraryAssets = [
            webPageAsset(title: oldestSource.title, url: oldestSource.location, capturedAt: oldestDate, text: "Oldest captured text."),
            webPageAsset(title: middleSource.title, url: middleSource.location, capturedAt: middleDate, text: "Middle captured text."),
            webPageAsset(title: newestSource.title, url: newestSource.location, capturedAt: newestDate, text: "Newest captured text.")
        ]

        let queuedIDs = store.queueStaleWatchedWebPageKnowledgeSources(
            maximumSourceCount: 2,
            now: now
        )

        #expect(queuedIDs == [oldestSource.id, middleSource.id])
        #expect(store.knowledgeSources.first(where: { $0.id == oldestSource.id })?.status == .queued)
        #expect(store.knowledgeSources.first(where: { $0.id == middleSource.id })?.status == .queued)
        #expect(store.knowledgeSources.first(where: { $0.id == newestSource.id })?.status == .ready)
    }

    @MainActor
    @Test("Code repository knowledge source indexes recursive readable files with default exclusions")
    func codeRepositoryKnowledgeSourceIndexesRecursiveReadableFilesWithDefaultExclusions() throws {
        let (_, store) = try makeLoadedStore()
        store.knowledgeSources.removeAll()
        store.knowledgeIndexManifests.removeAll()
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-repo-vector-store-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-repo-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        defer {
            try? FileManager.default.removeItem(at: storageURL)
            try? FileManager.default.removeItem(at: repoURL)
        }
        store.preferences.localStorageLabel = storageURL.path

        let sourcesURL = repoURL.appendingPathComponent("Sources", isDirectory: true)
        let nodeModulesURL = repoURL.appendingPathComponent("node_modules", isDirectory: true)
        let ignoredURL = repoURL.appendingPathComponent("Ignored", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nodeModulesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ignoredURL, withIntermediateDirectories: true)
        try "FIBER NEEDLE local repository overview for recursive RAG.".write(
            to: repoURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "QUARTZ ROUTER Swift source should be indexed from nested folders.".write(
            to: sourcesURL.appendingPathComponent("Router.swift"),
            atomically: true,
            encoding: .utf8
        )
        try writeSearchableDOCX(
            text: "DOCX COPPER LANTERN design notes should be indexed from recursive folders.",
            to: repoURL.appendingPathComponent("DesignNotes.docx")
        )
        try "This dependency text must not enter the local index.".write(
            to: nodeModulesURL.appendingPathComponent("dependency.md"),
            atomically: true,
            encoding: .utf8
        )
        try "This custom excluded text must not enter the local index.".write(
            to: ignoredURL.appendingPathComponent("secret.md"),
            atomically: true,
            encoding: .utf8
        )
        try Data(repeating: 65, count: 2_600_000).write(to: repoURL.appendingPathComponent("huge.txt"))
        try "Lock files must be skipped.".write(
            to: repoURL.appendingPathComponent("Package.resolved"),
            atomically: true,
            encoding: .utf8
        )

        let source = try #require(store.addKnowledgeSource(
            title: "Local repo",
            kind: .codeRepository,
            location: repoURL.path,
            watched: true
        ))
        let sourceIndex = try #require(store.knowledgeSources.firstIndex(where: { $0.id == source.id }))
        store.knowledgeSources[sourceIndex].exclusionRules = ["Ignored"]

        let inputs = store.localKnowledgeDocumentInputs()
            .filter { $0.knowledgeSourceID == source.id }
        #expect(inputs.map(\.title) == ["DesignNotes.docx", "README.md", "Sources/Router.swift"])

        store.rebuildKnowledgeIndexManifests(onlyQueued: true)
        let rebuilt = try #require(store.knowledgeSources.first(where: { $0.id == source.id }))
        let manifest = try #require(store.knowledgeIndexManifests.first(where: { $0.sourceID == source.id }))
        let packet = store.localKnowledgeRetrievalPacket(for: "QUARTZ ROUTER recursive folders", limit: 4)
        let docxPacket = store.localKnowledgeRetrievalPacket(for: "COPPER LANTERN design notes", limit: 4)

        #expect(rebuilt.status == .ready)
        #expect(rebuilt.documentCount == 3)
        #expect(rebuilt.chunkCount >= 3)
        #expect(manifest.status == .ready)
        #expect(manifest.documentCount == 3)
        #expect(packet.results.contains { $0.chunk.knowledgeSourceID == source.id && $0.chunk.sourceLocation.hasSuffix("Sources/Router.swift") })
        #expect(docxPacket.results.contains { $0.chunk.knowledgeSourceID == source.id && $0.chunk.sourceLocation.hasSuffix("DesignNotes.docx") })
        #expect(packet.results.contains { $0.chunk.text.contains("dependency text") } == false)
        #expect(packet.results.contains { $0.chunk.text.contains("custom excluded") } == false)
    }

    @MainActor
    @Test("Knowledge source onboarding updates duplicates and captures web source locally")
    func knowledgeSourceOnboardingUpdatesDuplicatesAndCapturesWebSource() throws {
        let (_, store) = try makeLoadedStore()
        let originalSourceCount = store.knowledgeSources.count
        let originalAssetCount = store.libraryAssets.count
        let url = "https://example.com/flannel-reference"

        let firstSource = try #require(store.addKnowledgeSource(
            title: "Reference page",
            kind: .webPage,
            location: " \(url) ",
            watched: false
        ))
        let updatedSource = try #require(store.addKnowledgeSource(
            title: "Reference page updated",
            kind: .webPage,
            location: url,
            watched: true
        ))

        #expect(store.knowledgeSources.count == originalSourceCount + 1)
        #expect(firstSource.id == updatedSource.id)
        #expect(updatedSource.title == "Reference page updated")
        #expect(updatedSource.status == .queued)
        #expect(updatedSource.isWatched == true)
        #expect(store.libraryAssets.count == originalAssetCount + 1)
        #expect(store.libraryAssets.contains { asset in
            asset.sourceURL?.absoluteString == url
                && asset.kind == .link
                && asset.tags.contains("knowledge")
        })
    }

    @MainActor
    @Test("Web page knowledge source does not index placeholder metadata before capture")
    func webPageKnowledgeSourceDoesNotIndexPlaceholderMetadataBeforeCapture() throws {
        let (_, store) = try makeLoadedStore()
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-web-negative-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: storageURL) }
        store.preferences.localStorageLabel = storageURL.path
        let url = "https://example.com/docs/live-capture"

        let source = try #require(store.addKnowledgeSource(
            title: "Example Docs",
            kind: .webPage,
            location: url,
            watched: true
        ))

        store.rebuildKnowledgeIndexManifests(onlyQueued: true)

        let rebuilt = try #require(store.knowledgeSources.first(where: { $0.id == source.id }))
        let manifest = try #require(store.knowledgeIndexManifests.first(where: { $0.sourceID == source.id }))
        let packet = store.localKnowledgeRetrievalPacket(for: "Page content remains local until import", limit: 5)

        #expect(rebuilt.status == .failed)
        #expect(rebuilt.documentCount == 0)
        #expect(rebuilt.chunkCount == 0)
        #expect(manifest.status == .failed)
        #expect(manifest.lastErrorMessage == "No readable local documents were found for this source.")
        #expect(packet.results.contains { $0.chunk.knowledgeSourceID == source.id } == false)
    }

    @MainActor
    @Test("Web page knowledge source indexes captured page body text")
    func webPageKnowledgeSourceIndexesCapturedPageBodyText() throws {
        let (_, store) = try makeLoadedStore()
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-web-positive-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: storageURL) }
        store.preferences.localStorageLabel = storageURL.path
        let url = "https://example.com/docs/live-capture"
        let source = try #require(store.addKnowledgeSource(
            title: "Example Docs",
            kind: .webPage,
            location: url,
            watched: true
        ))
        let captured = CapturedWebPage(
            url: URL(string: url)!,
            title: "Example Docs",
            text: "FROST NEEDLE 42 canonicalization pipeline preserves DOM headings and code samples for local RAG retrieval.",
            excerpt: "FROST NEEDLE 42 canonicalization pipeline preserves DOM headings and code samples.",
            statusCode: 200,
            contentType: "text/html",
            capturedAt: Date(timeIntervalSince1970: 1_788_000_000)
        )

        store.storeCapturedWebPage(captured, for: source.id, rebuild: true)
        let packet = store.localKnowledgeRetrievalPacket(
            for: "FROST NEEDLE canonicalization code samples",
            limit: 3
        )

        let rebuilt = try #require(store.knowledgeSources.first(where: { $0.id == source.id }))
        let top = try #require(packet.results.first(where: { $0.chunk.knowledgeSourceID == source.id }))
        let asset = try #require(store.libraryAssets.first(where: { $0.sourceIdentifier == url }))

        #expect(rebuilt.status == .ready)
        #expect(rebuilt.documentCount == 1)
        #expect(rebuilt.chunkCount > 0)
        #expect(top.chunk.sourceKind == .webPage)
        #expect(top.chunk.sourceTitle == "Example Docs")
        #expect(top.chunk.text.contains("canonicalization pipeline preserves DOM headings"))
        #expect(top.snippet.localizedCaseInsensitiveContains("code samples"))
        #expect(top.matchedTerms.contains("canonicalization"))
        #expect(top.matchedTerms.contains("samples"))
        #expect(packet.citations.isEmpty == false)
        #expect(asset.transcript?.status == .available)
        #expect(asset.summaryStatus == .ready)
    }

    @MainActor
    @Test("Message pins are idempotent and can be removed")
    func messagePinsAreIdempotentAndRemovable() throws {
        let (_, store) = try makeLoadedStore()
        let thread = try #require(store.currentAssistantThread)
        let messageID = try #require(thread.messages.last?.id)

        let pin = try #require(store.pinMessage(messageID, in: thread.id))
        let duplicatePin = try #require(store.pinMessage(messageID, in: thread.id))

        #expect(pin == duplicatePin)
        #expect(store.pinnedMessages.count == 1)
        #expect(store.isMessagePinned(messageID, in: thread.id))
        #expect(store.pinnedMessages.first?.threadID == thread.id)
        #expect(store.pinnedMessages.first?.messageID == messageID)

        store.unpinMessage(messageID, in: thread.id)

        #expect(store.pinnedMessages.isEmpty)
        #expect(store.isMessagePinned(messageID, in: thread.id) == false)
    }

    @MainActor
    @Test("Thread duplication copies the whole chat while fork copies through the selected message")
    func duplicateAndForkThreadFromMessage() throws {
        let (_, store) = try makeLoadedStore()
        let sourceThreadID = try #require(store.currentAssistantThread?.id)
        let folder = try #require(store.addChatFolder(title: "Deep Research"))
        #expect(store.assignThread(sourceThreadID, toFolder: folder.id))
        let userMessageID = store.appendAssistantMessage("Explore a split between local research and drafting.", role: .user)
        _ = store.appendAssistantMessage("Keep the research branch private until the draft is ready.", role: .assistant)
        let sourceThread = try #require(store.assistantThreads.first(where: { $0.id == sourceThreadID }))
        let userMessageIndex = try #require(sourceThread.messages.firstIndex(where: { $0.id == userMessageID }))
        let originalThreadCount = store.assistantThreads.count

        let duplicate = try #require(store.duplicateThread(from: userMessageID, in: sourceThreadID))

        #expect(store.assistantThreads.count == originalThreadCount + 1)
        #expect(duplicate.id != sourceThread.id)
        #expect(duplicate.title == "Copy of \(sourceThread.title)")
        #expect(duplicate.messages.map(\.text) == sourceThread.messages.map(\.text))
        #expect(Set(duplicate.messages.map(\.id)).isDisjoint(with: Set(sourceThread.messages.map(\.id))))
        #expect(duplicate.folderID == folder.id)
        #expect(store.selectedAssistantThreadID == duplicate.id)
        #expect(store.selectedDestination == .home)

        let fork = try #require(store.forkThread(from: userMessageID, in: sourceThreadID))
        let expectedForkMessages = sourceThread.messages.prefix(userMessageIndex + 1).map(\.text)

        #expect(fork.id != sourceThread.id)
        #expect(fork.title.hasPrefix("Fork: "))
        #expect(fork.messages.map(\.text) == expectedForkMessages)
        #expect(fork.messages.count < sourceThread.messages.count)
        #expect(Set(fork.messages.map(\.id)).isDisjoint(with: Set(sourceThread.messages.map(\.id))))
        #expect(fork.folderID == folder.id)
        #expect(store.selectedAssistantThreadID == fork.id)
    }

    @MainActor
    @Test("Retry rewinds to the selected turn and clears discarded pins")
    func retryRewindsThreadToSelectedTurnAndClearsDiscardedPins() throws {
        let (_, store) = try makeLoadedStore()
        let threadID = try #require(store.currentAssistantThread?.id)
        let firstUserID = store.appendAssistantMessage("First prompt stays in history.", role: .user)
        _ = store.appendAssistantMessage("First answer stays in history.", role: .assistant)
        let retryUserID = store.appendAssistantMessage("Regenerate this request.", role: .user)
        let discardedAssistantID = store.appendAssistantMessage("Discard this stale answer.", role: .assistant)
        _ = try #require(store.pinMessage(discardedAssistantID, in: threadID))

        let draft = try #require(store.rewindThreadForRetry(from: discardedAssistantID, in: threadID))
        let thread = try #require(store.assistantThreads.first(where: { $0.id == threadID }))

        #expect(draft.prompt == "Regenerate this request.")
        #expect(draft.attachments.isEmpty)
        #expect(thread.messages.contains { $0.id == firstUserID })
        #expect(thread.messages.contains { $0.id == retryUserID } == false)
        #expect(thread.messages.contains { $0.id == discardedAssistantID } == false)
        #expect(thread.messages.last?.text == "First answer stays in history.")
        #expect(store.pinnedMessages.contains { $0.messageID == discardedAssistantID } == false)
        #expect(store.selectedAssistantThreadID == threadID)
        #expect(store.selectedDestination == .home)
    }

    @MainActor
    @Test("Editing a user message restores prompt and attachments while trimming later messages")
    func editUserMessageRestoresPromptAndAttachmentsWhileTrimmingLaterMessages() throws {
        let (_, store) = try makeLoadedStore()
        let threadID = try #require(store.currentAssistantThread?.id)
        let attachment = AIChatAttachment(
            kind: .document,
            title: "brief.md",
            mimeType: "text/markdown",
            localPath: "/tmp/brief.md",
            excerpt: "Attachment context should travel with edits."
        )
        let editedUserID = store.appendAssistantMessage(
            "Rewrite this with the attached brief.",
            role: .user,
            attachments: [attachment]
        )
        let discardedAssistantID = store.appendAssistantMessage("This answer should be removed before editing.", role: .assistant)

        let draft = try #require(store.rewindThreadForRetry(from: editedUserID, in: threadID))
        let thread = try #require(store.assistantThreads.first(where: { $0.id == threadID }))

        #expect(draft.prompt == "Rewrite this with the attached brief.")
        #expect(draft.attachments.first?.localPath == "/tmp/brief.md")
        #expect(thread.messages.contains { $0.id == editedUserID } == false)
        #expect(thread.messages.contains { $0.id == discardedAssistantID } == false)
        #expect(store.selectedAssistantThreadID == threadID)
    }

    @MainActor
    @Test("Assistant message attachments persist, search, and fork with chat history")
    func assistantMessageAttachmentsPersistSearchAndFork() throws {
        let (_, store) = try makeLoadedStore()
        let attachment = AIChatAttachment(
            kind: .textSnippet,
            title: "launch-brief.md",
            mimeType: "text/markdown",
            localPath: "/tmp/launch-brief.md",
            byteCount: 512,
            excerpt: "Attachment-only strategy note."
        )

        let messageID = store.appendAssistantMessage(
            "Use this attachment.",
            role: .user,
            attachments: [attachment]
        )
        let thread = try #require(store.currentAssistantThread)
        let message = try #require(thread.messages.first(where: { $0.id == messageID }))

        #expect(message.attachments.first?.title == "launch-brief.md")
        #expect(store.searchChats("Attachment-only").contains { $0.matchKind == .attachment })

        let forked = try #require(store.forkThread(from: messageID, in: thread.id))
        #expect(forked.messages.last?.attachments.first?.localPath == "/tmp/launch-brief.md")
    }

    @MainActor
    @Test("Archived threads leave the active list but remain searchable globally")
    func archiveThreadAndGlobalChatSearch() throws {
        let (_, store) = try makeLoadedStore()
        let threadID = try #require(store.currentAssistantThread?.id)
        let messageID = store.appendAssistantMessage("Needle discussion for local chat organization.", role: .user)
        _ = try #require(store.pinMessage(messageID, in: threadID))
        let replacementThread = try #require(store.duplicateThread(from: messageID, in: threadID))
        store.selectedAssistantThreadID = threadID

        #expect(store.archiveThread(threadID))
        #expect(store.archivedAssistantThreadIDs.contains(threadID))
        #expect(store.assistantThreads.first(where: { $0.id == threadID })?.isArchived == true)
        #expect(store.activeAssistantThreads.contains(where: { $0.id == threadID }) == false)
        #expect(store.archivedAssistantThreads.contains(where: { $0.id == threadID }))
        #expect(store.selectedAssistantThreadID == replacementThread.id)

        let activeResults = store.searchChats("Needle", includeArchived: false)
        let globalResults = store.searchChats("Needle", includeArchived: true)

        #expect(activeResults.contains { $0.threadID == threadID } == false)
        #expect(globalResults.contains { $0.threadID == threadID && $0.messageID == messageID && $0.isArchived && $0.isPinned })
        #expect(globalResults.contains { $0.threadID == replacementThread.id && $0.isArchived == false })

        store.searchText = "Needle"
        #expect(store.globalChatSearchResults.contains { $0.threadID == threadID && $0.messageID == messageID })
    }

    @MainActor
    @Test("Chat history filters by provider model project and date")
    func chatHistoryFiltersByProviderModelProjectAndDate() throws {
        let (_, store) = try makeLoadedStore()
        let now = Date(timeIntervalSince1970: 2_000_000)
        let project = WorkspaceProject(title: "Research Workspace")
        let matchingThread = AssistantThread(
            title: "Matching chat",
            messages: [
                AssistantMessage(
                    role: .assistant,
                    text: "Filtered answer",
                    referencedEntityIDs: [project.id],
                    providerDisplayName: "Local Ollama",
                    modelIdentifier: "llama3.1"
                )
            ],
            pinnedProjectID: project.id,
            updatedAt: now.addingTimeInterval(-1_800)
        )
        let providerMismatch = AssistantThread(
            title: "Provider mismatch",
            messages: [
                AssistantMessage(
                    role: .assistant,
                    text: "Different provider",
                    providerDisplayName: "Anthropic",
                    modelIdentifier: "claude-opus"
                )
            ],
            pinnedProjectID: project.id,
            updatedAt: now.addingTimeInterval(-1_200)
        )
        let oldThread = AssistantThread(
            title: "Old matching provider",
            messages: [
                AssistantMessage(
                    role: .assistant,
                    text: "Old provider answer",
                    referencedEntityIDs: [project.id],
                    providerDisplayName: "Local Ollama",
                    modelIdentifier: "llama3.1"
                )
            ],
            pinnedProjectID: project.id,
            updatedAt: now.addingTimeInterval(-40 * 24 * 60 * 60)
        )
        store.projects = [project]
        store.assistantThreads = [matchingThread, providerMismatch, oldThread]

        let filters = ChatHistoryFilters(
            providerDisplayName: "Local Ollama",
            modelIdentifier: "llama3.1",
            projectID: project.id,
            dateFilter: .previousSevenDays
        )
        let results = store.chatHistoryThreads(filters: filters, now: now)

        #expect(results.map(\.id) == [matchingThread.id])
    }

    @MainActor
    @Test("Chat history filters by previous seven-day boundary")
    func chatHistoryFiltersByPreviousSevenDaysBoundary() throws {
        let (_, store) = try makeLoadedStore()
        let now = Date(timeIntervalSince1970: 2_000_000)
        let startOfToday = Calendar.autoupdatingCurrent.startOfDay(for: now)
        let lowerBound = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
        let project = WorkspaceProject(title: "Boundary Workspace")
        let boundaryThread = AssistantThread(
            title: "Boundary thread",
            messages: [
                AssistantMessage(
                    role: .assistant,
                    text: "Boundary included",
                    referencedEntityIDs: [project.id],
                    providerDisplayName: "Local Ollama",
                    modelIdentifier: "llama3.1"
                )
            ],
            pinnedProjectID: project.id,
            updatedAt: lowerBound
        )
        let staleThread = AssistantThread(
            title: "Stale thread",
            messages: [
                AssistantMessage(
                    role: .assistant,
                    text: "Stale excluded",
                    referencedEntityIDs: [project.id],
                    providerDisplayName: "Local Ollama",
                    modelIdentifier: "llama3.1"
                )
            ],
            pinnedProjectID: project.id,
            updatedAt: lowerBound.addingTimeInterval(-1)
        )

        store.projects = [project]
        store.assistantThreads = [staleThread, boundaryThread]

        let filters = ChatHistoryFilters(
            providerDisplayName: "Local Ollama",
            modelIdentifier: "llama3.1",
            projectID: project.id,
            dateFilter: .previousSevenDays
        )
        let results = store.chatHistoryThreads(filters: filters, now: now)

        #expect(results.map(\.id) == [boundaryThread.id])
    }

    @MainActor
    @Test("Filtered chat search only returns matching provider threads")
    func filteredChatSearchOnlyReturnsMatchingProviderThreads() throws {
        let (_, store) = try makeLoadedStore()
        let localThread = AssistantThread(
            title: "Local research",
            messages: [
                AssistantMessage(
                    role: .assistant,
                    text: "Needle answer from a local model.",
                    providerDisplayName: "Local Ollama",
                    modelIdentifier: "llama3.1"
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let cloudThread = AssistantThread(
            title: "Cloud research",
            messages: [
                AssistantMessage(
                    role: .assistant,
                    text: "Needle answer from a hosted model.",
                    providerDisplayName: "OpenAI",
                    modelIdentifier: "gpt-5.5"
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        store.assistantThreads = [localThread, cloudThread]

        let results = store.searchChats(
            "Needle",
            filters: ChatHistoryFilters(providerDisplayName: "Local Ollama")
        )

        #expect(results.contains { $0.threadID == localThread.id })
        #expect(results.contains { $0.threadID == cloudThread.id } == false)
    }

    @MainActor
    @Test("Chat pins and archived thread IDs persist across reload")
    func chatOrganizationPersistsAcrossReload() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)
        let threadID = try #require(store.currentAssistantThread?.id)
        let messageID = store.appendAssistantMessage("Persist this pinned chat organization state.", role: .user)
        _ = try #require(store.pinMessage(messageID, in: threadID))
        #expect(store.pinThread(threadID))
        store.applyTags(["Deep Research"], threadID: threadID)
        #expect(store.currentAssistantThread?.isPinned == true)
        #expect(store.currentAssistantThread?.tagNames == ["deep-research"])
        #expect(store.tags.contains { $0.name == "deep-research" && $0.usageCount == 1 })
        #expect(store.archiveThread(threadID))
        try store.persist(in: context)

        let reloadedStore = WorkspaceStore()
        try reloadedStore.loadOrCreate(in: context)

        #expect(reloadedStore.isMessagePinned(messageID, in: threadID))
        #expect(reloadedStore.assistantThreads.first(where: { $0.id == threadID })?.isPinned == true)
        #expect(reloadedStore.assistantThreads.first(where: { $0.id == threadID })?.isArchived == true)
        #expect(reloadedStore.assistantThreads.first(where: { $0.id == threadID })?.tagNames == ["deep-research"])
        #expect(reloadedStore.tags.contains { $0.name == "deep-research" && $0.usageCount == 1 })
        #expect(reloadedStore.searchChats("Persist").contains { $0.threadID == threadID && $0.isPinned })
        #expect(reloadedStore.searchChats("deep-research").contains { $0.threadID == threadID })
        #expect(reloadedStore.removeTag("Deep Research", fromThread: threadID))
        #expect(reloadedStore.assistantThreads.first(where: { $0.id == threadID })?.tagNames.isEmpty == true)
        #expect(reloadedStore.archivedAssistantThreadIDs.contains(threadID))
        #expect(reloadedStore.archivedAssistantThreads.contains { $0.id == threadID })
    }

    @MainActor
    @Test("Legacy thread archive flags hydrate into canonical archive state and can be cleared")
    func legacyThreadArchiveFlagsHydrateIntoCanonicalArchiveStateAndCanBeCleared() throws {
        let archivedThreadID = UUID()
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let item = Item(
            assistantThreads: [
                AssistantThread(
                    id: archivedThreadID,
                    title: "Legacy archived chat",
                    isArchived: true
                )
            ],
            archivedAssistantThreadIDs: []
        )
        context.insert(item)
        try context.save()

        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)

        #expect(store.archivedAssistantThreadIDs.contains(archivedThreadID))
        #expect(store.archivedAssistantThreads.contains { $0.id == archivedThreadID })
        #expect(store.assistantThreads.first(where: { $0.id == archivedThreadID })?.isArchived == true)

        #expect(store.unarchiveThread(archivedThreadID))
        #expect(store.archivedAssistantThreadIDs.contains(archivedThreadID) == false)
        #expect(store.assistantThreads.first(where: { $0.id == archivedThreadID })?.isArchived == false)

        try store.persist(in: context)

        let reloadedStore = WorkspaceStore()
        try reloadedStore.loadOrCreate(in: context)

        #expect(reloadedStore.archivedAssistantThreadIDs.contains(archivedThreadID) == false)
        #expect(reloadedStore.assistantThreads.first(where: { $0.id == archivedThreadID })?.isArchived == false)
    }

    @MainActor
    @Test("Chat folders assign persist search and delete without deleting chats")
    func chatFoldersAssignPersistSearchAndDeleteWithoutDeletingChats() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)
        let threadID = try #require(store.currentAssistantThread?.id)
        let folder = try #require(store.addChatFolder(title: "Grant Research", symbolName: "doc.text.magnifyingglass"))

        #expect(store.assignThread(threadID, toFolder: folder.id))
        #expect(store.currentAssistantThread?.folderID == folder.id)
        #expect(store.folder(for: try #require(store.currentAssistantThread))?.title == "Grant Research")
        #expect(store.threadCount(inFolder: folder.id) == 1)
        #expect(store.searchChats("Grant Research").contains { $0.threadID == threadID })

        try store.persist(in: context)
        let reloadedStore = WorkspaceStore()
        try reloadedStore.loadOrCreate(in: context)

        #expect(reloadedStore.chatFolders.contains { $0.id == folder.id && $0.title == "Grant Research" })
        #expect(reloadedStore.assistantThreads.first(where: { $0.id == threadID })?.folderID == folder.id)

        #expect(reloadedStore.deleteChatFolder(folder.id))
        #expect(reloadedStore.chatFolders.contains { $0.id == folder.id } == false)
        #expect(reloadedStore.assistantThreads.first(where: { $0.id == threadID })?.folderID == nil)
        #expect(reloadedStore.assistantThreads.contains { $0.id == threadID })
    }

    @MainActor
    @Test("Model comparison runs persist with immutable provider snapshots")
    func modelComparisonRunProviderSnapshotPersists() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)
        store.modelComparisonRuns.removeAll()
        store.providerConfigurations.removeAll()

        let stableProviderID = UUID(uuidString: "f7c4a1e0-9d73-4d66-a4f9-8f58be8fd2f3")!
        let volatileProviderID = UUID(uuidString: "3f0f1a2a-a0f2-4be6-a6f0-95af2ca6f0d1")!
        let stableProvider = ProviderConfiguration(
            id: stableProviderID,
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Stable provider",
            endpoint: "http://localhost:11434",
            modelIdentifier: "stable-model",
            isEnabled: true,
            connectionStatus: .ready,
            supportsStreaming: true
        )
        let volatileProvider = ProviderConfiguration(
            id: volatileProviderID,
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Volatile provider",
            endpoint: "http://localhost:11435",
            modelIdentifier: "volatile-model",
            isEnabled: true,
            connectionStatus: .ready,
            supportsStreaming: true
        )
        store.providerConfigurations = [stableProvider, volatileProvider]

        let runID = try #require(
            store.createModelComparisonRun(
                prompt: "  Compare local model behavior  ",
                providerIDs: [stableProvider.id, volatileProvider.id],
                systemPrompt: "  Compare models consistently  ",
                now: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        let baselineRun = try #require(store.modelComparisonRuns.first(where: { $0.id == runID }))
        #expect(baselineRun.prompt == "Compare local model behavior")
        #expect(baselineRun.systemPrompt == "Compare models consistently")
        #expect(baselineRun.providerIDs == [stableProvider.id, volatileProvider.id])
        #expect(baselineRun.results.count == 2)
        #expect(baselineRun.results.first(where: { $0.providerID == stableProvider.id })?.providerDisplayName == "Stable provider")
        #expect(baselineRun.results.first(where: { $0.providerID == stableProvider.id })?.modelIdentifier == "stable-model")

        if let providerIndex = store.providerConfigurations.firstIndex(where: { $0.id == stableProvider.id }) {
            store.providerConfigurations[providerIndex].displayName = "Renamed after creation"
            store.providerConfigurations[providerIndex].modelIdentifier = "renamed-model"
        }

        let snapshotResult = try #require(
            baselineRun.results.first(where: { $0.providerID == stableProvider.id })
        )
        #expect(snapshotResult.providerDisplayName == "Stable provider")
        #expect(snapshotResult.modelIdentifier == "stable-model")

        try store.persist(in: context)

        let reloadedStore = WorkspaceStore()
        try reloadedStore.loadOrCreate(in: context)
        let reloadedRun = try #require(reloadedStore.modelComparisonRuns.first(where: { $0.id == runID }))
        let reloadedSnapshot = try #require(reloadedRun.results.first(where: { $0.providerID == stableProvider.id }))
        #expect(reloadedRun.prompt == "Compare local model behavior")
        #expect(reloadedRun.systemPrompt == "Compare models consistently")
        #expect(reloadedRun.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(reloadedSnapshot.providerDisplayName == "Stable provider")
        #expect(reloadedSnapshot.modelIdentifier == "stable-model")
    }

    @MainActor
    @Test("Model comparison run captures provider identity and privacy metadata")
    func modelComparisonRunCapturesProviderIdentityMetadata() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)
        store.modelComparisonRuns.removeAll()
        store.providerConfigurations.removeAll()
        store.preferences.localOnlyMode = false
        store.preferences.allowCloudProviders = true

        let localProvider = ProviderConfiguration(
            id: UUID(uuidString: "4d8d4d58-9bf6-4f7e-9fd8-1f9e0f4a9d2b")!,
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Snapshot provider",
            endpoint: "http://localhost:11434",
            modelIdentifier: "stable-v1",
            isEnabled: true,
            connectionStatus: .ready,
            supportsStreaming: true
        )
        let cloudProvider = ProviderConfiguration(
            id: UUID(uuidString: "d31f6f20-9f58-4e7b-b6b7-0cf2f0db4f8a")!,
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Snapshot cloud",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-4.1-mini",
            secretReference: "flannel.tests:snapshot-openai-key",
            isEnabled: true,
            connectionStatus: .ready,
            supportsStreaming: true
        )
        store.providerConfigurations = [localProvider, cloudProvider]
        #expect(store.isProviderRunnableForChat(localProvider))
        #expect(store.isProviderRunnableForChat(cloudProvider))

        let runID = try #require(
            store.createModelComparisonRun(
                prompt: "Capture provider identity metadata.",
                providerIDs: [localProvider.id, cloudProvider.id],
                now: Date(timeIntervalSince1970: 1_810_000_000)
            )
        )

        if let providerIndex = store.providerConfigurations.firstIndex(where: { $0.id == localProvider.id }) {
            store.providerConfigurations[providerIndex].displayName = "Mutated name"
            store.providerConfigurations[providerIndex].modelIdentifier = "mutated-model"
            store.providerConfigurations[providerIndex].accessMode = .apiKey
            store.providerConfigurations[providerIndex].privacyScope = .externalAPI
        }

        let run = try #require(store.modelComparisonRuns.first(where: { $0.id == runID }))
        let localSnapshot = try #require(run.results.first(where: { $0.providerID == localProvider.id }))
        let cloudSnapshot = try #require(run.results.first(where: { $0.providerID == cloudProvider.id }))

        #expect(localSnapshot.providerKind == .lmStudio)
        #expect(localSnapshot.accessMode == .localServer)
        #expect(localSnapshot.privacyScope == .localOnly)
        #expect(localSnapshot.providerDisplayName == "Snapshot provider")
        #expect(localSnapshot.modelIdentifier == "stable-v1")

        #expect(cloudSnapshot.providerKind == .openAI)
        #expect(cloudSnapshot.accessMode == .apiKey)
        #expect(cloudSnapshot.privacyScope == .externalAPI)
        #expect(cloudSnapshot.providerDisplayName == "Snapshot cloud")
        #expect(cloudSnapshot.modelIdentifier == "gpt-4.1-mini")
    }

    @MainActor
    @Test("Model comparison results preserve exact streamed usage and mark fallbacks as estimates")
    func modelComparisonResultsPreserveExactStreamedUsage() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)
        store.modelComparisonRuns.removeAll()
        store.providerConfigurations.removeAll()

        let exactProvider = ProviderConfiguration(
            id: UUID(uuidString: "434fa2c7-94fe-4c74-8d01-4c9d89600f80")!,
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Exact LM Studio",
            endpoint: "http://localhost:1234/v1",
            modelIdentifier: "local/exact",
            isEnabled: true,
            connectionStatus: .ready,
            supportsStreaming: true
        )
        let estimatedProvider = ProviderConfiguration(
            id: UUID(uuidString: "b04290d4-8c10-4ab2-a9a6-c89f55f59fdb")!,
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Estimated Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1",
            isEnabled: true,
            connectionStatus: .ready,
            supportsStreaming: true
        )
        store.providerConfigurations = [exactProvider, estimatedProvider]

        let runID = try #require(
            store.createModelComparisonRun(
                prompt: "Compare exact and estimated token handling.",
                providerIDs: [exactProvider.id, estimatedProvider.id],
                now: Date(timeIntervalSince1970: 1_750_000_000)
            )
        )
        let startedAt = Date(timeIntervalSince1970: 1_750_000_001)
        let completedAt = Date(timeIntervalSince1970: 1_750_000_003)

        store.updateModelComparisonResult(
            runID: runID,
            providerID: exactProvider.id,
            status: .completed,
            text: "Provider reported exact usage.",
            startedAt: startedAt,
            completedAt: completedAt,
            inputTokenCount: 41,
            outputTokenCount: 67,
            latencyMilliseconds: 432,
            firstTokenLatencyMilliseconds: 123,
            tokenCountsAreEstimated: false
        )

        store.updateModelComparisonResult(
            runID: runID,
            providerID: estimatedProvider.id,
            status: .completed,
            text: "Provider did not report usage.",
            startedAt: startedAt,
            completedAt: completedAt
        )

        let run = try #require(store.modelComparisonRuns.first(where: { $0.id == runID }))
        let exactResult = try #require(run.results.first(where: { $0.providerID == exactProvider.id }))
        #expect(exactResult.inputTokenCount == 41)
        #expect(exactResult.outputTokenCount == 67)
        #expect(exactResult.latencyMilliseconds == 432)
        #expect(exactResult.firstTokenLatencyMilliseconds == 123)
        #expect(exactResult.tokenCountsAreEstimated == false)

        let estimatedResult = try #require(run.results.first(where: { $0.providerID == estimatedProvider.id }))
        #expect(estimatedResult.inputTokenCount != nil)
        #expect(estimatedResult.outputTokenCount != nil)
        #expect(estimatedResult.tokenCountsAreEstimated)

        try store.persist(in: context)

        let reloadedStore = WorkspaceStore()
        try reloadedStore.loadOrCreate(in: context)
        let reloadedRun = try #require(reloadedStore.modelComparisonRuns.first(where: { $0.id == runID }))
        let reloadedExactResult = try #require(reloadedRun.results.first(where: { $0.providerID == exactProvider.id }))
        let reloadedEstimatedResult = try #require(reloadedRun.results.first(where: { $0.providerID == estimatedProvider.id }))
        #expect(reloadedExactResult.inputTokenCount == 41)
        #expect(reloadedExactResult.outputTokenCount == 67)
        #expect(reloadedExactResult.latencyMilliseconds == 432)
        #expect(reloadedExactResult.firstTokenLatencyMilliseconds == 123)
        #expect(reloadedExactResult.tokenCountsAreEstimated == false)
        #expect(reloadedEstimatedResult.tokenCountsAreEstimated)
    }

    @MainActor
    @Test("Completed model comparison result can be promoted into the current chat")
    func completedModelComparisonResultPromotesIntoCurrentChat() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)
        store.assistantThreads.removeAll()
        store.selectedAssistantThreadID = nil
        store.modelComparisonRuns.removeAll()
        store.providerConfigurations.removeAll()

        let promotedProvider = ProviderConfiguration(
            id: UUID(uuidString: "c96347da-13f2-4b7c-93a8-09b5510277a4")!,
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Promoted LM Studio",
            endpoint: "http://localhost:1234/v1",
            modelIdentifier: "local/promoted",
            isEnabled: true,
            connectionStatus: .ready,
            supportsStreaming: true
        )
        let comparisonPeer = ProviderConfiguration(
            id: UUID(uuidString: "8c7b0ecf-1185-4e07-9894-b693edc752e7")!,
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Comparison Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1",
            isEnabled: true,
            connectionStatus: .ready,
            supportsStreaming: true
        )
        store.providerConfigurations = [promotedProvider, comparisonPeer]

        let citation = AIChatCitation(
            title: "Private comparison source",
            snippet: "Comparison answers should preserve source context when promoted.",
            sourceIdentifier: "comparison-source"
        )
        let runID = try #require(
            store.createModelComparisonRun(
                prompt: "Which route should answer this private workspace task?",
                providerIDs: [promotedProvider.id, comparisonPeer.id],
                citations: [citation],
                now: Date(timeIntervalSince1970: 1_820_000_000)
            )
        )
        let startedAt = Date(timeIntervalSince1970: 1_820_000_002)
        let completedAt = Date(timeIntervalSince1970: 1_820_000_006)
        store.updateModelComparisonResult(
            runID: runID,
            providerID: promotedProvider.id,
            status: .completed,
            text: "Use the local route because it keeps the workspace private.",
            startedAt: startedAt,
            completedAt: completedAt,
            inputTokenCount: 32,
            outputTokenCount: 48,
            latencyMilliseconds: 1_250,
            firstTokenLatencyMilliseconds: 220,
            tokenCountsAreEstimated: false
        )
        let resultID = try #require(
            store.modelComparisonRuns
                .first(where: { $0.id == runID })?
                .results
                .first(where: { $0.providerID == promotedProvider.id })?
                .id
        )

        let promotedMessageID = try #require(
            store.appendComparisonResultToCurrentChat(
                runID: runID,
                resultID: resultID,
                now: Date(timeIntervalSince1970: 1_820_000_010)
            )
        )

        let thread = try #require(store.currentAssistantThread)
        #expect(store.selectedAssistantThreadID == thread.id)
        #expect(thread.messages.count == 2)
        #expect(thread.messages.first?.role == .user)
        #expect(thread.messages.first?.text == "Which route should answer this private workspace task?")
        let promotedMessage = try #require(thread.messages.first(where: { $0.id == promotedMessageID }))
        #expect(promotedMessage.role == .assistant)
        #expect(promotedMessage.text == "Use the local route because it keeps the workspace private.")
        #expect(promotedMessage.providerDisplayName == "Promoted LM Studio")
        #expect(promotedMessage.modelIdentifier == "local/promoted")
        #expect(promotedMessage.inputTokenCount == 32)
        #expect(promotedMessage.outputTokenCount == 48)
        #expect(promotedMessage.latencyMilliseconds == 1_250)
        #expect(promotedMessage.firstTokenLatencyMilliseconds == 220)
        #expect(promotedMessage.providerAccessMode == .localServer)
        #expect(promotedMessage.providerPrivacyScope == .localOnly)
        #expect(promotedMessage.runStatus == .completed)
        #expect(promotedMessage.startedAt == startedAt)
        #expect(promotedMessage.completedAt == completedAt)
        #expect(promotedMessage.tokenCountsAreEstimated == false)
        #expect(promotedMessage.citations == [citation])
    }

    @MainActor
    @Test("runnableComparisonProviders filters non-runnable providers from comparison candidate ids")
    func runnableComparisonProvidersFilterUnavailableProviders() throws {
        let (_, store) = try makeLoadedStore()
        let runnableProviderID = UUID(uuidString: "a7cb4f91-9c44-43df-98d5-0d5f2c9c8b9c")!
        let secondRunnableProviderID = UUID(uuidString: "e9c40f1b-23ff-438a-9d37-e6e61f95f10b")!
        let disabledProviderID = UUID(uuidString: "b6e4f7aa-1b4e-4e8a-8f45-0f0f4e8ef7c1")!
        let nonStreamingProviderID = UUID(uuidString: "c8a7ec9f-2b7e-4f8d-b5f3-1ad4b7e4a4d8")!
        store.providerConfigurations = [
            ProviderConfiguration(
                id: runnableProviderID,
                kind: .lmStudio,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "Runnable Alpha",
                endpoint: "http://localhost:11436",
                modelIdentifier: "model-alpha",
                isEnabled: true,
                connectionStatus: .ready,
                isLocalPreferred: true,
                supportsStreaming: true
            ),
            ProviderConfiguration(
                id: secondRunnableProviderID,
                kind: .ollama,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "Runnable Delta",
                endpoint: "http://localhost:11439",
                modelIdentifier: "model-delta",
                isEnabled: true,
                connectionStatus: .ready,
                supportsStreaming: true
            ),
            ProviderConfiguration(
                id: disabledProviderID,
                kind: .lmStudio,
                accessMode: .localServer,
                privacyScope: .localOnly,
                displayName: "Disabled Beta",
                endpoint: "http://localhost:11437",
                modelIdentifier: "model-beta",
                isEnabled: false,
                connectionStatus: .ready,
                supportsStreaming: true
            ),
            ProviderConfiguration(
                id: nonStreamingProviderID,
                kind: .openAI,
                accessMode: .apiKey,
                privacyScope: .localOnly,
                displayName: "Non-streaming Gamma",
                endpoint: "https://api.openai.com/v1",
                modelIdentifier: "model-gamma",
                isEnabled: true,
                connectionStatus: .ready,
                isLocalPreferred: false,
                supportsStreaming: false
            )
        ]
        store.preferences.preferredProviderID = runnableProviderID
        store.preferences.localOnlyMode = true
        store.preferences.allowCloudProviders = true

        let providers = store.runnableComparisonProviders
        #expect(providers.map(\.id) == [runnableProviderID, secondRunnableProviderID])
        #expect(store.defaultComparisonProviderIDs(limit: 3) == [runnableProviderID, secondRunnableProviderID])
        #expect(store.createModelComparisonRun(
            prompt: "Single runnable provider is not enough",
            providerIDs: [disabledProviderID, runnableProviderID, nonStreamingProviderID]
        ) == nil)

        let runID = try #require(
            store.createModelComparisonRun(
                prompt: "Which one can run?",
                providerIDs: [disabledProviderID, runnableProviderID, nonStreamingProviderID, secondRunnableProviderID, runnableProviderID]
            )
        )
        let run = try #require(store.modelComparisonRuns.first(where: { $0.id == runID }))
        #expect(run.providerIDs == [runnableProviderID, secondRunnableProviderID])
        #expect(run.results.count == 2)
        #expect(run.results.first?.providerID == runnableProviderID)
        #expect(run.results.first?.providerDisplayName == "Runnable Alpha")
        #expect(run.status == .queued)
    }

    @MainActor
    @Test("Explicit local memories score into bounded chat context")
    func explicitLocalMemoriesScoreIntoBoundedChatContext() throws {
        let (_, store) = try makeLoadedStore()
        store.localMemories.removeAll()
        store.preferences.localMemory = LocalMemorySettings(
            isEnabled: true,
            includeInChatContext: true,
            maximumContextMemories: 1,
            requireExplicitSave: true
        )

        let writingMemory = try #require(store.addLocalMemory(
            title: "Writing voice",
            detail: "Austin prefers concise launch writing with concrete dates and no vague filler.",
            category: .writingStyle,
            tagNames: ["Writing", "Launch"]
        ))
        _ = store.addLocalMemory(
            title: "Meeting habit",
            detail: "Weekly planning happens on Fridays.",
            category: .workflow
        )

        let context = try #require(store.localMemoryPromptContext(for: "Use Austin launch writing voice."))

        #expect(context.contains("Local Memories:"))
        #expect(context.contains("[Writing Style] Writing voice"))
        #expect(context.contains("concrete dates"))
        #expect(context.contains("Weekly planning") == false)
        #expect(store.localMemories.first(where: { $0.id == writingMemory.id })?.useCount == 1)
        #expect(store.localMemories.first(where: { $0.id == writingMemory.id })?.lastUsedAt != nil)
    }

    @MainActor
    @Test("Local memory can be saved from slash command and disabled from context")
    func localMemorySlashCommandAndDisable() throws {
        let (_, store) = try makeLoadedStore()
        store.localMemories.removeAll()

        let commandText = "/remember Prefer local Ollama for private draft review."
        let memoryText = try #require(store.parseRememberCommand(commandText))
        let memory = try #require(store.rememberFromCurrentThread(memoryText, category: .preference))

        #expect(memory.title == "Prefer local Ollama for private draft review.")
        #expect(store.localMemories.count == 1)
        #expect(store.localMemoryPromptContext(for: "private draft review")?.contains("Prefer local Ollama") == true)

        store.setLocalMemoryEnabled(memory.id, isEnabled: false)
        #expect(store.localMemoryPromptContext(for: "private draft review") == nil)
    }

    @MainActor
    @Test("Local memories and settings persist across reload")
    func localMemoriesPersistAcrossReload() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)
        store.localMemories.removeAll()
        store.preferences.localMemory = LocalMemorySettings(
            isEnabled: true,
            includeInChatContext: false,
            maximumContextMemories: 3,
            requireExplicitSave: true
        )
        let memory = try #require(store.addLocalMemory(
            title: "Project constraint",
            detail: "Flannel must stay usable with no required login.",
            category: .project,
            tagNames: ["privacy"]
        ))
        try store.persist(in: context)

        let reloadedStore = WorkspaceStore()
        try reloadedStore.loadOrCreate(in: context)

        #expect(reloadedStore.preferences.localMemory?.includeInChatContext == false)
        #expect(reloadedStore.preferences.localMemory?.maximumContextMemories == 3)
        #expect(reloadedStore.localMemories.contains {
            $0.id == memory.id
                && $0.category == .project
                && $0.tagNames == ["privacy"]
                && $0.detail.contains("no required login")
        })
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

    private func writeSearchableDOCX(text: String, to fileURL: URL) throws {
        let attributedText = NSAttributedString(string: text)
        let data = try attributedText.data(
            from: NSRange(location: 0, length: attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func webPageAsset(
        title: String,
        url: String,
        capturedAt: Date,
        text: String
    ) -> LibraryAsset {
        LibraryAsset(
            title: title,
            kind: .link,
            sourceURL: URL(string: url)!,
            sourceIdentifier: url,
            summary: "Captured page body.",
            summaryStatus: .ready,
            updatedAt: capturedAt,
            capturedAt: capturedAt,
            transcript: TranscriptRecord(
                status: .available,
                text: text,
                sourceLabel: "Web page capture",
                importedAt: capturedAt,
                updatedAt: capturedAt
            )
        )
    }
}

private actor ToolRequestRecorder {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}

private actor OpenedURLRecorder {
    private(set) var urls: [URL] = []

    func open(_ url: URL) -> Bool {
        urls.append(url)
        return true
    }
}
