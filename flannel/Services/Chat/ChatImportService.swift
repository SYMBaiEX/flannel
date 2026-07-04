//
//  ChatImportService.swift
//  flannel
//

import Foundation
import UniformTypeIdentifiers

nonisolated enum ChatImportError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case emptyThread
    case unsupportedFormat(String)
    case unreadableText

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Flannel cannot import chat export schema version \(version)."
        case .emptyThread:
            "The selected file does not contain a chat thread."
        case .unsupportedFormat(let format):
            "Flannel cannot import \(format) chat transcripts yet."
        case .unreadableText:
            "Flannel could not read the selected transcript as UTF-8 text."
        }
    }
}

nonisolated enum ChatImportFormat: String, CaseIterable, Identifiable, Sendable {
    case json
    case markdown
    case html

    var id: String { rawValue }

    static var allowedContentTypes: [UTType] {
        [
            .json,
            .html,
            UTType(filenameExtension: "htm")
        ].compactMap(\.self) + markdownContentTypes
    }

    private static var markdownContentTypes: [UTType] {
        [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(importedAs: "net.daringfireball.markdown")
        ].compactMap(\.self)
    }

    static func inferred(from url: URL, contentType: UTType? = nil) -> ChatImportFormat? {
        if let contentType {
            if contentType.conforms(to: .json) {
                return .json
            }
            if contentType.conforms(to: .html) {
                return .html
            }
            if markdownContentTypes.contains(where: { contentType.conforms(to: $0) }) {
                return .markdown
            }
        }

        return inferred(from: url)
    }

    static func inferred(from url: URL) -> ChatImportFormat? {
        switch url.pathExtension.lowercased() {
        case "json":
            .json
        case "md", "markdown":
            .markdown
        case "html", "htm":
            .html
        default:
            nil
        }
    }
}

nonisolated struct ChatImportResult: Sendable {
    var thread: AssistantThread
    var originalThreadID: UUID
    var exportedAt: Date?
    var warnings: [String]

    init(
        thread: AssistantThread,
        originalThreadID: UUID,
        exportedAt: Date?,
        warnings: [String] = []
    ) {
        self.thread = thread
        self.originalThreadID = originalThreadID
        self.exportedAt = exportedAt
        self.warnings = warnings
    }
}

nonisolated struct ChatImportService: Sendable {
    func importThread(from data: Data, importedAt: Date = .now) throws -> ChatImportResult {
        try importJSONThread(from: data, importedAt: importedAt)
    }

    func importThread(from data: Data, sourceURL: URL, importedAt: Date = .now) throws -> ChatImportResult {
        try importThread(from: data, sourceURL: sourceURL, contentType: nil, importedAt: importedAt)
    }

    func importThread(
        from data: Data,
        sourceURL: URL,
        contentType: UTType?,
        importedAt: Date = .now
    ) throws -> ChatImportResult {
        guard let format = ChatImportFormat.inferred(from: sourceURL, contentType: contentType) else {
            throw ChatImportError.unsupportedFormat(sourceURL.pathExtension.isEmpty ? "this file" : ".\(sourceURL.pathExtension)")
        }

        return try importThread(from: data, format: format, importedAt: importedAt)
    }

    func importThread(from data: Data, format: ChatImportFormat, importedAt: Date = .now) throws -> ChatImportResult {
        switch format {
        case .json:
            return try importJSONThread(from: data, importedAt: importedAt)
        case .markdown:
            return try importMarkdownThread(from: data, importedAt: importedAt)
        case .html:
            return try importHTMLThread(from: data, importedAt: importedAt)
        }
    }

    private func importJSONThread(from data: Data, importedAt: Date) throws -> ChatImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ChatImportPayload.self, from: data)

        guard payload.schemaVersion == 1 else {
            throw ChatImportError.unsupportedSchemaVersion(payload.schemaVersion)
        }

        let thread = makeLocalCopy(of: payload.thread, importedAt: importedAt)
        guard !thread.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !thread.messages.isEmpty else {
            throw ChatImportError.emptyThread
        }

        return ChatImportResult(
            thread: thread,
            originalThreadID: payload.thread.id,
            exportedAt: payload.exportedAt
        )
    }

    private func importMarkdownThread(from data: Data, importedAt: Date) throws -> ChatImportResult {
        let transcript = try text(from: data)
        let lines = transcript.components(separatedBy: .newlines)
        let exportedAt = exportedAtFromMarkdown(lines)
        let title = markdownTitle(lines) ?? "Imported Markdown Chat"
        let parsedMessages = markdownMessages(lines, importedAt: importedAt)
        let sourceThread = AssistantThread(
            title: title,
            mode: .research,
            messages: parsedMessages,
            createdAt: parsedMessages.first?.createdAt ?? importedAt,
            updatedAt: importedAt
        )
        return try importedResult(
            from: sourceThread,
            exportedAt: exportedAt,
            importedAt: importedAt,
            warnings: [Self.textOnlyImportWarning(format: "Markdown")]
        )
    }

    private func importHTMLThread(from data: Data, importedAt: Date) throws -> ChatImportResult {
        let transcript = try text(from: data)
        let title = firstHTMLCapture(in: transcript, pattern: #"<h1[^>]*>(.*?)</h1>"#)
            .map(decodeHTML)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "Imported HTML Chat"
        let exportedAt = firstHTMLCapture(in: transcript, pattern: #"Exported\s+([^<\s]+)\s+from Flannel"#)
            .flatMap(parseDate)
        let messages = htmlArticleMatches(transcript).enumerated().compactMap { offset, article -> AssistantMessage? in
            let body = firstHTMLCapture(in: article.body, pattern: #"<pre[^>]*>(.*?)</pre>"#)
                .map(decodeHTML)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !body.isEmpty else { return nil }
            let createdAt = firstHTMLCapture(in: article.body, pattern: #"<time[^>]*>(.*?)</time>"#)
                .map(decodeHTML)
                .flatMap(parseDate)
                ?? importedAt.addingTimeInterval(Double(offset))
            return AssistantMessage(
                role: article.role,
                text: body,
                createdAt: createdAt
            )
        }
        let sourceThread = AssistantThread(
            title: title,
            mode: .research,
            messages: messages,
            createdAt: messages.first?.createdAt ?? importedAt,
            updatedAt: importedAt
        )
        return try importedResult(
            from: sourceThread,
            exportedAt: exportedAt,
            importedAt: importedAt,
            warnings: [Self.textOnlyImportWarning(format: "HTML")]
        )
    }

    private func importedResult(
        from sourceThread: AssistantThread,
        exportedAt: Date?,
        importedAt: Date,
        warnings: [String] = []
    ) throws -> ChatImportResult {
        let thread = makeLocalCopy(of: sourceThread, importedAt: importedAt)
        guard !thread.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !thread.messages.isEmpty else {
            throw ChatImportError.emptyThread
        }

        return ChatImportResult(
            thread: thread,
            originalThreadID: sourceThread.id,
            exportedAt: exportedAt,
            warnings: warnings
        )
    }

    private func makeLocalCopy(of thread: AssistantThread, importedAt: Date) -> AssistantThread {
        let copiedMessages = thread.messages.map(makeLocalCopy(of:))
        let title = thread.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Imported Chat"
            : thread.title

        return AssistantThread(
            title: title,
            mode: thread.mode,
            messages: copiedMessages,
            isPinned: thread.isPinned,
            isArchived: false,
            tagNames: importedTags(from: thread.tagNames),
            knowledgeSourceIDs: thread.knowledgeSourceIDs,
            folderID: nil,
            pinnedProjectID: nil,
            pinnedDraftID: nil,
            pinnedAssetID: nil,
            pinnedCalendarEntryID: nil,
            promptChainID: thread.promptChainID,
            activePromptChainStepID: thread.activePromptChainStepID,
            completedPromptChainStepIDs: thread.completedPromptChainStepIDs,
            createdAt: thread.createdAt,
            updatedAt: importedAt
        )
    }

    private func makeLocalCopy(of message: AssistantMessage) -> AssistantMessage {
        AssistantMessage(
            role: message.role,
            text: message.text,
            attachments: message.attachments,
            createdAt: message.createdAt,
            updatedAt: message.updatedAt,
            isPinned: message.isPinned,
            referencedEntityIDs: [],
            promptChainStepID: message.promptChainStepID,
            citations: message.citations,
            providerDisplayName: message.providerDisplayName,
            modelIdentifier: message.modelIdentifier,
            inputTokenCount: message.inputTokenCount,
            outputTokenCount: message.outputTokenCount,
            latencyMilliseconds: message.latencyMilliseconds,
            firstTokenLatencyMilliseconds: message.firstTokenLatencyMilliseconds,
            estimatedCostMicros: message.estimatedCostMicros,
            providerAccessMode: message.providerAccessMode,
            providerPrivacyScope: message.providerPrivacyScope,
            runStatus: message.runStatus,
            startedAt: message.startedAt,
            completedAt: message.completedAt,
            contextTokenCount: message.contextTokenCount,
            contextWindowTokens: message.contextWindowTokens,
            tokenCountsAreEstimated: message.tokenCountsAreEstimated,
            fallbackReason: message.fallbackReason,
            toolCalls: message.toolCalls
        )
    }

    private func importedTags(from tagNames: [String]) -> [String] {
        let normalizedTags = tagNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedTags.contains(where: { $0.localizedCaseInsensitiveCompare("imported") == .orderedSame }) else {
            return normalizedTags
        }
        return normalizedTags + ["imported"]
    }

    private func text(from data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ChatImportError.unreadableText
        }
        return text
    }

    private func markdownTitle(_ lines: [String]) -> String? {
        lines.lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("# ") }
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private func exportedAtFromMarkdown(_ lines: [String]) -> Date? {
        lines.lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.localizedCaseInsensitiveContains("- Exported:") }
            .flatMap { line in
                guard let range = line.range(of: ":") else { return nil }
                return parseDate(String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
    }

    private func markdownMessages(_ lines: [String], importedAt: Date) -> [AssistantMessage] {
        let markedMessages = flannelMarkedMarkdownMessages(lines, importedAt: importedAt)
        guard markedMessages.isEmpty else { return markedMessages }
        return legacyMarkdownMessages(lines, importedAt: importedAt)
    }

    private func flannelMarkedMarkdownMessages(_ lines: [String], importedAt: Date) -> [AssistantMessage] {
        var messages: [AssistantMessage] = []
        var cursor = 0

        while cursor < lines.count {
            guard isMarkdownMarker(lines[cursor], named: "flannel-message-start") else {
                cursor += 1
                continue
            }

            let startLine = lines[cursor]
            let messageID = htmlAttribute("id", in: startLine)
            let role = htmlAttribute("role", in: startLine).flatMap(role(from:)) ?? .assistant
            let createdAt = htmlAttribute("createdAt", in: startLine).flatMap(parseDate)
                ?? importedAt.addingTimeInterval(Double(messages.count))
            let blockStart = cursor + 1
            let blockEnd = nextMarkerIndex(
                in: lines,
                startingAt: blockStart,
                names: ["flannel-message-end"],
                id: messageID
            ) ?? nextMarkerIndex(
                in: lines,
                startingAt: blockStart,
                names: ["flannel-message-start"]
            ) ?? lines.count
            let blockLines = Array(lines[blockStart..<blockEnd])
            let parsedBody = parseMarkedMarkdownMessageBody(blockLines, id: messageID)
            let body = parsedBody.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                messages.append(
                    AssistantMessage(
                        role: role,
                        text: body,
                        createdAt: createdAt,
                        providerDisplayName: parsedBody.metadata.providerDisplayName,
                        modelIdentifier: parsedBody.metadata.modelIdentifier,
                        inputTokenCount: parsedBody.metadata.inputTokenCount,
                        outputTokenCount: parsedBody.metadata.outputTokenCount,
                        latencyMilliseconds: parsedBody.metadata.latencyMilliseconds,
                        firstTokenLatencyMilliseconds: parsedBody.metadata.firstTokenLatencyMilliseconds,
                        estimatedCostMicros: parsedBody.metadata.estimatedCostMicros,
                        providerAccessMode: parsedBody.metadata.providerAccessMode,
                        providerPrivacyScope: parsedBody.metadata.providerPrivacyScope,
                        runStatus: parsedBody.metadata.runStatus,
                        startedAt: parsedBody.metadata.startedAt,
                        completedAt: parsedBody.metadata.completedAt,
                        contextTokenCount: parsedBody.metadata.contextTokenCount,
                        contextWindowTokens: parsedBody.metadata.contextWindowTokens,
                        tokenCountsAreEstimated: parsedBody.metadata.tokenCountsAreEstimated,
                        fallbackReason: parsedBody.metadata.fallbackReason
                    )
                )
            }
            cursor = max(blockEnd + 1, cursor + 1)
        }

        return messages
    }

    private func legacyMarkdownMessages(_ lines: [String], importedAt: Date) -> [AssistantMessage] {
        let messageStarts = markdownMessageStarts(lines)
        return messageStarts.enumerated().compactMap { offset, start -> AssistantMessage? in
            let nextIndex = offset + 1 < messageStarts.count ? messageStarts[offset + 1].lineIndex : lines.count
            let bodyLines = Array(lines[(start.lineIndex + 1)..<nextIndex])
            let parsedBody = parseMarkdownMessageBody(bodyLines)
            let body = parsedBody.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            let createdAt = start.createdAt ?? importedAt.addingTimeInterval(Double(offset))
            return AssistantMessage(
                role: start.role,
                text: body,
                createdAt: createdAt,
                providerDisplayName: parsedBody.metadata.providerDisplayName,
                modelIdentifier: parsedBody.metadata.modelIdentifier,
                inputTokenCount: parsedBody.metadata.inputTokenCount,
                outputTokenCount: parsedBody.metadata.outputTokenCount,
                latencyMilliseconds: parsedBody.metadata.latencyMilliseconds,
                firstTokenLatencyMilliseconds: parsedBody.metadata.firstTokenLatencyMilliseconds,
                estimatedCostMicros: parsedBody.metadata.estimatedCostMicros,
                providerAccessMode: parsedBody.metadata.providerAccessMode,
                providerPrivacyScope: parsedBody.metadata.providerPrivacyScope,
                runStatus: parsedBody.metadata.runStatus,
                startedAt: parsedBody.metadata.startedAt,
                completedAt: parsedBody.metadata.completedAt,
                contextTokenCount: parsedBody.metadata.contextTokenCount,
                contextWindowTokens: parsedBody.metadata.contextWindowTokens,
                tokenCountsAreEstimated: parsedBody.metadata.tokenCountsAreEstimated,
                fallbackReason: parsedBody.metadata.fallbackReason
            )
        }
    }

    private func markdownMessageStarts(_ lines: [String]) -> [MarkdownMessageStart] {
        lines.enumerated().compactMap { lineIndex, rawLine -> MarkdownMessageStart? in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("## ") else { return nil }
            let header = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            let separators = [" - ", " — ", " – "]
            let split = separators.lazy.compactMap { separator -> (String, String)? in
                guard let range = header.range(of: separator) else { return nil }
                return (
                    String(header[..<range.lowerBound]),
                    String(header[range.upperBound...])
                )
            }.first
            let roleText = split?.0 ?? header
            guard let role = role(from: roleText) else { return nil }
            let createdAt: Date?
            if let dateText = split?.1.trimmingCharacters(in: .whitespacesAndNewlines) {
                createdAt = parseDate(dateText)
            } else {
                createdAt = nil
            }
            return MarkdownMessageStart(lineIndex: lineIndex, role: role, createdAt: createdAt)
        }
    }

    private func parseMarkdownMessageBody(_ lines: [String]) -> (text: String, metadata: ImportedMessageMetadata) {
        var metadata = ImportedMessageMetadata()
        var index = 0
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            index += 1
        }
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("- "),
                  let separator = line.range(of: ":") else {
                break
            }
            let key = String(line[line.index(line.startIndex, offsetBy: 2)..<separator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard metadata.apply(key: key, value: String(line[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)) else {
                break
            }
            index += 1
        }
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            index += 1
        }

        let bodyLines = lines[index...]
            .prefix { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                return line != "### Requested Tool Calls"
                    && line != "### Attachments"
                    && line != "### Sources"
            }
        return (bodyLines.joined(separator: "\n"), metadata)
    }

    private func parseMarkedMarkdownMessageBody(
        _ lines: [String],
        id: String?
    ) -> (text: String, metadata: ImportedMessageMetadata) {
        let textStart = nextMarkerIndex(
            in: lines,
            startingAt: 0,
            names: ["flannel-message-text-start"],
            id: id
        )
        guard let textStart else {
            return parseMarkdownMessageBody(lines)
        }

        var metadata = ImportedMessageMetadata()
        _ = metadata.apply(lines: Array(lines[..<textStart]))
        let textBodyStart = textStart + 1
        let textBodyEnd = nextMarkerIndex(
            in: lines,
            startingAt: textBodyStart,
            names: ["flannel-message-text-end"],
            id: id
        ) ?? lines.count
        return (Array(lines[textBodyStart..<textBodyEnd]).joined(separator: "\n"), metadata)
    }

    private func nextMarkerIndex(
        in lines: [String],
        startingAt: Int,
        names: Set<String>,
        id: String? = nil
    ) -> Int? {
        guard startingAt < lines.count else { return nil }
        return lines[startingAt...].firstIndex { line in
            names.contains { isMarkdownMarker(line, named: $0, id: id) }
        }
    }

    private func isMarkdownMarker(_ line: String, named markerName: String, id: String? = nil) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<!-- \(markerName)") else { return false }
        guard let id else { return true }
        return htmlAttribute("id", in: trimmed) == id
    }

    private func htmlArticleMatches(_ html: String) -> [HTMLArticleMatch] {
        regularExpressionMatches(
            in: html,
            pattern: #"<article\s+class="message\s+(system|user|assistant)"[^>]*>(.*?)</article>"#
        ).compactMap { captures in
            guard captures.count >= 2,
                  let role = role(from: captures[0]) else { return nil }
            return HTMLArticleMatch(role: role, body: captures[1])
        }
    }

    private func firstHTMLCapture(in html: String, pattern: String) -> String? {
        regularExpressionMatches(in: html, pattern: pattern).first?.first
    }

    private func regularExpressionMatches(in text: String, pattern: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { captureIndex in
                guard let captureRange = Range(match.range(at: captureIndex), in: text) else { return nil }
                return String(text[captureRange])
            }
        }
    }

    private func role(from rawValue: String) -> AssistantRole? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "system":
            .system
        case "user", "human":
            .user
        case "assistant", "flannel", "ai":
            .assistant
        default:
            nil
        }
    }

    private func parseDate(_ rawValue: String) -> Date? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        for options in [
            ISO8601DateFormatter.Options.withInternetDateTime.union(.withFractionalSeconds),
            .withInternetDateTime
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private func decodeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func htmlAttribute(_ name: String, in line: String) -> String? {
        let token = "\(name)=\""
        guard let start = line.range(of: token) else { return nil }
        let valueStart = start.upperBound
        guard let end = line[valueStart...].firstIndex(of: "\"") else { return nil }
        return decodeHTML(String(line[valueStart..<end]))
    }

    private static func textOnlyImportWarning(format: String) -> String {
        "\(format) import restores transcript text and visible run metadata only. Use Flannel JSON import when you need attachments, citations, tool-call records, and exact local provenance preserved."
    }
}

nonisolated private struct ChatImportPayload: Decodable {
    var schemaVersion: Int
    var exportedAt: Date?
    var thread: AssistantThread
}

nonisolated private struct MarkdownMessageStart: Sendable {
    var lineIndex: Int
    var role: AssistantRole
    var createdAt: Date?
}

nonisolated private struct HTMLArticleMatch: Sendable {
    var role: AssistantRole
    var body: String
}

nonisolated private struct ImportedMessageMetadata: Sendable {
    var providerDisplayName: String?
    var modelIdentifier: String?
    var inputTokenCount: Int?
    var outputTokenCount: Int?
    var latencyMilliseconds: Int?
    var firstTokenLatencyMilliseconds: Int?
    var estimatedCostMicros: Int?
    var providerAccessMode: ProviderAccessMode?
    var providerPrivacyScope: ProviderPrivacyScope?
    var runStatus: AssistantMessageRunStatus?
    var startedAt: Date?
    var completedAt: Date?
    var contextTokenCount: Int?
    var contextWindowTokens: Int?
    var tokenCountsAreEstimated = false
    var fallbackReason: String?

    mutating func apply(lines: [String]) -> Bool {
        var foundMetadata = false
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("- "),
                  let separator = line.range(of: ":") else {
                continue
            }
            let key = String(line[line.index(line.startIndex, offsetBy: 2)..<separator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            foundMetadata = apply(key: key, value: value) || foundMetadata
        }
        return foundMetadata
    }

    mutating func apply(key: String, value: String) -> Bool {
        switch key.lowercased() {
        case "status":
            runStatus = AssistantMessageRunStatus.allCases.first {
                $0.title.localizedCaseInsensitiveCompare(value) == .orderedSame
                    || $0.rawValue.localizedCaseInsensitiveCompare(value) == .orderedSame
            }
        case "provider":
            providerDisplayName = value
        case "provider mode":
            providerAccessMode = ProviderAccessMode.allCases.first {
                $0.title.localizedCaseInsensitiveCompare(value) == .orderedSame
                    || $0.rawValue.localizedCaseInsensitiveCompare(value) == .orderedSame
            }
        case "privacy scope":
            providerPrivacyScope = ProviderPrivacyScope.allCases.first {
                $0.title.localizedCaseInsensitiveCompare(value) == .orderedSame
                    || $0.rawValue.localizedCaseInsensitiveCompare(value) == .orderedSame
            }
        case "model":
            modelIdentifier = value
        case "started":
            startedAt = Self.parseDate(value)
        case "completed":
            completedAt = Self.parseDate(value)
        case "input tokens":
            inputTokenCount = Int(value)
        case "output tokens":
            outputTokenCount = Int(value)
        case "token counts":
            tokenCountsAreEstimated = value.localizedCaseInsensitiveContains("estimated")
        case "context tokens":
            let parts = value.split(separator: "/").map {
                Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            contextTokenCount = parts.first ?? nil
            if parts.count > 1 {
                contextWindowTokens = parts[1]
            }
        case "latency":
            latencyMilliseconds = Self.milliseconds(from: value)
        case "first token latency":
            firstTokenLatencyMilliseconds = Self.milliseconds(from: value)
        case "estimated cost micros":
            estimatedCostMicros = Int(value)
        case "fallback reason":
            fallbackReason = value
        default:
            return false
        }
        return true
    }

    private static func milliseconds(from value: String) -> Int? {
        let number = value
            .split(separator: " ")
            .first
            .map(String.init) ?? value
        return Int(number.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parseDate(_ rawValue: String) -> Date? {
        for options in [
            ISO8601DateFormatter.Options.withInternetDateTime.union(.withFractionalSeconds),
            .withInternetDateTime
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return date
            }
        }
        return nil
    }
}
