//
//  SearchView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @ObservedObject private var storage = StorageService.shared
    @Binding var selectedItem: MediaItem?
    @FocusState private var isSearchFocused: Bool
    
    @State private var isSyncingUpload = false
    @State private var isSyncingDownload = false
    @State private var syncAlert: (title: String, message: String)?
    
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Download from cloud
                Button {
                    Task {
                        await handleDownloadFromCloud()
                    }
                } label: {
                    if isSyncingDownload {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .help("Download from Cloud")
                .disabled(isSyncingDownload || isSyncingUpload)

                // Upload to cloud
                Button {
                    Task {
                        await handleUploadToCloud()
                    }
                } label: {
                    if isSyncingUpload {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle")
                    }
                }
                .help("Upload to Cloud")
                .disabled(isSyncingDownload || isSyncingUpload)
            }
        }
        .alert(syncAlert?.title ?? "", isPresented: Binding(get: { syncAlert != nil }, set: { if !$0 { syncAlert = nil } })) {
            Button("OK", role: .cancel) { syncAlert = nil }
        } message: {
            Text(syncAlert?.message ?? "")
        }
        .task {
            await viewModel.loadGenres()
        }
    }
    
    // MARK: - Manual Sync Actions
    private func handleUploadToCloud() async {
        if isSyncingUpload || isSyncingDownload { return }
        await MainActor.run { isSyncingUpload = true }
        await storage.uploadToCloud()
        await MainActor.run {
            if let error = storage.lastSyncError, !error.isEmpty {
                syncAlert = ("Upload Failed", error)
            } else {
                syncAlert = ("Upload Complete", "Your lists have been uploaded to the cloud.")
            }
        }
        await MainActor.run { isSyncingUpload = false }
    }

    private func handleDownloadFromCloud() async {
        if isSyncingUpload || isSyncingDownload { return }
        await MainActor.run { isSyncingDownload = true }
        await storage.downloadFromCloud()
        await MainActor.run {
            if let error = storage.lastSyncError, !error.isEmpty {
                syncAlert = ("Download Failed", error)
            } else {
                syncAlert = ("Download Complete", "Your lists have been downloaded from the cloud.")
            }
        }
        await MainActor.run { isSyncingDownload = false }
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

// MARK: - Popular TMDB Collection
struct PopularTMDBCollection: Identifiable {
    let id: Int
    let title: String
    let posterPath: String?
    let backdropPath: String?
    
    // Well-known TMDB collection IDs
    static let popular: [PopularTMDBCollection] = [
        PopularTMDBCollection(id: 529892, title: "Marvel Cinematic Universe", posterPath: "/coiGBvhSMO1ELWbOBnOtvlBSEbH.jpg", backdropPath: "/zuW6fOiusv4X9nnW3paHGfXcSll.jpg"),
        PopularTMDBCollection(id: 1241, title: "Harry Potter", posterPath: "/x8N3yjWAoQQGbAPiZi6AjDqzqJo.jpg", backdropPath: "/bLJTjfbR1syo2VIalJtnCuE0rWp.jpg"),
        PopularTMDBCollection(id: 10, title: "Star Wars", posterPath: "/r8Ph5MYXL04Qzu4QBbq2KjqwtkQ.jpg", backdropPath: "/d8duYyyC9J5T825Hg7grmaabfxQ.jpg"),
        PopularTMDBCollection(id: 328, title: "Jurassic Park", posterPath: "/jcUXVtJ6s0NG0EaxllQCAUtXAaT.jpg", backdropPath: "/yg3TSwGh7VKfYmsMYAmNLENwLSS.jpg"),
        PopularTMDBCollection(id: 86311, title: "The Avengers", posterPath: "/yFSIUVTCvgYrpalUktulvk3Gi5Y.jpg", backdropPath: "/zuW6fOiusv4X9nnW3paHGfXcSll.jpg"),
        PopularTMDBCollection(id: 748, title: "X-Men", posterPath: "/bSMLMxEHCnOrbxPYjeMPSHTChmu.jpg", backdropPath: "/8bcoRX3hQRHufLPSDREdvr3YMXx.jpg"),
        PopularTMDBCollection(id: 9485, title: "The Fast and the Furious", posterPath: "/z4ROnCrL77ZMzT0MsNXY5j25wS2.jpg", backdropPath: "/zIYROHKhGAYaYnEPRRpKaFGME3y.jpg"),
        PopularTMDBCollection(id: 87359, title: "Mission: Impossible", posterPath: "/geHHOyFnEVBqfJhPZbOBDjNJJfS.jpg", backdropPath: "/hML8WPREd4KjwLSsT9gfYZBBJlm.jpg"),
        PopularTMDBCollection(id: 2150, title: "Shrek", posterPath: "/gBkbSDJMJMXEGbEsOka3CiEfbzL.jpg", backdropPath: "/gEN2pYR4kUCHSNT7dMgY0UsLjjU.jpg"),
        PopularTMDBCollection(id: 84, title: "Indiana Jones", posterPath: "/2gkTn4MxaEiQnFXbXXIMBG8oEBp.jpg", backdropPath: "/6TnS7sCi2GjOVXJ4HdR3aD5GpV6.jpg"),
        PopularTMDBCollection(id: 119, title: "Lord of the Rings", posterPath: "/oENY593nKRVL2PnxXsMtlh8izb4.jpg", backdropPath: "/bccR2CGKNN4EjnXMOmGQJpwi89V.jpg"),
        PopularTMDBCollection(id: 263, title: "The Dark Knight", posterPath: "/qfevOTIJfiyBe3BNnX6WdOJFwWF.jpg", backdropPath: "/bvYjhsbxOBwpm8xLE5BhdA3a8CZ.jpg"),
    ]
}

// MARK: - Search Suggestions View
struct SearchSuggestionsView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onSelect: (String) -> Void
    
    @State private var selectedCollectionId: Int?
    @State private var showCollectionSheet = false
    
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
                
                // Popular Collections (TMDB)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Popular Collections")
                        .font(.headline)
                    
                    let columns = [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ]
                    
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(PopularTMDBCollection.popular) { collection in
                            Button {
                                selectedCollectionId = collection.id
                                showCollectionSheet = true
                            } label: {
                                TMDBCollectionTile(collection: collection)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showCollectionSheet) {
            if let collectionId = selectedCollectionId {
                TMDBCollectionSheet(collectionId: collectionId)
            }
        }
    }
}

// MARK: - TMDB Collection Tile
struct TMDBCollectionTile: View {
    let collection: PopularTMDBCollection
    @State private var isPressed = false
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image
            AsyncImage(url: TMDBService.shared.imageURL(path: collection.backdropPath, size: .backdropSmall)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .empty:
                    Color(.systemGray5)
                        .overlay(ProgressView())
                case .failure:
                    Color(.systemGray5)
                @unknown default:
                    Color(.systemGray5)
                }
            }
            .frame(height: 100)
            .clipped()
            
            // Gradient overlay
            LinearGradient(
                colors: [.black.opacity(0.75), .black.opacity(0.1)],
                startPoint: .bottom,
                endPoint: .top
            )
            
            // Title
            Text(collection.title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(2)
                .padding(10)
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - TMDB Collection Sheet
struct TMDBCollectionSheet: View {
    let collectionId: Int
    
    @Environment(\.dismiss) private var dismiss
    @State private var collectionDetails: CollectionDetails?
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedItem: MediaItem?
    
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Spacer()
                    }
                } else if let error = error {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text("Failed to load collection")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                } else if let details = collectionDetails {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Collection backdrop header
                            if details.backdropPath != nil {
                                AsyncImage(url: TMDBService.shared.imageURL(path: details.backdropPath, size: .backdrop)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(height: 180)
                                            .clipped()
                                    default:
                                        EmptyView()
                                    }
                                }
                            }
                            
                            // Overview
                            if let overview = details.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                            }
                            
                            // Movies grid
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(details.parts.sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }) { item in
                                    MediaPosterCard(item: item)
                                        .onTapGesture {
                                            selectedItem = item
                                        }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle(collectionDetails?.name ?? "Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedItem) { item in
                MediaDetailView(item: item)
            }
            .task {
                await loadCollection()
            }
        }
    }
    
    private func loadCollection() async {
        isLoading = true
        error = nil
        
        do {
            collectionDetails = try await TMDBService.shared.getCollectionDetails(id: collectionId)
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
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

// MARK: - SavedMediaItem -> MediaItem conversion
extension SavedMediaItem {
    func toMediaItem() -> MediaItem {
        let mediaTypeString = self.mediaType.rawValue

        return MediaItem(
            id: self.mediaId,
            title: mediaTypeString == "movie" ? self.title : nil,
            name: mediaTypeString == "tv" ? self.title : nil,
            originalTitle: nil,
            originalName: nil,
            overview: self.overview,
            posterPath: self.posterPath,
            backdropPath: self.backdropPath,
            releaseDate: mediaTypeString == "movie" ? self.year : nil,
            firstAirDate: mediaTypeString == "tv" ? self.year : nil,
            voteAverage: self.voteAverage,
            voteCount: nil,
            popularity: nil,
            genreIds: nil,
            mediaType: mediaTypeString,
            adult: false,
            originalLanguage: nil
        )
    }
}
