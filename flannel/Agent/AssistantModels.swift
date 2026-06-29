//
//  AssistantModels.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

struct AssistantContextChip: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var detail: String
    var symbolName: String
    var isSelected: Bool
}

struct AssistantSuggestedAction: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var prompt: String
    var symbolName: String
    var isProminent: Bool = false
}

enum AssistantTraceState: String, Sendable {
    case pending
    case running
    case completed
    case failed

    var label: String {
        switch self {
        case .pending:
            return "Pending"
        case .running:
            return "Running"
        case .completed:
            return "Done"
        case .failed:
            return "Needs Attention"
        }
    }

    var symbolName: String {
        switch self {
        case .pending:
            return "clock"
        case .running:
            return "bolt.circle"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
}

struct AssistantTraceStep: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var detail: String
    var state: AssistantTraceState
}

enum AssistantProviderAvailability: String, Equatable, Sendable {
    case localOnly
    case configured
    case unavailable
}

struct AssistantProviderStatus: Equatable, Sendable {
    var availability: AssistantProviderAvailability
    var badge: String
    var detail: String
    var requestWasSent: Bool
}

struct AssistantToolResult: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var output: String
}

struct AssistantRuntimeRequest: Sendable {
    var prompt: String
    var context: AssistantContextSnapshot
    var selectedChips: [AssistantContextChip]
    var provider: ProviderConfiguration?

    init(
        prompt: String,
        context: AssistantContextSnapshot,
        selectedChips: [AssistantContextChip],
        provider: ProviderConfiguration?
    ) {
        self.prompt = prompt
        self.context = context
        self.selectedChips = selectedChips
        self.provider = provider
    }
}

struct AssistantRunResult: Sendable {
    var responseText: String
    var toolActivity: [AssistantTraceStep]
    var usedFallback: Bool
    var providerBadge: String
    var note: String
    var providerStatus: AssistantProviderStatus
    var executedTools: [AssistantToolResult]
}

extension Array where Element == AssistantSuggestedAction {
    static let defaultActions: [AssistantSuggestedAction] = [
        AssistantSuggestedAction(
            id: "summarize-workspace",
            title: "Summarize Workspace",
            prompt: "Summarize the current workspace state and tell me what the assistant should prioritize next.",
            symbolName: "rectangle.text.magnifyingglass",
            isProminent: true
        ),
        AssistantSuggestedAction(
            id: "draft-tool-contract",
            title: "Define Tool Contract",
            prompt: "Draft a tool contract for a local action in Flannel. Include inputs, outputs, fallback behavior, and UI status handling.",
            symbolName: "hammer"
        ),
        AssistantSuggestedAction(
            id: "inspect-provider",
            title: "Inspect Provider",
            prompt: "Inspect the active provider state and tell me exactly what is configured, what is unavailable, and whether a real request can run.",
            symbolName: "desktopcomputer"
        ),
        AssistantSuggestedAction(
            id: "inspect-draft",
            title: "Review Selected Draft",
            prompt: "Review the selected draft context and suggest one refinement plus one follow-up action.",
            symbolName: "doc.text"
        ),
    ]
}
