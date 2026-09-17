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
}

final class WidgetDataService {
    static let shared = WidgetDataService()
    private init() {}

    private let appGroupID = "group.com.JasonSmith.WatchGuide-MovieandTVtracker.shared"
    private let comingSoonKey = "comingSoonWidgetItems"
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
                posterPath: $0.mediaItem.posterPath
            )
        }

        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(Array(widgetItems)) else { return }

        defaults.set(data, forKey: comingSoonKey)
        reloadWidget()
    }

    private func reloadWidget() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "com.JasonSmith.WatchGuide-MovieandTVtracker.comingsoon")
        #endif
    }
}
