//
//  CommandPaletteModels.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation
import SwiftUI

enum FlannelCommandID: String, CaseIterable, Identifiable, Sendable {
    case newChat
    case importChat
    case openCommandPalette
    case sendMessage
    case stopStreaming
    case comparePrompt
    case runComparison
    case discoverModels
    case toggleLocalOnly
    case openChat
    case openHistory
    case openCompare
    case openModels
    case openKnowledge
    case rebuildQueuedKnowledge
    case rebuildAllKnowledge
    case openTools
    case openAgents
    case openPrompts
    case openSettings
    case focusChat
    case showInspector
    case exportMarkdown
    case exportJSON
    case exportHTML
    case exportPDF
    case exportWorkspaceSnapshot
    case importWorkspaceSnapshot

    var id: String { rawValue }
}

struct FlannelCommandContext: Hashable, Sendable {
    var hasCurrentThread: Bool
    var canSendMessage: Bool
    var isStreaming: Bool
    var isDiscoveringModels: Bool
    var canCompareCurrentPrompt: Bool
    var canRunComparison: Bool
    var localOnlyMode: Bool
    var inspectorVisible: Bool
    var hasKnowledgeSources: Bool
    var hasQueuedKnowledgeSources: Bool

    init(
        hasCurrentThread: Bool,
        canSendMessage: Bool,
        isStreaming: Bool,
        isDiscoveringModels: Bool,
        canCompareCurrentPrompt: Bool,
        canRunComparison: Bool,
        localOnlyMode: Bool,
        inspectorVisible: Bool,
        hasKnowledgeSources: Bool = false,
        hasQueuedKnowledgeSources: Bool = false
    ) {
        self.hasCurrentThread = hasCurrentThread
        self.canSendMessage = canSendMessage
        self.isStreaming = isStreaming
        self.isDiscoveringModels = isDiscoveringModels
        self.canCompareCurrentPrompt = canCompareCurrentPrompt
        self.canRunComparison = canRunComparison
        self.localOnlyMode = localOnlyMode
        self.inspectorVisible = inspectorVisible
        self.hasKnowledgeSources = hasKnowledgeSources
        self.hasQueuedKnowledgeSources = hasQueuedKnowledgeSources
    }

    static let menuFallback = FlannelCommandContext(
        hasCurrentThread: false,
        canSendMessage: false,
        isStreaming: false,
        isDiscoveringModels: false,
        canCompareCurrentPrompt: false,
        canRunComparison: false,
        localOnlyMode: true,
        inspectorVisible: true,
        hasKnowledgeSources: false,
        hasQueuedKnowledgeSources: false
    )
}

struct FlannelCommand: Identifiable, Hashable, Sendable {
    var id: FlannelCommandID
    var title: String
    var subtitle: String
    var category: String
    var systemImage: String
    var keywords: [String]
    var keyEquivalent: String?
    var isEnabled: Bool

    init(
        id: FlannelCommandID,
        title: String,
        subtitle: String,
        category: String,
        systemImage: String,
        keywords: [String] = [],
        keyEquivalent: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.systemImage = systemImage
        self.keywords = keywords
        self.keyEquivalent = keyEquivalent
        self.isEnabled = isEnabled
    }

    func matches(_ query: String) -> Bool {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !terms.isEmpty else { return true }

        let haystack = ([title, subtitle, category] + keywords)
            .joined(separator: " ")

        return terms.allSatisfy { term in
            haystack.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    static func defaultCommands(context: FlannelCommandContext) -> [FlannelCommand] {
        [
            FlannelCommand(
                id: .newChat,
                title: "New Chat",
                subtitle: "Start a fresh local-first assistant thread.",
                category: "Chat",
                systemImage: "plus.bubble",
                keywords: ["thread", "conversation", "assistant"],
                keyEquivalent: "⌘N"
            ),
            FlannelCommand(
                id: .importChat,
                title: "Import Chat",
                subtitle: "Import a local Flannel chat export.",
                category: "Chat",
                systemImage: "square.and.arrow.down",
                keywords: ["restore", "json", "backup", "thread"],
                keyEquivalent: "⇧⌘I"
            ),
            FlannelCommand(
                id: .openCommandPalette,
                title: "Open Command Palette",
                subtitle: "Search every chat, model, privacy, layout, and export command.",
                category: "Chat",
                systemImage: "command",
                keywords: ["shortcuts", "actions", "keyboard", "menu"],
                keyEquivalent: "⌘K"
            ),
            FlannelCommand(
                id: .sendMessage,
                title: "Send Message",
                subtitle: context.canSendMessage ? "Send the composer text and attachments." : "Type a prompt or add an attachment first.",
                category: "Chat",
                systemImage: "paperplane.fill",
                keywords: ["prompt", "composer", "submit"],
                keyEquivalent: "⌘↩",
                isEnabled: context.canSendMessage
            ),
            FlannelCommand(
                id: .stopStreaming,
                title: "Stop Streaming",
                subtitle: context.isStreaming ? "Cancel the active assistant response." : "No response is currently streaming.",
                category: "Chat",
                systemImage: "stop.fill",
                keywords: ["cancel", "halt", "stream"],
                keyEquivalent: "Esc",
                isEnabled: context.isStreaming
            ),
            FlannelCommand(
                id: .comparePrompt,
                title: "Compare Current Prompt",
                subtitle: context.canCompareCurrentPrompt ? "Move the composer prompt into multi-model comparison." : "Type a prompt before sending it to comparison.",
                category: "Models",
                systemImage: "rectangle.split.3x1",
                keywords: ["models", "provider", "side by side", "routing"],
                isEnabled: context.canCompareCurrentPrompt
            ),
            FlannelCommand(
                id: .runComparison,
                title: "Run Model Comparison",
                subtitle: context.canRunComparison ? "Send the comparison prompt to selected providers." : "Comparison needs a prompt and no active run.",
                category: "Models",
                systemImage: "play.circle",
                keywords: ["evaluate", "benchmark", "multi model"],
                isEnabled: context.canRunComparison
            ),
            FlannelCommand(
                id: .discoverModels,
                title: "Discover Local Models",
                subtitle: context.isDiscoveringModels ? "Ollama and LM Studio discovery is already running." : "Refresh Ollama and LM Studio model lists.",
                category: "Models",
                systemImage: "antenna.radiowaves.left.and.right",
                keywords: ["ollama", "lm studio", "local", "refresh"],
                isEnabled: !context.isDiscoveringModels
            ),
            FlannelCommand(
                id: .toggleLocalOnly,
                title: context.localOnlyMode ? "Disable Local-Only Mode" : "Enable Local-Only Mode",
                subtitle: context.localOnlyMode ? "Allow explicitly configured external providers." : "Keep routing on local providers and local CLI modes.",
                category: "Privacy",
                systemImage: context.localOnlyMode ? "lock.open" : "lock",
                keywords: ["privacy", "cloud", "network", "provider"]
            ),
            FlannelCommand(
                id: .openChat,
                title: "Open Chat",
                subtitle: "Return focus to the active conversation.",
                category: "Navigate",
                systemImage: "sparkles",
                keywords: ["home", "assistant"]
            ),
            FlannelCommand(
                id: .openHistory,
                title: "Open Chat History",
                subtitle: "Search, pin, archive, and restore threads.",
                category: "Navigate",
                systemImage: "bubble.left.and.bubble.right",
                keywords: ["threads", "archive", "search"]
            ),
            FlannelCommand(
                id: .openCompare,
                title: "Compare Current Prompt",
                subtitle: "Create a multi-model artifact run in the right rail.",
                category: "Navigate",
                systemImage: "rectangle.split.3x1",
                keywords: ["models", "side by side", "artifacts"]
            ),
            FlannelCommand(
                id: .openModels,
                title: "Open Model Settings",
                subtitle: "Configure BYOK providers, local servers, and routing.",
                category: "Navigate",
                systemImage: "cpu",
                keywords: ["provider", "api", "ollama", "lm studio", "settings"]
            ),
            FlannelCommand(
                id: .openKnowledge,
                title: "Open Knowledge Settings",
                subtitle: "Manage RAG sources, indexes, and retrieval.",
                category: "Navigate",
                systemImage: "books.vertical",
                keywords: ["rag", "index", "documents", "search", "settings"]
            ),
            FlannelCommand(
                id: .rebuildQueuedKnowledge,
                title: "Rebuild Queued Knowledge",
                subtitle: context.hasQueuedKnowledgeSources ? "Index queued, stale, and not-yet-indexed local sources." : "No queued, stale, or unindexed knowledge sources.",
                category: "Knowledge",
                systemImage: "arrow.triangle.2.circlepath",
                keywords: ["rag", "index", "embeddings", "queued", "stale", "refresh", "rebuild"],
                isEnabled: context.hasQueuedKnowledgeSources
            ),
            FlannelCommand(
                id: .rebuildAllKnowledge,
                title: "Rebuild All Knowledge",
                subtitle: context.hasKnowledgeSources ? "Regenerate every local source manifest and embedding index." : "Add a knowledge source before rebuilding indexes.",
                category: "Knowledge",
                systemImage: "shippingbox.and.arrow.backward",
                keywords: ["rag", "index", "embeddings", "all sources", "refresh", "rebuild"],
                isEnabled: context.hasKnowledgeSources
            ),
            FlannelCommand(
                id: .openTools,
                title: "Open Tool Settings",
                subtitle: "Review tool permissions and local action results.",
                category: "Navigate",
                systemImage: "wrench.and.screwdriver",
                keywords: ["permissions", "approval", "agents", "settings"]
            ),
            FlannelCommand(
                id: .openAgents,
                title: "Open Agent Settings",
                subtitle: "Review multi-step workflows, traces, and approval gates.",
                category: "Navigate",
                systemImage: "flowchart",
                keywords: ["workflows", "plans", "runs", "settings"]
            ),
            FlannelCommand(
                id: .openPrompts,
                title: "Open Prompt Settings",
                subtitle: "Edit system profiles, templates, and prompt variables.",
                category: "Navigate",
                systemImage: "text.cursor",
                keywords: ["library", "templates", "system prompt", "settings"]
            ),
            FlannelCommand(
                id: .openSettings,
                title: "Open Settings",
                subtitle: "Adjust privacy, storage, provider defaults, and developer settings.",
                category: "Navigate",
                systemImage: "gearshape",
                keywords: ["preferences", "privacy", "storage"]
            ),
            FlannelCommand(
                id: .focusChat,
                title: "Focus Chat",
                subtitle: "Hide the artifact rail and give the transcript more room.",
                category: "Layout",
                systemImage: "sidebar.right",
                keywords: ["layout", "window", "artifacts"],
                keyEquivalent: "⌘/",
                isEnabled: context.inspectorVisible
            ),
            FlannelCommand(
                id: .showInspector,
                title: "Show Artifacts",
                subtitle: context.inspectorVisible ? "Artifact rail is already visible." : "Reveal comparison runs, provider trace, tools, and context.",
                category: "Layout",
                systemImage: "sidebar.right",
                keywords: ["layout", "context", "right sidebar", "artifacts"],
                isEnabled: !context.inspectorVisible
            ),
            FlannelCommand(
                id: .exportMarkdown,
                title: "Export Chat as Markdown",
                subtitle: "Save the current thread locally as Markdown.",
                category: "Export",
                systemImage: "doc.plaintext",
                keywords: ["share", "backup", "md"],
                isEnabled: context.hasCurrentThread
            ),
            FlannelCommand(
                id: .exportJSON,
                title: "Export Chat as JSON",
                subtitle: "Save the complete current thread payload.",
                category: "Export",
                systemImage: "curlybraces",
                keywords: ["share", "backup", "data"],
                isEnabled: context.hasCurrentThread
            ),
            FlannelCommand(
                id: .exportHTML,
                title: "Export Chat as HTML",
                subtitle: "Save a local readable HTML snapshot.",
                category: "Export",
                systemImage: "globe",
                keywords: ["share", "backup", "web"],
                isEnabled: context.hasCurrentThread
            ),
            FlannelCommand(
                id: .exportPDF,
                title: "Export Chat as PDF",
                subtitle: "Save a local PDF transcript.",
                category: "Export",
                systemImage: "doc.richtext",
                keywords: ["share", "backup", "print"],
                isEnabled: context.hasCurrentThread
            ),
            FlannelCommand(
                id: .exportWorkspaceSnapshot,
                title: "Export Workspace Snapshot",
                subtitle: "Save all local Flannel workspace state as a portable JSON backup.",
                category: "Export",
                systemImage: "externaldrive.badge.timemachine",
                keywords: ["backup", "workspace", "snapshot", "export everything"]
            ),
            FlannelCommand(
                id: .importWorkspaceSnapshot,
                title: "Import Workspace Snapshot",
                subtitle: "Restore a local Flannel workspace backup without importing API key values.",
                category: "Export",
                systemImage: "square.and.arrow.down.on.square",
                keywords: ["backup", "workspace", "snapshot", "restore", "import"]
            )
        ]
    }

    static func defaultCommand(
        _ id: FlannelCommandID,
        context: FlannelCommandContext
    ) -> FlannelCommand? {
        defaultCommands(context: context).first { $0.id == id }
    }
}

struct FlannelCommandRunnerKey: FocusedValueKey {
    typealias Value = (FlannelCommandID) -> Void
}

struct FlannelCommandContextKey: FocusedValueKey {
    typealias Value = FlannelCommandContext
}

extension FocusedValues {
    var flannelCommandRunner: ((FlannelCommandID) -> Void)? {
        get { self[FlannelCommandRunnerKey.self] }
        set { self[FlannelCommandRunnerKey.self] = newValue }
    }

    var flannelCommandContext: FlannelCommandContext? {
        get { self[FlannelCommandContextKey.self] }
        set { self[FlannelCommandContextKey.self] = newValue }
    }
}
