//
//  TheTVDBService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

/// Provides episode thumbnail images from TheTVDB v4 API as a fallback
/// when TMDB lacks episode still images.
actor TheTVDBService {
    static let shared = TheTVDBService()
    private init() {}

    // MARK: - Configuration

    private let baseURL = "https://api4.thetvdb.com/v4"
    private let apiKey = "099dcf07-ee4f-441c-8be0-3a7759660f9b"

    // MARK: - State

    private var bearerToken: String?
    private var imageCache: [String: URL] = [:]
    private var negativeCacheKeys: Set<String> = []

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    /// Returns an episode image URL from TheTVDB, or nil if unavailable.
    /// Uses TMDB show ID and resolves to TVDB ID internally.
    func episodeImageURL(tmdbShowId: Int, season: Int, episode: Int) async -> URL? {
        let cacheKey = "\(tmdbShowId)-\(season)-\(episode)"

        // Check positive cache
        if let cached = imageCache[cacheKey] { return cached }

        // Check negative cache (avoid repeated failed lookups)
        if negativeCacheKeys.contains(cacheKey) { return nil }

        // Resolve TMDB ID → TVDB ID
        guard let tvdbId = await FanArtService.shared.resolveTVDBId(tmdbId: tmdbShowId) else {
            negativeCacheKeys.insert(cacheKey)
            return nil
        }

        // Fetch episode image from TheTVDB
        do {
            let url = try await fetchEpisodeImage(tvdbSeriesId: tvdbId, season: season, episode: episode)
            if let url {
                evictCacheIfNeeded()
                imageCache[cacheKey] = url
            } else {
                negativeCacheKeys.insert(cacheKey)
            }
            return url
        } catch {
            negativeCacheKeys.insert(cacheKey)
            return nil
        }
    }

    // MARK: - Authentication

    private func ensureAuthenticated() async throws {
        if bearerToken != nil { return }
        try await login()
    }

    private func login() async throws {
        let url = URL(string: "\(baseURL)/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["apikey": apiKey]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TheTVDBError.authFailed
        }

        let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
        bearerToken = loginResponse.data.token
    }

    // MARK: - Episode Fetch

    private func fetchEpisodeImage(tvdbSeriesId: Int, season: Int, episode: Int) async throws -> URL? {
        // L2: Supabase shared cache (check before authenticating to save time)
        let supabaseKey = SupabaseCacheService.thetvdbCacheKey(tvdbSeriesId: tvdbSeriesId, season: season, episode: episode)
        if let cachedData = await SupabaseCacheService.shared.get(key: supabaseKey) {
            if let episodeResponse = try? JSONDecoder().decode(EpisodesResponse.self, from: cachedData),
               let ep = episodeResponse.data?.episodes?.first(where: {
                   $0.seasonNumber == season && $0.number == episode
               }), let imagePath = ep.image, !imagePath.isEmpty {
                return URL(string: imagePath)
            }
        }
        
        try await ensureAuthenticated()

        guard let token = bearerToken else { throw TheTVDBError.authFailed }

        var components = URLComponents(string: "\(baseURL)/series/\(tvdbSeriesId)/episodes/default")!
        components.queryItems = [
            URLQueryItem(name: "season", value: "\(season)"),
            URLQueryItem(name: "episodeNumber", value: "\(episode)"),
            URLQueryItem(name: "page", value: "0")
        ]

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        // Handle 401 — token expired, retry once
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            bearerToken = nil
            try await login()
            return try await fetchEpisodeImageRetry(tvdbSeriesId: tvdbSeriesId, season: season, episode: episode)
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        let episodeResponse = try JSONDecoder().decode(EpisodesResponse.self, from: data)

        // Fire-and-forget L2 write
        let capturedData = data
        Task.detached {
            await SupabaseCacheService.shared.set(
                key: supabaseKey,
                source: .thetvdb,
                responseData: capturedData,
                ttlSeconds: SupabaseCacheService.CacheTTL.episodeImages
            )
        }

        // Find the matching episode and extract image URL
        if let ep = episodeResponse.data?.episodes?.first(where: {
            $0.seasonNumber == season && $0.number == episode
        }), let imagePath = ep.image, !imagePath.isEmpty {
            return URL(string: imagePath)
        }

        return nil
    }

    private func fetchEpisodeImageRetry(tvdbSeriesId: Int, season: Int, episode: Int) async throws -> URL? {
        guard let token = bearerToken else { return nil }

        var components = URLComponents(string: "\(baseURL)/series/\(tvdbSeriesId)/episodes/default")!
        components.queryItems = [
            URLQueryItem(name: "season", value: "\(season)"),
            URLQueryItem(name: "episodeNumber", value: "\(episode)"),
            URLQueryItem(name: "page", value: "0")
        ]

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        let episodeResponse = try JSONDecoder().decode(EpisodesResponse.self, from: data)

        if let ep = episodeResponse.data?.episodes?.first(where: {
            $0.seasonNumber == season && $0.number == episode
        }), let imagePath = ep.image, !imagePath.isEmpty {
            return URL(string: imagePath)
        }

        return nil
    }

    // MARK: - Cache Management

    private func evictCacheIfNeeded() {
        if imageCache.count > 500 {
            let keysToRemove = Array(imageCache.keys.prefix(250))
            for key in keysToRemove { imageCache.removeValue(forKey: key) }
        }
        if negativeCacheKeys.count > 1000 {
            negativeCacheKeys.removeAll()
        }
    }

    // MARK: - Response Models

    private struct LoginResponse: Codable {
        let status: String
        let data: TokenData

        struct TokenData: Codable {
            let token: String
        }
    }

    private struct EpisodesResponse: Codable {
        let status: String?
        let data: EpisodesData?

        struct EpisodesData: Codable {
            let episodes: [TVDBEpisode]?
        }
    }

    private struct TVDBEpisode: Codable {
        let id: Int?
        let name: String?
        let number: Int?
        let seasonNumber: Int?
        let image: String?
    }

    private enum TheTVDBError: Error {
        case authFailed
    }
}
