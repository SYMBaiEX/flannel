//
//  ChatSearchHighlighterTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 7/3/26.
//

import SwiftUI
import Testing
@testable import flannel

struct ChatSearchHighlighterTests {
    @Test("Highlights every case-insensitive occurrence")
    func highlightsEveryCaseInsensitiveOccurrence() {
        let highlighted = ChatSearchHighlighter.highlighted(
            AttributedString("Needle in prose, needle in code."),
            query: "needle",
            isActive: true
        )

        #expect(highlightedRuns(in: highlighted) == ["Needle", "needle"])
    }

    @Test("Leaves attributed text unchanged for empty queries")
    func leavesTextUnchangedForEmptyQueries() {
        let source = AttributedString("No active search")
        let highlighted = ChatSearchHighlighter.highlighted(
            source,
            query: "   ",
            isActive: false
        )

        #expect(String(highlighted.characters) == String(source.characters))
        #expect(highlightedRuns(in: highlighted).isEmpty)
    }

    private func highlightedRuns(in attributed: AttributedString) -> [String] {
        attributed.runs.compactMap { run in
            guard run.attributes.backgroundColor != nil else { return nil }
            return String(attributed.characters[run.range])
        }
    }
}
