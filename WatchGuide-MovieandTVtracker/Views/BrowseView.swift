//
//  BrowseView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct BrowseView: View {
    @StateObject private var viewModel = BrowseViewModel()
    @Binding var selectedItem: MediaItem?
    @State private var showCompanyHub = false
    @State private var selectedHub: CompanyHub?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Hero Carousel
                if !viewModel.heroItems.isEmpty {
                    HeroCarouselView(items: viewModel.heroItems) { item in
                        selectedItem = item
                    }
                }
                
                // Company Hubs Section
                if !viewModel.companyHubs.isEmpty {
                    CompanyHubsRow(hubs: viewModel.companyHubs) { hub in
                        selectedHub = hub
                        showCompanyHub = true
                    }
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
                    }
                }
                
                // MDB Lists Rows (for backward compatibility)
                ForEach(viewModel.mdbListRows, id: \.title) { row in
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
        .sheet(isPresented: $showCompanyHub) {
            if let hub = selectedHub {
                CompanyHubSheet(hub: hub, selectedItem: $selectedItem)
            }
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
                
                if row.rowType == .mdbList {
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
    @Published var mdbListRows: [MediaRow] = []
    @Published var customHomeRows: [CustomHomeRow] = []
    @Published var customRowContent: [String: MediaRow] = [:]
    @Published var companyHubs: [CompanyHub] = []
    @Published var isLoading = false
    
    struct MediaRow {
        let title: String
        let items: [MediaItem]
    }
    
    func loadContent() async {
        guard !isLoading else { return }
        isLoading = true
        
        // Load company hubs
        companyHubs = StorageService.shared.companyHubs.filter { $0.isEnabled }
        
        // Load custom home rows
        customHomeRows = StorageService.shared.getEnabledCustomHomeRows()
        
        // Load hero items based on user's selected source
        await loadHeroItems()
        
        // Load all rows concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadBrowseRows() }
            group.addTask { await self.loadCustomHomeRowContent() }
            group.addTask { await self.loadMDBListRows() }
        }
        
        isLoading = false
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
            }
            heroItems = Array(items.prefix(10))
        } catch {
            print("Error loading hero: \(error)")
        }
    }
    
    func refresh() async {
        rows = []
        mdbListRows = []
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
            case .mdbList:
                if let mdbListId = customRow.mdbListId,
                   let mdbList = StorageService.shared.mdbLists.first(where: { $0.id == mdbListId }) {
                    // Convert SavedMediaItems to MediaItems
                    let items = mdbList.items.map { saved -> MediaItem in
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
                if let items = customRow.items {
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
    
    private func loadMDBListRows() async {
        // Load MDBLists that are set to show on home but don't have a custom row
        let mdbListsOnHome = StorageService.shared.getMDBListsForHome()
        let customRowMDBListIds = Set(customHomeRows.compactMap { $0.mdbListId })
        
        var loadedRows: [MediaRow] = []
        
        for mdbList in mdbListsOnHome {
            // Skip if already in custom rows
            if customRowMDBListIds.contains(mdbList.id) { continue }
            
            let items = mdbList.items.map { saved -> MediaItem in
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
                loadedRows.append(MediaRow(title: mdbList.displayName, items: items))
            }
        }
        
        mdbListRows = loadedRows
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

// MARK: - Company Hubs Row
struct CompanyHubsRow: View {
    let hubs: [CompanyHub]
    let onHubTap: (CompanyHub) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Studios & Networks")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(hubs) { hub in
                        CompanyHubCard(hub: hub)
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

struct CompanyHubCard: View {
    let hub: CompanyHub
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 56)
                
                Text(hub.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
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

// MARK: - Company Hub Sheet
struct CompanyHubSheet: View {
    let hub: CompanyHub
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @State private var movies: [MediaItem] = []
    @State private var tvShows: [MediaItem] = []
    @State private var isLoading = true
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
        isLoading = true
        
        // Load movies
        if !hub.companyIds.isEmpty {
            do {
                let response = try await TMDBService.shared.discoverMoviesByCompany(companyIds: hub.companyIds)
                movies = response.results
            } catch {
                print("Error loading movies: \(error)")
            }
        }
        
        // Load TV shows
        if !hub.networkIds.isEmpty {
            do {
                let response = try await TMDBService.shared.discoverTVByNetwork(networkIds: hub.networkIds)
                tvShows = response.results
            } catch {
                print("Error loading TV: \(error)")
            }
        } else if !hub.companyIds.isEmpty {
            do {
                let response = try await TMDBService.shared.discoverTVByCompany(companyIds: hub.companyIds)
                tvShows = response.results
            } catch {
                print("Error loading TV: \(error)")
            }
        }
        
        isLoading = false
    }
}

#Preview {
    BrowseView(selectedItem: .constant(nil))
}
