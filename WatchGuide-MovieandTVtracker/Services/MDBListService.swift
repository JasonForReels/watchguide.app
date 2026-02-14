//
//  MDBListService.swift
//  WatchGuide-MovieandTVtracker
//
//  MDBList service for fetching curated movie & TV lists
//  Uses the JSON export endpoint for reliable list fetching
//

import Foundation

actor MDBListService {
    static let shared = MDBListService()
    
    private let baseURL = "https://mdblist.com"
    
    private let apiKey = "mi46uequ1wi40i8fxp4789jxz"
    
    // Optimized session with caching
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()
    
    // In-memory cache for list results
    private var listCache: [String: (items: [MDBListItem], timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 600 // 10 minutes
    
    private init() {}
    
    var isConfigured: Bool {
        !apiKey.isEmpty
    }
    
    // MARK: - List Endpoints
    
    /// Get list items by list ID using the JSON export endpoint
    func getListItems(listId: String) async throws -> [MDBListItem] {
        guard !apiKey.isEmpty else {
            throw MDBListError.notConfigured
        }
        
        // Check in-memory cache
        if let cached = listCache[listId],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.items
        }
        
        // Use the JSON export endpoint which is more reliable
        let urlString = "\(baseURL)/lists/\(listId)/json?apikey=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw MDBListError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MDBListError.networkError
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MDBListError.apiError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let items = try decoder.decode([MDBListItem].self, from: data)
        
        // Cache the result
        listCache[listId] = (items: items, timestamp: Date())
        
        return items
    }
    
    // MARK: - Ratings Lookup
    
    /// Fetch ratings from MDBList by TMDB ID.
    /// Returns aggregated scores from IMDb, Rotten Tomatoes, Metacritic, Letterboxd, Trakt, etc.
    func getRatings(tmdbId: Int, mediaType: MediaType) async throws -> MDBListMediaInfo {
        guard !apiKey.isEmpty else { throw MDBListError.notConfigured }
        
        // Check in-memory cache
        let cacheKey = "ratings-\(mediaType.rawValue)-\(tmdbId)"
        if let cached = ratingsCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.info
        }
        
        var urlString = "\(baseURL)/api/?apikey=\(apiKey)&tm=\(tmdbId)"
        if mediaType == .tv {
            urlString += "&m=show"
        }
        
        guard let url = URL(string: urlString) else {
            throw MDBListError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MDBListError.networkError
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MDBListError.apiError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let info = try decoder.decode(MDBListMediaInfo.self, from: data)
        
        // Cache the result
        ratingsCache[cacheKey] = (info: info, timestamp: Date())
        
        return info
    }
    
    /// Convenience: get a RatingsSummary from MDBList for the detail page.
    /// Falls back to nil on any error so the view model can try OMDb.
    func getRatingsSummary(tmdbId: Int, mediaType: MediaType) async -> RatingsSummary? {
        do {
            let info = try await getRatings(tmdbId: tmdbId, mediaType: mediaType)
            return RatingsSummary(from: info)
        } catch {
            print("MDBList ratings error: \(error)")
            return nil
        }
    }
    
    // In-memory cache for ratings
    private var ratingsCache: [String: (info: MDBListMediaInfo, timestamp: Date)] = [:]
    
    // MARK: - Convenience Methods
    
    /// Fetch list items and convert to app's SavedMediaItem format
    func fetchListItemsAsSavedMedia(listId: String) async throws -> [SavedMediaItem] {
        let items = try await getListItems(listId: listId)
        var savedItems: [SavedMediaItem] = []
        
        for item in items.prefix(50) { // Limit to 50 to avoid too many API calls
            // Try to look up in TMDB for full details
            if let tmdbId = item.id, tmdbId > 0 {
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
    nonisolated func parseListId(from input: String) -> String {
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

/// Item from MDBList JSON export
struct MDBListItem: Codable, Identifiable {
    let id: Int?
    let title: String?
    let year: Int?
    let imdbId: String?
    let tvdbId: Int?
    let mediatype: String?
    let rank: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, title, year, rank, mediatype
        case imdbId = "imdb_id"
        case tvdbId = "tvdb_id"
    }
    
    func toSavedMediaItem() -> SavedMediaItem? {
        guard let title = title, let itemId = id, itemId > 0 else { return nil }
        
        let type: MediaType = mediatype == "show" ? .tv : .movie
        
        let mediaItem = MediaItem(
            id: itemId,
            title: type == .movie ? title : nil,
            name: type == .tv ? title : nil,
            originalTitle: nil,
            originalName: nil,
            overview: nil,
            posterPath: nil,
            backdropPath: nil,
            releaseDate: year != nil ? "\(year!)" : nil,
            firstAirDate: year != nil ? "\(year!)" : nil,
            voteAverage: nil,
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

// MARK: - MDBList Media Info (ratings response)

struct MDBListMediaInfo: Codable {
    let title: String?
    let year: Int?
    let imdbid: String?
    let traktid: Int?
    let tmdbid: Int?
    let score: Int?
    let ratings: [MDBListRating]?
    
    enum CodingKeys: String, CodingKey {
        case title, year, imdbid, traktid, tmdbid, score, ratings
    }
}

struct MDBListRating: Codable {
    let source: String
    let value: Double?
    let score: Int?
    let votes: Int?
    let url: String?
}

// MARK: - RatingsSummary from MDBList

extension RatingsSummary {
    /// Build a RatingsSummary from MDBList media-info ratings array.
    init?(from info: MDBListMediaInfo) {
        guard let ratings = info.ratings, !ratings.isEmpty else { return nil }
        
        // IMDb
        let imdb = ratings.first { $0.source == "imdb" }
        self.imdbRating = imdb.flatMap { r in r.value.map { String(format: "%.1f", $0) } }
        self.imdbVotes = imdb.flatMap { r in r.votes.map { formatVotes($0) } }
        
        // Rotten Tomatoes (critics)
        let rt = ratings.first { $0.source == "tomatoes" }
        self.rottenTomatoesScore = rt.flatMap { r in r.score.map { "\($0)%" } }
        
        // Metacritic
        let meta = ratings.first { $0.source == "metacritic" }
        self.metacriticScore = meta.flatMap { r in r.score.map { "\($0)/100" } }
    }
}

/// Format vote counts to a human-readable string (e.g., 12345 → "12,345")
private func formatVotes(_ votes: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: votes)) ?? "\(votes)"
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
