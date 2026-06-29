//
//  YouTubeToolService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation

nonisolated struct YouTubeToolRequest: Hashable, Sendable {
    var query: String
    var endpoint: String
    var apiKey: String
    var resultLimit: Int

    init(
        query: String,
        endpoint: String = YouTubeToolService.defaultEndpoint,
        apiKey: String,
        resultLimit: Int = 8
    ) {
        self.query = query
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.resultLimit = resultLimit
    }
}

nonisolated struct YouTubeToolItem: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var url: String
    var channelTitle: String
    var description: String
    var publishedAt: String?
    var duration: String?
    var viewCount: String?
    var likeCount: String?

    var metadata: [String] {
        [
            channelTitle.isEmpty ? nil : channelTitle,
            publishedAt,
            duration,
            viewCount.map { "\($0) views" },
            likeCount.map { "\($0) likes" }
        ].compactMap { $0 }
    }
}

nonisolated struct YouTubeToolResponse: Codable, Hashable, Sendable {
    var query: String
    var endpoint: String
    var mode: String
    var items: [YouTubeToolItem]
    var fetchedAt: Date

    var formattedToolOutput: String {
        let itemLines = items.enumerated().map { index, item in
            let metadataLine = item.metadata.isEmpty ? "" : "\n   \(item.metadata.joined(separator: " - "))"
            let summaryLine = item.description.isEmpty ? "" : "\n   \(item.description)"
            return "\(index + 1). \(item.title)\n   \(item.url)\(metadataLine)\(summaryLine)"
        }
        let block = itemLines.isEmpty ? "No YouTube videos were returned." : itemLines.joined(separator: "\n\n")

        return """
        YouTube context
        Query: \(query)
        Mode: \(mode)
        Endpoint: \(endpoint)
        Fetched: \(fetchedAt.formatted(date: .abbreviated, time: .shortened))

        Videos:
        \(block)
        """
    }
}

nonisolated enum YouTubeToolServiceError: LocalizedError, Equatable {
    case emptyQuery
    case invalidEndpoint
    case badStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "YouTube requires a video URL, video ID, or search query."
        case .invalidEndpoint:
            "The YouTube endpoint is not a valid HTTPS URL."
        case .badStatus(let statusCode):
            "YouTube Data API returned HTTP \(statusCode)."
        case .invalidResponse:
            "The YouTube Data API response could not be read."
        }
    }
}

nonisolated struct YouTubeToolService: Sendable {
    static let defaultEndpoint = "https://www.googleapis.com/youtube/v3"

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse?)

    private var transport: Transport

    init(transport: @escaping Transport = YouTubeToolService.urlSessionTransport) {
        self.transport = transport
    }

    func fetch(_ toolRequest: YouTubeToolRequest) async throws -> YouTubeToolResponse {
        let route = try route(for: toolRequest)
        let request = try makeURLRequest(for: toolRequest, route: route)
        let (data, response) = try await transport(request)

        if let statusCode = response?.statusCode,
           !(200..<300).contains(statusCode) {
            throw YouTubeToolServiceError.badStatus(statusCode)
        }

        guard !data.isEmpty else {
            throw YouTubeToolServiceError.invalidResponse
        }

        let object = try JSONSerialization.jsonObject(with: data)
        let items = try parseItems(object, route: route)
        guard !items.isEmpty else {
            throw YouTubeToolServiceError.invalidResponse
        }

        return YouTubeToolResponse(
            query: toolRequest.query.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: request.url?.absoluteString ?? toolRequest.endpoint,
            mode: route.modeTitle,
            items: Array(items.prefix(toolRequest.resultLimit)),
            fetchedAt: .now
        )
    }

    func makeURLRequest(for toolRequest: YouTubeToolRequest, route: YouTubeToolRoute? = nil) throws -> URLRequest {
        let route = try route ?? self.route(for: toolRequest)
        guard var components = URLComponents(
            url: try baseURL(from: toolRequest.endpoint).appendingPathComponent(route.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw YouTubeToolServiceError.invalidEndpoint
        }
        var queryItems = route.queryItems
        queryItems.append(URLQueryItem(name: "key", value: toolRequest.apiKey))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw YouTubeToolServiceError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func route(for toolRequest: YouTubeToolRequest) throws -> YouTubeToolRoute {
        let query = toolRequest.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw YouTubeToolServiceError.emptyQuery
        }

        let limit = max(1, min(toolRequest.resultLimit, 25))
        if let videoID = parseVideoID(query) {
            return YouTubeToolRoute(
                path: "videos",
                queryItems: [
                    URLQueryItem(name: "part", value: "snippet,contentDetails,statistics"),
                    URLQueryItem(name: "id", value: videoID)
                ],
                kind: .videoDetail
            )
        }

        return YouTubeToolRoute(
            path: "search",
            queryItems: [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "type", value: "video"),
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "maxResults", value: "\(limit)"),
                URLQueryItem(name: "safeSearch", value: "moderate")
            ],
            kind: .videoSearch
        )
    }

    private func baseURL(from rawEndpoint: String) throws -> URL {
        let endpoint = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            throw YouTubeToolServiceError.invalidEndpoint
        }
        return url
    }

    private func parseItems(_ object: Any, route: YouTubeToolRoute) throws -> [YouTubeToolItem] {
        guard let dictionary = object as? [String: Any],
              let items = dictionary["items"] as? [[String: Any]] else {
            throw YouTubeToolServiceError.invalidResponse
        }

        switch route.kind {
        case .videoSearch:
            return items.compactMap(searchItem)
        case .videoDetail:
            return items.compactMap(videoItem)
        }
    }

    private func searchItem(from dictionary: [String: Any]) -> YouTubeToolItem? {
        guard let id = dictionary["id"] as? [String: Any],
              let videoID = string(in: id, keys: ["videoId"]),
              let snippet = dictionary["snippet"] as? [String: Any],
              let title = string(in: snippet, keys: ["title"]) else {
            return nil
        }

        return YouTubeToolItem(
            id: videoID,
            title: sanitize(title),
            url: "https://www.youtube.com/watch?v=\(videoID)",
            channelTitle: sanitize(string(in: snippet, keys: ["channelTitle"]) ?? ""),
            description: sanitize(string(in: snippet, keys: ["description"]) ?? ""),
            publishedAt: string(in: snippet, keys: ["publishedAt"]),
            duration: nil,
            viewCount: nil,
            likeCount: nil
        )
    }

    private func videoItem(from dictionary: [String: Any]) -> YouTubeToolItem? {
        guard let videoID = string(in: dictionary, keys: ["id"]),
              let snippet = dictionary["snippet"] as? [String: Any],
              let title = string(in: snippet, keys: ["title"]) else {
            return nil
        }
        let details = dictionary["contentDetails"] as? [String: Any]
        let statistics = dictionary["statistics"] as? [String: Any]
        return YouTubeToolItem(
            id: videoID,
            title: sanitize(title),
            url: "https://www.youtube.com/watch?v=\(videoID)",
            channelTitle: sanitize(string(in: snippet, keys: ["channelTitle"]) ?? ""),
            description: sanitize(string(in: snippet, keys: ["description"]) ?? ""),
            publishedAt: string(in: snippet, keys: ["publishedAt"]),
            duration: details.flatMap { string(in: $0, keys: ["duration"]) },
            viewCount: statistics.flatMap { string(in: $0, keys: ["viewCount"]) },
            likeCount: statistics.flatMap { string(in: $0, keys: ["likeCount"]) }
        )
    }

    private func parseVideoID(_ query: String) -> String? {
        let candidate = strippedPrefix(query, prefixes: ["video:", "youtube:"])
        if let url = URL(string: candidate),
           let host = url.host?.lowercased(),
           host.contains("youtube.com") || host.contains("youtu.be") {
            if host.contains("youtu.be") {
                return safeVideoID(url.path.split(separator: "/").first.map(String.init))
            }

            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let id = components.queryItems?.first(where: { $0.name == "v" })?.value,
               let safeID = safeVideoID(id) {
                return safeID
            }

            let parts = url.path.split(separator: "/").map(String.init)
            if let markerIndex = parts.firstIndex(where: { ["shorts", "embed", "live"].contains($0) }),
               parts.indices.contains(markerIndex + 1) {
                return safeVideoID(parts[markerIndex + 1])
            }
        }

        return safeVideoID(candidate)
    }

    private func safeVideoID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.count == 11,
              value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            return nil
        }
        return value
    }

    private func strippedPrefix(_ value: String, prefixes: [String]) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        for prefix in prefixes where lowered.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func string(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let value = dictionary[key] as? Int {
                return "\(value)"
            }
        }
        return nil
    }

    private func sanitize(_ text: String) -> String {
        let decoded = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard decoded.count > 700 else {
            return decoded
        }
        return String(decoded.prefix(700)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse?) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as? HTTPURLResponse)
    }
}

nonisolated struct YouTubeToolRoute: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case videoSearch
        case videoDetail
    }

    var path: String
    var queryItems: [URLQueryItem]
    var kind: Kind

    var modeTitle: String {
        switch kind {
        case .videoSearch:
            "Video search"
        case .videoDetail:
            "Video detail"
        }
    }
}
