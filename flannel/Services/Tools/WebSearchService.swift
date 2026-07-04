//
//  WebSearchService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation

nonisolated struct WebSearchRequest: Hashable, Sendable {
    var query: String
    var endpoint: String
    var apiKey: String
    var resultLimit: Int

    init(
        query: String,
        endpoint: String = WebSearchService.defaultEndpoint,
        apiKey: String,
        resultLimit: Int = 8
    ) {
        self.query = query
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.resultLimit = resultLimit
    }
}

nonisolated struct WebSearchResult: Identifiable, Codable, Hashable, Sendable {
    var id: String { url }
    var title: String
    var url: String
    var description: String
    var snippets: [String]

    var bestSnippet: String {
        snippets.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? description
    }
}

nonisolated struct WebSearchResponse: Codable, Hashable, Sendable {
    var query: String
    var endpoint: String
    var results: [WebSearchResult]
    var context: String?
    var fetchedAt: Date

    var formattedToolOutput: String {
        let sourceLines = results.enumerated().map { index, result in
            let snippet = result.bestSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippetLine = snippet.isEmpty ? "" : "\n   \(snippet)"
            return "\(index + 1). \(result.title)\n   \(result.url)\(snippetLine)"
        }
        let sourceBlock = sourceLines.isEmpty
            ? "No source URLs were returned."
            : sourceLines.joined(separator: "\n\n")

        let contextBlock: String
        if let context,
           !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contextBlock = "\n\nLLM context:\n\(context.trimmingCharacters(in: .whitespacesAndNewlines))"
        } else {
            contextBlock = ""
        }

        return """
        Live web search
        Query: \(query)
        Endpoint: \(endpoint)
        Fetched: \(fetchedAt.formatted(date: .abbreviated, time: .shortened))

        Sources:
        \(sourceBlock)\(contextBlock)
        """
    }
}

nonisolated enum WebSearchServiceError: LocalizedError, Equatable {
    case emptyQuery
    case invalidEndpoint
    case badStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "Web search requires a non-empty query."
        case .invalidEndpoint:
            "The web search endpoint is not a valid HTTPS URL."
        case .badStatus(let statusCode):
            "The web search provider returned HTTP \(statusCode)."
        case .invalidResponse:
            "The web search response could not be read."
        }
    }
}

nonisolated struct WebSearchService: Sendable {
    static let defaultEndpoint = "https://api.search.brave.com/res/v1/llm/context"
    static let perplexityEndpoint = "https://api.perplexity.ai/search"

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse?)

    private var transport: Transport

    init(transport: @escaping Transport = WebSearchService.urlSessionTransport) {
        self.transport = transport
    }

    func search(_ searchRequest: WebSearchRequest) async throws -> WebSearchResponse {
        let request = try makeURLRequest(for: searchRequest)
        let (data, response) = try await transport(request)

        if let statusCode = response?.statusCode,
           !(200..<300).contains(statusCode) {
            throw WebSearchServiceError.badStatus(statusCode)
        }

        guard !data.isEmpty else {
            throw WebSearchServiceError.invalidResponse
        }

        let object = try JSONSerialization.jsonObject(with: data)
        return try Self.parseResponse(
            object,
            query: searchRequest.query.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: request.url?.absoluteString ?? searchRequest.endpoint
        )
    }

    func makeURLRequest(for searchRequest: WebSearchRequest) throws -> URLRequest {
        let query = searchRequest.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw WebSearchServiceError.emptyQuery
        }

        guard let endpointURL = URL(string: searchRequest.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              endpointURL.scheme?.lowercased() == "https",
              var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
            throw WebSearchServiceError.invalidEndpoint
        }

        if isPerplexityHost(endpointURL) {
            return try makePerplexityRequest(
                endpointURL: endpointURL,
                query: query,
                apiKey: searchRequest.apiKey,
                limit: max(1, min(searchRequest.resultLimit, 20))
            )
        }

        let limit = max(1, min(searchRequest.resultLimit, usesLLMContextEndpoint(endpointURL) ? 50 : 20))
        components.queryItems = requestQueryItems(
            existing: components.queryItems ?? [],
            query: query,
            limit: limit,
            endpointURL: endpointURL
        )

        guard let url = components.url else {
            throw WebSearchServiceError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(searchRequest.apiKey, forHTTPHeaderField: "X-Subscription-Token")
        return request
    }

    private func makePerplexityRequest(
        endpointURL: URL,
        query: String,
        apiKey: String,
        limit: Int
    ) throws -> URLRequest {
        guard let url = normalizedPerplexitySearchURL(from: endpointURL) else {
            throw WebSearchServiceError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            PerplexitySearchRequestPayload(query: query, maxResults: limit)
        )
        return request
    }

    private func requestQueryItems(
        existing: [URLQueryItem],
        query: String,
        limit: Int,
        endpointURL: URL
    ) -> [URLQueryItem] {
        var keyedItems = Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0.value) })
        keyedItems["q"] = query

        if usesLLMContextEndpoint(endpointURL) {
            keyedItems["count"] = keyedItems["count"] ?? String(limit)
            keyedItems["maximum_number_of_urls"] = keyedItems["maximum_number_of_urls"] ?? String(limit)
            keyedItems["maximum_number_of_tokens"] = keyedItems["maximum_number_of_tokens"] ?? "12000"
            keyedItems["maximum_number_of_snippets"] = keyedItems["maximum_number_of_snippets"] ?? "48"
            keyedItems["context_threshold_mode"] = keyedItems["context_threshold_mode"] ?? "balanced"
            keyedItems["enable_source_metadata"] = keyedItems["enable_source_metadata"] ?? "true"
        } else {
            keyedItems["count"] = keyedItems["count"] ?? String(limit)
            keyedItems["safesearch"] = keyedItems["safesearch"] ?? "moderate"
            keyedItems["text_decorations"] = keyedItems["text_decorations"] ?? "false"
            keyedItems["extra_snippets"] = keyedItems["extra_snippets"] ?? "true"
            keyedItems["result_filter"] = keyedItems["result_filter"] ?? "web"
        }

        return keyedItems
            .map { URLQueryItem(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private func usesLLMContextEndpoint(_ url: URL) -> Bool {
        url.path.lowercased().contains("/llm/context")
    }

    private func isPerplexityHost(_ url: URL) -> Bool {
        url.host?.lowercased() == "api.perplexity.ai"
    }

    private func normalizedPerplexitySearchURL(from url: URL) -> URL? {
        guard isPerplexityHost(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let path = components.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        if path.isEmpty {
            components.path = "/search"
        } else if path != "search" {
            return nil
        }
        components.queryItems = nil
        return components.url
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse?) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as? HTTPURLResponse)
    }

    private static func parseResponse(
        _ object: Any,
        query: String,
        endpoint: String
    ) throws -> WebSearchResponse {
        let dictionaries = collectResultDictionaries(in: object)
        var seenURLs = Set<String>()
        let results = dictionaries.compactMap { dictionary -> WebSearchResult? in
            guard let url = firstString(in: dictionary, keys: ["url", "link", "source_url"]),
                  !url.isEmpty,
                  seenURLs.insert(url).inserted else {
                return nil
            }

            let title = firstString(in: dictionary, keys: ["title", "name", "site_name"]) ?? url
            let description = firstString(in: dictionary, keys: ["description", "snippet", "summary", "content", "text"]) ?? ""
            let snippets = firstStringArray(in: dictionary, keys: ["snippets", "extra_snippets", "summary_snippets"])
            return WebSearchResult(
                title: sanitize(title),
                url: url,
                description: sanitize(description),
                snippets: snippets.map(sanitize)
            )
        }

        let context = firstLongContext(in: object).map(sanitize)
        guard !results.isEmpty || context?.isEmpty == false else {
            throw WebSearchServiceError.invalidResponse
        }

        return WebSearchResponse(
            query: query,
            endpoint: endpoint,
            results: Array(results.prefix(12)),
            context: context,
            fetchedAt: .now
        )
    }

    private static func collectResultDictionaries(in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            var matches: [[String: Any]] = []
            if dictionary.keys.contains(where: { ["url", "link", "source_url"].contains($0) }) {
                matches.append(dictionary)
            }

            for nested in dictionary.values {
                matches.append(contentsOf: collectResultDictionaries(in: nested))
            }
            return matches
        }

        if let array = value as? [Any] {
            return array.flatMap { collectResultDictionaries(in: $0) }
        }

        return []
    }

    private static func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func firstStringArray(in dictionary: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let values = dictionary[key] as? [String] {
                return values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            if let values = dictionary[key] as? [Any] {
                let strings = values.compactMap { $0 as? String }
                if !strings.isEmpty {
                    return strings
                }
            }
        }
        return []
    }

    private static func firstLongContext(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            for key in ["context", "llm_context", "content", "summary", "text"] {
                if let string = dictionary[key] as? String,
                   string.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 {
                    return string
                }
            }
            for nested in dictionary.values {
                if let context = firstLongContext(in: nested) {
                    return context
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let context = firstLongContext(in: nested) {
                    return context
                }
            }
        }

        return nil
    }

    private static func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated private struct PerplexitySearchRequestPayload: Encodable {
    var query: String
    var maxResults: Int

    enum CodingKeys: String, CodingKey {
        case query
        case maxResults = "max_results"
    }
}
