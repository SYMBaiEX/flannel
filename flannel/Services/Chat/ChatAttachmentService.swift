//
//  ChatAttachmentService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

struct ChatAttachmentImportFailure: Identifiable, Hashable, Sendable {
    var id = UUID()
    var url: URL
    var message: String
}

struct ChatAttachmentImportResult: Sendable {
    var attachments: [AIChatAttachment]
    var failures: [ChatAttachmentImportFailure]
}

struct ChatAttachmentService: Sendable {
    var maximumExcerptBytes: Int

    init(maximumExcerptBytes: Int = 24_000) {
        self.maximumExcerptBytes = maximumExcerptBytes
    }

    func importAttachments(from urls: [URL]) -> ChatAttachmentImportResult {
        var attachments: [AIChatAttachment] = []
        var failures: [ChatAttachmentImportFailure] = []

        for url in urls {
            do {
                attachments.append(try attachment(from: url))
            } catch {
                failures.append(
                    ChatAttachmentImportFailure(
                        url: url,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return ChatAttachmentImportResult(attachments: attachments, failures: failures)
    }

    func attachment(from url: URL) throws -> AIChatAttachment {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try url.resourceValues(forKeys: [
            .contentTypeKey,
            .fileSizeKey,
            .isDirectoryKey,
            .localizedNameKey
        ])

        let contentType = resourceValues.contentType ?? UTType(filenameExtension: url.pathExtension)
        let kind = attachmentKind(for: contentType, isDirectory: resourceValues.isDirectory == true)
        let byteCount = resourceValues.fileSize.map(Int64.init)
        let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        let excerpt = try excerpt(from: url, contentType: contentType, kind: kind)

        return AIChatAttachment(
            kind: kind,
            title: resourceValues.localizedName ?? url.lastPathComponent,
            mimeType: contentType?.preferredMIMEType,
            localPath: url.standardizedFileURL.path,
            byteCount: byteCount,
            excerpt: excerpt,
            securityScopedBookmarkData: bookmarkData
        )
    }

    private func attachmentKind(for contentType: UTType?, isDirectory: Bool) -> AIChatAttachmentKind {
        if isDirectory {
            return .document
        }

        guard let contentType else {
            return .document
        }

        if contentType.conforms(to: .image) {
            return .image
        }
        if contentType.conforms(to: .audio) || contentType.conforms(to: .movie) {
            return .audio
        }
        if Self.isTextLike(contentType) {
            return .textSnippet
        }
        return .document
    }

    private func excerpt(from url: URL, contentType: UTType?, kind: AIChatAttachmentKind) throws -> String? {
        if isPDF(url, contentType: contentType),
           let text = decodePDFText(from: url) {
            return normalizedExcerpt(from: text)
        }

        if isDOCX(url, contentType: contentType),
           let text = decodeDOCXText(from: url) {
            return normalizedExcerpt(from: text)
        }

        guard kind == .textSnippet || contentType.map(Self.isTextLike) == true else {
            return nil
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: maximumExcerptBytes) ?? Data()
        guard !data.isEmpty else { return nil }

        let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .ascii)

        guard let decoded else { return nil }

        return normalizedExcerpt(from: decoded)
    }

    private nonisolated static func isTextLike(_ contentType: UTType) -> Bool {
        contentType.conforms(to: .plainText)
            || contentType.conforms(to: .text)
            || contentType.conforms(to: .sourceCode)
            || contentType.conforms(to: .json)
            || contentType.conforms(to: .xml)
            || contentType.identifier.contains("markdown")
    }

    private nonisolated func isPDF(_ url: URL, contentType: UTType?) -> Bool {
        contentType?.conforms(to: .pdf) == true
            || url.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame
    }

    private nonisolated func isDOCX(_ url: URL, contentType: UTType?) -> Bool {
        url.pathExtension.localizedCaseInsensitiveCompare("docx") == .orderedSame
            || contentType?.identifier.localizedCaseInsensitiveContains("wordprocessingml") == true
    }

    private nonisolated func decodePDFText(from url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        let pageText = (0..<document.pageCount).compactMap { pageIndex in
            document.page(at: pageIndex)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let text = pageText.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    private nonisolated func decodeDOCXText(from url: URL) -> String? {
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

    private nonisolated func normalizedExcerpt(from text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        return normalized.count > 8_000
            ? String(normalized.prefix(8_000)) + "\n[Excerpt truncated]"
            : normalized
    }
}

extension AIChatAttachment {
    nonisolated var kindLabel: String {
        switch kind {
        case .textSnippet:
            "Text"
        case .image:
            "Image"
        case .document:
            "Document"
        case .audio:
            "Audio"
        case .workspaceAsset:
            "Workspace asset"
        case .externalURL:
            "URL"
        case .ragChunk:
            "RAG chunk"
        case .toolResult:
            "Tool result"
        }
    }

    nonisolated var displayDetail: String {
        var parts: [String] = [kindLabel]
        if let byteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
        }
        if let mimeType,
           !mimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(mimeType)
        }
        return parts.joined(separator: " · ")
    }

    nonisolated var promptContextBlock: String {
        var lines = [
            "Attachment: \(title)",
            "Kind: \(kindLabel)"
        ]

        if let mimeType {
            lines.append("MIME: \(mimeType)")
        }
        if let byteCount {
            lines.append("Size: \(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))")
        }
        if let localPath {
            lines.append("Local path: \(localPath)")
        }
        if let remoteURL {
            lines.append("URL: \(remoteURL.absoluteString)")
        }
        if let excerpt,
           !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Excerpt:\n\(excerpt)")
        }

        return lines.joined(separator: "\n")
    }
}

extension Array where Element == AIChatAttachment {
    nonisolated var promptContextBlock: String {
        guard !isEmpty else { return "" }

        return (["Attached files:"] + map(\.promptContextBlock))
            .joined(separator: "\n\n")
    }
}

extension AssistantMessage {
    nonisolated var textWithAttachmentPromptContext: String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentContext = attachments.promptContextBlock
        return [trimmedText, attachmentContext]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
}
