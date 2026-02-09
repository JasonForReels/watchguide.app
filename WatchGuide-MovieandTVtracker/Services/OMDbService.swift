//
//  OMDbService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

actor OMDbService {
    static let shared = OMDbService()
    
    private let baseURL = "https://www.omdbapi.com"
    
    private var apiKey: String {
        ApiKeyManager.shared.get(key: "OMDB_API_KEY") ?? ""
    }
    
    private var cache: [String: CachedRatings] = [:]
    private let cacheExpiration: TimeInterval = 3600 * 24 // 24 hours
    
    private struct CachedRatings {
        let response: OMDbResponse
        let cachedAt: Date
    }
    
    // Optimized session for OMDb
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 10
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    func getRatings(imdbId: String) async throws -> OMDbResponse {
        // Check cache
        if let cached = cache[imdbId],
           Date().timeIntervalSince(cached.cachedAt) < cacheExpiration {
            return cached.response
        }
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "i", value: imdbId),
            URLQueryItem(name: "plot", value: "short")
        ]
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let omdbResponse = try decoder.decode(OMDbResponse.self, from: data)
        
        // Cache the response
        cache[imdbId] = CachedRatings(response: omdbResponse, cachedAt: Date())
        
        return omdbResponse
    }
    
    func getRatingsSummary(imdbId: String) async -> RatingsSummary? {
        guard !apiKey.isEmpty else { return nil }
        
        do {
            let response = try await getRatings(imdbId: imdbId)
            return RatingsSummary(from: response)
        } catch {
            print("OMDb error: \(error)")
            return nil
        }
    }
}

// MARK: - Ratings Summary
struct RatingsSummary {
    let imdbRating: String?
    let imdbVotes: String?
    let rottenTomatoesScore: String?
    let metacriticScore: String?
    
    init?(from response: OMDbResponse) {
        guard response.response == "True" else { return nil }
        
        self.imdbRating = response.imdbRating
        self.imdbVotes = response.imdbVotes
        
        // Extract Rotten Tomatoes
        self.rottenTomatoesScore = response.ratings?.first { $0.source == "Rotten Tomatoes" }?.value
        
        // Extract Metacritic
        if let metascore = response.metascore, metascore != "N/A" {
            self.metacriticScore = "\(metascore)/100"
        } else {
            self.metacriticScore = response.ratings?.first { $0.source == "Metacritic" }?.value
        }
    }
}
