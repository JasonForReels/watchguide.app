import WidgetKit
import SwiftUI

// MARK: - Data Models

struct TrendingMovie: Identifiable {
    let id: Int
    let title: String
    let posterPath: String?
    let voteAverage: Double
    let year: String?
    let posterImage: UIImage?
}

// MARK: - Timeline Entry

struct TrendingMoviesEntry: TimelineEntry {
    let date: Date
    let movies: [TrendingMovie]
    let isPlaceholder: Bool
    
    static var placeholder: TrendingMoviesEntry {
        TrendingMoviesEntry(
            date: Date(),
            movies: (1...10).map { i in
                TrendingMovie(id: i, title: "Movie Title", posterPath: nil, voteAverage: 7.5, year: "2025", posterImage: nil)
            },
            isPlaceholder: true
        )
    }
}

// MARK: - Network Fetching

struct TrendingMovieFetcher {
    private static let tmdbAPIKey = "53b0ac93f3955b6a6ccb9782752fecf1"
    private static let baseURL = "https://api.themoviedb.org/3"
    private static let imageBaseURL = "https://image.tmdb.org/t/p"
    
    static func fetchTrendingMovies(count: Int) async -> [TrendingMovie] {
        guard var components = URLComponents(string: "\(baseURL)/trending/movie/week") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "api_key", value: tmdbAPIKey),
            URLQueryItem(name: "page", value: "1")
        ]
        guard let url = components.url else { return [] }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(TMDBWidgetResponse.self, from: data)
            let topResults = Array(decoded.results.prefix(count))
            
            // Download poster images concurrently
            return await withTaskGroup(of: TrendingMovie?.self, returning: [TrendingMovie].self) { group in
                for item in topResults {
                    group.addTask {
                        let title = item.title ?? item.name ?? "Unknown"
                        let year: String? = {
                            let dateStr = item.release_date ?? item.first_air_date
                            guard let d = dateStr, d.count >= 4 else { return nil }
                            return String(d.prefix(4))
                        }()
                        
                        var posterImage: UIImage? = nil
                        if let posterPath = item.poster_path,
                           let imgURL = URL(string: "\(imageBaseURL)/w185\(posterPath)") {
                            if let (imgData, _) = try? await URLSession.shared.data(from: imgURL) {
                                posterImage = UIImage(data: imgData)
                            }
                        }
                        
                        return TrendingMovie(
                            id: item.id,
                            title: title,
                            posterPath: item.poster_path,
                            voteAverage: item.vote_average ?? 0,
                            year: year,
                            posterImage: posterImage
                        )
                    }
                }
                
                var results: [TrendingMovie] = []
                for await movie in group {
                    if let movie = movie {
                        results.append(movie)
                    }
                }
                
                // Preserve original order from TMDB trending
                let orderMap = Dictionary(uniqueKeysWithValues: topResults.enumerated().map { ($0.element.id, $0.offset) })
                results.sort { (orderMap[$0.id] ?? 0) < (orderMap[$1.id] ?? 0) }
                
                return results
            }
        } catch {
            return []
        }
    }
}

// MARK: - TMDB Codable Response (widget-local)

private struct TMDBWidgetResponse: Codable {
    let results: [TMDBWidgetMovie]
}

private struct TMDBWidgetMovie: Codable {
    let id: Int
    let title: String?
    let name: String?
    let poster_path: String?
    let vote_average: Double?
    let release_date: String?
    let first_air_date: String?
}

// MARK: - Timeline Provider

struct TrendingMoviesProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrendingMoviesEntry {
        .placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (TrendingMoviesEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        let count = movieCount(for: context.family)
        Task {
            let movies = await TrendingMovieFetcher.fetchTrendingMovies(count: count)
            let entry = TrendingMoviesEntry(date: Date(), movies: movies, isPlaceholder: false)
            completion(entry)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<TrendingMoviesEntry>) -> Void) {
        let count = movieCount(for: context.family)
        Task {
            let movies = await TrendingMovieFetcher.fetchTrendingMovies(count: count)
            let entry = TrendingMoviesEntry(date: Date(), movies: movies, isPlaceholder: false)
            // Refresh every 2 hours
            let nextRefresh = Date().addingTimeInterval(2 * 60 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
            completion(timeline)
        }
    }
    
    private func movieCount(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 5
        case .systemLarge: return 10
        @unknown default: return 5
        }
    }
}

// MARK: - Widget Views

struct TrendingMoviesWidgetEntryView: View {
    var entry: TrendingMoviesEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        case .systemLarge:
            largeWidget
        default:
            mediumWidget
        }
    }
    
    // MARK: Small — 2 movies, poster-centric layout
    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Trending")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
            }
            
            if entry.movies.isEmpty && !entry.isPlaceholder {
                Spacer()
                HStack {
                    Spacer()
                    Text("No data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                HStack(spacing: 8) {
                    ForEach(entry.movies.prefix(2)) { movie in
                        smallMovieCard(movie: movie)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
    
    private func smallMovieCard(movie: TrendingMovie) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            posterView(movie: movie)
                .frame(maxWidth: .infinity)
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Text(movie.title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
    
    // MARK: Medium — 5 movies in a row
    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Trending Movies")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Spacer()
                Text("This Week")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            
            if entry.movies.isEmpty && !entry.isPlaceholder {
                Spacer()
                HStack {
                    Spacer()
                    Text("No data available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                HStack(spacing: 6) {
                    ForEach(entry.movies.prefix(5)) { movie in
                        mediumMovieCard(movie: movie)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
    
    private func mediumMovieCard(movie: TrendingMovie) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            posterView(movie: movie)
                .frame(maxWidth: .infinity)
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            
            Text(movie.title)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(2)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
    
    // MARK: Large — 10 movies in a ranked list
    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Text("Trending Movies")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Spacer()
                Text("This Week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)
            
            if entry.movies.isEmpty && !entry.isPlaceholder {
                Spacer()
                HStack {
                    Spacer()
                    Text("No data available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(Array(entry.movies.prefix(10).enumerated()), id: \.element.id) { index, movie in
                    largeMovieRow(movie: movie, rank: index + 1)
                    if index < min(entry.movies.count, 10) - 1 {
                        Divider()
                            .opacity(0.4)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
    
    private func largeMovieRow(movie: TrendingMovie, rank: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(rank <= 3 ? .orange : .secondary)
                .frame(width: 18, alignment: .center)
            
            posterView(movie: movie)
                .frame(width: 28, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            VStack(alignment: .leading, spacing: 1) {
                Text(movie.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 4) {
                    if let year = movie.year {
                        Text(year)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if movie.voteAverage > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", movie.voteAverage))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
    
    // MARK: Poster helper
    @ViewBuilder
    private func posterView(movie: TrendingMovie) -> some View {
        if let image = movie.posterImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.gray.opacity(0.2)
                Image(systemName: "film")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Widget Definition

struct TrendingMoviesWidget: Widget {
    let kind: String = "com.JasonSmith.WatchGuide-MovieandTVtracker.trending-movies"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrendingMoviesProvider()) { entry in
            if #available(iOS 17.0, *) {
                TrendingMoviesWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                TrendingMoviesWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Trending Movies")
        .description("See this week's top trending movies at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget Bundle

@main
struct WatchGuide_MovieandTVtrackerWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        TrendingMoviesWidget()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    TrendingMoviesWidget()
} timeline: {
    TrendingMoviesEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    TrendingMoviesWidget()
} timeline: {
    TrendingMoviesEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    TrendingMoviesWidget()
} timeline: {
    TrendingMoviesEntry.placeholder
}