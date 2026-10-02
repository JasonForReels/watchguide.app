import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Shared Model

// Mirrors WidgetDataService.ComingSoonWidgetItem — same fields, same JSON keys.
private struct ComingSoonWidgetItem: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let releaseDate: Date
    let mediaType: String
    let posterPath: String?
    /// TMDB id. Optional so items cached by older app builds still decode.
    let mediaId: Int?
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

    var posterImage: Image? { widgetImage(from: posterImageData) }

    var url: URL? { WidgetShared.mediaURL(mediaType: mediaType, mediaId: mediaId) }
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

// MARK: - Configuration

enum ComingSoonStyle: String, AppEnum {
    case poster
    case countdown
    case list

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static let caseDisplayRepresentations: [ComingSoonStyle: DisplayRepresentation] = [
        .poster: "Poster",
        .countdown: "Countdown",
        .list: "List"
    ]
}

struct ComingSoonConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Coming Soon"
    static let description = IntentDescription("Choose how upcoming releases are shown.")

    @Parameter(title: "Style", default: .poster)
    var style: ComingSoonStyle
}

// MARK: - Timeline Entry

private struct ComingSoonEntry: TimelineEntry {
    let date: Date
    let items: [ComingSoonWidgetItem]
    let style: ComingSoonStyle
    var nextItem: ComingSoonWidgetItem? { items.first }
}

// MARK: - Provider

private struct ComingSoonProvider: AppIntentTimelineProvider {
    private static let storageKey = "comingSoonWidgetItems"

    func placeholder(in context: Context) -> ComingSoonEntry {
        ComingSoonEntry(date: Date(), items: Self.placeholders, style: .poster)
    }

    // Snapshots MUST return quickly — disk cache only, zero network calls.
    func snapshot(for configuration: ComingSoonConfigurationIntent, in context: Context) async -> ComingSoonEntry {
        let style = configuration.style
        if context.isPreview {
            return ComingSoonEntry(date: Date(), items: Self.placeholders, style: style)
        }
        var items = loadCachedItems()
        if items.isEmpty { items = Self.placeholders }
        for i in 0..<min(Self.posterLimit(style, context.family), items.count) {
            guard let path = items[i].posterPath else { continue }
            items[i].posterImageData = WidgetPosterCache.cached(path)
        }
        return ComingSoonEntry(date: Date(), items: items, style: style)
    }

    // The timeline does the full async work — TMDB fetch + poster downloads.
    func timeline(for configuration: ComingSoonConfigurationIntent, in context: Context) async -> Timeline<ComingSoonEntry> {
        var items = await resolvedItems()
        for i in 0..<min(Self.posterLimit(configuration.style, context.family), items.count) {
            guard let path = items[i].posterPath else { continue }
            items[i].posterImageData = await WidgetPosterCache.load(path)
        }
        let entry = ComingSoonEntry(date: Date(), items: items, style: configuration.style)
        // Refresh just after midnight so "Tomorrow" becomes "Today" on time.
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        let next = min(Date().addingTimeInterval(6 * 3600), midnight.addingTimeInterval(60))
        return Timeline(entries: [entry], policy: .after(next))
    }

    /// How many posters each layout actually draws — no point downloading more.
    private static func posterLimit(_ style: ComingSoonStyle, _ family: WidgetFamily) -> Int {
        switch (style, family) {
        case (_, .accessoryCircular), (_, .accessoryRectangular), (_, .accessoryInline): return 0
        case (.poster, .systemSmall): return 1
        case (.poster, _): return 3
        case (.countdown, _): return 1
        case (.list, .systemSmall): return 0
        case (.list, _): return 4
        }
    }

    // MARK: - Data

    private func resolvedItems() async -> [ComingSoonWidgetItem] {
        let cached = loadCachedItems()
        if !cached.isEmpty { return cached }
        return await fetchFromTMDB()
    }

    private func loadCachedItems() -> [ComingSoonWidgetItem] {
        guard let data = WidgetShared.defaults?.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ComingSoonWidgetItem].self, from: data)
        else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        return decoded.filter { $0.releaseDate >= today }
    }

    private func fetchFromTMDB() async -> [ComingSoonWidgetItem] {
        guard let apiKey = WidgetShared.defaults?.string(forKey: WidgetShared.tmdbKeyStorageKey),
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
                    subtitle: nil, releaseDate: date, mediaType: "movie",
                    posterPath: movie.posterPath, mediaId: movie.id
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
                    subtitle: nil, releaseDate: date, mediaType: "tv",
                    posterPath: show.posterPath, mediaId: show.id
                ))
            }
        }

        return items.sorted { $0.releaseDate < $1.releaseDate }
    }

    private static var placeholders: [ComingSoonWidgetItem] {
        [
            ComingSoonWidgetItem(id: "ph1", title: "Upcoming Movie", subtitle: nil,
                releaseDate: Date().addingTimeInterval(7 * 86400), mediaType: "movie", posterPath: nil, mediaId: nil),
            ComingSoonWidgetItem(id: "ph2", title: "New TV Series", subtitle: "Season 2",
                releaseDate: Date().addingTimeInterval(14 * 86400), mediaType: "tv", posterPath: nil, mediaId: nil),
            ComingSoonWidgetItem(id: "ph3", title: "Coming Soon", subtitle: nil,
                releaseDate: Date().addingTimeInterval(30 * 86400), mediaType: "movie", posterPath: nil, mediaId: nil),
            ComingSoonWidgetItem(id: "ph4", title: "Season Premiere", subtitle: "Season 3",
                releaseDate: Date().addingTimeInterval(45 * 86400), mediaType: "tv", posterPath: nil, mediaId: nil),
        ]
    }
}

// MARK: - Poster style

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
            .widgetURL(item.url ?? comingSoonURL)
        } else {
            emptyState
        }
    }
}

private struct ComingSoonMediumView: View {
    let entry: ComingSoonEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ComingSoonHeader(next: entry.nextItem)

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
                        linked(item.url) { MediumItemCard(item: item) }
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
        .widgetURL(comingSoonURL)
    }
}

private struct MediumItemCard: View {
    let item: ComingSoonWidgetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PosterThumb(item: item, cornerRadius: 5)
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

// MARK: - Countdown style

private struct CountdownSmallView: View {
    let entry: ComingSoonEntry

    var body: some View {
        if let item = entry.nextItem {
            VStack(alignment: .leading, spacing: 0) {
                Label("COMING SOON", systemImage: item.isMovie ? "film" : "tv")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.accentColor)
                Spacer(minLength: 0)
                CountdownFigure(item: item, size: 50)
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(item.url ?? comingSoonURL)
        } else {
            emptyState
        }
    }
}

private struct CountdownMediumView: View {
    let entry: ComingSoonEntry

    var body: some View {
        if let item = entry.nextItem {
            HStack(spacing: 14) {
                PosterThumb(item: item, cornerRadius: 8)
                    .aspectRatio(2 / 3, contentMode: .fit)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    CountdownFigure(item: item, size: 40)
                    Text(item.releaseDate, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if entry.items.count > 1 {
                        let after = entry.items[1]
                        Text("Then \(after.title) · \(after.countdownText)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .widgetURL(item.url ?? comingSoonURL)
        } else {
            emptyState
        }
    }
}

/// The big number: "12 days", "1 day", or just "Today".
private struct CountdownFigure: View {
    let item: ComingSoonWidgetItem
    let size: CGFloat

    var body: some View {
        let days = max(item.daysUntil, 0)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if days == 0 {
                Text("Today")
                    .font(.system(size: size * 0.7, weight: .heavy, design: .rounded))
                    .foregroundColor(item.urgencyColor)
            } else {
                Text("\(days)")
                    .font(.system(size: size, weight: .heavy, design: .rounded))
                    .foregroundColor(item.urgencyColor)
                    .contentTransition(.numericText())
                Text(days == 1 ? "day" : "days")
                    .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

// MARK: - List style

private struct ListSmallView: View {
    let entry: ComingSoonEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ComingSoonHeader(next: nil)
            if entry.items.isEmpty {
                Spacer()
                Text("Open WatchGuide to load releases")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.items.prefix(3))) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(item.countdownText)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(item.urgencyColor)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(comingSoonURL)
    }
}

private struct ListMediumView: View {
    let entry: ComingSoonEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ComingSoonHeader(next: nil)
            if entry.items.isEmpty {
                Spacer()
                Text("Open WatchGuide to load releases")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ForEach(Array(entry.items.prefix(4))) { item in
                    linked(item.url) { ListRow(item: item) }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(comingSoonURL)
    }
}

private struct ListRow: View {
    let item: ComingSoonWidgetItem

    var body: some View {
        HStack(spacing: 8) {
            PosterThumb(item: item, cornerRadius: 3)
                .frame(width: 18, height: 27)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(item.releaseDate, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            Text(item.countdownText)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(item.urgencyColor)
        }
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
            .widgetURL(item.url ?? comingSoonURL)
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
                    Text(item.daysUntil == 1 ? "day" : "days")
                        .font(.system(size: 7, weight: .medium))
                        .textCase(.uppercase)
                }
            } else {
                Image(systemName: "popcorn.fill").font(.callout)
            }
        }
        .widgetURL(entry.nextItem?.url ?? comingSoonURL)
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

private let comingSoonURL = URL(string: "watchguide://countdown")

private struct ComingSoonHeader: View {
    let next: ComingSoonWidgetItem?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar.badge.clock")
                .font(.caption)
            Text("Coming Soon")
                .font(.caption)
                .fontWeight(.bold)
            Spacer()
            if let next {
                Text("Next: \(next.countdownText)")
                    .font(.caption2)
                    .foregroundColor(next.urgencyColor)
                    .fontWeight(.medium)
            }
        }
        .foregroundColor(.accentColor)
    }
}

private struct PosterThumb: View {
    let item: ComingSoonWidgetItem
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let img = item.posterImage {
                img.resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.accentColor.opacity(0.25)
                Image(systemName: item.isMovie ? "film" : "tv")
                    .foregroundColor(.accentColor.opacity(0.6))
                    .font(.caption)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// Wraps a sub-view in a `Link` when it has somewhere specific to go.
@ViewBuilder
private func linked<Content: View>(_ url: URL?, @ViewBuilder _ content: () -> Content) -> some View {
    if let url {
        Link(destination: url, label: content)
    } else {
        content()
    }
}

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
    .widgetURL(comingSoonURL)
}

// MARK: - Entry View Router

private struct ComingSoonEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ComingSoonEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: ComingSoonRectangularView(entry: entry)
        case .accessoryCircular:    ComingSoonCircularView(entry: entry)
        case .accessoryInline:      ComingSoonInlineView(entry: entry)
        default:
            homeScreenView
                // The background is always dark, so text must be too — otherwise
                // Light Mode draws black titles on deep purple.
                .environment(\.colorScheme, .dark)
        }
    }

    @ViewBuilder
    private var homeScreenView: some View {
        let small = family == .systemSmall
        switch entry.style {
        case .poster:
            if small { ComingSoonSmallView(entry: entry) } else { ComingSoonMediumView(entry: entry) }
        case .countdown:
            if small { CountdownSmallView(entry: entry) } else { CountdownMediumView(entry: entry) }
        case .list:
            if small { ListSmallView(entry: entry) } else { ListMediumView(entry: entry) }
        }
    }
}

// MARK: - Widget

struct ComingSoonWidget: Widget {
    static let kind = "com.JasonSmith.WatchGuide-MovieandTVtracker.comingsoon"

    var body: some WidgetConfiguration {
        // Same kind as the old StaticConfiguration, so widgets already on
        // people's Home Screens carry over with the default Poster style.
        AppIntentConfiguration(kind: Self.kind, intent: ComingSoonConfigurationIntent.self, provider: ComingSoonProvider()) { entry in
            ComingSoonEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    if entry.style == .poster, let item = entry.nextItem, item.posterImage != nil {
                        Color.black
                    } else {
                        widgetBrandBackground
                    }
                }
        }
        .configurationDisplayName("Coming Soon")
        .description("See what's releasing soon. Touch and hold, then Edit Widget to change the style.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}
