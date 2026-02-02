//
//  FanArtService.swift
//  WatchGuide-MovieandTVtracker
//
//  FanArt.tv service for fallback artwork loading
//

import Foundation

actor FanArtService {
    static let shared = FanArtService()
    
    private let baseURL = "https://webservice.fanart.tv/v3"
    private let apiKey = "1d270eb9c6cff8abfe6c074eebba8d6f"
    
    private var cache: [String: FanArtResponse] = [:]
    
    private init() {}
    
    // MARK: - Movie Art
    
    func getMovieArt(tmdbId: Int) async throws -> FanArtResponse {
        let cacheKey = "movie-\(tmdbId)"
        
        if let cached = cache[cacheKey] {
            return cached
        }
        
        let url = URL(string: "\(baseURL)/movies/\(tmdbId)?api_key=\(apiKey)")!
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FanArtError.notFound
        }
        
        let result = try JSONDecoder().decode(FanArtResponse.self, from: data)
        cache[cacheKey] = result
        return result
    }
    
    // MARK: - TV Art
    
    func getTVArt(tvdbId: Int) async throws -> FanArtResponse {
        let cacheKey = "tv-\(tvdbId)"
        
        if let cached = cache[cacheKey] {
            return cached
        }
        
        let url = URL(string: "\(baseURL)/tv/\(tvdbId)?api_key=\(apiKey)")!
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FanArtError.notFound
        }
        
        let result = try JSONDecoder().decode(FanArtResponse.self, from: data)
        cache[cacheKey] = result
        return result
    }
    
    // MARK: - Get Best Poster URL
    
    func getBestPosterURL(tmdbId: Int, mediaType: MediaType) async -> URL? {
        do {
            if mediaType == .movie {
                let art = try await getMovieArt(tmdbId: tmdbId)
                // Try movie poster first, then movie thumb
                if let poster = art.movieposter?.first {
                    return URL(string: poster.url)
                }
                if let thumb = art.moviethumb?.first {
                    return URL(string: thumb.url)
                }
            } else {
                // For TV, we'd need TVDB ID - this is a limitation
                // Could potentially use TMDB external IDs to get TVDB ID
            }
        } catch {
            print("FanArt.tv error: \(error)")
        }
        return nil
    }
    
    // MARK: - Get Best Backdrop URL
    
    func getBestBackdropURL(tmdbId: Int, mediaType: MediaType) async -> URL? {
        do {
            if mediaType == .movie {
                let art = try await getMovieArt(tmdbId: tmdbId)
                if let backdrop = art.moviebackground?.first {
                    return URL(string: backdrop.url)
                }
            }
        } catch {
            print("FanArt.tv error: \(error)")
        }
        return nil
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
            return "Artwork not found"
        case .networkError:
            return "Network error"
        }
    }
}
