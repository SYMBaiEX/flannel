//
//  WorkspaceAssistantStore.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class WorkspaceAssistantStore {
    var draft = ""
    var contextChips: [AssistantContextChip] = []
    var suggestedActions = [AssistantSuggestedAction].defaultActions
    var toolActivity: [AssistantTraceStep] = []
    var transcript: [AssistantMessage] = []
    var statusLine = "Loading workspace..."
    var isRunning = false
    var lastProviderNote = "No assistant run yet."

    private let workspaceStore = WorkspaceStore()
    private let runtime: AssistantRuntime
    private var modelContext: ModelContext?
    private var hasLoaded = false

    init(runtime: AssistantRuntime = AssistantRuntime()) {
        self.runtime = runtime
    }

    var availableProviders: [ProviderConfiguration] {
        workspaceStore.providerConfigurations
    }

    var activeProviderID: UUID? {
        workspaceStore.activeProvider?.id
    }

    var activeProvider: ProviderConfiguration? {
        workspaceStore.activeProvider
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRunning
    }

    var selectedChipCount: Int {
        contextChips.filter(\.isSelected).count
    }

    func loadIfNeeded(modelContext: ModelContext) async {
        guard !hasLoaded else { return }

        self.modelContext = modelContext

        do {
            try workspaceStore.loadOrCreate(in: modelContext)
            syncFromWorkspace()
            statusLine = "Ready for local assistant runs."
            hasLoaded = true
        } catch {
            statusLine = "Failed to load workspace."
            transcript = [
                AssistantMessage(
                    role: .system,
                    text: "Workspace loading failed: \(error.localizedDescription)"
                )
            ]
        }
    }

    func toggleChip(id: String) {
        guard let index = contextChips.firstIndex(where: { $0.id == id }) else {
            return
        }

        contextChips[index].isSelected.toggle()
    }

    func runSuggestedAction(_ action: AssistantSuggestedAction) async {
        draft = action.prompt
        await send()
    }

    func selectProvider(_ providerID: UUID) {
        workspaceStore.preferences.preferredProviderID = providerID
        refreshContextChips()
        persistWorkspace()
    }

    func endpointBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.activeProvider?.endpoint ?? ""
            },
            set: { [weak self] newValue in
                self?.mutateActiveProvider { $0.endpoint = newValue }
            }
        )
    }

    func modelBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.activeProvider?.modelIdentifier ?? ""
            },
            set: { [weak self] newValue in
                self?.mutateActiveProvider { $0.modelIdentifier = newValue }
            }
        )
    }

    func secretReferenceBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.activeProvider?.secretReference ?? ""
            },
            set: { [weak self] newValue in
                self?.mutateActiveProvider { provider in
                    provider.secretReference = newValue.isEmpty ? nil : newValue
                }
            }
        )
    }

    func send() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            statusLine = "Add a prompt before sending."
            return
        }

        workspaceStore.appendAssistantMessage(prompt, role: .user)
        syncTranscript()

        draft = ""
        isRunning = true
        statusLine = "Running local assistant tools..."

        do {
            let result = try runtime.run(
                AssistantRuntimeRequest(
                    prompt: prompt,
                    context: workspaceStore.assistantContext,
                    selectedChips: contextChips.filter(\.isSelected),
                    provider: activeProvider
                )
            )

            toolActivity = result.toolActivity
            workspaceStore.appendAssistantMessage(result.responseText, role: .assistant)
            syncTranscript()
            lastProviderNote = "\(result.providerBadge): \(result.note)"
            switch result.providerStatus.availability {
            case .localOnly:
                statusLine = "Completed with local-only tools."
            case .configured:
                statusLine = "Completed locally with a configured provider."
            case .unavailable:
                statusLine = "Completed locally. Provider needs attention."
            }
            persistWorkspace()
        } catch {
            toolActivity = [
                AssistantTraceStep(
                    id: "assemble-response",
                    title: "Assemble response",
                    detail: error.localizedDescription,
                    state: .failed
                )
            ]
            workspaceStore.appendAssistantMessage(
                "The assistant request did not run. \(error.localizedDescription)",
                role: .assistant
            )
            syncTranscript()
            statusLine = "Request failed before response generation."
            lastProviderNote = error.localizedDescription
        }

        isRunning = false
    }

    private func syncFromWorkspace() {
        syncTranscript()
        refreshContextChips()

        if transcript.isEmpty {
            workspaceStore.appendAssistantMessage(
                "Flannel Assistant runs local workspace tools against the current context. Main chat owns live model streaming; this secondary path records provider status without sending model requests.",
                role: .system
            )
            syncTranscript()
        }
    }

    private func syncTranscript() {
        transcript = workspaceStore.currentAssistantThread?.messages ?? []
    }

    private func refreshContextChips() {
        let snapshot = workspaceStore.assistantContext
        let selectedIDs = Set(contextChips.filter(\.isSelected).map(\.id))

        contextChips = buildContextChips(from: snapshot).map { chip in
            var chip = chip
            chip.isSelected = selectedIDs.isEmpty
                ? defaultSelectedChipIDs.contains(chip.id)
                : selectedIDs.contains(chip.id)
            return chip
        }
    }

    private var defaultSelectedChipIDs: Set<String> {
        ["destination", "provider", "project", "draft", "thread"]
    }

    private func buildContextChips(from snapshot: AssistantContextSnapshot) -> [AssistantContextChip] {
        var chips = [
            AssistantContextChip(
                id: "destination",
                title: "Destination",
                detail: snapshot.destination.title,
                symbolName: "point.topleft.down.curvedto.point.bottomright.up",
                isSelected: true
            )
        ]

        if let provider = snapshot.provider {
            chips.append(
                AssistantContextChip(
                    id: "provider",
                    title: "Provider",
                    detail: "\(provider.displayName) • \(provider.modelIdentifier)",
                    symbolName: provider.kind == .ollama ? "desktopcomputer" : "network",
                    isSelected: true
                )
            )
        }

        if let project = snapshot.project {
            chips.append(
                AssistantContextChip(
                    id: "project",
                    title: "Project",
                    detail: project.title,
                    symbolName: "folder",
                    isSelected: true
                )
            )
        }

        if let draft = snapshot.draft {
            chips.append(
                AssistantContextChip(
                    id: "draft",
                    title: "Draft",
                    detail: draft.title,
                    symbolName: "doc.text",
                    isSelected: true
                )
            )
        }

        if let asset = snapshot.libraryAsset {
            chips.append(
                AssistantContextChip(
                    id: "asset",
                    title: "Library Asset",
                    detail: asset.title,
                    symbolName: "books.vertical",
                    isSelected: false
                )
            )
        }

        if let calendarEntry = snapshot.calendarEntry {
            chips.append(
                AssistantContextChip(
                    id: "calendar",
                    title: "Calendar",
                    detail: calendarEntry.title,
                    symbolName: "calendar",
                    isSelected: false
                )
            )
        }

        if let thread = snapshot.thread {
            chips.append(
                AssistantContextChip(
                    id: "thread",
                    title: "Thread",
                    detail: thread.title,
                    symbolName: "bubble.left.and.bubble.right",
                    isSelected: true
                )
            )
        }

        return chips
    }

    private func mutateActiveProvider(_ mutate: (inout ProviderConfiguration) -> Void) {
        guard let activeProvider else { return }
        guard let index = workspaceStore.providerConfigurations.firstIndex(where: { $0.id == activeProvider.id }) else {
            return
        }

        var provider = workspaceStore.providerConfigurations[index]
        mutate(&provider)
        workspaceStore.providerConfigurations[index] = provider
        refreshContextChips()
        persistWorkspace()
    }

    private func persistWorkspace() {
        guard let modelContext else { return }
        try? workspaceStore.persist(in: modelContext)
    }
}
