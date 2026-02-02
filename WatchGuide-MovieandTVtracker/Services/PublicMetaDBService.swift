//
//  PublicMetaDBService.swift
//  WatchGuide-MovieandTVtracker
//
//  Public Meta DB service for fetching curated movie & TV lists
//

import Foundation

actor PublicMetaDBService {
    static let shared = PublicMetaDBService()
    
    private let baseURL = "https://publicmetadb.com/api"
    
    // API Key - hardcoded since it's provided directly
    private let apiKey = "pm-HWJMWXKd9NUSrVBSUSqpUtUJl0CORtucHGK9EgzxbEHN0jFfBMA9zf9wYFrO"
    
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
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        
        guard let url = components?.url else {
            throw PublicMetaDBError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 30
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PublicMetaDBError.networkError
        }
        
        // Debug logging
        if let responseString = String(data: data, encoding: .utf8) {
            print("PublicMetaDB Response (\(httpResponse.statusCode)): \(responseString.prefix(500))")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw PublicMetaDBError.apiError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
    
    // MARK: - List Endpoints
    
    /// Get list info by ID or slug
    func getListInfo(listId: String) async throws -> PMDBListInfo {
        try await request(endpoint: "/lists/\(listId)")
    }
    
    /// Get items from a list
    func getListItems(listId: String, page: Int = 1, limit: Int = 50) async throws -> PMDBListItemsResponse {
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        return try await request(endpoint: "/lists/\(listId)/items", queryItems: queryItems)
    }
    
    /// Search for public lists
    func searchLists(query: String, page: Int = 1) async throws -> PMDBSearchResponse {
        let queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        return try await request(endpoint: "/lists/search", queryItems: queryItems)
    }
    
    /// Get popular/featured lists
    func getPopularLists(page: Int = 1) async throws -> PMDBSearchResponse {
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)")
        ]
        return try await request(endpoint: "/lists/popular", queryItems: queryItems)
    }
    
    // MARK: - Convenience Methods
    
    /// Fetch list items and convert to app's SavedMediaItem format
    func fetchListItemsAsSavedMedia(listId: String) async throws -> [SavedMediaItem] {
        let response = try await getListItems(listId: listId)
        var savedItems: [SavedMediaItem] = []
        
        for item in response.items {
            // Try to look up in TMDB for full details
            if let tmdbId = item.tmdbId {
                do {
                    let mediaType: MediaType = item.mediaType == "tv" ? .tv : .movie
                    
                    if mediaType == .movie {
                        let details = try await TMDBService.shared.getMovieDetails(id: tmdbId)
                        savedItems.append(SavedMediaItem(from: details))
                    } else {
                        let details = try await TMDBService.shared.getTVShowDetails(id: tmdbId)
                        savedItems.append(SavedMediaItem(from: details))
                    }
                } catch {
                    // Create basic saved item from PublicMetaDB data
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
}

// MARK: - PublicMetaDB Response Models

struct PMDBListInfo: Codable {
    let id: String
    let name: String
    let slug: String?
    let description: String?
    let itemCount: Int?
    let likes: Int?
    let user: PMDBUser?
    let posterUrl: String?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, slug, description, likes, user
        case itemCount = "item_count"
        case posterUrl = "poster_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PMDBUser: Codable {
    let id: String?
    let name: String?
    let username: String?
}

struct PMDBListItemsResponse: Codable {
    let items: [PMDBListItem]
    let page: Int?
    let totalPages: Int?
    let totalItems: Int?
    
    enum CodingKeys: String, CodingKey {
        case items, page
        case totalPages = "total_pages"
        case totalItems = "total_items"
    }
}

struct PMDBListItem: Codable, Identifiable {
    var id: String {
        if let imdbId = imdbId {
            return "\(mediaType ?? "unknown")-\(imdbId)"
        } else if let tmdbId = tmdbId {
            return "\(mediaType ?? "unknown")-\(tmdbId)"
        }
        return "\(mediaType ?? "unknown")-\(UUID().uuidString)"
    }
    
    let title: String?
    let year: Int?
    let imdbId: String?
    let tmdbId: Int?
    let mediaType: String?
    let rank: Int?
    let poster: String?
    let posterPath: String?
    let backdrop: String?
    let backdropPath: String?
    let overview: String?
    let rating: Double?
    let voteAverage: Double?
    
    enum CodingKeys: String, CodingKey {
        case title, year, rank, overview, rating, poster, backdrop
        case imdbId = "imdb_id"
        case tmdbId = "tmdb_id"
        case mediaType = "media_type"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
    }
    
    func toSavedMediaItem() -> SavedMediaItem? {
        guard let title = title else { return nil }
        
        let type: MediaType = mediaType == "tv" ? .tv : .movie
        let itemId = tmdbId ?? 0
        
        // Handle poster path - could be full URL or TMDB path
        let finalPosterPath = posterPath ?? poster
        let finalBackdropPath = backdropPath ?? backdrop
        
        let mediaItem = MediaItem(
            id: itemId,
            title: type == .movie ? title : nil,
            name: type == .tv ? title : nil,
            originalTitle: nil,
            originalName: nil,
            overview: overview,
            posterPath: finalPosterPath,
            backdropPath: finalBackdropPath,
            releaseDate: year != nil ? "\(year!)" : nil,
            firstAirDate: year != nil ? "\(year!)" : nil,
            voteAverage: voteAverage ?? rating,
            voteCount: nil,
            popularity: nil,
            genreIds: nil,
            mediaType: type.rawValue,
            adult: nil,
            originalLanguage: nil
        )
        
        return SavedMediaItem(from: mediaItem)
    }
}

struct PMDBSearchResponse: Codable {
    let lists: [PMDBListInfo]
    let page: Int?
    let totalPages: Int?
    let totalResults: Int?
    
    enum CodingKeys: String, CodingKey {
        case lists, page
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

// MARK: - Errors

enum PublicMetaDBError: LocalizedError {
    case notConfigured
    case invalidURL
    case networkError
    case invalidList
    case apiError(Int)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "PublicMetaDB not configured"
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
