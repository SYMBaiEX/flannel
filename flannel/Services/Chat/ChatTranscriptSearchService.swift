//
//  ChatTranscriptSearchService.swift
//  flannel
//

import Foundation

struct ChatTranscriptSearchMatch: Identifiable, Hashable, Sendable {
    let id: String
    let messageID: UUID
    let role: AssistantRole
    let matchKind: AssistantChatSearchMatchKind
    let preview: String
}

struct ChatTranscriptSearchService: Sendable {
    static func matches(
        in messages: [AssistantMessage],
        query rawQuery: String,
        limit: Int = 200
    ) -> [ChatTranscriptSearchMatch] {
        guard limit > 0 else { return [] }
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var matches: [ChatTranscriptSearchMatch] = []
        for message in messages where message.role != .system {
            appendMatches(
                from: message.text,
                query: query,
                message: message,
                kind: .messageText,
                matches: &matches,
                limit: limit
            )

            for attachment in message.attachments {
                let searchableAttachmentText = [
                    attachment.title,
                    attachment.excerpt,
                    attachment.localPath,
                    attachment.remoteURL?.absoluteString
                ]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                appendMatches(
                    from: searchableAttachmentText,
                    query: query,
                    message: message,
                    kind: .attachment,
                    matches: &matches,
                    limit: limit
                )
            }

            for citation in message.citations {
                let searchableCitationText = [
                    citation.title,
                    citation.snippet,
                    citation.sourceIdentifier
                ]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                appendMatches(
                    from: searchableCitationText,
                    query: query,
                    message: message,
                    kind: .citation,
                    matches: &matches,
                    limit: limit
                )
            }

            if matches.count >= limit {
                return Array(matches.prefix(limit))
            }
        }

        return matches
    }

    private static func appendMatches(
        from text: String,
        query: String,
        message: AssistantMessage,
        kind: AssistantChatSearchMatchKind,
        matches: inout [ChatTranscriptSearchMatch],
        limit: Int
    ) {
        guard !text.isEmpty, matches.count < limit else { return }

        var searchRange = text.startIndex..<text.endIndex
        while matches.count < limit,
              let range = text.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange,
                locale: .autoupdatingCurrent
              ) {
            let ordinal = matches.count
            matches.append(
                ChatTranscriptSearchMatch(
                    id: "\(kind.rawValue)-\(message.id.uuidString)-\(ordinal)",
                    messageID: message.id,
                    role: message.role,
                    matchKind: kind,
                    preview: preview(from: text, around: range)
                )
            )

            if range.upperBound == searchRange.upperBound {
                break
            }
            searchRange = range.upperBound..<searchRange.upperBound
        }
    }

    private static func preview(from text: String, around range: Range<String.Index>) -> String {
        let previewRadius = 72
        let lowerBound = text.index(
            range.lowerBound,
            offsetBy: -previewRadius,
            limitedBy: text.startIndex
        ) ?? text.startIndex
        let upperBound = text.index(
            range.upperBound,
            offsetBy: previewRadius,
            limitedBy: text.endIndex
        ) ?? text.endIndex

        var preview = String(text[lowerBound..<upperBound])
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while preview.contains("  ") {
            preview = preview.replacingOccurrences(of: "  ", with: " ")
        }

        if lowerBound > text.startIndex {
            preview = "... \(preview)"
        }
        if upperBound < text.endIndex {
            preview = "\(preview) ..."
        }

        return preview
    }
}
