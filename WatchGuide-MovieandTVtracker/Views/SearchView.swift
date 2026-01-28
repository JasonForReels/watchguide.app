//
//  SearchView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @Binding var selectedItem: MediaItem?
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search movies, TV shows, people...", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        Task {
                            await viewModel.search()
                        }
                    }
                
                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding()
            
            // Filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    FilterChip(
                        title: "All",
                        isSelected: viewModel.selectedType == nil,
                        action: { viewModel.selectedType = nil }
                    )
                    
                    FilterChip(
                        title: "Movies",
                        isSelected: viewModel.selectedType == .movie,
                        action: { viewModel.selectedType = .movie }
                    )
                    
                    FilterChip(
                        title: "TV Shows",
                        isSelected: viewModel.selectedType == .tv,
                        action: { viewModel.selectedType = .tv }
                    )
                    
                    FilterChip(
                        title: "People",
                        isSelected: viewModel.selectedType == .person,
                        action: { viewModel.selectedType = .person }
                    )
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Genre filter
                    Menu {
                        Button("All Genres") {
                            viewModel.selectedGenre = nil
                        }
                        Divider()
                        ForEach(viewModel.genres, id: \.id) { genre in
                            Button(genre.name) {
                                viewModel.selectedGenre = genre
                            }
                        }
                    } label: {
                        FilterChip(
                            title: viewModel.selectedGenre?.name ?? "Genre",
                            isSelected: viewModel.selectedGenre != nil,
                            showChevron: true
                        )
                    }
                    
                    // Year filter
                    Menu {
                        Button("Any Year") {
                            viewModel.selectedYear = nil
                        }
                        Divider()
                        ForEach((1970...2025).reversed(), id: \.self) { year in
                            Button("\(year)") {
                                viewModel.selectedYear = year
                            }
                        }
                    } label: {
                        FilterChip(
                            title: viewModel.selectedYear != nil ? "\(viewModel.selectedYear!)" : "Year",
                            isSelected: viewModel.selectedYear != nil,
                            showChevron: true
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
            
            Divider()
            
            // Content
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Spacer()
            } else if viewModel.hasSearched && viewModel.results.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .font(.headline)
                    Text("Try different keywords or filters")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if viewModel.results.isEmpty {
                // Show search history and suggestions
                SearchSuggestionsView(
                    viewModel: viewModel,
                    onSelect: { query in
                        viewModel.query = query
                        Task {
                            await viewModel.search()
                        }
                    }
                )
            } else {
                // Results grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                    ], spacing: 20) {
                        ForEach(viewModel.results) { item in
                            MediaPosterCard(item: item)
                                .onTapGesture {
                                    selectedItem = item
                                    StorageService.shared.addSearchHistory(viewModel.query)
                                }
                        }
                    }
                    .padding()
                    
                    // Load more
                    if viewModel.hasMorePages {
                        Button {
                            Task {
                                await viewModel.loadMore()
                            }
                        } label: {
                            if viewModel.isLoadingMore {
                                ProgressView()
                            } else {
                                Text("Load More")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .task {
            await viewModel.loadGenres()
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var showChevron: Bool = false
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
            
            if showChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color(.systemGray5))
        .foregroundColor(isSelected ? .white : .primary)
        .cornerRadius(20)
        .onTapGesture {
            action?()
        }
    }
}

// MARK: - Search Suggestions View
struct SearchSuggestionsView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onSelect: (String) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Recent searches
                if !StorageService.shared.searchHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Searches")
                                .font(.headline)
                            Spacer()
                            Button("Clear") {
                                StorageService.shared.clearSearchHistory()
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        FlowLayout(spacing: 8) {
                            ForEach(StorageService.shared.searchHistory.prefix(10)) { item in
                                Button {
                                    onSelect(item.query)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "clock")
                                            .font(.caption)
                                        Text(item.query)
                                            .font(.subheadline)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(16)
                                }
                                .foregroundColor(.primary)
                            }
                        }
                    }
                }
                
                // Trending searches
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trending")
                        .font(.headline)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(["Dune", "The Last of Us", "Oppenheimer", "Breaking Bad", "The Batman", "Succession", "Avatar", "Stranger Things"], id: \.self) { term in
                            Button {
                                onSelect(term)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "flame.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    Text(term)
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray5))
                                .cornerRadius(16)
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + maxHeight)
        }
    }
}

// MARK: - Search View Model
@MainActor
class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [MediaItem] = []
    @Published var selectedType: MediaType?
    @Published var selectedGenre: Genre?
    @Published var selectedYear: Int?
    @Published var genres: [Genre] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasSearched = false
    @Published var currentPage = 1
    @Published var totalPages = 1
    
    var hasMorePages: Bool {
        currentPage < totalPages
    }
    
    func loadGenres() async {
        do {
            let movieGenres = try await TMDBService.shared.getMovieGenres()
            let tvGenres = try await TMDBService.shared.getTVGenres()
            
            // Merge and dedupe
            var allGenres = movieGenres.genres
            for genre in tvGenres.genres {
                if !allGenres.contains(where: { $0.id == genre.id }) {
                    allGenres.append(genre)
                }
            }
            genres = allGenres.sorted { $0.name < $1.name }
        } catch {
            print("Error loading genres: \(error)")
        }
    }
    
    func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            hasSearched = false
            return
        }
        
        isLoading = true
        hasSearched = true
        currentPage = 1
        
        do {
            if selectedGenre != nil || selectedYear != nil {
                // Use discover endpoint for filters
                await searchWithFilters()
            } else {
                // Regular search
                let response = try await TMDBService.shared.searchMulti(query: trimmedQuery)
                totalPages = response.totalPages ?? 1
                results = filterResults(response.results)
            }
        } catch {
            print("Search error: \(error)")
            results = []
        }
        
        isLoading = false
    }
    
    func loadMore() async {
        guard hasMorePages && !isLoadingMore else { return }
        
        isLoadingMore = true
        currentPage += 1
        
        do {
            let response = try await TMDBService.shared.searchMulti(query: query, page: currentPage)
            results.append(contentsOf: filterResults(response.results))
        } catch {
            print("Load more error: \(error)")
            currentPage -= 1
        }
        
        isLoadingMore = false
    }
    
    private func searchWithFilters() async {
        do {
            let genreIds = selectedGenre != nil ? [selectedGenre!.id] : nil
            
            if selectedType == .movie || selectedType == nil {
                let movies = try await TMDBService.shared.discoverMovies(genres: genreIds, year: selectedYear)
                results = movies.results
                totalPages = movies.totalPages ?? 1
            }
            
            if selectedType == .tv {
                let shows = try await TMDBService.shared.discoverTV(genres: genreIds, year: selectedYear)
                results = shows.results
                totalPages = shows.totalPages ?? 1
            }
        } catch {
            print("Filter search error: \(error)")
        }
    }
    
    private func filterResults(_ items: [MediaItem]) -> [MediaItem] {
        var filtered = items
        
        if let type = selectedType {
            filtered = filtered.filter { $0.resolvedMediaType == type }
        }
        
        return filtered
    }
    
    func clearSearch() {
        query = ""
        results = []
        hasSearched = false
    }
}

#Preview {
    SearchView(selectedItem: .constant(nil))
}
