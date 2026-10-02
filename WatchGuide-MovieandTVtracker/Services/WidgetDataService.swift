import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// Lightweight model written to the App Group so the widget can read it without
// depending on the full app's model graph.
struct ComingSoonWidgetItem: Codable {
    let id: String
    let title: String
    let subtitle: String?
    let releaseDate: Date
    let mediaType: String   // "movie" | "tv"
    let posterPath: String?
    let mediaId: Int
}

// Next episode for one in-progress show.
struct UpNextWidgetItem: Codable {
    let id: String
    let mediaId: Int
    let title: String
    let posterPath: String?
    let seasonNumber: Int
    let episodeNumber: Int
    let episodeTitle: String?
    let airDate: String?
    let lastUpdated: Date
}

final class WidgetDataService {
    static let shared = WidgetDataService()
    private init() {}

    private let appGroupID = "group.com.JasonSmith.WatchGuide-MovieandTVtracker.shared"
    private let comingSoonKey = "comingSoonWidgetItems"
    private let upNextKey = "upNextWidgetItems"
    private let comingSoonKind = "com.JasonSmith.WatchGuide-MovieandTVtracker.comingsoon"
    private let upNextKind = "com.JasonSmith.WatchGuide-MovieandTVtracker.upnext"
    private let tmdbKeyStorageKey = "widgetTMDBApiKey"

    // Called on app launch — pushes the TMDB key into the shared container so
    // the widget can fetch its own data without depending on CountdownCalendarView.
    func syncAPIKey() {
        guard let key = ApiKeyManager.shared.get(key: "TMDB_API_KEY"), !key.isEmpty,
              let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(key, forKey: tmdbKeyStorageKey)
    }

    // Called after CountdownCalendarView finishes loading — fast path that writes
    // already-fetched items so the widget doesn't need to call TMDB itself.
    func syncComingSoonItems(_ items: [CountdownItem]) {
        let widgetItems = items.prefix(10).map {
            ComingSoonWidgetItem(
                id: $0.id,
                title: $0.title,
                subtitle: $0.subtitle,
                releaseDate: $0.releaseDate,
                mediaType: $0.mediaType.rawValue,
                posterPath: $0.mediaItem.posterPath,
                mediaId: $0.mediaItem.id
            )
        }

        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(Array(widgetItems)) else { return }

        defaults.set(data, forKey: comingSoonKey)
        reloadWidget(kind: comingSoonKind)
    }

    // Called whenever StorageService.continueWatching changes. Skips the write
    // and reload when nothing the widget shows has changed, so routine saves
    // don't burn the widget's reload budget.
    func syncUpNextItems(_ items: [ContinueWatchingItem]) {
        let widgetItems: [UpNextWidgetItem] = items.compactMap { item in
            guard item.status == .inProgress, item.show.mediaType == .tv,
                  let next = item.nextEpisode else { return nil }
            return UpNextWidgetItem(
                id: item.id,
                mediaId: item.show.mediaId,
                title: item.show.title,
                posterPath: item.show.posterPath,
                seasonNumber: next.seasonNumber,
                episodeNumber: next.episodeNumber,
                episodeTitle: next.title,
                airDate: next.airDate,
                lastUpdated: item.lastUpdated
            )
        }

        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(Array(widgetItems.prefix(10))),
              data != defaults.data(forKey: upNextKey) else { return }

        defaults.set(data, forKey: upNextKey)
        reloadWidget(kind: upNextKind)
    }

    private func reloadWidget(kind: String) {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        #endif
    }
}
