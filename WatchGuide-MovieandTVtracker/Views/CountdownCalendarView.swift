//
//  CountdownCalendarView.swift
//  WatchGuide-MovieandTVtracker
//
//  Upcoming release countdowns for movies/shows — only future titles, capped at Dec 31 of current year
//

import SwiftUI

// MARK: - Language Filter
struct LanguageOption: Identifiable, Hashable {
    let id: String // ISO 639-1 code
    let name: String
    
    static let all = LanguageOption(id: "all", name: "All Languages")
    
    static let popular: [LanguageOption] = [
        .all,
        LanguageOption(id: "en", name: "English"),
        LanguageOption(id: "es", name: "Spanish"),
        LanguageOption(id: "fr", name: "French"),
        LanguageOption(id: "de", name: "German"),
        LanguageOption(id: "it", name: "Italian"),
        LanguageOption(id: "pt", name: "Portuguese"),
        LanguageOption(id: "ja", name: "Japanese"),
        LanguageOption(id: "ko", name: "Korean"),
        LanguageOption(id: "zh", name: "Chinese"),
        LanguageOption(id: "hi", name: "Hindi"),
        LanguageOption(id: "ar", name: "Arabic"),
        LanguageOption(id: "ru", name: "Russian"),
        LanguageOption(id: "tr", name: "Turkish"),
        LanguageOption(id: "nl", name: "Dutch"),
        LanguageOption(id: "sv", name: "Swedish"),
        LanguageOption(id: "pl", name: "Polish"),
        LanguageOption(id: "da", name: "Danish"),
        LanguageOption(id: "no", name: "Norwegian"),
        LanguageOption(id: "fi", name: "Finnish"),
        LanguageOption(id: "th", name: "Thai"),
        LanguageOption(id: "id", name: "Indonesian"),
        LanguageOption(id: "tl", name: "Filipino"),
        LanguageOption(id: "ms", name: "Malay"),
        LanguageOption(id: "af", name: "Afrikaans"),
        LanguageOption(id: "zu", name: "Zulu"),
    ]
}

struct CountdownCalendarView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var upcomingItems: [CountdownItem] = []
    @State private var isLoading = true
    @State private var selectedItem: MediaItem?
    @State private var selectedTab = 0
    @State private var showLanguageFilter = false
    @State private var selectedLanguage: LanguageOption = .all
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Source", selection: $selectedTab) {
                Text("Upcoming").tag(0)
                Text("My Watchlist").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Active language filter chip
            if selectedLanguage.id != "all" {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.caption2)
                    Text(selectedLanguage.name)
                        .font(.caption)
                        .fontWeight(.medium)
                    Button {
                        withAnimation { selectedLanguage = .all }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                    }
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(20)
                .padding(.bottom, 8)
            }
            
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
            } else if displayedItems.isEmpty {
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
                        if let nextUp = displayedItems.first {
                            CountdownFeaturedCard(item: nextUp) {
                                selectedItem = nextUp.mediaItem
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                        }
                        
                        // Group by month
                        ForEach(groupedByMonth, id: \.month) { group in
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showLanguageFilter = true
                } label: {
                    Image(systemName: "globe")
                        .font(.body)
                }
            }
        }
        .task {
            await loadUpcoming()
        }
        .sheet(item: $selectedItem) { item in
            MediaDetailView(item: item)
        }
        .sheet(isPresented: $showLanguageFilter) {
            CountdownLanguageFilterSheet(selectedLanguage: $selectedLanguage)
        }
    }
    
    // MARK: - Filtered & displayed items
    
    private var displayedItems: [CountdownItem] {
        var items = filteredByTab
        
        // Apply language filter
        if selectedLanguage.id != "all" {
            items = items.filter { $0.originalLanguage == selectedLanguage.id }
        }
        
        return items
    }
    
    private var filteredByTab: [CountdownItem] {
        if selectedTab == 0 {
            return upcomingItems
        } else {
            let watchlistIds = Set(storage.wantToWatch.map { $0.mediaId })
            return upcomingItems.filter { watchlistIds.contains($0.mediaItem.id) }
        }
    }
    
    private var groupedByMonth: [(month: String, items: [CountdownItem])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        
        var groups: [String: [CountdownItem]] = [:]
        var monthOrder: [String] = []
        
        // Skip the first item since it's the featured card
        let itemsAfterFirst = Array(displayedItems.dropFirst())
        
        for item in itemsAfterFirst {
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
    
    // MARK: - Loading
    
    private func loadUpcoming() async {
        isLoading = true
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        // Strictly future: tomorrow onward
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        // End of current calendar year
        let currentYear = calendar.component(.year, from: now)
        let endOfYearString = "\(currentYear)-12-31"
        guard let endOfYear = dateFormatter.date(from: endOfYearString) else {
            isLoading = false
            return
        }
        
        var items: [CountdownItem] = []
        
        // Load upcoming movies (3 pages for more coverage)
        do {
            async let p1 = TMDBService.shared.getUpcomingMovies(page: 1, endDate: endOfYearString)
            async let p2 = TMDBService.shared.getUpcomingMovies(page: 2, endDate: endOfYearString)
            async let p3 = TMDBService.shared.getUpcomingMovies(page: 3, endDate: endOfYearString)
            
            let allResults = try await (p1.results + p2.results + p3.results)
            
            for movie in allResults {
                guard let dateString = movie.releaseDate,
                      let date = dateFormatter.date(from: dateString) else { continue }
                // Only include strictly future dates, up to end of year
                guard date >= tomorrow && date <= endOfYear else { continue }
                
                let item = CountdownItem(
                    id: "movie-\(movie.id)",
                    title: movie.displayTitle,
                    subtitle: nil,
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
                    mediaType: .movie,
                    originalLanguage: movie.originalLanguage
                )
                items.append(item)
            }
        } catch {
            print("Error loading upcoming movies: \(error)")
        }
        
        // Load upcoming new TV shows
        do {
            async let p1 = TMDBService.shared.getUpcomingTV(page: 1, endDate: endOfYearString)
            async let p2 = TMDBService.shared.getUpcomingTV(page: 2, endDate: endOfYearString)
            async let p3 = TMDBService.shared.getUpcomingTV(page: 3, endDate: endOfYearString)
            
            let allResults = try await (p1.results + p2.results + p3.results)
            
            for show in allResults {
                let dateString = show.firstAirDate ?? show.releaseDate
                guard let dateStr = dateString,
                      let date = dateFormatter.date(from: dateStr) else { continue }
                guard date >= tomorrow && date <= endOfYear else { continue }
                
                let item = CountdownItem(
                    id: "tv-\(show.id)",
                    title: show.displayTitle,
                    subtitle: "New Series",
                    mediaItem: MediaItem(
                        id: show.id,
                        title: show.title,
                        name: show.name,
                        originalTitle: show.originalTitle,
                        originalName: show.originalName,
                        overview: show.overview,
                        posterPath: show.posterPath,
                        backdropPath: show.backdropPath,
                        releaseDate: show.releaseDate,
                        firstAirDate: show.firstAirDate,
                        voteAverage: show.voteAverage,
                        voteCount: show.voteCount,
                        popularity: show.popularity,
                        genreIds: show.genreIds,
                        mediaType: "tv",
                        adult: show.adult,
                        originalLanguage: show.originalLanguage
                    ),
                    releaseDate: date,
                    mediaType: .tv,
                    originalLanguage: show.originalLanguage
                )
                items.append(item)
            }
        } catch {
            print("Error loading upcoming TV: \(error)")
        }
        
        // Load on-the-air TV shows with next episode (returning episodes for existing shows)
        do {
            let onAir = try await TMDBService.shared.getOnTheAirTV(page: 1)
            
            // For each on-the-air show, check if it has a next episode to air
            await withTaskGroup(of: CountdownItem?.self) { group in
                for show in onAir.results.prefix(30) {
                    group.addTask {
                        do {
                            let info = try await TMDBService.shared.getTVShowNextEpisode(id: show.id)
                            
                            // Skip cancelled shows
                            if let status = info.status,
                               status == "Canceled" || status == "Cancelled" {
                                return nil
                            }
                            
                            guard let nextEp = info.nextEpisodeToAir,
                                  let airDateStr = nextEp.airDate,
                                  let airDate = dateFormatter.date(from: airDateStr) else { return nil }
                            
                            // Only future dates within this year
                            guard airDate >= tomorrow && airDate <= endOfYear else { return nil }
                            
                            let epLabel: String
                            if let s = nextEp.seasonNumber, let e = nextEp.episodeNumber {
                                epLabel = "S\(s)E\(e)"
                            } else {
                                epLabel = "New Episode"
                            }
                            
                            return CountdownItem(
                                id: "tv-ep-\(show.id)-\(nextEp.id)",
                                title: show.displayTitle,
                                subtitle: epLabel + (nextEp.name != nil ? ": \(nextEp.name!)" : ""),
                                mediaItem: MediaItem(
                                    id: show.id,
                                    title: show.title,
                                    name: show.name,
                                    originalTitle: show.originalTitle,
                                    originalName: show.originalName,
                                    overview: nextEp.overview ?? show.overview,
                                    posterPath: show.posterPath,
                                    backdropPath: show.backdropPath,
                                    releaseDate: show.releaseDate,
                                    firstAirDate: airDateStr,
                                    voteAverage: show.voteAverage,
                                    voteCount: show.voteCount,
                                    popularity: show.popularity,
                                    genreIds: show.genreIds,
                                    mediaType: "tv",
                                    adult: show.adult,
                                    originalLanguage: show.originalLanguage
                                ),
                                releaseDate: airDate,
                                mediaType: .tv,
                                originalLanguage: show.originalLanguage ?? info.originalLanguage
                            )
                        } catch {
                            return nil
                        }
                    }
                }
                
                for await item in group {
                    if let item = item {
                        items.append(item)
                    }
                }
            }
        } catch {
            print("Error loading on-the-air TV episodes: \(error)")
        }
        
        // Deduplicate: prefer episode-specific entries over generic show entries
        var seen = Set<String>()
        // Sort episode items first so they take precedence in dedup
        let sortedForDedup = items.sorted { a, b in
            // Episode-specific items come first
            if a.id.hasPrefix("tv-ep-") && !b.id.hasPrefix("tv-ep-") { return true }
            if !a.id.hasPrefix("tv-ep-") && b.id.hasPrefix("tv-ep-") { return false }
            return a.releaseDate < b.releaseDate
        }
        
        var deduped: [CountdownItem] = []
        var seenShowIds = Set<Int>()
        
        for item in sortedForDedup {
            // For TV items, deduplicate by show ID (keep the episode-specific one)
            if item.mediaType == .tv {
                if seenShowIds.contains(item.mediaItem.id) {
                    continue
                }
                seenShowIds.insert(item.mediaItem.id)
            }
            if seen.insert(item.id).inserted {
                deduped.append(item)
            }
        }
        
        upcomingItems = deduped.sorted { $0.releaseDate < $1.releaseDate }
        isLoading = false
    }
}

// MARK: - Countdown Item Model
struct CountdownItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String? // e.g. "S2E5: Episode Name" or "New Series"
    let mediaItem: MediaItem
    let releaseDate: Date
    let mediaType: MediaType
    let originalLanguage: String?
    
    init(id: String, title: String? = nil, subtitle: String? = nil, mediaItem: MediaItem, releaseDate: Date, mediaType: MediaType, originalLanguage: String? = nil) {
        self.id = id
        self.title = title ?? mediaItem.displayTitle
        self.subtitle = subtitle
        self.mediaItem = mediaItem
        self.releaseDate = releaseDate
        self.mediaType = mediaType
        self.originalLanguage = originalLanguage ?? mediaItem.originalLanguage
    }
    
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
        if days <= 0 { return "Released" }
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
                
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEXT UP")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(1)
                        .foregroundColor(.accentColor)
                    
                    Text(item.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text(item.mediaType == .movie ? "Movie" : "TV")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(item.mediaType == .movie ? Color.blue.opacity(0.3) : Color.purple.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            
                            Text(item.releaseDateFormatted)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
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
                PosterImageView(posterPath: item.mediaItem.posterPath, size: .small, mediaId: item.mediaItem.id, mediaType: item.mediaType)
                    .frame(width: 60, height: 90)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                    
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 6) {
                        Text(item.mediaType == .movie ? "Movie" : "TV")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(item.mediaType == .movie ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                            .foregroundColor(item.mediaType == .movie ? .blue : .purple)
                            .cornerRadius(4)
                        
                        Text(item.releaseDateFormatted)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let overview = item.mediaItem.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
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

// MARK: - Language Filter Sheet
struct CountdownLanguageFilterSheet: View {
    @Binding var selectedLanguage: LanguageOption
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private var filteredLanguages: [LanguageOption] {
        if searchText.isEmpty {
            return LanguageOption.popular
        }
        return LanguageOption.popular.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredLanguages) { lang in
                    Button {
                        selectedLanguage = lang
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lang.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                if lang.id != "all" {
                                    Text(lang.id.uppercased())
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if selectedLanguage.id == lang.id {
                                Image(systemName: "checkmark")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search languages")
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    NavigationStack {
        CountdownCalendarView()
    }
}
