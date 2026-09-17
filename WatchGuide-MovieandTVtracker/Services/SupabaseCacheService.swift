//
//  SupabaseCacheService.swift
//  WatchGuide-MovieandTVtracker
//
//  Shared server-side API response cache backed by Supabase.
//  Acts as an L2 cache behind each service's in-memory L1 cache.
//

import Foundation

actor SupabaseCacheService {
    static let shared = SupabaseCacheService()
    
    private var supabaseURL: String {
        ApiKeyManager.shared.get(key: "SUPABASE_URL") ?? ""
    }
    
    private var supabaseAnonKey: String {
        ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY") ?? ""
    }
    
    private init() {}
    
    var isConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
    
    // MARK: - Cache Source Identifiers
    
    enum CacheSource: String {
        case tmdb
        case mdblist
        case fanart
        case thetvdb
        case omdb
        case deeplink
        case watchalong
        case deepdive
    }
    
    // MARK: - TTL Presets (seconds)
    
    enum CacheTTL {
        static let trending: Int = 3600           // 1 hour
        static let popular: Int = 3600            // 1 hour
        static let search: Int = 3600             // 1 hour
        static let details: Int = 86400           // 24 hours
        static let credits: Int = 86400           // 24 hours
        static let videos: Int = 86400            // 24 hours
        static let providers: Int = 86400         // 24 hours
        static let ratings: Int = 43200           // 12 hours
        static let artwork: Int = 604800          // 7 days
        static let deepLinks: Int = 86400         // 24 hours
        static let genres: Int = 2592000          // 30 days
        static let discover: Int = 3600           // 1 hour
        static let episodeImages: Int = 604800    // 7 days
    }
    
    // Short timeout session — cache operations are best-effort
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
    
    // MARK: - Public API: Get cached response
    
    /// Returns raw Data if a valid (non-expired) cache entry exists, nil otherwise.
    func get(key: String) async -> Data? {
        guard isConfigured else { return nil }
        
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        let nowString = iso8601String(from: Date())
        
        guard var components = URLComponents(string: "\(supabaseURL)/rest/v1/api_cache") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "cache_key", value: "eq.\(encodedKey)"),
            URLQueryItem(name: "expires_at", value: "gt.\(nowString)"),
            URLQueryItem(name: "select", value: "response_data"),
            URLQueryItem(name: "limit", value: "1")
        ]
        
        guard let url = components.url else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return nil
            }
            
            // Supabase returns: [{"response_data": {...}}]
            guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = array.first,
                  let responseData = first["response_data"] else {
                return nil
            }
            
            return try? JSONSerialization.data(withJSONObject: responseData)
        } catch {
            return nil
        }
    }
    
    /// Convenience: returns decoded value if cache hit, nil otherwise.
    func get<T: Decodable>(key: String, as type: T.Type, decoder: JSONDecoder = JSONDecoder()) async -> T? {
        guard let data = await get(key: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
    
    // MARK: - Public API: Set cache entry
    
    /// Store a response in the shared cache. Callers should fire-and-forget.
    func set(key: String, source: CacheSource, responseData: Data, ttlSeconds: Int) async {
        guard isConfigured else { return }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: responseData) else {
            return
        }
        
        let now = Date()
        let expiresAt = now.addingTimeInterval(TimeInterval(ttlSeconds))
        
        let body: [String: Any] = [
            "cache_key": key,
            "source": source.rawValue,
            "response_data": jsonObject,
            "ttl_seconds": ttlSeconds,
            "created_at": iso8601String(from: now),
            "expires_at": iso8601String(from: expiresAt),
            "hit_count": 0
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return
        }
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/api_cache") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.addValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = bodyData
        
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                print("SupabaseCacheService set failed: HTTP \(http.statusCode)")
            }
        } catch {
            // Best-effort — silently ignore cache write failures
        }
    }
    
    // MARK: - Date Helpers
    
    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    
    // MARK: - Cache Key Builders
    
    /// Build a deterministic cache key for TMDB requests.
    /// Strips the api_key parameter since it's constant.
    nonisolated static func tmdbCacheKey(endpoint: String, queryItems: [URLQueryItem]) -> String {
        let filtered = queryItems.filter { $0.name != "api_key" }
        let sortedParams = filtered
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        
        return sortedParams.isEmpty
            ? "tmdb:\(endpoint)"
            : "tmdb:\(endpoint)?\(sortedParams)"
    }
    
    /// Build a cache key for MDBList requests.
    nonisolated static func mdblistCacheKey(type: String, identifier: String) -> String {
        "mdblist:\(type):\(identifier)"
    }
    
    /// Build a cache key for FanArt requests.
    nonisolated static func fanartCacheKey(mediaType: String, id: Int) -> String {
        "fanart:\(mediaType):\(id)"
    }
    
    /// Build a cache key for TheTVDB requests.
    nonisolated static func thetvdbCacheKey(tvdbSeriesId: Int, season: Int, episode: Int) -> String {
        "thetvdb:\(tvdbSeriesId):s\(season)e\(episode)"
    }
    
    /// Build a cache key for OMDb requests.
    nonisolated static func omdbCacheKey(imdbId: String) -> String {
        "omdb:\(imdbId)"
    }
    
    /// Build a cache key for StreamingDeepLink requests.
    nonisolated static func deepLinkCacheKey(mediaType: String, tmdbId: Int, country: String) -> String {
        "deeplink:\(mediaType):\(tmdbId):\(country)"
    }
    
    // MARK: - TTL Determination for TMDB endpoints
    
    /// Determine the appropriate TTL for a TMDB endpoint based on the path pattern.
    nonisolated static func tmdbTTL(for endpoint: String) -> Int {
        if endpoint.contains("/genre/") { return CacheTTL.genres }
        if endpoint.contains("/trending/") { return CacheTTL.trending }
        if endpoint.contains("/search/") { return CacheTTL.search }
        if endpoint.contains("/discover/") { return CacheTTL.discover }
        
        if endpoint.hasSuffix("/popular") ||
           endpoint.hasSuffix("/top_rated") ||
           endpoint.hasSuffix("/now_playing") ||
           endpoint.hasSuffix("/airing_today") ||
           endpoint.hasSuffix("/on_the_air") {
            return CacheTTL.popular
        }
        
        if endpoint.contains("/credits") { return CacheTTL.credits }
        if endpoint.contains("/videos") { return CacheTTL.videos }
        if endpoint.contains("/watch/providers") { return CacheTTL.providers }
        if endpoint.contains("/images") { return CacheTTL.artwork }
        
        if endpoint.contains("/reviews") ||
           endpoint.contains("/similar") ||
           endpoint.contains("/recommendations") {
            return CacheTTL.details
        }
        
        if endpoint.contains("/release_dates") ||
           endpoint.contains("/content_ratings") {
            return CacheTTL.details
        }
        
        // Movie/TV/Person details, collections, companies, find — default 24h
        return CacheTTL.details
    }
}
