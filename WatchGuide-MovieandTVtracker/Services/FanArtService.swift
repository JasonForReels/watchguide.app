//
//  FanArtService.swift
//  WatchGuide-MovieandTVtracker
//
//  FanArt.tv — primary artwork source for movies & TV shows.
//  TMDB is used as a fallback when FanArt.tv doesn't have the asset.
//

import Foundation

/// Synchronously readable cache of resolved FanArt.tv artwork URLs.
///
/// Views draw on the main thread and cannot await an actor just to pick a URL.
/// This lets a poster use FanArt art it already knows about without paying for a
/// lookup, while views that genuinely want the better artwork resolve it through
/// `FanArtService` and deposit the result here for everyone else.
final class FanArtURLCache: @unchecked Sendable {
    static let shared = FanArtURLCache()

    private let lock = NSLock()
    private var posters: [String: URL] = [:]
    private var backdrops: [String: URL] = [:]

    private init() {}

    private func key(_ tmdbId: Int, _ mediaType: MediaType) -> String {
        "\(mediaType.rawValue)-\(tmdbId)"
    }

    func posterURL(tmdbId: Int, mediaType: MediaType) -> URL? {
        lock.lock(); defer { lock.unlock() }
        return posters[key(tmdbId, mediaType)]
    }

    func setPosterURL(_ url: URL, tmdbId: Int, mediaType: MediaType) {
        lock.lock(); defer { lock.unlock() }
        posters[key(tmdbId, mediaType)] = url
    }

    func backdropURL(tmdbId: Int, mediaType: MediaType) -> URL? {
        lock.lock(); defer { lock.unlock() }
        return backdrops[key(tmdbId, mediaType)]
    }

    func setBackdropURL(_ url: URL, tmdbId: Int, mediaType: MediaType) {
        lock.lock(); defer { lock.unlock() }
        backdrops[key(tmdbId, mediaType)] = url
    }
}

actor FanArtService {
    static let shared = FanArtService()
    
    private let baseURL = "https://webservice.fanart.tv/v3"
    private let apiKey = "1d270eb9c6cff8abfe6c074eebba8d6f"
    
    // MARK: - Caches
    private var artCache: [String: FanArtResponse] = [:]
    /// TMDB ID → TVDB ID resolution cache (for TV shows)
    private var tvdbIdCache: [Int: Int?] = [:]
    
    // Shared session with caching
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 30 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    // MARK: - Raw API: Movie Art (keyed by TMDB ID)
    
    func getMovieArt(tmdbId: Int) async throws -> FanArtResponse {
        let cacheKey = "movie-\(tmdbId)"
        
        // L1: in-memory
        if let cached = artCache[cacheKey] { return cached }
        
        // L2: Supabase shared cache
        let supabaseKey = SupabaseCacheService.fanartCacheKey(mediaType: "movie", id: tmdbId)
        if let cachedData = await SupabaseCacheService.shared.get(key: supabaseKey) {
            if let result = try? JSONDecoder().decode(FanArtResponse.self, from: cachedData) {
                artCache[cacheKey] = result
                evictCacheIfNeeded()
                return result
            }
        }
        
        let url = URL(string: "\(baseURL)/movies/\(tmdbId)?api_key=\(apiKey)")!
        let (data, response) = try await session.data(from: url)
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw FanArtError.notFound
        }
        
        let result = try JSONDecoder().decode(FanArtResponse.self, from: data)
        artCache[cacheKey] = result
        evictCacheIfNeeded()
        
        // Fire-and-forget L2 write
        let capturedData = data
        Task.detached {
            await SupabaseCacheService.shared.set(
                key: supabaseKey,
                source: .fanart,
                responseData: capturedData,
                ttlSeconds: SupabaseCacheService.CacheTTL.artwork
            )
        }
        
        return result
    }
    
    // MARK: - Raw API: TV Art (keyed by TVDB ID)
    
    func getTVArt(tvdbId: Int) async throws -> FanArtResponse {
        let cacheKey = "tv-\(tvdbId)"
        
        // L1: in-memory
        if let cached = artCache[cacheKey] { return cached }
        
        // L2: Supabase shared cache
        let supabaseKey = SupabaseCacheService.fanartCacheKey(mediaType: "tv", id: tvdbId)
        if let cachedData = await SupabaseCacheService.shared.get(key: supabaseKey) {
            if let result = try? JSONDecoder().decode(FanArtResponse.self, from: cachedData) {
                artCache[cacheKey] = result
                evictCacheIfNeeded()
                return result
            }
        }
        
        let url = URL(string: "\(baseURL)/tv/\(tvdbId)?api_key=\(apiKey)")!
        let (data, response) = try await session.data(from: url)
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw FanArtError.notFound
        }
        
        let result = try JSONDecoder().decode(FanArtResponse.self, from: data)
        artCache[cacheKey] = result
        evictCacheIfNeeded()
        
        // Fire-and-forget L2 write
        let capturedData = data
        Task.detached {
            await SupabaseCacheService.shared.set(
                key: supabaseKey,
                source: .fanart,
                responseData: capturedData,
                ttlSeconds: SupabaseCacheService.CacheTTL.artwork
            )
        }
        
        return result
    }
    
    // MARK: - TVDB ID Resolution
    
    /// Resolve a TMDB TV show ID to a TVDB ID using TMDB's external_ids endpoint.
    func resolveTVDBId(tmdbId: Int) async -> Int? {
        if let cached = tvdbIdCache[tmdbId] { return cached }
        
        do {
            let details = try await TMDBService.shared.getTVShowDetails(id: tmdbId)
            let tvdbId = details.externalIds?.tvdbId
            tvdbIdCache[tmdbId] = tvdbId
            return tvdbId
        } catch {
            tvdbIdCache[tmdbId] = nil
            return nil
        }
    }
    
    /// Store a known TVDB ID so we skip the resolution request.
    func cacheTVDBId(tmdbId: Int, tvdbId: Int) {
        tvdbIdCache[tmdbId] = tvdbId
    }
    
    // MARK: - High-Level: Get Art for any media (handles TV→TVDB resolution)
    
    /// Fetches FanArtResponse for any media type. Returns nil if unavailable.
    func getArt(tmdbId: Int, mediaType: MediaType) async -> FanArtResponse? {
        do {
            if mediaType == .movie {
                return try await getMovieArt(tmdbId: tmdbId)
            } else if mediaType == .tv {
                guard let tvdbId = await resolveTVDBId(tmdbId: tmdbId) else { return nil }
                return try await getTVArt(tvdbId: tvdbId)
            }
        } catch {
            // Silently fail — caller will use TMDB fallback
        }
        return nil
    }
    
    // MARK: - Best Poster URL
    
    func getBestPosterURL(tmdbId: Int, mediaType: MediaType) async -> URL? {
        if let known = FanArtURLCache.shared.posterURL(tmdbId: tmdbId, mediaType: mediaType) {
            return known
        }
        guard let art = await getArt(tmdbId: tmdbId, mediaType: mediaType) else { return nil }

        // Only return actual poster artwork (portrait). Do NOT fall back to
        // thumbs, which are landscape and display incorrectly in poster frames.
        let image = mediaType == .movie
            ? bestEnglishImage(art.movieposter)
            : bestEnglishImage(art.tvposter)

        guard let image, let url = URL(string: image.url) else { return nil }
        // Publish it so views can pick it up synchronously from now on.
        FanArtURLCache.shared.setPosterURL(url, tmdbId: tmdbId, mediaType: mediaType)
        return url
    }
    
    // MARK: - Best Backdrop URL
    
    func getBestBackdropURL(tmdbId: Int, mediaType: MediaType) async -> URL? {
        if let known = FanArtURLCache.shared.backdropURL(tmdbId: tmdbId, mediaType: mediaType) {
            return known
        }
        guard let art = await getArt(tmdbId: tmdbId, mediaType: mediaType) else { return nil }

        let image = mediaType == .movie
            ? bestEnglishImage(art.moviebackground)
            : bestEnglishImage(art.showbackground)

        guard let image, let url = URL(string: image.url) else { return nil }
        FanArtURLCache.shared.setBackdropURL(url, tmdbId: tmdbId, mediaType: mediaType)
        return url
    }
    
    // MARK: - Best Logo URL (HD preferred)
    
    func getBestLogoURL(tmdbId: Int, mediaType: MediaType) async -> URL? {
        guard let art = await getArt(tmdbId: tmdbId, mediaType: mediaType) else { return nil }
        
        if mediaType == .movie {
            // Prefer HD logo, then standard logo
            if let img = bestEnglishImage(art.hdmovielogo) { return URL(string: img.url) }
            if let img = bestEnglishImage(art.movielogo) { return URL(string: img.url) }
        } else {
            if let img = bestEnglishImage(art.hdtvlogo) { return URL(string: img.url) }
            if let img = bestEnglishImage(art.clearlogo) { return URL(string: img.url) }
        }
        return nil
    }
    
    // MARK: - Best Clear Art URL
    
    func getBestClearArtURL(tmdbId: Int, mediaType: MediaType) async -> URL? {
        guard let art = await getArt(tmdbId: tmdbId, mediaType: mediaType) else { return nil }
        
        if mediaType == .movie {
            if let img = bestEnglishImage(art.hdmovieclearart) { return URL(string: img.url) }
        } else {
            if let img = bestEnglishImage(art.hdclearart) { return URL(string: img.url) }
            if let img = bestEnglishImage(art.characterart) { return URL(string: img.url) }
        }
        return nil
    }
    
    // MARK: - Best Character Art URL

    /// Alpha-channel subject art, used as the parallax cutout layer of the
    /// cinematic hero stage. Character art is preferred over clear art because
    /// clear art normally has the title lettering composited in, which would
    /// duplicate the hero's own logo layer.
    func getBestCharacterArtURL(tmdbId: Int, mediaType: MediaType) async -> URL? {
        guard let art = await getArt(tmdbId: tmdbId, mediaType: mediaType) else { return nil }

        // Character art only. Clear art has the title logo baked in, which put a
        // second copy of the title in the middle of the hero next to its own
        // treatment.
        if let img = bestEnglishImage(art.characterart) { return URL(string: img.url) }
        return nil
    }

    // MARK: - Best Banner URL
    
    func getBestBannerURL(tmdbId: Int, mediaType: MediaType) async -> URL? {
        guard let art = await getArt(tmdbId: tmdbId, mediaType: mediaType) else { return nil }
        
        if mediaType == .movie {
            if let img = bestEnglishImage(art.moviebanner) { return URL(string: img.url) }
        } else {
            if let img = bestEnglishImage(art.tvbanner) { return URL(string: img.url) }
        }
        return nil
    }
    
    // MARK: - Best Thumb URL
    
    func getBestThumbURL(tmdbId: Int, mediaType: MediaType) async -> URL? {
        guard let art = await getArt(tmdbId: tmdbId, mediaType: mediaType) else { return nil }
        
        if mediaType == .movie {
            if let img = bestEnglishImage(art.moviethumb) { return URL(string: img.url) }
        } else {
            if let img = bestEnglishImage(art.tvthumb) { return URL(string: img.url) }
        }
        return nil
    }
    
    // MARK: - Helpers
    
    /// Pick the best English image (or any language) sorted by likes
    private func bestEnglishImage(_ images: [FanArtImage]?) -> FanArtImage? {
        guard let images = images, !images.isEmpty else { return nil }
        
        // Prefer English or textless ("00"), sorted by likes descending
        let preferred = images
            .filter { $0.lang == "en" || $0.lang == "00" || $0.lang == nil || $0.lang == "" }
            .sorted { (Int($0.likes ?? "0") ?? 0) > (Int($1.likes ?? "0") ?? 0) }
        
        return preferred.first ?? images.first
    }
    
    /// Keep cache from growing unbounded
    private func evictCacheIfNeeded() {
        if artCache.count > 500 {
            // Remove half the entries arbitrarily
            let keysToRemove = Array(artCache.keys.prefix(250))
            for key in keysToRemove { artCache.removeValue(forKey: key) }
        }
    }
}

// MARK: - FanArt Response Models

struct FanArtResponse: Codable {
    let name: String?
    let tmdbId: String?
    let imdbId: String?
    
    // Movie art types
    let movieposter: [FanArtImage]?
    let moviebackground: [FanArtImage]?
    let moviethumb: [FanArtImage]?
    let movielogo: [FanArtImage]?
    let moviedisc: [FanArtImage]?
    let moviebanner: [FanArtImage]?
    let hdmovielogo: [FanArtImage]?
    let hdmovieclearart: [FanArtImage]?
    
    // TV art types
    let tvposter: [FanArtImage]?
    let showbackground: [FanArtImage]?
    let tvthumb: [FanArtImage]?
    let hdtvlogo: [FanArtImage]?
    let clearlogo: [FanArtImage]?
    let characterart: [FanArtImage]?
    let tvbanner: [FanArtImage]?
    let hdclearart: [FanArtImage]?
    let seasonposter: [FanArtImage]?
    let seasonthumb: [FanArtImage]?
    let seasonbanner: [FanArtImage]?
    
    enum CodingKeys: String, CodingKey {
        case name
        case tmdbId = "tmdb_id"
        case imdbId = "imdb_id"
        case movieposter, moviebackground, moviethumb, movielogo, moviedisc, moviebanner
        case hdmovielogo, hdmovieclearart
        case tvposter, showbackground, tvthumb, hdtvlogo, clearlogo, characterart
        case tvbanner, hdclearart, seasonposter, seasonthumb, seasonbanner
    }
}

struct FanArtImage: Codable {
    let id: String
    let url: String
    let lang: String?
    let likes: String?
}

// MARK: - Errors

enum FanArtError: LocalizedError {
    case notFound
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Artwork not found on FanArt.tv"
        case .networkError:
            return "Network error reaching FanArt.tv"
        }
    }
}
