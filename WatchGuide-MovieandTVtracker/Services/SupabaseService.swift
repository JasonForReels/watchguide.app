//
//  SupabaseService.swift
//  WatchGuide-MovieandTVtracker
//
//  Cloud sync service using Supabase
//

import Foundation

actor SupabaseService {
    static let shared = SupabaseService()
    
    private var supabaseURL: String {
        ApiKeyManager.shared.get(key: "SUPABASE_URL") ?? ""
    }
    
    private var supabaseAnonKey: String {
        ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY") ?? ""
    }
    
    private init() {}
    
    var isConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
    
    // MARK: - User ID for sync (prefer authenticated user, fallback to device ID)
    private func getSyncId() async -> String {
        // If user is authenticated, use their user ID for true cross-device sync
        let userId: String? = await MainActor.run {
            AuthService.shared.userId
        }
        if let userId = userId {
            return userId
        }
        // Fallback to device ID for anonymous sync
        return deviceId
    }
    
    // Access token for authenticated requests
    private func getAccessToken() async -> String? {
        await MainActor.run {
            AuthService.shared.accessToken
        }
    }
    
    // MARK: - Device ID for anonymous sync
    private var deviceId: String {
        if let existingId = UserDefaults.standard.string(forKey: "supabase_device_id") {
            return existingId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "supabase_device_id")
        return newId
    }
    
    // MARK: - Generic Request
    private func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        guard isConfigured else {
            throw SupabaseError.notConfigured
        }
        
        var components = URLComponents(string: "\(supabaseURL)/rest/v1/\(endpoint)")!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        // Use access token if authenticated, otherwise use anon key
        if let token = await getAccessToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.addValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }
        
        request.addValue("return=representation", forHTTPHeaderField: "Prefer")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        // Debug logging
        if let responseString = String(data: data, encoding: .utf8) {
            print("Supabase Response (\(httpResponse.statusCode)): \(responseString)")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                throw SupabaseError.apiError("Error \(httpResponse.statusCode): \(errorString)")
            }
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
    
    private func requestNoResponse(
        endpoint: String,
        method: String = "POST",
        body: Data? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws {
        guard isConfigured else {
            throw SupabaseError.notConfigured
        }
        
        var components = URLComponents(string: "\(supabaseURL)/rest/v1/\(endpoint)")!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        // Use access token if authenticated, otherwise use anon key
        if let token = await getAccessToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.addValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                throw SupabaseError.apiError("Error \(httpResponse.statusCode): \(errorString)")
            }
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Sync Media Items
    
    /// Fetch all items from a specific list type
    func fetchItems(listType: SyncListType) async throws -> [SyncedMediaItem] {
        let currentSyncId = await getSyncId()
        let queryItems = [
            URLQueryItem(name: "device_id", value: "eq.\(currentSyncId)"),
            URLQueryItem(name: "list_type", value: "eq.\(listType.rawValue)"),
            URLQueryItem(name: "order", value: "added_at.desc")
        ]
        
        return try await request(endpoint: "media_items", queryItems: queryItems)
    }
    
    /// Add an item to a list
    func addItem(_ item: SavedMediaItem, listType: SyncListType) async throws {
        let currentSyncId = await getSyncId()
        let syncItem = SyncedMediaItem(
            id: nil,
            deviceId: currentSyncId,
            listType: listType.rawValue,
            mediaId: item.mediaId,
            mediaType: item.mediaType.rawValue,
            title: item.title,
            posterPath: item.posterPath,
            backdropPath: item.backdropPath,
            year: item.year,
            voteAverage: item.voteAverage,
            overview: item.overview,
            addedAt: item.addedAt
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(syncItem)
        
        try await requestNoResponse(endpoint: "media_items", method: "POST", body: body)
    }
    
    /// Remove an item from a list
    func removeItem(mediaId: Int, mediaType: MediaType, listType: SyncListType) async throws {
        let currentSyncId = await getSyncId()
        let queryItems = [
            URLQueryItem(name: "device_id", value: "eq.\(currentSyncId)"),
            URLQueryItem(name: "list_type", value: "eq.\(listType.rawValue)"),
            URLQueryItem(name: "media_id", value: "eq.\(mediaId)"),
            URLQueryItem(name: "media_type", value: "eq.\(mediaType.rawValue)")
        ]
        
        try await requestNoResponse(endpoint: "media_items", method: "DELETE", queryItems: queryItems)
    }
    
    /// Sync all local data to cloud (full upload)
    func uploadAllData(
        wantToWatch: [SavedMediaItem],
        watched: [SavedMediaItem],
        liked: [SavedMediaItem]
    ) async throws {
        let currentSyncId = await getSyncId()
        
        // First, delete all existing items for this user/device
        let deleteQuery = [URLQueryItem(name: "device_id", value: "eq.\(currentSyncId)")]
        try await requestNoResponse(endpoint: "media_items", method: "DELETE", queryItems: deleteQuery)
        
        // Upload all items
        var allItems: [SyncedMediaItem] = []
        
        for item in wantToWatch {
            allItems.append(SyncedMediaItem(
                id: nil,
                deviceId: currentSyncId,
                listType: SyncListType.wantToWatch.rawValue,
                mediaId: item.mediaId,
                mediaType: item.mediaType.rawValue,
                title: item.title,
                posterPath: item.posterPath,
                backdropPath: item.backdropPath,
                year: item.year,
                voteAverage: item.voteAverage,
                overview: item.overview,
                addedAt: item.addedAt
            ))
        }
        
        for item in watched {
            allItems.append(SyncedMediaItem(
                id: nil,
                deviceId: currentSyncId,
                listType: SyncListType.watched.rawValue,
                mediaId: item.mediaId,
                mediaType: item.mediaType.rawValue,
                title: item.title,
                posterPath: item.posterPath,
                backdropPath: item.backdropPath,
                year: item.year,
                voteAverage: item.voteAverage,
                overview: item.overview,
                addedAt: item.addedAt
            ))
        }
        
        for item in liked {
            allItems.append(SyncedMediaItem(
                id: nil,
                deviceId: currentSyncId,
                listType: SyncListType.liked.rawValue,
                mediaId: item.mediaId,
                mediaType: item.mediaType.rawValue,
                title: item.title,
                posterPath: item.posterPath,
                backdropPath: item.backdropPath,
                year: item.year,
                voteAverage: item.voteAverage,
                overview: item.overview,
                addedAt: item.addedAt
            ))
        }
        
        if !allItems.isEmpty {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let body = try encoder.encode(allItems)
            
            try await requestNoResponse(endpoint: "media_items", method: "POST", body: body)
        }
    }
    
    /// Download all data from cloud (full download)
    func downloadAllData() async throws -> (wantToWatch: [SavedMediaItem], watched: [SavedMediaItem], liked: [SavedMediaItem]) {
        let currentSyncId = await getSyncId()
        let queryItems = [
            URLQueryItem(name: "device_id", value: "eq.\(currentSyncId)"),
            URLQueryItem(name: "order", value: "added_at.desc")
        ]
        
        let items: [SyncedMediaItem] = try await request(endpoint: "media_items", queryItems: queryItems)
        
        var wantToWatch: [SavedMediaItem] = []
        var watched: [SavedMediaItem] = []
        var liked: [SavedMediaItem] = []
        
        for item in items {
            guard let savedItem = item.toSavedMediaItem() else { continue }
            
            switch item.listType {
            case SyncListType.wantToWatch.rawValue:
                wantToWatch.append(savedItem)
            case SyncListType.watched.rawValue:
                watched.append(savedItem)
            case SyncListType.liked.rawValue:
                liked.append(savedItem)
            default:
                break
            }
        }
        
        return (wantToWatch, watched, liked)
    }
    
    /// Get last sync timestamp
    func getLastSyncTime() -> Date? {
        UserDefaults.standard.object(forKey: "supabase_last_sync") as? Date
    }
    
    /// Update last sync timestamp
    func updateLastSyncTime() {
        UserDefaults.standard.set(Date(), forKey: "supabase_last_sync")
    }
}

// MARK: - Sync List Type
enum SyncListType: String {
    case wantToWatch = "want_to_watch"
    case watched = "watched"
    case liked = "liked"
}

// MARK: - Synced Media Item (Supabase table model)
struct SyncedMediaItem: Codable {
    let id: Int?
    let deviceId: String
    let listType: String
    let mediaId: Int
    let mediaType: String
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let year: String?
    let voteAverage: Double?
    let overview: String?
    let addedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case listType = "list_type"
        case mediaId = "media_id"
        case mediaType = "media_type"
        case title
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case year
        case voteAverage = "vote_average"
        case overview
        case addedAt = "added_at"
    }
    
    func toSavedMediaItem() -> SavedMediaItem? {
        guard let type = MediaType(rawValue: mediaType) else { return nil }
        
        return SavedMediaItem(
            id: "\(mediaType)-\(mediaId)",
            mediaId: mediaId,
            mediaType: type,
            title: title,
            posterPath: posterPath,
            backdropPath: backdropPath,
            year: year,
            voteAverage: voteAverage,
            overview: overview,
            addedAt: addedAt
        )
    }
}

// MARK: - Errors
enum SupabaseError: LocalizedError {
    case notConfigured
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case syncFailed
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured. Please link a Supabase project."
        case .invalidResponse:
            return "Invalid response from Supabase"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return message
        case .syncFailed:
            return "Sync failed. Please try again."
        }
    }
}

// MARK: - Extension to SavedMediaItem for Supabase compatibility
extension SavedMediaItem {
    init(id: String, mediaId: Int, mediaType: MediaType, title: String, posterPath: String?, backdropPath: String?, year: String?, voteAverage: Double?, overview: String?, addedAt: Date) {
        self.id = id
        self.mediaId = mediaId
        self.mediaType = mediaType
        self.title = title
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.year = year
        self.voteAverage = voteAverage
        self.overview = overview
        self.addedAt = addedAt
    }
}
