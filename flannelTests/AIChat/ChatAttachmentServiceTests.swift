//
//  ChatAttachmentServiceTests.swift
//  flannelTests
//

import Foundation
import AppKit
import CoreText
import Testing
@testable import flannel

struct ChatAttachmentServiceTests {
    @Test("Local text import records metadata and a safe excerpt")
    func localTextImportRecordsMetadataAndExcerpt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-attachment-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("notes.md")
        try "# Private Notes\nUse local context only.".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = ChatAttachmentService(maximumExcerptBytes: 256).importAttachments(from: [fileURL])
        let attachment = try #require(result.attachments.first)

        #expect(result.failures.isEmpty)
        #expect(attachment.kind == .textSnippet)
        #expect(attachment.title == "notes.md")
        #expect(attachment.localPath?.hasSuffix("notes.md") == true)
        #expect(attachment.byteCount ?? 0 > 0)
        #expect(attachment.excerpt?.contains("Private Notes") == true)
        #expect(attachment.promptContextBlock.contains("Attached") == false)
        #expect(attachment.promptContextBlock.contains("Excerpt:"))
    }

    @Test("PDF attachment import extracts searchable prompt context")
    func pdfAttachmentImportExtractsSearchablePromptContext() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("research-brief.pdf")
        try writeSearchablePDF(
            text: "PDF AMBER LANTERN roadmap notes should be visible to the chat model.",
            to: fileURL
        )

        let result = ChatAttachmentService(maximumExcerptBytes: 256).importAttachments(from: [fileURL])
        let attachment = try #require(result.attachments.first)

        #expect(result.failures.isEmpty)
        #expect(attachment.kind == .document)
        #expect(attachment.title == "research-brief.pdf")
        #expect(attachment.mimeType == "application/pdf")
        #expect(attachment.excerpt?.contains("AMBER LANTERN") == true)
        #expect(attachment.promptContextBlock.contains("PDF AMBER LANTERN"))
    }

    @Test("DOCX attachment import extracts searchable prompt context")
    func docxAttachmentImportExtractsSearchablePromptContext() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("strategy.docx")
        try writeSearchableDOCX(
            text: "DOCX FROST NEEDLE launch details should travel with the prompt.",
            to: fileURL
        )

        let result = ChatAttachmentService(maximumExcerptBytes: 256).importAttachments(from: [fileURL])
        let attachment = try #require(result.attachments.first)

        #expect(result.failures.isEmpty)
        #expect(attachment.kind == .document)
        #expect(attachment.title == "strategy.docx")
        #expect(attachment.excerpt?.contains("FROST NEEDLE") == true)
        #expect(attachment.promptContextBlock.contains("DOCX FROST NEEDLE"))
    }

    @Test("Directory attachment import creates a capped local repository preview")
    func directoryAttachmentImportCreatesRepositoryPreview() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("node_modules/left-pad", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "print(\"alpha\")".write(
            to: directory.appendingPathComponent("Sources/App.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "# Project".write(
            to: directory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "should be skipped".write(
            to: directory.appendingPathComponent("node_modules/left-pad/index.js"),
            atomically: true,
            encoding: .utf8
        )

        let result = ChatAttachmentService(
            maximumExcerptBytes: 512,
            maximumDirectoryPreviewFiles: 4
        )
        .importAttachments(from: [directory])
        let attachment = try #require(result.attachments.first)
        let excerpt = try #require(attachment.excerpt)

        #expect(result.failures.isEmpty)
        #expect(attachment.kind == .workspaceAsset)
        #expect(excerpt.contains("Directory preview:"))
        #expect(excerpt.contains("Git repository or code workspace"))
        #expect(excerpt.contains("Supported files found: 2"))
        #expect(excerpt.contains("README.md"))
        #expect(excerpt.contains("Sources/App.swift"))
        #expect(!excerpt.contains("node_modules"))
        #expect(attachment.promptContextBlock.contains("Directory preview:"))
    }

    @Test("Directory attachment preview reports capped file counts")
    func directoryAttachmentPreviewReportsCappedRows() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0..<5 {
            try "note \(index)".write(
                to: directory.appendingPathComponent("note-\(index).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let result = ChatAttachmentService(
            maximumDirectoryPreviewFiles: 2,
            maximumDirectoryScanFiles: 10
        )
        .importAttachments(from: [directory])
        let excerpt = try #require(result.attachments.first?.excerpt)

        #expect(excerpt.contains("Supported files found: 5"))
        #expect(excerpt.contains("Preview files:"))
        #expect(excerpt.contains("...and 3 more supported files."))
    }

    @Test("Attachment prompt context combines message text with file metadata")
    func attachmentPromptContextCombinesMessageAndMetadata() {
        let message = AssistantMessage(
            role: .user,
            text: "Summarize this.",
            attachments: [
                AIChatAttachment(
                    kind: .textSnippet,
                    title: "brief.txt",
                    mimeType: "text/plain",
                    localPath: "/tmp/brief.txt",
                    byteCount: 42,
                    excerpt: "Private launch notes."
                )
            ]
        )

        #expect(message.textWithAttachmentPromptContext.contains("Summarize this."))
        #expect(message.textWithAttachmentPromptContext.contains("Attached files:"))
        #expect(message.textWithAttachmentPromptContext.contains("brief.txt"))
        #expect(message.textWithAttachmentPromptContext.contains("Private launch notes."))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-attachment-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
}
