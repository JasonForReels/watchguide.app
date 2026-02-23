//
//  CloudKitSyncService.swift
//  WatchGuide-MovieandTVtracker
//
//  iCloud/CloudKit data sync as an alternative to Supabase
//

import Foundation
import CloudKit

actor CloudKitSyncService {
    static let shared = CloudKitSyncService()
    
    private var _container: CKContainer?
    private var container: CKContainer {
        if let c = _container { return c }
        let c = CKContainer(identifier: "iCloud.com.JasonSmith.WatchGuide-MovieandTVtracker")
        _container = c
        return c
    }
    private var privateDB: CKDatabase {
        container.privateCloudDatabase
    }
    
    // Record types
    private let mediaItemType = "MediaItem"
    private let userSettingsType = "UserSettings"
    private let customListType = "CustomList"
    private let customListItemType = "CustomListItem"
    private let profileType = "UserProfile"
    private let browseConfigType = "BrowseConfig"
    private let networkHubConfigType = "NetworkHubConfig"
    private let hiddenSectionsType = "HiddenSections"
    private let browseSectionType = "BrowseSection"
    private let extensionListType = "ExtensionList"
    private let extensionListItemType = "ExtensionListItem"
    private let customHomeRowType = "CustomHomeRow"
    private let customJSONHubType = "CustomJSONHub"
    
    private init() {
        // Lazy initialization — container is created on first use, not at init time
    }
    
    // MARK: - Account Status
    
    func isAvailable() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            print("CloudKit account check failed: \(error)")
            return false
        }
    }
    
    // MARK: - Media Items
    
    func uploadAllMediaItems(
        wantToWatch: [SavedMediaItem],
        watched: [SavedMediaItem],
        liked: [SavedMediaItem]
    ) async throws {
        // Delete existing media items
        try await deleteAllRecords(ofType: mediaItemType)
        
        var records: [CKRecord] = []
        
        for item in wantToWatch {
            records.append(mediaItemRecord(item, listType: "want_to_watch"))
        }
        for item in watched {
            records.append(mediaItemRecord(item, listType: "watched"))
        }
        for item in liked {
            records.append(mediaItemRecord(item, listType: "liked"))
        }
        
        try await batchSave(records)
    }
    
    func downloadAllMediaItems() async throws -> (wantToWatch: [SavedMediaItem], watched: [SavedMediaItem], liked: [SavedMediaItem]) {
        let records = try await fetchAllRecords(ofType: mediaItemType)
        
        var wantToWatch: [SavedMediaItem] = []
        var watched: [SavedMediaItem] = []
        var liked: [SavedMediaItem] = []
        
        for record in records {
            guard let item = savedMediaItem(from: record),
                  let listType = record["listType"] as? String else { continue }
            
            switch listType {
            case "want_to_watch": wantToWatch.append(item)
            case "watched": watched.append(item)
            case "liked": liked.append(item)
            default: break
            }
        }
        
        return (wantToWatch, watched, liked)
    }
    
    func addMediaItem(_ item: SavedMediaItem, listType: SyncListType) async throws {
        let record = mediaItemRecord(item, listType: listType.rawValue)
        try await privateDB.save(record)
    }
    
    func removeMediaItem(mediaId: Int, mediaType: MediaType, listType: SyncListType) async throws {
        let predicate = NSPredicate(format: "mediaId == %d AND mediaType == %@ AND listType == %@",
                                    mediaId, mediaType.rawValue, listType.rawValue)
        let query = CKQuery(recordType: mediaItemType, predicate: predicate)
        let results = try await privateDB.records(matching: query)
        
        for (recordID, _) in results.matchResults {
            try await privateDB.deleteRecord(withID: recordID)
        }
    }
    
    // MARK: - User Settings
    
    func uploadSettings(_ settings: UserSettings) async throws {
        try await deleteAllRecords(ofType: userSettingsType)
        
        let record = CKRecord(recordType: userSettingsType)
        record["region"] = settings.region as CKRecordValue
        record["preferredLanguage"] = settings.preferredLanguage as CKRecordValue
        record["includeAdult"] = (settings.includeAdult ? 1 : 0) as CKRecordValue
        record["autoPlayTrailers"] = (settings.autoPlayTrailers ? 1 : 0) as CKRecordValue
        record["autoPlayTrailersMuted"] = (settings.autoPlayTrailersMuted ? 1 : 0) as CKRecordValue
        record["compactMode"] = (settings.compactMode ? 1 : 0) as CKRecordValue
        record["ambientModeEnabled"] = (settings.ambientModeEnabled ? 1 : 0) as CKRecordValue
        record["heroCarouselSource"] = settings.heroCarouselSource.rawValue as CKRecordValue
        record["isKidsProfile"] = (settings.isKidsProfile ? 1 : 0) as CKRecordValue
        if let passcode = settings.parentPasscode {
            record["parentPasscode"] = passcode as CKRecordValue
        }
        if let movieListId = settings.heroCarouselCustomMovieListId {
            record["heroCarouselCustomMovieListId"] = movieListId as CKRecordValue
        }
        if let showListId = settings.heroCarouselCustomShowListId {
            record["heroCarouselCustomShowListId"] = showListId as CKRecordValue
        }
        if let mdbMovieId = settings.heroCarouselMDBListMovieId {
            record["heroCarouselMDBListMovieId"] = mdbMovieId as CKRecordValue
        }
        if let mdbShowId = settings.heroCarouselMDBListShowId {
            record["heroCarouselMDBListShowId"] = mdbShowId as CKRecordValue
        }
        
        try await privateDB.save(record)
    }
    
    func downloadSettings() async throws -> UserSettings? {
        let records = try await fetchAllRecords(ofType: userSettingsType)
        guard let record = records.first else { return nil }
        
        var settings = UserSettings()
        if let region = record["region"] as? String { settings.region = region }
        if let lang = record["preferredLanguage"] as? String { settings.preferredLanguage = lang }
        if let val = record["includeAdult"] as? Int64 { settings.includeAdult = val == 1 }
        if let val = record["autoPlayTrailers"] as? Int64 { settings.autoPlayTrailers = val == 1 }
        if let val = record["autoPlayTrailersMuted"] as? Int64 { settings.autoPlayTrailersMuted = val == 1 }
        if let val = record["compactMode"] as? Int64 { settings.compactMode = val == 1 }
        if let val = record["ambientModeEnabled"] as? Int64 { settings.ambientModeEnabled = val == 1 }
        if let src = record["heroCarouselSource"] as? String, let source = HeroCarouselSource(rawValue: src) {
            settings.heroCarouselSource = source
        }
        if let val = record["isKidsProfile"] as? Int64 { settings.isKidsProfile = val == 1 }
        settings.parentPasscode = record["parentPasscode"] as? String
        settings.heroCarouselCustomMovieListId = record["heroCarouselCustomMovieListId"] as? String
        settings.heroCarouselCustomShowListId = record["heroCarouselCustomShowListId"] as? String
        settings.heroCarouselMDBListMovieId = record["heroCarouselMDBListMovieId"] as? String
        settings.heroCarouselMDBListShowId = record["heroCarouselMDBListShowId"] as? String
        
        return settings
    }
    
    // MARK: - Custom Lists
    
    func uploadCustomLists(_ lists: [CustomList]) async throws {
        try await deleteAllRecords(ofType: customListType)
        try await deleteAllRecords(ofType: customListItemType)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        for list in lists {
            let record = CKRecord(recordType: customListType)
            record["listId"] = list.id as CKRecordValue
            record["name"] = list.name as CKRecordValue
            if let desc = list.description { record["listDescription"] = desc as CKRecordValue }
            record["iconName"] = list.iconName as CKRecordValue
            record["displayStyle"] = list.displayStyle.rawValue as CKRecordValue
            record["createdAt"] = list.createdAt as CKRecordValue
            record["updatedAt"] = list.updatedAt as CKRecordValue
            
            try await privateDB.save(record)
            
            // Save list items
            var itemRecords: [CKRecord] = []
            for (index, item) in list.items.enumerated() {
                let itemRecord = CKRecord(recordType: customListItemType)
                itemRecord["listId"] = list.id as CKRecordValue
                itemRecord["mediaId"] = item.mediaId as CKRecordValue
                itemRecord["mediaType"] = item.mediaType.rawValue as CKRecordValue
                itemRecord["title"] = item.title as CKRecordValue
                if let poster = item.posterPath { itemRecord["posterPath"] = poster as CKRecordValue }
                if let backdrop = item.backdropPath { itemRecord["backdropPath"] = backdrop as CKRecordValue }
                if let year = item.year { itemRecord["year"] = year as CKRecordValue }
                if let rating = item.voteAverage { itemRecord["voteAverage"] = rating as CKRecordValue }
                if let overview = item.overview { itemRecord["overview"] = overview as CKRecordValue }
                itemRecord["sortOrder"] = index as CKRecordValue
                itemRecord["addedAt"] = item.addedAt as CKRecordValue
                itemRecords.append(itemRecord)
            }
            
            if !itemRecords.isEmpty {
                try await batchSave(itemRecords)
            }
        }
    }
    
    func downloadCustomLists() async throws -> [CustomList] {
        let listRecords = try await fetchAllRecords(ofType: customListType)
        let itemRecords = try await fetchAllRecords(ofType: customListItemType)
        
        let itemsByList = Dictionary(grouping: itemRecords, by: { $0["listId"] as? String ?? "" })
        
        return listRecords.compactMap { record -> CustomList? in
            guard let listId = record["listId"] as? String,
                  let name = record["name"] as? String else { return nil }
            
            let desc = record["listDescription"] as? String
            let iconName = record["iconName"] as? String ?? "folder.fill"
            let styleRaw = record["displayStyle"] as? String ?? "row"
            let style = CustomList.DisplayStyle(rawValue: styleRaw) ?? .row
            let createdAt = record["createdAt"] as? Date ?? Date()
            let updatedAt = record["updatedAt"] as? Date ?? Date()
            
            let items: [SavedMediaItem] = (itemsByList[listId] ?? [])
                .sorted { ($0["sortOrder"] as? Int ?? 0) < ($1["sortOrder"] as? Int ?? 0) }
                .compactMap { savedMediaItem(from: $0) }
            
            return CustomList(
                id: listId,
                name: name,
                description: desc,
                iconName: iconName,
                displayStyle: style,
                items: items,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }
    
    // MARK: - Profiles
    
    func uploadProfiles(_ profiles: [UserProfile]) async throws {
        try await deleteAllRecords(ofType: profileType)
        
        let dateFormatter = ISO8601DateFormatter()
        var records: [CKRecord] = []
        
        for profile in profiles {
            let record = CKRecord(recordType: profileType)
            record["profileId"] = profile.id as CKRecordValue
            record["name"] = profile.name as CKRecordValue
            record["avatar"] = profile.avatar.rawValue as CKRecordValue
            record["color"] = profile.color.rawValue as CKRecordValue
            record["ageGroup"] = profile.ageGroup.rawValue as CKRecordValue
            record["isKids"] = (profile.isKids ? 1 : 0) as CKRecordValue
            if let dob = profile.dateOfBirth {
                record["dateOfBirth"] = dateFormatter.string(from: dob) as CKRecordValue
            }
            if let widthRatio = profile.heroCarouselWidthRatio {
                record["heroCarouselWidthRatio"] = widthRatio as CKRecordValue
            }
            if let aspect = profile.heroCarouselAspect {
                record["heroCarouselAspect"] = aspect.rawValue as CKRecordValue
            }
            record["createdAt"] = profile.createdAt as CKRecordValue
            record["updatedAt"] = profile.updatedAt as CKRecordValue
            records.append(record)
        }
        
        try await batchSave(records)
    }
    
    func downloadProfiles() async throws -> [UserProfile] {
        let records = try await fetchAllRecords(ofType: profileType)
        let dateFormatter = ISO8601DateFormatter()
        
        return records
            .sorted { ($0["createdAt"] as? Date ?? Date()) < ($1["createdAt"] as? Date ?? Date()) }
            .compactMap { record -> UserProfile? in
                guard let profileId = record["profileId"] as? String,
                      let name = record["name"] as? String,
                      let avatarRaw = record["avatar"] as? String,
                      let colorRaw = record["color"] as? String,
                      let ageGroupRaw = record["ageGroup"] as? String,
                      let avatar = ProfileAvatar(rawValue: avatarRaw),
                      let color = ProfileColor(rawValue: colorRaw),
                      let ageGroup = AgeGroup(rawValue: ageGroupRaw) else { return nil }
                
                let isKids = (record["isKids"] as? Int64 ?? 0) == 1
                let dob = (record["dateOfBirth"] as? String).flatMap { dateFormatter.date(from: $0) }
                let widthRatio = record["heroCarouselWidthRatio"] as? Double
                let aspect = (record["heroCarouselAspect"] as? String).flatMap { HeroCarouselAspect(rawValue: $0) }
                let createdAt = record["createdAt"] as? Date ?? Date()
                let updatedAt = record["updatedAt"] as? Date ?? Date()
                
                return UserProfile(
                    id: profileId,
                    name: name,
                    avatar: avatar,
                    color: color,
                    ageGroup: ageGroup,
                    isKids: isKids,
                    dateOfBirth: dob,
                    heroCarouselWidthRatio: widthRatio,
                    heroCarouselAspect: aspect,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            }
    }
    
    // MARK: - Browse Config
    
    func uploadBrowseConfig(_ rows: [BrowseRowConfig]) async throws {
        try await deleteAllRecords(ofType: browseConfigType)
        
        var records: [CKRecord] = []
        for row in rows {
            let record = CKRecord(recordType: browseConfigType)
            record["rowId"] = row.id as CKRecordValue
            record["title"] = row.title as CKRecordValue
            record["endpoint"] = row.endpoint.rawValue as CKRecordValue
            record["isEnabled"] = (row.isEnabled ? 1 : 0) as CKRecordValue
            record["sortOrder"] = row.sortOrder as CKRecordValue
            records.append(record)
        }
        try await batchSave(records)
    }
    
    func downloadBrowseConfig() async throws -> [BrowseRowConfig] {
        let records = try await fetchAllRecords(ofType: browseConfigType)
        return records.compactMap { record -> BrowseRowConfig? in
            guard let rowId = record["rowId"] as? String,
                  let title = record["title"] as? String,
                  let endpointRaw = record["endpoint"] as? String,
                  let endpoint = BrowseRowConfig.BrowseEndpoint(rawValue: endpointRaw) else { return nil }
            
            let isEnabled = (record["isEnabled"] as? Int64 ?? 1) == 1
            let sortOrder = record["sortOrder"] as? Int ?? 0
            
            return BrowseRowConfig(id: rowId, title: title, endpoint: endpoint, isEnabled: isEnabled, sortOrder: sortOrder)
        }
    }
    
    // MARK: - Network Hubs Config
    
    func uploadNetworkHubsConfig(_ hubs: [NetworkHub]) async throws {
        try await deleteAllRecords(ofType: networkHubConfigType)
        
        var records: [CKRecord] = []
        for hub in hubs {
            let record = CKRecord(recordType: networkHubConfigType)
            record["hubId"] = hub.name.lowercased() as CKRecordValue
            record["isEnabled"] = (hub.isEnabled ? 1 : 0) as CKRecordValue
            record["sortOrder"] = hub.sortOrder as CKRecordValue
            records.append(record)
        }
        try await batchSave(records)
    }
    
    func downloadNetworkHubsConfig() async throws -> [(hubId: String, isEnabled: Bool, sortOrder: Int)] {
        let records = try await fetchAllRecords(ofType: networkHubConfigType)
        return records.compactMap { record -> (hubId: String, isEnabled: Bool, sortOrder: Int)? in
            guard let hubId = record["hubId"] as? String else { return nil }
            let isEnabled = (record["isEnabled"] as? Int64 ?? 1) == 1
            let sortOrder = record["sortOrder"] as? Int ?? 0
            return (hubId: hubId, isEnabled: isEnabled, sortOrder: sortOrder)
        }
    }
    
    // MARK: - Hidden Sections
    
    func uploadHiddenSections(_ sections: HiddenDefaultSections) async throws {
        try await deleteAllRecords(ofType: hiddenSectionsType)
        
        let record = CKRecord(recordType: hiddenSectionsType)
        record["hideStudiosRow"] = (sections.hideStudiosRow ? 1 : 0) as CKRecordValue
        record["hideNetworksRow"] = (sections.hideNetworksRow ? 1 : 0) as CKRecordValue
        record["hideForYouRow"] = (sections.hideForYouRow ? 1 : 0) as CKRecordValue
        record["hideDiscoverSection"] = (sections.hideDiscoverSection ? 1 : 0) as CKRecordValue
        try await privateDB.save(record)
    }
    
    func downloadHiddenSections() async throws -> HiddenDefaultSections? {
        let records = try await fetchAllRecords(ofType: hiddenSectionsType)
        guard let record = records.first else { return nil }
        
        var sections = HiddenDefaultSections()
        sections.hideStudiosRow = (record["hideStudiosRow"] as? Int64 ?? 0) == 1
        sections.hideNetworksRow = (record["hideNetworksRow"] as? Int64 ?? 0) == 1
        sections.hideForYouRow = (record["hideForYouRow"] as? Int64 ?? 0) == 1
        sections.hideDiscoverSection = (record["hideDiscoverSection"] as? Int64 ?? 0) == 1
        return sections
    }
    
    // MARK: - Browse Sections
    
    func uploadBrowseSections(_ sections: [BrowseSectionItem]) async throws {
        try await deleteAllRecords(ofType: browseSectionType)
        
        var records: [CKRecord] = []
        for section in sections {
            let record = CKRecord(recordType: browseSectionType)
            record["sectionId"] = section.id as CKRecordValue
            record["sectionType"] = section.sectionType.rawValue as CKRecordValue
            record["isEnabled"] = (section.isEnabled ? 1 : 0) as CKRecordValue
            record["sortOrder"] = section.sortOrder as CKRecordValue
            records.append(record)
        }
        try await batchSave(records)
    }
    
    func downloadBrowseSections() async throws -> [BrowseSectionItem] {
        let records = try await fetchAllRecords(ofType: browseSectionType)
        return records.compactMap { record -> BrowseSectionItem? in
            guard let sectionId = record["sectionId"] as? String,
                  let typeRaw = record["sectionType"] as? String,
                  let type = BrowseSectionItem.BrowseSectionType(rawValue: typeRaw) else { return nil }
            
            let isEnabled = (record["isEnabled"] as? Int64 ?? 1) == 1
            let sortOrder = record["sortOrder"] as? Int ?? 0
            return BrowseSectionItem(id: sectionId, sectionType: type, isEnabled: isEnabled, sortOrder: sortOrder)
        }
    }
    
    // MARK: - Helpers
    
    private func mediaItemRecord(_ item: SavedMediaItem, listType: String) -> CKRecord {
        let record = CKRecord(recordType: mediaItemType)
        record["listType"] = listType as CKRecordValue
        record["mediaId"] = item.mediaId as CKRecordValue
        record["mediaType"] = item.mediaType.rawValue as CKRecordValue
        record["title"] = item.title as CKRecordValue
        if let poster = item.posterPath { record["posterPath"] = poster as CKRecordValue }
        if let backdrop = item.backdropPath { record["backdropPath"] = backdrop as CKRecordValue }
        if let year = item.year { record["year"] = year as CKRecordValue }
        if let rating = item.voteAverage { record["voteAverage"] = rating as CKRecordValue }
        if let overview = item.overview { record["overview"] = overview as CKRecordValue }
        record["addedAt"] = item.addedAt as CKRecordValue
        return record
    }
    
    private func savedMediaItem(from record: CKRecord) -> SavedMediaItem? {
        guard let mediaId = record["mediaId"] as? Int,
              let mediaTypeRaw = record["mediaType"] as? String,
              let mediaType = MediaType(rawValue: mediaTypeRaw),
              let title = record["title"] as? String else { return nil }
        
        return SavedMediaItem(
            id: "\(mediaTypeRaw)-\(mediaId)",
            mediaId: mediaId,
            mediaType: mediaType,
            title: title,
            posterPath: record["posterPath"] as? String,
            backdropPath: record["backdropPath"] as? String,
            year: record["year"] as? String,
            voteAverage: record["voteAverage"] as? Double,
            overview: record["overview"] as? String,
            addedAt: record["addedAt"] as? Date ?? Date()
        )
    }
    
    private func fetchAllRecords(ofType type: String) async throws -> [CKRecord] {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: type, predicate: predicate)
        
        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil
        
        let results = try await privateDB.records(matching: query, resultsLimit: 400)
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                allRecords.append(record)
            }
        }
        cursor = results.queryCursor
        
        while let nextCursor = cursor {
            let moreResults = try await privateDB.records(continuingMatchFrom: nextCursor, resultsLimit: 400)
            for (_, result) in moreResults.matchResults {
                if let record = try? result.get() {
                    allRecords.append(record)
                }
            }
            cursor = moreResults.queryCursor
        }
        
        return allRecords
    }
    
    private func deleteAllRecords(ofType type: String) async throws {
        let records = try await fetchAllRecords(ofType: type)
        let ids = records.map { $0.recordID }
        
        // Delete in batches of 400
        let batchSize = 400
        for batchStart in stride(from: 0, to: ids.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, ids.count)
            let batch = Array(ids[batchStart..<batchEnd])
            
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batch)
            operation.savePolicy = .allKeys
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                privateDB.add(operation)
            }
        }
    }
    
    private func batchSave(_ records: [CKRecord]) async throws {
        guard !records.isEmpty else { return }
        
        let batchSize = 400
        for batchStart in stride(from: 0, to: records.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, records.count)
            let batch = Array(records[batchStart..<batchEnd])
            
            let operation = CKModifyRecordsOperation(recordsToSave: batch, recordIDsToDelete: nil)
            operation.savePolicy = .allKeys
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                privateDB.add(operation)
            }
        }
    }
    
    // MARK: - Last Sync Time
    
    func updateLastSyncTime() {
        UserDefaults.standard.set(Date(), forKey: "cloudkit_last_sync")
    }
    
    func getLastSyncTime() -> Date? {
        UserDefaults.standard.object(forKey: "cloudkit_last_sync") as? Date
    }
}
