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

// MARK: - Mood Discovery View
struct MoodDiscoveryView: View {
    @State private var selectedMood: MoodOption?
    @State private var results: [MediaItem] = []
    @State private var isLoading = false
    @State private var showResults = false
    @State private var selectedItem: MediaItem?
    @State private var mediaTypeFilter: MediaType = .movie
    @State private var animateGrid = false
    
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
                        Text("\(results.count) \(mediaTypeFilter == .movie ? "movies" : "shows") found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
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
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
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
            }
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
        
        do {
            let page = Int.random(in: 1...3) // Add randomness
            
            if mood.name == "Nostalgia Trip" {
                // Special case: classics from 1970-2005
                let response: TMDBResponse<MediaItem>
                if mediaTypeFilter == .movie {
                    response = try await TMDBService.shared.discoverMovies(
                        genres: nil,
                        year: nil,
                        sortBy: "vote_count.desc",
                        page: page
                    )
                } else {
                    response = try await TMDBService.shared.discoverTV(
                        genres: nil,
                        year: nil,
                        sortBy: "vote_count.desc",
                        page: page
                    )
                }
                results = response.results.shuffled()
            } else {
                let response: TMDBResponse<MediaItem>
                if mediaTypeFilter == .movie {
                    response = try await TMDBService.shared.discoverMovies(
                        genres: mood.genreIds.isEmpty ? nil : mood.genreIds,
                        year: nil,
                        sortBy: mood.sortBy,
                        page: page
                    )
                } else {
                    response = try await TMDBService.shared.discoverTV(
                        genres: mood.genreIds.isEmpty ? nil : mood.genreIds,
                        year: nil,
                        sortBy: mood.sortBy,
                        page: page
                    )
                }
                results = response.results.shuffled()
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
