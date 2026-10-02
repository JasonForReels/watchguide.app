import WidgetKit
import SwiftUI

// MARK: - Shared Model

// Mirrors WidgetDataService.UpNextWidgetItem — same fields, same JSON keys.
private struct UpNextWidgetItem: Codable, Identifiable {
    let id: String
    let mediaId: Int
    let title: String
    let posterPath: String?
    let seasonNumber: Int
    let episodeNumber: Int
    let episodeTitle: String?
    /// TMDB air date, "yyyy-MM-dd".
    let airDate: String?
    let lastUpdated: Date
    var posterImageData: Data?

    var code: String { "S\(seasonNumber) E\(episodeNumber)" }

    var posterImage: Image? { widgetImage(from: posterImageData) }

    var url: URL? { WidgetShared.mediaURL(mediaType: "tv", mediaId: mediaId) }

    var airDateValue: Date? {
        guard let airDate else { return nil }
        return Self.airDateFormatter.date(from: airDate)
    }

    /// Unknown air dates count as available: TMDB leaves old episodes blank.
    var isAvailable: Bool {
        guard let date = airDateValue else { return true }
        return date <= Date()
    }

    /// "Airs Fri 3 Oct" for episodes that aren't out yet; nil when watchable now.
    var availabilityText: String? {
        guard !isAvailable, let date = airDateValue else { return nil }
        return "Airs \(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    private static let airDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
}

// MARK: - Timeline Entry

private struct UpNextEntry: TimelineEntry {
    let date: Date
    let items: [UpNextWidgetItem]
    var first: UpNextWidgetItem? { items.first }
}

// MARK: - Provider

private struct UpNextProvider: TimelineProvider {
    private static let storageKey = "upNextWidgetItems"

    func placeholder(in context: Context) -> UpNextEntry {
        UpNextEntry(date: Date(), items: Self.placeholders)
    }

    // Snapshots MUST return quickly — disk cache only, zero network calls.
    func getSnapshot(in context: Context, completion: @escaping (UpNextEntry) -> Void) {
        if context.isPreview {
            completion(UpNextEntry(date: Date(), items: Self.placeholders))
            return
        }
        var items = loadItems()
        for i in 0..<min(Self.posterLimit(context.family), items.count) {
            guard let path = items[i].posterPath else { continue }
            items[i].posterImageData = WidgetPosterCache.cached(path)
        }
        completion(UpNextEntry(date: Date(), items: items))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpNextEntry>) -> Void) {
        Task {
            var items = loadItems()
            for i in 0..<min(Self.posterLimit(context.family), items.count) {
                guard let path = items[i].posterPath else { continue }
                items[i].posterImageData = await WidgetPosterCache.load(path)
            }
            // The app reloads this widget whenever progress changes; the timer
            // only has to catch episodes going from "Airs Fri" to available.
            let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
            let next = min(Date().addingTimeInterval(6 * 3600), midnight.addingTimeInterval(60))
            completion(Timeline(entries: [UpNextEntry(date: Date(), items: items)], policy: .after(next)))
        }
    }

    private static func posterLimit(_ family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 3
        default: return 0
        }
    }

    /// Watchable-now shows first (most recently watched on top), then shows
    /// waiting on a new episode, soonest first.
    private func loadItems() -> [UpNextWidgetItem] {
        guard let data = WidgetShared.defaults?.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([UpNextWidgetItem].self, from: data)
        else { return [] }
        let available = decoded.filter(\.isAvailable).sorted { $0.lastUpdated > $1.lastUpdated }
        let upcoming = decoded.filter { !$0.isAvailable }.sorted {
            ($0.airDateValue ?? .distantFuture) < ($1.airDateValue ?? .distantFuture)
        }
        return available + upcoming
    }

    private static var placeholders: [UpNextWidgetItem] {
        [
            UpNextWidgetItem(id: "ph1", mediaId: 0, title: "Your Show", posterPath: nil,
                             seasonNumber: 2, episodeNumber: 5, episodeTitle: "Next Episode",
                             airDate: nil, lastUpdated: Date()),
            UpNextWidgetItem(id: "ph2", mediaId: 0, title: "Another Series", posterPath: nil,
                             seasonNumber: 1, episodeNumber: 3, episodeTitle: "The Pilot's Return",
                             airDate: nil, lastUpdated: Date()),
            UpNextWidgetItem(id: "ph3", mediaId: 0, title: "New Season", posterPath: nil,
                             seasonNumber: 4, episodeNumber: 1, episodeTitle: "Premiere",
                             airDate: nil, lastUpdated: Date()),
        ]
    }
}

// MARK: - Small

private struct UpNextSmallView: View {
    let entry: UpNextEntry

    var body: some View {
        if let item = entry.first {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let img = item.posterImage {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.accentColor.opacity(0.3)
                    }
                }
                LinearGradient(colors: [.clear, .black.opacity(0.9)],
                               startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text("UP NEXT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                    Text(item.title)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(item.availabilityText ?? item.code)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(item.isAvailable ? .green : .orange)
                }
                .padding(10)
            }
            .widgetURL(item.url ?? upNextEmptyURL)
        } else {
            UpNextEmptyView()
        }
    }
}

// MARK: - Medium

private struct UpNextMediumView: View {
    let entry: UpNextEntry

    var body: some View {
        if entry.items.isEmpty {
            UpNextEmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "play.rectangle.on.rectangle")
                    Text("Up Next").fontWeight(.bold)
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.accentColor)

                ForEach(Array(entry.items.prefix(3))) { item in
                    if let url = item.url {
                        Link(destination: url) { UpNextRow(item: item) }
                    } else {
                        UpNextRow(item: item)
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetURL(upNextEmptyURL)
        }
    }
}

private struct UpNextRow: View {
    let item: UpNextWidgetItem

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if let img = item.posterImage {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.accentColor.opacity(0.25)
                    Image(systemName: "tv")
                        .font(.caption2)
                        .foregroundColor(.accentColor.opacity(0.6))
                }
            }
            .frame(width: 22, height: 33)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(episodeLine)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let airs = item.availabilityText {
                Text(airs)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
            }
        }
    }

    private var episodeLine: String {
        guard let name = item.episodeTitle, !name.isEmpty else { return item.code }
        return "\(item.code) · \(name)"
    }
}

// MARK: - Lock Screen

private struct UpNextRectangularView: View {
    let entry: UpNextEntry

    var body: some View {
        if let item = entry.first {
            VStack(alignment: .leading, spacing: 1) {
                Label("Up Next", systemImage: "play.rectangle.on.rectangle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(item.availabilityText ?? item.code)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(item.url ?? upNextEmptyURL)
        } else {
            Label("All caught up", systemImage: "checkmark.circle")
                .font(.caption)
        }
    }
}

private struct UpNextInlineView: View {
    let entry: UpNextEntry

    var body: some View {
        if let item = entry.first {
            Label("\(item.title) · \(item.code)", systemImage: "play.rectangle.on.rectangle")
        } else {
            Label("All caught up", systemImage: "checkmark.circle")
        }
    }
}

// MARK: - Empty

/// No Up Next yet: nothing in progress, or every show is finished.
private let upNextEmptyURL = URL(string: "watchguide://watchlist")

private struct UpNextEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("All caught up")
                .font(.caption.bold())
            Text("Start a show in WatchGuide and your next episode shows up here.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(upNextEmptyURL)
    }
}

// MARK: - Entry View Router

private struct UpNextEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: UpNextEntry

    var body: some View {
        switch family {
        case .systemSmall:          UpNextSmallView(entry: entry).environment(\.colorScheme, .dark)
        case .accessoryRectangular: UpNextRectangularView(entry: entry)
        case .accessoryInline:      UpNextInlineView(entry: entry)
        default:                    UpNextMediumView(entry: entry).environment(\.colorScheme, .dark)
        }
    }
}

// MARK: - Widget

struct UpNextWidget: Widget {
    static let kind = "com.JasonSmith.WatchGuide-MovieandTVtracker.upnext"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: UpNextProvider()) { entry in
            UpNextEntryView(entry: entry)
                .containerBackground(widgetBrandBackground, for: .widget)
        }
        .configurationDisplayName("Up Next")
        .description("The next episode of each show you're watching.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
