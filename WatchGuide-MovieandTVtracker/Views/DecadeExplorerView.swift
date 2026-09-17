//
//  DecadeExplorerView.swift
//  WatchGuide-MovieandTVtracker
//
//  Explore the best movies & TV by decade — a time machine for cinema
//

import SwiftUI

struct DecadeExplorerView: View {
    @State private var selectedDecade: DecadeOption?
    @State private var results: [MediaItem] = []
    @State private var isLoading = false
    @State private var selectedItem: MediaItem?
    @State private var mediaType: MediaType = .movie
    @State private var animateGrid = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if selectedDecade == nil {
                    decadeSelectionView
                } else {
                    decadeResultsView
                }
            }
            .padding(.top, 12)
        }
        .navigationTitle("Time Machine")
        .mediaDetailPresentation(item: $selectedItem)
    }
    
    // MARK: - Decade Selection
    private var decadeSelectionView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Travel Through Time")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Explore the best of every era")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Picker("Type", selection: $mediaType) {
                Text("Movies").tag(MediaType.movie)
                Text("TV Shows").tag(MediaType.tv)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(DecadeOption.decades) { decade in
                    DecadeCard(decade: decade) {
                        selectDecade(decade)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Decade Results
    private var decadeResultsView: some View {
        VStack(spacing: 20) {
            if let decade = selectedDecade {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.4)) {
                            selectedDecade = nil
                            results = []
                            animateGrid = false
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The \(decade.name)")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(decade.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 60)
            } else {
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
    private func selectDecade(_ decade: DecadeOption) {
        selectedDecade = decade
        Task { await loadDecade(decade) }
    }
    
    private func loadDecade(_ decade: DecadeOption) async {
        isLoading = true
        animateGrid = false
        
        do {
            // Use multiple years from the decade and merge results
            var allItems: [MediaItem] = []
            
            // Fetch the top-rated from the decade start year and mid-year
            for year in [decade.startYear, decade.startYear + 3, decade.startYear + 6, decade.startYear + 9] {
                if year <= 2025 {
                    let response: TMDBResponse<MediaItem>
                    if mediaType == .movie {
                        response = try await TMDBService.shared.discoverMovies(
                            genres: nil,
                            year: year,
                            sortBy: "vote_count.desc",
                            page: 1
                        )
                    } else {
                        response = try await TMDBService.shared.discoverTV(
                            genres: nil,
                            year: year,
                            sortBy: "vote_count.desc",
                            page: 1
                        )
                    }
                    allItems.append(contentsOf: response.results)
                }
            }
            
            // Deduplicate and sort by popularity
            var seen = Set<Int>()
            results = allItems.filter { item in
                if seen.contains(item.id) { return false }
                seen.insert(item.id)
                return true
            }
            .sorted { ($0.voteCount ?? 0) > ($1.voteCount ?? 0) }
            .prefix(40)
            .map { $0 }
            
        } catch {
            print("Decade explorer error: \(error)")
            results = []
        }
        
        isLoading = false
        withAnimation {
            animateGrid = true
        }
    }
}

// MARK: - Decade Option
struct DecadeOption: Identifiable {
    let id = UUID()
    let name: String
    let startYear: Int
    let description: String
    let color: Color
    
    static let decades: [DecadeOption] = [
        DecadeOption(name: "2020s", startYear: 2020, description: "Streaming era & modern cinema", color: .purple),
        DecadeOption(name: "2010s", startYear: 2010, description: "Superhero golden age & prestige TV", color: .blue),
        DecadeOption(name: "2000s", startYear: 2000, description: "CGI revolution & franchise launches", color: .teal),
        DecadeOption(name: "1990s", startYear: 1990, description: "Indie boom & cult classics", color: .green),
        DecadeOption(name: "1980s", startYear: 1980, description: "Blockbuster era & action icons", color: .orange),
        DecadeOption(name: "1970s", startYear: 1970, description: "New Hollywood & auteur filmmaking", color: .red),
        DecadeOption(name: "1960s", startYear: 1960, description: "International waves & counterculture", color: .pink),
        DecadeOption(name: "1950s", startYear: 1950, description: "Golden age epics & noir", color: .yellow),
    ]
}

// MARK: - Decade Card
struct DecadeCard: View {
    let decade: DecadeOption
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(decade.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(decade.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(decade.color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(decade.color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

#Preview {
    NavigationStack {
        DecadeExplorerView()
    }
}
