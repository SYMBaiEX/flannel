//
//  FlannelInspectorSectionTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 6/29/26.
//

import Testing
@testable import flannel

struct FlannelInspectorSectionTests {
    @Test("Sources are the preferred active artifact when citations exist")
    func sourcesWinDefaultSectionWhenPresent() {
        #expect(FlannelInspectorSection.defaultSection(
            hasCompareArtifacts: true,
            hasSourceArtifacts: true,
            hasToolArtifacts: true
        ) == .sources)
    }

    @Test("Inspector falls back through compare tools and chat detail")
    func defaultSectionFallsBackThroughArtifactTypes() {
        #expect(FlannelInspectorSection.defaultSection(
            hasCompareArtifacts: true,
            hasSourceArtifacts: false,
            hasToolArtifacts: true
        ) == .compare)
        #expect(FlannelInspectorSection.defaultSection(
            hasCompareArtifacts: false,
            hasSourceArtifacts: false,
            hasToolArtifacts: true
        ) == .tools)
        #expect(FlannelInspectorSection.defaultSection(
            hasCompareArtifacts: false,
            hasSourceArtifacts: false,
            hasToolArtifacts: false
        ) == .chatDetail)
    }

    @Test("Available inspector sections put contextual artifacts before details")
    func availableSectionsFollowRailOrder() {
        #expect(FlannelInspectorSection.availableSections(
            hasCompareArtifacts: false,
            hasSourceArtifacts: true,
            hasToolArtifacts: true
        ) == [.sources, .tools, .chatDetail])
        #expect(FlannelInspectorSection.availableSections(
            hasCompareArtifacts: true,
            hasSourceArtifacts: false,
            hasToolArtifacts: false
        ) == [.compare, .chatDetail])
        #expect(FlannelInspectorSection.availableSections(
            hasCompareArtifacts: false,
            hasSourceArtifacts: false,
            hasToolArtifacts: false
        ) == [.chatDetail])
    }
}
