//
//  JSONHubService.swift
//  WatchGuide-MovieandTVtracker
//
//  Fetches external JSON files and resolves them to media items via TMDB.
//

import Foundation

actor JSONHubService {
    static let shared = JSONHubService()
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    // MARK: - Fetch & Parse JSON File
    
    /// Downloads a JSON file from the given URL and parses it into SavedMediaItem entries.
    /// Supports multiple JSON shapes:
    ///   - Array of objects with `tmdb_id` + `media_type` (preferred)
    ///   - Array of objects with `title` + `year` (will search TMDB)
    ///   - Wrapped in `{ "items": [...] }` or `{ "results": [...] }`
    func fetchAndResolve(from urlString: String, maxItems: Int = 50) async throws -> (name: String?, items: [SavedMediaItem]) {
        guard let url = URL(string: urlString) else {
            throw JSONHubError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw JSONHubError.networkError
        }
        
        // Try to decode as various shapes
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        var entries: [ExternalJSONEntry] = []
        var hubName: String?
        
        // Shape 1: Direct array of entries
        if let directArray = try? decoder.decode([ExternalJSONEntry].self, from: data) {
            entries = directArray
        }
        // Shape 2: Wrapped in { "items": [...] } or { "results": [...] } or { "name": "...", "items": [...] }
        else if let wrapper = try? decoder.decode(JSONHubWrapper.self, from: data) {
            entries = wrapper.items ?? wrapper.results ?? []
            hubName = wrapper.name ?? wrapper.title
        }
        // Shape 3: Try flexible decoding
        else {
            throw JSONHubError.invalidFormat
        }
        
        guard !entries.isEmpty else {
            throw JSONHubError.emptyList
        }
        
        // Resolve entries to SavedMediaItems via TMDB
        var savedItems: [SavedMediaItem] = []
        
        for entry in entries.prefix(maxItems) {
            if let item = await resolveEntry(entry) {
                savedItems.append(item)
            }
        }
        
        return (name: hubName, items: savedItems)
    }
    
    /// Preview: just fetch and count items without full TMDB resolution
    func preview(from urlString: String) async throws -> (name: String?, count: Int, sampleEntries: [ExternalJSONEntry]) {
        guard let url = URL(string: urlString) else {
            throw JSONHubError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw JSONHubError.networkError
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        var entries: [ExternalJSONEntry] = []
        var hubName: String?
        
        if let directArray = try? decoder.decode([ExternalJSONEntry].self, from: data) {
            entries = directArray
        } else if let wrapper = try? decoder.decode(JSONHubWrapper.self, from: data) {
            entries = wrapper.items ?? wrapper.results ?? []
            hubName = wrapper.name ?? wrapper.title
        } else {
            throw JSONHubError.invalidFormat
        }
        
        guard !entries.isEmpty else {
            throw JSONHubError.emptyList
        }
        
        return (name: hubName, count: entries.count, sampleEntries: Array(entries.prefix(5)))
    }
    
    // MARK: - Resolve Single Entry
    
    private func resolveEntry(_ entry: ExternalJSONEntry) async -> SavedMediaItem? {
        // If we have a TMDB ID, use it directly
        if let tmdbId = entry.tmdbId, tmdbId > 0 {
            let mediaType: MediaType = (entry.mediaType == "tv" || entry.mediaType == "show") ? .tv : .movie
            
            do {
                if mediaType == .movie {
                    let details = try await TMDBService.shared.getMovieDetails(id: tmdbId)
                    return SavedMediaItem(from: details)
                } else {
                    let details = try await TMDBService.shared.getTVShowDetails(id: tmdbId)
                    return SavedMediaItem(from: details)
                }
            } catch {
                // Fallback to a basic item
                return createBasicItem(entry: entry, tmdbId: tmdbId, mediaType: mediaType)
            }
        }
        
        // If we have a title, search TMDB
        if let title = entry.title, !title.isEmpty {
            do {
                let results = try await TMDBService.shared.searchMulti(query: title)
                if let match = results.results.first {
                    return SavedMediaItem(from: match)
                }
            } catch {
                print("JSONHub search error for '\(title)': \(error)")
            }
        }
        
        return nil
    }
    
    private func createBasicItem(entry: ExternalJSONEntry, tmdbId: Int, mediaType: MediaType) -> SavedMediaItem {
        let title = entry.title ?? "Unknown"
        let mediaItem = MediaItem(
            id: tmdbId,
            title: mediaType == .movie ? title : nil,
            name: mediaType == .tv ? title : nil,
            originalTitle: nil,
            originalName: nil,
            overview: nil,
            posterPath: nil,
            backdropPath: nil,
            releaseDate: entry.year.map { "\($0)" },
            firstAirDate: entry.year.map { "\($0)" },
            voteAverage: nil,
            voteCount: nil,
            popularity: nil,
            genreIds: nil,
            mediaType: mediaType.rawValue,
            adult: nil,
            originalLanguage: nil
        )
        return SavedMediaItem(from: mediaItem)
    }
}

// MARK: - JSON Wrapper Shape
private struct JSONHubWrapper: Codable {
    let name: String?
    let title: String?
    let items: [ExternalJSONEntry]?
    let results: [ExternalJSONEntry]?
}

// MARK: - Errors
enum JSONHubError: LocalizedError {
    case invalidURL
    case networkError
    case invalidFormat
    case emptyList
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid JSON URL"
        case .networkError:
            return "Could not download the JSON file"
        case .invalidFormat:
            return "The JSON file format is not recognized. Expected an array of objects with tmdb_id and media_type."
        case .emptyList:
            return "The JSON file contains no items"
        }
    }
}
