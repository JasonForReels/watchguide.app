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
            // Scout AI Banner
            ScoutPromoBanner()
            
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
                    
                    // Hide People filter for kids profiles
                    if !StorageService.shared.settings.isKidsProfile {
                        FilterChip(
                            title: "People",
                            isSelected: viewModel.selectedType == .person,
                            action: { viewModel.selectedType = .person }
                        )
                    }
                    
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
struct PopularTMDBCollection: Identifiable, Hashable {
    let id: Int
    let title: String
    let posterPath: String?
    let backdropPath: String?
    /// If true, `id` is a TMDB *list* ID fetched via /list/{id} instead of /collection/{id}
    let isList: Bool
    /// Full URL for the tile backdrop (overrides backdropPath when set)
    let customBackdropURL: String?
    /// MDBList list ID; when set the collection is fetched from MDBList instead of TMDB
    let mdblistId: String?
    
    init(id: Int, title: String, posterPath: String?, backdropPath: String?, isList: Bool = false, customBackdropURL: String? = nil, mdblistId: String? = nil) {
        self.id = id
        self.title = title
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.isList = isList
        self.customBackdropURL = customBackdropURL
        self.mdblistId = mdblistId
    }
    
    /// Resolved URL for the tile backdrop image
    var tileBackdropURL: URL? {
        if let custom = customBackdropURL, let url = URL(string: custom) {
            return url
        }
        return TMDBService.shared.imageURL(path: backdropPath, size: .backdropSmall)
    }
    
    // Well-known TMDB collection / list IDs
    static let popular: [PopularTMDBCollection] = [
        PopularTMDBCollection(id: 0, title: "Marvel", posterPath: nil, backdropPath: nil, isList: false, customBackdropURL: "https://i.postimg.cc/2SvGNf7s/uwp4669808.webp", mdblistId: "dualipafan01/marvel"),
        PopularTMDBCollection(id: 1241, title: "Harry Potter", posterPath: "/x8N3yjWAoQQGbAPiZi6AjDqzqJo.jpg", backdropPath: "/bLJTjfbR1syo2VIalJtnCuE0rWp.jpg"),
        PopularTMDBCollection(id: 10, title: "Star Wars", posterPath: "/r8Ph5MYXL04Qzu4QBbq2KjqwtkQ.jpg", backdropPath: "/d8duYyyC9J5T825Hg7grmaabfxQ.jpg"),
        PopularTMDBCollection(id: 328, title: "Jurassic Park", posterPath: "/jcUXVtJ6s0NG0EaxllQCAUtXAaT.jpg", backdropPath: "/yg3TSwGh7VKfYmsMYAmNLENwLSS.jpg"),
        PopularTMDBCollection(id: 86311, title: "The Avengers", posterPath: "/yFSIUVTCvgYrpalUktulvk3Gi5Y.jpg", backdropPath: "/zuW6fOiusv4X9nnW3paHGfXcSll.jpg"),
        PopularTMDBCollection(id: 748, title: "X-Men", posterPath: "/bSMLMxEHCnOrbxPYjeMPSHTChmu.jpg", backdropPath: nil, customBackdropURL: "https://image.tmdb.org/t/p/original/roZFGw3Rg6VOYty9y4r5WvgvXoC.jpg"),
        PopularTMDBCollection(id: 9485, title: "The Fast and the Furious", posterPath: "/z4ROnCrL77ZMzT0MsNXY5j25wS2.jpg", backdropPath: "/zIYROHKhGAYaYnEPRRpKaFGME3y.jpg"),
        PopularTMDBCollection(id: 87359, title: "Mission: Impossible", posterPath: "/geHHOyFnEVBqfJhPZbOBDjNJJfS.jpg", backdropPath: "/hML8WPREd4KjwLSsT9gfYZBBJlm.jpg"),
        PopularTMDBCollection(id: 2150, title: "Shrek", posterPath: "/gBkbSDJMJMXEGbEsOka3CiEfbzL.jpg", backdropPath: "/gEN2pYR4kUCHSNT7dMgY0UsLjjU.jpg"),
        PopularTMDBCollection(id: 84, title: "Indiana Jones", posterPath: "/2gkTn4MxaEiQnFXbXXIMBG8oEBp.jpg", backdropPath: "/6TnS7sCi2GjOVXJ4HdR3aD5GpV6.jpg"),
        PopularTMDBCollection(id: 119, title: "Lord of the Rings", posterPath: "/oENY593nKRVL2PnxXsMtlh8izb4.jpg", backdropPath: "/bccR2CGKNN4EjnXMOmGQJpwi89V.jpg"),
        PopularTMDBCollection(id: 263, title: "The Dark Knight", posterPath: "/qfevOTIJfiyBe3BNnX6WdOJFwWF.jpg", backdropPath: nil, customBackdropURL: "https://image.tmdb.org/t/p/original/xyhrCEdB4XRkelfVsqXeUZ6rLHi.jpg"),
    ]
}

// MARK: - Search Suggestions View
struct SearchSuggestionsView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onSelect: (String) -> Void
    
    private var trendingSuggestions: [String] {
        if StorageService.shared.settings.isKidsProfile {
            return ["Frozen", "Moana", "Toy Story", "Paw Patrol", "Bluey", "SpongeBob", "Encanto", "Lego Movie"]
        }
        return ["Dune", "The Last of Us", "Oppenheimer", "Breaking Bad", "The Batman", "Succession", "Avatar", "Stranger Things"]
    }
    
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
                        ForEach(trendingSuggestions, id: \.self) { term in
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

// MARK: - TMDB Collection Tile
struct TMDBCollectionTile: View {
    let collection: PopularTMDBCollection
    @State private var isPressed = false
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image
            AsyncImage(url: collection.tileBackdropURL) { phase in
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
    let collection: PopularTMDBCollection
    
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = "Collection"
    @State private var overview: String?
    @State private var backdropPath: String?
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedItem: MediaItem?
    @State private var currentPage = 1
    @State private var hasMorePages = false
    @State private var isLoadingMore = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Spacer()
                    }
                } else if let error = error, items.isEmpty {
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
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Collection backdrop header
                            if let bp = backdropPath {
                                AsyncImage(url: TMDBService.shared.imageURL(path: bp, size: .backdrop)) { phase in
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
                            if let overview = overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                            }
                            
                            // Movies grid
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(items) { item in
                                    MediaPosterCard(item: item)
                                        .onTapGesture {
                                            selectedItem = item
                                        }
                                }
                            }
                            .padding(.horizontal)
                            
                            // Load more for list-based collections
                            if hasMorePages {
                                Button {
                                    Task { await loadMorePages() }
                                } label: {
                                    if isLoadingMore {
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
            }
            .navigationTitle(title)
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
        
        if let mdblistId = collection.mdblistId {
            await loadFromMDBList(listId: mdblistId)
        } else if collection.isList {
            await loadFromList(page: 1)
        } else {
            await loadFromCollection()
        }
        
        isLoading = false
    }
    
    private func loadFromMDBList(listId: String) async {
        do {
            let savedItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: listId)
            title = collection.title
            backdropPath = nil // MDBList collections use customBackdropURL on the tile, no header backdrop needed
            items = savedItems.map { $0.toMediaItem() }
            hasMorePages = false
        } catch let loadError {
            self.error = loadError.localizedDescription
            print("MDBList load error for \(listId): \(loadError)")
        }
    }
    
    private func loadFromCollection() async {
        do {
            let details = try await TMDBService.shared.getCollectionDetails(id: collection.id)
            title = details.name
            overview = details.overview
            backdropPath = details.backdropPath
            items = details.parts.sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }
        } catch let loadError {
            self.error = loadError.localizedDescription
            print("Collection load error for id \(collection.id): \(loadError)")
        }
    }
    
    private func loadFromList(page: Int) async {
        do {
            let listResponse = try await TMDBService.shared.getListDetails(listId: collection.id, page: page)
            title = listResponse.name ?? collection.title
            overview = listResponse.description
            backdropPath = collection.backdropPath
            
            if page == 1 {
                items = listResponse.items.sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }
            } else {
                let newItems = listResponse.items.sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }
                items.append(contentsOf: newItems)
            }
            
            // TMDB lists can have many pages; if we got a full page of 20 items, assume more
            hasMorePages = listResponse.items.count >= 20
            currentPage = page
        } catch let loadError {
            if page == 1 {
                self.error = loadError.localizedDescription
            }
            print("List load error for id \(collection.id): \(loadError)")
        }
    }
    
    private func loadMorePages() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        await loadFromList(page: currentPage + 1)
        isLoadingMore = false
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
        
        // Kids profile: filter to only show family-friendly content
        if StorageService.shared.settings.isKidsProfile {
            // Kids-friendly genre IDs:
            // Movies: Animation=16, Family=10751
            // TV: Animation=16, Family=10751, Kids=10762
            let kidsGenreIds: Set<Int> = [16, 10751, 10762]
            filtered = filtered.filter { item in
                // Exclude adult-flagged content
                if item.adult == true { return false }
                // Exclude people results for kids
                if item.resolvedMediaType == .person { return false }
                // If genre info is available, require at least one kids genre
                if let genres = item.genreIds, !genres.isEmpty {
                    return !genres.filter({ kidsGenreIds.contains($0) }).isEmpty
                }
                // If no genre info, allow it through (better than hiding everything)
                return true
            }
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
