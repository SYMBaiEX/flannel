//
//  BrowserAutomationService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import AppKit
import Foundation

struct BrowserAutomationRequest: Sendable, Hashable {
    var query: String
    var searchEndpoint: String

    init(
        query: String,
        searchEndpoint: String = BrowserAutomationService.defaultSearchEndpoint
    ) {
        self.query = query
        self.searchEndpoint = searchEndpoint
    }
}

struct BrowserAutomationResponse: Sendable, Hashable {
    enum Action: Sendable, Hashable {
        case openURL
        case searchWeb

        var title: String {
            switch self {
            case .openURL:
                "URL"
            case .searchWeb:
                "web search"
            }
        }
    }

    var action: Action
    var targetURL: URL

    var formattedToolOutput: String {
        """
        Browser automation opened \(action.title) in the default browser.
        Target: \(targetURL.absoluteString)

        Safety boundary: Flannel opened the browser only. It did not read page contents, inspect the DOM, click controls, submit forms, or interact with credentials.
        """
    }
}

enum BrowserAutomationServiceError: LocalizedError, Equatable {
    case emptyQuery
    case invalidURL(String)
    case unsupportedScheme(String)
    case invalidSearchEndpoint(String)
    case openRejected(URL)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "Browser automation needs a URL or a search query."
        case .invalidURL(let value):
            "Browser automation could not turn \"\(value)\" into a safe URL or search."
        case .unsupportedScheme(let scheme):
            "Browser automation only opens http and https URLs, not \(scheme) URLs."
        case .invalidSearchEndpoint(let endpoint):
            "Browser automation has an invalid search endpoint: \(endpoint)."
        case .openRejected(let url):
            "macOS did not accept the request to open \(url.absoluteString)."
        }
    }
}

struct BrowserAutomationService: Sendable {
    static let defaultSearchEndpoint = "https://duckduckgo.com/"

    private let openURL: @Sendable (URL) async -> Bool

    nonisolated init(openURL: @escaping @Sendable (URL) async -> Bool = BrowserAutomationService.openInDefaultBrowser) {
        self.openURL = openURL
    }

    func run(_ request: BrowserAutomationRequest) async throws -> BrowserAutomationResponse {
        let target = try Self.target(for: request.query, searchEndpoint: request.searchEndpoint)
        let didOpen = await openURL(target.url)
        guard didOpen else {
            throw BrowserAutomationServiceError.openRejected(target.url)
        }
        return BrowserAutomationResponse(action: target.action, targetURL: target.url)
    }

    private static func openInDefaultBrowser(_ url: URL) async -> Bool {
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    private static func target(
        for rawQuery: String,
        searchEndpoint: String
    ) throws -> (url: URL, action: BrowserAutomationResponse.Action) {
        guard var candidate = firstMeaningfulLine(in: rawQuery) else {
            throw BrowserAutomationServiceError.emptyQuery
        }

        let lowercasedCandidate = candidate.lowercased()
        for prefix in ["open:", "url:", "visit:", "go:"] where lowercasedCandidate.hasPrefix(prefix) {
            candidate = String(candidate.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return (try safeURL(from: candidate), .openURL)
        }

        for prefix in ["search:", "find:"] where lowercasedCandidate.hasPrefix(prefix) {
            let searchQuery = String(candidate.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return (try searchURL(for: searchQuery, endpoint: searchEndpoint), .searchWeb)
        }

        if let url = try possibleSafeURL(from: candidate) {
            return (url, .openURL)
        }

        return (try searchURL(for: candidate, endpoint: searchEndpoint), .searchWeb)
    }

    private static func firstMeaningfulLine(in query: String) -> String? {
        query
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func safeURL(from candidate: String) throws -> URL {
        guard let url = try possibleSafeURL(from: candidate) else {
            throw BrowserAutomationServiceError.invalidURL(candidate)
        }
        return url
    }

    private static func possibleSafeURL(from rawCandidate: String) throws -> URL? {
        let candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            throw BrowserAutomationServiceError.emptyQuery
        }

        if let components = URLComponents(string: candidate),
           let scheme = components.scheme {
            guard ["http", "https"].contains(scheme.lowercased()) else {
                throw BrowserAutomationServiceError.unsupportedScheme(scheme)
            }
            guard components.host?.isEmpty == false,
                  let url = components.url else {
                throw BrowserAutomationServiceError.invalidURL(candidate)
            }
            return url
        }

        guard candidate.contains("."),
              candidate.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              candidate.range(of: "\0") == nil,
              let url = URL(string: "https://\(candidate)") else {
            return nil
        }
        return url
    }

    private static func searchURL(for rawQuery: String, endpoint: String) throws -> URL {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw BrowserAutomationServiceError.emptyQuery
        }

        guard var components = URLComponents(string: endpoint),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host?.isEmpty == false else {
            throw BrowserAutomationServiceError.invalidSearchEndpoint(endpoint)
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "q" }
        queryItems.append(URLQueryItem(name: "q", value: query))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw BrowserAutomationServiceError.invalidSearchEndpoint(endpoint)
        }
        return url
    }
}
