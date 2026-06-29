//
//  NotionToolService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation

nonisolated struct NotionToolRequest: Hashable, Sendable {
    var query: String
    var endpoint: String
    var token: String
    var resultLimit: Int

    init(
        query: String,
        endpoint: String = NotionToolService.defaultEndpoint,
        token: String,
        resultLimit: Int = 8
    ) {
        self.query = query
        self.endpoint = endpoint
        self.token = token
        self.resultLimit = resultLimit
    }
}

nonisolated struct NotionToolItem: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var kind: String
    var title: String
    var url: String
    var summary: String
    var metadata: [String]
}

nonisolated struct NotionToolResponse: Codable, Hashable, Sendable {
    var query: String
    var endpoint: String
    var mode: String
    var items: [NotionToolItem]
    var fetchedAt: Date

    var formattedToolOutput: String {
        let itemLines = items.enumerated().map { index, item in
            let metadataLine = item.metadata.isEmpty ? "" : "\n   \(item.metadata.joined(separator: " - "))"
            let summaryLine = item.summary.isEmpty ? "" : "\n   \(item.summary)"
            return "\(index + 1). [\(item.kind)] \(item.title)\n   \(item.url)\(metadataLine)\(summaryLine)"
        }
        let block = itemLines.isEmpty ? "No Notion results were returned." : itemLines.joined(separator: "\n\n")

        return """
        Notion context
        Query: \(query)
        Mode: \(mode)
        Endpoint: \(endpoint)
        Fetched: \(fetchedAt.formatted(date: .abbreviated, time: .shortened))

        Results:
        \(block)
        """
    }
}

nonisolated enum NotionToolServiceError: LocalizedError, Equatable {
    case emptyQuery
    case invalidEndpoint
    case invalidIdentifier(String)
    case badStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "Notion requires a search query, page URL, page ID, or data source ID."
        case .invalidEndpoint:
            "The Notion endpoint is not a valid HTTPS URL."
        case .invalidIdentifier(let value):
            "Notion could not read a valid page or data source identifier from \"\(value)\"."
        case .badStatus(let statusCode):
            "Notion returned HTTP \(statusCode)."
        case .invalidResponse:
            "The Notion response could not be read."
        }
    }
}

nonisolated struct NotionToolService: Sendable {
    static let defaultEndpoint = "https://api.notion.com"
    static let apiVersion = "2026-03-11"

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse?)

    private var transport: Transport

    init(transport: @escaping Transport = NotionToolService.urlSessionTransport) {
        self.transport = transport
    }

    func fetch(_ toolRequest: NotionToolRequest) async throws -> NotionToolResponse {
        let route = try route(for: toolRequest)
        let request = try makeURLRequest(for: toolRequest, route: route)
        let (data, response) = try await transport(request)

        if let statusCode = response?.statusCode,
           !(200..<300).contains(statusCode) {
            throw NotionToolServiceError.badStatus(statusCode)
        }

        guard !data.isEmpty else {
            throw NotionToolServiceError.invalidResponse
        }

        let object = try JSONSerialization.jsonObject(with: data)
        let items = try parseItems(object, route: route, limit: toolRequest.resultLimit)
        guard !items.isEmpty else {
            throw NotionToolServiceError.invalidResponse
        }

        return NotionToolResponse(
            query: toolRequest.query.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: request.url?.absoluteString ?? toolRequest.endpoint,
            mode: route.modeTitle,
            items: items,
            fetchedAt: .now
        )
    }

    private func makeURLRequest(for toolRequest: NotionToolRequest, route: NotionToolRoute? = nil) throws -> URLRequest {
        let route = try route ?? self.route(for: toolRequest)
        let url = try baseURL(from: toolRequest.endpoint).appendingPathComponent(route.path)

        var request = URLRequest(url: url)
        request.httpMethod = route.method
        request.timeoutInterval = 30
        request.setValue("Bearer \(toolRequest.token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = route.body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func route(for toolRequest: NotionToolRequest) throws -> NotionToolRoute {
        let query = toolRequest.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw NotionToolServiceError.emptyQuery
        }

        let limit = max(1, min(toolRequest.resultLimit, 25))
        let lowered = query.lowercased()

        if lowered.hasPrefix("data_source:") || lowered.hasPrefix("datasource:") || lowered.hasPrefix("source:") {
            let identifier = strippedPrefix(query, prefixes: ["data_source:", "datasource:", "source:"])
            return NotionToolRoute(
                path: "/v1/data_sources/\(try notionIdentifier(from: identifier))/query",
                method: "POST",
                body: ["page_size": limit],
                kind: .dataSourceQuery
            )
        }

        if lowered.hasPrefix("page:") || lowered.hasPrefix("markdown:") {
            let identifier = strippedPrefix(query, prefixes: ["page:", "markdown:"])
            return NotionToolRoute(
                path: "/v1/pages/\(try notionIdentifier(from: identifier))/markdown",
                method: "GET",
                body: nil,
                kind: .pageMarkdown
            )
        }

        if let url = URL(string: query),
           url.host?.lowercased().contains("notion.") == true {
            return NotionToolRoute(
                path: "/v1/pages/\(try notionIdentifier(from: query))/markdown",
                method: "GET",
                body: nil,
                kind: .pageMarkdown
            )
        }

        return NotionToolRoute(
            path: "/v1/search",
            method: "POST",
            body: [
                "query": query,
                "page_size": limit
            ],
            kind: .search
        )
    }

    private func parseItems(_ object: Any, route: NotionToolRoute, limit: Int) throws -> [NotionToolItem] {
        switch route.kind {
        case .pageMarkdown:
            guard let dictionary = object as? [String: Any] else {
                throw NotionToolServiceError.invalidResponse
            }
            return [parseMarkdownPage(dictionary)]

        case .search, .dataSourceQuery:
            guard let dictionary = object as? [String: Any],
                  let results = dictionary["results"] as? [[String: Any]] else {
                throw NotionToolServiceError.invalidResponse
            }
            return Array(results.prefix(max(1, min(limit, 25)))).map(parseResultObject)
        }
    }

    private func parseMarkdownPage(_ dictionary: [String: Any]) -> NotionToolItem {
        let id = stringValue(dictionary["id"]) ?? "notion-page"
        let markdown = stringValue(dictionary["markdown"]) ?? stringValue(dictionary["content"]) ?? ""
        let title = stringValue(dictionary["title"]) ?? "Notion page \(shortIdentifier(id))"
        let isTruncated = boolValue(dictionary["truncated"])
        let metadata = [
            isTruncated == true ? "Truncated by Notion" : nil,
            arrayValue(dictionary["unknown_block_ids"]).isEmpty ? nil : "Unknown blocks: \(arrayValue(dictionary["unknown_block_ids"]).count)"
        ].compactMap { $0 }

        return NotionToolItem(
            id: id,
            kind: "page markdown",
            title: title,
            url: stringValue(dictionary["url"]) ?? notionPageURL(for: id),
            summary: markdown.truncatedForToolSummary(maximum: 1_800),
            metadata: metadata
        )
    }

    private func parseResultObject(_ dictionary: [String: Any]) -> NotionToolItem {
        let id = stringValue(dictionary["id"]) ?? UUID().uuidString
        let object = stringValue(dictionary["object"]) ?? "object"
        let title = titleValue(from: dictionary) ?? "\(object.capitalized) \(shortIdentifier(id))"
        let url = stringValue(dictionary["url"]) ?? notionPageURL(for: id)
        let summary = summaryValue(from: dictionary)
        let metadata = [
            stringValue(dictionary["created_time"]).map { "Created \($0)" },
            stringValue(dictionary["last_edited_time"]).map { "Edited \($0)" },
            stringValue(dictionary["archived"]).map { "Archived \($0)" },
            stringValue(dictionary["in_trash"]).map { "Trash \($0)" }
        ].compactMap { $0 }

        return NotionToolItem(
            id: id,
            kind: object,
            title: title,
            url: url,
            summary: summary,
            metadata: metadata
        )
    }

    private func titleValue(from dictionary: [String: Any]) -> String? {
        if let title = stringValue(dictionary["title"]), !title.isEmpty {
            return title
        }

        if let titleArray = dictionary["title"] as? [[String: Any]],
           let text = richTextPlainText(titleArray) {
            return text
        }

        if let properties = dictionary["properties"] as? [String: Any] {
            for value in properties.values {
                guard let property = value as? [String: Any],
                      stringValue(property["type"]) == "title",
                      let titleArray = property["title"] as? [[String: Any]],
                      let text = richTextPlainText(titleArray) else {
                    continue
                }
                return text
            }
        }

        if let parent = dictionary["parent"] as? [String: Any],
           let type = stringValue(parent["type"]) {
            return "Notion \(type.replacingOccurrences(of: "_", with: " "))"
        }

        return nil
    }

    private func summaryValue(from dictionary: [String: Any]) -> String {
        guard let properties = dictionary["properties"] as? [String: Any] else {
            return ""
        }

        let fragments = properties.sorted { $0.key < $1.key }.compactMap { key, rawValue -> String? in
            guard let property = rawValue as? [String: Any],
                  stringValue(property["type"]) != "title" else {
                return nil
            }

            if let value = compactPropertyValue(property) {
                return "\(key): \(value)"
            }
            return nil
        }

        return fragments.prefix(6).joined(separator: "; ").truncatedForToolSummary(maximum: 1_200)
    }

    private func compactPropertyValue(_ property: [String: Any]) -> String? {
        guard let type = stringValue(property["type"]) else { return nil }
        switch type {
        case "rich_text":
            return (property["rich_text"] as? [[String: Any]]).flatMap(richTextPlainText)
        case "number":
            return stringValue(property["number"])
        case "select":
            return (property["select"] as? [String: Any]).flatMap { stringValue($0["name"]) }
        case "multi_select":
            return (property["multi_select"] as? [[String: Any]])?
                .compactMap { stringValue($0["name"]) }
                .joined(separator: ", ")
        case "status":
            return (property["status"] as? [String: Any]).flatMap { stringValue($0["name"]) }
        case "date":
            return (property["date"] as? [String: Any]).flatMap { stringValue($0["start"]) }
        case "checkbox":
            return stringValue(property["checkbox"])
        case "url":
            return stringValue(property["url"])
        case "email":
            return stringValue(property["email"])
        case "phone_number":
            return stringValue(property["phone_number"])
        case "people":
            return (property["people"] as? [[String: Any]])?
                .compactMap { stringValue($0["name"]) }
                .joined(separator: ", ")
        case "files":
            return (property["files"] as? [[String: Any]])?
                .compactMap { stringValue($0["name"]) }
                .joined(separator: ", ")
        default:
            return nil
        }
    }

    private func richTextPlainText(_ values: [[String: Any]]) -> String? {
        let text = values.compactMap { stringValue($0["plain_text"]) }.joined()
        return text.isEmpty ? nil : text
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            value
        case let value as Bool:
            value ? "true" : "false"
        case let value as Int:
            String(value)
        case let value as Double:
            String(value)
        case .some(let value) where !(value is NSNull):
            String(describing: value)
        default:
            nil
        }
    }

    private func boolValue(_ value: Any?) -> Bool? {
        value as? Bool
    }

    private func arrayValue(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    private func notionIdentifier(from rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NotionToolServiceError.invalidIdentifier(rawValue)
        }

        let candidate: String
        if let url = URL(string: trimmed),
           url.host?.lowercased().contains("notion.") == true {
            candidate = url.pathComponents
                .reversed()
                .first(where: { $0.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil }) ?? trimmed
        } else {
            candidate = trimmed.components(separatedBy: .whitespacesAndNewlines).first ?? trimmed
        }

        let filteredHex = candidate.filter { $0.isHexDigit }
        let trailingSlugHex = candidate
            .split(separator: "-")
            .last
            .map(String.init)?
            .filter { $0.isHexDigit }
        let hex = filteredHex.count == 32 ? filteredHex : trailingSlugHex ?? filteredHex

        guard hex.count == 32 else {
            throw NotionToolServiceError.invalidIdentifier(rawValue)
        }
        return [
            String(hex.prefix(8)),
            String(hex.dropFirst(8).prefix(4)),
            String(hex.dropFirst(12).prefix(4)),
            String(hex.dropFirst(16).prefix(4)),
            String(hex.dropFirst(20).prefix(12))
        ].joined(separator: "-")
    }

    private func notionPageURL(for id: String) -> String {
        "https://www.notion.so/\(id.replacingOccurrences(of: "-", with: ""))"
    }

    private func shortIdentifier(_ id: String) -> String {
        String(id.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    private func strippedPrefix(_ value: String, prefixes: [String]) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        for prefix in prefixes where lowered.hasPrefix(prefix.lowercased()) {
            return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func baseURL(from endpoint: String) throws -> URL {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else {
            throw NotionToolServiceError.invalidEndpoint
        }
        return url
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse?) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as? HTTPURLResponse)
    }
}

nonisolated private struct NotionToolRoute {
    enum Kind {
        case search
        case pageMarkdown
        case dataSourceQuery
    }

    var path: String
    var method: String
    var body: [String: Any]?
    var kind: Kind

    var modeTitle: String {
        switch kind {
        case .search:
            "Search"
        case .pageMarkdown:
            "Page markdown"
        case .dataSourceQuery:
            "Data source query"
        }
    }
}

private extension String {
    nonisolated func truncatedForToolSummary(maximum: Int) -> String {
        guard count > maximum else { return self }
        return String(prefix(maximum)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
