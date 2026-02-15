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
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // 50 MB memory cache, 200 MB disk cache
        config.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 8
        config.waitsForConnectivity = true
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
    
    // MARK: - Generic Request (with in-memory caching)
    private func request<T: Decodable>(_ endpoint: String, queryItems: [URLQueryItem] = [], useCache: Bool = true) async throws -> T {
        var components = URLComponents(string: "\(baseURL)\(endpoint)")!
        var items = queryItems
        items.append(URLQueryItem(name: "api_key", value: apiKey))
        components.queryItems = items
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        let cacheKey = url.absoluteString
        
        // Check in-memory cache first
        if useCache, let cached: T = getCached(cacheKey) {
            return cached
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(T.self, from: data)
        
        // Store in in-memory cache
        if useCache {
            setCache(cacheKey, value: result)
        }
        
        return result
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
        let endDateString = endDate ?? {
            let year = Calendar.current.component(.year, from: today)
            return "\(year)-12-31"
        }()
        
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
    
    func getMovieCredits(id: Int) async throws -> Credits {
        try await request("/movie/\(id)/credits")
    }
    
    func getMovieVideos(id: Int) async throws -> VideosResponse {
        try await request("/movie/\(id)/videos")
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
    
    func getTVShowCredits(id: Int) async throws -> Credits {
        try await request("/tv/\(id)/credits")
    }
    
    func getTVShowVideos(id: Int) async throws -> VideosResponse {
        try await request("/tv/\(id)/videos")
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
    
    // MARK: - Discover
    func discoverMovies(genres: [Int]? = nil, year: Int? = nil, sortBy: String = "popularity.desc", page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let adult = await includeAdultValue()
        var queryItems = [
            URLQueryItem(name: "sort_by", value: sortBy),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: adult)
        ]
        if let genres = genres, !genres.isEmpty {
            queryItems.append(URLQueryItem(name: "with_genres", value: genres.map { "\($0)" }.joined(separator: ",")))
        }
        if let year = year {
            queryItems.append(URLQueryItem(name: "primary_release_year", value: "\(year)"))
        }
        return try await request("/discover/movie", queryItems: queryItems)
    }
    
    func discoverTV(genres: [Int]? = nil, year: Int? = nil, sortBy: String = "popularity.desc", page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let adult = await includeAdultValue()
        var queryItems = [
            URLQueryItem(name: "sort_by", value: sortBy),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: adult)
        ]
        if let genres = genres, !genres.isEmpty {
            queryItems.append(URLQueryItem(name: "with_genres", value: genres.map { "\($0)" }.joined(separator: ",")))
        }
        if let year = year {
            queryItems.append(URLQueryItem(name: "first_air_date_year", value: "\(year)"))
        }
        return try await request("/discover/tv", queryItems: queryItems)
    }
    
    func discoverMoviesByCompany(companyIds: [Int], page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let queryItems = [
            URLQueryItem(name: "with_companies", value: companyIds.map { "\($0)" }.joined(separator: "|")),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        return try await request("/discover/movie", queryItems: queryItems)
    }
    
    func discoverTVByNetwork(networkIds: [Int], page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let queryItems = [
            URLQueryItem(name: "with_networks", value: networkIds.map { "\($0)" }.joined(separator: "|")),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
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
        let queryItems = [
            URLQueryItem(name: "with_watch_providers", value: providerIds.map { "\($0)" }.joined(separator: "|")),
            URLQueryItem(name: "watch_region", value: region),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        return try await request("/discover/movie", queryItems: queryItems)
    }
    
    func discoverTVWithProvider(providerIds: [Int], region: String, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let queryItems = [
            URLQueryItem(name: "with_watch_providers", value: providerIds.map { "\($0)" }.joined(separator: "|")),
            URLQueryItem(name: "watch_region", value: region),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        return try await request("/discover/tv", queryItems: queryItems)
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
