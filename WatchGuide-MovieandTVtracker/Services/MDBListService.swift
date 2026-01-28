//
//  MDBListService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

actor MDBListService {
    static let shared = MDBListService()
    
    private let baseURL = "https://mdblist.com/api"
    
    private var clientId: String {
        ApiKeyManager.shared.get(key: "MDBLIST_CLIENT_ID") ?? ""
    }
    
    private var clientSecret: String {
        ApiKeyManager.shared.get(key: "MDBLIST_CLIENT_SECRET") ?? ""
    }
    
    private init() {}
    
    var isConfigured: Bool {
        !clientId.isEmpty && !clientSecret.isEmpty
    }
    
    // MARK: - Fetch List Items
    func fetchListItems(listId: String) async throws -> [MDBListMedia] {
        guard isConfigured else {
            throw MDBListError.notConfigured
        }
        
        var components = URLComponents(string: "\(baseURL)/lists/\(listId)/items")!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: clientSecret)
        ]
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let items = try decoder.decode([MDBListMedia].self, from: data)
        return items
    }
    
    // MARK: - Get List Info
    func getListInfo(listId: String) async throws -> MDBListInfo {
        guard isConfigured else {
            throw MDBListError.notConfigured
        }
        
        var components = URLComponents(string: "\(baseURL)/lists/\(listId)")!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: clientSecret)
        ]
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let info = try decoder.decode(MDBListInfo.self, from: data)
        return info
    }
}

// MARK: - MDBList Models
struct MDBListMedia: Codable, Identifiable {
    var id: String {
        if let imdbId = imdbId {
            return "\(mediatype ?? "unknown")-\(imdbId)"
        } else if let tmdbId = tmdbId {
            return "\(mediatype ?? "unknown")-\(tmdbId)"
        }
        return "\(mediatype ?? "unknown")-\(UUID().uuidString)"
    }
    let title: String?
    let year: Int?
    let imdbId: String?
    let tmdbId: Int?
    let mediatype: String?
    let rank: Int?
    
    enum CodingKeys: String, CodingKey {
        case title, year, rank, mediatype
        case imdbId = "imdb_id"
        case tmdbId = "tmdb_id"
    }
}

struct MDBListInfo: Codable {
    let id: Int
    let name: String
    let description: String?
    let itemCount: Int?
    let likes: Int?
    let user: MDBListUser?
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, likes, user
        case itemCount = "item_count"
    }
}

struct MDBListUser: Codable {
    let id: Int
    let name: String?
}

// MARK: - Errors
enum MDBListError: LocalizedError {
    case notConfigured
    case invalidList
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "MDBList API not configured"
        case .invalidList:
            return "Invalid list ID"
        case .networkError:
            return "Network error"
        }
    }
}
