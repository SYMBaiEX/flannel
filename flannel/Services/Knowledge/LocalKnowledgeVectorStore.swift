//
//  LocalKnowledgeVectorStore.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

nonisolated struct LocalKnowledgeVectorRecord: Codable, Hashable, Sendable {
    var chunkID: String
    var sourceIdentifier: String
    var knowledgeSourceID: UUID?
    var sourceTitle: String
    var sourceKind: KnowledgeSourceKind
    var sourceLocation: String
    var ordinal: Int
    var contentFingerprint: String
    var text: String
    var vector: [Double]
}

nonisolated struct LocalKnowledgeVectorIndexFile: Codable, Hashable, Sendable {
    var version: Int
    var sourceID: UUID?
    var title: String
    var modelIdentifier: String
    var vectorDimension: Int
    var contentFingerprint: String
    var builtAt: Date
    var records: [LocalKnowledgeVectorRecord]

    init(
        version: Int = 1,
        sourceID: UUID?,
        title: String,
        modelIdentifier: String,
        vectorDimension: Int,
        contentFingerprint: String,
        builtAt: Date,
        records: [LocalKnowledgeVectorRecord]
    ) {
        self.version = version
        self.sourceID = sourceID
        self.title = title
        self.modelIdentifier = modelIdentifier
        self.vectorDimension = vectorDimension
        self.contentFingerprint = contentFingerprint
        self.builtAt = builtAt
        self.records = records
    }
}

nonisolated struct LocalKnowledgeVectorRecordGroup: Hashable, Sendable {
    var modelIdentifier: String
    var vectorDimension: Int
    var embeddingProviderKind: LLMProviderKind?
    var records: [LocalKnowledgeVectorRecord]
}

nonisolated struct LocalKnowledgeVectorStore {
    typealias ProviderEmbeddingGenerator = @Sendable (
        ProviderConfiguration,
        String,
        [String]
    ) async throws -> LocalEmbeddingResult

    var fileManager: FileManager
    var embeddingService: LocalEmbeddingService
    var providerEmbeddingGenerator: ProviderEmbeddingGenerator

    init(
        fileManager: FileManager = .default,
        embeddingService: LocalEmbeddingService = LocalEmbeddingService(),
        providerEmbeddingGenerator: ProviderEmbeddingGenerator? = nil
    ) {
        self.fileManager = fileManager
        self.embeddingService = embeddingService
        self.providerEmbeddingGenerator = providerEmbeddingGenerator ?? { provider, modelIdentifier, inputs in
            try await embeddingService.embed(
                LocalEmbeddingRequest(
                    provider: provider,
                    modelIdentifier: modelIdentifier,
                    inputs: inputs
                )
            )
        }
    }

    func buildVectorIndexFile(
        for index: LocalKnowledgeIndex,
        sourceID: UUID?,
        title: String,
        modelIdentifier: String,
        contentFingerprint: String,
        builtAt: Date,
        vectorDimension: Int = LocalEmbeddingService.defaultLocalVectorDimension
    ) -> LocalKnowledgeVectorIndexFile {
        let records = index.chunks.map { chunk in
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
                vector: embeddingService.deterministicLocalVector(
                    for: chunk.text,
                    dimensions: vectorDimension
                )
            )
        }

        return LocalKnowledgeVectorIndexFile(
            sourceID: sourceID,
            title: title,
            modelIdentifier: modelIdentifier,
            vectorDimension: vectorDimension,
            contentFingerprint: contentFingerprint,
            builtAt: builtAt,
            records: records
        )
    }

    func buildVectorIndexFile(
        for index: LocalKnowledgeIndex,
        sourceID: UUID?,
        title: String,
        modelIdentifier: String,
        embeddingProvider: ProviderConfiguration?,
        contentFingerprint: String,
        builtAt: Date,
        vectorDimension: Int = LocalEmbeddingService.defaultLocalVectorDimension
    ) async throws -> LocalKnowledgeVectorIndexFile {
        let requestedModel = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let embeddingProvider,
              !requestedModel.isEmpty,
              requestedModel != LocalEmbeddingService.deterministicModelIdentifier else {
            return buildVectorIndexFile(
                for: index,
                sourceID: sourceID,
                title: title,
                modelIdentifier: requestedModel.isEmpty ? LocalEmbeddingService.deterministicModelIdentifier : requestedModel,
                contentFingerprint: contentFingerprint,
                builtAt: builtAt,
                vectorDimension: vectorDimension
            )
        }

        let result = try await providerEmbeddingGenerator(
            embeddingProvider,
            requestedModel,
            index.chunks.map(\.text)
        )
        return try buildVectorIndexFile(
            for: index,
            sourceID: sourceID,
            title: title,
            modelIdentifier: result.modelIdentifier,
            contentFingerprint: contentFingerprint,
            builtAt: builtAt,
            vectors: result.vectors
        )
    }

    func buildVectorIndexFile(
        for index: LocalKnowledgeIndex,
        sourceID: UUID?,
        title: String,
        modelIdentifier: String,
        contentFingerprint: String,
        builtAt: Date,
        vectors: [[Double]]
    ) throws -> LocalKnowledgeVectorIndexFile {
        guard vectors.count == index.chunks.count else {
            throw LocalKnowledgeVectorStoreError.embeddingCountMismatch(
                expected: index.chunks.count,
                actual: vectors.count
            )
        }

        let vectorDimension = try validatedVectorDimension(vectors)
        let records = zip(index.chunks, vectors).map { chunk, vector in
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

        return LocalKnowledgeVectorIndexFile(
            sourceID: sourceID,
            title: title,
            modelIdentifier: modelIdentifier,
            vectorDimension: vectorDimension,
            contentFingerprint: contentFingerprint,
            builtAt: builtAt,
            records: records
        )
    }

    @discardableResult
    func write(
        _ vectorIndexFile: LocalKnowledgeVectorIndexFile,
        to storageLocation: String
    ) throws -> URL {
        let url = fileURL(for: storageLocation)
        let directoryURL = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(vectorIndexFile)
        try data.write(to: url, options: [.atomic])
        return url
    }

    func read(from storageLocation: String) throws -> LocalKnowledgeVectorIndexFile {
        let url = fileURL(for: storageLocation)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LocalKnowledgeVectorIndexFile.self, from: data)
    }

    func loadRecords(
        from manifests: [KnowledgeIndexManifest],
        matching index: LocalKnowledgeIndex
    ) -> [LocalKnowledgeVectorRecord] {
        loadRecordGroups(from: manifests, matching: index).flatMap(\.records)
    }

    func loadRecordGroups(
        from manifests: [KnowledgeIndexManifest],
        matching index: LocalKnowledgeIndex
    ) -> [LocalKnowledgeVectorRecordGroup] {
        let chunksByID = Dictionary(uniqueKeysWithValues: index.chunks.map { ($0.id, $0) })
        var groups: [LocalKnowledgeVectorRecordGroup] = []

        for manifest in manifests where manifest.status == .ready && manifest.embeddingRecordCount > 0 {
            guard let vectorIndexFile = try? read(from: manifest.storageLocation),
                  vectorIndexFile.contentFingerprint == manifest.contentFingerprint else {
                continue
            }

            let validRecords = vectorIndexFile.records.filter { record in
                guard let chunk = chunksByID[record.chunkID] else {
                    return false
                }
                return chunk.contentFingerprint == record.contentFingerprint
            }
            guard !validRecords.isEmpty else { continue }
            groups.append(
                LocalKnowledgeVectorRecordGroup(
                    modelIdentifier: vectorIndexFile.modelIdentifier,
                    vectorDimension: vectorIndexFile.vectorDimension,
                    embeddingProviderKind: manifest.embeddingProviderKind,
                    records: validRecords
                )
            )
        }

        return groups
    }

    func fileURL(for storageLocation: String) -> URL {
        let expanded = (storageLocation as NSString).expandingTildeInPath
        if let parsedURL = URL(string: expanded), parsedURL.isFileURL {
            return parsedURL.standardizedFileURL
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    private func validatedVectorDimension(_ vectors: [[Double]]) throws -> Int {
        guard let firstVector = vectors.first,
              !firstVector.isEmpty else {
            throw LocalKnowledgeVectorStoreError.emptyEmbeddingVector
        }
        let dimension = firstVector.count
        guard vectors.allSatisfy({ $0.count == dimension && !$0.isEmpty }) else {
            throw LocalKnowledgeVectorStoreError.inconsistentEmbeddingDimensions
        }
        return dimension
    }
}

nonisolated enum LocalKnowledgeVectorStoreError: LocalizedError, Equatable {
    case embeddingCountMismatch(expected: Int, actual: Int)
    case emptyEmbeddingVector
    case inconsistentEmbeddingDimensions

    var errorDescription: String? {
        switch self {
        case .embeddingCountMismatch(let expected, let actual):
            "The embedding provider returned \(actual) vectors for \(expected) indexed chunks."
        case .emptyEmbeddingVector:
            "The embedding provider returned an empty vector."
        case .inconsistentEmbeddingDimensions:
            "The embedding provider returned vectors with inconsistent dimensions."
        }
    }
}
