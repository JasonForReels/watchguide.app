//
//  StreamingDeepLinkService.swift
//  WatchGuide-MovieandTVtracker
//
//  Fetches per-title deep links from the Movie of the Night Streaming Availability API
//  so tapping a provider logo opens the exact content page instead of a search.
//

import Foundation

// MARK: - Models

struct StreamingDeepLink: Sendable {
    let serviceId: String   // MOTN service id, e.g. "netflix", "disney"
    let type: String        // "subscription", "rent", "buy", "free", "addon"
    let link: URL           // Direct deep link URL
}

// MARK: - Service

actor StreamingDeepLinkService {
    static let shared = StreamingDeepLinkService()

    // MARK: - Cache

    private struct CacheEntry {
        let links: [StreamingDeepLink]
        let timestamp: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 600 // 10 minutes

    // MARK: - Networking

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private let baseURL = "https://api.movieofthenight.com/v4"

    private var apiKey: String? {
        ApiKeyManager.shared.get(key: "MOTN_API_KEY")
    }

    // MARK: - Public API

    /// Fetch deep links for a given TMDB ID and media type in the specified country.
    func fetchDeepLinks(tmdbId: Int, mediaType: MediaType, country: String) async -> [StreamingDeepLink] {
        let normalizedCountry = country.lowercased()
        let mediaPath = mediaType == .movie ? "movie" : "tv"
        let cacheKey = "\(mediaPath)/\(tmdbId)/\(normalizedCountry)"

        // Check cache
        if let entry = cache[cacheKey], Date().timeIntervalSince(entry.timestamp) < cacheTTL {
            return entry.links
        }

        // Evict stale entries periodically
        if cache.count > 200 {
            let now = Date()
            cache = cache.filter { now.timeIntervalSince($0.value.timestamp) < cacheTTL }
        }

        guard let key = apiKey, !key.isEmpty else {
            return []
        }

        guard var components = URLComponents(string: "\(baseURL)/shows/\(mediaPath)/\(tmdbId)") else {
            return []
        }
        components.queryItems = [URLQueryItem(name: "country", value: normalizedCountry)]

        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }

            let links = parseDeepLinks(from: data, country: normalizedCountry)
            cache[cacheKey] = CacheEntry(links: links, timestamp: Date())
            return links
        } catch {
            return []
        }
    }

    /// Look up the best deep link for a given TMDB provider ID from previously fetched links.
    /// Prefers "subscription" > "free" > "ads" > "addon" > "rent" > "buy".
    func deepLink(forTMDBProviderId providerId: Int, from links: [StreamingDeepLink]) -> URL? {
        guard let motnId = Self.tmdbToMOTN[providerId] else { return nil }

        let matching = links.filter { $0.serviceId == motnId }
        guard !matching.isEmpty else { return nil }

        let priority = ["subscription", "free", "ads", "addon", "rent", "buy"]
        for type in priority {
            if let link = matching.first(where: { $0.type == type }) {
                return link.link
            }
        }
        return matching.first?.link
    }

    // MARK: - Parsing

    private func parseDeepLinks(from data: Data, country: String) -> [StreamingDeepLink] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streamingOptions = json["streamingOptions"] as? [String: Any],
              let countryOptions = streamingOptions[country] as? [[String: Any]] else {
            return []
        }

        var results: [StreamingDeepLink] = []
        for option in countryOptions {
            guard let service = option["service"] as? [String: Any],
                  let serviceId = service["id"] as? String,
                  let type = option["type"] as? String,
                  let linkString = option["link"] as? String,
                  let link = URL(string: linkString) else {
                continue
            }
            results.append(StreamingDeepLink(serviceId: serviceId, type: type, link: link))
        }
        return results
    }

    // MARK: - TMDB Provider ID → MOTN Service ID Mapping

    static let tmdbToMOTN: [Int: String] = [
        // Netflix
        8: "netflix",
        // Disney+
        337: "disney",
        // Max / HBO Max
        384: "hbo",
        1899: "hbo",
        // Hulu
        15: "hulu",
        // Paramount+
        531: "paramount",
        582: "paramount",
        // Peacock
        386: "peacock",
        387: "peacock",
        // Apple TV
        350: "apple",
        2: "apple",
        // Crunchyroll
        283: "crunchyroll",
        // Discovery+
        510: "discovery",
        584: "discovery",
        // MUBI
        11: "mubi",
        // Showmax
        55: "showmax",
        // BritBox
        380: "britbox",
        151: "britbox",
        // Tubi
        73: "tubi",
        // Pluto TV
        300: "plutotv",
        // Vudu / Fandango at Home
        7: "vudu",
        // Shudder
        99: "shudder",
        // Starz
        43: "starz",
        // Amazon Prime Video
        10: "prime",
        119: "prime",
        9: "prime",
        // Google Play Movies
        3: "google",
        192: "google",
    ]
}
