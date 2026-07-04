//
//  LocalKnowledgeTypes.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

nonisolated struct LocalKnowledgeDocumentInput: Sendable, Hashable {
    enum Storage: Sendable, Hashable {
        case inlineText(String)
        case file(URL)
    }

    var title: String
    var kind: KnowledgeSourceKind
    var location: String
    var knowledgeSourceID: UUID?

    var storage: Storage

    static func knowledgeSource(_ source: KnowledgeSource, text: String) -> Self {
        Self(
            title: source.title,
            kind: source.kind,
            location: source.location,
            knowledgeSourceID: source.id,
            storage: .inlineText(text)
        )
    }

    static func file(
        _ url: URL,
        title: String? = nil,
        kind: KnowledgeSourceKind = .file,
        knowledgeSourceID: UUID? = nil
    ) -> Self {
        let fileURL = url.standardizedFileURL
        return Self(
            title: title ?? fileURL.lastPathComponent,
            kind: kind,
            location: fileURL.path,
            knowledgeSourceID: knowledgeSourceID,
            storage: .file(fileURL)
        )
    }

    static func plainText(
        title: String,
        text: String,
        location: String = "flannel://plain-text",
        kind: KnowledgeSourceKind = .workspaceNotes
    ) -> Self {
        Self(
            title: title,
            kind: kind,
            location: location,
            knowledgeSourceID: nil,
            storage: .inlineText(text)
        )
    }
}

nonisolated struct LocalKnowledgeChunkingOptions: Sendable, Hashable {
    var maximumCharacterCount: Int
    var overlapCharacterCount: Int
    var minimumCharacterCount: Int

    init(
        maximumCharacterCount: Int = 700,
        overlapCharacterCount: Int = 120,
        minimumCharacterCount: Int = 180
    ) {
        self.maximumCharacterCount = maximumCharacterCount
        self.overlapCharacterCount = overlapCharacterCount
        self.minimumCharacterCount = minimumCharacterCount
    }

    var normalized: Self {
        let maximum = max(1, maximumCharacterCount)
        let minimum = max(1, min(minimumCharacterCount, maximum))
        let overlap = max(0, min(overlapCharacterCount, maximum - 1))
        return Self(
            maximumCharacterCount: maximum,
            overlapCharacterCount: overlap,
            minimumCharacterCount: minimum
        )
    }
}

nonisolated struct LocalKnowledgeRerankingOptions: Sendable, Hashable {
    var isEnabled: Bool
    var sourceRepeatPenaltyFraction: Double
    var adjacentChunkPenaltyFraction: Double
    var termNoveltyBoostFraction: Double
    var minimumSourceRepeatPenalty: Double

    init(
        isEnabled: Bool = true,
        sourceRepeatPenaltyFraction: Double = 0.28,
        adjacentChunkPenaltyFraction: Double = 0.12,
        termNoveltyBoostFraction: Double = 0.08,
        minimumSourceRepeatPenalty: Double = 2.0
    ) {
        self.isEnabled = isEnabled
        self.sourceRepeatPenaltyFraction = sourceRepeatPenaltyFraction
        self.adjacentChunkPenaltyFraction = adjacentChunkPenaltyFraction
        self.termNoveltyBoostFraction = termNoveltyBoostFraction
        self.minimumSourceRepeatPenalty = minimumSourceRepeatPenalty
    }
}

nonisolated struct LocalKnowledgeIndex: Sendable, Hashable {
    var sources: [LocalKnowledgeSourceSnapshot]
    var chunks: [LocalKnowledgeChunk]
    var chunkingOptions: LocalKnowledgeChunkingOptions

    var chunkCount: Int { chunks.count }
}

nonisolated struct LocalKnowledgeSourceSnapshot: Identifiable, Sendable, Hashable {
    var id: String
    var knowledgeSourceID: UUID?
    var title: String
    var kind: KnowledgeSourceKind
    var location: String
    var contentFingerprint: String
    var chunkCount: Int
}

nonisolated struct LocalKnowledgeChunk: Identifiable, Sendable, Hashable {
    var id: String
    var sourceIdentifier: String
    var knowledgeSourceID: UUID?
    var sourceTitle: String
    var sourceKind: KnowledgeSourceKind
    var sourceLocation: String
    var ordinal: Int
    var characterRange: Range<Int>
    var text: String
    var normalizedText: String
    var termFrequencies: [String: Int]
    var titleTermFrequencies: [String: Int]
    var locationTermFrequencies: [String: Int]
    var contentFingerprint: String

    var citationTitle: String {
        "\(sourceTitle) • chunk \(ordinal + 1)"
    }
}

nonisolated struct LocalKnowledgeSearchResult: Identifiable, Sendable, Hashable {
    var chunk: LocalKnowledgeChunk
    var score: Double
    var matchedTerms: [String]
    var snippet: String

    var id: String { chunk.id }

    func makeCitation() -> AIChatCitation {
        AIChatCitation(
            title: chunk.citationTitle,
            snippet: snippet,
            indexID: chunk.knowledgeSourceID,
            sourceIdentifier: chunk.id,
            sourceLocation: chunk.sourceLocation,
            score: score
        )
    }
}

nonisolated struct LocalKnowledgeRetrievalPacket: Sendable, Hashable {
    var query: String
    var results: [LocalKnowledgeSearchResult]

    var citations: [AIChatCitation] {
        results.map { $0.makeCitation() }
    }

    var isEmpty: Bool {
        results.isEmpty
    }

    static func empty(query: String) -> Self {
        Self(query: query, results: [])
    }

    var promptContext: String {
        guard !results.isEmpty else { return "" }

        let entries = results.enumerated().map { index, result in
            """
            [\(index + 1)] \(result.chunk.citationTitle)
            Location: \(result.chunk.sourceLocation)
            Matched terms: \(result.matchedTerms.joined(separator: ", "))
            Snippet: \(result.snippet)
            """
        }

        return """
        Local knowledge retrieval for: \(query)
        Use the following snippets as local-first context. Cite relevant snippets with bracket numbers such as [1].

        \(entries.joined(separator: "\n\n"))
        """
    }

    var responseCitationBlock: String {
        guard !results.isEmpty else { return "" }

        let entries = results.enumerated().map { index, result in
            "\(index + 1). \(result.chunk.citationTitle): \(result.snippet)"
        }

        return "\n\nSources\n" + entries.joined(separator: "\n")
    }
}

nonisolated enum LocalKnowledgeIndexingError: Error, LocalizedError, Equatable {
    case unreadableFile(path: String)
    case undecodableFile(path: String)

    var errorDescription: String? {
        switch self {
        case let .unreadableFile(path):
            return "Flannel could not read the local knowledge file at \(path)."
        case let .undecodableFile(path):
            return "Flannel could not decode the local knowledge file at \(path) as text."
        }
    }
}
