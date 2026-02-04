//
//  BrowseView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct BrowseView: View {
    @StateObject private var viewModel = BrowseViewModel()
    @Binding var selectedItem: MediaItem?
    @State private var showNetworkHub = false
    @State private var selectedNetworkHub: NetworkHub?
    @State private var showStudioHub = false
    @State private var selectedStudioHub: StudioHub?
    @State private var showCustomizeSheet = false
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Hero Carousel
                if !viewModel.heroItems.isEmpty {
                    HeroCarouselView(items: viewModel.heroItems) { item in
                        selectedItem = item
                    }
                    .aspectRatio(16.0/9.0, contentMode: .fit)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                
                // Networks Section (Streaming Services)
                if !viewModel.networkHubs.isEmpty {
                    NetworkHubsRow(hubs: viewModel.networkHubs) { hub in
                        selectedNetworkHub = hub
                        showNetworkHub = true
                    }
                    .padding(.top, 4)
                }
                
                // Custom Home Rows (MDBList and Custom Hubs)
                ForEach(viewModel.customHomeRows) { customRow in
                    if let row = viewModel.customRowContent[customRow.id], !row.items.isEmpty {
                        CustomHomeRowView(
                            row: customRow,
                            items: row.items,
                            onItemTap: { item in
                                selectedItem = item
                            }
                        )
                    }
                }
                
                // Browse Rows
                ForEach(viewModel.rows, id: \.title) { row in
                    if !row.items.isEmpty {
                        MediaRowView(
                            title: row.title,
                            items: row.items,
                            onItemTap: { item in
                                selectedItem = item
                            }
                        )
                        if row.title == "Popular Movies" && !viewModel.studios.isEmpty {
                            StudiosRow(studios: viewModel.studios) { studio in
                                selectedStudioHub = studio
                                showStudioHub = true
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                
                // Imported Lists Rows (for backward compatibility)
                ForEach(viewModel.importedListRows, id: \.title) { row in
                    if !row.items.isEmpty {
                        MediaRowView(
                            title: row.title,
                            items: row.items,
                            onItemTap: { item in
                                selectedItem = item
                            }
                        )
                    }
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadContent()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCustomizeSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showNetworkHub) {
            if let hub = selectedNetworkHub {
                NetworkHubSheet(hub: hub, selectedItem: $selectedItem)
            }
        }
        .sheet(isPresented: $showStudioHub) {
            if let studio = selectedStudioHub {
                StudioHubSheet(studio: studio, selectedItem: $selectedItem)
            }
        }
        .sheet(isPresented: $showCustomizeSheet) {
            BrowseCustomizeSheet()
        }
        .onChange(of: StorageService.shared.settings.heroCarouselSource) { _, _ in
            Task { await viewModel.refresh() }
        }
    }
}

// MARK: - Custom Home Row View
struct CustomHomeRowView: View {
    let row: CustomHomeRow
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with optional image
            HStack {
                if let imageURL = row.hubImageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 28)
                                .cornerRadius(4)
                        default:
                            EmptyView()
                        }
                    }
                }
                
                Text(row.name)
                    .font(.title3)
                    .fontWeight(.bold)
                
                if row.rowType == .importedList {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Scrolling content
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        MediaPosterCard(item: item)
                            .onTapGesture {
                                onItemTap(item)
                            }
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - Browse View Model
@MainActor
class BrowseViewModel: ObservableObject {
    @Published var heroItems: [MediaItem] = []
    @Published var rows: [MediaRow] = []
    @Published var importedListRows: [MediaRow] = []
    @Published var customHomeRows: [CustomHomeRow] = []
    @Published var customRowContent: [String: MediaRow] = [:]
    @Published var networkHubs: [NetworkHub] = []
    @Published var studios: [StudioHub] = []
    @Published var isLoading = false
    
    struct MediaRow {
        let title: String
        let items: [MediaItem]
    }
    
    func loadContent() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        
        // Load network hubs (streaming services)
        networkHubs = StorageService.shared.getEnabledNetworkHubs()
        
        // Load custom home rows
        customHomeRows = StorageService.shared.getEnabledCustomHomeRows()
        
        // Studios (circular hubs)
        studios = [
            StudioHub(
                name: "20th Century Studios",
                logoURL: "https://i.ibb.co/23tL20Sb/20th-century-studios-seeklogo.png",
                listId: "dualipafan01/20th-century-studios"
            )
        ]
        
        // Load hero items based on user's selected source (concurrently)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadHeroItems() }
            group.addTask { await self.loadBrowseRows() }
            group.addTask { await self.loadCustomHomeRowContent() }
            group.addTask { await self.loadImportedListRows() }
        }
    }
    
    private func loadHeroItems() async {
        let source = StorageService.shared.settings.heroCarouselSource
        
        do {
            let items: [MediaItem]
            switch source {
            case .trendingMovies:
                items = try await TMDBService.shared.getTrending(mediaType: .movie, timeWindow: "day").results
            case .trendingTV:
                items = try await TMDBService.shared.getTrending(mediaType: .tv, timeWindow: "day").results
            case .popularMovies:
                items = try await TMDBService.shared.getPopularMovies().results
            case .popularTV:
                items = try await TMDBService.shared.getPopularTV().results
            case .nowPlayingMovies:
                items = try await TMDBService.shared.getNowPlayingMovies().results
            case .topRatedMovies:
                items = try await TMDBService.shared.getTopRatedMovies().results
            case .upcomingMovies:
                items = try await TMDBService.shared.getUpcomingMovies().results
            case .mdblistTrending:
                // Fetch MDBList trending list and split into up to 5 movies + 5 TV if mixed
                let listId = "dualipafan01/trending-titles"
                let mediaItems: [MediaItem]
                do {
                    let savedItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: listId)
                    // Convert to MediaItem array
                    let converted: [MediaItem] = savedItems.map { saved in
                        MediaItem(
                            id: saved.mediaId,
                            title: saved.mediaType == .movie ? saved.title : nil,
                            name: saved.mediaType == .tv ? saved.title : nil,
                            originalTitle: nil,
                            originalName: nil,
                            overview: saved.overview,
                            posterPath: saved.posterPath,
                            backdropPath: saved.backdropPath,
                            releaseDate: saved.year,
                            firstAirDate: saved.year,
                            voteAverage: saved.voteAverage,
                            voteCount: nil,
                            popularity: nil,
                            genreIds: nil,
                            mediaType: saved.mediaType.rawValue,
                            adult: nil,
                            originalLanguage: nil
                        )
                    }
                    let movies = converted.filter { $0.resolvedMediaType == .movie }
                    let tv = converted.filter { $0.resolvedMediaType == .tv }
                    if !movies.isEmpty && !tv.isEmpty {
                        mediaItems = Array(movies.prefix(5)) + Array(tv.prefix(5))
                    } else {
                        mediaItems = converted
                    }
                } catch {
                    print("Error loading MDBList trending: \(error)")
                    mediaItems = []
                }
                items = mediaItems
            }
            heroItems = Array(items.prefix(10))
        } catch {
            print("Error loading hero: \(error)")
        }
    }
    
    func refresh() async {
        // Wait for any in-flight load to finish to avoid clearing data mid-load
        while isLoading {
            try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s
        }

        rows = []
        importedListRows = []
        customRowContent = [:]
        heroItems = []
        await loadContent()
    }
    
    private func loadBrowseRows() async {
        let configs = StorageService.shared.browseRows.filter { $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
        
        var loadedRows: [(Int, MediaRow)] = []
        
        await withTaskGroup(of: (Int, MediaRow?).self) { group in
            for (index, config) in configs.enumerated() {
                group.addTask {
                    do {
                        let items = try await self.fetchRow(config.endpoint)
                        return (index, MediaRow(title: config.title, items: items))
                    } catch {
                        print("Error loading \(config.title): \(error)")
                        return (index, nil)
                    }
                }
            }
            
            for await result in group {
                if let row = result.1 {
                    loadedRows.append((result.0, row))
                }
            }
        }
        
        // Sort by original order and extract rows
        rows = loadedRows.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
    }
    
    private func loadCustomHomeRowContent() async {
        for customRow in customHomeRows {
            switch customRow.rowType {
            case .importedList:
                if let importedListId = customRow.importedListId,
                   let importedList = StorageService.shared.importedLists.first(where: { $0.id == importedListId }),
                   !importedList.items.isEmpty {
                    // Convert SavedMediaItems to MediaItems
                    let items = importedList.items.map { saved -> MediaItem in
                        MediaItem(
                            id: saved.mediaId,
                            title: saved.mediaType == .movie ? saved.title : nil,
                            name: saved.mediaType == .tv ? saved.title : nil,
                            originalTitle: nil,
                            originalName: nil,
                            overview: saved.overview,
                            posterPath: saved.posterPath,
                            backdropPath: saved.backdropPath,
                            releaseDate: saved.year,
                            firstAirDate: saved.year,
                            voteAverage: saved.voteAverage,
                            voteCount: nil,
                            popularity: nil,
                            genreIds: nil,
                            mediaType: saved.mediaType.rawValue,
                            adult: nil,
                            originalLanguage: nil
                        )
                    }
                    customRowContent[customRow.id] = MediaRow(title: customRow.name, items: items)
                }
                
            case .customHub:
                if let items = customRow.items, !items.isEmpty {
                    let mediaItems = items.map { saved -> MediaItem in
                        MediaItem(
                            id: saved.mediaId,
                            title: saved.mediaType == .movie ? saved.title : nil,
                            name: saved.mediaType == .tv ? saved.title : nil,
                            originalTitle: nil,
                            originalName: nil,
                            overview: saved.overview,
                            posterPath: saved.posterPath,
                            backdropPath: saved.backdropPath,
                            releaseDate: saved.year,
                            firstAirDate: saved.year,
                            voteAverage: saved.voteAverage,
                            voteCount: nil,
                            popularity: nil,
                            genreIds: nil,
                            mediaType: saved.mediaType.rawValue,
                            adult: nil,
                            originalLanguage: nil
                        )
                    }
                    customRowContent[customRow.id] = MediaRow(title: customRow.name, items: mediaItems)
                }
            }
        }
    }
    
    private func loadImportedListRows() async {
        // Load imported lists that are set to show on home but don't have a custom row
        let listsOnHome = StorageService.shared.getImportedListsForHome()
        let customRowListIds = Set(customHomeRows.compactMap { $0.importedListId })
        
        var loadedRows: [MediaRow] = []
        
        for list in listsOnHome {
            // Skip if already in custom rows
            if customRowListIds.contains(list.id) { continue }
            
            let items = list.items.map { saved -> MediaItem in
                MediaItem(
                    id: saved.mediaId,
                    title: saved.mediaType == .movie ? saved.title : nil,
                    name: saved.mediaType == .tv ? saved.title : nil,
                    originalTitle: nil,
                    originalName: nil,
                    overview: saved.overview,
                    posterPath: saved.posterPath,
                    backdropPath: saved.backdropPath,
                    releaseDate: saved.year,
                    firstAirDate: saved.year,
                    voteAverage: saved.voteAverage,
                    voteCount: nil,
                    popularity: nil,
                    genreIds: nil,
                    mediaType: saved.mediaType.rawValue,
                    adult: nil,
                    originalLanguage: nil
                )
            }
            
            if !items.isEmpty {
                loadedRows.append(MediaRow(title: list.displayName, items: items))
            }
        }
        
        importedListRows = loadedRows
    }
    
    private func fetchRow(_ endpoint: BrowseRowConfig.BrowseEndpoint) async throws -> [MediaItem] {
        switch endpoint {
        case .trendingMovies:
            return try await TMDBService.shared.getTrending(mediaType: .movie).results
        case .trendingTV:
            return try await TMDBService.shared.getTrending(mediaType: .tv).results
        case .popularMovies:
            return try await TMDBService.shared.getPopularMovies().results
        case .popularTV:
            return try await TMDBService.shared.getPopularTV().results
        case .topRatedMovies:
            return try await TMDBService.shared.getTopRatedMovies().results
        case .topRatedTV:
            return try await TMDBService.shared.getTopRatedTV().results
        case .nowPlayingMovies:
            return try await TMDBService.shared.getNowPlayingMovies().results
        case .airingTodayTV:
            return try await TMDBService.shared.getAiringTodayTV().results
        case .upcomingMovies:
            return try await TMDBService.shared.getUpcomingMovies().results
        case .onTheAirTV:
            return try await TMDBService.shared.getOnTheAirTV().results
        }
    }
}

struct StudioHub: Identifiable {
    let id = UUID()
    let name: String
    let logoURL: String
    let listId: String
}

// MARK: - Network Hubs Row (Streaming Services)
struct NetworkHubsRow: View {
    let hubs: [NetworkHub]
    let onHubTap: (NetworkHub) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Networks")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(hubs) { hub in
                        NetworkHubCard(hub: hub)
                            .onTapGesture {
                                onHubTap(hub)
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct StudiosRow: View {
    let studios: [StudioHub]
    let onStudioTap: (StudioHub) -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Studios")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(studios) { studio in
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                                    .frame(width: 72, height: 72)
                                
                                AsyncImage(url: URL(string: studio.logoURL)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .renderingMode(.template)
                                            .foregroundStyle(colorScheme == .light ? .black : .white)
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 56, height: 56)
                                    default:
                                        EmptyView()
                                    }
                                }
                            }
                            Text(studio.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(width: 80)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onStudioTap(studio) }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct NetworkHubCard: View {
    let hub: NetworkHub
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(width: 100, height: 56)
                
                if let logoURL = hub.logoURL, let url = URL(string: logoURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .renderingMode(.template)
                                .foregroundStyle(colorScheme == .light ? .black : .white)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 40)
                        case .failure, .empty:
                            Text(hub.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal, 4)
                        @unknown default:
                            Text(hub.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                } else {
                    Text(hub.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: isHovered ? 8 : 4, y: isHovered ? 4 : 2)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

extension NetworkHub {
    var companyIdsIfKnown: [Int] {
        switch name {
        case "Disney Channel":
            // TMDB company id for Disney Channel
            return [2739]
        case "Showmax":
            // TMDB company id for Showmax (placeholder if unknown)
            return [128351]
        default:
            return []
        }
    }
}

// MARK: - Network Hub Sheet
struct NetworkHubSheet: View {
    let hub: NetworkHub
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var movies: [MediaItem] = []
    @State private var tvShows: [MediaItem] = []
    @State private var isLoading = true
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                if let logoURL = hub.logoURL, let url = URL(string: logoURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .renderingMode(.template)
                                .foregroundStyle(colorScheme == .light ? .black : .white)
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 40)
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV Shows").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                        ], spacing: 20) {
                            let items = selectedTab == 0 ? movies : tvShows
                            ForEach(items) { item in
                                MediaPosterCard(item: item)
                                    .onTapGesture {
                                        selectedItem = item
                                        dismiss()
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(hub.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        await MainActor.run { isLoading = true }
        
        var region = StorageService.shared.settings.region
        
        // Special handling for South Africa Disney+ (mirrors UK content)
        if region == "ZA" && hub.name == "Disney+" {
            region = "GB"
        }
        
        // Special-case: Disney Channel hub uses curated MDBList content instead of provider-based discovery
        if hub.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "disney channel" {
            do {
                // Fetch MDBList items and convert to MediaItem
                let savedItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: "dualipafan01/disney-channel")
                let converted: [MediaItem] = savedItems.map { saved in
                    MediaItem(
                        id: saved.mediaId,
                        title: saved.mediaType == .movie ? saved.title : nil,
                        name: saved.mediaType == .tv ? saved.title : nil,
                        originalTitle: nil,
                        originalName: nil,
                        overview: saved.overview,
                        posterPath: saved.posterPath,
                        backdropPath: saved.backdropPath,
                        releaseDate: saved.year,
                        firstAirDate: saved.year,
                        voteAverage: saved.voteAverage,
                        voteCount: nil,
                        popularity: nil,
                        genreIds: nil,
                        mediaType: saved.mediaType.rawValue,
                        adult: nil,
                        originalLanguage: nil
                    )
                }
                // Split into movies and TV, then ensure content is visible
                let m = converted.filter { $0.resolvedMediaType == .movie }
                let t = converted.filter { $0.resolvedMediaType == .tv }
                await MainActor.run {
                    if m.isEmpty && !t.isEmpty {
                        self.movies = t
                        self.tvShows = t
                        self.selectedTab = 1 // TV Shows
                    } else if t.isEmpty && !m.isEmpty {
                        self.movies = m
                        self.tvShows = m
                        self.selectedTab = 0 // Movies
                    } else if m.isEmpty && t.isEmpty {
                        // Fallback: show all items in both tabs
                        self.movies = converted
                        self.tvShows = converted
                        self.selectedTab = 0
                    } else {
                        self.movies = m
                        self.tvShows = t
                        self.selectedTab = 0
                    }
                    self.isLoading = false
                }
            } catch {
                print("Error loading Disney Channel MDBList: \(error)")
                await MainActor.run {
                    self.movies = []
                    self.tvShows = []
                    self.isLoading = false
                }
            }
            return
        }
        
        // Load movies: try provider-based first; fallback to empty if no providers
        do {
            if !hub.providerIds.isEmpty {
                let response = try await TMDBService.shared.discoverMoviesWithProvider(
                    providerIds: hub.providerIds,
                    region: region
                )
                await MainActor.run { movies = response.results }
            } else {
                await MainActor.run { movies = [] }
            }
        } catch {
            print("Error loading movies: \(error)")
        }
        
        // Load TV: try provider-based first; fallback to empty if no providers
        do {
            if !hub.providerIds.isEmpty {
                let response = try await TMDBService.shared.discoverTVWithProvider(
                    providerIds: hub.providerIds,
                    region: region
                )
                await MainActor.run { tvShows = response.results }
            } else {
                await MainActor.run { tvShows = [] }
            }
        } catch {
            print("Error loading TV: \(error)")
        }
        
        await MainActor.run { isLoading = false }
    }
}

struct StudioHubSheet: View {
    let studio: StudioHub
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var movies: [MediaItem] = []
    @State private var tvShows: [MediaItem] = []
    @State private var isLoading = true
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                AsyncImage(url: URL(string: studio.logoURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(colorScheme == .light ? .black : .white)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 40)
                    default:
                        EmptyView()
                    }
                }
                .padding(.vertical, 8)
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV Shows").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                        ], spacing: 20) {
                            let items = selectedTab == 0 ? movies : tvShows
                            ForEach(items) { item in
                                MediaPosterCard(item: item)
                                    .onTapGesture {
                                        selectedItem = item
                                        dismiss()
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(studio.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await loadContent() }
    }
    
    private func loadContent() async {
        await MainActor.run { isLoading = true }
        do {
            let savedItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: studio.listId)
            let converted: [MediaItem] = savedItems.map { saved in
                MediaItem(
                    id: saved.mediaId,
                    title: saved.mediaType == .movie ? saved.title : nil,
                    name: saved.mediaType == .tv ? saved.title : nil,
                    originalTitle: nil,
                    originalName: nil,
                    overview: saved.overview,
                    posterPath: saved.posterPath,
                    backdropPath: saved.backdropPath,
                    releaseDate: saved.year,
                    firstAirDate: saved.year,
                    voteAverage: saved.voteAverage,
                    voteCount: nil,
                    popularity: nil,
                    genreIds: nil,
                    mediaType: saved.mediaType.rawValue,
                    adult: nil,
                    originalLanguage: nil
                )
            }
            let m = converted.filter { $0.resolvedMediaType == .movie }
            let t = converted.filter { $0.resolvedMediaType == .tv }
            await MainActor.run {
                if m.isEmpty && !t.isEmpty {
                    self.movies = t
                    self.tvShows = t
                    self.selectedTab = 1
                } else if t.isEmpty && !m.isEmpty {
                    self.movies = m
                    self.tvShows = m
                    self.selectedTab = 0
                } else if m.isEmpty && t.isEmpty {
                    self.movies = converted
                    self.tvShows = converted
                    self.selectedTab = 0
                } else {
                    self.movies = m
                    self.tvShows = t
                    self.selectedTab = 0
                }
                self.isLoading = false
            }
        } catch {
            print("Error loading studio list: \(error)")
            await MainActor.run {
                self.movies = []
                self.tvShows = []
                self.isLoading = false
            }
        }
    }
}

// MARK: - Browse Customize Sheet
struct BrowseCustomizeSheet: View {
    @ObservedObject private var storage = StorageService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var browseRows: [BrowseRowConfig] = []
    @State private var networkHubs: [NetworkHub] = []
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Networks Section - only show available in user's region
                Section {
                    ForEach($networkHubs.filter { storage.settings.region.isEmpty || $0.wrappedValue.regions.contains(storage.settings.region) }) { $hub in
                        HStack {
                            if let logoURL = hub.logoURL, let url = URL(string: logoURL) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .renderingMode(.template)
                                            .foregroundStyle(colorScheme == .light ? .black : .white)
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 50, height: 24)
                                    default:
                                        Text(hub.name)
                                            .fontWeight(.medium)
                                    }
                                }
                            } else {
                                Text(hub.name)
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $hub.isEnabled)
                                .labelsHidden()
                        }
                        .listRowBackground(
                            isIPad ? AnyView(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)) : AnyView(Color.clear)
                        )
                    }
                    .onMove { from, to in
                        networkHubs.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("Networks (Available in \(regionName))")
                } footer: {
                    Text("Drag to reorder, toggle to show/hide. Only services available in your region are shown.")
                }
                
                // Browse Rows Section
                Section {
                    ForEach($browseRows) { $row in
                        HStack {
                            Text(row.title)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Toggle("", isOn: $row.isEnabled)
                                .labelsHidden()
                        }
                        .listRowBackground(
                            isIPad ? AnyView(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)) : AnyView(Color.clear)
                        )
                    }
                    .onMove { from, to in
                        browseRows.move(fromOffsets: from, toOffset: to)
                        updateSortOrder()
                    }
                } header: {
                    Text("Content Rows")
                } footer: {
                    Text("Drag to reorder, toggle to show/hide")
                }
            }
            .scrollContentBackground(isIPad ? .hidden : .automatic)
            .background {
                if isIPad {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                }
            }
            .navigationTitle("Customize Browse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
            .onAppear {
                browseRows = storage.browseRows.sorted { $0.sortOrder < $1.sortOrder }
                networkHubs = storage.networkHubs.sorted { $0.sortOrder < $1.sortOrder }
            }
        }
    }
    
    private var regionName: String {
        let region = storage.settings.region
        let regionNames: [String: String] = [
            "US": "United States",
            "GB": "United Kingdom",
            "CA": "Canada",
            "AU": "Australia",
            "ZA": "South Africa",
            "DE": "Germany",
            "FR": "France",
            "JP": "Japan",
            "KR": "South Korea",
            "IN": "India",
            "BR": "Brazil",
            "NZ": "New Zealand",
            "NG": "Nigeria",
            "KE": "Kenya"
        ]
        return regionNames[region] ?? region
    }
    
    private func updateSortOrder() {
        for (index, _) in browseRows.enumerated() {
            browseRows[index].sortOrder = index
        }
    }
    
    private func saveChanges() {
        // Save browse rows
        var updatedRows = browseRows
        for (index, _) in updatedRows.enumerated() {
            updatedRows[index].sortOrder = index
        }
        storage.updateBrowseRows(updatedRows)
        
        // Save network hubs
        storage.reorderNetworkHubs(networkHubs)
    }
}

#Preview {
    BrowseView(selectedItem: .constant(nil))
}

