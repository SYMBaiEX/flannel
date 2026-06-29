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

    @Test("Available inspector sections keep chat detail first and include only present artifacts")
    func availableSectionsFollowRailOrder() {
        #expect(FlannelInspectorSection.availableSections(
            hasCompareArtifacts: false,
            hasSourceArtifacts: true,
            hasToolArtifacts: true
        ) == [.chatDetail, .sources, .tools])
        #expect(FlannelInspectorSection.availableSections(
            hasCompareArtifacts: true,
            hasSourceArtifacts: false,
            hasToolArtifacts: false
        ) == [.chatDetail, .compare])
    }
}
