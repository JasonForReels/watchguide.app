//
//  TMDBService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

actor TMDBService {
    static let shared = TMDBService()
    
    private let baseURL = "https://api.themoviedb.org/3"
    private let imageBaseURL = "https://image.tmdb.org/t/p"
    
    private let apiKey = "53b0ac93f3955b6a6ccb9782752fecf1"
    
    // MARK: - Optimized URLSession with caching
    private nonisolated let session: URLSession = {
        let config = URLSessionConfiguration.default
        // 50 MB memory cache, 200 MB disk cache
        config.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 8
        // Fail fast when the simulator/device is offline instead of appearing to hang.
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
    
    // MARK: - In-memory response cache
    private var responseCache: [String: (data: Any, timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    
    private func getCached<T>(_ key: String) -> T? {
        guard let entry = responseCache[key],
              Date().timeIntervalSince(entry.timestamp) < cacheTTL,
              let value = entry.data as? T else { return nil }
        return value
    }
    
    private func setCache<T>(_ key: String, value: T) {
        // Evict old entries if cache grows too large
        if responseCache.count > 500 {
            let cutoff = Date().addingTimeInterval(-cacheTTL)
            responseCache = responseCache.filter { $0.value.timestamp > cutoff }
        }
        responseCache[key] = (data: value, timestamp: Date())
    }
    
    private init() {}
    
    // MARK: - Image URL Builder
    enum ImageSize: String {
        case small = "w185"
        case medium = "w342"
        case large = "w500"
        case original = "original"
        case backdrop = "w1280"
        case backdropSmall = "w780"
        case profile = "h632"
        case logo = "w300"
    }
    
    nonisolated func imageURL(path: String?, size: ImageSize = .medium) -> URL? {
        guard let path = path else { return nil }
        return URL(string: "\(imageBaseURL)/\(size.rawValue)\(path)")
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    nonisolated func date(from string: String) -> Date? {
        return Self.dateFormatter.date(from: string)
    }
    
    // MARK: - Generic Request (with L1 in-memory + L2 Supabase caching)
    private func request<T: Decodable>(_ endpoint: String, queryItems: [URLQueryItem] = [], useCache: Bool = true) async throws -> T {
        var components = URLComponents(string: "\(baseURL)\(endpoint)")!
        var items = queryItems
        items.append(URLQueryItem(name: "api_key", value: apiKey))
        components.queryItems = items
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        let cacheKey = url.absoluteString

        // L1: Check in-memory cache first
        if useCache, let cached: T = getCached(cacheKey) {
            return cached
        }

        let supabaseKey = useCache
            ? SupabaseCacheService.tmdbCacheKey(endpoint: endpoint, queryItems: queryItems)
            : nil

        // L2 (Supabase) and TMDB itself are raced rather than tried in sequence.
        // Checking Supabase first meant every cold request paid a full extra
        // round-trip before TMDB was even contacted, which on a screen that
        // issues a dozen requests dominated the load time.
        let (data, fromOrigin) = try await fetchData(url: url, supabaseKey: supabaseKey)

        let result = try JSONDecoder().decode(T.self, from: data)

        // Store in L1 in-memory cache
        if useCache {
            setCache(cacheKey, value: result)
        }

        // Fire-and-forget: write to L2 Supabase cache. Only origin responses are
        // worth writing back — an L2 hit is already there.
        if useCache, fromOrigin, let supabaseKey {
            let ttl = SupabaseCacheService.tmdbTTL(for: endpoint)
            let capturedData = data
            Task.detached(priority: .background) {
                await SupabaseCacheService.shared.set(
                    key: supabaseKey,
                    source: .tmdb,
                    responseData: capturedData,
                    ttlSeconds: ttl
                )
            }
        }

        return result
    }

    /// Returns the first usable response from the shared Supabase cache or TMDB,
    /// whichever answers first. `fromOrigin` reports which one won.
    private func fetchData(url: URL, supabaseKey: String?) async throws -> (data: Data, fromOrigin: Bool) {
        guard let supabaseKey else {
            return (try await originData(url: url), true)
        }

        return try await withThrowingTaskGroup(of: (Data, Bool)?.self) { group in
            group.addTask {
                guard let cached = await SupabaseCacheService.shared.get(key: supabaseKey) else {
                    return nil
                }
                return (cached, false)
            }
            group.addTask { [self] in
                (try await originData(url: url), true)
            }

            var originError: Error?

            // Two children: a nil result is a cache miss, so keep waiting for the
            // other one rather than giving up.
            for _ in 0..<2 {
                do {
                    if let result = try await group.next() ?? nil {
                        group.cancelAll()
                        return result
                    }
                } catch {
                    originError = error
                }
            }

            throw originError ?? URLError(.badServerResponse)
        }
    }

    /// Fetches straight from TMDB. `nonisolated` so racing requests don't
    /// serialize on the actor while they wait on the network.
    private nonisolated func originData(url: URL) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            print("TMDBService request failed: \(url.absoluteString) error=\(error)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("TMDBService invalid response: \(url.absoluteString)")
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            print("TMDBService bad status: \(httpResponse.statusCode) url=\(url.absoluteString)")
            throw URLError(.badServerResponse)
        }

        return data
    }
    
    // MARK: - Trending
    func getTrending(mediaType: MediaType, timeWindow: String = "week", page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let endpoint = "/trending/\(mediaType.rawValue)/\(timeWindow)"
        let response: TMDBResponse<MediaItem> = try await request(endpoint, queryItems: [URLQueryItem(name: "page", value: "\(page)")])
        
        // Ensure mediaType is set correctly for items that might be missing it
        let updatedResults = response.results.map { item -> MediaItem in
            if item.mediaType == nil {
                return MediaItem(
                    id: item.id,
                    title: item.title,
                    name: item.name,
                    originalTitle: item.originalTitle,
                    originalName: item.originalName,
                    overview: item.overview,
                    posterPath: item.posterPath,
                    backdropPath: item.backdropPath,
                    releaseDate: item.releaseDate,
                    firstAirDate: item.firstAirDate,
                    voteAverage: item.voteAverage,
                    voteCount: item.voteCount,
                    popularity: item.popularity,
                    genreIds: item.genreIds,
                    mediaType: mediaType.rawValue,
                    adult: item.adult,
                    originalLanguage: item.originalLanguage
                )
            }
            return item
        }
        
        return TMDBResponse(
            page: response.page,
            results: updatedResults,
            totalPages: response.totalPages,
            totalResults: response.totalResults
        )
    }

    func getTrendingPeople(timeWindow: String = "week", page: Int = 1) async throws -> TMDBResponse<Person> {
        let endpoint = "/trending/person/\(timeWindow)"
        let response: TMDBResponse<Person> = try await request(endpoint, queryItems: [URLQueryItem(name: "page", value: "\(page)")])
        return response
    }

    // MARK: - Media Images (Logos)
    func getMediaLogos(mediaType: MediaType, id: Int) async throws -> [MediaImage] {
        let endpoint: String
        switch mediaType {
        case .movie:
            endpoint = "/movie/\(id)/images"
        case .tv:
            endpoint = "/tv/\(id)/images"
        case .person:
            return []
        }
        
        let response: MediaImagesResponse = try await request(
            endpoint,
            queryItems: [
                URLQueryItem(name: "include_image_language", value: "en,null")
            ]
        )
        return response.logos
    }

    /// Fetches English-language backdrops for a movie or TV show, sorted by vote average.
    func getMediaBackdrops(mediaType: MediaType, id: Int) async throws -> [MediaImage] {
        let endpoint: String
        switch mediaType {
        case .movie:
            endpoint = "/movie/\(id)/images"
        case .tv:
            endpoint = "/tv/\(id)/images"
        case .person:
            return []
        }

        let response: MediaImagesResponse = try await request(
            endpoint,
            queryItems: [
                URLQueryItem(name: "include_image_language", value: "en,null")
            ]
        )
        let backdrops = response.backdrops ?? []
        // Prefer English (text-baked) backdrops over null (textless), then sort by votes within each group
        return backdrops.sorted { a, b in
            let aIsEnglish = a.iso639_1 == "en"
            let bIsEnglish = b.iso639_1 == "en"
            if aIsEnglish != bIsEnglish { return aIsEnglish }
            return (a.voteAverage ?? 0) > (b.voteAverage ?? 0)
        }
    }
    
    // MARK: - Movies
    func getPopularMovies(page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        try await request("/movie/popular", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    func getTopRatedMovies(page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        try await request("/movie/top_rated", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    func getNowPlayingMovies(page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        try await request("/movie/now_playing", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    func getUpcomingMovies(page: Int = 1, endDate: String? = nil) async throws -> TMDBResponse<MediaItem> {
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // Start from tomorrow to exclude today's releases
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let tomorrowString = formatter.string(from: tomorrow)
        
        // Default to end of current year
        let endDateString = endDate ?? "\(Calendar.current.component(.year, from: today))-12-31"
        
        let region = await MainActor.run { StorageService.shared.settings.region }
        
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "primary_release_date.gte", value: tomorrowString),
            URLQueryItem(name: "primary_release_date.lte", value: endDateString),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "region", value: region),
            URLQueryItem(name: "vote_count.gte", value: "0")
        ]
        
        let result: TMDBResponse<MediaItem> = try await request("/discover/movie", queryItems: queryItems)
        
        if result.results.isEmpty {
            let fallbackItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "primary_release_date.gte", value: tomorrowString),
                URLQueryItem(name: "primary_release_date.lte", value: endDateString),
                URLQueryItem(name: "sort_by", value: "popularity.desc")
            ]
            return try await request("/discover/movie", queryItems: fallbackItems, useCache: false)
        }
        
        return result
    }
    
    func getUpcomingTV(page: Int = 1, endDate: String? = nil) async throws -> TMDBResponse<MediaItem> {
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let tomorrowString = formatter.string(from: tomorrow)
        
        let endDateString = endDate ?? {
            let year = Calendar.current.component(.year, from: today)
            return "\(year)-12-31"
        }()
        
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "first_air_date.gte", value: tomorrowString),
            URLQueryItem(name: "first_air_date.lte", value: endDateString),
            URLQueryItem(name: "sort_by", value: "popularity.desc")
        ]
        
        return try await request("/discover/tv", queryItems: queryItems)
    }
    
    /// Fetch on-the-air TV shows that have a next episode airing (for countdown)
    func getOnTheAirTVForCountdown(page: Int = 1, endDate: String? = nil) async throws -> TMDBResponse<MediaItem> {
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)
        
        let endDateString = endDate ?? {
            let year = Calendar.current.component(.year, from: today)
            return "\(year)-12-31"
        }()
        
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "air_date.gte", value: todayString),
            URLQueryItem(name: "air_date.lte", value: endDateString),
            URLQueryItem(name: "sort_by", value: "popularity.desc")
        ]
        
        return try await request("/discover/tv", queryItems: queryItems)
    }
    
    func getMovieDetails(id: Int) async throws -> MovieDetails {
        try await request("/movie/\(id)")
    }

    func getMovieReleaseDates(id: Int) async throws -> MovieReleaseDatesResponse {
        try await request("/movie/\(id)/release_dates")
    }
    
    func getMovieCredits(id: Int) async throws -> Credits {
        try await request("/movie/\(id)/credits")
    }
    
    func getMovieVideos(id: Int) async throws -> VideosResponse {
        try await request("/movie/\(id)/videos")
    }

    func getMovieReviews(id: Int, page: Int = 1) async throws -> ReviewsResponse {
        try await request("/movie/\(id)/reviews", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    func getMovieWatchProviders(id: Int) async throws -> WatchProvidersResponse {
        try await request("/movie/\(id)/watch/providers")
    }
    
    func getSimilarMovies(id: Int, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        try await request("/movie/\(id)/similar", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    func getMovieRecommendations(id: Int, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        try await request("/movie/\(id)/recommendations", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    // MARK: - TV Shows
    func getPopularTV(page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        try await request("/tv/popular", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    func getTopRatedTV(page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        try await request("/tv/top_rated", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    func getAiringTodayTV(page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        try await request("/tv/airing_today", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    func getOnTheAirTV(page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        try await request("/tv/on_the_air", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    func getTVShowDetails(id: Int) async throws -> TVShowDetails {
        var queryItems = [URLQueryItem]()
        queryItems.append(URLQueryItem(name: "append_to_response", value: "external_ids"))
        return try await request("/tv/\(id)", queryItems: queryItems)
    }

    func getTVContentRatings(id: Int) async throws -> TVContentRatingsResponse {
        try await request("/tv/\(id)/content_ratings")
    }
    
    func getTVShowCredits(id: Int) async throws -> Credits {
        try await request("/tv/\(id)/credits")
    }
    
    func getTVShowVideos(id: Int) async throws -> VideosResponse {
        try await request("/tv/\(id)/videos")
    }

    func getTVShowReviews(id: Int, page: Int = 1) async throws -> ReviewsResponse {
        try await request("/tv/\(id)/reviews", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    func getTVShowWatchProviders(id: Int) async throws -> WatchProvidersResponse {
        try await request("/tv/\(id)/watch/providers")
    }
    
    func getSimilarTVShows(id: Int, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        try await request("/tv/\(id)/similar", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    func getTVShowRecommendations(id: Int, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        try await request("/tv/\(id)/recommendations", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    func getSeasonDetails(tvId: Int, seasonNumber: Int) async throws -> SeasonDetails {
        try await request("/tv/\(tvId)/season/\(seasonNumber)")
    }
    
    /// Lightweight TV details that includes next_episode_to_air for countdown purposes
    func getTVShowNextEpisode(id: Int) async throws -> TVShowAiringInfo {
        try await request("/tv/\(id)", queryItems: [])
    }
    
    // MARK: - Adult Content Setting Helper
    /// Reads the "Include Adult Content" toggle from Settings on the main actor.
    private func includeAdultValue() async -> String {
        let include = await MainActor.run { StorageService.shared.settings.includeAdult }
        return include ? "true" : "false"
    }
    
    // MARK: - Search
    func searchMulti(query: String, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let adult = await includeAdultValue()
        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: adult)
        ]
        return try await request("/search/multi", queryItems: queryItems)
    }
    
    func searchMovies(query: String, year: Int? = nil, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let adult = await includeAdultValue()
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: adult)
        ]
        if let year = year {
            queryItems.append(URLQueryItem(name: "year", value: "\(year)"))
        }
        return try await request("/search/movie", queryItems: queryItems)
    }
    
    func searchTV(query: String, year: Int? = nil, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let adult = await includeAdultValue()
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: adult)
        ]
        if let year = year {
            queryItems.append(URLQueryItem(name: "first_air_date_year", value: "\(year)"))
        }
        return try await request("/search/tv", queryItems: queryItems)
    }
    
    func searchPerson(query: String, page: Int = 1) async throws -> TMDBResponse<Person> {
        let adult = await includeAdultValue()
        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: adult)
        ]
        return try await request("/search/person", queryItems: queryItems)
    }

    func searchCompanies(query: String, page: Int = 1) async throws -> TMDBResponse<Company> {
        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        return try await request("/search/company", queryItems: queryItems)
    }
    
    // MARK: - Discover

    /// Joins TMDB filter IDs. TMDB reads `,` as AND and `|` as OR within a single
    /// `with_*` parameter, so `matchAny` picks the separator.
    private func joinFilterIds(_ ids: [Int], matchAny: Bool) -> String {
        ids.map { "\($0)" }.joined(separator: matchAny ? "|" : ",")
    }

    func discoverMovies(
        genres: [Int]? = nil,
        year: Int? = nil,
        originalLanguage: String? = nil,
        productionRegion: String? = nil,
        keywords: [Int]? = nil,
        matchAnyGenre: Bool = false,
        matchAnyKeyword: Bool = true,
        releasedBefore: Int? = nil,
        sortBy: String = "popularity.desc",
        page: Int = 1
    ) async throws -> TMDBResponse<MediaItem> {
        let adult = await includeAdultValue()
        var queryItems = [
            URLQueryItem(name: "sort_by", value: sortBy),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: adult)
        ]
        if let genres = genres, !genres.isEmpty {
            queryItems.append(URLQueryItem(name: "with_genres", value: joinFilterIds(genres, matchAny: matchAnyGenre)))
        }
        if let keywords = keywords, !keywords.isEmpty {
            queryItems.append(URLQueryItem(name: "with_keywords", value: joinFilterIds(keywords, matchAny: matchAnyKeyword)))
        }
        if let year = year {
            queryItems.append(URLQueryItem(name: "primary_release_year", value: "\(year)"))
        }
        if let releasedBefore = releasedBefore {
            queryItems.append(URLQueryItem(name: "primary_release_date.lte", value: "\(releasedBefore)-12-31"))
        }
        if let originalLanguage = originalLanguage, !originalLanguage.isEmpty {
            queryItems.append(URLQueryItem(name: "with_original_language", value: originalLanguage))
        }
        if let productionRegion = productionRegion, !productionRegion.isEmpty {
            queryItems.append(URLQueryItem(name: "with_origin_country", value: productionRegion))
        }
        return try await request("/discover/movie", queryItems: queryItems)
    }
    
    func discoverTV(
        genres: [Int]? = nil,
        year: Int? = nil,
        originalLanguage: String? = nil,
        productionRegion: String? = nil,
        keywords: [Int]? = nil,
        matchAnyGenre: Bool = false,
        matchAnyKeyword: Bool = true,
        releasedBefore: Int? = nil,
        sortBy: String = "popularity.desc",
        page: Int = 1
    ) async throws -> TMDBResponse<MediaItem> {
        let adult = await includeAdultValue()
        var queryItems = [
            URLQueryItem(name: "sort_by", value: sortBy),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: adult)
        ]
        if let genres = genres, !genres.isEmpty {
            queryItems.append(URLQueryItem(name: "with_genres", value: joinFilterIds(genres, matchAny: matchAnyGenre)))
        }
        if let keywords = keywords, !keywords.isEmpty {
            queryItems.append(URLQueryItem(name: "with_keywords", value: joinFilterIds(keywords, matchAny: matchAnyKeyword)))
        }
        if let year = year {
            queryItems.append(URLQueryItem(name: "first_air_date_year", value: "\(year)"))
        }
        if let releasedBefore = releasedBefore {
            queryItems.append(URLQueryItem(name: "first_air_date.lte", value: "\(releasedBefore)-12-31"))
        }
        if let originalLanguage = originalLanguage, !originalLanguage.isEmpty {
            queryItems.append(URLQueryItem(name: "with_original_language", value: originalLanguage))
        }
        if let productionRegion = productionRegion, !productionRegion.isEmpty {
            queryItems.append(URLQueryItem(name: "with_origin_country", value: productionRegion))
        }
        return try await request("/discover/tv", queryItems: queryItems)
    }

    func getLatestHighRatedMovies(
        minimumVoteAverage: Double = 6.0,
        minimumVoteCount: Int = 50,
        page: Int = 1
    ) async throws -> TMDBResponse<MediaItem> {
        let adult = await includeAdultValue()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())

        let queryItems = [
            URLQueryItem(name: "sort_by", value: "primary_release_date.desc"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: adult),
            URLQueryItem(name: "vote_average.gte", value: String(format: "%.1f", minimumVoteAverage)),
            URLQueryItem(name: "vote_count.gte", value: "\(minimumVoteCount)"),
            URLQueryItem(name: "primary_release_date.lte", value: todayString)
        ]

        let response: TMDBResponse<MediaItem> = try await request("/discover/movie", queryItems: queryItems)
        return normalizedResponse(response, mediaType: .movie)
    }

    func getLatestHighRatedTV(
        minimumVoteAverage: Double = 6.0,
        minimumVoteCount: Int = 50,
        page: Int = 1
    ) async throws -> TMDBResponse<MediaItem> {
        let adult = await includeAdultValue()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())

        let queryItems = [
            URLQueryItem(name: "sort_by", value: "first_air_date.desc"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: adult),
            URLQueryItem(name: "vote_average.gte", value: String(format: "%.1f", minimumVoteAverage)),
            URLQueryItem(name: "vote_count.gte", value: "\(minimumVoteCount)"),
            URLQueryItem(name: "first_air_date.lte", value: todayString)
        ]

        let response: TMDBResponse<MediaItem> = try await request("/discover/tv", queryItems: queryItems)
        return normalizedResponse(response, mediaType: .tv)
    }

    private func normalizedResponse(_ response: TMDBResponse<MediaItem>, mediaType: MediaType) -> TMDBResponse<MediaItem> {
        let updatedResults = response.results.map { item -> MediaItem in
            guard item.mediaType == nil else { return item }

            return MediaItem(
                id: item.id,
                title: item.title,
                name: item.name,
                originalTitle: item.originalTitle,
                originalName: item.originalName,
                overview: item.overview,
                posterPath: item.posterPath,
                backdropPath: item.backdropPath,
                releaseDate: item.releaseDate,
                firstAirDate: item.firstAirDate,
                voteAverage: item.voteAverage,
                voteCount: item.voteCount,
                popularity: item.popularity,
                genreIds: item.genreIds,
                mediaType: mediaType.rawValue,
                adult: item.adult,
                originalLanguage: item.originalLanguage
            )
        }

        return TMDBResponse(
            page: response.page,
            results: updatedResults,
            totalPages: response.totalPages,
            totalResults: response.totalResults
        )
    }
    
    func discoverMoviesByCompany(
        companyIds: [Int],
        sortBy: String = "popularity.desc",
        page: Int = 1
    ) async throws -> TMDBResponse<MediaItem> {
        let adult = await includeAdultValue()
        let queryItems = [
            URLQueryItem(name: "with_companies", value: companyIds.map { "\($0)" }.joined(separator: "|")),
            URLQueryItem(name: "sort_by", value: sortBy),
            URLQueryItem(name: "include_adult", value: adult),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        return try await request("/discover/movie", queryItems: queryItems)
    }
    
    func discoverTVByNetwork(networkIds: [Int], providerIds: [Int] = [], region: String? = nil, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        var queryItems = [
            URLQueryItem(name: "with_networks", value: networkIds.map { "\($0)" }.joined(separator: "|")),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        if !providerIds.isEmpty, let region = region {
            let effectiveRegion = Self.effectiveProviderRegion(region: region, providerIds: providerIds)
            queryItems.append(URLQueryItem(name: "with_watch_providers", value: providerIds.map { "\($0)" }.joined(separator: "|")))
            queryItems.append(URLQueryItem(name: "watch_region", value: effectiveRegion))
        }
        return try await request("/discover/tv", queryItems: queryItems)
    }
    
    func discoverTVByCompany(companyIds: [Int], page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let queryItems = [
            URLQueryItem(name: "with_companies", value: companyIds.map { "\($0)" }.joined(separator: "|")),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        return try await request("/discover/tv", queryItems: queryItems)
    }
    
    // MARK: - Kids / Family Content Discovery
    
    /// Discover family-friendly movies suitable for kids profiles (13 and under).
    /// Uses certification filters (G, PG) and the Animation (16) / Family (10751) genres.
    func discoverKidsMovies(page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let region = await MainActor.run { StorageService.shared.settings.region }
        let certRegion = ["US", "CA", "GB", "AU", "NZ", "DE", "FR"].contains(region) ? region : "US"
        let queryItems = [
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "with_genres", value: "16|10751"),  // Animation OR Family
            URLQueryItem(name: "certification_country", value: certRegion),
            URLQueryItem(name: "certification.lte", value: "PG"),
            URLQueryItem(name: "vote_count.gte", value: "50")
        ]
        return try await request("/discover/movie", queryItems: queryItems)
    }
    
    /// Discover family-friendly TV shows suitable for kids profiles (13 and under).
    /// Uses the Animation (16) / Family (10751) / Kids (10762) genres.
    func discoverKidsTV(page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let queryItems = [
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "with_genres", value: "16|10751|10762"),  // Animation OR Family OR Kids
            URLQueryItem(name: "vote_count.gte", value: "20")
        ]
        return try await request("/discover/tv", queryItems: queryItems)
    }
    
    // MARK: - Discover by Watch Provider
    func discoverMoviesWithProvider(providerIds: [Int], region: String, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let effectiveRegion = Self.effectiveProviderRegion(region: region, providerIds: providerIds)
        let queryItems = [
            URLQueryItem(name: "with_watch_providers", value: providerIds.map { "\($0)" }.joined(separator: "|")),
            URLQueryItem(name: "watch_region", value: effectiveRegion),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        return try await request("/discover/movie", queryItems: queryItems)
    }
    
    func discoverTVWithProvider(providerIds: [Int], region: String, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let effectiveRegion = Self.effectiveProviderRegion(region: region, providerIds: providerIds)
        let queryItems = [
            URLQueryItem(name: "with_watch_providers", value: providerIds.map { "\($0)" }.joined(separator: "|")),
            URLQueryItem(name: "watch_region", value: effectiveRegion),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        return try await request("/discover/tv", queryItems: queryItems)
    }
    
    /// Maps Disney+ South Africa requests to use UK content, since Disney+ ZA mirrors GB.
    static func effectiveProviderRegion(region: String, providerIds: [Int]) -> String {
        let disneyPlusProviderId = 337
        if region == "ZA", providerIds.contains(disneyPlusProviderId) {
            return "GB"
        }
        return region
    }
    
    // MARK: - Collections
    func getCollectionDetails(id: Int) async throws -> CollectionDetails {
        try await request("/collection/\(id)")
    }
    
    // MARK: - TMDB Lists (v4-style via v3 wrapper)
    func getListDetails(listId: Int, page: Int = 1) async throws -> TMDBListResponse {
        try await request("/list/\(listId)", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }
    
    // MARK: - Genres
    func getMovieGenres() async throws -> GenresResponse {
        try await request("/genre/movie/list")
    }
    
    func getTVGenres() async throws -> GenresResponse {
        try await request("/genre/tv/list")
    }

    // MARK: - Keywords

    func getMovieKeywords(id: Int) async throws -> KeywordsResponse {
        try await request("/movie/\(id)/keywords")
    }

    func getTVKeywords(id: Int) async throws -> KeywordsResponse {
        try await request("/tv/\(id)/keywords")
    }

    /// Keywords for a title regardless of media type. Returns an empty list for
    /// people, and never throws — callers treat keywords as optional enrichment.
    func getKeywords(id: Int, mediaType: MediaType) async -> [Keyword] {
        do {
            switch mediaType {
            case .movie: return try await getMovieKeywords(id: id).keywords
            case .tv:    return try await getTVKeywords(id: id).keywords
            case .person: return []
            }
        } catch {
            return []
        }
    }
    
    // MARK: - Companies
    func getCompanyDetails(id: Int) async throws -> Company {
        try await request("/company/\(id)")
    }
    
    // MARK: - Person Details
    func getPersonDetails(id: Int) async throws -> Person {
        try await request("/person/\(id)")
    }
    
    func getPersonMovieCredits(id: Int) async throws -> PersonCreditsResponse {
        try await request("/person/\(id)/movie_credits")
    }
    
    func getPersonTVCredits(id: Int) async throws -> PersonCreditsResponse {
        try await request("/person/\(id)/tv_credits")
    }

    // MARK: - Certifications
    func getMovieCertification(id: Int) async throws -> String? {
        let response = try await getMovieReleaseDates(id: id)
        let region = await MainActor.run { StorageService.shared.settings.region }
        return TMDBService.pickMovieCertification(from: response, region: region)
    }

    func getTVCertification(id: Int) async throws -> String? {
        let response = try await getTVContentRatings(id: id)
        let region = await MainActor.run { StorageService.shared.settings.region }
        return TMDBService.pickTVCertification(from: response, region: region)
    }

    private static func pickMovieCertification(from response: MovieReleaseDatesResponse, region: String) -> String? {
        let normalizedRegion = region.isEmpty ? "US" : region
        let fallbackRegion = "US"
        let regionResult = response.results.first(where: { $0.iso3166_1 == normalizedRegion })
            ?? response.results.first(where: { $0.iso3166_1 == fallbackRegion })
        guard let releaseDates = regionResult?.releaseDates else { return nil }
        let candidates = releaseDates.filter { !($0.certification?.isEmpty ?? true) }
        if candidates.isEmpty { return nil }
        let preferred = candidates.sorted { lhs, rhs in
            let lhsScore = TMDBService.releaseTypeScore(lhs.type)
            let rhsScore = TMDBService.releaseTypeScore(rhs.type)
            return lhsScore < rhsScore
        }
        return preferred.first?.certification
    }

    private static func pickTVCertification(from response: TVContentRatingsResponse, region: String) -> String? {
        let normalizedRegion = region.isEmpty ? "US" : region
        let fallbackRegion = "US"
        let regionResult = response.results.first(where: { $0.iso3166_1 == normalizedRegion })
            ?? response.results.first(where: { $0.iso3166_1 == fallbackRegion })
        let rating = regionResult?.rating
        return rating?.isEmpty == false ? rating : nil
    }

    private static func releaseTypeScore(_ type: Int?) -> Int {
        switch type {
        case 3:
            return 0 // Theatrical
        case 4:
            return 1 // Digital
        case 2:
            return 2 // Limited
        case 5:
            return 3 // Physical
        case 6:
            return 4 // TV
        case 1:
            return 5 // Premiere
        default:
            return 6
        }
    }
    
    // MARK: - Find by external ID (IMDb, TVDB, etc.)
    func findByExternalId(externalId: String, source: String = "imdb_id") async throws -> FindByIdResponse {
        let queryItems = [
            URLQueryItem(name: "external_source", value: source)
        ]
        return try await request("/find/\(externalId)", queryItems: queryItems)
    }
}

// MARK: - Person Credits Response
struct PersonCreditsResponse: Codable {
    let cast: [MediaItem]?
    let crew: [MediaItem]?
}

// MARK: - Find By ID Response
struct FindByIdResponse: Codable {
    let movieResults: [MediaItem]?
    let tvResults: [MediaItem]?
    let personResults: [Person]?
    
    enum CodingKeys: String, CodingKey {
        case movieResults = "movie_results"
        case tvResults = "tv_results"
        case personResults = "person_results"
    }
}

// MARK: - Certifications Responses
struct MovieReleaseDatesResponse: Codable {
    let results: [MovieReleaseDatesResult]
}

struct MovieReleaseDatesResult: Codable {
    let iso3166_1: String
    let releaseDates: [MovieReleaseDate]

    enum CodingKeys: String, CodingKey {
        case iso3166_1 = "iso_3166_1"
        case releaseDates = "release_dates"
    }
}

struct MovieReleaseDate: Codable {
    let certification: String?
    let type: Int?
    /// TMDB release type: 1 premiere, 2 limited theatrical, 3 theatrical,
    /// 4 digital, 5 physical, 6 TV. Needed to tell "in cinemas" apart from
    /// "streaming", which a bare release date can't.
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case certification, type
        case releaseDate = "release_date"
    }
}

struct TVContentRatingsResponse: Codable {
    let results: [TVContentRatingsResult]
}

struct TVContentRatingsResult: Codable {
    let iso3166_1: String
    let rating: String?

    enum CodingKeys: String, CodingKey {
        case iso3166_1 = "iso_3166_1"
        case rating
    }
}
