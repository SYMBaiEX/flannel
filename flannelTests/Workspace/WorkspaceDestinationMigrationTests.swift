//
//  WorkspaceDestinationMigrationTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation
import SwiftData
import Testing
@testable import flannel

struct WorkspaceDestinationMigrationTests {
    @Test("Workspace preferences default to Chat")
    func workspacePreferencesDefaultToChat() throws {
        #expect(WorkspacePreferences().defaultDestination == .home)

        let decoded = try JSONDecoder().decode(WorkspacePreferences.self, from: Data("{}".utf8))
        #expect(decoded.defaultDestination == .home)
    }

    @MainActor
    @Test("Selecting Settings normalizes to Chat")
    func selectingSettingsDestinationNormalizesToChat() {
        let store = WorkspaceStore()

        store.select(.settings)

        #expect(store.selectedDestination == .home)
        #expect(store.preferences.defaultDestination == .home)
    }

    @MainActor
    @Test("Legacy persisted Settings destination migrates to Chat on load")
    func loadingLegacySettingsDestinationMigratesToChat() throws {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let legacyThread = AssistantThread(
            title: "Legacy Chat",
            messages: [AssistantMessage(role: .user, text: "hello")]
        )
        let legacyWorkspace = Item(
            selectedDestination: .settings,
            selectedAssistantThreadID: legacyThread.id,
            assistantThreads: [legacyThread],
            preferences: WorkspacePreferences(defaultDestination: .settings)
        )
        context.insert(legacyWorkspace)
        try context.save()

        let store = WorkspaceStore()
        try store.loadOrCreate(in: context)

        #expect(store.selectedDestination == .home)
        #expect(store.preferences.defaultDestination == .home)
        #expect(store.currentAssistantThread?.title == "Legacy Chat")
    }

    @MainActor
    @Test("Legacy main-window routes all migrate to Chat")
    func legacyMainWindowRoutesAllMigrateToChat() throws {
        for destination in WorkspaceDestination.allCases where destination != .home {
            let container = try ModelContainer(
                for: Item.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = ModelContext(container)
            let workspace = Item(
                selectedDestination: destination,
                preferences: WorkspacePreferences(defaultDestination: destination)
            )
            context.insert(workspace)
            try context.save()

            let store = WorkspaceStore()
            try store.loadOrCreate(in: context)

            #expect(store.selectedDestination == .home)
            #expect(store.preferences.defaultDestination == .home)
        }
    }
}
