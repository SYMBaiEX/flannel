//
//  XToolService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation

nonisolated struct XToolRequest: Hashable, Sendable {
    var query: String
    var endpoint: String
    var bearerToken: String
    var resultLimit: Int

    init(
        query: String,
        endpoint: String = XToolService.defaultEndpoint,
        bearerToken: String,
        resultLimit: Int = 8
    ) {
        self.query = query
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        self.resultLimit = resultLimit
    }
}

nonisolated struct XToolItem: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var kind: String
    var title: String
    var url: String
    var summary: String
    var metadata: [String]
}

nonisolated struct XToolResponse: Codable, Hashable, Sendable {
    var query: String
    var endpoint: String
    var mode: String
    var items: [XToolItem]
    var fetchedAt: Date

    var formattedToolOutput: String {
        let itemLines = items.enumerated().map { index, item in
            let metadataLine = item.metadata.isEmpty ? "" : "\n   \(item.metadata.joined(separator: " - "))"
            let summaryLine = item.summary.isEmpty ? "" : "\n   \(item.summary)"
            return "\(index + 1). [\(item.kind)] \(item.title)\n   \(item.url)\(metadataLine)\(summaryLine)"
        }
        let block = itemLines.isEmpty ? "No X results were returned." : itemLines.joined(separator: "\n\n")

        return """
        X context
        Query: \(query)
        Mode: \(mode)
        Endpoint: \(endpoint)
        Fetched: \(fetchedAt.formatted(date: .abbreviated, time: .shortened))

        Results:
        \(block)
        """
    }
}

nonisolated enum XToolServiceError: LocalizedError, Equatable {
    case emptyQuery
    case invalidEndpoint
    case badStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "X requires a post URL, post ID, username, or search query."
        case .invalidEndpoint:
            "The X API endpoint is not a valid HTTPS URL."
        case .badStatus(let statusCode):
            "X API returned HTTP \(statusCode)."
        case .invalidResponse:
            "The X API response could not be read."
        }
    }
}

nonisolated struct XToolService: Sendable {
    static let defaultEndpoint = "https://api.x.com/2"

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse?)

    private var transport: Transport

    init(transport: @escaping Transport = XToolService.urlSessionTransport) {
        self.transport = transport
    }

    func fetch(_ toolRequest: XToolRequest) async throws -> XToolResponse {
        let route = try route(for: toolRequest)
        let request = try makeURLRequest(for: toolRequest, route: route)
        let (data, response) = try await transport(request)

        if let statusCode = response?.statusCode,
           !(200..<300).contains(statusCode) {
            throw XToolServiceError.badStatus(statusCode)
        }

        guard !data.isEmpty else {
            throw XToolServiceError.invalidResponse
        }

        let object = try JSONSerialization.jsonObject(with: data)
        let items = try parseItems(object, route: route)
        guard !items.isEmpty else {
            throw XToolServiceError.invalidResponse
        }

        return XToolResponse(
            query: toolRequest.query.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: request.url?.absoluteString ?? toolRequest.endpoint,
            mode: route.modeTitle,
            items: Array(items.prefix(toolRequest.resultLimit)),
            fetchedAt: .now
        )
    }

    func makeURLRequest(for toolRequest: XToolRequest, route: XToolRoute? = nil) throws -> URLRequest {
        let route = try route ?? self.route(for: toolRequest)
        guard var components = URLComponents(
            url: try baseURL(from: toolRequest.endpoint).appendingPathComponent(route.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw XToolServiceError.invalidEndpoint
        }
        components.queryItems = route.queryItems

        guard let url = components.url else {
            throw XToolServiceError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(toolRequest.bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func route(for toolRequest: XToolRequest) throws -> XToolRoute {
        let query = toolRequest.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw XToolServiceError.emptyQuery
        }

        if let postID = parsePostID(query) {
            return XToolRoute(
                path: "tweets/\(postID)",
                queryItems: tweetQueryItems(),
                kind: .postDetail
            )
        }

        if let username = parseUsername(query) {
            return XToolRoute(
                path: "users/by/username/\(username)",
                queryItems: [
                    URLQueryItem(name: "user.fields", value: "created_at,description,location,public_metrics,url,verified,verified_type")
                ],
                kind: .userProfile
            )
        }

        let limit = max(10, min(toolRequest.resultLimit, 100))
        return XToolRoute(
            path: "tweets/search/recent",
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "max_results", value: "\(limit)")
            ] + tweetQueryItems(),
            kind: .recentSearch
        )
    }

    private func tweetQueryItems() -> [URLQueryItem] {
        [
            URLQueryItem(name: "tweet.fields", value: "author_id,created_at,lang,public_metrics,conversation_id"),
            URLQueryItem(name: "expansions", value: "author_id"),
            URLQueryItem(name: "user.fields", value: "username,name,verified,verified_type,public_metrics")
        ]
    }

    private func baseURL(from rawEndpoint: String) throws -> URL {
        let endpoint = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            throw XToolServiceError.invalidEndpoint
        }
        return url
    }

    private func parseItems(_ object: Any, route: XToolRoute) throws -> [XToolItem] {
        switch route.kind {
        case .recentSearch:
            let users = includedUsers(in: object)
            return tweetDictionaries(in: object).compactMap { tweetItem(from: $0, users: users) }
        case .postDetail:
            guard let dictionary = object as? [String: Any],
                  let data = dictionary["data"] as? [String: Any] else {
                throw XToolServiceError.invalidResponse
            }
            return [tweetItem(from: data, users: includedUsers(in: object))].compactMap { $0 }
        case .userProfile:
            guard let dictionary = object as? [String: Any],
                  let data = dictionary["data"] as? [String: Any],
                  let item = userItem(from: data) else {
                throw XToolServiceError.invalidResponse
            }
            return [item]
        }
    }

    private func tweetDictionaries(in object: Any) -> [[String: Any]] {
        guard let dictionary = object as? [String: Any] else { return [] }
        if let data = dictionary["data"] as? [[String: Any]] {
            return data
        }
        if let data = dictionary["data"] as? [String: Any] {
            return [data]
        }
        return []
    }

    private func includedUsers(in object: Any) -> [String: [String: Any]] {
        guard let dictionary = object as? [String: Any],
              let includes = dictionary["includes"] as? [String: Any],
              let users = includes["users"] as? [[String: Any]] else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: users.compactMap { user in
            guard let id = string(in: user, keys: ["id"]) else { return nil }
            return (id, user)
        })
    }

    private func tweetItem(from dictionary: [String: Any], users: [String: [String: Any]]) -> XToolItem? {
        guard let id = string(in: dictionary, keys: ["id"]),
              let text = string(in: dictionary, keys: ["text"]) else {
            return nil
        }
        let author = string(in: dictionary, keys: ["author_id"]).flatMap { users[$0] }
        let username = author.flatMap { string(in: $0, keys: ["username"]) }
        let displayName = author.flatMap { string(in: $0, keys: ["name"]) }
        let metrics = dictionary["public_metrics"] as? [String: Any]
        let retweets = metrics.flatMap { int(in: $0, key: "retweet_count") }.map { "\($0) reposts" }
        let replies = metrics.flatMap { int(in: $0, key: "reply_count") }.map { "\($0) replies" }
        let likes = metrics.flatMap { int(in: $0, key: "like_count") }.map { "\($0) likes" }
        let quotes = metrics.flatMap { int(in: $0, key: "quote_count") }.map { "\($0) quotes" }
        let createdAt = string(in: dictionary, keys: ["created_at"])
        let title = username.map { "@\($0)" } ?? displayName ?? "Post \(id)"

        return XToolItem(
            id: id,
            kind: "post",
            title: title,
            url: username.map { "https://x.com/\($0)/status/\(id)" } ?? "https://x.com/i/web/status/\(id)",
            summary: sanitize(text),
            metadata: [createdAt, retweets, replies, likes, quotes].compactMap { $0 }
        )
    }

    private func userItem(from dictionary: [String: Any]) -> XToolItem? {
        guard let id = string(in: dictionary, keys: ["id"]),
              let username = string(in: dictionary, keys: ["username"]) else {
            return nil
        }
        let metrics = dictionary["public_metrics"] as? [String: Any]
        let followers = metrics.flatMap { int(in: $0, key: "followers_count") }.map { "\($0) followers" }
        let following = metrics.flatMap { int(in: $0, key: "following_count") }.map { "\($0) following" }
        let posts = metrics.flatMap { int(in: $0, key: "tweet_count") }.map { "\($0) posts" }
        let verified = bool(in: dictionary, key: "verified") == true ? "verified" : nil
        let name = string(in: dictionary, keys: ["name"]) ?? "@\(username)"

        return XToolItem(
            id: id,
            kind: "profile",
            title: "\(name) (@\(username))",
            url: "https://x.com/\(username)",
            summary: sanitize(string(in: dictionary, keys: ["description"]) ?? ""),
            metadata: [verified, followers, following, posts].compactMap { $0 }
        )
    }

    private func parsePostID(_ query: String) -> String? {
        let candidate = strippedPrefix(query, prefixes: ["post:", "tweet:", "status:", "x:"])
        if let url = URL(string: candidate),
           let host = url.host?.lowercased(),
           host.contains("x.com") || host.contains("twitter.com") {
            let parts = url.path.split(separator: "/").map(String.init)
            if let markerIndex = parts.firstIndex(where: { ["status", "statuses"].contains($0) }),
               parts.indices.contains(markerIndex + 1) {
                return safePostID(parts[markerIndex + 1])
            }
        }
        return safePostID(candidate)
    }

    private func parseUsername(_ query: String) -> String? {
        let candidate = strippedPrefix(query, prefixes: ["user:", "profile:", "account:"])
        if let url = URL(string: candidate),
           let host = url.host?.lowercased(),
           host.contains("x.com") || host.contains("twitter.com") {
            let parts = url.path.split(separator: "/").map(String.init)
            guard let first = parts.first,
                  !["home", "i", "search", "hashtag", "intent"].contains(first.lowercased()),
                  !parts.contains("status") else {
                return nil
            }
            return safeUsername(first)
        }

        if candidate.hasPrefix("@") {
            return safeUsername(String(candidate.dropFirst()))
        }
        return nil
    }

    private func safePostID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.count >= 5,
              value.allSatisfy(\.isNumber) else {
            return nil
        }
        return value
    }

    private func safeUsername(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              (1...15).contains(value.count),
              value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
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

    private func int(in dictionary: [String: Any], key: String) -> Int? {
        if let value = dictionary[key] as? Int {
            return value
        }
        if let value = dictionary[key] as? String {
            return Int(value)
        }
        return nil
    }

    private func bool(in dictionary: [String: Any], key: String) -> Bool? {
        if let value = dictionary[key] as? Bool {
            return value
        }
        if let value = dictionary[key] as? String {
            return Bool(value)
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

nonisolated struct XToolRoute: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case recentSearch
        case postDetail
        case userProfile
    }

    var path: String
    var queryItems: [URLQueryItem]
    var kind: Kind

    var modeTitle: String {
        switch kind {
        case .recentSearch:
            "Recent post search"
        case .postDetail:
            "Post detail"
        case .userProfile:
            "Profile detail"
        }
    }
}
