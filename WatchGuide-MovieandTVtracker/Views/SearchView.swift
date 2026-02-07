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

// MARK: - Search Suggestions View
struct SearchSuggestionsView: View {
    // MARK: - SearchCollection nested struct
    struct SearchCollection: Identifiable {
        let id: String
        let title: String
        let listId: String
        let thumbnailURL: String
        
        init(title: String, listId: String, thumbnailURL: String) {
            self.title = title
            self.listId = listId
            self.thumbnailURL = thumbnailURL
            self.id = listId
        }
    }
    
    @ObservedObject var viewModel: SearchViewModel
    let onSelect: (String) -> Void
    
    @State private var showCollectionSheet = false
    @State private var selectedCollection: SearchCollection?
    
    var collections: [SearchCollection] {
        [
            SearchCollection(
                title: "Marvel Cinematic Universe",
                listId: "kraftynic/marvel-cinematic-universe",
                thumbnailURL: "https://disney.images.edge.bamgrid.com/ripcut-delivery/v2/variant/disney/CCC3F8712F781DC1ECDDC406924EF0569A30DB0F0BF628CA9EAF60B97C9ABC4B/compose?aspectRatio=1.78&format=webp&width=1600"
            ),
            SearchCollection(
                title: "Wizarding World",
                listId: "ahasson/wizarding-world",
                thumbnailURL: "https://i.ibb.co/rRjJyvSh/wp12750397.jpg"
            ),
            SearchCollection(
                title: "Jurassic",
                listId: "andyhawks/universe-jurassic-park",
                thumbnailURL: "https://i.ibb.co/d0t640Qd/717-Pj-P13-Ax-L-AC-UF1000-1000-QL80.jpg"
            ),
            SearchCollection(
                title: "Mission: Impossible",
                listId: "nammel/mission-impossible-saga",
                thumbnailURL: "https://i.ibb.co/35hTnqNv/dg2wdje-d4656d1e-b019-44f2-81ba-849bf6171c71.jpg"
            )
        ]
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
                
                // Collections
                VStack(alignment: .leading, spacing: 12) {
                    Text("Collections")
                        .font(.headline)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(collections) { collection in
                                Button {
                                    selectedCollection = collection
                                    showCollectionSheet = true
                                } label: {
                                    ZStack(alignment: .bottom) {
                                        AsyncImage(url: URL(string: collection.thumbnailURL)) { phase in
                                            switch phase {
                                            case .empty:
                                                Color(.systemGray5)
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            case .failure:
                                                Color(.systemGray5)
                                            @unknown default:
                                                Color(.systemGray5)
                                            }
                                        }
                                        .frame(width: 280, height: 140)
                                        .clipped()
                                        .cornerRadius(12)
                                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                                        
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear]),
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                        .frame(height: 50)
                                        .cornerRadius(12)
                                        
                                        Text(collection.title)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.bottom, 8)
                                            .padding(.horizontal, 12)
                                            .frame(maxWidth: 280, alignment: .leading)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showCollectionSheet) {
            if let selectedCollection = selectedCollection {
                CollectionListSheet(collection: selectedCollection)
            }
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
// MARK: - CollectionListSheet
struct CollectionListSheet: View {
    let collection: SearchSuggestionsView.SearchCollection
    
    @Environment(\.dismiss) private var dismiss
    @State private var allItems: [SavedMediaItem] = []
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
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(allItems) { savedItem in
                                SavedMediaPosterCard(item: savedItem)
                                    .onTapGesture {
                                        selectedItem = savedItem.toMediaItem()
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(collection.title)
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
                do {
                    isLoading = true
                    error = nil
                    allItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: collection.listId)
                } catch {
                    self.error = error.localizedDescription
                    allItems = []
                }
                isLoading = false
            }
        }
    }
}

// MARK: - SavedMediaItem -> MediaItem conversion
extension SavedMediaItem {
    func toMediaItem() -> MediaItem {
        // Safely coerce id to Int if the SavedMediaItem.id is not already Int-compatible
        // If your SavedMediaItem.id is a String, try to parse it; otherwise, use 0 as a fallback.
        let coercedId: Int
        if let intId = self.id as? Int {
            coercedId = intId
        } else if let stringId = self.id as? String, let parsed = Int(stringId) {
            coercedId = parsed
        } else {
            // If id is some other type, provide a stable fallback
            coercedId = 0
        }

        // Determine media type string if available; otherwise default to "movie"
        // Adjust `mediaType` property name if your SavedMediaItem uses a different one.
        let mediaTypeString: String = {
            if let mt = (self as AnyObject).value(forKey: "mediaType") as? String {
                return mt
            }
            return "movie"
        }()

        // Map a single stored date to releaseDate/firstAirDate depending on media type if possible.
        // Tries common property names via KVC without hard dependency on model shape.
        let storedDate: String? = {
            // Try common keys
            let keys = ["releaseDate", "firstAirDate", "date"]
            for key in keys {
                if let value = (self as AnyObject).value(forKey: key) as? String, !value.isEmpty {
                    return value
                }
            }
            return nil
        }()

        // Decide where to place the date depending on media type
        let releaseDate: String? = mediaTypeString == "tv" ? nil : storedDate
        let firstAirDate: String? = mediaTypeString == "tv" ? storedDate : nil

        return MediaItem(
            id: coercedId,
            title: self.title ?? "",
            name: nil,
            originalTitle: nil,
            originalName: nil,
            overview: self.overview ?? "",
            posterPath: self.posterPath,
            backdropPath: self.backdropPath,
            releaseDate: releaseDate,
            firstAirDate: firstAirDate,
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
