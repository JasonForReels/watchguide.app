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
                
                // MDB Lists Rows
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

// MARK: - Browse View Model
@MainActor
class BrowseViewModel: ObservableObject {
    @Published var heroItems: [MediaItem] = []
    @Published var rows: [MediaRow] = []
    @Published var mdbListRows: [MediaRow] = []
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
        
        // Load hero items (trending)
        do {
            let trending = try await TMDBService.shared.getTrending(mediaType: .movie, timeWindow: "day")
            heroItems = Array(trending.results.prefix(10))
        } catch {
            print("Error loading hero: \(error)")
        }
        
        // Load all rows concurrently
        await loadBrowseRows()
        
        isLoading = false
    }
    
    func refresh() async {
        rows = []
        mdbListRows = []
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
