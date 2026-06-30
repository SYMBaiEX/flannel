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

    @Test("Settings surface is narrower than conversation surface")
    func settingsModeUsesNarrowerSidebarWidth() {
        let conversationWidth = FlannelSidebarSurface.conversation.columnWidth
        let settingsWidth = FlannelSidebarSurface.settings.columnWidth

        #expect(settingsWidth.ideal < conversationWidth.ideal)
        #expect(settingsWidth.min < conversationWidth.min)
        #expect(settingsWidth.max < conversationWidth.max)
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

    @Test("Inspector sections stay stable when a chat has no artifacts yet")
    func inspectorSectionsRemainAvailableWithoutArtifacts() {
        #expect(FlannelInspectorSection.availableSections(
            hasCompareArtifacts: false,
            hasSourceArtifacts: false,
            hasToolArtifacts: false
        ) == FlannelInspectorSection.allCases)
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
