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
    let addonId: String?    // For addon type: the add-on identifier, e.g. "hulu" under "disney"
    let link: URL           // Deep link to title page
    let videoLink: URL?     // Deep link that starts playback (available for some services)
    let expiresOn: Date?    // When the title leaves this service, if announced
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
        ApiKeyManager.shared.get(key: "MOTN_API_KEY") ?? "motn-key-v4-NPc1rsKqfO2CDkFol4n29R0IM45GyMhj"
    }

    // MARK: - Public API

    /// Fetch deep links for a given TMDB ID and media type in the specified country.
    func fetchDeepLinks(tmdbId: Int, mediaType: MediaType, country: String) async -> [StreamingDeepLink] {
        let normalizedCountry = country.lowercased()
        let mediaPath = mediaType == .movie ? "movie" : "tv"
        let cacheKey = "\(mediaPath)/\(tmdbId)/\(normalizedCountry)"

        // L1: in-memory cache
        if let entry = cache[cacheKey], Date().timeIntervalSince(entry.timestamp) < cacheTTL {
            return entry.links
        }

        // Evict stale entries periodically
        if cache.count > 200 {
            let now = Date()
            cache = cache.filter { now.timeIntervalSince($0.value.timestamp) < cacheTTL }
        }
        
        // L2: Supabase shared cache
        let supabaseKey = SupabaseCacheService.deepLinkCacheKey(mediaType: mediaPath, tmdbId: tmdbId, country: normalizedCountry)
        if let cachedData = await SupabaseCacheService.shared.get(key: supabaseKey) {
            let links = parseDeepLinks(from: cachedData, country: normalizedCountry)
            if !links.isEmpty {
                cache[cacheKey] = CacheEntry(links: links, timestamp: Date())
                return links
            }
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
            
            // Fire-and-forget L2 write
            let capturedData = data
            Task.detached {
                await SupabaseCacheService.shared.set(
                    key: supabaseKey,
                    source: .deeplink,
                    responseData: capturedData,
                    ttlSeconds: SupabaseCacheService.CacheTTL.deepLinks
                )
            }
            
            return links
        } catch {
            return []
        }
    }

    /// Look up the best deep link for a given TMDB provider ID from previously fetched links.
    /// Prefers "subscription" > "free" > "ads" > "addon" > "rent" > "buy".
    /// For streamable types (subscription/free/ads/addon), prefers `videoLink` (auto-play) over `link` (title page).
    ///
    /// Hulu is fully merged into Disney+. The MOTN API returns both a standalone
    /// "hulu" entry (hulu.com links) and a "disney" entry (disneyplus.com links)
    /// for Hulu content. For Hulu lookups we prefer the Disney+ entry so the user
    /// lands in the Disney+ app, falling back to the Hulu entry only if no Disney+
    /// entry exists.
    func deepLink(forTMDBProviderId providerId: Int, from links: [StreamingDeepLink]) -> URL? {
        guard let motnId = Self.tmdbToMOTN[providerId] else { return nil }

        // For Hulu, try Disney+ links first, then fall back to standalone Hulu links.
        if providerId == 15 {
            if let disneyURL = bestLink(from: links, serviceId: "disney") {
                return disneyURL
            }
        }

        return bestLink(from: links, serviceId: motnId)
    }

    /// The date a title leaves the given TMDB provider's streaming catalog, if
    /// MOTN has one. Only streamable options count — a rental "expiring" is noise.
    nonisolated static func leavingDate(forTMDBProviderId providerId: Int, from links: [StreamingDeepLink]) -> Date? {
        guard let motnId = tmdbToMOTN[providerId] else { return nil }
        let serviceIds: Set<String> = providerId == 15 ? [motnId, "disney"] : [motnId]
        let streamableTypes: Set<String> = ["subscription", "free", "ads", "addon"]
        return links
            .filter { serviceIds.contains($0.serviceId) && streamableTypes.contains($0.type) }
            .compactMap(\.expiresOn)
            .min()
    }

    /// Finds the best URL from `links` filtered to the given MOTN service ID.
    private func bestLink(from links: [StreamingDeepLink], serviceId: String) -> URL? {
        let matching = links.filter { $0.serviceId == serviceId }
        guard !matching.isEmpty else { return nil }

        let streamableTypes: Set<String> = ["subscription", "free", "ads", "addon"]
        let priority = ["subscription", "free", "ads", "addon", "rent", "buy"]
        for type in priority {
            if let match = matching.first(where: { $0.type == type }) {
                // For streamable content, prefer videoLink (auto-play) if available
                if streamableTypes.contains(type), let videoLink = match.videoLink {
                    return videoLink
                }
                return match.link
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
            let videoLink: URL? = {
                guard let videoLinkString = option["videoLink"] as? String else { return nil }
                return URL(string: videoLinkString)
            }()
            let addonId = (option["addon"] as? [String: Any])?["id"] as? String
            let expiresOn = (option["expiresOn"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            results.append(StreamingDeepLink(serviceId: serviceId, type: type, addonId: addonId, link: link, videoLink: videoLink, expiresOn: expiresOn))
        }
        return results
    }

    // MARK: - Daily Cache Warm-Up

    private static let lastWarmUpKey = "motn_last_warmup_date"
    private static let warmUpInterval: TimeInterval = 86400 // 24 hours

    /// Call once on app launch. Requires a WatchGuide Pro subscription.
    /// Checks if 24h have passed since the last warm-up, and if so,
    /// prefetches deep links for all items in the user's lists
    /// (Want to Watch, Watched, Liked). Runs in the background without blocking UI.
    func warmCacheIfNeeded() async {
        // Only available for WatchGuide Pro subscribers
        let isUnlimited = await MainActor.run { ScoutSubscriptionService.shared.isUnlimitedActive }
        guard isUnlimited else { return }

        let now = Date()
        let lastWarmUp = UserDefaults.standard.double(forKey: Self.lastWarmUpKey)
        guard lastWarmUp == 0 || now.timeIntervalSince1970 - lastWarmUp >= Self.warmUpInterval else {
            return
        }

        // Mark immediately so concurrent launches don't duplicate work
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastWarmUpKey)

        let region = await MainActor.run { StorageService.shared.settings.region }

        // Gather unique (mediaId, mediaType) pairs from all user lists
        let allItems: [(id: Int, type: MediaType)] = await MainActor.run {
            let storage = StorageService.shared
            var seen = Set<String>()
            var items: [(id: Int, type: MediaType)] = []
            for saved in storage.wantToWatch + storage.watched + storage.liked {
                guard saved.mediaType != .person else { continue }
                let key = "\(saved.mediaType.rawValue)_\(saved.mediaId)"
                if seen.insert(key).inserted {
                    items.append((id: saved.mediaId, type: saved.mediaType))
                }
            }
            return items
        }

        guard !allItems.isEmpty else { return }

        // Fetch sequentially with a small delay to respect rate limits
        for item in allItems {
            _ = await fetchDeepLinks(tmdbId: item.id, mediaType: item.type, country: region)
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms between requests
        }
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
