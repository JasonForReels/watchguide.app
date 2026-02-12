//
//  StatsInsightsView.swift
//  WatchGuide-MovieandTVtracker
//
//  Personal analytics dashboard for watching habits
//

import SwiftUI

struct StatsInsightsView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var movieGenreCounts: [(name: String, count: Int)] = []
    @State private var tvGenreCounts: [(name: String, count: Int)] = []
    @State private var decadeCounts: [(decade: String, count: Int)] = []
    @State private var ratingDistribution: [(range: String, count: Int)] = []
    @State private var topRatedItems: [SavedMediaItem] = []
    @State private var recentlyAdded: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var allGenres: [Genre] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Overview Cards
                overviewSection
                
                // Watching Streak / Activity
                activitySection
                
                // Genre Breakdown
                if !movieGenreCounts.isEmpty || !tvGenreCounts.isEmpty {
                    genreSection
                }
                
                // Decade Distribution
                if !decadeCounts.isEmpty {
                    decadeSection
                }
                
                // Rating Distribution
                if !ratingDistribution.isEmpty {
                    ratingSection
                }
                
                // Top Rated in Your Lists
                if !topRatedItems.isEmpty {
                    topRatedSection
                }
                
                // Recently Added
                if !recentlyAdded.isEmpty {
                    recentlyAddedSection
                }
                
                Spacer(minLength: 40)
            }
            .padding(.top, 12)
        }
        .navigationTitle("My Stats")
        .task {
            await loadStats()
        }
    }
    
    // MARK: - Overview Cards
    private var overviewSection: some View {
        VStack(spacing: 16) {
            // Big numbers
            HStack(spacing: 12) {
                OverviewCard(
                    title: "Total Tracked",
                    value: "\(totalTracked)",
                    subtitle: "movies & shows",
                    iconName: "film.stack.fill",
                    color: .accentColor
                )
                
                OverviewCard(
                    title: "Watched",
                    value: "\(storage.watched.count)",
                    subtitle: watchedBreakdown,
                    iconName: "checkmark.circle.fill",
                    color: .green
                )
            }
            .padding(.horizontal)
            
            HStack(spacing: 12) {
                OverviewCard(
                    title: "Watchlist",
                    value: "\(storage.wantToWatch.count)",
                    subtitle: "queued up",
                    iconName: "bookmark.fill",
                    color: .blue
                )
                
                OverviewCard(
                    title: "Liked",
                    value: "\(storage.liked.count)",
                    subtitle: "favorites",
                    iconName: "heart.fill",
                    color: .red
                )
            }
            .padding(.horizontal)
            
            // Avg rating
            if avgRating > 0 {
                HStack(spacing: 12) {
                    OverviewCard(
                        title: "Avg Rating",
                        value: String(format: "%.1f", avgRating),
                        subtitle: "across your lists",
                        iconName: "star.fill",
                        color: .yellow
                    )
                    
                    OverviewCard(
                        title: "Custom Lists",
                        value: "\(storage.customLists.count)",
                        subtitle: "\(totalCustomItems) items total",
                        iconName: "folder.fill",
                        color: .purple
                    )
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Activity Section
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            // Movie vs TV ratio
            let movieCount = allItems.filter { $0.mediaType == .movie }.count
            let tvCount = allItems.filter { $0.mediaType == .tv }.count
            let total = max(movieCount + tvCount, 1)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Movies vs TV Shows")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(movieCount) / \(tvCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                GeometryReader { geo in
                    let movieWidth = geo.size.width * CGFloat(movieCount) / CGFloat(total)
                    
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.mint.opacity(0.3))
                            .frame(height: 10)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor)
                            .frame(width: max(movieWidth, 4), height: 10)
                    }
                }
                .frame(height: 10)
                
                HStack {
                    HStack(spacing: 4) {
                        Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                        Text("Movies (\(Int(Double(movieCount) / Double(total) * 100))%)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(Color.mint.opacity(0.3)).frame(width: 8, height: 8)
                        Text("TV Shows (\(Int(Double(tvCount) / Double(total) * 100))%)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(14)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Genre Section
    private var genreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Genres")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            let combined = combineGenreCounts()
            let maxCount = combined.first?.count ?? 1
            
            VStack(spacing: 8) {
                ForEach(combined.prefix(8), id: \.name) { genre in
                    HStack(spacing: 12) {
                        Text(genre.name)
                            .font(.subheadline)
                            .frame(width: 100, alignment: .trailing)
                        
                        GeometryReader { geo in
                            let barWidth = geo.size.width * CGFloat(genre.count) / CGFloat(max(maxCount, 1))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.7))
                                .frame(width: max(barWidth, 4), height: 20)
                        }
                        .frame(height: 20)
                        
                        Text("\(genre.count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .leading)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(14)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Decade Section
    private var decadeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Decade")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            let maxCount = decadeCounts.max(by: { $0.count < $1.count })?.count ?? 1
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(decadeCounts, id: \.decade) { item in
                        VStack(spacing: 6) {
                            // Bar
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.6))
                                .frame(width: 36, height: CGFloat(item.count) / CGFloat(max(maxCount, 1)) * 100)
                            
                            Text("\(item.count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                            
                            Text(item.decade)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(minHeight: 140, alignment: .bottom)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Rating Section
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rating Distribution")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            let maxCount = ratingDistribution.max(by: { $0.count < $1.count })?.count ?? 1
            
            VStack(spacing: 6) {
                ForEach(ratingDistribution, id: \.range) { item in
                    HStack(spacing: 8) {
                        Text(item.range)
                            .font(.caption)
                            .frame(width: 50, alignment: .trailing)
                        
                        GeometryReader { geo in
                            let barWidth = geo.size.width * CGFloat(item.count) / CGFloat(max(maxCount, 1))
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ratingColor(for: item.range))
                                .frame(width: max(barWidth, 2), height: 16)
                        }
                        .frame(height: 16)
                        
                        Text("\(item.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 24, alignment: .leading)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(14)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Top Rated Section
    private var topRatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Highest Rated")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(topRatedItems.prefix(10)) { item in
                        VStack(spacing: 6) {
                            PosterImageView(posterPath: item.posterPath, size: .medium, mediaId: item.mediaId, mediaType: item.mediaType)
                                .frame(width: 100, height: 150)
                            
                            if let rating = item.voteAverage, rating > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.yellow)
                                    Text(String(format: "%.1f", rating))
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                }
                            }
                            
                            Text(item.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 100)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Recently Added Section
    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Added")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentlyAdded.prefix(10)) { item in
                        VStack(spacing: 6) {
                            PosterImageView(posterPath: item.posterPath, size: .medium, mediaId: item.mediaId, mediaType: item.mediaType)
                                .frame(width: 100, height: 150)
                            
                            Text(item.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 100)
                            
                            Text(item.addedAt.formatted(.relative(presentation: .named)))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 100)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Computed Properties
    private var totalTracked: Int {
        let allIds = Set(
            storage.wantToWatch.map { $0.id } +
            storage.watched.map { $0.id } +
            storage.liked.map { $0.id }
        )
        return allIds.count
    }
    
    private var allItems: [SavedMediaItem] {
        var seen = Set<String>()
        var items: [SavedMediaItem] = []
        for item in storage.watched + storage.liked + storage.wantToWatch {
            if !seen.contains(item.id) {
                seen.insert(item.id)
                items.append(item)
            }
        }
        return items
    }
    
    private var watchedBreakdown: String {
        let movies = storage.watched.filter { $0.mediaType == .movie }.count
        let tv = storage.watched.filter { $0.mediaType == .tv }.count
        return "\(movies) movies, \(tv) shows"
    }
    
    private var avgRating: Double {
        let items = allItems.compactMap { $0.voteAverage }.filter { $0 > 0 }
        guard !items.isEmpty else { return 0 }
        return items.reduce(0, +) / Double(items.count)
    }
    
    private var totalCustomItems: Int {
        storage.customLists.reduce(0) { $0 + $1.items.count }
    }
    
    // MARK: - Helpers
    private func combineGenreCounts() -> [(name: String, count: Int)] {
        var combined: [String: Int] = [:]
        for g in movieGenreCounts {
            combined[g.name, default: 0] += g.count
        }
        for g in tvGenreCounts {
            combined[g.name, default: 0] += g.count
        }
        return combined.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    private func ratingColor(for range: String) -> Color {
        switch range {
        case "9-10": return .green
        case "8-9": return Color(.systemGreen).opacity(0.8)
        case "7-8": return .teal
        case "6-7": return .yellow
        case "5-6": return .orange
        default: return .red.opacity(0.7)
        }
    }
    
    // MARK: - Load Stats
    private func loadStats() async {
        // Load genres
        do {
            let movieGenresResp = try await TMDBService.shared.getMovieGenres()
            let tvGenresResp = try await TMDBService.shared.getTVGenres()
            allGenres = movieGenresResp.genres + tvGenresResp.genres
        } catch {
            print("Error loading genres: \(error)")
        }
        
        let items = allItems
        
        // Genre counting via genreIds on the items
        // Since SavedMediaItem doesn't store genreIds, we'll approximate from TMDB detail loading
        // For now, count what we have locally
        
        // Decade distribution
        var decades: [String: Int] = [:]
        for item in items {
            if let year = item.year, year.count >= 4, let y = Int(year) {
                let decade = "\(y / 10 * 10)s"
                decades[decade, default: 0] += 1
            }
        }
        decadeCounts = decades.sorted { $0.key < $1.key }.map { (decade: $0.key, count: $0.value) }
        
        // Rating distribution
        var ratings: [String: Int] = [
            "9-10": 0, "8-9": 0, "7-8": 0, "6-7": 0, "5-6": 0, "0-5": 0
        ]
        for item in items {
            if let r = item.voteAverage, r > 0 {
                if r >= 9 { ratings["9-10", default: 0] += 1 }
                else if r >= 8 { ratings["8-9", default: 0] += 1 }
                else if r >= 7 { ratings["7-8", default: 0] += 1 }
                else if r >= 6 { ratings["6-7", default: 0] += 1 }
                else if r >= 5 { ratings["5-6", default: 0] += 1 }
                else { ratings["0-5", default: 0] += 1 }
            }
        }
        let ratingOrder = ["9-10", "8-9", "7-8", "6-7", "5-6", "0-5"]
        ratingDistribution = ratingOrder.compactMap { key in
            if let count = ratings[key], count > 0 {
                return (range: key, count: count)
            }
            return nil
        }
        
        // Top rated
        topRatedItems = items
            .filter { ($0.voteAverage ?? 0) > 0 }
            .sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }
        
        // Recently added
        recentlyAdded = items.sorted { $0.addedAt > $1.addedAt }
        
        isLoading = false
    }
}

// MARK: - Overview Card
struct OverviewCard: View {
    let title: String
    let value: String
    let subtitle: String
    let iconName: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName)
                    .font(.subheadline)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }
}

#Preview {
    NavigationStack {
        StatsInsightsView()
    }
}
