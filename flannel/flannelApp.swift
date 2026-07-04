//
//  flannelApp.swift
//  flannel
//
//  Created by SYMBiEX on 6/28/26.
//

import SwiftUI
import SwiftData

@main
struct flannelApp: App {
    @State private var store: WorkspaceStore
    private let sharedModelContainer: ModelContainer

    init() {
        let bootstrap = Self.makeModelContainer()
        _store = State(initialValue: WorkspaceStore(initialPersistenceIssue: bootstrap.issue))
        sharedModelContainer = bootstrap.container
    }

    private static func makeModelContainer() -> (container: ModelContainer, issue: WorkspacePersistenceIssue?) {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return (try ModelContainer(for: schema, configurations: [modelConfiguration]), nil)
        } catch {
            let issue = WorkspacePersistenceIssue(
                operation: .containerSetup,
                error: error,
                recoverySuggestion: "Flannel is running with temporary in-memory storage. Export anything important before quitting, then check disk space and app data permissions."
            )
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return (try ModelContainer(for: schema, configurations: [fallbackConfiguration]), issue)
            } catch {
                preconditionFailure("Could not create a SwiftData container, including the in-memory fallback: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            FlannelAppCommands()
        }
    }
}

private struct FlannelAppCommands: Commands {
    @FocusedValue(\.flannelCommandRunner) private var runFocusedCommand
    @FocusedValue(\.flannelCommandContext) private var focusedCommandContext

    private var context: FlannelCommandContext {
        focusedCommandContext ?? .menuFallback
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                run(.openSettings)
            }
            .disabled(runFocusedCommand == nil || FlannelCommand.defaultCommand(.openSettings, context: context)?.isEnabled != true)
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandMenu("Chat") {
            commandButton(.newChat)
                .keyboardShortcut("n", modifiers: [.command])

            commandButton(.importChat)
                .keyboardShortcut("i", modifiers: [.command, .shift])

            commandButton(.openCommandPalette)
                .keyboardShortcut("k", modifiers: [.command])
            commandButton(.findInChat)
                .keyboardShortcut("f", modifiers: [.command])
            commandButton(.continuePromptChainStep)
                .keyboardShortcut("]", modifiers: [.command, .shift])

            Divider()

            commandButton(.openChat)
            commandButton(.openHistory)
        }

        CommandMenu("Models") {
            commandButton(.discoverModels)
            commandButton(.comparePrompt)
            commandButton(.runComparison)

            Divider()

            routingPolicyButton(.selectedProvider)
            routingPolicyButton(.localFirst)
            routingPolicyButton(.bestAvailable)
            routingPolicyButton(.cheapest)
            routingPolicyButton(.fastest)

            Divider()

            commandButton(.openCompare)
            commandButton(.openModels)
        }

        CommandMenu("Knowledge") {
            commandButton(.openKnowledge)

            Divider()

            commandButton(.rebuildQueuedKnowledge)
            commandButton(.rebuildAllKnowledge)
        }

        CommandMenu("Privacy") {
            commandButton(.toggleLocalOnly)
                .keyboardShortcut("l", modifiers: [.command, .option])
            commandButton(.toggleCloudProviders)
                .keyboardShortcut("c", modifiers: [.command, .option])
        }

        CommandMenu("Artifacts") {
            if context.inspectorVisible {
                commandButton(.focusChat)
                    .keyboardShortcut("/", modifiers: [.command])
            } else {
                commandButton(.showInspector)
                    .keyboardShortcut("/", modifiers: [.command])
            }
        }

        CommandMenu("Export") {
            commandButton(.exportMarkdown)
            commandButton(.exportJSON)
            commandButton(.exportHTML)
            commandButton(.exportPDF)

            Divider()

            commandButton(.exportWorkspaceSnapshot)
            commandButton(.importWorkspaceSnapshot)
        }
    }

    private func commandButton(_ id: FlannelCommandID) -> some View {
        let command = FlannelCommand.defaultCommand(id, context: context)

        return Button(command?.title ?? fallbackTitle(for: id)) {
            run(id)
        }
        .disabled(runFocusedCommand == nil || command?.isEnabled != true)
    }

    private func routingPolicyButton(_ policy: ProviderRoutingPolicy) -> some View {
        let id = FlannelCommandID.routingCommandID(for: policy)
        let command = FlannelCommand.defaultCommand(id, context: context)

        return Button {
            run(id)
        } label: {
            Label(
                command?.title ?? policy.title,
                systemImage: context.providerRoutingPolicy == policy ? "checkmark" : policy.icon
            )
        }
        .disabled(runFocusedCommand == nil || command?.isEnabled != true)
    }

    private func run(_ id: FlannelCommandID) {
        guard let command = FlannelCommand.defaultCommand(id, context: context),
              command.isEnabled else {
            return
        }
        runFocusedCommand?(id)
    }

    private func fallbackTitle(for id: FlannelCommandID) -> String {
        id.rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }
}
