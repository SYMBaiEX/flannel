//
//  KnowledgeSourceWatchServiceTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation
import Testing
@testable import flannel

struct KnowledgeSourceWatchServiceTests {
    @Test("Watch descriptors include only watched local folder and repository roots")
    func watchDescriptorsIncludeOnlyWatchedLocalRoots() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-watch-folder-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-watch-repo-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        let ignoredURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-watch-ignored-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        defer {
            try? FileManager.default.removeItem(at: folderURL)
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: ignoredURL)
        }

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ignoredURL, withIntermediateDirectories: true)

        let watchedFolder = KnowledgeSource(
            title: "Watched folder",
            kind: .folder,
            location: folderURL.path,
            isWatched: true
        )
        let watchedRepo = KnowledgeSource(
            title: "Watched repo",
            kind: .codeRepository,
            location: repoURL.path,
            isWatched: true
        )
        let manualFolder = KnowledgeSource(
            title: "Manual folder",
            kind: .folder,
            location: ignoredURL.path,
            isWatched: false
        )
        let watchedWebPage = KnowledgeSource(
            title: "Watched page",
            kind: .webPage,
            location: "https://example.com",
            isWatched: true
        )
        let missingFolder = KnowledgeSource(
            title: "Missing folder",
            kind: .folder,
            location: folderURL.appendingPathComponent("missing", isDirectory: true).path,
            isWatched: true
        )

        let descriptors = KnowledgeSourceWatchService.watchDescriptors(
            for: [watchedFolder, watchedRepo, manualFolder, watchedWebPage, missingFolder]
        )

        #expect(descriptors.map(\.sourceID) == [watchedFolder.id, watchedRepo.id])
        #expect(descriptors.map(\.rootPath) == [folderURL.path, repoURL.path])
        #expect(descriptors.allSatisfy { $0.kind.supportsFileSystemWatching })
    }
}
