//
//  SpotlightIndexingService.swift
//  WatchGuide-MovieandTVtracker
//
//  Indexes saved media items into CoreSpotlight for system-wide search.
//

#if canImport(CoreSpotlight) && !os(tvOS)
import CoreSpotlight
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
class SpotlightIndexingService {
    static let shared = SpotlightIndexingService()

    private let searchableIndex = CSSearchableIndex.default()

    // Domain identifiers for batch management
    private static let wantToWatchDomain = "watchguide.wantToWatch"
    private static let watchedDomain = "watchguide.watched"
    private static let likedDomain = "watchguide.liked"

    private init() {}

    // MARK: - Full Index

    /// Indexes all saved content from StorageService into Spotlight.
    /// Call this on app launch to ensure the index is up to date.
    func indexAllContent() {
        Task {
            let storage = StorageService.shared

            // Remove stale items then re-index everything
            try? await searchableIndex.deleteAllSearchableItems()

            var items: [CSSearchableItem] = []

            for savedItem in storage.wantToWatch {
                if let searchableItem = await makeSearchableItem(savedItem, domain: Self.wantToWatchDomain, listLabel: "Watchlist") {
                    items.append(searchableItem)
                }
            }

            for savedItem in storage.watched {
                if let searchableItem = await makeSearchableItem(savedItem, domain: Self.watchedDomain, listLabel: "Watched") {
                    items.append(searchableItem)
                }
            }

            for savedItem in storage.liked {
                if let searchableItem = await makeSearchableItem(savedItem, domain: Self.likedDomain, listLabel: "Liked") {
                    items.append(searchableItem)
                }
            }

            guard !items.isEmpty else { return }

            do {
                try await searchableIndex.indexSearchableItems(items)
                print("[Spotlight] Indexed \(items.count) items")
            } catch {
                print("[Spotlight] Failed to index: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Incremental Index

    /// Index a single item when added to a list.
    func indexItem(_ item: SavedMediaItem, listType: ListType) {
        Task {
            let domain = domainIdentifier(for: listType)
            let label = listType.displayName

            guard let searchableItem = await makeSearchableItem(item, domain: domain, listLabel: label) else { return }

            do {
                try await searchableIndex.indexSearchableItems([searchableItem])
                print("[Spotlight] Indexed: \(item.title)")
            } catch {
                print("[Spotlight] Failed to index \(item.title): \(error.localizedDescription)")
            }
        }
    }

    /// Remove a single item from the Spotlight index.
    func removeItem(_ item: SavedMediaItem) {
        Task {
            do {
                try await searchableIndex.deleteSearchableItems(withIdentifiers: [item.id])
                print("[Spotlight] Removed: \(item.title)")
            } catch {
                print("[Spotlight] Failed to remove \(item.title): \(error.localizedDescription)")
            }
        }
    }

    /// Remove all items for a specific list type.
    func removeAllItems(for listType: ListType) {
        Task {
            let domain = domainIdentifier(for: listType)
            do {
                try await searchableIndex.deleteSearchableItems(withDomainIdentifiers: [domain])
                print("[Spotlight] Removed all items for domain: \(domain)")
            } catch {
                print("[Spotlight] Failed to remove domain \(domain): \(error.localizedDescription)")
            }
        }
    }

    /// Remove everything from the Spotlight index.
    func removeAllItems() {
        Task {
            do {
                try await searchableIndex.deleteAllSearchableItems()
                print("[Spotlight] Removed all indexed items")
            } catch {
                print("[Spotlight] Failed to remove all: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private Helpers

    private func makeSearchableItem(_ item: SavedMediaItem, domain: String, listLabel: String) async -> CSSearchableItem? {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .content)

        // Core metadata
        attributeSet.title = item.title
        attributeSet.contentDescription = item.overview
        attributeSet.displayName = item.title

        // Keywords for search relevance
        var keywords = [item.title, listLabel]
        if let year = item.year {
            keywords.append(year)
        }
        let typeLabel = item.mediaType == .movie ? "Movie" : "TV Show"
        keywords.append(typeLabel)
        attributeSet.keywords = keywords

        // Rating
        if let rating = item.voteAverage {
            attributeSet.rating = NSNumber(value: rating)
        }

        // Deep link URL: watchguide://media/{mediaType}/{mediaId}
        let urlString = "watchguide://media/\(item.mediaType.rawValue)/\(item.mediaId)"
        attributeSet.contentURL = URL(string: urlString)
        attributeSet.relatedUniqueIdentifier = item.id

        // Poster thumbnail (download asynchronously)
        if let posterPath = item.posterPath {
            attributeSet.thumbnailData = await downloadThumbnail(path: posterPath)
        }

        return CSSearchableItem(
            uniqueIdentifier: item.id,
            domainIdentifier: domain,
            attributeSet: attributeSet
        )
    }

    private func downloadThumbnail(path: String) async -> Data? {
        // Use TMDB small poster size for thumbnails
        let urlString = "https://image.tmdb.org/t/p/w92\(path)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return data
            }
            return nil
        } catch {
            return nil
        }
    }

    private func domainIdentifier(for listType: ListType) -> String {
        switch listType {
        case .wantToWatch: return Self.wantToWatchDomain
        case .watched: return Self.watchedDomain
        case .liked: return Self.likedDomain
        case .custom: return "watchguide.custom"
        }
    }

    // MARK: - Deep Link Parsing

    /// Parse a Spotlight activity's unique identifier into mediaType and mediaId.
    /// The identifier format is "{mediaType}-{mediaId}" (e.g., "movie-123").
    static func parseSpotlightIdentifier(_ identifier: String) -> (mediaType: MediaType, mediaId: Int)? {
        let parts = identifier.split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let mediaType = MediaType(rawValue: String(parts[0])),
              let mediaId = Int(parts[1]) else {
            return nil
        }
        return (mediaType, mediaId)
    }
}

#endif
