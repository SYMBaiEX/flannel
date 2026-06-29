//
//  ChatExportService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import AppKit
import CoreGraphics
import CoreText
import Foundation
import UniformTypeIdentifiers

enum ChatExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case json
    case html
    case pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown:
            "Markdown"
        case .json:
            "JSON"
        case .html:
            "HTML"
        case .pdf:
            "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            "md"
        case .json:
            "json"
        case .html:
            "html"
        case .pdf:
            "pdf"
        }
    }

    var contentType: UTType {
        UTType(filenameExtension: fileExtension) ?? .data
    }
}

enum ChatExportError: LocalizedError {
    case failedToCreatePDF
    case emptyPDF

    var errorDescription: String? {
        switch self {
        case .failedToCreatePDF:
            "Flannel could not create a PDF export context."
        case .emptyPDF:
            "Flannel created an empty PDF export."
        }
    }
}

struct ChatExportService: Sendable {
    func export(thread: AssistantThread, format: ChatExportFormat, exportedAt: Date = .now) throws -> Data {
        switch format {
        case .markdown:
            return Data(markdown(thread: thread, exportedAt: exportedAt).utf8)
        case .json:
            return try json(thread: thread, exportedAt: exportedAt)
        case .html:
            return Data(html(thread: thread, exportedAt: exportedAt).utf8)
        case .pdf:
            return try pdf(thread: thread, exportedAt: exportedAt)
        }
    }

    func defaultFilename(for thread: AssistantThread, format: ChatExportFormat) -> String {
        "\(Self.slug(thread.title)).\(format.fileExtension)"
    }

    func markdown(thread: AssistantThread, exportedAt: Date = .now) -> String {
        var lines: [String] = [
            "# \(thread.title)",
            "",
            "- Thread ID: `\(thread.id.uuidString)`",
            "- Exported: \(Self.iso8601.string(from: exportedAt))",
            "- Created: \(Self.iso8601.string(from: thread.createdAt))",
            "- Updated: \(Self.iso8601.string(from: thread.updatedAt))"
        ]

        if !thread.tagNames.isEmpty {
            lines.append("- Tags: \(thread.tagNames.joined(separator: ", "))")
        }

        lines.append("")

        for message in thread.messages {
            let messageID = message.id.uuidString
            lines.append("<!-- flannel-message-start id=\"\(messageID)\" role=\"\(message.role.rawValue)\" createdAt=\"\(Self.iso8601.string(from: message.createdAt))\" -->")
            lines.append("## \(message.role.exportTitle) - \(Self.iso8601.string(from: message.createdAt))")
            lines.append("")

            let metadata = message.exportMetadata
            if !metadata.isEmpty {
                lines.append(metadata.map { "- \($0)" }.joined(separator: "\n"))
                lines.append("")
            }

            lines.append("<!-- flannel-message-text-start id=\"\(messageID)\" -->")
            lines.append(message.text)
            lines.append("<!-- flannel-message-text-end id=\"\(messageID)\" -->")
            lines.append("")

            if !message.toolCalls.isEmpty {
                lines.append("### Requested Tool Calls")
                lines.append("")
                for toolCall in message.toolCalls {
                    lines.append("- \(toolCall.toolName) (\(toolCall.permissionScope.exportTitle); \(toolCall.executionExportTitle))")
                    if let providerCallID = toolCall.providerCallID,
                       !providerCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        lines.append("  - Provider call ID: `\(providerCallID)`")
                    }
                    if let executionResultID = toolCall.executionResultID {
                        lines.append("  - Tool result ID: `\(executionResultID.uuidString)`")
                    }
                    if let outputPreview = toolCall.outputPreview,
                       !outputPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        lines.append("  - Output preview: \(outputPreview)")
                    }
                    if !toolCall.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        lines.append("")
                        lines.append("  ```json")
                        for line in toolCall.argumentsJSON.split(separator: "\n", omittingEmptySubsequences: false).prefix(80) {
                            lines.append("  \(line)")
                        }
                        lines.append("  ```")
                    }
                }
                lines.append("")
            }

            if !message.attachments.isEmpty {
                lines.append("### Attachments")
                lines.append("")
                for attachment in message.attachments {
                    lines.append("- \(attachment.title) (\(attachment.displayDetail))")
                    if let localPath = attachment.localPath {
                        lines.append("  - Path: `\(localPath)`")
                    }
                    if let remoteURL = attachment.remoteURL {
                        lines.append("  - URL: \(remoteURL.absoluteString)")
                    }
                    if let excerpt = attachment.excerpt,
                       !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        lines.append("")
                        lines.append("  ```text")
                        for line in excerpt.split(separator: "\n", omittingEmptySubsequences: false).prefix(80) {
                            lines.append("  \(line)")
                        }
                        lines.append("  ```")
                    }
                }
                lines.append("")
            }

            if !message.citations.isEmpty {
                lines.append("### Sources")
                lines.append("")
                for citation in message.citations {
                    lines.append("- \(citation.title): \(citation.snippet)")
                }
                lines.append("")
            }

            lines.append("<!-- flannel-message-end id=\"\(messageID)\" -->")
            lines.append("")
        }

        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n"
    }

    func html(thread: AssistantThread, exportedAt: Date = .now) -> String {
        let messages = thread.messages.map { message in
            let metadata = message.exportMetadata.map { "<li>\(Self.escapeHTML($0))</li>" }.joined()
            let toolCalls = message.toolCalls.map { toolCall in
                let providerCallID = toolCall.providerCallID.map {
                    "<div class=\"tool-call-id\">\(Self.escapeHTML($0))</div>"
                } ?? ""
                let executionResultID = toolCall.executionResultID.map {
                    "<div class=\"tool-call-id\">Result: \(Self.escapeHTML($0.uuidString))</div>"
                } ?? ""
                let outputPreview = toolCall.outputPreview.map {
                    "<pre>\(Self.escapeHTML($0))</pre>"
                } ?? ""
                let arguments = toolCall.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? ""
                    : "<pre>\(Self.escapeHTML(toolCall.argumentsJSON))</pre>"
                return """
                <li>
                  <strong>\(Self.escapeHTML(toolCall.toolName))</strong>
                  <span>\(Self.escapeHTML(toolCall.permissionScope.exportTitle))</span>
                  <span>\(Self.escapeHTML(toolCall.executionExportTitle))</span>
                  \(providerCallID)
                  \(executionResultID)
                  \(outputPreview)
                  \(arguments)
                </li>
                """
            }.joined()
            let attachments = message.attachments.map { attachment in
                let excerpt = attachment.excerpt.map {
                    "<pre>\(Self.escapeHTML($0))</pre>"
                } ?? ""
                let path = attachment.localPath.map {
                    "<div class=\"attachment-path\">\(Self.escapeHTML($0))</div>"
                } ?? ""
                return """
                <li>
                  <strong>\(Self.escapeHTML(attachment.title))</strong>
                  <span>\(Self.escapeHTML(attachment.displayDetail))</span>
                  \(path)
                  \(excerpt)
                </li>
                """
            }.joined()
            let citations = message.citations.map {
                "<li><strong>\(Self.escapeHTML($0.title))</strong>: \(Self.escapeHTML($0.snippet))</li>"
            }.joined()

            return """
            <article class="message \(message.role.rawValue)">
              <header>
                <h2>\(Self.escapeHTML(message.role.exportTitle))</h2>
                <time>\(Self.escapeHTML(Self.iso8601.string(from: message.createdAt)))</time>
              </header>
              \(metadata.isEmpty ? "" : "<ul class=\"metadata\">\(metadata)</ul>")
              <pre>\(Self.escapeHTML(message.text))</pre>
              \(toolCalls.isEmpty ? "" : "<section class=\"tool-calls\"><h3>Requested Tool Calls</h3><ul>\(toolCalls)</ul></section>")
              \(attachments.isEmpty ? "" : "<section class=\"attachments\"><h3>Attachments</h3><ul>\(attachments)</ul></section>")
              \(citations.isEmpty ? "" : "<section class=\"sources\"><h3>Sources</h3><ul>\(citations)</ul></section>")
            </article>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(Self.escapeHTML(thread.title))</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
            body { margin: 0; padding: 48px; background: Canvas; color: CanvasText; }
            main { max-width: 900px; margin: 0 auto; }
            h1 { margin: 0 0 8px; font-size: 32px; }
            .summary { color: GrayText; margin-bottom: 28px; }
            .message { border: 1px solid color-mix(in srgb, CanvasText 14%, transparent); border-radius: 8px; padding: 18px; margin: 14px 0; }
            .message header { display: flex; align-items: baseline; justify-content: space-between; gap: 16px; }
            .message h2 { font-size: 17px; margin: 0; }
            time, .metadata { color: GrayText; font-size: 13px; }
            pre { white-space: pre-wrap; word-break: break-word; font: inherit; line-height: 1.45; }
            .attachments h3, .sources h3, .tool-calls h3 { font-size: 14px; margin-bottom: 6px; }
            .attachments span, .attachment-path, .tool-calls span, .tool-call-id { display: block; color: GrayText; font-size: 13px; margin-top: 3px; }
            .attachments pre, .tool-calls pre { background: color-mix(in srgb, CanvasText 6%, transparent); border-radius: 8px; padding: 10px; }
          </style>
        </head>
        <body>
          <main>
            <h1>\(Self.escapeHTML(thread.title))</h1>
            <p class="summary">Exported \(Self.escapeHTML(Self.iso8601.string(from: exportedAt))) from Flannel. Thread \(Self.escapeHTML(thread.id.uuidString)).</p>
            \(messages)
          </main>
        </body>
        </html>
        """
    }

    private func json(thread: AssistantThread, exportedAt: Date) throws -> Data {
        let payload = ChatExportPayload(
            schemaVersion: 1,
            exportedAt: exportedAt,
            thread: thread
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private func pdf(thread: AssistantThread, exportedAt: Date) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw ChatExportError.failedToCreatePDF
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ChatExportError.failedToCreatePDF
        }

        let attributed = NSAttributedString(
            string: plainText(thread: thread, exportedAt: exportedAt),
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var range = CFRange(location: 0, length: 0)
        let pageRect = CGRect(x: 48, y: 48, width: mediaBox.width - 96, height: mediaBox.height - 96)

        while range.location < attributed.length {
            context.beginPDFPage(nil)
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: 0, y: mediaBox.height)
            context.scaleBy(x: 1, y: -1)

            let path = CGMutablePath()
            path.addRect(pageRect)
            let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
            CTFrameDraw(frame, context)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            range.location += max(visibleRange.length, 1)

            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        guard data.length > 0 else { throw ChatExportError.emptyPDF }
        return data as Data
    }

    private func plainText(thread: AssistantThread, exportedAt: Date) -> String {
        markdown(thread: thread, exportedAt: exportedAt)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<!-- flannel-message-") }
            .joined(separator: "\n")
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "`", with: "")
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func slug(_ value: String) -> String {
        let cleaned = value
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : "-" }
        let slug = String(cleaned)
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return slug.isEmpty ? "flannel-chat" : slug
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private struct ChatExportPayload: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var thread: AssistantThread
}

private extension AssistantRole {
    var exportTitle: String {
        switch self {
        case .system:
            "System"
        case .user:
            "User"
        case .assistant:
            "Assistant"
        }
    }
}

private extension AIToolPermissionScope {
    var exportTitle: String {
        switch self {
        case .readWorkspace:
            "Read workspace"
        case .writeWorkspace:
            "Write workspace"
        case .runShellCommand:
            "Run shell command"
        case .makeNetworkRequest:
            "Network request"
        case .queryRAGIndex:
            "Query RAG index"
        case .mutateRAGIndex:
            "Mutate RAG index"
        }
    }
}

private extension AIToolCallRecord {
    var executionExportTitle: String {
        executionStatus?.exportTitle ?? "Pending"
    }
}

private extension LocalToolExecutionStatus {
    var exportTitle: String {
        switch self {
        case .completed:
            "Executed"
        case .requiresApproval:
            "Approval required"
        case .denied:
            "Denied"
        case .blocked:
            "Blocked"
        case .unavailable:
            "Unavailable"
        }
    }
}

private extension AssistantMessage {
    var exportMetadata: [String] {
        var values: [String] = []
        if let runStatus {
            values.append("Status: \(runStatus.title)")
        }
        if let providerDisplayName,
           !providerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values.append("Provider: \(providerDisplayName)")
        }
        if let providerAccessMode {
            values.append("Provider mode: \(providerAccessMode.title)")
        }
        if let providerPrivacyScope {
            values.append("Privacy scope: \(providerPrivacyScope.title)")
        }
        if let modelIdentifier,
           !modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values.append("Model: \(modelIdentifier)")
        }
        if let startedAt {
            values.append("Started: \(Self.metadataDate(startedAt))")
        }
        if let completedAt {
            values.append("Completed: \(Self.metadataDate(completedAt))")
        }
        if let inputTokenCount {
            values.append("Input tokens: \(inputTokenCount)")
        }
        if let outputTokenCount {
            values.append("Output tokens: \(outputTokenCount)")
        }
        if tokenCountsAreEstimated, inputTokenCount != nil || outputTokenCount != nil {
            values.append("Token counts: estimated")
        }
        if let contextTokenCount {
            if let contextWindowTokens {
                values.append("Context tokens: \(contextTokenCount) / \(contextWindowTokens)")
            } else {
                values.append("Context tokens: \(contextTokenCount)")
            }
        }
        if let latencyMilliseconds {
            values.append("Latency: \(latencyMilliseconds) ms")
        }
        if let firstTokenLatencyMilliseconds {
            values.append("First token latency: \(firstTokenLatencyMilliseconds) ms")
        }
        if let estimatedCostMicros {
            values.append("Estimated cost micros: \(estimatedCostMicros)")
        }
        if let fallbackReason = fallbackReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallbackReason.isEmpty {
            values.append("Fallback reason: \(fallbackReason)")
        }
        return values
    }

    private static func metadataDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
