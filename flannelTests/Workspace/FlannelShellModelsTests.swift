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
    @Test("Settings mode replaces the conversation sidebar instead of extending it")
    func settingsModeReplacesConversationSidebar() {
        #expect(FlannelSidebarSurface.conversation.showsConversationFooter)
        #expect(FlannelSidebarSurface.conversation.showsInspectorColumn)

        #expect(FlannelSidebarSurface.settings.showsConversationFooter == false)
        #expect(FlannelSidebarSurface.settings.showsInspectorColumn == false)
    }

    @Test("Settings mode uses a narrower native source-list width")
    func settingsModeUsesNarrowerSidebarWidth() {
        let conversationWidth = FlannelSidebarSurface.conversation.columnWidth
        let settingsWidth = FlannelSidebarSurface.settings.columnWidth

        #expect(settingsWidth.ideal < conversationWidth.ideal)
        #expect(settingsWidth.min < conversationWidth.min)
        #expect(settingsWidth.max < conversationWidth.max)
    }

    @Test("Escape exits settings before collapsing the artifact rail")
    func exitCommandPrioritizesSettingsMode() {
        #expect(FlannelExitCommandIntent.resolve(
            sidebarSurface: .settings,
            isInspectorVisible: true
        ) == .exitSettings)
        #expect(FlannelExitCommandIntent.resolve(
            sidebarSurface: .settings,
            isInspectorVisible: false
        ) == .exitSettings)
    }

    @Test("Escape collapses artifacts only in conversation mode")
    func exitCommandCollapsesArtifactsInConversationMode() {
        #expect(FlannelExitCommandIntent.resolve(
            sidebarSurface: .conversation,
            isInspectorVisible: true
        ) == .collapseArtifacts)
        #expect(FlannelExitCommandIntent.resolve(
            sidebarSurface: .conversation,
            isInspectorVisible: false
        ) == .none)
    }

    @Test("Transcript follow policy treats near-bottom positions as pinned")
    func transcriptFollowPolicyUsesBottomThreshold() {
        #expect(FlannelTranscriptFollowPolicy.isPinnedToBottom(bottomDistance: -12))
        #expect(FlannelTranscriptFollowPolicy.isPinnedToBottom(bottomDistance: 0))
        #expect(FlannelTranscriptFollowPolicy.isPinnedToBottom(bottomDistance: 64))
        #expect(FlannelTranscriptFollowPolicy.isPinnedToBottom(bottomDistance: 96) == false)
    }
}
