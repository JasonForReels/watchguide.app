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
    @Published private(set) var customJSONHubs: [CustomJSONHub] = []
    @Published private(set) var settings: UserSettings = UserSettings()
    @Published private(set) var searchHistory: [SearchHistoryItem] = []
    @Published private(set) var browseRows: [BrowseRowConfig] = BrowseRowConfig.defaultRows
    @Published private(set) var hiddenSections: HiddenDefaultSections = .default
    @Published private(set) var browseSections: [BrowseSectionItem] = BrowseSectionItem.defaultSections
    
    // MARK: - Sync State
    @Published var isSyncing = false
    @Published var lastSyncError: String?
    @Published var cloudSyncEnabled = false

    var lastSyncTime: Date? {
        if let cloud = UserDefaults.standard.object(forKey: "cloud_last_sync") as? Date {
            return cloud
        }
        return UserDefaults.standard.object(forKey: "supabase_last_sync") as? Date
    }

    var isCloudConfigured: Bool {
        isSupabaseConfigured || AuthService.shared.isAppleAuthActive
    }
    
    /// Whether Supabase is configured
    var isSupabaseConfigured: Bool {
        let url = ApiKeyManager.shared.get(key: "SUPABASE_URL") ?? ""
        let key = ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY") ?? ""
        return !url.isEmpty && !key.isEmpty
    }

    var cloudProviderDisplayName: String {
        isSupabaseConfigured ? "Supabase" : "CloudKit"
    }

    private var isApplyingCloudSnapshot = false
    
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
    private let customJSONHubsURL: URL
    private let settingsURL: URL
    private let searchHistoryURL: URL
    private let browseRowsURL: URL
    private let hiddenSectionsURL: URL
    private let browseSectionsURL: URL
    
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
        customJSONHubsURL = documentsDirectory.appendingPathComponent("custom_json_hubs.json")
        settingsURL = documentsDirectory.appendingPathComponent("settings.json")
        searchHistoryURL = documentsDirectory.appendingPathComponent("search_history.json")
        browseRowsURL = documentsDirectory.appendingPathComponent("browse_rows.json")
        hiddenSectionsURL = documentsDirectory.appendingPathComponent("hidden_sections.json")
        browseSectionsURL = documentsDirectory.appendingPathComponent("browse_sections.json")
        
        loadAll()
        migrateBrowseRowsIfNeeded()
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
        customJSONHubs = load(from: customJSONHubsURL) ?? []
        settings = load(from: settingsURL) ?? UserSettings()
        searchHistory = load(from: searchHistoryURL) ?? []
        browseRows = load(from: browseRowsURL) ?? BrowseRowConfig.defaultRows
        hiddenSections = load(from: hiddenSectionsURL) ?? .default
        browseSections = load(from: browseSectionsURL) ?? BrowseSectionItem.defaultSections
        migrateBrowseSectionsIfNeeded()
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

    private func migrateBrowseRowsIfNeeded() {
        guard !browseRows.contains(where: { $0.endpoint == .trendingPeople }) else { return }
        
        var updated = browseRows
        let newRow = BrowseRowConfig(
            id: "trending_people",
            title: "Trending Actors",
            endpoint: .trendingPeople,
            isEnabled: true,
            sortOrder: 0
        )
        
        if let trendingTVIndex = updated.firstIndex(where: { $0.endpoint == .trendingTV }) {
            updated.insert(newRow, at: trendingTVIndex + 1)
        } else {
            updated.append(newRow)
        }
        
        for (index, _) in updated.enumerated() {
            updated[index].sortOrder = index
        }
        
        browseRows = updated
        save(browseRows, to: browseRowsURL)
    }
    
    /// Ensure all section types exist (in case new ones were added)
    private func migrateBrowseSectionsIfNeeded() {
        let existing = Set(browseSections.map { $0.sectionType })
        var updated = browseSections
        for def in BrowseSectionItem.defaultSections where !existing.contains(def.sectionType) {
            var newSec = def
            newSec.sortOrder = updated.count
            updated.append(newSec)
        }
        if updated.count != browseSections.count {
            browseSections = updated
            save(browseSections, to: browseSectionsURL)
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
        // If there are no saved hubs, seed with defaults (which now include Disney Channel)
        if networkHubs.isEmpty {
            var hubs = NetworkHub.defaultHubs
            for (index, _) in hubs.enumerated() {
                hubs[index].sortOrder = index
            }
            networkHubs = hubs
            save(networkHubs, to: networkHubsURL)
            return
        }
        
        // Migration: Remove any existing Disney Channel hub and rebuild it like streaming hubs
        var updated = networkHubs
        // Remove all existing Disney Channel hubs
        updated.removeAll { $0.name.lowercased() == "disney channel" }
        
        // Build fresh Disney Channel hub
        var disneyChannel = NetworkHub(
            name: "Disney Channel",
            logoURL: "https://i.ibb.co/XZWP8tTs/disney-channel-seeklogo.png",
            networkIds: [],
            providerIds: [],
            regions: [] // show in all regions
        )
        disneyChannel.isEnabled = true
        
        // Insert right after Disney+ if present, otherwise append
        if let disneyPlusIndex = updated.firstIndex(where: { $0.name.lowercased() == "disney+" }) {
            let insertIndex = min(disneyPlusIndex + 1, updated.count)
            updated.insert(disneyChannel, at: insertIndex)
        } else {
            updated.append(disneyChannel)
        }
        
        // Reassign sortOrder
        for (idx, _) in updated.enumerated() {
            updated[idx].sortOrder = idx
        }
        
        // Persist changes
        networkHubs = updated
        save(networkHubs, to: networkHubsURL)
    }
    
    // MARK: - Network Hub Methods
    func updateNetworkHub(_ hub: NetworkHub) {
        if let index = networkHubs.firstIndex(where: { $0.id == hub.id }) {
            networkHubs[index] = hub
            save(networkHubs, to: networkHubsURL)
            syncNetworkHubsToCloud()
        }
    }
    
    func reorderNetworkHubs(_ hubs: [NetworkHub]) {
        var updatedHubs = hubs
        for (index, _) in updatedHubs.enumerated() {
            updatedHubs[index].sortOrder = index
        }
        networkHubs = updatedHubs
        save(networkHubs, to: networkHubsURL)
        syncNetworkHubsToCloud()
    }
    
    func getEnabledNetworkHubs() -> [NetworkHub] {
        let userRegion = settings.region
        return networkHubs
            .filter { hub in
                guard hub.isEnabled else { return false }
                // If regions is empty, show in all regions. Otherwise, require a match.
                return hub.regions.isEmpty || hub.regions.contains(userRegion)
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    func getNetworkHubsForRegion(_ region: String) -> [NetworkHub] {
        return networkHubs
            .filter { $0.regions.contains(region) }
            .sorted { $0.sortOrder < $1.sortOrder }
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
            lastSyncError = "Cloud sync not configured"
            return
        }
        
        isSyncing = true
        lastSyncError = nil
        if isSupabaseConfigured {
            await uploadToSupabase()
        } else {
            await uploadToICloud()
        }
        
        isSyncing = false
    }
    
    private func uploadToSupabase() async {
        do {
            try await SupabaseService.shared.uploadAllData(
                wantToWatch: wantToWatch,
                watched: watched,
                liked: liked
            )
            try await SupabaseService.shared.uploadSettings(settings)
            try await SupabaseService.shared.uploadCustomLists(customLists)

            #if !os(tvOS)
            try await HomeScreenSyncService.shared.uploadAllHomeScreenConfig(
                browseRows: browseRows,
                extensionLists: importedLists,
                customHomeRows: customHomeRows,
                networkHubs: networkHubs,
                hiddenSections: hiddenSections
            )
            #endif

            ProfileService.shared.syncProfilesToCloud()
            await SupabaseService.shared.updateLastSyncTime()
            objectWillChange.send()
        } catch {
            lastSyncError = error.localizedDescription
            print("Supabase upload failed: \(error)")
        }
    }
    
    /// Download all cloud data to local
    func downloadFromCloud() async {
        guard isCloudConfigured else {
            lastSyncError = "Cloud sync not configured"
            return
        }
        
        isSyncing = true
        lastSyncError = nil
        if isSupabaseConfigured {
            await downloadFromSupabase()
        } else {
            await downloadFromICloud()
        }
        
        isSyncing = false
    }
    
    private func downloadFromSupabase() async {
        do {
            async let mediaDataTask = SupabaseService.shared.downloadAllData()
            async let settingsTask = SupabaseService.shared.downloadSettings()
            async let customListsTask = SupabaseService.shared.downloadCustomLists()
            async let homeConfigTask = HomeScreenSyncService.shared.downloadAllHomeScreenConfig()

            let data = try await mediaDataTask
            let cloudSettings = try await settingsTask
            let cloudCustomLists = try await customListsTask
            let homeConfig = try await homeConfigTask

            applyDownloadedMediaItems(data.wantToWatch, data.watched, data.liked)
            if let cloudSettings = cloudSettings {
                settings = cloudSettings
                save(settings, to: settingsURL)
            }
            if !cloudCustomLists.isEmpty {
                customLists = cloudCustomLists
                save(customLists, to: customListsURL)
            }
            applyHomeScreenConfig(homeConfig)

            await ProfileService.shared.downloadProfilesFromCloud()
            await SupabaseService.shared.updateLastSyncTime()
            objectWillChange.send()
        } catch {
            lastSyncError = error.localizedDescription
            print("Supabase download failed: \(error)")
        }
    }
    
    // MARK: - Shared Helpers
    
    private func applyDownloadedMediaItems(_ w: [SavedMediaItem], _ watched: [SavedMediaItem], _ liked: [SavedMediaItem]) {
        self.wantToWatch = w
        self.watched = watched
        self.liked = liked
        save(self.wantToWatch, to: wantToWatchURL)
        save(self.watched, to: watchedURL)
        save(self.liked, to: likedURL)
    }
    
    /// Applies home screen config downloaded from Supabase
    private func applyHomeScreenConfig(_ homeConfig: HomeScreenConfig) {
        var mergedBrowseRows = homeConfig.browseRows
        let cloudEndpoints = Set(mergedBrowseRows.map { $0.endpoint })
        for defaultRow in BrowseRowConfig.defaultRows where !cloudEndpoints.contains(defaultRow.endpoint) {
            var newRow = defaultRow
            newRow.sortOrder = mergedBrowseRows.count
            newRow.isEnabled = homeConfig.browseRows.isEmpty ? defaultRow.isEnabled : false
            mergedBrowseRows.append(newRow)
        }
        browseRows = mergedBrowseRows
        save(browseRows, to: browseRowsURL)

        importedLists = homeConfig.extensionLists
        save(importedLists, to: importedListsURL)

        customHomeRows = homeConfig.customHomeRows
        save(customHomeRows, to: customHomeRowsURL)

        if !homeConfig.networkHubsConfig.isEmpty {
            for config in homeConfig.networkHubsConfig {
                if let idx = networkHubs.firstIndex(where: { $0.name.lowercased() == config.hubId.lowercased() }) {
                    networkHubs[idx].isEnabled = config.isEnabled
                    networkHubs[idx].sortOrder = config.sortOrder
                }
            }
            networkHubs.sort { $0.sortOrder < $1.sortOrder }
            save(networkHubs, to: networkHubsURL)
        }

        customJSONHubs = homeConfig.customJSONHubs
        save(customJSONHubs, to: customJSONHubsURL)

        if let syncedHidden = homeConfig.hiddenSections {
            hiddenSections = syncedHidden
            save(hiddenSections, to: hiddenSectionsURL)
        }

        if let syncedSections = homeConfig.browseSections, !syncedSections.isEmpty {
            var merged = syncedSections
            let cloudTypes = Set(merged.map { $0.sectionType })
            for def in BrowseSectionItem.defaultSections where !cloudTypes.contains(def.sectionType) {
                var newSec = def
                newSec.sortOrder = merged.count
                newSec.isEnabled = false
                merged.append(newSec)
            }
            browseSections = merged
            save(browseSections, to: browseSectionsURL)
        }
    }
    
    /// Sync individual item add to cloud (background)
    private func syncAddToCloud(_ item: SavedMediaItem, listType: SyncListType) {
        guard shouldAutoSyncHomeConfig else { return }
        
        Task {
            if isSupabaseConfigured {
                do {
                    try await SupabaseService.shared.addItem(item, listType: listType)
                } catch {
                    print("Cloud sync add failed: \(error)")
                }
            } else {
                await uploadToICloud()
            }
        }
    }
    
    /// Sync individual item remove from cloud (background)
    private func syncRemoveFromCloud(mediaId: Int, mediaType: MediaType, listType: SyncListType) {
        guard shouldAutoSyncHomeConfig else { return }
        
        Task {
            if isSupabaseConfigured {
                do {
                    try await SupabaseService.shared.removeItem(mediaId: mediaId, mediaType: mediaType, listType: listType)
                } catch {
                    print("Cloud sync remove failed: \(error)")
                }
            } else {
                await uploadToICloud()
            }
        }
    }
    
    // MARK: - Browse Customization Cloud Sync
    
    /// Whether data should auto-sync to cloud.
    /// Syncs whenever the user is authenticated and cloud is configured.
    private var shouldAutoSyncHomeConfig: Bool {
        #if os(tvOS)
        return false
        #else
        guard isCloudConfigured else { return false }
        guard !isApplyingCloudSnapshot else { return false }
        return AuthService.shared.isAuthenticated
        #endif
    }
    
    /// Sync browse row config to cloud (background)
    private func syncBrowseConfigToCloud() {
        guard shouldAutoSyncHomeConfig else { return }
        if isSupabaseConfigured {
            let rowsCopy = browseRows
            Task {
                do {
                    try await HomeScreenSyncService.shared.uploadBrowseConfig(rowsCopy)
                } catch {
                    print("Cloud sync browse config failed: \(error)")
                }
            }
        } else {
            syncICloudSnapshotInBackground()
        }
    }
    
    /// Sync network hubs config to cloud (background)
    private func syncNetworkHubsToCloud() {
        guard shouldAutoSyncHomeConfig else { return }
        if isSupabaseConfigured {
            let hubsCopy = networkHubs
            Task {
                do {
                    try await HomeScreenSyncService.shared.uploadNetworkHubsConfig(hubsCopy)
                } catch {
                    print("Cloud sync network hubs failed: \(error)")
                }
            }
        } else {
            syncICloudSnapshotInBackground()
        }
    }
    
    /// Sync hidden sections to cloud (background)
    private func syncHiddenSectionsToCloud() {
        guard shouldAutoSyncHomeConfig else { return }
        if isSupabaseConfigured {
            let sectionsCopy = hiddenSections
            Task {
                do {
                    try await HomeScreenSyncService.shared.uploadHiddenSections(sectionsCopy)
                } catch {
                    print("Cloud sync hidden sections failed: \(error)")
                }
            }
        } else {
            syncICloudSnapshotInBackground()
        }
    }
    
    /// Sync custom JSON hubs to cloud (background)
    private func syncCustomJSONHubsToCloud() {
        guard shouldAutoSyncHomeConfig else { return }
        if isSupabaseConfigured {
            let hubsCopy = customJSONHubs
            Task {
                do {
                    try await HomeScreenSyncService.shared.uploadCustomJSONHubs(hubsCopy)
                } catch {
                    print("Cloud sync custom JSON hubs failed: \(error)")
                }
            }
        } else {
            syncICloudSnapshotInBackground()
        }
    }
    
    /// Sync extension lists to cloud (background)
    private func syncExtensionListsToCloud() {
        guard shouldAutoSyncHomeConfig else { return }
        if isSupabaseConfigured {
            let listsCopy = importedLists
            Task {
                do {
                    try await HomeScreenSyncService.shared.uploadExtensionLists(listsCopy)
                } catch {
                    print("Cloud sync extension lists failed: \(error)")
                }
            }
        } else {
            syncICloudSnapshotInBackground()
        }
    }
    
    /// Sync custom home rows to cloud (background)
    private func syncCustomHomeRowsToCloud() {
        guard shouldAutoSyncHomeConfig else { return }
        if isSupabaseConfigured {
            let rowsCopy = customHomeRows
            Task {
                do {
                    try await HomeScreenSyncService.shared.uploadCustomHomeRows(rowsCopy)
                } catch {
                    print("Cloud sync custom home rows failed: \(error)")
                }
            }
        } else {
            syncICloudSnapshotInBackground()
        }
    }
    
    // MARK: - Custom Lists
    func createCustomList(name: String, description: String? = nil, iconName: String = "folder.fill", displayStyle: CustomList.DisplayStyle = .row) {
        let list = CustomList(name: name, description: description, iconName: iconName, displayStyle: displayStyle)
        customLists.append(list)
        save(customLists, to: customListsURL)
        syncCustomListsToCloud()
    }
    
    func updateCustomList(_ list: CustomList) {
        if let index = customLists.firstIndex(where: { $0.id == list.id }) {
            customLists[index] = list
            save(customLists, to: customListsURL)
            syncCustomListsToCloud()
        }
    }
    
    func deleteCustomList(id: String) {
        customLists.removeAll { $0.id == id }
        save(customLists, to: customListsURL)
        syncCustomListsToCloud()
    }
    
    func addToCustomList(listId: String, item: SavedMediaItem) {
        if let index = customLists.firstIndex(where: { $0.id == listId }) {
            guard !customLists[index].items.contains(where: { $0.id == item.id }) else { return }
            customLists[index].items.insert(item, at: 0)
            customLists[index].updatedAt = Date()
            save(customLists, to: customListsURL)
            syncCustomListsToCloud()
        }
    }
    
    func removeFromCustomList(listId: String, item: SavedMediaItem) {
        if let index = customLists.firstIndex(where: { $0.id == listId }) {
            customLists[index].items.removeAll { $0.id == item.id }
            customLists[index].updatedAt = Date()
            save(customLists, to: customListsURL)
            syncCustomListsToCloud()
        }
    }
    
    /// Sync custom lists to cloud (background)
    private func syncCustomListsToCloud() {
        guard shouldAutoSyncHomeConfig else { return }
        if isSupabaseConfigured {
            let listsCopy = customLists
            Task {
                do {
                    try await SupabaseService.shared.uploadCustomLists(listsCopy)
                } catch {
                    print("Cloud sync custom lists failed: \(error)")
                }
            }
        } else {
            syncICloudSnapshotInBackground()
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
        syncExtensionListsToCloud()
    }
    
    func updateImportedList(_ list: ImportedListItem) {
        if let index = importedLists.firstIndex(where: { $0.id == list.id }) {
            importedLists[index] = list
            save(importedLists, to: importedListsURL)
            syncExtensionListsToCloud()
        }
    }
    
    func deleteImportedList(id: String) {
        importedLists.removeAll { $0.id == id }
        save(importedLists, to: importedListsURL)
        // Also remove any custom home rows that use this list
        customHomeRows.removeAll { $0.importedListId == id }
        save(customHomeRows, to: customHomeRowsURL)
        syncExtensionListsToCloud()
        syncCustomHomeRowsToCloud()
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
        syncCustomHomeRowsToCloud()
    }
    
    func updateCustomHomeRow(_ row: CustomHomeRow) {
        if let index = customHomeRows.firstIndex(where: { $0.id == row.id }) {
            customHomeRows[index] = row
            save(customHomeRows, to: customHomeRowsURL)
            syncCustomHomeRowsToCloud()
        }
    }
    
    func deleteCustomHomeRow(id: String) {
        customHomeRows.removeAll { $0.id == id }
        save(customHomeRows, to: customHomeRowsURL)
        syncCustomHomeRowsToCloud()
    }
    
    func reorderCustomHomeRows(_ rows: [CustomHomeRow]) {
        var updatedRows = rows
        for (index, _) in updatedRows.enumerated() {
            updatedRows[index].sortOrder = index
        }
        customHomeRows = updatedRows
        save(customHomeRows, to: customHomeRowsURL)
        syncCustomHomeRowsToCloud()
    }
    
    func getEnabledCustomHomeRows() -> [CustomHomeRow] {
        return customHomeRows.filter { $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    // MARK: - Custom JSON Hubs
    func addCustomJSONHub(_ hub: CustomJSONHub) {
        var newHub = hub
        newHub.sortOrder = customJSONHubs.count
        customJSONHubs.append(newHub)
        save(customJSONHubs, to: customJSONHubsURL)
        syncCustomJSONHubsToCloud()
    }
    
    func updateCustomJSONHub(_ hub: CustomJSONHub) {
        if let index = customJSONHubs.firstIndex(where: { $0.id == hub.id }) {
            customJSONHubs[index] = hub
            save(customJSONHubs, to: customJSONHubsURL)
            syncCustomJSONHubsToCloud()
        }
    }
    
    func deleteCustomJSONHub(id: String) {
        customJSONHubs.removeAll { $0.id == id }
        save(customJSONHubs, to: customJSONHubsURL)
        syncCustomJSONHubsToCloud()
    }
    
    func getEnabledCustomJSONHubs() -> [CustomJSONHub] {
        return customJSONHubs
            .filter { $0.isEnabled }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    func reorderCustomJSONHubs(_ hubs: [CustomJSONHub]) {
        var updated = hubs
        for (index, _) in updated.enumerated() {
            updated[index].sortOrder = index
        }
        customJSONHubs = updated
        save(customJSONHubs, to: customJSONHubsURL)
        syncCustomJSONHubsToCloud()
    }
    
    // MARK: - Settings
    func updateSettings(_ newSettings: UserSettings) {
        settings = newSettings
        save(settings, to: settingsURL)
        syncSettingsToCloud()
    }
    
    /// Sync settings to cloud (background)
    private func syncSettingsToCloud() {
        guard shouldAutoSyncHomeConfig else { return }
        if isSupabaseConfigured {
            let settingsCopy = settings
            Task {
                do {
                    try await SupabaseService.shared.uploadSettings(settingsCopy)
                } catch {
                    print("Cloud sync settings failed: \(error)")
                }
            }
        } else {
            syncICloudSnapshotInBackground()
        }
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
        syncBrowseConfigToCloud()
    }
    
    // MARK: - Hidden Default Sections
    func updateHiddenSections(_ sections: HiddenDefaultSections) {
        hiddenSections = sections
        save(hiddenSections, to: hiddenSectionsURL)
        syncHiddenSectionsToCloud()
    }
    
    // MARK: - Browse Sections (Order & Visibility)
    func updateBrowseSections(_ sections: [BrowseSectionItem]) {
        browseSections = sections
        save(browseSections, to: browseSectionsURL)
        syncBrowseSectionsToCloud()
        
        // Keep hiddenSections in sync for backward compatibility
        var hidden = hiddenSections
        for sec in sections {
            switch sec.sectionType {
            case .networks:  hidden.hideNetworksRow = !sec.isEnabled
            case .studios:   hidden.hideStudiosRow = !sec.isEnabled
            case .forYou:    hidden.hideForYouRow = !sec.isEnabled
            case .discover:  hidden.hideDiscoverSection = !sec.isEnabled
            default: break
            }
        }
        if hidden != hiddenSections {
            hiddenSections = hidden
            save(hiddenSections, to: hiddenSectionsURL)
        }
    }
    
    func getOrderedEnabledSections() -> [BrowseSectionItem] {
        browseSections.filter { $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    /// Sync browse sections to cloud (background)
    private func syncBrowseSectionsToCloud() {
        guard shouldAutoSyncHomeConfig else { return }
        if isSupabaseConfigured {
            let sectionsCopy = browseSections
            Task {
                do {
                    try await HomeScreenSyncService.shared.uploadBrowseSections(sectionsCopy)
                } catch {
                    print("Cloud sync browse sections failed: \(error)")
                }
            }
        } else {
            syncICloudSnapshotInBackground()
        }
    }
    
    // MARK: - Clear All Data
    /// Removes all user-generated data (lists, history, settings, etc.)
    func clearAllData() {
        wantToWatch = []
        watched = []
        liked = []
        customLists = []
        searchHistory = []
        importedLists = []
        customHomeRows = []
        customJSONHubs = []
        
        save(wantToWatch, to: wantToWatchURL)
        save(watched, to: watchedURL)
        save(liked, to: likedURL)
        save(customLists, to: customListsURL)
        save(searchHistory, to: searchHistoryURL)
        save(importedLists, to: importedListsURL)
        save(customHomeRows, to: customHomeRowsURL)
        save(customJSONHubs, to: customJSONHubsURL)
        
        // Reset hidden sections
        hiddenSections = .default
        save(hiddenSections, to: hiddenSectionsURL)
        
        // Reset browse sections order
        browseSections = BrowseSectionItem.defaultSections
        save(browseSections, to: browseSectionsURL)
        
        // Reset settings to defaults
        settings = UserSettings()
        save(settings, to: settingsURL)
        
        // Clear profiles
        ProfileService.shared.clearAllProfiles()
        
        // Disable cloud sync
        setCloudSyncEnabled(false)
        lastSyncError = nil
    }

    // MARK: - CloudKit Fallback Sync

    private func syncICloudSnapshotInBackground() {
        Task { @MainActor in
            await uploadToICloud()
        }
    }

    private func uploadToICloud() async {
        guard let userId = AuthService.shared.userId, !userId.isEmpty else {
            lastSyncError = "Sign in is required before syncing."
            return
        }
        do {
            let snapshot = makeCloudSnapshot()
            let data = try JSONEncoder().encode(snapshot)
            try await CloudKitSyncService.shared.uploadSnapshot(data: data, userId: userId)
            UserDefaults.standard.set(Date(), forKey: "cloud_last_sync")
            objectWillChange.send()
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private func downloadFromICloud() async {
        guard let userId = AuthService.shared.userId, !userId.isEmpty else {
            lastSyncError = "Sign in is required before syncing."
            return
        }
        do {
            guard let data = try await CloudKitSyncService.shared.downloadSnapshot(userId: userId) else { return }
            let snapshot = try JSONDecoder().decode(CloudSyncSnapshot.self, from: data)
            applyCloudSnapshot(snapshot)
            UserDefaults.standard.set(Date(), forKey: "cloud_last_sync")
            objectWillChange.send()
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private func makeCloudSnapshot() -> CloudSyncSnapshot {
        let profileService = ProfileService.shared
        return CloudSyncSnapshot(
            wantToWatch: wantToWatch,
            watched: watched,
            liked: liked,
            customLists: customLists,
            networkHubs: networkHubs,
            importedLists: importedLists,
            customHomeRows: customHomeRows,
            customJSONHubs: customJSONHubs,
            settings: settings,
            searchHistory: searchHistory,
            browseRows: browseRows,
            hiddenSections: hiddenSections,
            browseSections: browseSections,
            profiles: profileService.profiles,
            activeProfileId: profileService.activeProfile?.id,
            syncedAt: Date()
        )
    }

    private func applyCloudSnapshot(_ snapshot: CloudSyncSnapshot) {
        isApplyingCloudSnapshot = true
        defer { isApplyingCloudSnapshot = false }

        applyDownloadedMediaItems(snapshot.wantToWatch, snapshot.watched, snapshot.liked)

        customLists = snapshot.customLists
        save(customLists, to: customListsURL)
        networkHubs = snapshot.networkHubs
        save(networkHubs, to: networkHubsURL)
        importedLists = snapshot.importedLists
        save(importedLists, to: importedListsURL)
        customHomeRows = snapshot.customHomeRows
        save(customHomeRows, to: customHomeRowsURL)
        customJSONHubs = snapshot.customJSONHubs
        save(customJSONHubs, to: customJSONHubsURL)
        settings = snapshot.settings
        save(settings, to: settingsURL)
        searchHistory = snapshot.searchHistory
        save(searchHistory, to: searchHistoryURL)
        browseRows = snapshot.browseRows
        save(browseRows, to: browseRowsURL)
        hiddenSections = snapshot.hiddenSections
        save(hiddenSections, to: hiddenSectionsURL)
        browseSections = snapshot.browseSections
        save(browseSections, to: browseSectionsURL)

        ProfileService.shared.applyCloudProfiles(
            snapshot.profiles,
            preferredActiveId: snapshot.activeProfileId
        )
    }
}

private struct CloudSyncSnapshot: Codable {
    let wantToWatch: [SavedMediaItem]
    let watched: [SavedMediaItem]
    let liked: [SavedMediaItem]
    let customLists: [CustomList]
    let networkHubs: [NetworkHub]
    let importedLists: [ImportedListItem]
    let customHomeRows: [CustomHomeRow]
    let customJSONHubs: [CustomJSONHub]
    let settings: UserSettings
    let searchHistory: [SearchHistoryItem]
    let browseRows: [BrowseRowConfig]
    let hiddenSections: HiddenDefaultSections
    let browseSections: [BrowseSectionItem]
    let profiles: [UserProfile]
    let activeProfileId: String?
    let syncedAt: Date
}
