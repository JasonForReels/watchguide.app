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
        
        // Only set upsert header for POST/PATCH, not DELETE
        if method == "POST" || method == "PATCH" {
            request.addValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        }
        
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
        
        // Upload new — use endpoint.rawValue as the stable row identifier
        // (the original id like "1", "2" is consistent, but endpoint.rawValue is more semantic)
        let syncItems = rows.map { row in
            SyncedBrowseConfig(
                userId: userId,
                rowId: row.endpoint.rawValue,
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
            // Match to local default row by endpoint to get the original id
            let localId = BrowseRowConfig.defaultRows.first(where: { $0.endpoint == endpoint })?.id ?? item.rowId
            return BrowseRowConfig(
                id: localId,
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
        
        // Upload new — use hub name (lowercased) as hubId so it's consistent across devices
        // (each device generates different random UUIDs for hub.id, but the name is always the same)
        let syncItems = hubs.map { hub in
            SyncedNetworkHubConfig(
                userId: userId,
                hubId: hub.name.lowercased(),
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
    
    // MARK: - Custom JSON Hubs Sync
    
    func uploadCustomJSONHubs(_ hubs: [CustomJSONHub]) async throws {
        let userId = await getUserId()
        guard !userId.isEmpty else {
            throw HomeScreenSyncError.apiError("User ID is empty.")
        }
        
        // Delete existing
        let deleteQuery = [URLQueryItem(name: "user_id", value: "eq.\(userId)")]
        do {
            try await requestNoResponse(endpoint: "custom_json_hubs", method: "DELETE", queryItems: deleteQuery)
        } catch {
            print("Warning: Could not delete existing custom_json_hubs: \(error)")
        }
        
        guard !hubs.isEmpty else { return }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let syncItems = hubs.map { hub in
            SyncedCustomJSONHub(
                userId: userId,
                hubId: hub.id,
                name: hub.name,
                jsonUrl: hub.jsonURL,
                iconUrl: hub.iconURL,
                imageUrl: hub.imageURL,
                brandColor: hub.brandColor,
                isEnabled: hub.isEnabled,
                sortOrder: hub.sortOrder,
                lastSynced: hub.lastSynced,
                createdAt: hub.createdAt,
                source: hub.source.rawValue,
                mdblistId: hub.mdblistId,
                mdblistIds: hub.mdblistIds,
                rowName: hub.rowName
            )
        }
        
        let body = try encoder.encode(syncItems)
        try await requestNoResponse(endpoint: "custom_json_hubs", method: "POST", body: body)
    }
    
    func downloadCustomJSONHubs() async throws -> [CustomJSONHub] {
        let userId = await getUserId()
        let queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ]
        
        let items: [SyncedCustomJSONHub] = try await request(endpoint: "custom_json_hubs", queryItems: queryItems)
        
        // Build hub shells first (no network calls)
        var hubShells: [CustomJSONHub] = items.map { item in
            var hub = CustomJSONHub(
                id: item.hubId,
                name: item.name,
                jsonURL: item.jsonUrl,
                iconURL: item.iconUrl,
                brandColor: item.brandColor,
                isEnabled: item.isEnabled,
                sortOrder: item.sortOrder,
                lastSynced: item.lastSynced,
                createdAt: item.createdAt ?? Date()
            )
            hub.imageURL = item.imageUrl
            hub.rowName = item.rowName
            
            if let sourceRaw = item.source, let source = CustomHubSource(rawValue: sourceRaw) {
                hub.source = source
            } else if item.jsonUrl.hasPrefix("mdblist://") {
                hub.source = .mdblist
            }
            
            hub.mdblistId = item.mdblistId
            hub.mdblistIds = item.mdblistIds
            return hub
        }
        
        // Fetch all hub items in parallel using a TaskGroup
        await withTaskGroup(of: (Int, [SavedMediaItem]).self) { group in
            for (index, hub) in hubShells.enumerated() {
                group.addTask {
                    let listIds = hub.resolvedMDBListIds
                    
                    if hub.source == .mdblist || !listIds.isEmpty {
                        if !listIds.isEmpty {
                            do {
                                let fetchedItems = try await MDBListService.shared.fetchMultipleListsAsSavedMedia(inputs: listIds)
                                return (index, fetchedItems)
                            } catch {
                                print("Warning: Could not fetch MDBList items for hub \(hub.name): \(error)")
                                return (index, [])
                            }
                        }
                    } else {
                        do {
                            let result = try await JSONHubService.shared.fetchAndResolve(from: hub.jsonURL)
                            return (index, result.items)
                        } catch {
                            print("Warning: Could not fetch items for hub \(hub.name): \(error)")
                            return (index, [])
                        }
                    }
                    return (index, [])
                }
            }
            
            for await (index, fetchedItems) in group {
                hubShells[index].items = fetchedItems
                if !fetchedItems.isEmpty {
                    hubShells[index].lastSynced = Date()
                }
            }
        }
        
        return hubShells
    }
    
    // MARK: - Browse Sections Order Sync
    
    /// Ensures the browse_sections table exists by attempting a CREATE TABLE IF NOT EXISTS.
    /// This is safe to call multiple times; it's a no-op if the table already exists.
    private var hasMigratedBrowseSections = false
    
    private func ensureBrowseSectionsTable() async {
        guard !hasMigratedBrowseSections else { return }
        hasMigratedBrowseSections = true
        
        // Try a lightweight SELECT first — if it succeeds, the table exists
        do {
            let _: [SyncedBrowseSection] = try await request(
                endpoint: "browse_sections",
                queryItems: [URLQueryItem(name: "limit", value: "1")]
            )
            // Table exists, we're good
        } catch {
            // Table likely doesn't exist — log for user awareness
            print("⚠️ browse_sections table not found. Please run the migration SQL in Supabase SQL Editor:")
            print("""
            CREATE TABLE IF NOT EXISTS browse_sections (
                id SERIAL PRIMARY KEY,
                user_id TEXT NOT NULL,
                section_id TEXT NOT NULL,
                section_type TEXT NOT NULL,
                is_enabled BOOLEAN DEFAULT TRUE,
                sort_order INTEGER DEFAULT 0,
                UNIQUE(user_id, section_id)
            );
            ALTER TABLE browse_sections ENABLE ROW LEVEL SECURITY;
            CREATE POLICY "Allow all for anon" ON browse_sections FOR ALL TO anon USING (true) WITH CHECK (true);
            CREATE POLICY "Allow all for auth" ON browse_sections FOR ALL TO authenticated USING (true) WITH CHECK (true);
            """)
        }
    }
    
    func uploadBrowseSections(_ sections: [BrowseSectionItem]) async throws {
        let userId = await getUserId()
        guard !userId.isEmpty else {
            throw HomeScreenSyncError.apiError("User ID is empty.")
        }
        
        await ensureBrowseSectionsTable()
        
        // Delete existing
        let deleteQuery = [URLQueryItem(name: "user_id", value: "eq.\(userId)")]
        do {
            try await requestNoResponse(endpoint: "browse_sections", method: "DELETE", queryItems: deleteQuery)
        } catch {
            print("Warning: Could not delete existing browse_sections: \(error)")
            return // Table likely doesn't exist yet — skip upload
        }
        
        guard !sections.isEmpty else { return }
        
        // Use sectionType.rawValue as the stable identifier (consistent across devices)
        let syncItems = sections.map { sec in
            SyncedBrowseSection(
                userId: userId,
                sectionId: sec.sectionType.rawValue,
                sectionType: sec.sectionType.rawValue,
                isEnabled: sec.isEnabled,
                sortOrder: sec.sortOrder
            )
        }
        
        let encoder = JSONEncoder()
        let body = try encoder.encode(syncItems)
        try await requestNoResponse(endpoint: "browse_sections", method: "POST", body: body)
    }
    
    func downloadBrowseSections() async throws -> [BrowseSectionItem]? {
        await ensureBrowseSectionsTable()
        
        let userId = await getUserId()
        let queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ]
        
        let items: [SyncedBrowseSection] = try await request(endpoint: "browse_sections", queryItems: queryItems)
        guard !items.isEmpty else { return nil }
        
        return items.compactMap { item in
            guard let sectionType = BrowseSectionItem.BrowseSectionType(rawValue: item.sectionType) else { return nil }
            // Use stable IDs matching the defaults (sec_<type>)
            let stableId = "sec_\(sectionType.rawValue)"
            return BrowseSectionItem(
                id: stableId,
                sectionType: sectionType,
                isEnabled: item.isEnabled,
                sortOrder: item.sortOrder
            )
        }
    }
    
    // MARK: - Hidden Sections Sync
    
    func uploadHiddenSections(_ sections: HiddenDefaultSections) async throws {
        let userId = await getUserId()
        guard !userId.isEmpty else {
            throw HomeScreenSyncError.apiError("User ID is empty.")
        }
        
        // Delete existing row for this user first (reliable delete-then-insert)
        let deleteQuery = [URLQueryItem(name: "user_id", value: "eq.\(userId)")]
        do {
            try await requestNoResponse(endpoint: "hidden_sections", method: "DELETE", queryItems: deleteQuery)
        } catch {
            print("Warning: Could not delete existing hidden_sections: \(error)")
        }
        
        let syncItem = SyncedHiddenSections(
            userId: userId,
            hideStudiosRow: sections.hideStudiosRow,
            hideNetworksRow: sections.hideNetworksRow,
            hideForYouRow: sections.hideForYouRow,
            hideDiscoverSection: sections.hideDiscoverSection
        )
        
        // Insert as array (PostgREST standard)
        let encoder = JSONEncoder()
        let body = try encoder.encode([syncItem])
        try await requestNoResponse(endpoint: "hidden_sections", method: "POST", body: body)
    }
    
    func downloadHiddenSections() async throws -> HiddenDefaultSections? {
        let userId = await getUserId()
        let queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        
        let items: [SyncedHiddenSections] = try await request(endpoint: "hidden_sections", queryItems: queryItems)
        guard let synced = items.first else { return nil }
        
        return HiddenDefaultSections(
            hideStudiosRow: synced.hideStudiosRow ?? false,
            hideNetworksRow: synced.hideNetworksRow ?? false,
            hideForYouRow: synced.hideForYouRow ?? false,
            hideDiscoverSection: synced.hideDiscoverSection ?? false
        )
    }
    
    // MARK: - Full Sync
    
    func uploadAllHomeScreenConfig(
        browseRows: [BrowseRowConfig],
        extensionLists: [ImportedListItem],
        customHomeRows: [CustomHomeRow],
        networkHubs: [NetworkHub],
        hiddenSections: HiddenDefaultSections = .default
    ) async throws {
        try await uploadBrowseConfig(browseRows)
        try await uploadExtensionLists(extensionLists)
        try await uploadCustomHomeRows(customHomeRows)
        try await uploadNetworkHubsConfig(networkHubs)
        
        // Also upload custom JSON hubs
        let jsonHubs = await MainActor.run { StorageService.shared.customJSONHubs }
        try await uploadCustomJSONHubs(jsonHubs)
        
        // Upload hidden sections
        do {
            try await uploadHiddenSections(hiddenSections)
        } catch {
            print("Warning: Could not upload hidden sections: \(error)")
        }
        
        // Upload browse sections order
        let sections = await MainActor.run { StorageService.shared.browseSections }
        do {
            try await uploadBrowseSections(sections)
        } catch {
            print("Warning: Could not upload browse sections: \(error)")
        }
    }
    
    func downloadAllHomeScreenConfig() async throws -> HomeScreenConfig {
        async let browseRows = downloadBrowseConfig()
        async let extensionLists = downloadExtensionLists()
        async let customHomeRows = downloadCustomHomeRows()
        async let networkHubsConfig = downloadNetworkHubsConfig()
        async let customJSONHubs = downloadCustomJSONHubs()
        async let hiddenSectionsResult = downloadHiddenSectionsSafe()
        async let browseSectionsResult = downloadBrowseSectionsSafe()
        
        return try await HomeScreenConfig(
            browseRows: browseRows,
            extensionLists: extensionLists,
            customHomeRows: customHomeRows,
            networkHubsConfig: networkHubsConfig,
            customJSONHubs: customJSONHubs,
            hiddenSections: hiddenSectionsResult,
            browseSections: browseSectionsResult
        )
    }
    
    /// Safe wrapper that never throws — returns nil on any failure
    private func downloadHiddenSectionsSafe() async -> HiddenDefaultSections? {
        do {
            return try await downloadHiddenSections()
        } catch {
            print("Warning: Could not download hidden sections: \(error)")
            return nil
        }
    }
    
    /// Safe wrapper that never throws — returns nil on any failure
    private func downloadBrowseSectionsSafe() async -> [BrowseSectionItem]? {
        do {
            return try await downloadBrowseSections()
        } catch {
            print("Warning: Could not download browse sections: \(error)")
            return nil
        }
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
    
    // Explicitly encode all keys (including nil as null) to avoid PGRST102
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(listId, forKey: .listId)
        try container.encode(name, forKey: .name)
        try container.encode(source, forKey: .source)
        try container.encode(customName, forKey: .customName)
        try container.encode(showOnHome, forKey: .showOnHome)
        try container.encode(lastSynced, forKey: .lastSynced)
        try container.encode(createdAt, forKey: .createdAt)
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
        try container.encode(voteAverage, forKey: .voteAverage)
        try container.encode(overview, forKey: .overview)
        try container.encode(sortOrder, forKey: .sortOrder)
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
    
    // Explicitly encode all keys (including nil as null) to avoid PGRST102
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(rowId, forKey: .rowId)
        try container.encode(name, forKey: .name)
        try container.encode(rowType, forKey: .rowType)
        try container.encode(importedListId, forKey: .importedListId)
        try container.encode(hubImageUrl, forKey: .hubImageUrl)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(createdAt, forKey: .createdAt)
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
    let customJSONHubs: [CustomJSONHub]
    let hiddenSections: HiddenDefaultSections?
    let browseSections: [BrowseSectionItem]?
    
    init(browseRows: [BrowseRowConfig], extensionLists: [ImportedListItem], customHomeRows: [CustomHomeRow], networkHubsConfig: [SyncedNetworkHubConfig], customJSONHubs: [CustomJSONHub] = [], hiddenSections: HiddenDefaultSections? = nil, browseSections: [BrowseSectionItem]? = nil) {
        self.browseRows = browseRows
        self.extensionLists = extensionLists
        self.customHomeRows = customHomeRows
        self.networkHubsConfig = networkHubsConfig
        self.customJSONHubs = customJSONHubs
        self.hiddenSections = hiddenSections
        self.browseSections = browseSections
    }
}

struct SyncedCustomJSONHub: Codable {
    let userId: String
    let hubId: String
    let name: String
    let jsonUrl: String
    let iconUrl: String?
    let imageUrl: String?
    let brandColor: String?
    let isEnabled: Bool
    let sortOrder: Int
    let lastSynced: Date?
    let createdAt: Date?
    let source: String?
    let mdblistId: String?
    let mdblistIds: [String]?
    let rowName: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case hubId = "hub_id"
        case name
        case jsonUrl = "json_url"
        case iconUrl = "icon_url"
        case imageUrl = "image_url"
        case brandColor = "brand_color"
        case isEnabled = "is_enabled"
        case sortOrder = "sort_order"
        case lastSynced = "last_synced"
        case createdAt = "created_at"
        case source
        case mdblistId = "mdblist_id"
        case mdblistIds = "mdblist_ids"
        case rowName = "row_name"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(hubId, forKey: .hubId)
        try container.encode(name, forKey: .name)
        try container.encode(jsonUrl, forKey: .jsonUrl)
        try container.encode(iconUrl, forKey: .iconUrl)
        try container.encode(imageUrl, forKey: .imageUrl)
        try container.encode(brandColor, forKey: .brandColor)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(lastSynced, forKey: .lastSynced)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(source, forKey: .source)
        try container.encode(mdblistId, forKey: .mdblistId)
        try container.encode(mdblistIds, forKey: .mdblistIds)
        try container.encode(rowName, forKey: .rowName)
    }
}

struct SyncedHiddenSections: Codable {
    let userId: String
    let hideStudiosRow: Bool?
    let hideNetworksRow: Bool?
    let hideForYouRow: Bool?
    let hideDiscoverSection: Bool?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case hideStudiosRow = "hide_studios_row"
        case hideNetworksRow = "hide_networks_row"
        case hideForYouRow = "hide_for_you_row"
        case hideDiscoverSection = "hide_discover_section"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(hideStudiosRow, forKey: .hideStudiosRow)
        try container.encode(hideNetworksRow, forKey: .hideNetworksRow)
        try container.encode(hideForYouRow, forKey: .hideForYouRow)
        try container.encode(hideDiscoverSection, forKey: .hideDiscoverSection)
    }
}

struct SyncedBrowseSection: Codable {
    let userId: String
    let sectionId: String
    let sectionType: String
    let isEnabled: Bool
    let sortOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case sectionId = "section_id"
        case sectionType = "section_type"
        case isEnabled = "is_enabled"
        case sortOrder = "sort_order"
    }
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
