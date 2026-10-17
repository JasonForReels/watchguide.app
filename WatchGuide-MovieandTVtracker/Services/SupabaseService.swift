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
        // Postgres (and the web app) may send fractional seconds, which .iso8601 rejects.
        decoder.dateDecodingStrategy = .custom { d in
            let str = try d.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            let frac = ISO8601DateFormatter()
            frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = plain.date(from: str) ?? frac.date(from: str) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Bad date \(str)"))
        }
        return try decoder.decode(T.self, from: data)
    }
    
    private func requestNoResponse(
        endpoint: String,
        method: String = "POST",
        body: Data? = nil,
        queryItems: [URLQueryItem] = [],
        prefer: String? = nil
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
        
        if let prefer { request.addValue(prefer, forHTTPHeaderField: "Prefer") }
        
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
    
    // MARK: - Per-user list tables (shared with the web app)
    // user_list_items / user_custom_lists / user_custom_list_items, locked by RLS to user_id = auth.uid().
    // Uploads insert only what the account is missing and delete only what the person removed.

    /// The signed-in account id. These tables are per account, so there is no device-ID fallback.
    private func requireUserId() async throws -> String {
        let authed = await isAuthenticated()
        let id: String? = await MainActor.run { AuthService.shared.userId }
        guard authed, let id, !id.isEmpty else {
            throw SupabaseError.apiError("Sign in to sync your lists.")
        }
        return id
    }

    private static let pageSize = 1000

    private func fetchAll<T: Decodable>(_ table: String, userId: String, order: String) async throws -> [T] {
        var out: [T] = []
        var offset = 0
        while true {
            let page: [T] = try await request(endpoint: table, queryItems: [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "order", value: order),
                URLQueryItem(name: "limit", value: String(Self.pageSize)),
                URLQueryItem(name: "offset", value: String(offset))
            ])
            out.append(contentsOf: page)
            if page.count < Self.pageSize { break }
            offset += Self.pageSize
        }
        return out
    }

    /// Insert rows, silently skipping ones the account already has.
    private func insertMissing<E: Encodable>(_ table: String, _ rows: [E]) async throws {
        guard !rows.isEmpty else { return }
        let body = try Self.encoder.encode(rows)
        try await requestNoResponse(endpoint: table, method: "POST", body: body, prefer: "resolution=ignore-duplicates,return=minimal")
    }

    /// Whole-second ISO8601 (no fractions) so the web app and older decoders read it.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private func syncedItem(_ item: SavedMediaItem, userId: String, listType: SyncListType) -> SyncedMediaItem {
        SyncedMediaItem(
            userId: userId, listType: listType.rawValue, mediaId: item.mediaId, mediaType: item.mediaType.rawValue,
            title: item.title, posterPath: item.posterPath, backdropPath: item.backdropPath, year: item.year,
            releaseDate: item.releaseDate, voteAverage: item.voteAverage, overview: item.overview, addedAt: item.addedAt
        )
    }

    /// Add an item to a list
    func addItem(_ item: SavedMediaItem, listType: SyncListType) async throws {
        let userId = try await requireUserId()
        try await insertMissing("user_list_items", [syncedItem(item, userId: userId, listType: listType)])
    }

    /// Remove an item from a list
    func removeItem(mediaId: Int, mediaType: MediaType, listType: SyncListType) async throws {
        let userId = try await requireUserId()
        try await requestNoResponse(endpoint: "user_list_items", method: "DELETE", queryItems: [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "list_type", value: "eq.\(listType.rawValue)"),
            URLQueryItem(name: "media_id", value: "eq.\(mediaId)"),
            URLQueryItem(name: "media_type", value: "eq.\(mediaType.rawValue)")
        ])
    }

    /// Push local titles the account doesn't have yet. Never deletes: removals go through `removeItem`.
    func uploadAllData(
        wantToWatch: [SavedMediaItem],
        watched: [SavedMediaItem],
        liked: [SavedMediaItem]
    ) async throws {
        let userId = try await requireUserId()
        let remote: [SyncedMediaItem] = try await fetchAll("user_list_items", userId: userId, order: "list_type.asc,media_type.asc,media_id.asc")
        var have = Set(remote.map { "\($0.listType)-\($0.mediaType)-\($0.mediaId)" })

        var missing: [SyncedMediaItem] = []
        for (items, type) in [(wantToWatch, SyncListType.wantToWatch), (watched, .watched), (liked, .liked)] {
            for item in items {
                let key = "\(type.rawValue)-\(item.mediaType.rawValue)-\(item.mediaId)"
                guard have.insert(key).inserted else { continue }
                missing.append(syncedItem(item, userId: userId, listType: type))
            }
        }
        for start in stride(from: 0, to: missing.count, by: 500) {
            try await insertMissing("user_list_items", Array(missing[start..<min(start + 500, missing.count)]))
        }
    }

    /// Download all data from cloud (full download)
    func downloadAllData() async throws -> (wantToWatch: [SavedMediaItem], watched: [SavedMediaItem], liked: [SavedMediaItem]) {
        let userId = try await requireUserId()
        let items: [SyncedMediaItem] = try await fetchAll("user_list_items", userId: userId, order: "added_at.desc,media_id.asc")

        var wantToWatch: [SavedMediaItem] = []
        var watched: [SavedMediaItem] = []
        var liked: [SavedMediaItem] = []

        for item in items {
            guard let savedItem = item.toSavedMediaItem() else { continue }
            switch item.listType {
            case SyncListType.wantToWatch.rawValue: wantToWatch.append(savedItem)
            case SyncListType.watched.rawValue: watched.append(savedItem)
            case SyncListType.liked.rawValue: liked.append(savedItem)
            default: break
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
            showTrailersInMediaDetail: settings.showTrailersInMediaDetail,
            trailerAddons: settings.trailerAddons,
            compactMode: settings.compactMode,
            ambientModeEnabled: settings.ambientModeEnabled,
            heroCarouselSource: settings.heroCarouselSource.rawValue,
            heroCarouselCustomMovieListId: settings.heroCarouselCustomMovieListId,
            heroCarouselCustomShowListId: settings.heroCarouselCustomShowListId,
            heroCarouselMDBListMovieId: settings.heroCarouselMDBListMovieId,
            heroCarouselMDBListShowId: settings.heroCarouselMDBListShowId,
            isKidsProfile: settings.isKidsProfile,
            parentPasscode: settings.parentPasscode,
            streamqServiceIds: settings.streamqServiceIds,
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
        settings.autoPlayTrailers = synced.autoPlayTrailers ?? true
        settings.autoPlayTrailersMuted = synced.autoPlayTrailersMuted ?? true
        settings.showTrailersInMediaDetail = synced.showTrailersInMediaDetail ?? true
        settings.trailerAddons = synced.trailerAddons ?? settings.trailerAddons
        settings.compactMode = synced.compactMode ?? false
        settings.ambientModeEnabled = synced.ambientModeEnabled ?? false
        if let source = synced.heroCarouselSource, let heroSource = HeroCarouselSource(rawValue: source) {
            settings.heroCarouselSource = heroSource
        }
        settings.heroCarouselCustomMovieListId = synced.heroCarouselCustomMovieListId
        settings.heroCarouselCustomShowListId = synced.heroCarouselCustomShowListId
        settings.heroCarouselMDBListMovieId = synced.heroCarouselMDBListMovieId
        settings.heroCarouselMDBListShowId = synced.heroCarouselMDBListShowId
        settings.isKidsProfile = synced.isKidsProfile ?? false
        settings.parentPasscode = synced.parentPasscode
        settings.streamqServiceIds = synced.streamqServiceIds ?? []
        return settings
    }
    
    // MARK: - Custom Lists Sync

    /// What the account held at the last successful custom-list sync: list id (lowercased) -> title keys.
    /// A list or title that is in here but gone locally was removed by the person, so it is deleted remotely.
    private static let customBaseKey = "supabase_custom_lists_base"

    private func loadCustomBase() -> [String: [String]]? {
        UserDefaults.standard.dictionary(forKey: Self.customBaseKey) as? [String: [String]]
    }

    /// Upload custom lists: create missing lists, add missing titles, delete only what the person removed.
    func uploadCustomLists(_ lists: [CustomList]) async throws {
        let userId = try await requireUserId()

        let remoteLists: [SyncedCustomList] = try await fetchAll("user_custom_lists", userId: userId, order: "created_at.asc,list_id.asc")
        let remoteItems: [SyncedCustomListItem] = remoteLists.isEmpty ? [] :
            try await fetchAll("user_custom_list_items", userId: userId, order: "list_id.asc,media_type.asc,media_id.asc")

        let base = loadCustomBase()
        let remoteById = Dictionary(remoteLists.map { ($0.listId.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let itemsByList = Dictionary(grouping: remoteItems, by: { $0.listId.lowercased() })
        var newBase: [String: [String]] = [:]
        var seen = Set<String>()

        for list in lists {
            let lid = list.id.lowercased()
            seen.insert(lid)

            guard let remote = remoteById[lid] else {
                if base?[lid] != nil { continue }  // deleted on the account since the last sync
                try await insertMissing("user_custom_lists", [SyncedCustomList(
                    userId: userId, listId: list.id, name: list.name, description: list.description,
                    iconName: list.iconName, displayStyle: list.displayStyle.rawValue,
                    createdAt: list.createdAt, updatedAt: list.updatedAt
                )])
                try await insertMissing("user_custom_list_items", customRows(list, userId: userId, only: nil, firstSort: 0))
                newBase[lid] = list.items.map(\.id)
                continue
            }

            let remoteRows = itemsByList[lid] ?? []
            let remoteKeys = Set(remoteRows.map { "\($0.mediaType)-\($0.mediaId)" })
            let localKeys = Set(list.items.map(\.id))
            let baseKeys = Set(base?[lid] ?? [])

            // Name changed here since the last sync -> push it (only name/updated_at; icon etc. stay).
            if base?[lid] != nil, remote.name != list.name, baseName(for: lid) == remote.name {
                try await requestNoResponse(endpoint: "user_custom_lists", method: "PATCH", body: try Self.encoder.encode(["name": list.name, "updated_at": isoNow()]), queryItems: [
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                    URLQueryItem(name: "list_id", value: "eq.\(remote.listId)")
                ])
            }

            let toAdd = Set(localKeys.subtracting(remoteKeys).subtracting(baseKeys))
            let toRemove = remoteKeys.intersection(baseKeys).subtracting(localKeys)
            let firstSort = (remoteRows.map(\.sortOrder).max() ?? -1) + 1
            try await insertMissing("user_custom_list_items", customRows(list, userId: userId, only: toAdd, firstSort: firstSort))
            for row in remoteRows where toRemove.contains("\(row.mediaType)-\(row.mediaId)") {
                try await requestNoResponse(endpoint: "user_custom_list_items", method: "DELETE", queryItems: [
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                    URLQueryItem(name: "list_id", value: "eq.\(remote.listId)"),
                    URLQueryItem(name: "media_type", value: "eq.\(row.mediaType)"),
                    URLQueryItem(name: "media_id", value: "eq.\(row.mediaId)")
                ])
            }
            newBase[lid] = Array(remoteKeys.subtracting(toRemove).union(toAdd))
        }

        // Lists the account has that this device doesn't: removed here if the base knew them, else new from elsewhere.
        for remote in remoteLists {
            let lid = remote.listId.lowercased()
            guard !seen.contains(lid) else { continue }
            if base?[lid] != nil {
                try await requestNoResponse(endpoint: "user_custom_list_items", method: "DELETE", queryItems: [
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"), URLQueryItem(name: "list_id", value: "eq.\(remote.listId)")
                ])
                try await requestNoResponse(endpoint: "user_custom_lists", method: "DELETE", queryItems: [
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"), URLQueryItem(name: "list_id", value: "eq.\(remote.listId)")
                ])
            } else {
                newBase[lid] = (itemsByList[lid] ?? []).map { "\($0.mediaType)-\($0.mediaId)" }
            }
        }

        UserDefaults.standard.set(newBase, forKey: Self.customBaseKey)
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: remoteLists.map { ($0.listId.lowercased(), $0.name) }).merging(
            lists.map { ($0.id.lowercased(), $0.name) }, uniquingKeysWith: { _, new in new }), forKey: Self.customBaseKey + "_names")
    }

    private func baseName(for lid: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: Self.customBaseKey + "_names") as? [String: String])?[lid]
    }

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func customRows(_ list: CustomList, userId: String, only: Set<String>?, firstSort: Int) -> [SyncedCustomListItem] {
        var rows: [SyncedCustomListItem] = []
        for item in list.items where only?.contains(item.id) ?? true {
            rows.append(SyncedCustomListItem(
                userId: userId, listId: list.id, mediaId: item.mediaId, mediaType: item.mediaType.rawValue,
                title: item.title, posterPath: item.posterPath, backdropPath: item.backdropPath, year: item.year,
                releaseDate: item.releaseDate, voteAverage: item.voteAverage, overview: item.overview,
                sortOrder: firstSort + rows.count, addedAt: item.addedAt
            ))
        }
        return rows
    }

    /// Download custom lists from cloud
    func downloadCustomLists() async throws -> [CustomList] {
        let userId = try await requireUserId()
        let lists: [SyncedCustomList] = try await fetchAll("user_custom_lists", userId: userId, order: "created_at.asc,list_id.asc")
        let allItems: [SyncedCustomListItem] = lists.isEmpty ? [] :
            try await fetchAll("user_custom_list_items", userId: userId, order: "list_id.asc,sort_order.asc")
        let itemsByList = Dictionary(grouping: allItems, by: { $0.listId })

        let result = lists.map { list in
            CustomList(
                id: list.listId,
                name: list.name,
                description: list.description,
                iconName: list.iconName ?? "folder.fill",
                displayStyle: CustomList.DisplayStyle(rawValue: list.displayStyle ?? "row") ?? .row,
                items: (itemsByList[list.listId] ?? []).sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }.compactMap { item in
                    guard let mediaType = MediaType(rawValue: item.mediaType) else { return nil }
                    return SavedMediaItem(
                        id: "\(item.mediaType)-\(item.mediaId)", mediaId: item.mediaId, mediaType: mediaType,
                        title: item.title, posterPath: item.posterPath, backdropPath: item.backdropPath,
                        year: item.year, releaseDate: item.releaseDate, voteAverage: item.voteAverage,
                        overview: item.overview, addedAt: item.addedAt ?? Date()
                    )
                },
                createdAt: list.createdAt ?? Date(),
                updatedAt: list.updatedAt ?? Date()
            )
        }
        // What we just read is what the account holds: the next upload's baseline.
        UserDefaults.standard.set(Dictionary(result.map { ($0.id.lowercased(), $0.items.map(\.id)) }, uniquingKeysWith: { a, _ in a }), forKey: Self.customBaseKey)
        UserDefaults.standard.set(Dictionary(result.map { ($0.id.lowercased(), $0.name) }, uniquingKeysWith: { a, _ in a }), forKey: Self.customBaseKey + "_names")
        return result
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
    let userId: String
    let listType: String
    let mediaId: Int
    let mediaType: String
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let year: String?
    let releaseDate: String?
    let voteAverage: Double?
    let overview: String?
    let addedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case listType = "list_type"
        case mediaId = "media_id"
        case mediaType = "media_type"
        case title
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case year
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case overview
        case addedAt = "added_at"
    }
    
    // Explicitly encode all keys (including nil as null) to avoid PGRST102
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(listType, forKey: .listType)
        try container.encode(mediaId, forKey: .mediaId)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(title, forKey: .title)
        try container.encode(posterPath, forKey: .posterPath)
        try container.encode(backdropPath, forKey: .backdropPath)
        try container.encode(year, forKey: .year)
        try container.encode(releaseDate, forKey: .releaseDate)
        try container.encode(voteAverage, forKey: .voteAverage)
        try container.encode(overview, forKey: .overview)
        try container.encode(addedAt, forKey: .addedAt)
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
            releaseDate: releaseDate,
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
    let showTrailersInMediaDetail: Bool?
    let trailerAddons: [TrailerAddon]?
    let compactMode: Bool?
    let ambientModeEnabled: Bool?
    let heroCarouselSource: String?
    let heroCarouselCustomMovieListId: String?
    let heroCarouselCustomShowListId: String?
    let heroCarouselMDBListMovieId: String?
    let heroCarouselMDBListShowId: String?
    let isKidsProfile: Bool?
    let parentPasscode: String?
    let streamqServiceIds: [Int]?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case region
        case preferredLanguage = "preferred_language"
        case includeAdult = "include_adult"
        case autoPlayTrailers = "auto_play_trailers"
        case autoPlayTrailersMuted = "auto_play_trailers_muted"
        case showTrailersInMediaDetail = "show_trailers_in_media_detail"
        case trailerAddons = "trailer_addons"
        case compactMode = "compact_mode"
        case ambientModeEnabled = "ambient_mode_enabled"
        case heroCarouselSource = "hero_carousel_source"
        case heroCarouselCustomMovieListId = "hero_carousel_custom_movie_list_id"
        case heroCarouselCustomShowListId = "hero_carousel_custom_show_list_id"
        case heroCarouselMDBListMovieId = "hero_carousel_mdblist_movie_id"
        case heroCarouselMDBListShowId = "hero_carousel_mdblist_show_id"
        case isKidsProfile = "is_kids_profile"
        case parentPasscode = "parent_passcode"
        case streamqServiceIds = "streamq_service_ids"
        case updatedAt = "updated_at"
    }
    
    // Explicitly encode all keys (including nil as null) to avoid PGRST102
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(region, forKey: .region)
        try container.encode(preferredLanguage, forKey: .preferredLanguage)
        try container.encode(includeAdult, forKey: .includeAdult)
        try container.encode(autoPlayTrailers, forKey: .autoPlayTrailers)
        try container.encode(autoPlayTrailersMuted, forKey: .autoPlayTrailersMuted)
        try container.encode(showTrailersInMediaDetail, forKey: .showTrailersInMediaDetail)
        try container.encode(trailerAddons, forKey: .trailerAddons)
        try container.encode(compactMode, forKey: .compactMode)
        try container.encode(ambientModeEnabled, forKey: .ambientModeEnabled)
        try container.encode(heroCarouselSource, forKey: .heroCarouselSource)
        try container.encode(heroCarouselCustomMovieListId, forKey: .heroCarouselCustomMovieListId)
        try container.encode(heroCarouselCustomShowListId, forKey: .heroCarouselCustomShowListId)
        try container.encode(heroCarouselMDBListMovieId, forKey: .heroCarouselMDBListMovieId)
        try container.encode(heroCarouselMDBListShowId, forKey: .heroCarouselMDBListShowId)
        try container.encode(isKidsProfile, forKey: .isKidsProfile)
        try container.encode(parentPasscode, forKey: .parentPasscode)
        try container.encode(streamqServiceIds, forKey: .streamqServiceIds)
        try container.encode(updatedAt, forKey: .updatedAt)
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
    
    // Explicitly encode all keys (including nil as null) to avoid PGRST102
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(listId, forKey: .listId)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(iconName, forKey: .iconName)
        try container.encode(displayStyle, forKey: .displayStyle)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
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
    let releaseDate: String?
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
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case overview
        case sortOrder = "sort_order"
        case addedAt = "added_at"
    }
    
    // Explicitly encode all keys (including nil as null) to avoid PGRST102
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(listId, forKey: .listId)
        try container.encode(mediaId, forKey: .mediaId)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(title, forKey: .title)
        try container.encode(posterPath, forKey: .posterPath)
        try container.encode(backdropPath, forKey: .backdropPath)
        try container.encode(year, forKey: .year)
        try container.encode(releaseDate, forKey: .releaseDate)
        try container.encode(voteAverage, forKey: .voteAverage)
        try container.encode(overview, forKey: .overview)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(addedAt, forKey: .addedAt)
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
