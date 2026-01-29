//
//  MDBListService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation
import AuthenticationServices
import CryptoKit

actor MDBListService {
    static let shared = MDBListService()
    
    private let baseURL = "https://mdblist.com/api"
    private let oauthBaseURL = "https://mdblist.com/oauth"
    
    // OAuth credentials
    private let clientId = "XH4s24sCDpn4sH4yJm35l0Y4PTjGJJ0uxldubxKX"
    private let clientSecret = "8i0oYHEN5RauJdlMwWMIzBT7HviFGn3lLzGbjAM9OgbUNA3Cwc0VHtJjEybYIxY5WQ8LaXukT2Nr4Wd3ewgFPEx4k4weA1cqFuXjRQ6VxUB6YnbJmL0KHFEiygdMxC5w"
    private let redirectURI = "watchguide://oauth/callback"
    
    // PKCE storage key
    private let pkceVerifierKey = "mdblist_pkce_verifier"
    
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
    
    // MARK: - PKCE Helper Methods
    
    /// Generate a random code verifier for PKCE
    private nonisolated func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    /// Generate code challenge from verifier using SHA256
    private nonisolated func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - OAuth 2.0 Flow with PKCE
    
    /// Generate the OAuth authorization URL with PKCE challenge (nonisolated for sync access from UI)
    nonisolated func getAuthorizationURL() -> URL? {
        // Generate PKCE code verifier and challenge
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        // Store the verifier for later use during token exchange
        UserDefaults.standard.set(codeVerifier, forKey: pkceVerifierKey)
        
        // MDBList OAuth authorize endpoint (without trailing slash)
        var components = URLComponents(string: "\(oauthBaseURL)/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components?.url
    }
    
    /// Exchange authorization code for access token (with PKCE verifier)
    func exchangeCodeForToken(code: String) async throws {
        // MDBList OAuth token endpoint (without trailing slash)
        guard let url = URL(string: "\(oauthBaseURL)/token") else {
            throw MDBListError.invalidURL
        }
        
        // Retrieve the stored code verifier
        guard let codeVerifier = UserDefaults.standard.string(forKey: pkceVerifierKey) else {
            print("MDBList Error: No code verifier found")
            throw MDBListError.authenticationFailed
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Build form-encoded body - order matters for some OAuth servers
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code_verifier", value: codeVerifier)
        ]
        
        // Get the query string without the leading "?"
        request.httpBody = bodyComponents.query?.data(using: .utf8)
        
        // Debug logging for request
        print("MDBList Token Request URL: \(url)")
        print("MDBList Token Request Body: \(bodyComponents.query ?? "nil")")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Clear the stored verifier after use
        UserDefaults.standard.removeObject(forKey: pkceVerifierKey)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MDBListError.authenticationFailed
        }
        
        // Debug logging
        if let responseString = String(data: data, encoding: .utf8) {
            print("MDBList Token Response (\(httpResponse.statusCode)): \(responseString)")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Parse error response for more details
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let errorDesc = errorJson["error_description"] as? String ?? errorJson["error"] as? String ?? "Unknown error"
                print("MDBList OAuth Error: \(errorDesc)")
            }
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
