//
//  StorageService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation
import Combine

@MainActor
class StorageService: ObservableObject {
    static let shared = StorageService()

    private static let remoteStudioHubsURLString = "https://raw.githubusercontent.com/WatchGuide-app/Studios-hubs/refs/heads/main/studios.json"
    private static let remoteStudioAssetsBaseURLString = "https://raw.githubusercontent.com/WatchGuide-app/Studios-hubs/refs/heads/main/"
    private static let marvelMDBListPath = "dualipafan01/marvel-studios"
    
    // MARK: - Published Properties
    @Published private(set) var wantToWatch: [SavedMediaItem] = []
    @Published private(set) var watched: [SavedMediaItem] = []
    @Published private(set) var liked: [SavedMediaItem] = []
    @Published private(set) var continueWatching: [ContinueWatchingItem] = []
    @Published private(set) var watchSessions: [WatchSession] = []
    @Published private(set) var watchHistory: [WatchHistoryEntry] = []
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
        isSupabaseConfigured
    }
    
    /// Whether Supabase is configured
    var isSupabaseConfigured: Bool {
        let url = ApiKeyManager.shared.get(key: "SUPABASE_URL") ?? ""
        let key = ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY") ?? ""
        return !url.isEmpty && !key.isEmpty
    }

    var cloudProviderDisplayName: String {
        "Supabase"
    }

    private var isApplyingCloudSnapshot = false
    
    // MARK: - File URLs
    private let documentsDirectory: URL
    private let wantToWatchURL: URL
    private let watchedURL: URL
    private let likedURL: URL
    private let continueWatchingURL: URL
    private let watchSessionsURL: URL
    private let watchHistoryURL: URL
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
        continueWatchingURL = documentsDirectory.appendingPathComponent("continue_watching.json")
        watchSessionsURL = documentsDirectory.appendingPathComponent("watch_sessions.json")
        watchHistoryURL = documentsDirectory.appendingPathComponent("watch_history.json")
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
        Task { await migrateMarvelCustomHubIfNeeded() }
        initializeDefaultHubs()
        migrateCompanyHubsIfNeeded()
        initializeNetworkHubs()
        Task { await refreshCompanyHubsFromRemote() }
        
        // Load cloud sync preference
        cloudSyncEnabled = UserDefaults.standard.bool(forKey: "cloud_sync_enabled")
    }
    
    // MARK: - Load All Data
    private func loadAll() {
        wantToWatch = load(from: wantToWatchURL) ?? []
        watched = load(from: watchedURL) ?? []
        liked = load(from: likedURL) ?? []
        continueWatching = load(from: continueWatchingURL) ?? []
        watchSessions = load(from: watchSessionsURL) ?? []
        watchHistory = load(from: watchHistoryURL) ?? []
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
        migrateTrailerAddonSettingsIfNeeded()

        // Index all saved content into Spotlight for system-wide search
        #if canImport(CoreSpotlight) && !os(tvOS)
        SpotlightIndexingService.shared.indexAllContent()
        #endif
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
        var updated = browseRows
        var didChange = false

        if !updated.contains(where: { $0.endpoint == .trendingPeople }) {
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
            didChange = true
        }

        if !updated.contains(where: { $0.endpoint == .latestCertifiedFresh }) {
            let newRow = BrowseRowConfig(
                id: "latest_certified_fresh",
                title: BrowseRowConfig.latestHighRatedTitle,
                endpoint: .latestCertifiedFresh,
                isEnabled: true,
                sortOrder: 0
            )

            if let topRatedTVIndex = updated.firstIndex(where: { $0.endpoint == .topRatedTV }) {
                updated.insert(newRow, at: topRatedTVIndex + 1)
            } else if let comingSoonIndex = updated.firstIndex(where: { $0.endpoint == .upcomingMovies }) {
                updated.insert(newRow, at: comingSoonIndex)
            } else {
                updated.append(newRow)
            }
            didChange = true
        }

        for index in updated.indices
        where updated[index].endpoint == .latestCertifiedFresh && updated[index].title != BrowseRowConfig.latestHighRatedTitle {
            updated[index] = BrowseRowConfig(
                id: updated[index].id,
                title: BrowseRowConfig.latestHighRatedTitle,
                endpoint: updated[index].endpoint,
                isEnabled: updated[index].isEnabled,
                sortOrder: updated[index].sortOrder
            )
            didChange = true
        }

        for index in updated.indices where updated[index].endpoint == .upcomingMovies && updated[index].title != "Coming Soon" {
            updated[index] = BrowseRowConfig(
                id: updated[index].id,
                title: "Coming Soon",
                endpoint: updated[index].endpoint,
                isEnabled: updated[index].isEnabled,
                sortOrder: updated[index].sortOrder
            )
            didChange = true
        }

        guard didChange else { return }

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

        // Insert Continue Watching at the top for existing users
        if !existing.contains(.continueWatching) {
            let newSection = BrowseSectionItem(
                id: "sec_continue_watching",
                sectionType: .continueWatching,
                isEnabled: true,
                sortOrder: -1
            )
            updated.insert(newSection, at: 0)
        }

        for def in BrowseSectionItem.defaultSections where !existing.contains(def.sectionType) && def.sectionType != .continueWatching {
            var newSec = def
            newSec.sortOrder = updated.count
            updated.append(newSec)
        }
        if updated.count != browseSections.count {
            // Renumber sort orders
            for i in updated.indices {
                updated[i].sortOrder = i
            }
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
            CompanyHub(name: "DC", logoPath: nil, companyIds: [429, 184898], networkIds: []),
            CompanyHub(name: "Pixar", logoPath: nil, companyIds: [3], networkIds: []),
            CompanyHub(name: "Universal Pictures", logoPath: nil, companyIds: [33], networkIds: []),
            CompanyHub(name: "Searchlight Pictures", logoPath: nil, companyIds: [127929], networkIds: []),
            CompanyHub(name: "Dreamworks", logoPath: nil, companyIds: [521], networkIds: []),
            CompanyHub(name: "Illumination", logoPath: nil, companyIds: [6704], networkIds: []),
        ]
        
        companyHubs = defaultHubs
        save(companyHubs, to: companyHubsURL)
    }

    private func migrateCompanyHubsIfNeeded() {
        let requiredHubs: [(name: String, companyIds: [Int])] = [
            ("DC", [429, 184898]),
            ("Searchlight Pictures", [127929]),
            ("Dreamworks", [521]),
            ("Illumination", [6704])
        ]

        var updated = companyHubs
        var didChange = false

        if let dcIndex = updated.firstIndex(where: {
            $0.name.caseInsensitiveCompare("DC Studios") == .orderedSame ||
            $0.name.caseInsensitiveCompare("DC") == .orderedSame
        }) {
            let existing = updated[dcIndex]
            let mergedCompanyIds = Array(Set(existing.companyIds + [429, 184898])).sorted()
            let renamed = CompanyHub(
                id: existing.id,
                name: "DC",
                logoPath: existing.logoPath,
                companyIds: mergedCompanyIds,
                networkIds: existing.networkIds,
                isEnabled: existing.isEnabled,
                buttonShape: existing.buttonShape,
                backgroundStyle: existing.backgroundStyle,
                createdAt: existing.createdAt
            )
            if existing.name != renamed.name || existing.companyIds != renamed.companyIds {
                updated[dcIndex] = renamed
                didChange = true
            }
        }

        for required in requiredHubs {
            guard !updated.contains(where: { $0.name.caseInsensitiveCompare(required.name) == .orderedSame }) else {
                continue
            }
            updated.append(CompanyHub(name: required.name, logoPath: nil, companyIds: required.companyIds, networkIds: []))
            didChange = true
        }

        if didChange {
            companyHubs = updated
            save(companyHubs, to: companyHubsURL)
        }
    }

    private struct RemoteStudioHub: Decodable {
        let name: String
        let logoURL: String?
        let logoPath: String?
        let companyId: Int?
        let companyIds: [Int]?
        let networkIds: [Int]?
        let buttonShape: String?
        let backgroundStyle: String?
        let isEnabled: Bool?

        enum CodingKeys: String, CodingKey {
            case name
            case logoURL
            case logoPath
            case companyId
            case companyIds
            case networkIds
            case buttonShape
            case backgroundStyle
            case isEnabled
        }
    }

    private func normalizeRemoteLogoPath(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        return Self.remoteStudioAssetsBaseURLString + value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func makeCompanyHub(from remote: RemoteStudioHub) -> CompanyHub? {
        let ids = remote.companyIds ?? (remote.companyId.map { [$0] } ?? [])
        guard !remote.name.isEmpty, !ids.isEmpty else { return nil }
        return CompanyHub(
            name: remote.name,
            logoPath: normalizeRemoteLogoPath(remote.logoURL ?? remote.logoPath),
            companyIds: ids,
            networkIds: remote.networkIds ?? [],
            buttonShape: remote.buttonShape.flatMap { CompanyHub.ButtonShape(rawValue: $0) },
            backgroundStyle: remote.backgroundStyle.flatMap { CompanyHub.BackgroundStyle(rawValue: $0) }
        )
    }

    func refreshCompanyHubsFromRemote() async {
        guard let url = URL(string: Self.remoteStudioHubsURLString) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return
            }

            let decoder = JSONDecoder()
            let remoteEntries = try decoder.decode([RemoteStudioHub].self, from: data)
            let remoteHubs = remoteEntries.compactMap { makeCompanyHub(from: $0) }
            guard !remoteHubs.isEmpty else { return }

            if companyHubs.isEmpty {
                companyHubs = remoteHubs
                save(companyHubs, to: companyHubsURL)
                return
            }

            var merged = companyHubs
            for remote in remoteHubs {
                if let existingIndex = merged.firstIndex(where: { $0.name.caseInsensitiveCompare(remote.name) == .orderedSame }) {
                    let existing = merged[existingIndex]
                    let updated = CompanyHub(
                        id: existing.id,
                        name: existing.name,
                        logoPath: remote.logoPath ?? existing.logoPath,
                        companyIds: remote.companyIds,
                        networkIds: remote.networkIds,
                        isEnabled: existing.isEnabled,
                        buttonShape: existing.buttonShape ?? remote.buttonShape,
                        backgroundStyle: existing.backgroundStyle ?? remote.backgroundStyle,
                        createdAt: existing.createdAt
                    )
                    merged[existingIndex] = updated
                } else {
                    merged.append(remote)
                }
            }

            companyHubs = merged
            save(companyHubs, to: companyHubsURL)
        } catch {
            print("Failed to refresh remote studio hubs: \(error)")
        }
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
        #if canImport(CoreSpotlight) && !os(tvOS)
        SpotlightIndexingService.shared.indexItem(item, listType: .wantToWatch)
        #endif
        Task {
            await TraktService.shared.addToWatchlist(item)
        }
    }
    
    func removeFromWantToWatch(_ item: SavedMediaItem) {
        wantToWatch.removeAll { $0.id == item.id }
        save(wantToWatch, to: wantToWatchURL)
        syncRemoveFromCloud(mediaId: item.mediaId, mediaType: item.mediaType, listType: .wantToWatch)
        #if canImport(CoreSpotlight) && !os(tvOS)
        SpotlightIndexingService.shared.removeItem(item)
        #endif
        Task {
            await TraktService.shared.removeFromWatchlist(item)
        }
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
        #if canImport(CoreSpotlight) && !os(tvOS)
        SpotlightIndexingService.shared.indexItem(item, listType: .watched)
        #endif
    }
    
    func removeFromWatched(_ item: SavedMediaItem) {
        watched.removeAll { $0.id == item.id }
        save(watched, to: watchedURL)
        syncRemoveFromCloud(mediaId: item.mediaId, mediaType: item.mediaType, listType: .watched)
        #if canImport(CoreSpotlight) && !os(tvOS)
        SpotlightIndexingService.shared.removeItem(item)
        #endif
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
        #if canImport(CoreSpotlight) && !os(tvOS)
        SpotlightIndexingService.shared.indexItem(item, listType: .liked)
        #endif
        Task {
            await TraktService.shared.addLike(item)
        }
    }
    
    func removeFromLiked(_ item: SavedMediaItem) {
        liked.removeAll { $0.id == item.id }
        save(liked, to: likedURL)
        syncRemoveFromCloud(mediaId: item.mediaId, mediaType: item.mediaType, listType: .liked)
        #if canImport(CoreSpotlight) && !os(tvOS)
        SpotlightIndexingService.shared.removeItem(item)
        #endif
        Task {
            await TraktService.shared.removeLike(item)
        }
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

    // MARK: - Trakt Merge

    func mergeTraktWatchlist(_ items: [SavedMediaItem]) {
        wantToWatch = mergedItems(prioritizing: items, existing: wantToWatch)
        save(wantToWatch, to: wantToWatchURL)
    }

    func mergeTraktWatched(_ items: [SavedMediaItem]) {
        watched = mergedItems(prioritizing: items, existing: watched)
        save(watched, to: watchedURL)
    }

    func mergeTraktLiked(_ items: [SavedMediaItem]) {
        liked = mergedItems(prioritizing: items, existing: liked)
        save(liked, to: likedURL)
    }

    func updateContinueWatching(_ items: [ContinueWatchingItem]) {
        continueWatching = items.sorted { $0.lastUpdated > $1.lastUpdated }
        save(continueWatching, to: continueWatchingURL)
    }

    func clearContinueWatching() {
        continueWatching = []
        save(continueWatching, to: continueWatchingURL)
    }

    func upsertContinueWatchingItem(_ item: ContinueWatchingItem) {
        if let index = continueWatching.firstIndex(where: { $0.id == item.id }) {
            continueWatching[index] = item
        } else {
            continueWatching.insert(item, at: 0)
        }
        continueWatching.sort { $0.lastUpdated > $1.lastUpdated }
        save(continueWatching, to: continueWatchingURL)
    }

    func removeContinueWatchingItem(id: String) {
        continueWatching.removeAll { $0.id == id }
        save(continueWatching, to: continueWatchingURL)
    }

    // MARK: - WatchHour Sessions & History

    func upsertWatchSession(_ session: WatchSession) {
        if let index = watchSessions.firstIndex(where: { $0.id == session.id }) {
            watchSessions[index] = session
        } else {
            watchSessions.insert(session, at: 0)
        }
        save(watchSessions, to: watchSessionsURL)
        syncWatchHourToCloud()
    }

    func removeWatchSession(id: String) {
        watchSessions.removeAll { $0.id == id }
        save(watchSessions, to: watchSessionsURL)
        syncWatchHourToCloud()
    }

    func appendWatchHistory(_ entry: WatchHistoryEntry) {
        watchHistory.insert(entry, at: 0)
        // Keep history bounded to a sensible size.
        if watchHistory.count > 500 {
            watchHistory = Array(watchHistory.prefix(500))
        }
        save(watchHistory, to: watchHistoryURL)
        syncWatchHourToCloud()
    }

    func updateWatchHistoryRating(entryId: String, rating: Int) {
        guard let index = watchHistory.firstIndex(where: { $0.id == entryId }) else { return }
        watchHistory[index].rating = rating
        save(watchHistory, to: watchHistoryURL)
        syncWatchHourToCloud()
    }

    func clearWatchHistory() {
        watchHistory = []
        save(watchHistory, to: watchHistoryURL)
        syncWatchHourToCloud()
    }

    /// Best-effort background sync of WatchHour data via the cloud snapshot.
    private func syncWatchHourToCloud() {
        guard !isApplyingCloudSnapshot, cloudSyncEnabled else { return }
        syncICloudSnapshotInBackground()
    }

    private func mergedItems(prioritizing incoming: [SavedMediaItem], existing: [SavedMediaItem]) -> [SavedMediaItem] {
        var seen = Set<String>()
        var merged: [SavedMediaItem] = []

        for item in incoming where seen.insert(item.id).inserted {
            merged.append(item)
        }

        for item in existing where seen.insert(item.id).inserted {
            merged.append(item)
        }

        return merged
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
                settings = normalizedSettings(cloudSettings)
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
        var mergedBrowseRows = homeConfig.browseRows.map { row in
            switch row.endpoint {
            case .latestCertifiedFresh:
                guard row.title != BrowseRowConfig.latestHighRatedTitle else {
                    return row
                }

                return BrowseRowConfig(
                    id: row.id,
                    title: BrowseRowConfig.latestHighRatedTitle,
                    endpoint: row.endpoint,
                    isEnabled: row.isEnabled,
                    sortOrder: row.sortOrder
                )
            case .upcomingMovies:
                guard row.title != "Coming Soon" else {
                    return row
                }

                return BrowseRowConfig(
                    id: row.id,
                    title: "Coming Soon",
                    endpoint: row.endpoint,
                    isEnabled: row.isEnabled,
                    sortOrder: row.sortOrder
                )
            default:
                return row
            }
        }
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
    @discardableResult
    func createCustomList(name: String, description: String? = nil, iconName: String = "folder.fill", displayStyle: CustomList.DisplayStyle = .row) -> Bool {
        guard AIMessageQuota.canCreateCustomList(currentCount: customLists.count) else { return false }
        let list = CustomList(name: name, description: description, iconName: iconName, displayStyle: displayStyle)
        customLists.append(list)
        save(customLists, to: customListsURL)
        syncCustomListsToCloud()
        return true
    }

    func createCustomListAndReturn(name: String, description: String? = nil, iconName: String = "folder.fill", displayStyle: CustomList.DisplayStyle = .row) -> CustomList? {
        guard AIMessageQuota.canCreateCustomList(currentCount: customLists.count) else { return nil }
        let list = CustomList(name: name, description: description, iconName: iconName, displayStyle: displayStyle)
        customLists.append(list)
        save(customLists, to: customListsURL)
        syncCustomListsToCloud()
        return list
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

    func reorderCompanyHubs(_ hubs: [CompanyHub]) {
        companyHubs = hubs
        save(companyHubs, to: companyHubsURL)
    }

    func getEnabledCompanyHubs() -> [CompanyHub] {
        companyHubs.filter { $0.isEnabled }
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
        settings = normalizedSettings(newSettings)
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

    private func migrateTrailerAddonSettingsIfNeeded() {
        // v2: remove Trailerio from the list entirely so users must manually add it.
        // Supersedes v1 (which only disabled it). Syncs the change to cloud.
        let migrationKey = "trailerAddonDefaultDisableMigration_v2"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            let before = settings.trailerAddons
            settings.trailerAddons = before.filter { addon in
                !addon.baseURL
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .contains("trailerio.cc")
            }
            if settings.trailerAddons != before {
                save(settings, to: settingsURL)
                syncSettingsToCloud()
            }
            UserDefaults.standard.set(true, forKey: migrationKey)
        }

        if ensureDefaultTrailerAddons() {
            save(settings, to: settingsURL)
            syncSettingsToCloud()
        }

        let normalized = normalizedSettings(settings)
        guard normalized != settings else { return }
        settings = normalized
        save(settings, to: settingsURL)
    }

    /// Ensures every default addon is present in settings. Returns true if any were added.
    /// Called both on startup and after cloud sync, so a cloud snapshot that deleted an addon
    /// never permanently removes it.
    @discardableResult
    private func ensureDefaultTrailerAddons() -> Bool {
        var modified = false
        for defaultAddon in TrailerAddon.defaultAddons {
            let exists = settings.trailerAddons.contains {
                $0.baseURL
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .contains(defaultAddon.baseURL.lowercased())
            }
            if !exists {
                settings.trailerAddons.insert(defaultAddon, at: 0)
                modified = true
            }
        }
        return modified
    }

    private func migrateMarvelCustomHubIfNeeded() async {
        let targetPath = Self.marvelMDBListPath
        let targetJSONURL = "mdblist://\(targetPath)"

        var updatedHubs = customJSONHubs
        var didMutate = false

        for index in updatedHubs.indices {
            let hub = updatedHubs[index]
            let normalizedName = hub.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedRowName = hub.rowName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isMarvelHub = normalizedName == "marvel" || normalizedName == "marvel studios" || normalizedRowName == "marvel" || normalizedRowName == "marvel studios"

            guard isMarvelHub else { continue }

            if hub.mdblistId == targetPath,
               hub.mdblistIds == [targetPath],
               hub.jsonURL == targetJSONURL {
                continue
            }

            updatedHubs[index].source = .mdblist
            updatedHubs[index].jsonURL = targetJSONURL
            updatedHubs[index].mdblistId = targetPath
            updatedHubs[index].mdblistIds = [targetPath]
            updatedHubs[index].lastSynced = nil
            didMutate = true
        }

        guard didMutate else { return }

        customJSONHubs = updatedHubs
        save(customJSONHubs, to: customJSONHubsURL)
        syncCustomJSONHubsToCloud()

        for index in customJSONHubs.indices {
            let hub = customJSONHubs[index]
            let normalizedName = hub.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedRowName = hub.rowName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isMarvelHub = normalizedName == "marvel" || normalizedName == "marvel studios" || normalizedRowName == "marvel" || normalizedRowName == "marvel studios"

            guard isMarvelHub else { continue }

            do {
                let items = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: targetPath)
                customJSONHubs[index].items = items
                customJSONHubs[index].lastSynced = Date()
            } catch {
                print("Marvel custom hub migration refresh failed: \(error)")
            }
        }

        save(customJSONHubs, to: customJSONHubsURL)
        syncCustomJSONHubsToCloud()
    }

    private func normalizedSettings(_ value: UserSettings) -> UserSettings {
        var normalized = value

        // Migrate old trailio.cc URLs to trailerio.cc
        normalized.trailerAddons = normalized.trailerAddons.map { addon in
            let lower = addon.baseURL.lowercased()
            if lower.contains("trailio.cc") && !lower.contains("trailerio.cc") {
                var migrated = addon
                migrated.baseURL = addon.baseURL.replacingOccurrences(
                    of: "trailio.cc",
                    with: "trailerio.cc",
                    options: .caseInsensitive
                )
                if migrated.name == "Trailio" {
                    migrated.name = "Trailerio"
                }
                return migrated
            }
            return addon
        }

        var seenURLs = Set<String>()
        normalized.trailerAddons = normalized.trailerAddons.filter { addon in
            let key = normalizedTrailerAddonURL(addon.baseURL)
            if seenURLs.contains(key) {
                return false
            }
            seenURLs.insert(key)
            return true
        }

        return normalized
    }

    private func normalizedTrailerAddonURL(_ url: String) -> String {
        url
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
            watchSessions: watchSessions,
            watchHistory: watchHistory,
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
        settings = normalizedSettings(snapshot.settings)
        ensureDefaultTrailerAddons()
        save(settings, to: settingsURL)
        searchHistory = snapshot.searchHistory
        save(searchHistory, to: searchHistoryURL)
        browseRows = snapshot.browseRows
        save(browseRows, to: browseRowsURL)
        hiddenSections = snapshot.hiddenSections
        save(hiddenSections, to: hiddenSectionsURL)
        browseSections = snapshot.browseSections
        save(browseSections, to: browseSectionsURL)

        watchSessions = snapshot.watchSessions ?? []
        save(watchSessions, to: watchSessionsURL)
        watchHistory = snapshot.watchHistory ?? []
        save(watchHistory, to: watchHistoryURL)

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
    let watchSessions: [WatchSession]?
    let watchHistory: [WatchHistoryEntry]?
    let syncedAt: Date
}
