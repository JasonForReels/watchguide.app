//
//  FreeWebSearchService.swift
//  WatchGuide-MovieandTVtracker
//
//  Keyless, zero-cost web search used to give free OpenRouter models live web
//  context (RAG) instead of the paid OpenRouter web plugin. Backed by
//  DuckDuckGo's keyless endpoints — best-effort, with graceful fallback to
//  "no context" when a query returns nothing.
//

import Foundation

actor FreeWebSearchService {
    static let shared = FreeWebSearchService()
    private init() {}

    struct Result: Hashable {
        let title: String
        let snippet: String
        let url: String
    }

    /// Runs a keyless web search and returns a small set of result snippets.
    /// Tries DuckDuckGo's Instant Answer JSON first (stable), then enriches with
    /// the HTML results page (broader coverage, more fragile). Never throws —
    /// returns whatever it could gather, possibly empty.
    func search(_ query: String, maxResults: Int = 5) async -> [Result] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var collected: [Result] = []
        var seenURLs = Set<String>()

        func add(_ results: [Result]) {
            for r in results where !r.snippet.isEmpty {
                let key = r.url.isEmpty ? r.snippet : r.url
                guard !seenURLs.contains(key) else { continue }
                seenURLs.insert(key)
                collected.append(r)
            }
        }

        add(await instantAnswer(for: trimmed))
        if collected.count < maxResults {
            add(await htmlResults(for: trimmed))
        }

        return Array(collected.prefix(maxResults))
    }

    /// Formats search results as a compact, prompt-injectable context block.
    /// Returns nil when there were no usable results.
    func contextBlock(for query: String, maxResults: Int = 5) async -> String? {
        let results = await search(query, maxResults: maxResults)
        guard !results.isEmpty else { return nil }

        let body = results.enumerated().map { index, r -> String in
            var line = "\(index + 1). \(r.title)\n\(r.snippet)"
            if !r.url.isEmpty { line += "\nSource: \(r.url)" }
            return line
        }.joined(separator: "\n\n")

        return body
    }

    // MARK: - DuckDuckGo Instant Answer (keyless JSON)

    private func instantAnswer(for query: String) async -> [Result] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1")
        else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        guard let data = try? await URLSession.shared.data(for: request).0,
              let payload = try? JSONDecoder().decode(InstantAnswer.self, from: data)
        else { return [] }

        var results: [Result] = []

        if let abstract = payload.AbstractText, !abstract.isEmpty {
            results.append(Result(
                title: payload.Heading ?? query,
                snippet: abstract,
                url: payload.AbstractURL ?? ""
            ))
        }

        // RelatedTopics may contain nested topic groups; flatten one level.
        func harvest(_ topics: [InstantAnswer.Topic]) {
            for topic in topics {
                if let nested = topic.Topics {
                    harvest(nested)
                } else if let text = topic.Text, !text.isEmpty {
                    results.append(Result(title: text, snippet: text, url: topic.FirstURL ?? ""))
                }
            }
        }
        harvest(payload.RelatedTopics ?? [])

        return results
    }

    private struct InstantAnswer: Codable {
        let Heading: String?
        let AbstractText: String?
        let AbstractURL: String?
        let RelatedTopics: [Topic]?

        struct Topic: Codable {
            let Text: String?
            let FirstURL: String?
            let Topics: [Topic]?
        }
    }

    // MARK: - DuckDuckGo HTML results (keyless, scraped)

    private func htmlResults(for query: String) async -> [Result] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)")
        else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        // A browser-like UA avoids the bare-bones blocked response.
        request.addValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        guard let data = try? await URLSession.shared.data(for: request).0,
              let html = String(data: data, encoding: .utf8)
        else { return [] }

        return parseHTMLResults(html)
    }

    /// Extracts result titles/links/snippets from DuckDuckGo's HTML results page.
    private func parseHTMLResults(_ html: String) -> [Result] {
        let titles = matches(in: html, pattern: "class=\"result__a\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>", groups: 2)
        let snippets = matches(in: html, pattern: "class=\"result__snippet\"[^>]*>(.*?)</a>", groups: 1)

        var results: [Result] = []
        for (index, title) in titles.enumerated() {
            let link = decodeDDGRedirect(title[0])
            let titleText = stripHTML(title[1])
            let snippet = index < snippets.count ? stripHTML(snippets[index][0]) : titleText
            guard !titleText.isEmpty else { continue }
            results.append(Result(title: titleText, snippet: snippet, url: link))
        }
        return results
    }

    /// Returns the captured groups for every regex match.
    private func matches(in text: String, pattern: String, groups: Int) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            var captures: [String] = []
            for group in 1...groups {
                guard let r = Range(match.range(at: group), in: text) else { return nil }
                captures.append(String(text[r]))
            }
            return captures
        }
    }

    /// DuckDuckGo wraps result links as `/l/?uddg=<encoded-target>`; unwrap them.
    private func decodeDDGRedirect(_ href: String) -> String {
        let normalized = href.hasPrefix("//") ? "https:\(href)" : href
        guard let comps = URLComponents(string: normalized),
              let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value
        else { return normalized }
        return uddg
    }

    /// Removes HTML tags and decodes the few entities DuckDuckGo emits.
    private func stripHTML(_ input: String) -> String {
        var text = input.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#x27;": "'", "&#39;": "'", "&nbsp;": " "]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
