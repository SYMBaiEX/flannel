//
//  LocalKnowledgeIndexingServiceTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation
import AppKit
import CoreText
import Testing
@testable import flannel

struct LocalKnowledgeIndexingServiceTests {
    private let service = LocalKnowledgeIndexingService()

    @Test("Plain text indexing creates stable overlapping chunk identifiers")
    func plainTextIndexingCreatesStableOverlappingChunkIdentifiers() throws {
        let text = (1...36).map { "token\($0)" }.joined(separator: " ")
        let options = LocalKnowledgeChunkingOptions(
            maximumCharacterCount: 54,
            overlapCharacterCount: 18,
            minimumCharacterCount: 24
        )
        let input = LocalKnowledgeDocumentInput.plainText(
            title: "Roadmap Draft",
            text: text,
            location: "flannel://drafts/roadmap"
        )

        let firstIndex = try service.buildIndex(for: [input], options: options)
        let secondIndex = try service.buildIndex(for: [input], options: options)
        let firstChunk = try #require(firstIndex.chunks.first)
        let secondChunk = try #require(firstIndex.chunks.dropFirst().first)

        #expect(firstIndex.chunkCount > 1)
        #expect(firstIndex.chunkingOptions == options.normalized)
        #expect(firstIndex.chunks.map(\.id) == secondIndex.chunks.map(\.id))
        #expect(firstChunk.characterRange.upperBound > secondChunk.characterRange.lowerBound)
        #expect(firstIndex.sources.first?.chunkCount == firstIndex.chunkCount)
    }

    @Test("KnowledgeSource indexing ranks exact keyword matches first and produces citations")
    func knowledgeSourceSearchRanksExactMatchesFirst() throws {
        let exactSource = KnowledgeSource(
            id: UUID(uuidString: "E2F1A6D3-CA57-4E8F-B463-B422E7C8F6B5")!,
            title: "Local Workflow Playbook",
            kind: .workspaceNotes,
            location: "flannel://notes/local-workflows"
        )
        let weakerSource = KnowledgeSource(
            id: UUID(uuidString: "6F449E0B-A2F4-4760-8E34-E973955F1B45")!,
            title: "General Research Notes",
            kind: .workspaceNotes,
            location: "flannel://notes/research"
        )

        let index = try service.buildIndex(
            for: [
                .knowledgeSource(
                    weakerSource,
                    text: "Local privacy matters. Drafting tools should stay fast and private even before citations are added."
                ),
                .knowledgeSource(
                    exactSource,
                    text: "A local workflow should answer with citations. This local workflow keeps drafts private and shows citations beside every answer."
                )
            ]
        )

        let results = service.search("local workflow citations", in: index, limit: 2)
        let topResult = try #require(results.first)
        let citation = topResult.makeCitation()

        #expect(results.count == 2)
        #expect(topResult.chunk.knowledgeSourceID == exactSource.id)
        #expect(topResult.matchedTerms == ["local", "workflow", "citations"])
        #expect(topResult.snippet.localizedCaseInsensitiveContains("citations"))
        #expect(citation.title == "Local Workflow Playbook • chunk 1")
        #expect(citation.indexID == exactSource.id)
        #expect(citation.sourceIdentifier == topResult.chunk.id)
    }

    @Test("Local reranking diversifies top retrieval results across sources")
    func localRerankingDiversifiesTopRetrievalResultsAcrossSources() throws {
        let results = [
            searchResult(
                title: "Long Project Notes",
                sourceIdentifier: "source-a",
                ordinal: 0,
                score: 100,
                matchedTerms: ["local", "rerank"]
            ),
            searchResult(
                title: "Long Project Notes",
                sourceIdentifier: "source-a",
                ordinal: 1,
                score: 98,
                matchedTerms: ["local", "rerank"]
            ),
            searchResult(
                title: "Long Project Notes",
                sourceIdentifier: "source-a",
                ordinal: 2,
                score: 97,
                matchedTerms: ["local", "rerank"]
            ),
            searchResult(
                title: "Side Source A",
                sourceIdentifier: "source-b",
                ordinal: 0,
                score: 96,
                matchedTerms: ["local", "rerank"]
            ),
            searchResult(
                title: "Side Source B",
                sourceIdentifier: "source-c",
                ordinal: 0,
                score: 95,
                matchedTerms: ["local", "rerank"]
            )
        ]

        let reranked = service.rerankResults(results, for: "local rerank", limit: 3)
        let raw = service.rerankResults(
            results,
            for: "local rerank",
            limit: 3,
            options: LocalKnowledgeRerankingOptions(isEnabled: false)
        )

        #expect(reranked.map(\.chunk.sourceIdentifier) == ["source-a", "source-b", "source-c"])
        #expect(raw.map(\.chunk.sourceIdentifier) == ["source-a", "source-a", "source-a"])
    }

    @Test("Local reranking boosts candidates with uncovered query terms")
    func localRerankingBoostsCandidatesWithUncoveredQueryTerms() throws {
        let results = [
            searchResult(
                title: "Primary Source",
                sourceIdentifier: "source-a",
                ordinal: 0,
                score: 40,
                matchedTerms: ["local", "rerank"]
            ),
            searchResult(
                title: "Primary Source",
                sourceIdentifier: "source-a",
                ordinal: 1,
                score: 39,
                matchedTerms: ["local", "rerank"]
            ),
            searchResult(
                title: "Security Source",
                sourceIdentifier: "source-b",
                ordinal: 0,
                score: 38,
                matchedTerms: ["safety"]
            )
        ]

        let reranked = service.rerankResults(results, for: "local rerank safety", limit: 2)

        #expect(reranked.map(\.chunk.sourceIdentifier) == ["source-a", "source-b"])
        #expect(reranked[1].matchedTerms == ["safety"])
    }

    @Test("File input reads local text and returns searchable citations")
    func fileInputReadsLocalText() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-knowledge-\(UUID().uuidString).txt")
            .standardizedFileURL
        let text = """
        Release notes:
        The macOS launch now includes offline indexing, deterministic chunk IDs, and citation previews for local search.
        """

        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let index = try service.buildIndex(for: [.file(fileURL, title: "Release Notes")])
        let result = try #require(service.search("offline indexing", in: index).first)

        #expect(index.sources.first?.location == fileURL.path)
        #expect(result.chunk.sourceLocation == fileURL.path)
        #expect(result.chunk.sourceTitle == "Release Notes")
        #expect(result.makeCitation().title == "Release Notes • chunk 1")
    }

    @Test("HTML file input indexes readable body text without markup or scripts")
    func htmlFileInputIndexesReadableBodyTextWithoutMarkupOrScripts() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-knowledge-\(UUID().uuidString).html")
            .standardizedFileURL
        let html = """
        <!doctype html>
        <html>
          <head>
            <title>Head title should not become body text</title>
            <style>
              .hidden { display: none; }
              body::before { content: "STYLE LEAK NEEDLE"; }
            </style>
            <script>
              window.localKnowledgeLeak = "SCRIPT LEAK NEEDLE";
            </script>
          </head>
          <body>
            <article>
              <h1>Local HTML knowledge note</h1>
              <p>Amber retrieval compass guides local citations &amp; workspace search.</p>
              <p>Readable body paragraphs become indexed chunks for FROST NEEDLE lookup.</p>
            </article>
          </body>
        </html>
        """

        try html.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let index = try service.buildIndex(for: [.file(fileURL, title: "Local HTML Notes")])
        let chunk = try #require(index.chunks.first)
        let result = try #require(service.search("amber retrieval compass", in: index).first)

        #expect(chunk.text.contains("Local HTML knowledge note"))
        #expect(chunk.text.contains("Amber retrieval compass guides local citations & workspace search."))
        #expect(chunk.text.contains("FROST NEEDLE lookup"))
        #expect(chunk.text.localizedCaseInsensitiveContains("STYLE LEAK NEEDLE") == false)
        #expect(chunk.text.localizedCaseInsensitiveContains("SCRIPT LEAK NEEDLE") == false)
        #expect(chunk.text.contains("<article") == false)
        #expect(chunk.text.contains("<p>") == false)
        #expect(result.chunk.id == chunk.id)
        #expect(result.snippet.contains("Amber retrieval compass"))
    }

    @Test("PDF input extracts searchable text")
    func pdfInputExtractsSearchableText() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-knowledge-\(UUID().uuidString).pdf")
            .standardizedFileURL
        try writeSearchablePDF(
            text: "PDF QUARTZ ROUTER citations stay searchable for local RAG.",
            to: fileURL
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let index = try service.buildIndex(for: [.file(fileURL, title: "PDF Notes")])
        let result = try #require(service.search("QUARTZ ROUTER", in: index).first)

        #expect(index.sources.first?.location == fileURL.path)
        #expect(result.chunk.sourceTitle == "PDF Notes")
        #expect(result.chunk.text.contains("QUARTZ ROUTER"))
    }

    @Test("DOCX input extracts searchable Office Open XML text")
    func docxInputExtractsSearchableText() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-knowledge-\(UUID().uuidString).docx")
            .standardizedFileURL
        try writeSearchableDOCX(
            text: "DOCX COPPER LANTERN notes stay searchable for private local RAG.",
            to: fileURL
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let index = try service.buildIndex(for: [.file(fileURL, title: "DOCX Notes")])
        let result = try #require(service.search("COPPER LANTERN", in: index).first)

        #expect(index.sources.first?.location == fileURL.path)
        #expect(result.chunk.sourceTitle == "DOCX Notes")
        #expect(result.chunk.text.contains("COPPER LANTERN"))
    }

    @Test("Retrieval packet formats prompt context and source block")
    func retrievalPacketFormatsPromptContextAndSourceBlock() throws {
        let packet = try service.retrievalPacket(
            for: "private citation workflow",
            inputs: [
                .plainText(
                    title: "Citation Plan",
                    text: "A private citation workflow should retrieve local snippets, rank them, and show sources below the answer."
                )
            ],
            limit: 1
        )

        #expect(packet.results.count == 1)
        #expect(packet.citations.count == 1)
        #expect(packet.promptContext.contains("Local knowledge retrieval for: private citation workflow"))
        #expect(packet.promptContext.contains("[1] Citation Plan • chunk 1"))
        #expect(packet.responseCitationBlock.contains("Sources"))
        #expect(packet.responseCitationBlock.contains("Citation Plan • chunk 1"))
    }

    @Test("Hybrid search can include persisted semantic vector matches without keyword overlap")
    func hybridSearchIncludesSemanticOnlyVectorMatch() throws {
        let index = try service.buildIndex(
            for: [
                .plainText(
                    title: "Vector Only Note",
                    text: "This passage uses completely different words from the user request."
                )
            ]
        )
        let chunk = try #require(index.chunks.first)
        let queryVector = LocalEmbeddingService().deterministicLocalVector(for: "semantic retrieval")
        let vectorRecord = LocalKnowledgeVectorRecord(
            chunkID: chunk.id,
            sourceIdentifier: chunk.sourceIdentifier,
            knowledgeSourceID: chunk.knowledgeSourceID,
            sourceTitle: chunk.sourceTitle,
            sourceKind: chunk.sourceKind,
            sourceLocation: chunk.sourceLocation,
            ordinal: chunk.ordinal,
            contentFingerprint: chunk.contentFingerprint,
            text: chunk.text,
            vector: queryVector
        )

        let keywordResults = service.search("semantic retrieval", in: index)
        let hybridResults = service.hybridSearch(
            "semantic retrieval",
            in: index,
            vectorRecords: [vectorRecord],
            limit: 1
        )

        #expect(keywordResults.isEmpty)
        #expect(hybridResults.first?.chunk.id == chunk.id)
        #expect(hybridResults.first?.matchedTerms == ["semantic"])
    }

    @Test("Hybrid search diversifies reranked top K across sources")
    func hybridSearchDiversifiesRerankedTopKAcrossSources() throws {
        let candidateResults = [
            searchResult(
                title: "Long Project Notes",
                sourceIdentifier: "source-a",
                ordinal: 0,
                score: 100,
                matchedTerms: ["local", "rerank"]
            ),
            searchResult(
                title: "Long Project Notes",
                sourceIdentifier: "source-a",
                ordinal: 1,
                score: 98,
                matchedTerms: ["local", "rerank"]
            ),
            searchResult(
                title: "Long Project Notes",
                sourceIdentifier: "source-a",
                ordinal: 2,
                score: 97,
                matchedTerms: ["local", "rerank"]
            ),
            searchResult(
                title: "Side Source A",
                sourceIdentifier: "source-b",
                ordinal: 0,
                score: 96,
                matchedTerms: ["local", "rerank"]
            ),
            searchResult(
                title: "Side Source B",
                sourceIdentifier: "source-c",
                ordinal: 0,
                score: 95,
                matchedTerms: ["local", "rerank"]
            )
        ]
        let chunks = candidateResults.map(\.chunk)
        let index = LocalKnowledgeIndex(
            sources: [
                sourceSnapshot(id: "source-a", title: "Long Project Notes", chunkCount: 3),
                sourceSnapshot(id: "source-b", title: "Side Source A", chunkCount: 1),
                sourceSnapshot(id: "source-c", title: "Side Source B", chunkCount: 1)
            ],
            chunks: chunks,
            chunkingOptions: LocalKnowledgeChunkingOptions()
        )
        let vectorRecords = chunks.map {
            vectorRecord(for: $0, vector: [1, 0])
        }

        let results = service.hybridSearch(
            "local rerank",
            in: index,
            vectorRecords: vectorRecords,
            queryVector: [1, 0],
            limit: 3
        )

        #expect(results.map(\.chunk.sourceIdentifier) == ["source-a", "source-b", "source-c"])
    }

    @Test("Hybrid search ignores semantic vectors with mismatched dimensions")
    func hybridSearchIgnoresMismatchedVectorDimensions() throws {
        let index = try service.buildIndex(
            for: [
                .plainText(
                    title: "Vector Only Note",
                    text: "This passage uses completely different words from the user request."
                )
            ]
        )
        let chunk = try #require(index.chunks.first)
        let vectorRecord = LocalKnowledgeVectorRecord(
            chunkID: chunk.id,
            sourceIdentifier: chunk.sourceIdentifier,
            knowledgeSourceID: chunk.knowledgeSourceID,
            sourceTitle: chunk.sourceTitle,
            sourceKind: chunk.sourceKind,
            sourceLocation: chunk.sourceLocation,
            ordinal: chunk.ordinal,
            contentFingerprint: chunk.contentFingerprint,
            text: chunk.text,
            vector: [1, 0, 0]
        )

        let results = service.hybridSearch(
            "semantic retrieval",
            in: index,
            vectorRecords: [vectorRecord],
            queryVector: [1, 0],
            limit: 1
        )

        #expect(results.isEmpty)
    }

    @MainActor
    @Test("Vector store builds provider-backed vectors from configured embeddings")
    func vectorStoreBuildsProviderBackedVectors() async throws {
        let index = try service.buildIndex(
            for: [
                .plainText(
                    title: "Provider Embedding Note",
                    text: "Provider embeddings should be persisted exactly for local RAG."
                )
            ]
        )
        let provider = ProviderConfiguration(
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "LM Studio",
            endpoint: "http://localhost:1234",
            modelIdentifier: "text-embedding-local",
            supportsEmbeddings: true
        )
        let vectors = index.chunks.enumerated().map { offset, _ in
            [Double(offset) + 0.1, Double(offset) + 0.2]
        }
        let providerID = provider.id
        let store = LocalKnowledgeVectorStore(providerEmbeddingGenerator: { receivedProvider, modelIdentifier, inputs in
            #expect(receivedProvider.id == providerID)
            #expect(modelIdentifier == "text-embedding-local")
            #expect(inputs == index.chunks.map(\.text))
            return LocalEmbeddingResult(modelIdentifier: modelIdentifier, vectors: vectors)
        })

        let vectorFile = try await store.buildVectorIndexFile(
            for: index,
            sourceID: nil,
            title: "Provider Embedding Note",
            modelIdentifier: "text-embedding-local",
            embeddingProvider: provider,
            contentFingerprint: "fingerprint",
            builtAt: Date(timeIntervalSince1970: 0)
        )

        #expect(vectorFile.modelIdentifier == "text-embedding-local")
        #expect(vectorFile.vectorDimension == 2)
        #expect(vectorFile.records.map(\.vector) == vectors)
    }

    @Test("Missing file input throws a readable local indexing error")
    func missingFileInputThrowsReadableError() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-missing-\(UUID().uuidString).txt")
            .standardizedFileURL

        #expect(throws: LocalKnowledgeIndexingError.unreadableFile(path: fileURL.path)) {
            _ = try service.buildIndex(for: [.file(fileURL)])
        }
    }

    @Test("Web page capture extracts readable body text and skips page chrome")
    func webPageCaptureExtractsReadableBodyTextAndSkipsPageChrome() throws {
        let html = """
        <!doctype html>
        <html>
          <head>
            <title>Flannel &amp; Local RAG</title>
            <style>.hidden { display: none; }</style>
            <script>window.bad = "do not index";</script>
          </head>
          <body>
            <nav>Navigation chrome</nav>
            <main>
              <h1>Private page capture</h1>
              <p>Readable DOM paragraphs become local snippets &amp; citations.</p>
              <p>Code samples stay searchable for FROST NEEDLE checks.</p>
            </main>
          </body>
        </html>
        """

        let captured = try WebPageCaptureService.extractReadableContent(
            from: html,
            url: try #require(URL(string: "https://example.com/flannel"))
        )

        #expect(captured.title == "Flannel & Local RAG")
        #expect(captured.text.contains("Private page capture"))
        #expect(captured.text.contains("Readable DOM paragraphs become local snippets & citations."))
        #expect(captured.text.contains("FROST NEEDLE checks"))
        #expect(captured.text.contains("do not index") == false)
        #expect(captured.excerpt.contains("Readable DOM paragraphs"))
    }

    private func writeSearchablePDF(text: String, to fileURL: URL) throws {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        context.beginPDFPage(nil)
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18),
                .foregroundColor: NSColor.black
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let path = CGPath(rect: CGRect(x: 72, y: 640, width: 468, height: 80), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.endPDFPage()
        context.closePDF()
        try data.write(to: fileURL, options: .atomic)
    }

    private func writeSearchableDOCX(text: String, to fileURL: URL) throws {
        let attributedText = NSAttributedString(string: text)
        let data = try attributedText.data(
            from: NSRange(location: 0, length: attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func searchResult(
        title: String,
        sourceIdentifier: String,
        ordinal: Int,
        score: Double,
        matchedTerms: [String]
    ) -> LocalKnowledgeSearchResult {
        let text = "Fixture \(title) chunk \(ordinal): \(matchedTerms.joined(separator: " "))."
        let chunk = LocalKnowledgeChunk(
            id: "\(sourceIdentifier)-\(ordinal)",
            sourceIdentifier: sourceIdentifier,
            knowledgeSourceID: nil,
            sourceTitle: title,
            sourceKind: .workspaceNotes,
            sourceLocation: "flannel://tests/\(sourceIdentifier)",
            ordinal: ordinal,
            characterRange: 0..<text.count,
            text: text,
            normalizedText: matchedTerms.joined(separator: " "),
            termFrequencies: Dictionary(uniqueKeysWithValues: matchedTerms.map { ($0, 1) }),
            titleTermFrequencies: [:],
            locationTermFrequencies: [:],
            contentFingerprint: "\(sourceIdentifier)-\(ordinal)-fingerprint"
        )

        return LocalKnowledgeSearchResult(
            chunk: chunk,
            score: score,
            matchedTerms: matchedTerms,
            snippet: text
        )
    }

    private func sourceSnapshot(
        id: String,
        title: String,
        chunkCount: Int
    ) -> LocalKnowledgeSourceSnapshot {
        LocalKnowledgeSourceSnapshot(
            id: id,
            knowledgeSourceID: nil,
            title: title,
            kind: .workspaceNotes,
            location: "flannel://tests/\(id)",
            contentFingerprint: "\(id)-fingerprint",
            chunkCount: chunkCount
        )
    }

    private func vectorRecord(
        for chunk: LocalKnowledgeChunk,
        vector: [Double]
    ) -> LocalKnowledgeVectorRecord {
        LocalKnowledgeVectorRecord(
            chunkID: chunk.id,
            sourceIdentifier: chunk.sourceIdentifier,
            knowledgeSourceID: chunk.knowledgeSourceID,
            sourceTitle: chunk.sourceTitle,
            sourceKind: chunk.sourceKind,
            sourceLocation: chunk.sourceLocation,
            ordinal: chunk.ordinal,
            contentFingerprint: chunk.contentFingerprint,
            text: chunk.text,
            vector: vector
        )
    }
}
