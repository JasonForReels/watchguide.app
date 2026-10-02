import SwiftUI

// MARK: - App Group

enum WidgetShared {
    static let appGroupID = "group.com.JasonSmith.WatchGuide-MovieandTVtracker.shared"
    static let tmdbKeyStorageKey = "widgetTMDBApiKey"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// Same shape the app's Spotlight index and notifications use, so every
    /// widget tap lands on the title's detail page.
    static func mediaURL(mediaType: String, mediaId: Int?) -> URL? {
        guard let mediaId else { return nil }
        return URL(string: "watchguide://media/\(mediaType)/\(mediaId)")
    }
}

// MARK: - Poster cache

/// Posters live in the App Group container so every widget (and every
/// timeline reload) reuses the same downloads.
enum WidgetPosterCache {
    private static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetShared.appGroupID)?
            .appendingPathComponent("PosterCache", isDirectory: true)
    }

    private static func fileURL(for posterPath: String) -> URL? {
        let safe = posterPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "_")
        return directory?.appendingPathComponent(safe)
    }

    /// Disk only — safe to call from `getSnapshot`, which must return quickly.
    static func cached(_ posterPath: String) -> Data? {
        guard let url = fileURL(for: posterPath) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Disk first, then TMDB. Downloads are written back to the cache.
    static func load(_ posterPath: String) async -> Data? {
        if let data = cached(posterPath) { return data }
        guard let remote = URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)"),
              let (data, response) = try? await URLSession.shared.data(from: remote),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty else { return nil }
        if let dir = directory, let url = fileURL(for: posterPath) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: url)
        }
        return data
    }
}

func widgetImage(from data: Data?) -> Image? {
    guard let data else { return nil }
    #if os(macOS)
    guard let ns = NSImage(data: data) else { return nil }
    return Image(nsImage: ns)
    #else
    guard let ui = UIImage(data: data) else { return nil }
    return Image(uiImage: ui)
    #endif
}

/// Deep purple used behind every text-led widget layout.
let widgetBrandBackground = Color(red: 0.10, green: 0.07, blue: 0.22)
