//
//  WebPageCaptureService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

nonisolated struct CapturedWebPage: Hashable, Sendable {
    var url: URL
    var title: String
    var text: String
    var excerpt: String
    var statusCode: Int?
    var contentType: String?
    var capturedAt: Date
}

nonisolated enum WebPageCaptureError: Error, Equatable, LocalizedError {
    case unsupportedURL(String)
    case networkFailed(String)
    case badStatus(Int)
    case undecodableResponse
    case emptyReadableText

    var errorDescription: String? {
        switch self {
        case let .unsupportedURL(value):
            return "Flannel can capture only http or https pages. \(value) is not supported."
        case let .networkFailed(message):
            return "Flannel could not capture the page: \(message)"
        case let .badStatus(statusCode):
            return "The page returned HTTP \(statusCode)."
        case .undecodableResponse:
            return "Flannel could not decode the page response as text."
        case .emptyReadableText:
            return "Flannel captured the page, but no readable text was found."
        }
    }
}

nonisolated struct WebPageCaptureService: Sendable {
    var maximumCapturedBytes: Int = 2_000_000
    private var captureHandler: (@Sendable (URL, Date, Int) async throws -> CapturedWebPage)?

    init(
        maximumCapturedBytes: Int = 2_000_000,
        captureHandler: (@Sendable (URL, Date, Int) async throws -> CapturedWebPage)? = nil
    ) {
        self.maximumCapturedBytes = maximumCapturedBytes
        self.captureHandler = captureHandler
    }

    func capture(url: URL, capturedAt: Date = .now) async throws -> CapturedWebPage {
        if let captureHandler {
            return try await captureHandler(url, capturedAt, maximumCapturedBytes)
        }

        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw WebPageCaptureError.unsupportedURL(url.absoluteString)
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.setValue("Flannel/1.0 local knowledge capture", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html, text/plain;q=0.9, */*;q=0.2", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WebPageCaptureError.networkFailed(error.localizedDescription)
        }

        let httpResponse = response as? HTTPURLResponse
        if let statusCode = httpResponse?.statusCode,
           !(200..<300).contains(statusCode) {
            throw WebPageCaptureError.badStatus(statusCode)
        }

        let boundedData = data.count > maximumCapturedBytes ? data.prefix(maximumCapturedBytes) : data[...]
        guard let html = decodeText(from: Data(boundedData), response: httpResponse) else {
            throw WebPageCaptureError.undecodableResponse
        }

        return try Self.extractReadableContent(
            from: html,
            url: httpResponse?.url ?? url,
            capturedAt: capturedAt,
            statusCode: httpResponse?.statusCode,
            contentType: httpResponse?.value(forHTTPHeaderField: "Content-Type")
        )
    }

    nonisolated static func extractReadableContent(
        from html: String,
        url: URL,
        capturedAt: Date = .now,
        statusCode: Int? = nil,
        contentType: String? = nil
    ) throws -> CapturedWebPage {
        let title = decodeHTMLEntities(firstMatch(in: html, pattern: #"(?is)<title[^>]*>(.*?)</title>"#) ?? "")
            .collapsedWhitespace()
        let fallbackTitle = url.host(percentEncoded: false) ?? url.absoluteString
        let readableText = readableText(from: html)
        guard !readableText.isEmpty else {
            throw WebPageCaptureError.emptyReadableText
        }

        return CapturedWebPage(
            url: url,
            title: title.isEmpty ? fallbackTitle : title,
            text: readableText,
            excerpt: excerpt(from: readableText),
            statusCode: statusCode,
            contentType: contentType,
            capturedAt: capturedAt
        )
    }
}

private extension WebPageCaptureService {
    nonisolated func decodeText(from data: Data, response: HTTPURLResponse?) -> String? {
        if let encodingName = response?.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                let encoding = String.Encoding(rawValue: nsEncoding)
                if let text = String(data: data, encoding: encoding) {
                    return text
                }
            }
        }

        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    nonisolated static func readableText(from html: String) -> String {
        var working = html
        let removals = [
            #"(?is)<script\b[^>]*>.*?</script>"#,
            #"(?is)<style\b[^>]*>.*?</style>"#,
            #"(?is)<noscript\b[^>]*>.*?</noscript>"#,
            #"(?is)<svg\b[^>]*>.*?</svg>"#,
            #"(?is)<head\b[^>]*>.*?</head>"#
        ]

        for pattern in removals {
            working = replaceMatches(in: working, pattern: pattern, with: "\n")
        }

        working = replaceMatches(
            in: working,
            pattern: #"(?i)</?(article|aside|blockquote|br|dd|div|dl|dt|figcaption|footer|h[1-6]|header|hr|li|main|nav|ol|p|pre|section|table|td|th|tr|ul)\b[^>]*>"#,
            with: "\n"
        )
        working = replaceMatches(in: working, pattern: #"(?s)<[^>]+>"#, with: " ")
        working = decodeHTMLEntities(working)

        return working
            .components(separatedBy: .newlines)
            .map { $0.collapsedWhitespace() }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    nonisolated static func excerpt(from text: String, limit: Int = 360) -> String {
        let collapsed = text.collapsedWhitespace()
        guard collapsed.count > limit else { return collapsed }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    nonisolated static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange])
    }

    nonisolated static func replaceMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    nonisolated static func decodeHTMLEntities(_ text: String) -> String {
        var result = ""
        var cursor = text.startIndex

        while cursor < text.endIndex {
            guard let ampersand = text[cursor...].firstIndex(of: "&") else {
                result += text[cursor...]
                break
            }

            result += text[cursor..<ampersand]
            guard let semicolon = text[ampersand...].firstIndex(of: ";"),
                  text.distance(from: ampersand, to: semicolon) <= 12 else {
                result.append("&")
                cursor = text.index(after: ampersand)
                continue
            }

            let entityStart = text.index(after: ampersand)
            let entity = String(text[entityStart..<semicolon])
            result += decodeEntity(entity) ?? "&\(entity);"
            cursor = text.index(after: semicolon)
        }

        return result
    }

    nonisolated static func decodeEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            let value = String(entity.dropFirst(2))
            guard let scalarValue = UInt32(value, radix: 16),
                  let scalar = UnicodeScalar(scalarValue) else { return nil }
            return String(Character(scalar))
        }

        if entity.hasPrefix("#") {
            let value = String(entity.dropFirst())
            guard let scalarValue = UInt32(value, radix: 10),
                  let scalar = UnicodeScalar(scalarValue) else { return nil }
            return String(Character(scalar))
        }

        switch entity.lowercased() {
        case "amp":
            return "&"
        case "apos":
            return "'"
        case "gt":
            return ">"
        case "lt":
            return "<"
        case "nbsp":
            return " "
        case "quot":
            return "\""
        default:
            return nil
        }
    }
}

private extension String {
    nonisolated func collapsedWhitespace() -> String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
