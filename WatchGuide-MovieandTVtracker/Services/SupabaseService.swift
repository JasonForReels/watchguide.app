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
        if let userId = userId, !userId.isEmpty {
            return userId
        }
        // Fallback to device ID for anonymous sync
        return deviceId
    }
    
    // Check if user is authenticated
    private func isAuthenticated() async -> Bool {
        await MainActor.run {
            AuthService.shared.isAuthenticated
        }
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
        
        // Validate syncId is not empty
        guard !currentSyncId.isEmpty else {
            throw SupabaseError.apiError("User ID is empty. Please sign in or try again.")
        }
        
        // First, delete all existing items for this user/device
        let deleteQuery = [URLQueryItem(name: "device_id", value: "eq.\(currentSyncId)")]
        do {
            try await requestNoResponse(endpoint: "media_items", method: "DELETE", queryItems: deleteQuery)
        } catch {
            print("Warning: Could not delete existing media_items: \(error)")
            // Continue anyway - the table might not exist or be empty
        }
        
        // Upload all items - deduplicate by (list_type, media_id, media_type) to avoid unique constraint violations
        var seenKeys = Set<String>()
        var allItems: [SyncedMediaItem] = []
        
        for item in wantToWatch {
            let key = "\(SyncListType.wantToWatch.rawValue)-\(item.mediaId)-\(item.mediaType.rawValue)"
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            
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
            let key = "\(SyncListType.watched.rawValue)-\(item.mediaId)-\(item.mediaType.rawValue)"
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            
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
            let key = "\(SyncListType.liked.rawValue)-\(item.mediaId)-\(item.mediaType.rawValue)"
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            
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
    
    // MARK: - User Settings Sync
    
    /// Upload user settings to cloud
    func uploadSettings(_ settings: UserSettings) async throws {
        let currentSyncId = await getSyncId()
        guard !currentSyncId.isEmpty else {
            throw SupabaseError.apiError("User ID is empty.")
        }
        
        let syncSettings = SyncedUserSettings(
            userId: currentSyncId,
            region: settings.region,
            preferredLanguage: settings.preferredLanguage,
            includeAdult: settings.includeAdult,
            autoPlayTrailers: settings.autoPlayTrailers,
            autoPlayTrailersMuted: settings.autoPlayTrailersMuted,
            compactMode: settings.compactMode,
            ambientModeEnabled: settings.ambientModeEnabled,
            heroCarouselSource: settings.heroCarouselSource.rawValue,
            isKidsProfile: settings.isKidsProfile,
            parentPasscode: settings.parentPasscode,
            updatedAt: Date()
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(syncSettings)
        
        // Upsert (insert or update on conflict)
        guard var components = URLComponents(string: "\(supabaseURL)/rest/v1/user_settings") else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id")]
        
        guard let url = components.url else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let token = await getAccessToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.addValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorStr = String(data: data, encoding: .utf8) ?? "Unknown"
            throw SupabaseError.apiError("Settings upload failed: \(errorStr)")
        }
    }
    
    /// Download user settings from cloud
    func downloadSettings() async throws -> UserSettings? {
        let currentSyncId = await getSyncId()
        let queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(currentSyncId)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        
        let items: [SyncedUserSettings] = try await request(endpoint: "user_settings", queryItems: queryItems)
        guard let synced = items.first else { return nil }
        
        var settings = UserSettings()
        settings.region = synced.region ?? settings.region
        settings.preferredLanguage = synced.preferredLanguage ?? settings.preferredLanguage
        settings.includeAdult = synced.includeAdult ?? false
        settings.autoPlayTrailers = synced.autoPlayTrailers ?? false
        settings.autoPlayTrailersMuted = synced.autoPlayTrailersMuted ?? true
        settings.compactMode = synced.compactMode ?? false
        settings.ambientModeEnabled = synced.ambientModeEnabled ?? false
        if let source = synced.heroCarouselSource, let heroSource = HeroCarouselSource(rawValue: source) {
            settings.heroCarouselSource = heroSource
        }
        settings.isKidsProfile = synced.isKidsProfile ?? false
        settings.parentPasscode = synced.parentPasscode
        return settings
    }
    
    // MARK: - Custom Lists Sync
    
    /// Upload custom lists to cloud
    func uploadCustomLists(_ lists: [CustomList]) async throws {
        let currentSyncId = await getSyncId()
        guard !currentSyncId.isEmpty else {
            throw SupabaseError.apiError("User ID is empty.")
        }
        
        // Delete existing
        let deleteQuery = [URLQueryItem(name: "user_id", value: "eq.\(currentSyncId)")]
        do {
            try await requestNoResponse(endpoint: "custom_lists", method: "DELETE", queryItems: deleteQuery)
        } catch { print("Warning: Could not delete existing custom_lists: \(error)") }
        do {
            try await requestNoResponse(endpoint: "custom_list_items", method: "DELETE", queryItems: deleteQuery)
        } catch { print("Warning: Could not delete existing custom_list_items: \(error)") }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        for list in lists {
            let syncList = SyncedCustomList(
                userId: currentSyncId,
                listId: list.id,
                name: list.name,
                description: list.description,
                iconName: list.iconName,
                displayStyle: list.displayStyle.rawValue,
                createdAt: list.createdAt,
                updatedAt: list.updatedAt
            )
            
            let body = try encoder.encode([syncList])
            try await requestNoResponse(endpoint: "custom_lists", method: "POST", body: body)
            
            // Upload list items
            if !list.items.isEmpty {
                let syncItems = list.items.enumerated().map { index, item in
                    SyncedCustomListItem(
                        userId: currentSyncId,
                        listId: list.id,
                        mediaId: item.mediaId,
                        mediaType: item.mediaType.rawValue,
                        title: item.title,
                        posterPath: item.posterPath,
                        backdropPath: item.backdropPath,
                        year: item.year,
                        voteAverage: item.voteAverage,
                        overview: item.overview,
                        sortOrder: index,
                        addedAt: item.addedAt
                    )
                }
                
                let itemsBody = try encoder.encode(syncItems)
                try await requestNoResponse(endpoint: "custom_list_items", method: "POST", body: itemsBody)
            }
        }
    }
    
    /// Download custom lists from cloud
    func downloadCustomLists() async throws -> [CustomList] {
        let currentSyncId = await getSyncId()
        
        let listQuery = [
            URLQueryItem(name: "user_id", value: "eq.\(currentSyncId)"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ]
        let lists: [SyncedCustomList] = try await request(endpoint: "custom_lists", queryItems: listQuery)
        
        let itemsQuery = [
            URLQueryItem(name: "user_id", value: "eq.\(currentSyncId)"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ]
        let allItems: [SyncedCustomListItem] = try await request(endpoint: "custom_list_items", queryItems: itemsQuery)
        
        let itemsByList = Dictionary(grouping: allItems, by: { $0.listId })
        
        return lists.map { list in
            var customList = CustomList(name: list.name, description: list.description, iconName: list.iconName ?? "folder.fill", displayStyle: CustomList.DisplayStyle(rawValue: list.displayStyle ?? "row") ?? .row)
            // Override the auto-generated ID with the synced one
            customList = CustomList(
                id: list.listId,
                name: list.name,
                description: list.description,
                iconName: list.iconName ?? "folder.fill",
                displayStyle: CustomList.DisplayStyle(rawValue: list.displayStyle ?? "row") ?? .row,
                items: itemsByList[list.listId]?.compactMap { item in
                    guard let mediaType = MediaType(rawValue: item.mediaType) else { return nil }
                    return SavedMediaItem(
                        id: "\(item.mediaType)-\(item.mediaId)",
                        mediaId: item.mediaId,
                        mediaType: mediaType,
                        title: item.title,
                        posterPath: item.posterPath,
                        backdropPath: item.backdropPath,
                        year: item.year,
                        voteAverage: item.voteAverage,
                        overview: item.overview,
                        addedAt: item.addedAt ?? Date()
                    )
                } ?? [],
                createdAt: list.createdAt ?? Date(),
                updatedAt: list.updatedAt ?? Date()
            )
            return customList
        }
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
enum SyncListType: String, CaseIterable {
    case wantToWatch = "want_to_watch"
    case watched = "watched"
    case liked = "liked"
    
    // Validate that a string matches expected list types
    static func isValid(_ value: String) -> Bool {
        return Self.allCases.contains { $0.rawValue == value }
    }
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

// MARK: - Synced User Settings
struct SyncedUserSettings: Codable {
    let userId: String
    let region: String?
    let preferredLanguage: String?
    let includeAdult: Bool?
    let autoPlayTrailers: Bool?
    let autoPlayTrailersMuted: Bool?
    let compactMode: Bool?
    let ambientModeEnabled: Bool?
    let heroCarouselSource: String?
    let isKidsProfile: Bool?
    let parentPasscode: String?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case region
        case preferredLanguage = "preferred_language"
        case includeAdult = "include_adult"
        case autoPlayTrailers = "auto_play_trailers"
        case autoPlayTrailersMuted = "auto_play_trailers_muted"
        case compactMode = "compact_mode"
        case ambientModeEnabled = "ambient_mode_enabled"
        case heroCarouselSource = "hero_carousel_source"
        case isKidsProfile = "is_kids_profile"
        case parentPasscode = "parent_passcode"
        case updatedAt = "updated_at"
    }
}

// MARK: - Synced Custom List
struct SyncedCustomList: Codable {
    let userId: String
    let listId: String
    let name: String
    let description: String?
    let iconName: String?
    let displayStyle: String?
    let createdAt: Date?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case listId = "list_id"
        case name, description
        case iconName = "icon_name"
        case displayStyle = "display_style"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Synced Custom List Item
struct SyncedCustomListItem: Codable {
    let userId: String
    let listId: String
    let mediaId: Int
    let mediaType: String
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let year: String?
    let voteAverage: Double?
    let overview: String?
    let sortOrder: Int
    let addedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case listId = "list_id"
        case mediaId = "media_id"
        case mediaType = "media_type"
        case title
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case year
        case voteAverage = "vote_average"
        case overview
        case sortOrder = "sort_order"
        case addedAt = "added_at"
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

// MARK: - Extension to CustomList for Supabase compatibility
extension CustomList {
    init(id: String, name: String, description: String?, iconName: String, displayStyle: DisplayStyle, items: [SavedMediaItem], createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.displayStyle = displayStyle
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
