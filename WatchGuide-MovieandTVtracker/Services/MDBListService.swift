//
//  MDBListService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation
import AuthenticationServices

actor MDBListService {
    static let shared = MDBListService()
    
    private let baseURL = "https://mdblist.com/api"
    private let oauthBaseURL = "https://mdblist.com/oauth"
    
    // OAuth credentials
    private let clientId = "yrYmrtdSHTR12MBp9fdjHWFTsE4BXWAZ0LXiIA4R"
    private let clientSecret = "S8u0AAPpm2xJiYUMPrh7O4AMsXXCHlrIodMaC46ZhnMed4VqtBtDb7BbFvnwdg254vsqP6RyxqFwMFJK1hsTtZv8BeZaVyoeicx2PBZxpHDtq6z63Z2xjTinUzl4ar6n"
    private let redirectURI = "watchguide://mdblist/callback"
    
    private init() {}
    
    // MARK: - Token Management
    private var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "mdblist_access_token") }
        set { UserDefaults.standard.set(newValue, forKey: "mdblist_access_token") }
    }
    
    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "mdblist_refresh_token") }
        set { UserDefaults.standard.set(newValue, forKey: "mdblist_refresh_token") }
    }
    
    private var tokenExpiry: Date? {
        get { UserDefaults.standard.object(forKey: "mdblist_token_expiry") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "mdblist_token_expiry") }
    }
    
    var isAuthenticated: Bool {
        accessToken != nil && (tokenExpiry == nil || tokenExpiry! > Date())
    }
    
    var isConfigured: Bool {
        !clientId.isEmpty && !clientSecret.isEmpty
    }
    
    // MARK: - OAuth 2.0 Flow
    
    /// Generate the OAuth authorization URL (nonisolated for sync access from UI)
    nonisolated func getAuthorizationURL() -> URL? {
        var components = URLComponents(string: "\(oauthBaseURL)/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "read write")
        ]
        return components?.url
    }
    
    /// Exchange authorization code for access token
    func exchangeCodeForToken(code: String) async throws {
        guard let url = URL(string: "\(oauthBaseURL)/token") else {
            throw MDBListError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MDBListError.authenticationFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        
        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken
        
        if let expiresIn = tokenResponse.expiresIn {
            tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        }
    }
    
    /// Refresh the access token
    func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw MDBListError.notAuthenticated
        }
        
        guard let url = URL(string: "\(oauthBaseURL)/token") else {
            throw MDBListError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Clear tokens on refresh failure
            await signOut()
            throw MDBListError.authenticationFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        
        accessToken = tokenResponse.accessToken
        if let newRefreshToken = tokenResponse.refreshToken {
            self.refreshToken = newRefreshToken
        }
        
        if let expiresIn = tokenResponse.expiresIn {
            tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        }
    }
    
    /// Sign out and clear tokens
    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        UserDefaults.standard.removeObject(forKey: "mdblist_access_token")
        UserDefaults.standard.removeObject(forKey: "mdblist_refresh_token")
        UserDefaults.standard.removeObject(forKey: "mdblist_token_expiry")
    }
    
    // MARK: - API Requests
    
    private func authenticatedRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        // Check if token needs refresh
        if let expiry = tokenExpiry, expiry < Date() {
            try await refreshAccessToken()
        }
        
        guard let token = accessToken else {
            throw MDBListError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw MDBListError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MDBListError.networkError
        }
        
        if httpResponse.statusCode == 401 {
            // Try to refresh token and retry
            try await refreshAccessToken()
            return try await authenticatedRequest(endpoint: endpoint, method: method, body: body)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MDBListError.apiError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
    
    // MARK: - User Lists
    
    /// Get user's own lists
    func getUserLists() async throws -> [MDBUserList] {
        try await authenticatedRequest(endpoint: "/lists/user")
    }
    
    /// Get items from a specific list
    func getListItems(listId: Int) async throws -> [MDBListMedia] {
        try await authenticatedRequest(endpoint: "/lists/\(listId)/items")
    }
    
    /// Get public list info by ID or slug
    func getPublicListInfo(listId: String) async throws -> MDBListInfo {
        guard let url = URL(string: "\(baseURL)/lists/\(listId)") else {
            throw MDBListError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MDBListError.invalidList
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MDBListInfo.self, from: data)
    }
    
    /// Get items from a public list
    func getPublicListItems(listId: String) async throws -> [MDBListMedia] {
        guard let url = URL(string: "\(baseURL)/lists/\(listId)/items") else {
            throw MDBListError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MDBListError.invalidList
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([MDBListMedia].self, from: data)
    }
    
    // MARK: - Legacy API Key Methods (for backward compatibility)
    
    func fetchListItems(listId: String) async throws -> [MDBListMedia] {
        // Try authenticated first if available
        if isAuthenticated, let listIdInt = Int(listId) {
            return try await getListItems(listId: listIdInt)
        }
        
        // Fall back to public API
        return try await getPublicListItems(listId: listId)
    }
    
    func getListInfo(listId: String) async throws -> MDBListInfo {
        return try await getPublicListInfo(listId: listId)
    }
}

// MARK: - OAuth Token Response
struct OAuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

// MARK: - MDBList User List
struct MDBUserList: Codable, Identifiable {
    let id: Int
    let name: String
    let slug: String?
    let description: String?
    let itemCount: Int?
    let isPublic: Bool?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, slug, description
        case itemCount = "item_count"
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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
    let poster: String?
    let backdrop: String?
    let overview: String?
    let rating: Double?
    
    enum CodingKeys: String, CodingKey {
        case title, year, rank, mediatype, poster, backdrop, overview, rating
        case imdbId = "imdb_id"
        case tmdbId = "tmdb_id"
    }
}

struct MDBListInfo: Codable {
    let id: Int
    let name: String
    let slug: String?
    let description: String?
    let itemCount: Int?
    let likes: Int?
    let user: MDBListUser?
    let posterUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, slug, description, likes, user
        case itemCount = "item_count"
        case posterUrl = "poster_url"
    }
}

struct MDBListUser: Codable {
    let id: Int
    let name: String?
}

// MARK: - Errors
enum MDBListError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case authenticationFailed
    case invalidList
    case invalidURL
    case networkError
    case apiError(Int)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "MDBList not configured"
        case .notAuthenticated:
            return "Not signed in to MDBList"
        case .authenticationFailed:
            return "MDBList authentication failed"
        case .invalidList:
            return "Invalid list ID"
        case .invalidURL:
            return "Invalid URL"
        case .networkError:
            return "Network error"
        case .apiError(let code):
            return "API error: \(code)"
        }
    }
}
