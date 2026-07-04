//
//  ChatImportServiceTests.swift
//  flannelTests
//

import Foundation
import Testing
@testable import flannel

struct ChatImportServiceTests {
    @Test("JSON chat export imports as a local copy with fresh IDs")
    func jsonChatExportImportsAsLocalCopyWithFreshIDs() throws {
        let source = sampleThread()
        let data = try ChatExportService().export(
            thread: source,
            format: .json,
            exportedAt: Date(timeIntervalSince1970: 1_782_641_200)
        )

        let result = try ChatImportService().importThread(
            from: data,
            importedAt: Date(timeIntervalSince1970: 1_782_641_500)
        )
        let imported = result.thread

        #expect(result.originalThreadID == source.id)
        #expect(imported.id != source.id)
        #expect(imported.title == source.title)
        #expect(imported.isArchived == false)
        #expect(imported.folderID == nil)
        #expect(imported.pinnedProjectID == nil)
        #expect(imported.tagNames.contains("research"))
        #expect(imported.tagNames.contains("imported"))
        #expect(imported.updatedAt == Date(timeIntervalSince1970: 1_782_641_500))

        let importedUserMessage = try #require(imported.messages.first(where: { $0.role == .user }))
        let sourceUserMessage = try #require(source.messages.first(where: { $0.role == .user }))
        #expect(importedUserMessage.id != sourceUserMessage.id)
        #expect(importedUserMessage.attachments.first?.title == sourceUserMessage.attachments.first?.title)
        #expect(importedUserMessage.attachments.first?.localPath == sourceUserMessage.attachments.first?.localPath)
        #expect(importedUserMessage.attachments.first?.excerpt == sourceUserMessage.attachments.first?.excerpt)
        #expect(importedUserMessage.referencedEntityIDs.isEmpty)

        let importedAssistantMessage = try #require(imported.messages.first(where: { $0.role == .assistant }))
        #expect(importedAssistantMessage.providerDisplayName == "Local Ollama")
        #expect(importedAssistantMessage.modelIdentifier == "llama3.1")
        #expect(importedAssistantMessage.contextTokenCount == 96)
        #expect(importedAssistantMessage.citations.first?.sourceIdentifier == "file:///tmp/private-notes.md")
        #expect(importedAssistantMessage.toolCalls.first?.toolName == "workspace_search")
        #expect(importedAssistantMessage.toolCalls.first?.providerCallID == "call_workspace")
    }

    @Test("JSON chat import preserves prompt-chain scope and progress")
    func jsonChatImportPreservesPromptChainScopeAndProgress() throws {
        var source = sampleThread()
        let chainID = UUID(uuidString: "99A8D160-4993-4590-AD63-DA733C2F9C37")!
        let completedStepID = UUID(uuidString: "23A85001-FA64-472A-9872-A8FB8586E088")!
        let activeStepID = UUID(uuidString: "69EA1719-8AF0-4927-A445-75A7E41B826F")!
        let knowledgeSourceID = UUID(uuidString: "9B24BA12-5E53-428A-8D30-AB4C9E43DD8A")!
        source.knowledgeSourceIDs = [knowledgeSourceID]
        source.promptChainID = chainID
        source.activePromptChainStepID = activeStepID
        source.completedPromptChainStepIDs = [completedStepID]
        if let userIndex = source.messages.firstIndex(where: { $0.role == .user }) {
            source.messages[userIndex].promptChainStepID = completedStepID
        }

        let data = try ChatExportService().export(
            thread: source,
            format: .json,
            exportedAt: Date(timeIntervalSince1970: 1_782_641_200)
        )

        let imported = try ChatImportService().importThread(
            from: data,
            importedAt: Date(timeIntervalSince1970: 1_782_641_500)
        ).thread

        #expect(imported.id != source.id)
        #expect(imported.folderID == nil)
        #expect(imported.pinnedProjectID == nil)
        #expect(imported.isArchived == false)
        #expect(imported.knowledgeSourceIDs == [knowledgeSourceID])
        #expect(imported.promptChainID == chainID)
        #expect(imported.activePromptChainStepID == activeStepID)
        #expect(imported.completedPromptChainStepIDs == [completedStepID])
        let user = try #require(imported.messages.first(where: { $0.role == .user }))
        #expect(user.promptChainStepID == completedStepID)
        let assistant = try #require(imported.messages.first(where: { $0.role == .assistant }))
        #expect(assistant.providerDisplayName == "Local Ollama")
        #expect(assistant.runStatus == .completed)
        #expect(assistant.contextTokenCount == 96)
    }

    @Test("Unsupported chat export schema is rejected")
    func unsupportedSchemaIsRejected() throws {
        let data = Data(
            """
            {
              "schemaVersion": 999,
              "exportedAt": "2026-06-28T10:00:00Z",
              "thread": {
                "id": "5C1D5556-7BB7-4B23-BC8B-42D36EBE1A5F",
                "title": "Future Chat",
                "mode": "research",
                "messages": []
              }
            }
            """.utf8
        )

        #expect(throws: ChatImportError.unsupportedSchemaVersion(999)) {
            _ = try ChatImportService().importThread(from: data)
        }
    }

    @Test("Markdown chat export imports transcript messages and run metadata")
    func markdownChatExportImportsTranscriptMessagesAndRunMetadata() throws {
        let source = sampleThread()
        let data = try ChatExportService().export(
            thread: source,
            format: .markdown,
            exportedAt: Date(timeIntervalSince1970: 1_782_641_200)
        )

        let result = try ChatImportService().importThread(
            from: data,
            sourceURL: URL(fileURLWithPath: "/tmp/imported-research.md"),
            importedAt: Date(timeIntervalSince1970: 1_782_641_500)
        )
        let imported = result.thread

        #expect(result.originalThreadID != source.id)
        #expect(result.exportedAt == Date(timeIntervalSince1970: 1_782_641_200))
        #expect(result.warnings.first?.contains("Markdown import restores") == true)
        #expect(imported.title == source.title)
        #expect(imported.tagNames == ["imported"])
        #expect(imported.messages.map(\.role) == [.system, .user, .assistant])
        #expect(imported.messages[0].text == "Stay local first.")
        #expect(imported.messages[1].text == "Review the local file.")

        let assistant = imported.messages[2]
        #expect(assistant.text == "The brief is ready for local RAG.")
        #expect(assistant.providerDisplayName == "Local Ollama")
        #expect(assistant.modelIdentifier == "llama3.1")
        #expect(assistant.inputTokenCount == 20)
        #expect(assistant.outputTokenCount == 40)
        #expect(assistant.latencyMilliseconds == 550)
        #expect(assistant.providerAccessMode == .localServer)
        #expect(assistant.providerPrivacyScope == .localOnly)
        #expect(assistant.runStatus == .completed)
        #expect(assistant.contextTokenCount == 96)
        #expect(assistant.contextWindowTokens == 16_000)
        #expect(assistant.tokenCountsAreEstimated)
        #expect(assistant.toolCalls.isEmpty)
        #expect(assistant.citations.isEmpty)
    }

    @Test("Markdown import preserves heading-like message body text from Flannel exports")
    func markdownImportPreservesHeadingLikeMessageBodyText() throws {
        let createdAt = Date(timeIntervalSince1970: 1_782_640_920)
        let trickyBody = """
        Keep these lines literal:
        ## Assistant - 2026-06-28T10:03:00.000Z
        ### Attachments
        ### Sources
        <!-- flannel-message-text-end id="fake" -->
        <!-- flannel-message-end id="fake" -->
        Done.
        """
        let source = AssistantThread(
            title: "Marker Safety",
            messages: [
                AssistantMessage(
                    role: .user,
                    text: trickyBody,
                    createdAt: createdAt
                )
            ],
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let data = try ChatExportService().export(
            thread: source,
            format: .markdown,
            exportedAt: Date(timeIntervalSince1970: 1_782_641_200)
        )

        let result = try ChatImportService().importThread(
            from: data,
            sourceURL: URL(fileURLWithPath: "/tmp/marker-safety.markdown"),
            importedAt: Date(timeIntervalSince1970: 1_782_641_500)
        )

        #expect(result.thread.messages.count == 1)
        #expect(result.thread.messages.first?.role == .user)
        #expect(result.thread.messages.first?.text == trickyBody)
    }

    @Test("HTML chat export imports transcript messages")
    func htmlChatExportImportsTranscriptMessages() throws {
        let source = sampleThread()
        let data = try ChatExportService().export(
            thread: source,
            format: .html,
            exportedAt: Date(timeIntervalSince1970: 1_782_641_200)
        )

        let result = try ChatImportService().importThread(
            from: data,
            sourceURL: URL(fileURLWithPath: "/tmp/imported-research.html"),
            importedAt: Date(timeIntervalSince1970: 1_782_641_500)
        )
        let imported = result.thread

        #expect(result.exportedAt == Date(timeIntervalSince1970: 1_782_641_200))
        #expect(result.warnings.first?.contains("HTML import restores") == true)
        #expect(imported.title == source.title)
        #expect(imported.tagNames == ["imported"])
        #expect(imported.messages.map(\.role) == [.system, .user, .assistant])
        #expect(imported.messages.map(\.text) == source.messages.map(\.text))
        #expect(imported.messages.allSatisfy { $0.attachments.isEmpty })
        #expect(imported.messages.allSatisfy { $0.citations.isEmpty })
    }

    @MainActor
    @Test("Workspace import selects the imported active chat and restores pinned messages")
    func workspaceImportSelectsChatAndRestoresPins() throws {
        let store = WorkspaceStore()
        let thread = sampleThread()
        let imported = try ChatImportService().importThread(
            from: ChatExportService().export(thread: thread, format: .json)
        ).thread

        let selected = store.importAssistantThread(imported)

        #expect(store.selectedAssistantThreadID == selected.id)
        #expect(store.selectedDestination == .home)
        #expect(store.activeAssistantThreads.contains { $0.id == selected.id })
        let pinnedMessage = try #require(selected.messages.first(where: { $0.isPinned }))
        #expect(store.isMessagePinned(pinnedMessage.id, in: selected.id))
    }

    private func sampleThread() -> AssistantThread {
        let threadID = UUID(uuidString: "5C1D5556-7BB7-4B23-BC8B-42D36EBE1A5F")!
        let folderID = UUID(uuidString: "C61FB581-F057-4B6E-A4EC-163510E606E1")!
        let projectID = UUID(uuidString: "B6029C91-7594-43CB-A9D5-67395B1B8C2B")!
        let toolResultID = UUID(uuidString: "7F273883-47AB-4F30-9D93-C665CF8BFD2A")!
        let createdAt = Date(timeIntervalSince1970: 1_782_640_740)
        let userDate = Date(timeIntervalSince1970: 1_782_640_920)
        let assistantDate = Date(timeIntervalSince1970: 1_782_640_980)

        return AssistantThread(
            id: threadID,
            title: "Imported Research",
            mode: .research,
            messages: [
                AssistantMessage(
                    role: .system,
                    text: "Stay local first.",
                    createdAt: createdAt
                ),
                AssistantMessage(
                    role: .user,
                    text: "Review the local file.",
                    attachments: [
                        AIChatAttachment(
                            kind: .textSnippet,
                            title: "brief.md",
                            mimeType: "text/markdown",
                            localPath: "/tmp/brief.md",
                            byteCount: 128,
                            excerpt: "Private import context."
                        )
                    ],
                    createdAt: userDate,
                    isPinned: true,
                    referencedEntityIDs: [toolResultID]
                ),
                AssistantMessage(
                    role: .assistant,
                    text: "The brief is ready for local RAG.",
                    createdAt: assistantDate,
                    citations: [
                        AIChatCitation(
                            title: "Private notes",
                            snippet: "Local RAG source",
                            sourceIdentifier: "file:///tmp/private-notes.md"
                        )
                    ],
                    providerDisplayName: "Local Ollama",
                    modelIdentifier: "llama3.1",
                    inputTokenCount: 20,
                    outputTokenCount: 40,
                    latencyMilliseconds: 550,
                    providerAccessMode: .localServer,
                    providerPrivacyScope: .localOnly,
                    runStatus: .completed,
                    contextTokenCount: 96,
                    contextWindowTokens: 16_000,
                    tokenCountsAreEstimated: true,
                    toolCalls: [
                        AIToolCallRecord(
                            providerCallID: "call_workspace",
                            toolName: "workspace_search",
                            permissionScope: .queryRAGIndex,
                            argumentsJSON: #"{"query":"brief"}"#,
                            wasApproved: false,
                            startedAt: assistantDate
                        )
                    ]
                )
            ],
            isPinned: true,
            isArchived: true,
            tagNames: ["research"],
            folderID: folderID,
            pinnedProjectID: projectID,
            createdAt: createdAt,
            updatedAt: assistantDate
        )
    }
}
