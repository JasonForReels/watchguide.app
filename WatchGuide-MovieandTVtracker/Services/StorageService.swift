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
    @Published private(set) var mdbLists: [MDBListItem] = []
    @Published private(set) var settings: UserSettings = UserSettings()
    @Published private(set) var searchHistory: [SearchHistoryItem] = []
    @Published private(set) var browseRows: [BrowseRowConfig] = BrowseRowConfig.defaultRows
    
    // MARK: - File URLs
    private let documentsDirectory: URL
    private let wantToWatchURL: URL
    private let watchedURL: URL
    private let likedURL: URL
    private let customListsURL: URL
    private let companyHubsURL: URL
    private let mdbListsURL: URL
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
        mdbListsURL = documentsDirectory.appendingPathComponent("mdb_lists.json")
        settingsURL = documentsDirectory.appendingPathComponent("settings.json")
        searchHistoryURL = documentsDirectory.appendingPathComponent("search_history.json")
        browseRowsURL = documentsDirectory.appendingPathComponent("browse_rows.json")
        
        loadAll()
        initializeDefaultHubs()
    }
    
    // MARK: - Load All Data
    private func loadAll() {
        wantToWatch = load(from: wantToWatchURL) ?? []
        watched = load(from: watchedURL) ?? []
        liked = load(from: likedURL) ?? []
        customLists = load(from: customListsURL) ?? []
        companyHubs = load(from: companyHubsURL) ?? []
        mdbLists = load(from: mdbListsURL) ?? []
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
    
    // MARK: - Default Company Hubs
    private func initializeDefaultHubs() {
        guard companyHubs.isEmpty else { return }
        
        let defaultHubs = [
            CompanyHub(name: "Warner Bros.", logoPath: nil, companyIds: [174, 17, 429, 76043], networkIds: []),
            CompanyHub(name: "Walt Disney Pictures", logoPath: nil, companyIds: [2, 3, 420, 7505, 7521], networkIds: [2739]),
            CompanyHub(name: "Marvel Studios", logoPath: nil, companyIds: [420], networkIds: []),
            CompanyHub(name: "DC Studios", logoPath: nil, companyIds: [128064, 174], networkIds: []),
            CompanyHub(name: "Pixar", logoPath: nil, companyIds: [3], networkIds: []),
            CompanyHub(name: "Universal Pictures", logoPath: nil, companyIds: [33], networkIds: []),
            CompanyHub(name: "Netflix", logoPath: nil, companyIds: [213], networkIds: [213]),
            CompanyHub(name: "Apple TV+", logoPath: nil, companyIds: [158420], networkIds: [2552]),
            CompanyHub(name: "HBO", logoPath: nil, companyIds: [3268], networkIds: [49]),
            CompanyHub(name: "Amazon Studios", logoPath: nil, companyIds: [20580], networkIds: [1024]),
        ]
        
        companyHubs = defaultHubs
        save(companyHubs, to: companyHubsURL)
    }
    
    // MARK: - Want to Watch
    func addToWantToWatch(_ item: SavedMediaItem) {
        guard !wantToWatch.contains(where: { $0.id == item.id }) else { return }
        wantToWatch.insert(item, at: 0)
        save(wantToWatch, to: wantToWatchURL)
    }
    
    func removeFromWantToWatch(_ item: SavedMediaItem) {
        wantToWatch.removeAll { $0.id == item.id }
        save(wantToWatch, to: wantToWatchURL)
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
    }
    
    func removeFromWatched(_ item: SavedMediaItem) {
        watched.removeAll { $0.id == item.id }
        save(watched, to: watchedURL)
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
    }
    
    func removeFromLiked(_ item: SavedMediaItem) {
        liked.removeAll { $0.id == item.id }
        save(liked, to: likedURL)
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
    
    // MARK: - MDB Lists
    func addMDBList(_ list: MDBListItem) {
        mdbLists.append(list)
        save(mdbLists, to: mdbListsURL)
    }
    
    func updateMDBList(_ list: MDBListItem) {
        if let index = mdbLists.firstIndex(where: { $0.id == list.id }) {
            mdbLists[index] = list
            save(mdbLists, to: mdbListsURL)
        }
    }
    
    func deleteMDBList(id: String) {
        mdbLists.removeAll { $0.id == id }
        save(mdbLists, to: mdbListsURL)
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
