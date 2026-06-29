//
//  GitHubToolService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation

nonisolated struct GitHubToolRequest: Hashable, Sendable {
    var query: String
    var endpoint: String
    var token: String?
    var resultLimit: Int

    init(
        query: String,
        endpoint: String = GitHubToolService.defaultEndpoint,
        token: String? = nil,
        resultLimit: Int = 8
    ) {
        self.query = query
        self.endpoint = endpoint
        self.token = token
        self.resultLimit = resultLimit
    }
}

nonisolated struct GitHubToolItem: Identifiable, Codable, Hashable, Sendable {
    var id: String { url }
    var kind: String
    var title: String
    var url: String
    var summary: String
    var metadata: [String]
}

nonisolated struct GitHubToolResponse: Codable, Hashable, Sendable {
    var query: String
    var endpoint: String
    var mode: String
    var items: [GitHubToolItem]
    var fetchedAt: Date

    var formattedToolOutput: String {
        let itemLines = items.enumerated().map { index, item in
            let metadataLine = item.metadata.isEmpty ? "" : "\n   \(item.metadata.joined(separator: " - "))"
            let summaryLine = item.summary.isEmpty ? "" : "\n   \(item.summary)"
            return "\(index + 1). [\(item.kind)] \(item.title)\n   \(item.url)\(metadataLine)\(summaryLine)"
        }
        let block = itemLines.isEmpty ? "No GitHub results were returned." : itemLines.joined(separator: "\n\n")

        return """
        GitHub context
        Query: \(query)
        Mode: \(mode)
        Endpoint: \(endpoint)
        Fetched: \(fetchedAt.formatted(date: .abbreviated, time: .shortened))

        Results:
        \(block)
        """
    }
}

nonisolated enum GitHubToolServiceError: LocalizedError, Equatable {
    case emptyQuery
    case invalidEndpoint
    case badStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "GitHub requires a repository reference or search query."
        case .invalidEndpoint:
            "The GitHub endpoint is not a valid HTTPS URL."
        case .badStatus(let statusCode):
            "GitHub returned HTTP \(statusCode)."
        case .invalidResponse:
            "The GitHub response could not be read."
        }
    }
}

nonisolated struct GitHubToolService: Sendable {
    static let defaultEndpoint = "https://api.github.com"
    static let apiVersion = "2026-03-10"

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse?)

    private var transport: Transport

    init(transport: @escaping Transport = GitHubToolService.urlSessionTransport) {
        self.transport = transport
    }

    func fetch(_ toolRequest: GitHubToolRequest) async throws -> GitHubToolResponse {
        let route = try route(for: toolRequest)
        let request = try makeURLRequest(for: toolRequest, route: route)
        let (data, response) = try await transport(request)

        if let statusCode = response?.statusCode,
           !(200..<300).contains(statusCode) {
            throw GitHubToolServiceError.badStatus(statusCode)
        }

        guard !data.isEmpty else {
            throw GitHubToolServiceError.invalidResponse
        }

        let object = try JSONSerialization.jsonObject(with: data)
        let items = try parseItems(object, route: route)
        guard !items.isEmpty else {
            throw GitHubToolServiceError.invalidResponse
        }

        return GitHubToolResponse(
            query: toolRequest.query.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: request.url?.absoluteString ?? toolRequest.endpoint,
            mode: route.modeTitle,
            items: Array(items.prefix(toolRequest.resultLimit)),
            fetchedAt: .now
        )
    }

    func makeURLRequest(for toolRequest: GitHubToolRequest, route: GitHubToolRoute? = nil) throws -> URLRequest {
        let route = try route ?? self.route(for: toolRequest)
        guard var components = URLComponents(
            url: try baseURL(from: toolRequest.endpoint).appendingPathComponent(route.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw GitHubToolServiceError.invalidEndpoint
        }
        components.queryItems = route.queryItems

        guard let url = components.url else {
            throw GitHubToolServiceError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token = toolRequest.token?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func route(for toolRequest: GitHubToolRequest) throws -> GitHubToolRoute {
        let query = toolRequest.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw GitHubToolServiceError.emptyQuery
        }

        let limit = max(1, min(toolRequest.resultLimit, 20))
        if let issue = parseIssueReference(query) {
            return GitHubToolRoute(
                path: "/repos/\(issue.owner)/\(issue.repo)/issues/\(issue.number)",
                queryItems: [],
                kind: .issueDetail
            )
        }

        if let repo = parseRepoReference(query) {
            return GitHubToolRoute(
                path: "/repos/\(repo.owner)/\(repo.repo)",
                queryItems: [],
                kind: .repositoryDetail
            )
        }

        let lowered = query.lowercased()
        if lowered.hasPrefix("issues:") || lowered.hasPrefix("issue:") {
            return searchRoute(
                kind: .issueSearch,
                query: strippedPrefix(query, prefixes: ["issues:", "issue:"]),
                extraQualifier: "type:issue",
                limit: limit
            )
        }

        if lowered.hasPrefix("pulls:") || lowered.hasPrefix("prs:") || lowered.hasPrefix("pr:") {
            return searchRoute(
                kind: .pullRequestSearch,
                query: strippedPrefix(query, prefixes: ["pulls:", "prs:", "pr:"]),
                extraQualifier: "type:pr",
                limit: limit
            )
        }

        return searchRoute(kind: .repositorySearch, query: query, extraQualifier: nil, limit: limit)
    }

    private func searchRoute(
        kind: GitHubToolRoute.Kind,
        query: String,
        extraQualifier: String?,
        limit: Int
    ) -> GitHubToolRoute {
        let searchPath: String
        switch kind {
        case .issueSearch, .pullRequestSearch:
            searchPath = "/search/issues"
        case .repositorySearch:
            searchPath = "/search/repositories"
        case .repositoryDetail, .issueDetail:
            searchPath = "/search/repositories"
        }

        let q = ([query.trimmingCharacters(in: .whitespacesAndNewlines), extraQualifier]
            .compactMap { $0 }
            .filter { !$0.isEmpty })
            .joined(separator: " ")
        return GitHubToolRoute(
            path: searchPath,
            queryItems: [
                URLQueryItem(name: "q", value: q),
                URLQueryItem(name: "per_page", value: "\(limit)")
            ],
            kind: kind
        )
    }

    private func baseURL(from rawEndpoint: String) throws -> URL {
        let endpoint = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            throw GitHubToolServiceError.invalidEndpoint
        }
        return url
    }

    private func parseItems(_ object: Any, route: GitHubToolRoute) throws -> [GitHubToolItem] {
        switch route.kind {
        case .repositoryDetail:
            guard let dictionary = object as? [String: Any] else {
                throw GitHubToolServiceError.invalidResponse
            }
            return [repoItem(from: dictionary)].compactMap { $0 }
        case .issueDetail:
            guard let dictionary = object as? [String: Any] else {
                throw GitHubToolServiceError.invalidResponse
            }
            return [issueItem(from: dictionary)].compactMap { $0 }
        case .repositorySearch:
            return searchItems(in: object).compactMap(repoItem)
        case .issueSearch, .pullRequestSearch:
            return searchItems(in: object).compactMap(issueItem)
        }
    }

    private func searchItems(in object: Any) -> [[String: Any]] {
        guard let dictionary = object as? [String: Any],
              let items = dictionary["items"] as? [[String: Any]] else {
            return []
        }
        return items
    }

    private func repoItem(from dictionary: [String: Any]) -> GitHubToolItem? {
        guard let url = string(in: dictionary, keys: ["html_url", "url"]),
              let fullName = string(in: dictionary, keys: ["full_name", "name"]) else {
            return nil
        }
        let description = sanitize(string(in: dictionary, keys: ["description"]) ?? "")
        let stars = int(in: dictionary, key: "stargazers_count").map { "\($0) stars" }
        let forks = int(in: dictionary, key: "forks_count").map { "\($0) forks" }
        let issues = int(in: dictionary, key: "open_issues_count").map { "\($0) open issues" }
        let language = string(in: dictionary, keys: ["language"]).flatMap { $0.isEmpty ? nil : $0 }
        return GitHubToolItem(
            kind: "repository",
            title: fullName,
            url: url,
            summary: description,
            metadata: [language, stars, forks, issues].compactMap { $0 }
        )
    }

    private func issueItem(from dictionary: [String: Any]) -> GitHubToolItem? {
        guard let url = string(in: dictionary, keys: ["html_url", "url"]),
              let title = string(in: dictionary, keys: ["title"]) else {
            return nil
        }
        let number = int(in: dictionary, key: "number").map { "#\($0)" }
        let state = string(in: dictionary, keys: ["state"])
        let user = (dictionary["user"] as? [String: Any]).flatMap { string(in: $0, keys: ["login"]) }
        let kind = dictionary["pull_request"] == nil ? "issue" : "pull request"
        return GitHubToolItem(
            kind: kind,
            title: title,
            url: url,
            summary: sanitize(string(in: dictionary, keys: ["body"]) ?? ""),
            metadata: [number, state, user.map { "by \($0)" }].compactMap { $0 }
        )
    }

    private func parseRepoReference(_ query: String) -> (owner: String, repo: String)? {
        let candidate = strippedPrefix(query, prefixes: ["repo:", "repository:"])
        if let url = URL(string: candidate),
           url.host?.lowercased().contains("github.com") == true {
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 2 {
                return (parts[0], parts[1].replacingOccurrences(of: ".git", with: ""))
            }
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count == 2,
              isSafeGitHubPathSegment(parts[0]),
              isSafeGitHubPathSegment(parts[1]) else {
            return nil
        }
        return (parts[0], parts[1].replacingOccurrences(of: ".git", with: ""))
    }

    private func parseIssueReference(_ query: String) -> (owner: String, repo: String, number: Int)? {
        let candidate = strippedPrefix(query, prefixes: ["issue:", "pr:", "pull:"])
        if let url = URL(string: candidate),
           url.host?.lowercased().contains("github.com") == true {
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 4,
               ["issues", "pull"].contains(parts[2]),
               let number = Int(parts[3]) {
                return (parts[0], parts[1], number)
            }
        }

        let pattern = #"^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)#([0-9]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)),
              match.numberOfRanges == 4,
              let ownerRange = Range(match.range(at: 1), in: candidate),
              let repoRange = Range(match.range(at: 2), in: candidate),
              let numberRange = Range(match.range(at: 3), in: candidate),
              let number = Int(candidate[numberRange]) else {
            return nil
        }
        return (String(candidate[ownerRange]), String(candidate[repoRange]), number)
    }

    private func strippedPrefix(_ value: String, prefixes: [String]) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        for prefix in prefixes where lowered.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func isSafeGitHubPathSegment(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    private func string(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func int(in dictionary: [String: Any], key: String) -> Int? {
        if let value = dictionary[key] as? Int {
            return value
        }
        if let value = dictionary[key] as? Double {
            return Int(value)
        }
        return nil
    }

    private func sanitize(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 700 else {
            return collapsed
        }
        return String(collapsed.prefix(700)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse?) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as? HTTPURLResponse)
    }
}

nonisolated struct GitHubToolRoute: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case repositorySearch
        case issueSearch
        case pullRequestSearch
        case repositoryDetail
        case issueDetail
    }

    var path: String
    var queryItems: [URLQueryItem]
    var kind: Kind

    var modeTitle: String {
        switch kind {
        case .repositorySearch:
            "Repository search"
        case .issueSearch:
            "Issue search"
        case .pullRequestSearch:
            "Pull request search"
        case .repositoryDetail:
            "Repository detail"
        case .issueDetail:
            "Issue or pull request detail"
        }
    }
}
