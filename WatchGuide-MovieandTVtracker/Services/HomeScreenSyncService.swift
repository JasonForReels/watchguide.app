//
//  HomeScreenSyncService.swift
//  WatchGuide-MovieandTVtracker
//
//  Service for syncing home screen customization to Supabase
//

import Foundation

actor HomeScreenSyncService {
    static let shared = HomeScreenSyncService()
    
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
    
    // MARK: - User ID
    private func getUserId() async -> String {
        let userId: String? = await MainActor.run {
            AuthService.shared.userId
        }
        if let userId = userId {
            return userId
        }
        // Fallback to device ID - ensure it's stored consistently
        if let existingId = UserDefaults.standard.string(forKey: "supabase_device_id") {
            return existingId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "supabase_device_id")
        return newId
    }
    
    // Check if user is authenticated
    private func isAuthenticated() async -> Bool {
        await MainActor.run {
            AuthService.shared.isAuthenticated
        }
    }
    
    private func getAccessToken() async -> String? {
        await MainActor.run {
            AuthService.shared.accessToken
        }
    }
    
    // MARK: - Generic Request
    private func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        guard isConfigured else {
            throw HomeScreenSyncError.notConfigured
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
            throw HomeScreenSyncError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                throw HomeScreenSyncError.apiError("Error \(httpResponse.statusCode): \(errorString)")
            }
            throw HomeScreenSyncError.httpError(httpResponse.statusCode)
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
            throw HomeScreenSyncError.notConfigured
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
        
        if let token = await getAccessToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.addValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }
        
        // For upsert
        request.addValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HomeScreenSyncError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                throw HomeScreenSyncError.apiError("Error \(httpResponse.statusCode): \(errorString)")
            }
            throw HomeScreenSyncError.httpError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Browse Config Sync
    
    func uploadBrowseConfig(_ rows: [BrowseRowConfig]) async throws {
        let userId = await getUserId()
        
        // Delete existing
        let deleteQuery = [URLQueryItem(name: "user_id", value: "eq.\(userId)")]
        try await requestNoResponse(endpoint: "browse_config", method: "DELETE", queryItems: deleteQuery)
        
        // Upload new
        let syncItems = rows.map { row in
            SyncedBrowseConfig(
                userId: userId,
                rowId: row.id,
                rowType: row.endpoint.rawValue,
                title: row.title,
                isEnabled: row.isEnabled,
                sortOrder: row.sortOrder
            )
        }
        
        if !syncItems.isEmpty {
            let encoder = JSONEncoder()
            let body = try encoder.encode(syncItems)
            try await requestNoResponse(endpoint: "browse_config", method: "POST", body: body)
        }
    }
    
    func downloadBrowseConfig() async throws -> [BrowseRowConfig] {
        let userId = await getUserId()
        let queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ]
        
        let items: [SyncedBrowseConfig] = try await request(endpoint: "browse_config", queryItems: queryItems)
        
        return items.compactMap { item in
            guard let endpoint = BrowseRowConfig.BrowseEndpoint(rawValue: item.rowType) else { return nil }
            return BrowseRowConfig(
                id: item.rowId,
                title: item.title,
                endpoint: endpoint,
                isEnabled: item.isEnabled,
                sortOrder: item.sortOrder
            )
        }
    }
    
    // MARK: - Extension Lists Sync
    
    func uploadExtensionLists(_ lists: [ImportedListItem]) async throws {
        let userId = await getUserId()
        
        // Validate userId is not empty
        guard !userId.isEmpty else {
            throw HomeScreenSyncError.apiError("User ID is empty. Please sign in or try again.")
        }
        
        // Delete existing - wrap in do/catch to continue even if delete fails (table might not exist)
        let deleteQuery = [URLQueryItem(name: "user_id", value: "eq.\(userId)")]
        do {
            try await requestNoResponse(endpoint: "extension_lists", method: "DELETE", queryItems: deleteQuery)
        } catch {
            print("Warning: Could not delete existing extension_lists: \(error)")
        }
        do {
            try await requestNoResponse(endpoint: "extension_list_items", method: "DELETE", queryItems: deleteQuery)
        } catch {
            print("Warning: Could not delete existing extension_list_items: \(error)")
        }
        
        // Upload lists
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        for list in lists {
            // Create a sanitized list ID that replaces problematic characters
            // The list_id should be URL-safe and match database text field requirements
            let sanitizedListId = list.listId
                .replacingOccurrences(of: " ", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Ensure source matches expected values
            let sourceValue = list.source.rawValue
            
            let syncList = SyncedExtensionList(
                userId: userId,
                listId: sanitizedListId,
                name: list.name,
                source: sourceValue,
                customName: list.customName,
                showOnHome: list.showOnHome,
                lastSynced: list.lastSynced,
                createdAt: list.createdAt
            )
            
            let body = try encoder.encode([syncList])
            try await requestNoResponse(endpoint: "extension_lists", method: "POST", body: body)
            
            // Upload list items
            if !list.items.isEmpty {
                let syncItems = list.items.enumerated().map { index, item in
                    SyncedExtensionListItem(
                        userId: userId,
                        listId: sanitizedListId,
                        mediaId: item.mediaId,
                        mediaType: item.mediaType.rawValue,
                        title: item.title,
                        posterPath: item.posterPath,
                        backdropPath: item.backdropPath,
                        year: item.year,
                        voteAverage: item.voteAverage,
                        overview: item.overview,
                        sortOrder: index
                    )
                }
                
                let itemsBody = try encoder.encode(syncItems)
                try await requestNoResponse(endpoint: "extension_list_items", method: "POST", body: itemsBody)
            }
        }
    }
    
    func downloadExtensionLists() async throws -> [ImportedListItem] {
        let userId = await getUserId()
        
        // Fetch lists
        let listQuery = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ]
        let lists: [SyncedExtensionList] = try await request(endpoint: "extension_lists", queryItems: listQuery)
        
        // Fetch all items
        let itemsQuery = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ]
        let allItems: [SyncedExtensionListItem] = try await request(endpoint: "extension_list_items", queryItems: itemsQuery)
        
        // Group items by list
        let itemsByList = Dictionary(grouping: allItems, by: { $0.listId })
        
        return lists.compactMap { list in
            guard let source = ImportedListSource(rawValue: list.source) else { return nil }
            
            var importedList = ImportedListItem(
                name: list.name,
                listId: list.listId,
                showOnHome: list.showOnHome,
                source: source
            )
            importedList.customName = list.customName
            importedList.lastSynced = list.lastSynced
            
            // Add items
            if let listItems = itemsByList[list.listId] {
                importedList.items = listItems.compactMap { item in
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
                        addedAt: Date()
                    )
                }
            }
            
            return importedList
        }
    }
    
    // MARK: - Custom Home Rows Sync
    
    func uploadCustomHomeRows(_ rows: [CustomHomeRow]) async throws {
        let userId = await getUserId()
        
        // Delete existing
        let deleteQuery = [URLQueryItem(name: "user_id", value: "eq.\(userId)")]
        try await requestNoResponse(endpoint: "custom_home_rows", method: "DELETE", queryItems: deleteQuery)
        
        // Upload new
        let syncItems = rows.map { row in
            SyncedCustomHomeRow(
                userId: userId,
                rowId: row.id,
                name: row.name,
                rowType: row.rowType.rawValue,
                importedListId: row.importedListId,
                hubImageUrl: row.hubImageURL,
                isEnabled: row.isEnabled,
                sortOrder: row.sortOrder,
                createdAt: row.createdAt
            )
        }
        
        if !syncItems.isEmpty {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let body = try encoder.encode(syncItems)
            try await requestNoResponse(endpoint: "custom_home_rows", method: "POST", body: body)
        }
    }
    
    func downloadCustomHomeRows() async throws -> [CustomHomeRow] {
        let userId = await getUserId()
        let queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ]
        
        let items: [SyncedCustomHomeRow] = try await request(endpoint: "custom_home_rows", queryItems: queryItems)
        
        return items.compactMap { item in
            guard let rowType = CustomHomeRow.CustomRowType(rawValue: item.rowType) else { return nil }
            
            var row = CustomHomeRow(name: item.name, rowType: rowType, sortOrder: item.sortOrder)
            // Preserve original ID for consistency
            row = CustomHomeRow(
                id: item.rowId,
                name: item.name,
                rowType: rowType,
                sortOrder: item.sortOrder,
                isEnabled: item.isEnabled,
                importedListId: item.importedListId,
                hubImageURL: item.hubImageUrl,
                createdAt: item.createdAt ?? Date()
            )
            return row
        }
    }
    
    // MARK: - Network Hubs Config Sync
    
    func uploadNetworkHubsConfig(_ hubs: [NetworkHub]) async throws {
        let userId = await getUserId()
        
        // Delete existing
        let deleteQuery = [URLQueryItem(name: "user_id", value: "eq.\(userId)")]
        try await requestNoResponse(endpoint: "network_hubs_config", method: "DELETE", queryItems: deleteQuery)
        
        // Upload new
        let syncItems = hubs.map { hub in
            SyncedNetworkHubConfig(
                userId: userId,
                hubId: hub.id,
                isEnabled: hub.isEnabled,
                sortOrder: hub.sortOrder
            )
        }
        
        if !syncItems.isEmpty {
            let encoder = JSONEncoder()
            let body = try encoder.encode(syncItems)
            try await requestNoResponse(endpoint: "network_hubs_config", method: "POST", body: body)
        }
    }
    
    func downloadNetworkHubsConfig() async throws -> [SyncedNetworkHubConfig] {
        let userId = await getUserId()
        let queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ]
        
        return try await request(endpoint: "network_hubs_config", queryItems: queryItems)
    }
    
    // MARK: - Full Sync
    
    func uploadAllHomeScreenConfig(
        browseRows: [BrowseRowConfig],
        extensionLists: [ImportedListItem],
        customHomeRows: [CustomHomeRow],
        networkHubs: [NetworkHub]
    ) async throws {
        try await uploadBrowseConfig(browseRows)
        try await uploadExtensionLists(extensionLists)
        try await uploadCustomHomeRows(customHomeRows)
        try await uploadNetworkHubsConfig(networkHubs)
    }
    
    func downloadAllHomeScreenConfig() async throws -> HomeScreenConfig {
        async let browseRows = downloadBrowseConfig()
        async let extensionLists = downloadExtensionLists()
        async let customHomeRows = downloadCustomHomeRows()
        async let networkHubsConfig = downloadNetworkHubsConfig()
        
        return try await HomeScreenConfig(
            browseRows: browseRows,
            extensionLists: extensionLists,
            customHomeRows: customHomeRows,
            networkHubsConfig: networkHubsConfig
        )
    }
}

// MARK: - Sync Models

struct SyncedBrowseConfig: Codable {
    let userId: String
    let rowId: String
    let rowType: String
    let title: String
    let isEnabled: Bool
    let sortOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case rowId = "row_id"
        case rowType = "row_type"
        case title
        case isEnabled = "is_enabled"
        case sortOrder = "sort_order"
    }
}

struct SyncedExtensionList: Codable {
    let userId: String
    let listId: String
    let name: String
    let source: String
    let customName: String?
    let showOnHome: Bool
    let lastSynced: Date?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case listId = "list_id"
        case name, source
        case customName = "custom_name"
        case showOnHome = "show_on_home"
        case lastSynced = "last_synced"
        case createdAt = "created_at"
    }
}

struct SyncedExtensionListItem: Codable {
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
    }
}

struct SyncedCustomHomeRow: Codable {
    let userId: String
    let rowId: String
    let name: String
    let rowType: String
    let importedListId: String?
    let hubImageUrl: String?
    let isEnabled: Bool
    let sortOrder: Int
    let createdAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case rowId = "row_id"
        case name
        case rowType = "row_type"
        case importedListId = "imported_list_id"
        case hubImageUrl = "hub_image_url"
        case isEnabled = "is_enabled"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

struct SyncedNetworkHubConfig: Codable {
    let userId: String
    let hubId: String
    let isEnabled: Bool
    let sortOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case hubId = "hub_id"
        case isEnabled = "is_enabled"
        case sortOrder = "sort_order"
    }
}

struct HomeScreenConfig {
    let browseRows: [BrowseRowConfig]
    let extensionLists: [ImportedListItem]
    let customHomeRows: [CustomHomeRow]
    let networkHubsConfig: [SyncedNetworkHubConfig]
}

// MARK: - Custom Home Row Extension for full init
extension CustomHomeRow {
    init(id: String, name: String, rowType: CustomRowType, sortOrder: Int, isEnabled: Bool, importedListId: String?, hubImageURL: String?, createdAt: Date) {
        self.id = id
        self.name = name
        self.rowType = rowType
        self.sortOrder = sortOrder
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.importedListId = importedListId
        self.hubImageURL = hubImageURL
        self.items = nil
    }
}

// MARK: - Errors

enum HomeScreenSyncError: LocalizedError {
    case notConfigured
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return message
        }
    }
}
