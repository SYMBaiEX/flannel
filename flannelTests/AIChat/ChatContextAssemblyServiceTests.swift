//
//  ChatContextAssemblyServiceTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation
import Testing
@testable import flannel

struct ChatContextAssemblyServiceTests {
    @Test("Assembler keeps prioritized local context and estimates budget")
    func assemblerKeepsPrioritizedLocalContextAndEstimatesBudget() {
        let provider = provider(contextWindowTokens: 2_400)
        let packet = retrievalPacket(snippet: "The launch checklist says keep all RAG citations local.")
        let service = ChatContextAssemblyService(reserveOutputTokens: 400)

        let result = service.assemble(
            ChatContextAssemblyInput(
                baseSystemPrompt: "You are Flannel.",
                additionalSystemPrompt: "Prefer local evidence.",
                localMemoryContext: "Local Memories:\n- [Preference] User prefers terse answers.",
                retrievalPacket: packet,
                history: [
                    AssistantMessage(role: .user, text: "Use the launch checklist.")
                ],
                provider: provider
            )
        )

        #expect(result.systemPrompt.contains("You are Flannel."))
        #expect(result.systemPrompt.contains("Prefer local evidence."))
        #expect(result.systemPrompt.contains("Local knowledge retrieval"))
        #expect(result.systemPrompt.contains("Local Memories"))
        #expect(result.history.map(\.role) == [.user])
        #expect(result.estimatedTokenCount > 0)
        #expect(result.promptBudgetTokens == 2_000)
        #expect(!result.wasTruncated)
    }

    @Test("Assembler trims old history before dropping newest user turn")
    func assemblerTrimsOldHistoryBeforeNewestUserTurn() {
        let provider = provider(contextWindowTokens: 900)
        let service = ChatContextAssemblyService(reserveOutputTokens: 300)
        let oldMessages = (0..<12).flatMap { index in
            [
                AssistantMessage(role: .user, text: "old user \(index) " + String(repeating: "context ", count: 36)),
                AssistantMessage(role: .assistant, text: "old assistant \(index) " + String(repeating: "answer ", count: 36))
            ]
        }
        let latest = AssistantMessage(role: .user, text: "latest tiny question")

        let result = service.assemble(
            ChatContextAssemblyInput(
                baseSystemPrompt: "System survives.",
                retrievalPacket: .empty(query: "latest tiny question"),
                history: oldMessages + [latest],
                provider: provider
            )
        )

        #expect(result.history.last?.text == "latest tiny question")
        #expect(result.omittedHistoryMessageCount > 0)
        #expect(result.wasTruncated)
        #expect(result.estimatedTokenCount <= result.promptBudgetTokens + service.estimatedTokenCount(for: latest.text))
    }

    @Test("Subscription CLI providers reserve a larger prompt buffer")
    func subscriptionCLIProvidersReserveLargerPromptBuffer() {
        let apiProvider = provider(accessMode: .apiKey, contextWindowTokens: 4_000)
        let cliProvider = provider(accessMode: .subscriptionCLI, contextWindowTokens: 4_000)
        let service = ChatContextAssemblyService(reserveOutputTokens: 800)

        let apiResult = service.assemble(
            ChatContextAssemblyInput(
                baseSystemPrompt: "System",
                retrievalPacket: .empty(query: "hello"),
                history: [AssistantMessage(role: .user, text: "hello")],
                provider: apiProvider
            )
        )
        let cliResult = service.assemble(
            ChatContextAssemblyInput(
                baseSystemPrompt: "System",
                retrievalPacket: .empty(query: "hello"),
                history: [AssistantMessage(role: .user, text: "hello")],
                provider: cliProvider
            )
        )

        #expect(apiResult.promptBudgetTokens == 3_200)
        #expect(cliResult.promptBudgetTokens == 2_000)
    }

    private func provider(
        accessMode: ProviderAccessMode = .apiKey,
        contextWindowTokens: Int?
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            kind: .openAI,
            accessMode: accessMode,
            privacyScope: accessMode == .subscriptionCLI ? .localCLI : .externalAPI,
            displayName: "OpenAI",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-4.1",
            contextWindowTokens: contextWindowTokens
        )
    }

    private func retrievalPacket(snippet: String) -> LocalKnowledgeRetrievalPacket {
        let chunk = LocalKnowledgeChunk(
            id: "source:0",
            sourceIdentifier: "source",
            knowledgeSourceID: nil,
            sourceTitle: "Launch Notes",
            sourceKind: .workspaceNotes,
            sourceLocation: "flannel://notes",
            ordinal: 0,
            characterRange: 0..<snippet.count,
            text: snippet,
            normalizedText: snippet.lowercased(),
            termFrequencies: [:],
            titleTermFrequencies: [:],
            locationTermFrequencies: [:],
            contentFingerprint: "fingerprint"
        )
        return LocalKnowledgeRetrievalPacket(
            query: "launch",
            results: [
                LocalKnowledgeSearchResult(
                    chunk: chunk,
                    score: 1,
                    matchedTerms: ["launch"],
                    snippet: snippet
                )
            ]
        )
    }
}
