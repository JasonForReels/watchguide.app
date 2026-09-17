//
//  MoodDiscoveryView.swift
//  WatchGuide-MovieandTVtracker
//
//  Mood-based discovery: pick your vibe, get curated results
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Mood Model

/// TMDB keyword IDs, grouped by the mood they express. Keywords carry tone in a
/// way genres can't — "Cozy Night In" is not a genre, it's `small town` +
/// `slice of life`. Every ID below was verified against the live API for result
/// volume; TMDB's keyword vocabulary is user-submitted and has a long tail of
/// near-empty duplicates, so prefer established IDs over newly minted ones.
private enum MoodKeyword {
    static let friendship = 6054
    static let hope = 3929
    static let feelgood = 275276

    static let suspense = 288394
    static let survival = 10349
    static let raceAgainstTime = 4776
    static let catAndMouse = 15076

    static let psychologicalThriller = 12565
    static let dystopia = 4565
    static let timeLoop = 10854
    static let plotTwist = 275311

    static let smallTown = 1415
    static let sliceOfLife = 9914

    static let magic = 2343
    static let mythology = 2035
    static let hero = 1701
    static let swordAndSorcery = 234213

    static let satire = 8201
    static let parody = 9755
    static let slapstick = 9253
    static let buddyComedy = 167541

    static let neoNoir = 207268
    static let filmNoir = 9807
    static let organizedCrime = 10291
    static let corruption = 417

    static let grief = 9872
    static let tragedy = 10614
    static let terminalIllness = 6564
    static let tearjerker = 156924

    static let supernatural = 6152
    static let ghost = 162846
    static let hauntedHouse = 3358
    static let monster = 1299

    static let eighties = 208289
    static let nineties = 210608
    static let nostalgia = 5609
    static let comingOfAge = 10683

    static let love = 9673
    static let romance = 9840
    static let loveTriangle = 128
    static let wedding = 13027

    static let childrensBook = 15101
}

/// TMDB genre IDs. Movies and TV use *different* vocabularies — TV has no
/// Thriller, Horror, Sci-Fi, Adventure, Fantasy, or Romance genre, folding them
/// into Action & Adventure / Sci-Fi & Fantasy / Soap. Passing a movie genre ID
/// to `/discover/tv` silently matches nothing, so moods carry both sets.
private enum MovieGenre {
    static let action = 28, adventure = 12, animation = 16, comedy = 35
    static let crime = 80, drama = 18, family = 10751, fantasy = 14
    static let horror = 27, mystery = 9648, romance = 10749
    static let sciFi = 878, thriller = 53
}

private enum TVGenre {
    static let actionAdventure = 10759, animation = 16, comedy = 35
    static let crime = 80, drama = 18, family = 10751, kids = 10762
    static let mystery = 9648, sciFiFantasy = 10765, soap = 10766
}

struct MoodOption: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let subtitle: String
    let genreIds: [Int]       // TMDB movie genre IDs
    let tvGenreIds: [Int]     // TMDB TV genre IDs (different vocabulary — see TVGenre)
    let keywords: [Int]       // TMDB keyword IDs, OR-matched to widen rather than narrow
    /// Latest release year to include. Only "Nostalgia Trip" sets this — keywords
    /// alone match films *about* the past (Joker, Spider-Man) rather than films
    /// *from* it, which isn't what "Classics & retro favorites" promises.
    var maxYear: Int? = nil
    let sortBy: String
    let color: Color

    /// Genre IDs for the media type being browsed.
    func genreIds(for mediaType: MediaType) -> [Int] {
        mediaType == .tv ? tvGenreIds : genreIds
    }

    static let moods: [MoodOption] = [
        MoodOption(
            name: "Feel-Good", emoji: "☀️", subtitle: "Uplifting & heartwarming",
            genreIds: [MovieGenre.comedy, MovieGenre.family],
            tvGenreIds: [TVGenre.comedy, TVGenre.family],
            keywords: [MoodKeyword.friendship, MoodKeyword.hope, MoodKeyword.feelgood],
            sortBy: "vote_average.desc", color: Color.yellow
        ),
        MoodOption(
            name: "Edge of My Seat", emoji: "🔥", subtitle: "Thrilling & intense",
            genreIds: [MovieGenre.action, MovieGenre.thriller],
            tvGenreIds: [TVGenre.actionAdventure, TVGenre.mystery],
            keywords: [MoodKeyword.suspense, MoodKeyword.survival, MoodKeyword.raceAgainstTime, MoodKeyword.catAndMouse],
            sortBy: "popularity.desc", color: Color.red
        ),
        MoodOption(
            name: "Mind-Bending", emoji: "🧠", subtitle: "Twisty & thought-provoking",
            genreIds: [MovieGenre.sciFi, MovieGenre.mystery],
            tvGenreIds: [TVGenre.sciFiFantasy, TVGenre.mystery],
            keywords: [MoodKeyword.psychologicalThriller, MoodKeyword.dystopia, MoodKeyword.timeLoop, MoodKeyword.plotTwist],
            sortBy: "vote_average.desc", color: Color.purple
        ),
        MoodOption(
            name: "Cozy Night In", emoji: "🌙", subtitle: "Relaxing & easy-going",
            genreIds: [MovieGenre.romance, MovieGenre.comedy],
            tvGenreIds: [TVGenre.comedy, TVGenre.family],
            keywords: [MoodKeyword.smallTown, MoodKeyword.sliceOfLife, MoodKeyword.feelgood, MoodKeyword.friendship],
            sortBy: "popularity.desc", color: Color.indigo
        ),
        MoodOption(
            name: "Epic Adventure", emoji: "⚔️", subtitle: "Grand scale & fantastical",
            genreIds: [MovieGenre.adventure, MovieGenre.fantasy],
            tvGenreIds: [TVGenre.actionAdventure, TVGenre.sciFiFantasy],
            keywords: [MoodKeyword.magic, MoodKeyword.mythology, MoodKeyword.hero, MoodKeyword.swordAndSorcery],
            sortBy: "popularity.desc", color: Color.teal
        ),
        MoodOption(
            name: "Laugh Out Loud", emoji: "😂", subtitle: "Hilarious comedies",
            genreIds: [MovieGenre.comedy],
            tvGenreIds: [TVGenre.comedy],
            keywords: [MoodKeyword.satire, MoodKeyword.parody, MoodKeyword.slapstick, MoodKeyword.buddyComedy],
            sortBy: "popularity.desc", color: Color.orange
        ),
        MoodOption(
            name: "Dark & Gritty",
            emoji: "🌑",
            subtitle: "Noir, crime & suspense",
            genreIds: [MovieGenre.crime, MovieGenre.thriller],
            tvGenreIds: [TVGenre.crime, TVGenre.mystery],
            keywords: [MoodKeyword.neoNoir, MoodKeyword.filmNoir, MoodKeyword.organizedCrime, MoodKeyword.corruption],
            sortBy: "vote_average.desc",
            color: {
                #if os(tvOS)
                return Color.gray
                #elseif canImport(UIKit)
                return Color(UIColor.systemGray)
                #else
                return Color.gray
                #endif
            }()
        ),
        MoodOption(
            name: "Cry It Out", emoji: "💧", subtitle: "Emotional & moving dramas",
            genreIds: [MovieGenre.drama],
            tvGenreIds: [TVGenre.drama],
            keywords: [MoodKeyword.grief, MoodKeyword.tragedy, MoodKeyword.terminalIllness, MoodKeyword.tearjerker],
            sortBy: "vote_average.desc", color: Color.blue
        ),
        MoodOption(
            name: "Spooky",
            emoji: "👻",
            subtitle: "Scary & unsettling",
            genreIds: [MovieGenre.horror],
            // TV has no Horror genre — the keywords carry this mood on the TV side.
            tvGenreIds: [TVGenre.mystery, TVGenre.sciFiFantasy],
            keywords: [MoodKeyword.supernatural, MoodKeyword.ghost, MoodKeyword.hauntedHouse, MoodKeyword.monster],
            sortBy: "popularity.desc",
            color: {
                #if os(tvOS)
                return Color(white: 0.7)
                #elseif canImport(UIKit)
                return Color(UIColor.systemGray2)
                #else
                return Color(white: 0.7)
                #endif
            }()
        ),
        MoodOption(
            name: "Nostalgia Trip", emoji: "📼", subtitle: "Classics & retro favorites",
            genreIds: [], tvGenreIds: [],
            keywords: [MoodKeyword.eighties, MoodKeyword.nineties, MoodKeyword.nostalgia, MoodKeyword.comingOfAge],
            maxYear: 2005,
            sortBy: "vote_count.desc", color: Color.brown
        ),
        MoodOption(
            name: "Date Night", emoji: "❤️", subtitle: "Romantic & charming",
            genreIds: [MovieGenre.romance],
            tvGenreIds: [TVGenre.soap, TVGenre.comedy],
            keywords: [MoodKeyword.love, MoodKeyword.romance, MoodKeyword.loveTriangle, MoodKeyword.wedding],
            sortBy: "popularity.desc", color: Color.pink
        ),
        MoodOption(
            name: "Family Time", emoji: "🏠", subtitle: "Fun for all ages",
            genreIds: [MovieGenre.animation, MovieGenre.family],
            tvGenreIds: [TVGenre.animation, TVGenre.family, TVGenre.kids],
            keywords: [MoodKeyword.childrensBook, MoodKeyword.friendship, MoodKeyword.magic],
            sortBy: "popularity.desc", color: Color.green
        ),
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
        .mediaDetailPresentation(item: $selectedItem)
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
        
        // Determine sort for the API call. The date sort field differs by media
        // type — /discover/tv rejects `primary_release_date` and wants
        // `first_air_date` — so pick the one the endpoint understands.
        let dateSortField = mediaTypeFilter == .tv ? "first_air_date" : "primary_release_date"
        let sortBy: String
        switch activeFilter {
        case .mostPopular:
            sortBy = mood.sortBy
        case .trending:
            sortBy = "popularity.desc"
        case .oldest:
            sortBy = "\(dateSortField).asc"
        case .newest:
            sortBy = "\(dateSortField).desc"
        case .imdb, .rottenTomatoes:
            sortBy = "vote_average.desc"
        }
        
        do {
            let page = Int.random(in: 1...3) // Add randomness

            // Genres and keywords are OR-matched within themselves and AND-matched
            // against each other, so a mood reads as "any of these genres, and at
            // least one of these keywords" — wide enough to fill a grid, specific
            // enough to feel like the mood.
            let genres = mood.genreIds(for: mediaTypeFilter)
            let response: TMDBResponse<MediaItem>
            if mediaTypeFilter == .movie {
                response = try await TMDBService.shared.discoverMovies(
                    genres: genres.isEmpty ? nil : genres,
                    year: nil,
                    keywords: mood.keywords.isEmpty ? nil : mood.keywords,
                    matchAnyGenre: true,
                    releasedBefore: mood.maxYear,
                    sortBy: sortBy,
                    page: page
                )
            } else {
                response = try await TMDBService.shared.discoverTV(
                    genres: genres.isEmpty ? nil : genres,
                    year: nil,
                    keywords: mood.keywords.isEmpty ? nil : mood.keywords,
                    matchAnyGenre: true,
                    releasedBefore: mood.maxYear,
                    sortBy: sortBy,
                    page: page
                )
            }
            results = activeFilter == .oldest || activeFilter == .newest ? response.results : response.results.shuffled()
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
                sortAndFilterSection

                if localFilter == .imdb {
                    imdbFilterSection
                }

                if localFilter == .rottenTomatoes {
                    rottenTomatoesFilterSection
                }
            }
            .navigationTitle("Filters")
            #if !os(macOS)
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #endif
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

    private var sortAndFilterSection: some View {
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
                                .fill(localFilter == filter ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.2))
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
    }

    private var imdbFilterSection: some View {
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

                imdbRatingControl

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

    private var rottenTomatoesFilterSection: some View {
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

                rottenTomatoesControl

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

    @ViewBuilder
    private var imdbRatingControl: some View {
        #if os(tvOS)
        Picker("IMDb Rating", selection: $localIMDb) {
            ForEach(stride(from: 1.0, through: 10.0, by: 0.5).map { Double($0) }, id: \.self) { option in
                Text(String(format: "%.1f", option)).tag(option)
            }
        }
        #else
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
        #endif
    }

    @ViewBuilder
    private var rottenTomatoesControl: some View {
        #if os(tvOS)
        Picker("Rotten Tomatoes", selection: $localRT) {
            ForEach(Array(stride(from: 0, through: 100, by: 5)), id: \.self) { option in
                Text("\(option)%").tag(Double(option))
            }
        }
        #else
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
        #endif
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
