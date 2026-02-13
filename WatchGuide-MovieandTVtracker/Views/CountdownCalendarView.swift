//
//  CountdownCalendarView.swift
//  WatchGuide-MovieandTVtracker
//
//  Upcoming release countdowns for movies/shows in your watchlist + trending upcoming
//

import SwiftUI

struct CountdownCalendarView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var upcomingItems: [CountdownItem] = []
    @State private var isLoading = true
    @State private var selectedItem: MediaItem?
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Source", selection: $selectedTab) {
                Text("Upcoming").tag(0)
                Text("My Watchlist").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading upcoming releases...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if filteredItems.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(selectedTab == 0 ? "No upcoming releases found" : "No upcoming items in your watchlist")
                        .font(.headline)
                    Text(selectedTab == 0 ? "Check back soon!" : "Add upcoming movies or shows to your watchlist")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Featured next-up card
                        if let nextUp = filteredItems.first {
                            CountdownFeaturedCard(item: nextUp) {
                                selectedItem = nextUp.mediaItem
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                        }
                        
                        // Group by month
                        ForEach(groupedByMonth, id: \.month) { group in
                            // Month header
                            HStack {
                                Text(group.month)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                Spacer()
                                Text("\(group.items.count) titles")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.top, 20)
                            .padding(.bottom, 8)
                            
                            ForEach(group.items) { item in
                                CountdownRow(item: item) {
                                    selectedItem = item.mediaItem
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Countdown")
        .task {
            await loadUpcoming()
        }
        .sheet(item: $selectedItem) { item in
            MediaDetailView(item: item)
        }
    }
    
    private var filteredItems: [CountdownItem] {
        if selectedTab == 0 {
            return upcomingItems
        } else {
            // Filter to only items in user's watchlist
            let watchlistIds = Set(storage.wantToWatch.map { $0.mediaId })
            return upcomingItems.filter { watchlistIds.contains($0.mediaItem.id) }
        }
    }
    
    private var groupedByMonth: [(month: String, items: [CountdownItem])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        
        var groups: [String: [CountdownItem]] = [:]
        var monthOrder: [String] = []
        
        for item in filteredItems {
            let key = formatter.string(from: item.releaseDate)
            if groups[key] == nil {
                monthOrder.append(key)
            }
            groups[key, default: []].append(item)
        }
        
        return monthOrder.map { month in
            (month: month, items: groups[month] ?? [])
        }
    }
    
    private func loadUpcoming() async {
        isLoading = true
        
        do {
            // Load upcoming movies
            let movies = try await TMDBService.shared.getUpcomingMovies()
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let today = Date()
            
            var items: [CountdownItem] = []
            
            for movie in movies.results {
                if let dateString = movie.releaseDate,
                   let date = formatter.date(from: dateString),
                   date >= today {
                    let item = CountdownItem(
                        id: "movie-\(movie.id)",
                        mediaItem: MediaItem(
                            id: movie.id,
                            title: movie.title,
                            name: movie.name,
                            originalTitle: movie.originalTitle,
                            originalName: movie.originalName,
                            overview: movie.overview,
                            posterPath: movie.posterPath,
                            backdropPath: movie.backdropPath,
                            releaseDate: movie.releaseDate,
                            firstAirDate: movie.firstAirDate,
                            voteAverage: movie.voteAverage,
                            voteCount: movie.voteCount,
                            popularity: movie.popularity,
                            genreIds: movie.genreIds,
                            mediaType: "movie",
                            adult: movie.adult,
                            originalLanguage: movie.originalLanguage
                        ),
                        releaseDate: date,
                        mediaType: .movie
                    )
                    items.append(item)
                }
            }
            
            upcomingItems = items.sorted { $0.releaseDate < $1.releaseDate }
        } catch {
            print("Error loading upcoming: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Countdown Item Model
struct CountdownItem: Identifiable {
    let id: String
    let mediaItem: MediaItem
    let releaseDate: Date
    let mediaType: MediaType
    
    var daysUntilRelease: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: releaseDate)).day ?? 0
    }
    
    var releaseDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: releaseDate)
    }
    
    var countdownText: String {
        let days = daysUntilRelease
        if days == 0 { return "Today!" }
        if days == 1 { return "Tomorrow" }
        if days < 7 { return "\(days) days" }
        let weeks = days / 7
        let remainingDays = days % 7
        if remainingDays == 0 {
            return "\(weeks) week\(weeks > 1 ? "s" : "")"
        }
        return "\(weeks)w \(remainingDays)d"
    }
    
    var urgencyColor: Color {
        let days = daysUntilRelease
        if days <= 1 { return .green }
        if days <= 7 { return .orange }
        if days <= 30 { return .blue }
        return .secondary
    }
}

// MARK: - Featured Countdown Card
struct CountdownFeaturedCard: View {
    let item: CountdownItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Backdrop
                AsyncImage(url: TMDBService.shared.imageURL(path: item.mediaItem.backdropPath, size: .backdrop)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16.0/9.0, contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .aspectRatio(16.0/9.0, contentMode: .fill)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Dark overlay
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEXT UP")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(1)
                        .foregroundColor(.accentColor)
                    
                    Text(item.mediaItem.displayTitle)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    HStack(spacing: 12) {
                        Text(item.releaseDateFormatted)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text(item.countdownText)
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(item.urgencyColor.opacity(0.2))
                            .foregroundColor(item.urgencyColor)
                            .cornerRadius(6)
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Countdown Row
struct CountdownRow: View {
    let item: CountdownItem
    let onTap: () -> Void
    @ObservedObject private var storage = StorageService.shared
    
    private var isInWatchlist: Bool {
        storage.isInWantToWatch(item.mediaItem.id, mediaType: item.mediaType)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Poster
                PosterImageView(posterPath: item.mediaItem.posterPath, size: .small, mediaId: item.mediaItem.id, mediaType: item.mediaType)
                    .frame(width: 60, height: 90)
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.mediaItem.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                    
                    Text(item.releaseDateFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let overview = item.mediaItem.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                // Countdown badge
                VStack(spacing: 4) {
                    Text(item.countdownText)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(item.urgencyColor)
                    
                    if isInWatchlist {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
                .frame(minWidth: 60)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        
        Divider()
            .padding(.leading, 90)
    }
}

#Preview {
    NavigationStack {
        CountdownCalendarView()
    }
}
