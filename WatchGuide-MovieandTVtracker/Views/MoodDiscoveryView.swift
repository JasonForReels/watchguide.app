//
//  MoodDiscoveryView.swift
//  WatchGuide-MovieandTVtracker
//
//  Mood-based discovery: pick your vibe, get curated results
//

import SwiftUI

// MARK: - Mood Model
struct MoodOption: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let subtitle: String
    let genreIds: [Int]       // TMDB genre IDs
    let keywords: [Int]       // TMDB keyword IDs (optional extra filter)
    let sortBy: String
    let color: Color
    
    static let moods: [MoodOption] = [
        MoodOption(name: "Feel-Good", emoji: "☀️", subtitle: "Uplifting & heartwarming", genreIds: [35, 10751], keywords: [], sortBy: "vote_average.desc", color: Color.yellow),
        MoodOption(name: "Edge of My Seat", emoji: "🔥", subtitle: "Thrilling & intense", genreIds: [28, 53], keywords: [], sortBy: "popularity.desc", color: Color.red),
        MoodOption(name: "Mind-Bending", emoji: "🧠", subtitle: "Twisty & thought-provoking", genreIds: [878, 9648], keywords: [], sortBy: "vote_average.desc", color: Color.purple),
        MoodOption(name: "Cozy Night In", emoji: "🌙", subtitle: "Relaxing & easy-going", genreIds: [10749, 35], keywords: [], sortBy: "popularity.desc", color: Color.indigo),
        MoodOption(name: "Epic Adventure", emoji: "⚔️", subtitle: "Grand scale & fantastical", genreIds: [12, 14], keywords: [], sortBy: "popularity.desc", color: Color.teal),
        MoodOption(name: "Laugh Out Loud", emoji: "😂", subtitle: "Hilarious comedies", genreIds: [35], keywords: [], sortBy: "popularity.desc", color: Color.orange),
        MoodOption(
            name: "Dark & Gritty",
            emoji: "🌑",
            subtitle: "Noir, crime & suspense",
            genreIds: [80, 53],
            keywords: [],
            sortBy: "vote_average.desc",
            color: {
                #if os(tvOS)
                return Color.gray
                #else
                return Color(.systemGray)
                #endif
            }()
        ),
        MoodOption(name: "Cry It Out", emoji: "💧", subtitle: "Emotional & moving dramas", genreIds: [18], keywords: [], sortBy: "vote_average.desc", color: Color.blue),
        MoodOption(
            name: "Spooky",
            emoji: "👻",
            subtitle: "Scary & unsettling",
            genreIds: [27],
            keywords: [],
            sortBy: "popularity.desc",
            color: {
                #if os(tvOS)
                return Color(white: 0.7)
                #else
                return Color(.systemGray2)
                #endif
            }()
        ),
        MoodOption(name: "Nostalgia Trip", emoji: "📼", subtitle: "Classics & retro favorites", genreIds: [], keywords: [], sortBy: "vote_count.desc", color: Color.brown),
        MoodOption(name: "Date Night", emoji: "❤️", subtitle: "Romantic & charming", genreIds: [10749], keywords: [], sortBy: "popularity.desc", color: Color.pink),
        MoodOption(name: "Family Time", emoji: "🏠", subtitle: "Fun for all ages", genreIds: [16, 10751], keywords: [], sortBy: "popularity.desc", color: Color.green),
    ]
}

// MARK: - Mood Filter Option
enum MoodSortFilter: String, CaseIterable, Identifiable {
    case mostPopular = "Most Popular"
    case trending = "Trending"
    case oldest = "Oldest"
    case newest = "Newest"
    case imdb = "IMDb"
    case rottenTomatoes = "Rotten Tomatoes"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .mostPopular: return "flame.fill"
        case .trending: return "chart.line.uptrend.xyaxis"
        case .oldest: return "clock.arrow.circlepath"
        case .newest: return "sparkles"
        case .imdb: return "star.fill"
        case .rottenTomatoes: return "percent"
        }
    }
    
    var tmdbSortBy: String {
        switch self {
        case .mostPopular: return "popularity.desc"
        case .trending: return "popularity.desc"
        case .oldest: return "primary_release_date.asc"
        case .newest: return "primary_release_date.desc"
        case .imdb: return "vote_average.desc"
        case .rottenTomatoes: return "vote_average.desc"
        }
    }
}

// MARK: - Mood Discovery View
struct MoodDiscoveryView: View {
    @State private var selectedMood: MoodOption?
    @State private var results: [MediaItem] = []
    @State private var isLoading = false
    @State private var showResults = false
    @State private var selectedItem: MediaItem?
    @State private var mediaTypeFilter: MediaType = .movie
    @State private var animateGrid = false
    
    // Filter state
    @State private var showFilterSheet = false
    @State private var activeFilter: MoodSortFilter = .mostPopular
    @State private var imdbMinRating: Double = 5.0
    @State private var rtMinPercentage: Double = 50.0
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if !showResults {
                    moodSelectionView
                } else {
                    moodResultsView
                }
            }
            .padding(.top, 12)
        }
        .navigationTitle("Mood Discovery")
        .sheet(item: $selectedItem) { item in
            MediaDetailView(item: item)
        }
        .sheet(isPresented: $showFilterSheet) {
            MoodFilterSheet(
                activeFilter: $activeFilter,
                imdbMinRating: $imdbMinRating,
                rtMinPercentage: $rtMinPercentage
            ) {
                // On apply — reload with new filter
                if let mood = selectedMood {
                    Task { await loadResults(for: mood) }
                }
            }
        }
    }
    
    // MARK: - Mood Selection Grid
    private var moodSelectionView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("How are you feeling?")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Pick your mood and we'll find the perfect match")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            
            // Media type toggle
            Picker("Type", selection: $mediaTypeFilter) {
                Text("Movies").tag(MediaType.movie)
                Text("TV Shows").tag(MediaType.tv)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Mood grid
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(MoodOption.moods) { mood in
                    MoodCard(mood: mood) {
                        selectMood(mood)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Mood Results
    private var moodResultsView: some View {
        VStack(spacing: 20) {
            // Back + mood header
            if let mood = selectedMood {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.4)) {
                            showResults = false
                            results = []
                            animateGrid = false
                            activeFilter = .mostPopular
                            imdbMinRating = 5.0
                            rtMinPercentage = 50.0
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                    
                    Text(mood.emoji)
                        .font(.title)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mood.name)
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("\(filteredResults.count) \(mediaTypeFilter == .movie ? "movies" : "shows") found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Filter button
                    Button {
                        showFilterSheet = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                            .overlay(alignment: .topTrailing) {
                                if activeFilter != .mostPopular {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 2, y: -2)
                                }
                            }
                    }
                    
                    // Shuffle button
                    Button {
                        Task { await loadResults(for: mood) }
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal)
                
                // Active filter pill
                if activeFilter != .mostPopular {
                    activeFilterPill
                }
            }
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Finding your vibe...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                // Results grid
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                ], spacing: 20) {
                    ForEach(Array(filteredResults.enumerated()), id: \.element.id) { index, item in
                        MediaPosterCard(item: item)
                            .onTapGesture {
                                selectedItem = item
                            }
                            .opacity(animateGrid ? 1 : 0)
                            .offset(y: animateGrid ? 0 : 20)
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.8)
                                    .delay(Double(index) * 0.03),
                                value: animateGrid
                            )
                    }
                }
                .padding(.horizontal)
                
                if !isLoading && filteredResults.isEmpty && !results.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.below.square.and.square.filled")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No results match your filter")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Try lowering the minimum rating")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                }
            }
        }
    }
    
    // MARK: - Active Filter Pill
    private var activeFilterPill: some View {
        HStack(spacing: 8) {
            Image(systemName: activeFilter.iconName)
                .font(.caption)
                .foregroundColor(.accentColor)
            
            Text(activeFilter.rawValue)
                .font(.caption)
                .fontWeight(.medium)
            
            if activeFilter == .imdb {
                Text("\(String(format: "%.1f", imdbMinRating))+ / 10")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if activeFilter == .rottenTomatoes {
                Text("\(Int(rtMinPercentage))%+")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button {
                activeFilter = .mostPopular
                imdbMinRating = 5.0
                rtMinPercentage = 50.0
                if let mood = selectedMood {
                    Task { await loadResults(for: mood) }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.1))
        )
        .overlay(
            Capsule()
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.horizontal)
    }
    
    // MARK: - Filtered Results
    private var filteredResults: [MediaItem] {
        switch activeFilter {
        case .imdb:
            return results.filter { item in
                let rating = item.voteAverage ?? 0
                return rating >= imdbMinRating
            }
        case .rottenTomatoes:
            // Approximate RT percentage from TMDB vote_average (0-10 scale → 0-100%)
            return results.filter { item in
                let percentage = (item.voteAverage ?? 0) * 10
                return percentage >= rtMinPercentage
            }
        case .oldest:
            return results.sorted { a, b in
                let dateA = a.displayDate ?? "9999"
                let dateB = b.displayDate ?? "9999"
                return dateA < dateB
            }
        case .newest:
            return results.sorted { a, b in
                let dateA = a.displayDate ?? "0000"
                let dateB = b.displayDate ?? "0000"
                return dateA > dateB
            }
        case .mostPopular, .trending:
            return results
        }
    }
    
    // MARK: - Actions
    private func selectMood(_ mood: MoodOption) {
        selectedMood = mood
        withAnimation(.spring(response: 0.4)) {
            showResults = true
        }
        Task { await loadResults(for: mood) }
    }
    
    private func loadResults(for mood: MoodOption) async {
        isLoading = true
        animateGrid = false
        
        // Determine sort for the API call
        let sortBy: String
        switch activeFilter {
        case .mostPopular:
            sortBy = mood.sortBy
        case .trending:
            sortBy = "popularity.desc"
        case .oldest:
            sortBy = "primary_release_date.asc"
        case .newest:
            sortBy = "primary_release_date.desc"
        case .imdb, .rottenTomatoes:
            sortBy = "vote_average.desc"
        }
        
        do {
            let page = Int.random(in: 1...3) // Add randomness
            
            if mood.name == "Nostalgia Trip" {
                // Special case: classics
                let response: TMDBResponse<MediaItem>
                if mediaTypeFilter == .movie {
                    response = try await TMDBService.shared.discoverMovies(
                        genres: nil,
                        year: nil,
                        sortBy: activeFilter == .mostPopular ? "vote_count.desc" : sortBy,
                        page: page
                    )
                } else {
                    response = try await TMDBService.shared.discoverTV(
                        genres: nil,
                        year: nil,
                        sortBy: activeFilter == .mostPopular ? "vote_count.desc" : sortBy,
                        page: page
                    )
                }
                results = activeFilter == .oldest || activeFilter == .newest ? response.results : response.results.shuffled()
            } else {
                let response: TMDBResponse<MediaItem>
                if mediaTypeFilter == .movie {
                    response = try await TMDBService.shared.discoverMovies(
                        genres: mood.genreIds.isEmpty ? nil : mood.genreIds,
                        year: nil,
                        sortBy: sortBy,
                        page: page
                    )
                } else {
                    response = try await TMDBService.shared.discoverTV(
                        genres: mood.genreIds.isEmpty ? nil : mood.genreIds,
                        year: nil,
                        sortBy: sortBy,
                        page: page
                    )
                }
                results = activeFilter == .oldest || activeFilter == .newest ? response.results : response.results.shuffled()
            }
        } catch {
            print("Mood discovery error: \(error)")
            results = []
        }
        
        isLoading = false
        withAnimation {
            animateGrid = true
        }
    }
}

// MARK: - Mood Filter Sheet
struct MoodFilterSheet: View {
    @Binding var activeFilter: MoodSortFilter
    @Binding var imdbMinRating: Double
    @Binding var rtMinPercentage: Double
    let onApply: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var localFilter: MoodSortFilter
    @State private var localIMDb: Double
    @State private var localRT: Double
    
    init(activeFilter: Binding<MoodSortFilter>, imdbMinRating: Binding<Double>, rtMinPercentage: Binding<Double>, onApply: @escaping () -> Void) {
        self._activeFilter = activeFilter
        self._imdbMinRating = imdbMinRating
        self._rtMinPercentage = rtMinPercentage
        self.onApply = onApply
        self._localFilter = State(initialValue: activeFilter.wrappedValue)
        self._localIMDb = State(initialValue: imdbMinRating.wrappedValue)
        self._localRT = State(initialValue: rtMinPercentage.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Sort/Filter Options
                Section {
                    ForEach(MoodSortFilter.allCases) { filter in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                localFilter = filter
                            }
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(localFilter == filter ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                                        .frame(width: 36, height: 36)
                                    
                                    Image(systemName: filter.iconName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(localFilter == filter ? .accentColor : .secondary)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(filter.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    Text(filterDescription(for: filter))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if localFilter == filter {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                        .listRowBackground(
                            localFilter == filter
                            ? Color.accentColor.opacity(0.06)
                            : Color.clear
                        )
                    }
                } header: {
                    Text("Sort & Filter")
                }
                
                // IMDb Rating Slider
                if localFilter == .imdb {
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text("Minimum IMDb Rating")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(String(format: "%.1f", localIMDb))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.accentColor)
                                    .monospacedDigit()
                                Text("/ 10")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $localIMDb, in: 1...10, step: 0.5) {
                                Text("IMDb Rating")
                            } minimumValueLabel: {
                                Text("1")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("10")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .tint(.yellow)
                            
                            // Rating reference labels
                            HStack {
                                ratingRefLabel("Bad", value: "1-3")
                                Spacer()
                                ratingRefLabel("Average", value: "5-6")
                                Spacer()
                                ratingRefLabel("Great", value: "8+")
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("IMDb Rating Filter")
                    } footer: {
                        Text("Only show titles rated \(String(format: "%.1f", localIMDb)) and above on IMDb's 10-point scale")
                    }
                }
                
                // Rotten Tomatoes Percentage Slider
                if localFilter == .rottenTomatoes {
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "percent")
                                    .foregroundColor(.red)
                                Text("Minimum Tomatometer")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(localRT))")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                                    .monospacedDigit()
                                Text("%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $localRT, in: 0...100, step: 5) {
                                Text("Rotten Tomatoes")
                            } minimumValueLabel: {
                                Text("0%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Text("100%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .tint(.red)
                            
                            // Freshness reference labels
                            HStack {
                                freshnessLabel("Rotten", range: "0-59%", color: .green)
                                Spacer()
                                freshnessLabel("Fresh", range: "60-74%", color: .red)
                                Spacer()
                                freshnessLabel("Certified", range: "75%+", color: .red)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Rotten Tomatoes Filter")
                    } footer: {
                        Text("Only show titles with a Tomatometer score of \(Int(localRT))% and above")
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        activeFilter = localFilter
                        imdbMinRating = localIMDb
                        rtMinPercentage = localRT
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func filterDescription(for filter: MoodSortFilter) -> String {
        switch filter {
        case .mostPopular: return "Sort by overall popularity"
        case .trending: return "What's hot right now"
        case .oldest: return "Earliest release date first"
        case .newest: return "Latest release date first"
        case .imdb: return "Filter by IMDb rating"
        case .rottenTomatoes: return "Filter by Tomatometer score"
        }
    }
    
    private func ratingRefLabel(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
    
    private func freshnessLabel(_ label: String, range: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            Text(range)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
}

// MARK: - Mood Card
struct MoodCard: View {
    let mood: MoodOption
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(mood.emoji)
                    .font(.system(size: 32))
                
                Text(mood.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Text(mood.subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(mood.color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(mood.color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

#Preview {
    NavigationStack {
        MoodDiscoveryView()
    }
}
