import WidgetKit
import SwiftUI

// MARK: - Shared Model

// Mirrors WidgetDataService.ComingSoonWidgetItem — same fields, same JSON keys.
private struct ComingSoonWidgetItem: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let releaseDate: Date
    let mediaType: String
    let posterPath: String?
    var posterImageData: Data?

    var daysUntil: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: releaseDate)
        ).day ?? 0
    }

    var countdownText: String {
        let d = daysUntil
        if d <= 0 { return "Today" }
        if d == 1 { return "Tomorrow" }
        if d < 7 { return "\(d) days" }
        let w = d / 7, r = d % 7
        return r == 0 ? "\(w)w" : "\(w)w \(r)d"
    }

    var urgencyColor: Color {
        let d = daysUntil
        if d <= 1 { return .green }
        if d <= 7 { return .orange }
        if d <= 30 { return Color(red: 0.4, green: 0.6, blue: 1.0) }
        return .secondary
    }

    var isMovie: Bool { mediaType == "movie" }

    var posterImage: Image? {
        guard let data = posterImageData else { return nil }
        #if os(macOS)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #else
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #endif
    }
}

// MARK: - Minimal TMDB response models

private struct TMDBListResponse: Decodable {
    let results: [TMDBResult]
}

private struct TMDBResult: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
    }
}

// MARK: - Timeline Entry

private struct ComingSoonEntry: TimelineEntry {
    let date: Date
    let items: [ComingSoonWidgetItem]
    var nextItem: ComingSoonWidgetItem? { items.first }
}

// MARK: - Provider

private struct ComingSoonProvider: TimelineProvider {
    private static let appGroupID = "group.com.JasonSmith.WatchGuide-MovieandTVtracker.shared"
    private static let storageKey = "comingSoonWidgetItems"
    private static let tmdbKeyStorageKey = "widgetTMDBApiKey"

    private static var posterCacheDir: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("PosterCache", isDirectory: true)
    }

    func placeholder(in context: Context) -> ComingSoonEntry {
        ComingSoonEntry(date: Date(), items: Self.placeholders)
    }

    // getSnapshot MUST return quickly — disk cache only, zero network calls.
    func getSnapshot(in context: Context, completion: @escaping (ComingSoonEntry) -> Void) {
        if context.isPreview {
            completion(ComingSoonEntry(date: Date(), items: Self.placeholders))
            return
        }
        var items = loadCachedItems()
        if items.isEmpty { items = Self.placeholders }
        let limit = context.family == .systemSmall ? 1 : 3
        for i in 0..<min(limit, items.count) {
            guard let path = items[i].posterPath else { continue }
            items[i].posterImageData = readCachedPoster(for: path)
        }
        completion(ComingSoonEntry(date: Date(), items: items))
    }

    // getTimeline does the full async work — TMDB fetch + poster downloads.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComingSoonEntry>) -> Void) {
        Task {
            var items = await resolvedItems()
            await attachPosters(to: &items, limit: context.family == .systemSmall ? 1 : 3)
            let entry = ComingSoonEntry(date: Date(), items: items)
            let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(6 * 3600)))
            completion(timeline)
        }
    }

    // MARK: - Poster helpers

    private func attachPosters(to items: inout [ComingSoonWidgetItem], limit: Int) async {
        prepareCacheDir()
        for i in 0..<min(limit, items.count) {
            guard let path = items[i].posterPath else { continue }
            if let cached = readCachedPoster(for: path) {
                items[i].posterImageData = cached
            } else if let downloaded = await downloadPoster(path: path) {
                writeCachedPoster(downloaded, for: path)
                items[i].posterImageData = downloaded
            }
        }
    }

    private func downloadPoster(path: String) async -> Data? {
        guard let url = URL(string: "https://image.tmdb.org/t/p/w342\(path)"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty else { return nil }
        return data
    }

    // MARK: - Disk cache

    private func prepareCacheDir() {
        guard let dir = Self.posterCacheDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func cacheURL(for posterPath: String) -> URL? {
        let safe = posterPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "_")
        return Self.posterCacheDir?.appendingPathComponent(safe)
    }

    private func readCachedPoster(for posterPath: String) -> Data? {
        guard let url = cacheURL(for: posterPath) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func writeCachedPoster(_ data: Data, for posterPath: String) {
        guard let url = cacheURL(for: posterPath) else { return }
        try? data.write(to: url)
    }

    // MARK: - Data

    private func resolvedItems() async -> [ComingSoonWidgetItem] {
        let cached = loadCachedItems()
        if !cached.isEmpty { return cached }
        return await fetchFromTMDB()
    }

    private func loadCachedItems() -> [ComingSoonWidgetItem] {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ComingSoonWidgetItem].self, from: data)
        else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        return decoded.filter { $0.releaseDate >= today }
    }

    private func fetchFromTMDB() async -> [ComingSoonWidgetItem] {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let apiKey = defaults.string(forKey: Self.tmdbKeyStorageKey),
              !apiKey.isEmpty else { return [] }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        var items: [ComingSoonWidgetItem] = []

        if let url = URL(string: "https://api.themoviedb.org/3/movie/upcoming?api_key=\(apiKey)&language=en-US&page=1"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let response = try? JSONDecoder().decode(TMDBListResponse.self, from: data) {
            for movie in response.results {
                guard let dateStr = movie.releaseDate,
                      let date = df.date(from: dateStr), date >= tomorrow else { continue }
                items.append(ComingSoonWidgetItem(
                    id: "movie-\(movie.id)", title: movie.title ?? movie.name ?? "Unknown",
                    subtitle: nil, releaseDate: date, mediaType: "movie", posterPath: movie.posterPath
                ))
            }
        }

        if let url = URL(string: "https://api.themoviedb.org/3/tv/on_the_air?api_key=\(apiKey)&language=en-US&page=1"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let response = try? JSONDecoder().decode(TMDBListResponse.self, from: data) {
            for show in response.results {
                guard let dateStr = show.firstAirDate ?? show.releaseDate,
                      let date = df.date(from: dateStr), date >= tomorrow else { continue }
                items.append(ComingSoonWidgetItem(
                    id: "tv-\(show.id)", title: show.name ?? show.title ?? "Unknown",
                    subtitle: nil, releaseDate: date, mediaType: "tv", posterPath: show.posterPath
                ))
            }
        }

        return items.sorted { $0.releaseDate < $1.releaseDate }
    }

    private static var placeholders: [ComingSoonWidgetItem] {
        [
            ComingSoonWidgetItem(id: "ph1", title: "Upcoming Movie", subtitle: nil,
                releaseDate: Date().addingTimeInterval(7 * 86400), mediaType: "movie", posterPath: nil),
            ComingSoonWidgetItem(id: "ph2", title: "New TV Series", subtitle: "Season 2",
                releaseDate: Date().addingTimeInterval(14 * 86400), mediaType: "tv", posterPath: nil),
            ComingSoonWidgetItem(id: "ph3", title: "Coming Soon", subtitle: nil,
                releaseDate: Date().addingTimeInterval(30 * 86400), mediaType: "movie", posterPath: nil),
        ]
    }
}

// MARK: - Small Widget

private struct ComingSoonSmallView: View {
    let entry: ComingSoonEntry

    var body: some View {
        if let item = entry.nextItem {
            ZStack(alignment: .bottomLeading) {
                posterBackground(item)
                LinearGradient(colors: [.clear, .black.opacity(0.85)],
                               startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Text(item.countdownText)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(item.urgencyColor)
                        Spacer()
                        Image(systemName: item.isMovie ? "film" : "tv")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .padding(10)
            }
            .widgetURL(URL(string: "watchguide://countdown"))
        } else {
            emptyState
        }
    }
}

// MARK: - Medium Widget

private struct ComingSoonMediumView: View {
    let entry: ComingSoonEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text("Coming Soon")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
                Spacer()
                if let first = entry.items.first {
                    Text("Next: \(first.countdownText)")
                        .font(.caption2)
                        .foregroundColor(first.urgencyColor)
                        .fontWeight(.medium)
                }
            }

            Divider()

            if entry.items.isEmpty {
                Spacer()
                Text("Open WatchGuide to load releases")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(entry.items.prefix(3))) { item in
                        MediumItemCard(item: item)
                    }
                    if entry.items.count < 3 {
                        ForEach(0..<(3 - entry.items.count), id: \.self) { _ in
                            Spacer().frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(12)
        .widgetURL(URL(string: "watchguide://countdown"))
    }
}

private struct MediumItemCard: View {
    let item: ComingSoonWidgetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if let img = item.posterImage {
                    img.resizable()
                        .aspectRatio(2 / 3, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(0.25))
                    Image(systemName: item.isMovie ? "film" : "tv")
                        .foregroundColor(.accentColor.opacity(0.6))
                        .font(.title3)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(2 / 3, contentMode: .fit)

            Text(item.title)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(2)
                .foregroundColor(.primary)

            Text(item.countdownText)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(item.urgencyColor)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Lock Screen Views

private struct ComingSoonRectangularView: View {
    let entry: ComingSoonEntry

    var body: some View {
        if let item = entry.nextItem {
            HStack(spacing: 6) {
                Image(systemName: item.isMovie ? "film" : "tv").font(.callout)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.caption).fontWeight(.semibold).lineLimit(1)
                    Text(item.countdownText).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }
        } else {
            Label("Coming Soon", systemImage: "calendar.badge.clock").font(.caption)
        }
    }
}

private struct ComingSoonCircularView: View {
    let entry: ComingSoonEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let item = entry.nextItem {
                VStack(spacing: 0) {
                    Text("\(max(item.daysUntil, 0))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("days")
                        .font(.system(size: 7, weight: .medium))
                        .textCase(.uppercase)
                }
            } else {
                Image(systemName: "popcorn.fill").font(.callout)
            }
        }
    }
}

private struct ComingSoonInlineView: View {
    let entry: ComingSoonEntry

    var body: some View {
        if let item = entry.nextItem {
            Label("\(item.title) · \(item.countdownText)", systemImage: "popcorn.fill").lineLimit(1)
        } else {
            Label("Coming Soon", systemImage: "calendar.badge.clock")
        }
    }
}

// MARK: - Helpers

private func posterBackground(_ item: ComingSoonWidgetItem) -> some View {
    Group {
        if let img = item.posterImage {
            img.resizable().aspectRatio(contentMode: .fill)
        } else {
            Color.accentColor.opacity(0.3)
        }
    }
}

private var emptyState: some View {
    VStack(spacing: 8) {
        Image(systemName: "calendar.badge.clock").font(.title2).foregroundColor(.accentColor)
        Text("Coming Soon").font(.caption.bold())
        Text("Open WatchGuide\nto load releases")
            .font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

// MARK: - Entry View Router

private struct ComingSoonEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ComingSoonEntry

    var body: some View {
        switch family {
        case .systemSmall:   ComingSoonSmallView(entry: entry)
        case .systemMedium:  ComingSoonMediumView(entry: entry)
        case .accessoryRectangular: ComingSoonRectangularView(entry: entry)
        case .accessoryCircular:    ComingSoonCircularView(entry: entry)
        case .accessoryInline:      ComingSoonInlineView(entry: entry)
        default:             ComingSoonMediumView(entry: entry)
        }
    }
}

// MARK: - Widget

struct ComingSoonWidget: Widget {
    static let kind = "com.JasonSmith.WatchGuide-MovieandTVtracker.comingsoon"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ComingSoonProvider()) { entry in
            ComingSoonEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    if let item = entry.nextItem, item.posterImage != nil {
                        Color.black
                    } else {
                        Color(red: 0.10, green: 0.07, blue: 0.22)
                    }
                }
        }
        .configurationDisplayName("Coming Soon")
        .description("See what's releasing soon — movies and TV shows.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}
