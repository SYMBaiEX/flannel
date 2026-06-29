//
//  ChatTranscriptSearchServiceTests.swift
//  flannelTests
//

import Foundation
import Testing
@testable import flannel

struct ChatTranscriptSearchServiceTests {
    @Test("Current chat search matches visible message text in transcript order")
    func matchesVisibleMessageTextInTranscriptOrder() {
        let firstID = UUID()
        let secondID = UUID()
        let messages = [
            AssistantMessage(role: .system, text: "Hidden needle"),
            AssistantMessage(id: firstID, role: .user, text: "Find the local model needle."),
            AssistantMessage(id: secondID, role: .assistant, text: "The Needle appears again with citations.")
        ]

        let matches = ChatTranscriptSearchService.matches(in: messages, query: "needle")

        #expect(matches.map(\.messageID) == [firstID, secondID])
        #expect(matches.allSatisfy { $0.matchKind == .messageText })
        #expect(matches.contains { $0.preview.localizedCaseInsensitiveContains("local model needle") })
    }

    @Test("Current chat search includes attachments and citations")
    func matchesAttachmentsAndCitations() {
        let userID = UUID()
        let assistantID = UUID()
        let messages = [
            AssistantMessage(
                id: userID,
                role: .user,
                text: "Review the files.",
                attachments: [
                    AIChatAttachment(
                        kind: .document,
                        title: "launch-brief.md",
                        mimeType: "text/markdown",
                        localPath: "/tmp/launch-brief.md",
                        excerpt: "Private RAG source for LaunchSignal."
                    )
                ]
            ),
            AssistantMessage(
                id: assistantID,
                role: .assistant,
                text: "I found the supporting source.",
                citations: [
                    AIChatCitation(
                        title: "Local notes",
                        snippet: "LaunchSignal risk register",
                        sourceIdentifier: "file:///tmp/notes.md"
                    )
                ]
            )
        ]

        let attachmentMatches = ChatTranscriptSearchService.matches(in: messages, query: "RAG source")
        let citationMatches = ChatTranscriptSearchService.matches(in: messages, query: "risk register")

        #expect(attachmentMatches.first?.messageID == userID)
        #expect(attachmentMatches.first?.matchKind == .attachment)
        #expect(citationMatches.first?.messageID == assistantID)
        #expect(citationMatches.first?.matchKind == .citation)
    }

    @Test("Current chat search trims query and honors match limit")
    func trimsQueryAndHonorsLimit() {
        let messages = [
            AssistantMessage(role: .user, text: "alpha alpha alpha"),
            AssistantMessage(role: .assistant, text: "alpha alpha")
        ]

        let matches = ChatTranscriptSearchService.matches(in: messages, query: " alpha ", limit: 3)

        #expect(matches.count == 3)
        #expect(matches.map(\.role) == [.user, .user, .user])
    }
}
