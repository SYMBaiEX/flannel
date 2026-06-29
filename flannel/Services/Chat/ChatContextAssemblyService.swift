//
//  ChatContextAssemblyService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation

nonisolated struct ChatContextAssemblyInput: Sendable {
    var baseSystemPrompt: String
    var additionalSystemPrompt: String?
    var localMemoryContext: String?
    var retrievalPacket: LocalKnowledgeRetrievalPacket
    var history: [AssistantMessage]
    var provider: ProviderConfiguration

    init(
        baseSystemPrompt: String,
        additionalSystemPrompt: String? = nil,
        localMemoryContext: String? = nil,
        retrievalPacket: LocalKnowledgeRetrievalPacket,
        history: [AssistantMessage],
        provider: ProviderConfiguration
    ) {
        self.baseSystemPrompt = baseSystemPrompt
        self.additionalSystemPrompt = additionalSystemPrompt
        self.localMemoryContext = localMemoryContext
        self.retrievalPacket = retrievalPacket
        self.history = history
        self.provider = provider
    }
}

nonisolated struct ChatContextAssemblyResult: Sendable, Hashable {
    var systemPrompt: String
    var history: [AssistantMessage]
    var estimatedTokenCount: Int
    var contextWindowTokens: Int?
    var promptBudgetTokens: Int
    var omittedHistoryMessageCount: Int
    var omittedContextSectionCount: Int

    var wasTruncated: Bool {
        omittedHistoryMessageCount > 0 || omittedContextSectionCount > 0
    }
}

nonisolated struct ChatContextAssemblyService: Sendable {
    private struct ContextSection: Sendable, Hashable {
        var title: String
        var text: String
        var priority: Int
    }

    var defaultContextWindowTokens: Int
    var reserveOutputTokens: Int
    var maximumPromptBudgetTokens: Int

    init(
        defaultContextWindowTokens: Int = 16_000,
        reserveOutputTokens: Int = 1_500,
        maximumPromptBudgetTokens: Int = 56_000
    ) {
        self.defaultContextWindowTokens = defaultContextWindowTokens
        self.reserveOutputTokens = reserveOutputTokens
        self.maximumPromptBudgetTokens = maximumPromptBudgetTokens
    }

    func assemble(_ input: ChatContextAssemblyInput) -> ChatContextAssemblyResult {
        let contextWindow = max(1, input.provider.contextWindowTokens ?? defaultContextWindowTokens)
        let promptBudget = promptBudgetTokens(for: input.provider, contextWindow: contextWindow)
        let sections = prioritizedSections(from: input)

        var selectedSections: [ContextSection] = []
        var usedTokens = 0
        var omittedContextSectionCount = 0

        for section in sections {
            let sectionTokens = estimatedTokenCount(for: section.text)
            if section.priority == 0 || usedTokens + sectionTokens <= promptBudget {
                selectedSections.append(section)
                usedTokens += sectionTokens
            } else {
                omittedContextSectionCount += 1
            }
        }

        let remainingBudget = max(promptBudget - usedTokens, max(256, promptBudget / 5))
        let selectedHistory = selectHistory(
            input.history,
            provider: input.provider,
            budgetTokens: remainingBudget
        )
        let historyTokenCount = selectedHistory.reduce(0) { partialResult, message in
            partialResult + estimatedTokenCount(for: message.textWithAttachmentPromptContext)
        }

        let systemPrompt = selectedSections
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return ChatContextAssemblyResult(
            systemPrompt: systemPrompt,
            history: selectedHistory,
            estimatedTokenCount: usedTokens + historyTokenCount,
            contextWindowTokens: input.provider.contextWindowTokens,
            promptBudgetTokens: promptBudget,
            omittedHistoryMessageCount: max(0, input.history.count - selectedHistory.count),
            omittedContextSectionCount: omittedContextSectionCount
        )
    }

    func estimatedTokenCount(for text: String) -> Int {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard characterCount > 0 else { return 0 }
        return max(1, Int(ceil(Double(characterCount) / 4.0)))
    }

    private func promptBudgetTokens(for provider: ProviderConfiguration, contextWindow: Int) -> Int {
        let transportReserve = provider.accessMode == .subscriptionCLI
            ? max(reserveOutputTokens, 2_000)
            : reserveOutputTokens
        let rawBudget = max(512, contextWindow - transportReserve)
        return min(rawBudget, maximumPromptBudgetTokens)
    }

    private func prioritizedSections(from input: ChatContextAssemblyInput) -> [ContextSection] {
        [
            ContextSection(title: "System", text: input.baseSystemPrompt, priority: 0),
            ContextSection(title: "Additional system", text: input.additionalSystemPrompt ?? "", priority: 1),
            ContextSection(title: "Local retrieval", text: input.retrievalPacket.promptContext, priority: 2),
            ContextSection(title: "Local memory", text: input.localMemoryContext ?? "", priority: 3)
        ]
        .map { section in
            ContextSection(
                title: section.title,
                text: section.text.trimmingCharacters(in: .whitespacesAndNewlines),
                priority: section.priority
            )
        }
        .filter { !$0.text.isEmpty }
        .sorted {
            if $0.priority == $1.priority {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.priority < $1.priority
        }
    }

    private func selectHistory(
        _ messages: [AssistantMessage],
        provider: ProviderConfiguration,
        budgetTokens: Int
    ) -> [AssistantMessage] {
        let maxMessages = provider.accessMode == .subscriptionCLI ? 20 : 36
        var selected: [AssistantMessage] = []
        var usedTokens = 0

        for message in messages.reversed() {
            let content = message.textWithAttachmentPromptContext.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }

            let messageTokens = estimatedTokenCount(for: content)
            let mustKeepLatestUserMessage = selected.isEmpty && message.role == .user
            if !mustKeepLatestUserMessage,
               selected.count >= maxMessages || usedTokens + messageTokens > budgetTokens {
                break
            }

            selected.append(message)
            usedTokens += messageTokens
        }

        return selected.reversed()
    }
}
