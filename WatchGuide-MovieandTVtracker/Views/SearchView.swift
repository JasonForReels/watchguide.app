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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var isSyncingUpload = false
    @State private var isSyncingDownload = false
    @State private var syncAlert: (title: String, message: String)?
    @State private var selectedPerson: Person?
    @State private var trendingPopupService: StreamingServiceOption?
    @State private var useNaturalLanguageForNextSearch = false
    private let appleIntelligenceReport = AppleIntelligenceCapabilityService.currentReport()
    
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
                            await performSearch()
                        }
                    }

                if storage.settings.useAppleIntelligenceSearch && appleIntelligenceReport.isAppleIntelligenceAvailableNow {
                    Button {
                        useNaturalLanguageForNextSearch.toggle()
                    } label: {
                        Image(systemName: "apple.intelligence")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(useNaturalLanguageForNextSearch ? .accentColor : .secondary)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Siri natural language search")
                    .help("Use Siri natural language search for next query")
                }
                
                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.clearSearch()
                        useNaturalLanguageForNextSearch = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.12))
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
                    
                    // Hide genre/year filters when People is selected (not applicable)
                    if viewModel.selectedType != .person {
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
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)

            if !viewModel.streamingServices.isEmpty {
                StreamingServiceFilterSection(
                    services: viewModel.streamingServices,
                    selectedServiceIds: viewModel.selectedStreamingServiceIds,
                    onToggle: { service in
                        Task {
                            await viewModel.toggleStreamingService(service)
                        }
                    },
                    onTrendingTap: { service in
                        trendingPopupService = service
                    }
                )
                .padding(.bottom, 8)
            }
            
            Divider()
            
            // Content
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Spacer()
            } else if viewModel.hasSearched && viewModel.isEmptyResults {
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
            } else if !viewModel.hasSearched && viewModel.isEmptyResults {
                // Show search history and suggestions
                SearchSuggestionsView(
                    viewModel: viewModel,
                    onSelect: { query in
                        viewModel.query = query
                        Task {
                            await performSearch()
                        }
                    }
                )
            } else if viewModel.isPeopleSearch {
                // People results grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 20)
                    ], spacing: 24) {
                        ForEach(viewModel.personResults) { person in
                            PersonSearchCard(person: person)
                                .onTapGesture {
                                    selectedPerson = person
                                    let trimmed = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        StorageService.shared.addSearchHistory(trimmed)
                                    }
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
            } else {
                // Media results grid
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if viewModel.isStreamingMode && viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            StreamingRecommendationHeader(
                                serviceNames: viewModel.selectedStreamingServiceNames
                            )
                            .padding(.horizontal)
                        }

                        LazyVGrid(columns: [
                            GridItem(
                                .adaptive(
                                    minimum: ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass),
                                    maximum: ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass) + 30
                                ),
                                spacing: 16
                            )
                        ], spacing: 20) {
                            ForEach(viewModel.results) { item in
                                MediaPosterCard(item: item)
                                    .onTapGesture {
                                        selectedItem = item
                                        let trimmed = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmed.isEmpty {
                                            StorageService.shared.addSearchHistory(trimmed)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    
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
                    .padding(.top, 8)
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
        .sheet(item: $selectedPerson) { person in
            PersonDetailView(
                personId: person.id,
                personName: person.name,
                profilePath: person.profilePath
            )
        }
        .sheet(item: $trendingPopupService) { service in
            NetworkTrendingPopup(service: service, selectedItem: $selectedItem)
        }
        .onChange(of: viewModel.selectedType) { _, _ in
            // Re-search when filter type changes (if there's an active query)
            if viewModel.isStreamingMode && viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.applyStreamingFilters()
            } else if viewModel.hasSearched && !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task {
                    await viewModel.search(useNaturalLanguage: viewModel.usedNaturalLanguageInLastSearch)
                }
            }
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

    private func performSearch() async {
        let shouldUseNaturalLanguage = storage.settings.useAppleIntelligenceSearch && useNaturalLanguageForNextSearch
        await viewModel.search(useNaturalLanguage: shouldUseNaturalLanguage)
        useNaturalLanguageForNextSearch = false
    }
}

// MARK: - Filter Chip (Liquid Glass — iOS 26 SDK)
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
        .foregroundColor(isSelected ? .primary : .secondary)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
            }
        }
        .glassEffect(.regular, in: .capsule)
        .onTapGesture {
            action?()
        }
    }
}

// MARK: - Streaming Service Filter Section
struct StreamingServiceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let logoURL: String
    let brandColorHex: String
    let listURL: String
    /// Optional MDBList trending list URL — when set, tapping the card shows a trending popup
    let trendingListURL: String?
    
    init(id: String, name: String, logoURL: String, brandColorHex: String, listURL: String, trendingListURL: String? = nil) {
        self.id = id
        self.name = name
        self.logoURL = logoURL
        self.brandColorHex = brandColorHex
        self.listURL = listURL
        self.trendingListURL = trendingListURL
    }
}

struct StreamingServiceFilterSection: View {
    let services: [StreamingServiceOption]
    let selectedServiceIds: Set<String>
    let onToggle: (StreamingServiceOption) -> Void
    var onTrendingTap: ((StreamingServiceOption) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Networks")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(services) { service in
                        Button {
                            if service.trendingListURL != nil, let onTrendingTap {
                                onTrendingTap(service)
                            } else {
                                onToggle(service)
                            }
                        } label: {
                            StreamingServiceCard(
                                service: service,
                                isSelected: selectedServiceIds.contains(service.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct StreamingServiceCard: View {
    let service: StreamingServiceOption
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        Color(hex: service.brandColorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(backgroundColor)
                    .opacity(colorScheme == .dark ? 0.85 : 1.0)

                AsyncImage(url: URL(string: service.logoURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 26)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    case .failure:
                        Text(service.name)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    case .empty:
                        ProgressView()
                            .tint(.white)
                            .frame(height: 26)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .frame(width: 140, height: 54)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.25 : 0.12), radius: isSelected ? 8 : 4, y: 3)

            Text(service.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.gray.opacity(0.35), lineWidth: isSelected ? 2 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct StreamingRecommendationHeader: View {
    let serviceNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top 10 recommendations")
                .font(.headline)
                .fontWeight(.bold)
            if !serviceNames.isEmpty {
                Text(serviceNames.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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
                                    .background(Color.gray.opacity(0.18))
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
                                .background(Color.gray.opacity(0.18))
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
                    Color.gray.opacity(0.18)
                        .overlay(ProgressView())
                case .failure:
                    Color.gray.opacity(0.18)
                @unknown default:
                    Color.gray.opacity(0.18)
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    
    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass),
                    maximum: ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass) + 30
                ),
                spacing: 16
            )
        ]
    }
    
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
            .inlineNavTitleIfSupported()
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
    @Published var personResults: [Person] = []
    @Published var selectedType: MediaType?
    @Published var selectedGenre: Genre?
    @Published var selectedYear: Int?
    @Published var genres: [Genre] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasSearched = false
    @Published var currentPage = 1
    @Published var totalPages = 1
    @Published var selectedStreamingServiceIds: Set<String> = []
    @Published private(set) var usedNaturalLanguageInLastSearch = false

    let streamingServices: [StreamingServiceOption] = [
        StreamingServiceOption(
            id: "netflix",
            name: "Netflix",
            logoURL: "https://cdn.brandfetch.io/ideQwN5lBE/w/800/h/216/theme/light/logo.png?c=1bxid64Mup7aczewSAYMX&t=1741362568562",
            brandColorHex: "#000000",
            listURL: "https://mdblist.com/lists/dualipafan01/netflix",
            trendingListURL: "https://mdblist.com/lists/dualipafan01/netflix-trending"
        ),
        StreamingServiceOption(
            id: "disney-plus",
            name: "Disney+",
            logoURL: "https://cdn.brandfetch.io/idhQlYRiX2/w/800/h/434/theme/light/logo.png?c=1bxid64Mup7aczewSAYMX&t=1769147818509",
            brandColorHex: "#084F60",
            listURL: "https://mdblist.com/lists/dualipafan01/disney",
            trendingListURL: "https://mdblist.com/lists/dualipafan01/disney-trending"
        ),
        StreamingServiceOption(
            id: "cartoon-network",
            name: "Cartoon Network",
            logoURL: "https://cdn.brandfetch.io/idFmMXJiW_/w/820/h/491/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1727089154071",
            brandColorHex: "#030327",
            listURL: "https://mdblist.com/lists/dualipafan01/cartoon-network"
        )
    ]

    private var streamingBaseResults: [MediaItem] = []
    private var activeSearchQuery = ""

    private struct NaturalLanguageIntent {
        enum ExplicitContentType {
            case movie
            case tv
        }
        
        enum PersonCreditMode {
            case cast
            case crew
            case any
        }

        var explicitContentType: ExplicitContentType?
        var genreId: Int?
        var personName: String?
        var personCreditMode: PersonCreditMode = .cast
        var companyNames: [String] = []
        var providerNames: [String] = []
        var releasedOnly: Bool = false
        var year: Int?
    }
    
    var hasMorePages: Bool {
        currentPage < totalPages
    }
    
    /// True when the People filter is active
    var isPeopleSearch: Bool {
        selectedType == .person
    }

    var isStreamingMode: Bool {
        !selectedStreamingServiceIds.isEmpty
    }

    var selectedStreamingServiceNames: [String] {
        streamingServices
            .filter { selectedStreamingServiceIds.contains($0.id) }
            .map { $0.name }
    }
    
    /// True when there are no results at all (media + people)
    var isEmptyResults: Bool {
        results.isEmpty && personResults.isEmpty
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
    
    func search(useNaturalLanguage: Bool = false) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            personResults = []
            hasSearched = false
            activeSearchQuery = ""
            usedNaturalLanguageInLastSearch = false
            return
        }

        selectedStreamingServiceIds.removeAll()
        streamingBaseResults = []

        isLoading = true
        hasSearched = true
        currentPage = 1
        personResults = []
        activeSearchQuery = trimmedQuery
        
        do {
            if selectedType == .person {
                usedNaturalLanguageInLastSearch = false
                // Dedicated person search
                let response = try await TMDBService.shared.searchPerson(query: activeSearchQuery)
                totalPages = response.totalPages ?? 1
                personResults = response.results
                results = []
            } else if selectedGenre != nil || selectedYear != nil {
                usedNaturalLanguageInLastSearch = false
                // Use discover endpoint for filters
                await searchWithFilters()
            } else {
                let shouldUseNaturalLanguage = useNaturalLanguage && StorageService.shared.settings.useAppleIntelligenceSearch
                usedNaturalLanguageInLastSearch = shouldUseNaturalLanguage

                if shouldUseNaturalLanguage, try await performStructuredNaturalLanguageSearch(for: trimmedQuery) {
                    isLoading = false
                    return
                }

                let queriesToTry: [String]
                if shouldUseNaturalLanguage {
                    queriesToTry = await AppleIntelligenceSearchService.shared.candidateQueries(for: trimmedQuery)
                } else {
                    queriesToTry = [trimmedQuery]
                }

                var processedAtLeastOneQuery = false
                for queryCandidate in queriesToTry {
                    let response = try await TMDBService.shared.searchMulti(query: queryCandidate)
                    let filteredResults = filterResults(response.results)
                    activeSearchQuery = queryCandidate
                    totalPages = response.totalPages ?? 1
                    processedAtLeastOneQuery = true

                    if !filteredResults.isEmpty || queryCandidate == queriesToTry.last {
                        results = filteredResults
                        break
                    }
                }

                if !processedAtLeastOneQuery {
                    results = []
                    totalPages = 1
                }
            }
        } catch {
            print("Search error: \(error)")
            results = []
            personResults = []
        }
        
        isLoading = false
    }
    
    func loadMore() async {
        if isStreamingMode { return }
        if activeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        guard hasMorePages && !isLoadingMore else { return }
        
        isLoadingMore = true
        currentPage += 1
        
        do {
            if selectedType == .person {
                let response = try await TMDBService.shared.searchPerson(query: activeSearchQuery, page: currentPage)
                personResults.append(contentsOf: response.results)
            } else {
                let response = try await TMDBService.shared.searchMulti(query: activeSearchQuery, page: currentPage)
                results.append(contentsOf: filterResults(response.results))
            }
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

    private func performStructuredNaturalLanguageSearch(for query: String) async throws -> Bool {
        let intent = parseNaturalLanguageIntent(from: query)
        let explicitMovieIntent = intent.explicitContentType == .movie
        let explicitTVIntent = intent.explicitContentType == .tv
        let requestedMovies = explicitMovieIntent || (intent.explicitContentType == nil && selectedType != .tv)
        let requestedTV = explicitTVIntent || (intent.explicitContentType == nil && selectedType != .movie)
        let applySelectedTypeFilter = intent.explicitContentType == nil

        if let personName = intent.personName, (requestedMovies || requestedTV) {
            let personResponse = try await TMDBService.shared.searchPerson(query: personName)
            if let person = personResponse.results.first {
                var personMedia: [MediaItem] = []
                
                if requestedMovies {
                    let movieCredits = try await TMDBService.shared.getPersonMovieCredits(id: person.id)
                    switch intent.personCreditMode {
                    case .cast:
                        personMedia.append(contentsOf: movieCredits.cast ?? [])
                    case .crew:
                        personMedia.append(contentsOf: movieCredits.crew ?? [])
                    case .any:
                        personMedia.append(contentsOf: movieCredits.cast ?? [])
                        personMedia.append(contentsOf: movieCredits.crew ?? [])
                    }
                }
                
                if requestedTV {
                    let tvCredits = try await TMDBService.shared.getPersonTVCredits(id: person.id)
                    switch intent.personCreditMode {
                    case .cast:
                        personMedia.append(contentsOf: tvCredits.cast ?? [])
                    case .crew:
                        personMedia.append(contentsOf: tvCredits.crew ?? [])
                    case .any:
                        personMedia.append(contentsOf: tvCredits.cast ?? [])
                        personMedia.append(contentsOf: tvCredits.crew ?? [])
                    }
                }

                if let genreId = intent.genreId {
                    personMedia = personMedia.filter { item in
                        guard let genreIds = item.genreIds, !genreIds.isEmpty else { return true }
                        return genreIds.contains(genreId)
                    }
                }

                if let year = intent.year {
                    personMedia = personMedia.filter { item in
                        guard let displayDate = item.displayDate, displayDate.count >= 4 else { return true }
                        return String(displayDate.prefix(4)) == String(year)
                    }
                }
                
                if intent.releasedOnly {
                    personMedia = filterReleasedItems(personMedia)
                }

                personMedia = dedupeMediaItems(personMedia).sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
                let filtered = filterResults(personMedia, applyingSelectedType: applySelectedTypeFilter)
                if !filtered.isEmpty {
                    results = filtered
                    personResults = []
                    currentPage = 1
                    totalPages = 1
                    activeSearchQuery = query
                    return true
                }
            }
        }

        if !intent.providerNames.isEmpty, (requestedMovies || requestedTV) {
            let providerIds = resolveProviderIDs(for: intent.providerNames)
            if !providerIds.isEmpty {
                let region = effectiveProviderRegion(for: intent.providerNames)
                var combinedResults: [MediaItem] = []
                var mergedTotalPages = 1

                if requestedMovies {
                    let movieResponse = try await TMDBService.shared.discoverMoviesWithProvider(
                        providerIds: providerIds,
                        region: region
                    )
                    combinedResults.append(contentsOf: movieResponse.results)
                    mergedTotalPages = max(mergedTotalPages, movieResponse.totalPages ?? 1)
                }

                if requestedTV {
                    let tvResponse = try await TMDBService.shared.discoverTVWithProvider(
                        providerIds: providerIds,
                        region: region
                    )
                    combinedResults.append(contentsOf: tvResponse.results)
                    mergedTotalPages = max(mergedTotalPages, tvResponse.totalPages ?? 1)
                }

                var providerMedia = dedupeMediaItems(combinedResults)

                if intent.releasedOnly {
                    providerMedia = filterReleasedItems(providerMedia)
                }

                if let genreId = intent.genreId {
                    providerMedia = providerMedia.filter { item in
                        guard let genreIds = item.genreIds, !genreIds.isEmpty else { return true }
                        return genreIds.contains(genreId)
                    }
                }

                if let year = intent.year {
                    providerMedia = providerMedia.filter { item in
                        guard let displayDate = item.displayDate, displayDate.count >= 4 else { return true }
                        return String(displayDate.prefix(4)) == String(year)
                    }
                }

                providerMedia.sort { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
                let filtered = filterResults(providerMedia, applyingSelectedType: applySelectedTypeFilter)
                if !filtered.isEmpty {
                    results = filtered
                    personResults = []
                    currentPage = 1
                    totalPages = mergedTotalPages
                    activeSearchQuery = query
                    return true
                }
            }
        }

        if !intent.companyNames.isEmpty, (requestedMovies || requestedTV) {
            var companyIds: Set<Int> = []
            for companyName in intent.companyNames {
                let ids = try await resolveCompanyIDs(for: companyName, wantsTV: requestedTV && !requestedMovies)
                companyIds.formUnion(ids)
            }

            guard !companyIds.isEmpty else { return false }
            var combinedResults: [MediaItem] = []
            var mergedTotalPages = 1

            if requestedMovies {
                let movieResponse = try await TMDBService.shared.discoverMoviesByCompany(companyIds: Array(companyIds))
                combinedResults.append(contentsOf: movieResponse.results)
                mergedTotalPages = max(mergedTotalPages, movieResponse.totalPages ?? 1)
            }

            if requestedTV {
                let tvResponse = try await TMDBService.shared.discoverTVByCompany(companyIds: Array(companyIds))
                combinedResults.append(contentsOf: tvResponse.results)
                mergedTotalPages = max(mergedTotalPages, tvResponse.totalPages ?? 1)
            }

            var companyMedia = dedupeMediaItems(combinedResults)

            if intent.releasedOnly {
                companyMedia = filterReleasedItems(companyMedia)
            }

            if let genreId = intent.genreId {
                companyMedia = companyMedia.filter { item in
                    guard let genreIds = item.genreIds, !genreIds.isEmpty else { return true }
                    return genreIds.contains(genreId)
                }
            }

            if let year = intent.year {
                companyMedia = companyMedia.filter { item in
                    guard let displayDate = item.displayDate, displayDate.count >= 4 else { return true }
                    return String(displayDate.prefix(4)) == String(year)
                }
            }

            companyMedia.sort { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            let filtered = filterResults(companyMedia, applyingSelectedType: applySelectedTypeFilter)
            guard !filtered.isEmpty else { return false }

            results = filtered
            personResults = []
            currentPage = 1
            totalPages = mergedTotalPages
            activeSearchQuery = query
            return true
        }

        if let genreId = intent.genreId, requestedMovies, intent.personName == nil {
            let response = try await TMDBService.shared.discoverMovies(genres: [genreId], year: intent.year)
            let filtered = filterResults(response.results, applyingSelectedType: applySelectedTypeFilter)
            guard !filtered.isEmpty else { return false }

            results = filtered
            personResults = []
            currentPage = 1
            totalPages = response.totalPages ?? 1
            activeSearchQuery = query
            return true
        }

        return false
    }

    private func parseNaturalLanguageIntent(from query: String) -> NaturalLanguageIntent {
        let normalized = normalizeIntentText(query)
        var intent = NaturalLanguageIntent()

        let releasedPhrases = [
            "released", "already released", "already out", "out now",
            "have been out", "that are out", "came out", "have come out",
            "exclude upcoming", "no upcoming", "not upcoming"
        ]
        intent.releasedOnly = releasedPhrases.contains { containsPhrase(normalized, phrase: $0) }

        let moviePhrases = ["movie", "movies", "film", "films", "cinema"]
        let tvPhrases = ["tv", "show", "shows", "series", "episodes", "episode"]
        if moviePhrases.contains(where: { containsPhrase(normalized, phrase: $0) }) {
            intent.explicitContentType = .movie
        } else if tvPhrases.contains(where: { containsPhrase(normalized, phrase: $0) }) {
            intent.explicitContentType = .tv
        }

        let genreMap: [(phrases: [String], genreId: Int)] = [
            (["action", "fight"], 28),
            (["adventure"], 12),
            (["animation", "animated"], 16),
            (["comedy", "funny"], 35),
            (["crime", "gangster"], 80),
            (["documentary", "doc"], 99),
            (["drama"], 18),
            (["family", "kids"], 10751),
            (["fantasy"], 14),
            (["history", "historical"], 36),
            (["horror", "scary"], 27),
            (["music", "musical"], 10402),
            (["mystery"], 9648),
            (["romance", "romantic"], 10749),
            (["science fiction", "sci fi", "scifi"], 878),
            (["thriller"], 53),
            (["war"], 10752),
            (["western"], 37)
        ]

        for entry in genreMap {
            if entry.phrases.contains(where: { containsPhrase(normalized, phrase: $0) }) {
                let genreId = entry.genreId
                intent.genreId = genreId
                break
            }
        }

        if let yearMatch = normalized.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
            intent.year = Int(normalized[yearMatch])
        }

        let starringPerson = extractEntity(
            in: normalized,
            triggers: ["starring", "featuring", "with actor", "with actress", "with", "acted by"],
            stoppers: [" but ", " and ", " that ", " which ", " who ", " where ", " produced by ", " made by ", " from ", " by ", " released ", " movie ", " movies ", " tv ", " show ", " series "]
        ) ?? extractEntityUsingPatterns(
            in: normalized,
            patterns: [
                #"(?:movies|movie|films|film|shows|show|series|tv shows|tv)\s+(?:starring|featuring|with|acted by)\s+([a-z0-9&\-\.' ]{2,80})"#,
                #"(?:starring|featuring|with|acted by)\s+([a-z0-9&\-\.' ]{2,80})\s+(?:movies|movie|films|film|shows|show|series|tv shows|tv)"#,
                #"(?:cast featuring|cast with)\s+([a-z0-9&\-\.' ]{2,80})"#
            ]
        )
        let crewPerson = extractEntity(
            in: normalized,
            triggers: ["directed by", "director", "directed", "produced by", "producer", "produced"],
            stoppers: [" but ", " and ", " that ", " which ", " who ", " where ", " starring ", " featuring ", " with ", " actor ", " actress ", " released ", " movie ", " movies ", " tv ", " show ", " series ", " studios ", " studio "]
        ) ?? extractEntityUsingPatterns(
            in: normalized,
            patterns: [
                #"(?:movies|movie|films|film|shows|show|series|tv shows|tv)\s+(?:directed by|directed|from director|by director)\s+([a-z0-9&\-\.' ]{2,80})"#,
                #"(?:movies|movie|films|film|shows|show|series|tv shows|tv)\s+(?:produced by|produced|from producer|by producer)\s+([a-z0-9&\-\.' ]{2,80})"#,
                #"(?:directed by|directed|from director|by director)\s+([a-z0-9&\-\.' ]{2,80})\s+(?:movies|movie|films|film|shows|show|series|tv shows|tv)"#,
                #"(?:produced by|produced|from producer|by producer)\s+([a-z0-9&\-\.' ]{2,80})\s+(?:movies|movie|films|film|shows|show|series|tv shows|tv)"#
            ]
        )
        
        if let starringPerson {
            intent.personName = starringPerson
            if containsPhrase(normalized, phrase: "director") || containsPhrase(normalized, phrase: "producer") {
                intent.personCreditMode = .any
            } else {
                intent.personCreditMode = .cast
            }
        } else if let crewPerson {
            intent.personName = crewPerson
            intent.personCreditMode = .crew
        }

        let companyPhrase = extractEntity(
            in: normalized,
            triggers: ["produced by", "production by", "made by", "studio", "studios", "from", "by"],
            stoppers: [" but ", " that ", " which ", " who ", " where ", " starring ", " featuring ", " with ", " actor ", " actress ", " directed by ", " director ", " producer ", " released ", " movie ", " movies ", " tv ", " show ", " series "]
        ) ?? extractEntityUsingPatterns(
            in: normalized,
            patterns: [
                #"(?:movies|movie|films|film|shows|show|series|tv shows|tv)\s+(?:made by|from studio|from studios|studio|studios|produced by|production by|distributed by)\s+([a-z0-9&\-\.' ]{2,80})"#,
                #"(?:made by|from studio|from studios|studio|studios|produced by|production by|distributed by)\s+([a-z0-9&\-\.' ]{2,80})\s+(?:movies|movie|films|film|shows|show|series|tv shows|tv)"#,
                #"(?:made for)\s+([a-z0-9&\-\+.' ]{2,80})"#
            ]
        )
        if let companyPhrase, intent.personName == nil || looksLikeCompanyPhrase(companyPhrase) {
            intent.companyNames = parseCompanyNames(from: companyPhrase)
        }

        intent.providerNames = extractProviderNames(from: normalized)

        return intent
    }

    private func normalizeIntentText(_ text: String) -> String {
        var normalized = text.lowercased()
        let replacements = [",", ".", "?", "!", ":", ";", "(", ")", "\"", "'"]
        for token in replacements {
            normalized = normalized.replacingOccurrences(of: token, with: " ")
        }
        while normalized.contains("  ") {
            normalized = normalized.replacingOccurrences(of: "  ", with: " ")
        }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsPhrase(_ text: String, phrase: String) -> Bool {
        let paddedText = " \(text) "
        let paddedPhrase = " \(phrase) "
        return paddedText.contains(paddedPhrase)
    }

    private func extractEntity(in normalized: String, triggers: [String], stoppers: [String]) -> String? {
        let orderedTriggers = triggers.sorted { $0.count > $1.count }
        for trigger in orderedTriggers {
            let pattern = "\(trigger) "
            guard let range = normalized.range(of: pattern) else { continue }

            var candidate = String(normalized[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            for stopper in stoppers {
                if let stopRange = candidate.range(of: stopper) {
                    candidate = String(candidate[..<stopRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if candidate.hasPrefix("the ") {
                candidate = String(candidate.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if candidate.hasSuffix(" studio") {
                candidate += "s"
            }
            if candidate.hasSuffix(" studioss") {
                candidate = candidate.replacingOccurrences(of: " studioss", with: " studios")
            }

            let words = candidate.split(separator: " ")
            if !candidate.isEmpty && words.count <= 6 {
                return candidate
            }
        }
        return nil
    }
    
    private func extractEntityUsingPatterns(in normalized: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            guard let match = regex.firstMatch(in: normalized, options: [], range: range) else { continue }
            guard match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: normalized) else { continue }
            let candidate = normalized[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = cleanupEntityCandidate(candidate)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }
    
    private func cleanupEntityCandidate(_ candidate: String) -> String {
        var cleaned = candidate
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("the ") {
            cleaned = String(cleaned.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.hasSuffix(" studio") {
            cleaned += "s"
        }
        if cleaned.hasSuffix(" studioss") {
            cleaned = cleaned.replacingOccurrences(of: " studioss", with: " studios")
        }
        let words = cleaned.split(separator: " ")
        if words.isEmpty || words.count > 8 { return "" }
        return cleaned
    }
    
    private func looksLikeCompanyPhrase(_ phrase: String) -> Bool {
        let normalized = phrase.lowercased()
        let companyTokens = [
            "studio", "studios", "pictures", "productions", "entertainment",
            "media", "films", "network", "animation", "plus", "tv"
        ]
        return companyTokens.contains { normalized.contains($0) }
    }

    private func parseCompanyNames(from phrase: String) -> [String] {
        var normalized = phrase
            .replacingOccurrences(of: " and ", with: "|")
            .replacingOccurrences(of: " & ", with: "|")
            .replacingOccurrences(of: ",", with: "|")
            .replacingOccurrences(of: " plus ", with: "|")
            .replacingOccurrences(of: " or ", with: "|")

        while normalized.contains("||") {
            normalized = normalized.replacingOccurrences(of: "||", with: "|")
        }

        let names = normalized
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { canonicalCompanyName($0) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        var deduped: [String] = []
        for name in names {
            if seen.contains(name) { continue }
            seen.insert(name)
            deduped.append(name)
        }
        return deduped
    }

    private func canonicalCompanyName(_ name: String) -> String {
        let lowered = name.lowercased()
        if lowered == "universal" {
            return "universal pictures"
        }
        return name
    }

    private func resolveCompanyIDs(for companyName: String, wantsTV: Bool) async throws -> [Int] {
        let appHubIds = resolveCompanyIDsFromAppHubs(for: companyName)
        if !appHubIds.isEmpty {
            return appHubIds
        }

        let response = try await TMDBService.shared.searchCompanies(query: companyName)
        guard !response.results.isEmpty else { return [] }

        let normalizedQuery = companyName.lowercased()
        let scored = response.results
            .map { company in
                (id: company.id, score: companyScore(name: company.name, query: normalizedQuery, wantsTV: wantsTV))
            }
            .sorted { $0.score > $1.score }

        let positive = scored.filter { $0.score > 0 }.map(\.id)
        if normalizedQuery.contains("marvel") {
            return Array(positive.prefix(6))
        }

        if let first = positive.first {
            return [first]
        }
        return [response.results[0].id]
    }

    private func resolveCompanyIDsFromAppHubs(for companyName: String) -> [Int] {
        let normalizedName = normalizeIntentText(companyName)
        let tokens = normalizedName.split(separator: " ").map(String.init)
        let hubs = StorageService.shared.companyHubs

        var matched: [Int] = []
        for hub in hubs {
            let hubName = normalizeIntentText(hub.name)
            if hubName == normalizedName || hubName.contains(normalizedName) || normalizedName.contains(hubName) {
                matched.append(contentsOf: hub.companyIds)
                continue
            }

            if !tokens.isEmpty && tokens.allSatisfy({ hubName.contains($0) }) {
                matched.append(contentsOf: hub.companyIds)
            }
        }

        return Array(Set(matched))
    }

    private func extractProviderNames(from normalized: String) -> [String] {
        let hubs = StorageService.shared.networkHubs
        guard !hubs.isEmpty else { return [] }

        var matches: [String] = []
        for hub in hubs {
            let aliases = providerAliases(for: hub.name)
            if aliases.contains(where: { containsPhrase(normalized, phrase: $0) }) {
                matches.append(hub.name)
            }
        }

        var seen: Set<String> = []
        var deduped: [String] = []
        for name in matches {
            if seen.contains(name) { continue }
            seen.insert(name)
            deduped.append(name)
        }
        return deduped
    }

    private func providerAliases(for providerName: String) -> [String] {
        let normalized = normalizeIntentText(providerName)
        switch normalized {
        case "disney+":
            return ["disney+", "disney plus", "disneyplus", "d+"]
        case "netflix":
            return ["netflix", "net flix"]
        case "max":
            return ["max", "hbo max", "hbomax"]
        case "paramount+":
            return ["paramount+", "paramount plus", "paramountplus"]
        case "apple tv+", "apple tv":
            return ["apple tv+", "apple tv plus", "appletv+", "appletv plus", "appletv"]
        case "amazon prime video":
            return ["amazon prime", "prime video", "prime"]
        default:
            return [normalized]
        }
    }

    private func resolveProviderIDs(for providerNames: [String]) -> [Int] {
        let hubs = StorageService.shared.networkHubs
        var ids: [Int] = []
        for name in providerNames {
            if let hub = hubs.first(where: { normalizeIntentText($0.name) == normalizeIntentText(name) }) {
                ids.append(contentsOf: hub.providerIds)
            }
        }
        return Array(Set(ids))
    }

    private func effectiveProviderRegion(for providerNames: [String]) -> String {
        let region = StorageService.shared.settings.region
        let lowered = providerNames.map { $0.lowercased() }

        // Match existing Disney+ ZA behavior used in browse rows.
        if region == "ZA", lowered.contains(where: { $0.contains("disney") }) {
            return "GB"
        }
        return region
    }

    private func companyScore(name: String, query: String, wantsTV: Bool) -> Int {
        let normalizedName = name.lowercased()
        var score = 0

        if normalizedName == query { score += 100 }
        if normalizedName.contains(query) { score += 60 }

        let queryTokens = query.split(separator: " ").map(String.init)
        for token in queryTokens where token.count > 1 {
            if normalizedName.contains(token) {
                score += 10
            }
        }

        if wantsTV {
            if normalizedName.contains("television") || normalizedName.contains("tv") || normalizedName.contains("animation") {
                score += 20
            }
        } else {
            if normalizedName.contains("studios") || normalizedName.contains("pictures") || normalizedName.contains("films") {
                score += 10
            }
        }

        if query.contains("marvel") && normalizedName.contains("marvel") {
            score += 50
        }

        return score
    }

    private func dedupeMediaItems(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<Int>()
        return items.filter { item in
            guard !seen.contains(item.id) else { return false }
            seen.insert(item.id)
            return true
        }
    }

    private func filterReleasedItems(_ items: [MediaItem]) -> [MediaItem] {
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)

        return items.filter { item in
            guard let releaseDate = item.releaseDate, releaseDate.count >= 10 else { return false }
            return releaseDate <= todayString
        }
    }
    
    private func filterResults(_ items: [MediaItem], applyingSelectedType: Bool = true) -> [MediaItem] {
        var filtered = items
        
        if applyingSelectedType, let type = selectedType {
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

    func toggleStreamingService(_ service: StreamingServiceOption) async {
        if selectedStreamingServiceIds.contains(service.id) {
            selectedStreamingServiceIds.remove(service.id)
        } else {
            selectedStreamingServiceIds.insert(service.id)
        }
        await loadStreamingRecommendations()
    }

    func applyStreamingFilters() {
        guard isStreamingMode else { return }
        results = filterResults(streamingBaseResults)
    }

    private func loadStreamingRecommendations() async {
        if selectedStreamingServiceIds.isEmpty {
            streamingBaseResults = []
            results = []
            personResults = []
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasSearched = false
            }
            return
        }

        query = ""
        selectedGenre = nil
        selectedYear = nil
        selectedType = nil

        isLoading = true
        hasSearched = true
        currentPage = 1
        totalPages = 1
        personResults = []

        let listInputs = streamingServices
            .filter { selectedStreamingServiceIds.contains($0.id) }
            .map { $0.listURL }

        do {
            let savedItems = try await MDBListService.shared.fetchMultipleListsAsSavedMedia(
                inputs: listInputs,
                perListLimit: 20,
                totalLimit: 10,
                preferTMDBDetails: true
            )
            streamingBaseResults = savedItems.map { $0.toMediaItem() }
            results = filterResults(streamingBaseResults)
        } catch {
            print("Streaming recommendations error: \(error)")
            streamingBaseResults = []
            results = []
        }

        isLoading = false
    }
    
    func clearSearch() {
        query = ""
        results = []
        personResults = []
        hasSearched = false
        usedNaturalLanguageInLastSearch = false
        activeSearchQuery = ""
        selectedStreamingServiceIds.removeAll()
        streamingBaseResults = []
    }
}

// MARK: - Person Search Card
struct PersonSearchCard: View {
    let person: Person
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 10) {
            ProfileImageView(profilePath: person.profilePath, size: 90)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            
            VStack(spacing: 3) {
                Text(person.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                if let dept = person.knownForDepartment, !dept.isEmpty {
                    Text(dept)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Show top known-for title
                if let knownFor = person.knownFor?.first, let title = knownFor.displayTitle as String? {
                    Text(title)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .italic()
                }
            }
            .frame(width: 100)
        }
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Network Trending Popup
struct NetworkTrendingPopup: View {
    let service: StreamingServiceOption
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var trendingMovies: [MediaItem] = []
    @State private var trendingShows: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var detailItem: MediaItem?
    
    private var brandColor: Color {
        Color(hex: service.brandColorHex)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading trending...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if let error {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.orange)
                        Text("Couldn't load trending")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                } else {
                    trendingContent
                }
            }
            .inlineNavTitleIfSupported()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $detailItem) { item in
                MediaDetailView(item: item)
            }
        }
        .presentationDetents([.large])
        .task {
            await loadTrending()
        }
    }
    
    private var trendingContent: some View {
        VStack(spacing: 0) {
            // Service header
            serviceHeader
                .padding(.top, 4)
                .padding(.bottom, 12)
            
            // Two columns: Movies and TV Shows
            if trendingMovies.isEmpty && trendingShows.isEmpty {
                Spacer()
                Text("No trending content found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 16) {
                    // Movies column
                    trendingColumn(
                        title: "Movies",
                        icon: "film.fill",
                        items: trendingMovies
                    )
                    
                    // Divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 1)
                        .padding(.vertical, 4)
                    
                    // TV Shows column
                    trendingColumn(
                        title: "TV Shows",
                        icon: "tv.fill",
                        items: trendingShows
                    )
                }
                .padding(.horizontal)
                
                Spacer(minLength: 16)
            }
        }
    }
    
    private var serviceHeader: some View {
        VStack(spacing: 8) {
            // Logo
            AsyncImage(url: URL(string: service.logoURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 24)
                default:
                    Text(service.name)
                        .font(.title3)
                        .fontWeight(.bold)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(brandColor)
            )
            
            Text("Trending Now")
                .font(.headline)
                .foregroundColor(.primary)
        }
    }
    
    private func trendingColumn(title: String, icon: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Column header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(.bottom, 2)
            
            if items.isEmpty {
                Text("None found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        detailItem = item
                    } label: {
                        TrendingItemRow(item: item, rank: index + 1, brandColor: brandColor)
                    }
                    .buttonStyle(.plain)
                    
                    if index < items.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func loadTrending() async {
        guard let listURL = service.trendingListURL else {
            error = "No trending list configured."
            isLoading = false
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            let items = try await MDBListService.shared.fetchListItemsAsSavedMedia(
                listId: listURL,
                limit: 20
            )
            
            let movies = items
                .filter { $0.mediaType == .movie }
                .prefix(5)
                .map { $0.toMediaItem() }
            
            let shows = items
                .filter { $0.mediaType == .tv }
                .prefix(5)
                .map { $0.toMediaItem() }
            
            trendingMovies = Array(movies)
            trendingShows = Array(shows)
        } catch {
            self.error = "Failed to load trending content."
            print("Network trending popup error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Trending Item Row
private struct TrendingItemRow: View {
    let item: MediaItem
    let rank: Int
    let brandColor: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            // Rank number
            Text("\(rank)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(rank <= 3 ? brandColor : .secondary)
                .frame(width: 22, alignment: .center)
            
            // Poster thumbnail
            let posterURL = TMDBService.shared.imageURL(path: item.posterPath, size: .small)
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.18))
                        .overlay { ProgressView().scaleEffect(0.6) }
                default:
                    Rectangle()
                        .fill(Color.gray.opacity(0.18))
                        .overlay {
                            Image(systemName: "film")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                }
            }
            .frame(width: 36, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            
            // Title and year
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if let year = item.year {
                    Text(year)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private extension View {
    @ViewBuilder
    func inlineNavTitleIfSupported() -> some View {
#if os(macOS)
        self
#else
        self.navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 3:
            (r, g, b) = (
                ((int >> 8) & 0xF) * 17,
                ((int >> 4) & 0xF) * 17,
                (int & 0xF) * 17
            )
        default:
            (r, g, b) = (128, 128, 128)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
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
