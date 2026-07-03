//
//  ChatSearchHighlighter.swift
//  flannel
//
//  Created by OpenAI Codex on 7/3/26.
//

import Foundation
import SwiftUI

enum ChatSearchHighlighter {
    static func highlighted(
        _ attributed: AttributedString,
        query rawQuery: String,
        isActive: Bool
    ) -> AttributedString {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return attributed }

        var highlighted = attributed
        var searchRange = highlighted.startIndex..<highlighted.endIndex
        let fill = Color.accentColor.opacity(isActive ? 0.30 : 0.18)

        while let range = highlighted[searchRange].range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .autoupdatingCurrent
        ) {
            highlighted[range].backgroundColor = fill

            if range.upperBound == searchRange.upperBound {
                break
            }
            searchRange = range.upperBound..<searchRange.upperBound
        }

        return highlighted
    }
}
