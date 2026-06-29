//
//  LocalKnowledgeIndexingService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import CryptoKit
import Foundation
import AppKit
import PDFKit

nonisolated struct LocalKnowledgeIndexingService: Sendable {
    func buildIndex(
        for inputs: [LocalKnowledgeDocumentInput],
        options: LocalKnowledgeChunkingOptions = LocalKnowledgeChunkingOptions()
    ) throws -> LocalKnowledgeIndex {
        let normalizedOptions = options.normalized
        let resolvedDocuments = try inputs.map(resolveDocument)
        let sourcesAndChunks = resolvedDocuments.map { document in
            let chunks = makeChunks(for: document, options: normalizedOptions)
            let snapshot = LocalKnowledgeSourceSnapshot(
                id: document.sourceIdentifier,
                knowledgeSourceID: document.knowledgeSourceID,
                title: document.title,
                kind: document.kind,
                location: document.location,
                contentFingerprint: document.contentFingerprint,
                chunkCount: chunks.count
            )
            return (snapshot, chunks)
        }

        return LocalKnowledgeIndex(
            sources: sourcesAndChunks.map(\.0),
            chunks: sourcesAndChunks.flatMap(\.1),
            chunkingOptions: normalizedOptions
        )
    }

    func search(
        _ query: String,
        in index: LocalKnowledgeIndex,
        limit: Int = 8
    ) -> [LocalKnowledgeSearchResult] {
        let queryTerms = orderedUniqueTokens(in: query)
        guard queryTerms.isEmpty == false else {
            return []
        }

        let normalizedQuery = queryTerms.joined(separator: " ")
        let scoredResults = index.chunks.compactMap { chunk -> LocalKnowledgeSearchResult? in
            let bodyMatches = queryTerms.filter { chunk.termFrequencies[$0, default: 0] > 0 }
            let titleMatches = queryTerms.filter { chunk.titleTermFrequencies[$0, default: 0] > 0 }
            let locationMatches = queryTerms.filter { chunk.locationTermFrequencies[$0, default: 0] > 0 }
            let matchedTerms = stableUnion(bodyMatches, titleMatches, locationMatches)

            guard matchedTerms.isEmpty == false else {
                return nil
            }

            let coverage = Double(matchedTerms.count) / Double(queryTerms.count)
            let bodyFrequency = bodyMatches.reduce(into: 0) { partialResult, term in
                partialResult += min(chunk.termFrequencies[term, default: 0], 4)
            }
            let titleFrequency = titleMatches.reduce(into: 0) { partialResult, term in
                partialResult += min(chunk.titleTermFrequencies[term, default: 0], 2)
            }
            let locationFrequency = locationMatches.reduce(into: 0) { partialResult, term in
                partialResult += min(chunk.locationTermFrequencies[term, default: 0], 2)
            }
            let exactPhraseBoost = chunk.normalizedText.contains(normalizedQuery) ? 6.0 : 0.0
            let score = (coverage * 10.0)
                + (Double(bodyFrequency) * 1.5)
                + (Double(titleFrequency) * 2.0)
                + (Double(locationFrequency) * 0.75)
                + exactPhraseBoost

            return LocalKnowledgeSearchResult(
                chunk: chunk,
                score: score,
                matchedTerms: matchedTerms,
                snippet: makeSnippet(from: chunk.text, matchedTerms: matchedTerms)
            )
        }

        return scoredResults
            .sorted(by: compareResults)
            .prefix(max(0, limit))
            .map { $0 }
    }

    func retrievalPacket(
        for query: String,
        inputs: [LocalKnowledgeDocumentInput],
        limit: Int = 5,
        options: LocalKnowledgeChunkingOptions = LocalKnowledgeChunkingOptions(),
        vectorRecords: [LocalKnowledgeVectorRecord] = []
    ) throws -> LocalKnowledgeRetrievalPacket {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty,
              !inputs.isEmpty else {
            return .empty(query: query)
        }

        let index = try buildIndex(for: inputs, options: options)
        return retrievalPacket(
            for: trimmedQuery,
            index: index,
            vectorRecords: vectorRecords,
            limit: limit
        )
    }

    func retrievalPacket(
        for query: String,
        index: LocalKnowledgeIndex,
        vectorRecords: [LocalKnowledgeVectorRecord] = [],
        queryVector: [Double]? = nil,
        limit: Int = 5
    ) -> LocalKnowledgeRetrievalPacket {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return .empty(query: query)
        }

        let results = vectorRecords.isEmpty
            ? search(trimmedQuery, in: index, limit: limit)
            : hybridSearch(
                trimmedQuery,
                in: index,
                vectorRecords: vectorRecords,
                queryVector: queryVector,
                limit: limit
            )

        return LocalKnowledgeRetrievalPacket(
            query: trimmedQuery,
            results: results
        )
    }

    func contentFingerprint(for index: LocalKnowledgeIndex) -> String {
        let joinedFingerprints = index.sources
            .map { "\($0.id):\($0.contentFingerprint):\($0.chunkCount)" }
            .sorted()
            .joined(separator: "|")
        return sha256Hex(joinedFingerprints)
    }

    func hybridSearch(
        _ query: String,
        in index: LocalKnowledgeIndex,
        vectorRecords: [LocalKnowledgeVectorRecord],
        queryVector providedQueryVector: [Double]? = nil,
        limit: Int = 8
    ) -> [LocalKnowledgeSearchResult] {
        let queryTerms = orderedUniqueTokens(in: query)
        guard queryTerms.isEmpty == false else {
            return []
        }

        let keywordResults = Dictionary(
            uniqueKeysWithValues: search(query, in: index, limit: index.chunks.count).map { ($0.chunk.id, $0) }
        )
        let vectorsByChunkID = Dictionary(uniqueKeysWithValues: vectorRecords.map { ($0.chunkID, $0.vector) })
        let queryVector = providedQueryVector ?? LocalEmbeddingService().deterministicLocalVector(for: query)

        let scoredResults = index.chunks.compactMap { chunk -> LocalKnowledgeSearchResult? in
            let keywordResult = keywordResults[chunk.id]
            let semanticScore = vectorsByChunkID[chunk.id].map { cosineSimilarity(queryVector, $0) } ?? 0
            guard keywordResult != nil || semanticScore >= 0.12 else {
                return nil
            }

            let matchedTerms = keywordResult?.matchedTerms ?? semanticMatchedTerms(queryTerms, in: chunk)
            let keywordScore = keywordResult?.score ?? 0
            let combinedScore = keywordScore + (semanticScore * 8.0)

            return LocalKnowledgeSearchResult(
                chunk: chunk,
                score: combinedScore,
                matchedTerms: matchedTerms,
                snippet: keywordResult?.snippet ?? makeSnippet(from: chunk.text, matchedTerms: matchedTerms)
            )
        }

        return scoredResults
            .sorted(by: compareResults)
            .prefix(max(0, limit))
            .map { $0 }
    }
}

private extension LocalKnowledgeIndexingService {
    struct ResolvedDocument: Sendable {
        var sourceIdentifier: String
        var knowledgeSourceID: UUID?
        var title: String
        var kind: KnowledgeSourceKind
        var location: String
        var text: String
        var contentFingerprint: String
    }

    nonisolated func resolveDocument(_ input: LocalKnowledgeDocumentInput) throws -> ResolvedDocument {
        let text: String
        switch input.storage {
        case let .inlineText(rawText):
            text = rawText
        case let .file(url):
            if url.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame {
                if let decodedText = decodePDFText(from: url) {
                    text = decodedText
                } else {
                    throw LocalKnowledgeIndexingError.undecodableFile(path: url.path)
                }
            } else if url.pathExtension.localizedCaseInsensitiveCompare("docx") == .orderedSame {
                if let decodedText = decodeDOCXText(from: url) {
                    text = decodedText
                } else {
                    throw LocalKnowledgeIndexingError.undecodableFile(path: url.path)
                }
            } else {
                let data: Data
                do {
                    data = try Data(contentsOf: url)
                } catch {
                    throw LocalKnowledgeIndexingError.unreadableFile(path: url.path)
                }

                let isHTML = isHTMLFile(url)
                if let decodedText = decodeText(from: data) {
                    if isHTML {
                        guard let readableHTMLText = decodeHTMLText(from: decodedText, url: url) else {
                            throw LocalKnowledgeIndexingError.undecodableFile(path: url.path)
                        }
                        text = readableHTMLText
                    } else {
                        text = decodedText
                    }
                } else {
                    throw LocalKnowledgeIndexingError.undecodableFile(path: url.path)
                }
            }
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceIdentifier = makeSourceIdentifier(
            knowledgeSourceID: input.knowledgeSourceID,
            title: input.title,
            kind: input.kind,
            location: input.location
        )

        return ResolvedDocument(
            sourceIdentifier: sourceIdentifier,
            knowledgeSourceID: input.knowledgeSourceID,
            title: input.title,
            kind: input.kind,
            location: input.location,
            text: trimmedText,
            contentFingerprint: sha256Hex(trimmedText)
        )
    }

    nonisolated func makeChunks(
        for document: ResolvedDocument,
        options: LocalKnowledgeChunkingOptions
    ) -> [LocalKnowledgeChunk] {
        guard document.text.isEmpty == false else {
            return []
        }

        let tokenRanges = tokenRanges(in: document.text)
        guard tokenRanges.isEmpty == false else {
            return []
        }

        var chunks: [LocalKnowledgeChunk] = []
        var startTokenIndex = 0
        var ordinal = 0

        while startTokenIndex < tokenRanges.count {
            let startIndex = tokenRanges[startTokenIndex].lowerBound
            var endTokenIndex = startTokenIndex
            var lastValidEndTokenIndex = startTokenIndex

            while endTokenIndex < tokenRanges.count {
                let candidateRange = startIndex..<tokenRanges[endTokenIndex].upperBound
                let candidateLength = document.text.distance(
                    from: candidateRange.lowerBound,
                    to: candidateRange.upperBound
                )
                if candidateLength <= options.maximumCharacterCount || endTokenIndex == startTokenIndex {
                    lastValidEndTokenIndex = endTokenIndex
                    endTokenIndex += 1
                } else {
                    break
                }
            }

            let selectedRange = startIndex..<tokenRanges[lastValidEndTokenIndex].upperBound
            let chunkText = document.text[selectedRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedText = normalizeForSearch(chunkText)
            let startOffset = document.text.distance(from: document.text.startIndex, to: selectedRange.lowerBound)
            let endOffset = document.text.distance(from: document.text.startIndex, to: selectedRange.upperBound)

            chunks.append(
                LocalKnowledgeChunk(
                    id: makeChunkIdentifier(
                        sourceIdentifier: document.sourceIdentifier,
                        ordinal: ordinal,
                        startOffset: startOffset,
                        endOffset: endOffset,
                        text: chunkText
                    ),
                    sourceIdentifier: document.sourceIdentifier,
                    knowledgeSourceID: document.knowledgeSourceID,
                    sourceTitle: document.title,
                    sourceKind: document.kind,
                    sourceLocation: document.location,
                    ordinal: ordinal,
                    characterRange: startOffset..<endOffset,
                    text: chunkText,
                    normalizedText: normalizedText,
                    termFrequencies: termFrequencyMap(in: chunkText),
                    titleTermFrequencies: termFrequencyMap(in: document.title),
                    locationTermFrequencies: termFrequencyMap(in: document.location),
                    contentFingerprint: sha256Hex(chunkText)
                )
            )

            if lastValidEndTokenIndex == tokenRanges.count - 1 {
                break
            }

            let overlappedStartTokenIndex = nextChunkStartTokenIndex(
                currentStartTokenIndex: startTokenIndex,
                endTokenIndex: lastValidEndTokenIndex,
                tokenRanges: tokenRanges,
                text: document.text,
                overlapCharacterCount: options.overlapCharacterCount
            )
            startTokenIndex = overlappedStartTokenIndex
            ordinal += 1
        }

        return chunks
    }

    nonisolated func nextChunkStartTokenIndex(
        currentStartTokenIndex: Int,
        endTokenIndex: Int,
        tokenRanges: [Range<String.Index>],
        text: String,
        overlapCharacterCount: Int
    ) -> Int {
        guard overlapCharacterCount > 0 else {
            return endTokenIndex + 1
        }

        let endIndex = tokenRanges[endTokenIndex].upperBound
        var candidate = endTokenIndex

        while candidate > currentStartTokenIndex {
            let overlapLength = text.distance(from: tokenRanges[candidate].lowerBound, to: endIndex)
            if overlapLength > overlapCharacterCount {
                break
            }
            candidate -= 1
        }

        let proposedIndex = min(endTokenIndex, candidate + 1)
        return proposedIndex <= currentStartTokenIndex ? currentStartTokenIndex + 1 : proposedIndex
    }

    nonisolated func tokenRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var index = text.startIndex

        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }

            guard index < text.endIndex else {
                break
            }

            let start = index
            while index < text.endIndex, text[index].isWhitespace == false {
                index = text.index(after: index)
            }
            ranges.append(start..<index)
        }

        return ranges
    }

    nonisolated func makeSnippet(from text: String, matchedTerms: [String], maximumLength: Int = 220) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumLength else {
            return trimmed
        }

        let bestTermRange = matchedTerms
            .compactMap { term in
                trimmed.range(of: term, options: .caseInsensitive)
            }
            .min(by: { trimmed.distance(from: trimmed.startIndex, to: $0.lowerBound) < trimmed.distance(from: trimmed.startIndex, to: $1.lowerBound) })

        guard let range = bestTermRange else {
            let prefix = String(trimmed.prefix(maximumLength)).trimmingCharacters(in: .whitespacesAndNewlines)
            return prefix + "…"
        }

        let anchorOffset = trimmed.distance(from: trimmed.startIndex, to: range.lowerBound)
        let lowerOffset = max(0, anchorOffset - (maximumLength / 3))
        let upperOffset = min(trimmed.count, lowerOffset + maximumLength)
        let snippetStart = trimmed.index(trimmed.startIndex, offsetBy: lowerOffset)
        let snippetEnd = trimmed.index(trimmed.startIndex, offsetBy: upperOffset)
        let snippet = String(trimmed[snippetStart..<snippetEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        let prefix = lowerOffset > 0 ? "…" : ""
        let suffix = upperOffset < trimmed.count ? "…" : ""
        return prefix + snippet + suffix
    }

    nonisolated func decodeText(from data: Data) -> String? {
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .ascii] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return nil
    }

    nonisolated func decodeHTMLText(from html: String, url: URL) -> String? {
        try? WebPageCaptureService.extractReadableContent(from: html, url: url).text
    }

    nonisolated func isHTMLFile(_ url: URL) -> Bool {
        ["html", "htm"].contains(url.pathExtension.lowercased())
    }

    nonisolated func decodePDFText(from url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        let pageText = (0..<document.pageCount).compactMap { pageIndex in
            document.page(at: pageIndex)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let text = pageText.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    nonisolated func decodeDOCXText(from url: URL) -> String? {
        guard let attributedText = try? NSAttributedString(
            url: url,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: nil
        ) else {
            return nil
        }
        let text = attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    nonisolated func makeSourceIdentifier(
        knowledgeSourceID: UUID?,
        title: String,
        kind: KnowledgeSourceKind,
        location: String
    ) -> String {
        if let knowledgeSourceID {
            let documentHash = sha256Hex("\(kind.rawValue)|\(title)|\(location)")
            return "knowledge-source:\(knowledgeSourceID.uuidString.lowercased()):\(documentHash)"
        }

        return "local-source:\(sha256Hex("\(kind.rawValue)|\(title)|\(location)"))"
    }

    nonisolated func makeChunkIdentifier(
        sourceIdentifier: String,
        ordinal: Int,
        startOffset: Int,
        endOffset: Int,
        text: String
    ) -> String {
        sha256Hex("\(sourceIdentifier)|\(ordinal)|\(startOffset)|\(endOffset)|\(text)")
    }

    nonisolated func termFrequencyMap(in text: String) -> [String: Int] {
        tokenize(text).reduce(into: [:]) { partialResult, token in
            partialResult[token, default: 0] += 1
        }
    }

    nonisolated func orderedUniqueTokens(in text: String) -> [String] {
        stableUnion(tokenize(text))
    }

    nonisolated func tokenize(_ text: String) -> [String] {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var tokens: [String] = []
        var current = ""

        for scalar in normalized.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if current.isEmpty == false {
                tokens.append(current.lowercased())
                current.removeAll(keepingCapacity: true)
            }
        }

        if current.isEmpty == false {
            tokens.append(current.lowercased())
        }

        return tokens
    }

    nonisolated func normalizeForSearch(_ text: String) -> String {
        tokenize(text).joined(separator: " ")
    }

    nonisolated func stableUnion(_ terms: [String]...) -> [String] {
        stableUnion(terms.flatMap { $0 })
    }

    nonisolated func stableUnion(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for term in terms where seen.insert(term).inserted {
            ordered.append(term)
        }

        return ordered
    }

    nonisolated func compareResults(_ lhs: LocalKnowledgeSearchResult, _ rhs: LocalKnowledgeSearchResult) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.chunk.sourceTitle != rhs.chunk.sourceTitle {
            return lhs.chunk.sourceTitle.localizedCaseInsensitiveCompare(rhs.chunk.sourceTitle) == .orderedAscending
        }
        if lhs.chunk.ordinal != rhs.chunk.ordinal {
            return lhs.chunk.ordinal < rhs.chunk.ordinal
        }
        return lhs.chunk.id < rhs.chunk.id
    }

    nonisolated func semanticMatchedTerms(
        _ queryTerms: [String],
        in chunk: LocalKnowledgeChunk
    ) -> [String] {
        let directMatches = queryTerms.filter { chunk.termFrequencies[$0, default: 0] > 0 }
        return directMatches.isEmpty ? ["semantic"] : directMatches
    }

    nonisolated func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        let count = lhs.count
        guard count > 0,
              rhs.count == count else { return 0 }

        var dotProduct = 0.0
        var lhsMagnitude = 0.0
        var rhsMagnitude = 0.0

        for index in 0..<count {
            dotProduct += lhs[index] * rhs[index]
            lhsMagnitude += lhs[index] * lhs[index]
            rhsMagnitude += rhs[index] * rhs[index]
        }

        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return 0 }
        return dotProduct / (sqrt(lhsMagnitude) * sqrt(rhsMagnitude))
    }

    nonisolated func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
