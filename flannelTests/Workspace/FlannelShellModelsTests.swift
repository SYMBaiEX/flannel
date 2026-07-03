//
//  FlannelShellModelsTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 6/29/26.
//

import CoreGraphics
import Testing
@testable import flannel

struct FlannelShellModelsTests {
    @Test("Sidebar surfaces only expose conversation and settings")
    func sidebarSurfacesOnlyExposeConversationAndSettings() {
        #expect(FlannelSidebarSurface.allCases == [.conversation, .settings])
    }

    @Test("Conversation surface shows inspector and footer")
    func conversationSurfaceShowsInspectorAndFooter() {
        #expect(FlannelSidebarSurface.conversation.showsConversationFooter)
        #expect(FlannelSidebarSurface.conversation.showsInspectorColumn)
    }

    @Test("Settings surface hides inspector and footer")
    func settingsSurfaceHidesInspectorAndFooter() {
        #expect(FlannelSidebarSurface.settings.showsConversationFooter == false)
        #expect(FlannelSidebarSurface.settings.showsInspectorColumn == false)
    }

    @Test("Settings surface reserves more width for route descriptions")
    func settingsModeUsesWiderSidebarWidth() {
        let conversationWidth = FlannelSidebarSurface.conversation.columnWidth
        let settingsWidth = FlannelSidebarSurface.settings.columnWidth

        #expect(settingsWidth.ideal > conversationWidth.ideal)
        #expect(settingsWidth.min > conversationWidth.min)
        #expect(settingsWidth.max > conversationWidth.max)
        #expect(settingsWidth.min >= 420)
        #expect(settingsWidth.ideal >= 456)
        #expect(settingsWidth.max >= 560)
    }

    @Test("Settings sidebar labels stay concise")
    func settingsSidebarLabelsStayConcise() {
        for tab in SettingsTab.allCases {
            #expect(tab.sidebarDetail.count <= tab.detail.count)
            #expect(tab.sidebarDetail.count <= 28)
        }
    }

    @Test("Settings sidebar uses compact copy for dense routes")
    func settingsSidebarUsesCompactCopyForDenseRoutes() {
        #expect(SettingsTab.general.sidebarDetail == "Startup, history, folders")
        #expect(SettingsTab.models.sidebarDetail == "Routes, keys, local models")
        #expect(SettingsTab.knowledge.sidebarDetail == "Sources and indexing")
        #expect(SettingsTab.privacy.sidebarDetail == "Network and secrets")
    }

    @Test("Escape exits settings surface")
    func exitIntentMapsSettingsToExitSettings() {
        #expect(FlannelExitCommandIntent.resolve(
            sidebarSurface: .settings,
            isInspectorVisible: true
        ) == .exitSettings)
        #expect(FlannelExitCommandIntent.resolve(
            sidebarSurface: .settings,
            isInspectorVisible: false
        ) == .exitSettings)
    }

    @Test("Escape collapses artifacts when conversation inspector is visible")
    func exitIntentCollapsesArtifactsFromConversationWithVisibleInspector() {
        #expect(FlannelExitCommandIntent.resolve(
            sidebarSurface: .conversation,
            isInspectorVisible: true
        ) == .collapseArtifacts)
        #expect(FlannelExitCommandIntent.resolve(
            sidebarSurface: .conversation,
            isInspectorVisible: false
        ) == .none)
    }

    @Test("Escape closes visible shell surfaces before canceling streams")
    func exitActionPrioritizesVisibleShellSurfacesBeforeStreaming() {
        #expect(FlannelExitCommandAction.resolve(
            isCommandPalettePresented: true,
            sidebarSurface: .settings,
            isInspectorVisible: true,
            isStreamingResponse: true
        ) == .closeCommandPalette)
        #expect(FlannelExitCommandAction.resolve(
            isCommandPalettePresented: false,
            sidebarSurface: .settings,
            isInspectorVisible: true,
            isStreamingResponse: true
        ) == .exitSettings)
        #expect(FlannelExitCommandAction.resolve(
            isCommandPalettePresented: false,
            sidebarSurface: .conversation,
            isInspectorVisible: true,
            isStreamingResponse: true
        ) == .collapseArtifacts)
        #expect(FlannelExitCommandAction.resolve(
            isCommandPalettePresented: false,
            sidebarSurface: .conversation,
            isInspectorVisible: false,
            isStreamingResponse: true
        ) == .cancelStreaming)
    }

    @Test("Inspector sections stay minimal when a chat has no artifacts yet")
    func inspectorSectionsStayMinimalWithoutArtifacts() {
        #expect(FlannelInspectorSection.availableSections(
            hasCompareArtifacts: false,
            hasSourceArtifacts: false,
            hasToolArtifacts: false
        ) == [.chatDetail])
        #expect(FlannelInspectorSection.defaultSection(
            hasCompareArtifacts: false,
            hasSourceArtifacts: false,
            hasToolArtifacts: false
        ) == .chatDetail)
    }

    @Test("Transcript follow policy treats near-bottom positions as pinned")
    func transcriptFollowPolicyUsesBottomThreshold() {
        #expect(FlannelTranscriptFollowPolicy.isPinnedToBottom(bottomDistance: -12))
        #expect(FlannelTranscriptFollowPolicy.isPinnedToBottom(bottomDistance: 0))
        #expect(FlannelTranscriptFollowPolicy.isPinnedToBottom(bottomDistance: 64))
        #expect(FlannelTranscriptFollowPolicy.isPinnedToBottom(bottomDistance: 96) == false)
    }
}
