//
//  StorageService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation
import Combine

@MainActor
class StorageService: ObservableObject {
    static let shared = StorageService()
    
    // MARK: - Published Properties
    @Published private(set) var wantToWatch: [SavedMediaItem] = []
    @Published private(set) var watched: [SavedMediaItem] = []
    @Published private(set) var liked: [SavedMediaItem] = []
    @Published private(set) var customLists: [CustomList] = []
    @Published private(set) var companyHubs: [CompanyHub] = []
    @Published private(set) var networkHubs: [NetworkHub] = []
    @Published private(set) var importedLists: [ImportedListItem] = []
    @Published private(set) var customHomeRows: [CustomHomeRow] = []
    @Published private(set) var settings: UserSettings = UserSettings()
    @Published private(set) var searchHistory: [SearchHistoryItem] = []
    @Published private(set) var browseRows: [BrowseRowConfig] = BrowseRowConfig.defaultRows
    
    // MARK: - Sync State
    @Published var isSyncing = false
    @Published var lastSyncError: String?
    @Published var cloudSyncEnabled = false
    
    var lastSyncTime: Date? {
        UserDefaults.standard.object(forKey: "supabase_last_sync") as? Date
    }
    
    var isCloudConfigured: Bool {
        let url = ApiKeyManager.shared.get(key: "SUPABASE_URL") ?? ""
        let key = ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY") ?? ""
        return !url.isEmpty && !key.isEmpty
    }
    
    // MARK: - File URLs
    private let documentsDirectory: URL
    private let wantToWatchURL: URL
    private let watchedURL: URL
    private let likedURL: URL
    private let customListsURL: URL
    private let companyHubsURL: URL
    private let networkHubsURL: URL
    private let importedListsURL: URL
    private let customHomeRowsURL: URL
    private let settingsURL: URL
    private let searchHistoryURL: URL
    private let browseRowsURL: URL
    
    private init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        wantToWatchURL = documentsDirectory.appendingPathComponent("want_to_watch.json")
        watchedURL = documentsDirectory.appendingPathComponent("watched.json")
        likedURL = documentsDirectory.appendingPathComponent("liked.json")
        customListsURL = documentsDirectory.appendingPathComponent("custom_lists.json")
        companyHubsURL = documentsDirectory.appendingPathComponent("company_hubs.json")
        networkHubsURL = documentsDirectory.appendingPathComponent("network_hubs.json")
        importedListsURL = documentsDirectory.appendingPathComponent("imported_lists.json")
        customHomeRowsURL = documentsDirectory.appendingPathComponent("custom_home_rows.json")
        settingsURL = documentsDirectory.appendingPathComponent("settings.json")
        searchHistoryURL = documentsDirectory.appendingPathComponent("search_history.json")
        browseRowsURL = documentsDirectory.appendingPathComponent("browse_rows.json")
        
        loadAll()
        initializeDefaultHubs()
        initializeNetworkHubs()
        
        // Load cloud sync preference
        cloudSyncEnabled = UserDefaults.standard.bool(forKey: "cloud_sync_enabled")
    }
    
    // MARK: - Load All Data
    private func loadAll() {
        wantToWatch = load(from: wantToWatchURL) ?? []
        watched = load(from: watchedURL) ?? []
        liked = load(from: likedURL) ?? []
        customLists = load(from: customListsURL) ?? []
        companyHubs = load(from: companyHubsURL) ?? []
        networkHubs = load(from: networkHubsURL) ?? []
        importedLists = load(from: importedListsURL) ?? []
        customHomeRows = load(from: customHomeRowsURL) ?? []
        settings = load(from: settingsURL) ?? UserSettings()
        searchHistory = load(from: searchHistoryURL) ?? []
        browseRows = load(from: browseRowsURL) ?? BrowseRowConfig.defaultRows
    }
    
    private func load<T: Decodable>(from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("Error loading \(url.lastPathComponent): \(error)")
            return nil
        }
    }
    
    private func save<T: Encodable>(_ item: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(item)
            try data.write(to: url)
        } catch {
            print("Error saving \(url.lastPathComponent): \(error)")
        }
    }
    
    // MARK: - Default Company Hubs (Legacy)
    private func initializeDefaultHubs() {
        guard companyHubs.isEmpty else { return }
        
        let defaultHubs = [
            CompanyHub(name: "Warner Bros.", logoPath: nil, companyIds: [174, 17, 429, 76043], networkIds: []),
            CompanyHub(name: "Walt Disney Pictures", logoPath: nil, companyIds: [2, 3, 420, 7505, 7521], networkIds: [2739]),
            CompanyHub(name: "Marvel Studios", logoPath: nil, companyIds: [420], networkIds: []),
            CompanyHub(name: "DC Studios", logoPath: nil, companyIds: [128064, 174], networkIds: []),
            CompanyHub(name: "Pixar", logoPath: nil, companyIds: [3], networkIds: []),
            CompanyHub(name: "Universal Pictures", logoPath: nil, companyIds: [33], networkIds: []),
        ]
        
        companyHubs = defaultHubs
        save(companyHubs, to: companyHubsURL)
    }
    
    // MARK: - Network Hubs (Streaming Services)
    private func initializeNetworkHubs() {
        guard networkHubs.isEmpty else { return }
        
        var hubs = NetworkHub.defaultHubs
        for (index, _) in hubs.enumerated() {
            hubs[index].sortOrder = index
        }
        
        networkHubs = hubs
        save(networkHubs, to: networkHubsURL)
    }
    
    // MARK: - Network Hub Methods
    func updateNetworkHub(_ hub: NetworkHub) {
        if let index = networkHubs.firstIndex(where: { $0.id == hub.id }) {
            networkHubs[index] = hub
            save(networkHubs, to: networkHubsURL)
        }
    }
    
    func reorderNetworkHubs(_ hubs: [NetworkHub]) {
        var updatedHubs = hubs
        for (index, _) in updatedHubs.enumerated() {
            updatedHubs[index].sortOrder = index
        }
        networkHubs = updatedHubs
        save(networkHubs, to: networkHubsURL)
    }
    
    func getEnabledNetworkHubs() -> [NetworkHub] {
        return networkHubs.filter { $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    // MARK: - Want to Watch
    func addToWantToWatch(_ item: SavedMediaItem) {
        guard !wantToWatch.contains(where: { $0.id == item.id }) else { return }
        wantToWatch.insert(item, at: 0)
        save(wantToWatch, to: wantToWatchURL)
        syncAddToCloud(item, listType: .wantToWatch)
    }
    
    func removeFromWantToWatch(_ item: SavedMediaItem) {
        wantToWatch.removeAll { $0.id == item.id }
        save(wantToWatch, to: wantToWatchURL)
        syncRemoveFromCloud(mediaId: item.mediaId, mediaType: item.mediaType, listType: .wantToWatch)
    }
    
    func isInWantToWatch(_ mediaId: Int, mediaType: MediaType) -> Bool {
        let id = "\(mediaType.rawValue)-\(mediaId)"
        return wantToWatch.contains { $0.id == id }
    }
    
    // MARK: - Watched
    func addToWatched(_ item: SavedMediaItem) {
        guard !watched.contains(where: { $0.id == item.id }) else { return }
        watched.insert(item, at: 0)
        save(watched, to: watchedURL)
        syncAddToCloud(item, listType: .watched)
    }
    
    func removeFromWatched(_ item: SavedMediaItem) {
        watched.removeAll { $0.id == item.id }
        save(watched, to: watchedURL)
        syncRemoveFromCloud(mediaId: item.mediaId, mediaType: item.mediaType, listType: .watched)
    }
    
    func isInWatched(_ mediaId: Int, mediaType: MediaType) -> Bool {
        let id = "\(mediaType.rawValue)-\(mediaId)"
        return watched.contains { $0.id == id }
    }
    
    // MARK: - Liked
    func addToLiked(_ item: SavedMediaItem) {
        guard !liked.contains(where: { $0.id == item.id }) else { return }
        liked.insert(item, at: 0)
        save(liked, to: likedURL)
        syncAddToCloud(item, listType: .liked)
    }
    
    func removeFromLiked(_ item: SavedMediaItem) {
        liked.removeAll { $0.id == item.id }
        save(liked, to: likedURL)
        syncRemoveFromCloud(mediaId: item.mediaId, mediaType: item.mediaType, listType: .liked)
    }
    
    func isInLiked(_ mediaId: Int, mediaType: MediaType) -> Bool {
        let id = "\(mediaType.rawValue)-\(mediaId)"
        return liked.contains { $0.id == id }
    }
    
    // MARK: - Toggle Methods
    func toggleWantToWatch(_ item: SavedMediaItem) {
        if wantToWatch.contains(where: { $0.id == item.id }) {
            removeFromWantToWatch(item)
        } else {
            addToWantToWatch(item)
        }
    }
    
    func toggleWatched(_ item: SavedMediaItem) {
        if watched.contains(where: { $0.id == item.id }) {
            removeFromWatched(item)
        } else {
            addToWatched(item)
        }
    }
    
    func toggleLiked(_ item: SavedMediaItem) {
        if liked.contains(where: { $0.id == item.id }) {
            removeFromLiked(item)
        } else {
            addToLiked(item)
        }
    }
    
    // MARK: - Cloud Sync Methods
    
    /// Enable or disable cloud sync
    func setCloudSyncEnabled(_ enabled: Bool) {
        cloudSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "cloud_sync_enabled")
    }
    
    /// Upload all local data to cloud
    func uploadToCloud() async {
        guard isCloudConfigured else {
            lastSyncError = "Supabase not configured"
            return
        }
        
        isSyncing = true
        lastSyncError = nil
        
        do {
            try await SupabaseService.shared.uploadAllData(
                wantToWatch: wantToWatch,
                watched: watched,
                liked: liked
            )
            await SupabaseService.shared.updateLastSyncTime()
            objectWillChange.send()
        } catch {
            lastSyncError = error.localizedDescription
            print("Upload failed: \(error)")
        }
        
        isSyncing = false
    }
    
    /// Download all cloud data to local
    func downloadFromCloud() async {
        guard isCloudConfigured else {
            lastSyncError = "Supabase not configured"
            return
        }
        
        isSyncing = true
        lastSyncError = nil
        
        do {
            let data = try await SupabaseService.shared.downloadAllData()
            
            wantToWatch = data.wantToWatch
            watched = data.watched
            liked = data.liked
            
            save(wantToWatch, to: wantToWatchURL)
            save(watched, to: watchedURL)
            save(liked, to: likedURL)
            
            await SupabaseService.shared.updateLastSyncTime()
            objectWillChange.send()
        } catch {
            lastSyncError = error.localizedDescription
            print("Download failed: \(error)")
        }
        
        isSyncing = false
    }
    
    /// Sync individual item add to cloud (background)
    private func syncAddToCloud(_ item: SavedMediaItem, listType: SyncListType) {
        guard cloudSyncEnabled && isCloudConfigured else { return }
        
        Task {
            do {
                try await SupabaseService.shared.addItem(item, listType: listType)
            } catch {
                print("Cloud sync add failed: \(error)")
            }
        }
    }
    
    /// Sync individual item remove from cloud (background)
    private func syncRemoveFromCloud(mediaId: Int, mediaType: MediaType, listType: SyncListType) {
        guard cloudSyncEnabled && isCloudConfigured else { return }
        
        Task {
            do {
                try await SupabaseService.shared.removeItem(mediaId: mediaId, mediaType: mediaType, listType: listType)
            } catch {
                print("Cloud sync remove failed: \(error)")
            }
        }
    }
    
    // MARK: - Custom Lists
    func createCustomList(name: String, description: String? = nil, iconName: String = "folder.fill", displayStyle: CustomList.DisplayStyle = .row) {
        let list = CustomList(name: name, description: description, iconName: iconName, displayStyle: displayStyle)
        customLists.append(list)
        save(customLists, to: customListsURL)
    }
    
    func updateCustomList(_ list: CustomList) {
        if let index = customLists.firstIndex(where: { $0.id == list.id }) {
            customLists[index] = list
            save(customLists, to: customListsURL)
        }
    }
    
    func deleteCustomList(id: String) {
        customLists.removeAll { $0.id == id }
        save(customLists, to: customListsURL)
    }
    
    func addToCustomList(listId: String, item: SavedMediaItem) {
        if let index = customLists.firstIndex(where: { $0.id == listId }) {
            guard !customLists[index].items.contains(where: { $0.id == item.id }) else { return }
            customLists[index].items.insert(item, at: 0)
            customLists[index].updatedAt = Date()
            save(customLists, to: customListsURL)
        }
    }
    
    func removeFromCustomList(listId: String, item: SavedMediaItem) {
        if let index = customLists.firstIndex(where: { $0.id == listId }) {
            customLists[index].items.removeAll { $0.id == item.id }
            customLists[index].updatedAt = Date()
            save(customLists, to: customListsURL)
        }
    }
    
    func isInCustomList(listId: String, mediaId: Int, mediaType: MediaType) -> Bool {
        let id = "\(mediaType.rawValue)-\(mediaId)"
        return customLists.first { $0.id == listId }?.items.contains { $0.id == id } ?? false
    }
    
    // MARK: - Company Hubs
    func updateCompanyHub(_ hub: CompanyHub) {
        if let index = companyHubs.firstIndex(where: { $0.id == hub.id }) {
            companyHubs[index] = hub
            save(companyHubs, to: companyHubsURL)
        }
    }
    
    func addCompanyHub(_ hub: CompanyHub) {
        companyHubs.append(hub)
        save(companyHubs, to: companyHubsURL)
    }
    
    func deleteCompanyHub(id: String) {
        companyHubs.removeAll { $0.id == id }
        save(companyHubs, to: companyHubsURL)
    }
    
    // MARK: - Imported Lists (PublicMetaDB)
    func addImportedList(_ list: ImportedListItem) {
        importedLists.append(list)
        save(importedLists, to: importedListsURL)
    }
    
    func updateImportedList(_ list: ImportedListItem) {
        if let index = importedLists.firstIndex(where: { $0.id == list.id }) {
            importedLists[index] = list
            save(importedLists, to: importedListsURL)
        }
    }
    
    func deleteImportedList(id: String) {
        importedLists.removeAll { $0.id == id }
        save(importedLists, to: importedListsURL)
        // Also remove any custom home rows that use this list
        customHomeRows.removeAll { $0.importedListId == id }
        save(customHomeRows, to: customHomeRowsURL)
    }
    
    func getImportedListsForHome() -> [ImportedListItem] {
        return importedLists.filter { $0.showOnHome }
    }
    
    // MARK: - Custom Home Rows
    func addCustomHomeRow(_ row: CustomHomeRow) {
        var newRow = row
        newRow.sortOrder = customHomeRows.count
        customHomeRows.append(newRow)
        save(customHomeRows, to: customHomeRowsURL)
    }
    
    func updateCustomHomeRow(_ row: CustomHomeRow) {
        if let index = customHomeRows.firstIndex(where: { $0.id == row.id }) {
            customHomeRows[index] = row
            save(customHomeRows, to: customHomeRowsURL)
        }
    }
    
    func deleteCustomHomeRow(id: String) {
        customHomeRows.removeAll { $0.id == id }
        save(customHomeRows, to: customHomeRowsURL)
    }
    
    func reorderCustomHomeRows(_ rows: [CustomHomeRow]) {
        var updatedRows = rows
        for (index, _) in updatedRows.enumerated() {
            updatedRows[index].sortOrder = index
        }
        customHomeRows = updatedRows
        save(customHomeRows, to: customHomeRowsURL)
    }
    
    func getEnabledCustomHomeRows() -> [CustomHomeRow] {
        return customHomeRows.filter { $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    // MARK: - Settings
    func updateSettings(_ newSettings: UserSettings) {
        settings = newSettings
        save(settings, to: settingsURL)
    }
    
    // MARK: - Search History
    func addSearchHistory(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Remove existing entry if present
        searchHistory.removeAll { $0.query.lowercased() == trimmed.lowercased() }
        
        // Add to front
        searchHistory.insert(SearchHistoryItem(query: trimmed), at: 0)
        
        // Keep only last 20
        if searchHistory.count > 20 {
            searchHistory = Array(searchHistory.prefix(20))
        }
        
        save(searchHistory, to: searchHistoryURL)
    }
    
    func clearSearchHistory() {
        searchHistory = []
        save(searchHistory, to: searchHistoryURL)
    }
    
    // MARK: - Browse Rows
    func updateBrowseRows(_ rows: [BrowseRowConfig]) {
        browseRows = rows
        save(browseRows, to: browseRowsURL)
    }
}
