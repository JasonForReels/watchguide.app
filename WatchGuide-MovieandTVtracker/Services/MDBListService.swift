//
//  MDBListService.swift
//  WatchGuide-MovieandTVtracker
//
//  MDBList service for fetching curated movie & TV lists
//  API Docs: https://mdblist.docs.apiary.io/
//

import Foundation

actor MDBListService {
    static let shared = MDBListService()
    
    private let baseURL = "https://mdblist.com/api"
    
    // API Key - hardcoded since it's provided directly
    private let apiKey = "mi46uequ1wi40i8fxp4789jxz"
    
    private init() {}
    
    var isConfigured: Bool {
        !apiKey.isEmpty
    }
    
    // MARK: - API Requests
    
    private func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        var components = URLComponents(string: "\(baseURL)\(endpoint)")
        var items = queryItems
        items.append(URLQueryItem(name: "apikey", value: apiKey))
        components?.queryItems = items
        
        guard let url = components?.url else {
            throw MDBListError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MDBListError.networkError
        }
        
        // Debug logging
        if let responseString = String(data: data, encoding: .utf8) {
            print("MDBList Response (\(httpResponse.statusCode)): \(responseString.prefix(500))")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MDBListError.apiError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
    
    // MARK: - List Endpoints
    
    /// Get list items by list ID
    func getListItems(listId: String) async throws -> [MDBListItem] {
        try await request(endpoint: "/lists/\(listId)/items")
    }
    
    /// Get user's lists
    func getUserLists(userId: String) async throws -> [MDBListInfo] {
        try await request(endpoint: "/lists/user/\(userId)")
    }
    
    /// Search for media
    func searchMedia(query: String) async throws -> [MDBListSearchResult] {
        let queryItems = [
            URLQueryItem(name: "s", value: query)
        ]
        return try await request(endpoint: "/", queryItems: queryItems)
    }
    
    /// Get media details by IMDb ID
    func getMediaByIMDbId(imdbId: String) async throws -> MDBListMediaDetails {
        let queryItems = [
            URLQueryItem(name: "i", value: imdbId)
        ]
        return try await request(endpoint: "/", queryItems: queryItems)
    }
    
    /// Get media details by TMDB ID
    func getMediaByTMDbId(tmdbId: Int, mediaType: String = "movie") async throws -> MDBListMediaDetails {
        let queryItems = [
            URLQueryItem(name: "tm", value: "\(tmdbId)"),
            URLQueryItem(name: "m", value: mediaType)
        ]
        return try await request(endpoint: "/", queryItems: queryItems)
    }
    
    // MARK: - Convenience Methods
    
    /// Fetch list items and convert to app's SavedMediaItem format
    func fetchListItemsAsSavedMedia(listId: String) async throws -> [SavedMediaItem] {
        let items = try await getListItems(listId: listId)
        var savedItems: [SavedMediaItem] = []
        
        for item in items {
            // Try to look up in TMDB for full details
            if let tmdbId = item.id {
                do {
                    let mediaType: MediaType = item.mediatype == "show" ? .tv : .movie
                    
                    if mediaType == .movie {
                        let details = try await TMDBService.shared.getMovieDetails(id: tmdbId)
                        savedItems.append(SavedMediaItem(from: details))
                    } else {
                        let details = try await TMDBService.shared.getTVShowDetails(id: tmdbId)
                        savedItems.append(SavedMediaItem(from: details))
                    }
                } catch {
                    // Create basic saved item from MDBList data
                    if let savedItem = item.toSavedMediaItem() {
                        savedItems.append(savedItem)
                    }
                }
            } else if let savedItem = item.toSavedMediaItem() {
                savedItems.append(savedItem)
            }
        }
        
        return savedItems
    }
    
    /// Parse list ID from URL or return as-is
    func parseListId(from input: String) -> String {
        var id = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle URL formats like https://mdblist.com/lists/username/listname
        if id.contains("mdblist.com/lists/") {
            // Extract the path after /lists/
            if let url = URL(string: id) {
                let pathComponents = url.pathComponents
                if let listsIndex = pathComponents.firstIndex(of: "lists"),
                   listsIndex + 2 < pathComponents.count {
                    // Return username/listname format
                    let username = pathComponents[listsIndex + 1]
                    let listname = pathComponents[listsIndex + 2]
                    id = "\(username)/\(listname)"
                }
            }
        }
        
        return id
    }
}

// MARK: - MDBList Response Models

struct MDBListInfo: Codable, Identifiable {
    let id: String?
    let name: String?
    let slug: String?
    let description: String?
    let itemCount: Int?
    let likes: Int?
    let user: String?
    let userId: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, slug, description, likes, user
        case itemCount = "item_count"
        case userId = "user_id"
    }
}

struct MDBListItem: Codable, Identifiable {
    var id: Int? { tmdbId ?? imdbId?.hashValue }
    
    let title: String?
    let year: Int?
    let imdbId: String?
    let tmdbId: Int?
    let tvdbId: Int?
    let mediatype: String?
    let rank: Int?
    let poster: String?
    let backdrop: String?
    let description: String?
    let score: Double?
    let scoreAverage: Double?
    let adult: Bool?
    let releaseDate: String?
    
    enum CodingKeys: String, CodingKey {
        case title, year, rank, description, score, adult, poster, backdrop, mediatype
        case imdbId = "imdb_id"
        case tmdbId = "id"
        case tvdbId = "tvdb_id"
        case scoreAverage = "score_average"
        case releaseDate = "release_date"
    }
    
    func toSavedMediaItem() -> SavedMediaItem? {
        guard let title = title else { return nil }
        
        let type: MediaType = mediatype == "show" ? .tv : .movie
        let itemId = tmdbId ?? 0
        
        let mediaItem = MediaItem(
            id: itemId,
            title: type == .movie ? title : nil,
            name: type == .tv ? title : nil,
            originalTitle: nil,
            originalName: nil,
            overview: description,
            posterPath: poster,
            backdropPath: backdrop,
            releaseDate: year != nil ? "\(year!)" : nil,
            firstAirDate: year != nil ? "\(year!)" : nil,
            voteAverage: scoreAverage ?? score,
            voteCount: nil,
            popularity: nil,
            genreIds: nil,
            mediaType: type.rawValue,
            adult: adult,
            originalLanguage: nil
        )
        
        return SavedMediaItem(from: mediaItem)
    }
}

struct MDBListSearchResult: Codable, Identifiable {
    var id: String { imdbId ?? "\(tmdbId ?? 0)" }
    
    let title: String?
    let year: Int?
    let imdbId: String?
    let tmdbId: Int?
    let type: String?
    let poster: String?
    let score: Double?
    
    enum CodingKeys: String, CodingKey {
        case title, year, type, poster, score
        case imdbId = "imdb_id"
        case tmdbId = "tmdb_id"
    }
}

struct MDBListMediaDetails: Codable {
    let title: String?
    let year: Int?
    let imdbId: String?
    let tmdbId: Int?
    let tvdbId: Int?
    let type: String?
    let poster: String?
    let backdrop: String?
    let description: String?
    let runtime: Int?
    let score: Double?
    let scoreAverage: Double?
    let ratings: [MDBListRating]?
    let streams: [MDBListStream]?
    let trailer: String?
    
    enum CodingKeys: String, CodingKey {
        case title, year, type, poster, backdrop, description, runtime, score, ratings, streams, trailer
        case imdbId = "imdb_id"
        case tmdbId = "tmdb_id"
        case tvdbId = "tvdb_id"
        case scoreAverage = "score_average"
    }
}

struct MDBListRating: Codable {
    let source: String?
    let value: Double?
    let score: Int?
    let votes: Int?
    let url: String?
}

struct MDBListStream: Codable {
    let name: String?
    let link: String?
    let logo: String?
    let type: String?
}

// MARK: - Errors

enum MDBListError: LocalizedError {
    case notConfigured
    case invalidURL
    case networkError
    case invalidList
    case apiError(Int)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "MDBList not configured"
        case .invalidURL:
            return "Invalid URL"
        case .networkError:
            return "Network error"
        case .invalidList:
            return "Invalid list ID"
        case .apiError(let code):
            return "API error: \(code)"
        }
    }
}
