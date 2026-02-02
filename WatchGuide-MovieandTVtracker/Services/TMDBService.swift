//
//  TMDBService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

actor TMDBService {
    static let shared = TMDBService()
    
    private let baseURL = "https://api.themoviedb.org/3"
    private let imageBaseURL = "https://image.tmdb.org/t/p"
    
    private var apiKey: String {
        ApiKeyManager.shared.get(key: "TMDB_API_KEY") ?? ""
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
    
    // MARK: - Generic Request
    private func request<T: Decodable>(_ endpoint: String, queryItems: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(string: "\(baseURL)\(endpoint)")!
        var items = queryItems
        items.append(URLQueryItem(name: "api_key", value: apiKey))
        components.queryItems = items
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
    
    // MARK: - Trending
    func getTrending(mediaType: MediaType, timeWindow: String = "week", page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let endpoint = "/trending/\(mediaType.rawValue)/\(timeWindow)"
        return try await request(endpoint, queryItems: [URLQueryItem(name: "page", value: "\(page)")])
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
    
    func getUpcomingMovies(page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        // Use discover endpoint with future release dates for better upcoming movies
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)
        
        // Get movies releasing in the next 6 months
        let futureDate = Calendar.current.date(byAdding: .month, value: 6, to: today) ?? today
        let futureDateString = formatter.string(from: futureDate)
        
        let region = await MainActor.run { StorageService.shared.settings.region }
        
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "primary_release_date.gte", value: todayString),
            URLQueryItem(name: "primary_release_date.lte", value: futureDateString),
            URLQueryItem(name: "sort_by", value: "primary_release_date.asc"),
            URLQueryItem(name: "with_release_type", value: "2|3"), // Theatrical releases
            URLQueryItem(name: "region", value: region)
        ]
        
        return try await request("/discover/movie", queryItems: queryItems)
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
    
    // MARK: - Search
    func searchMulti(query: String, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        return try await request("/search/multi", queryItems: queryItems)
    }
    
    func searchMovies(query: String, year: Int? = nil, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        if let year = year {
            queryItems.append(URLQueryItem(name: "year", value: "\(year)"))
        }
        return try await request("/search/movie", queryItems: queryItems)
    }
    
    func searchTV(query: String, year: Int? = nil, page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        if let year = year {
            queryItems.append(URLQueryItem(name: "first_air_date_year", value: "\(year)"))
        }
        return try await request("/search/tv", queryItems: queryItems)
    }
    
    func searchPerson(query: String, page: Int = 1) async throws -> TMDBResponse<Person> {
        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        return try await request("/search/person", queryItems: queryItems)
    }
    
    // MARK: - Discover
    func discoverMovies(genres: [Int]? = nil, year: Int? = nil, sortBy: String = "popularity.desc", page: Int = 1) async throws -> TMDBResponse<MediaItem> {
        var queryItems = [
            URLQueryItem(name: "sort_by", value: sortBy),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: "false")
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
        var queryItems = [
            URLQueryItem(name: "sort_by", value: sortBy),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "include_adult", value: "false")
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
