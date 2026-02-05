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
    @State private var showCustomizeSheet = false
    
    var body: some View {
        NavigationStack {
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
                    
                    // Studios Section
                    if !viewModel.studioHubs.isEmpty {
                        StudioHubsRow(studios: viewModel.studioHubs) { studio in
                            viewModel.selectedStudio = studio
                            showStudioHub = true
                        }
                        .padding(.top, 4)
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
                if let studio = viewModel.selectedStudio {
                    StudioHubSheet(studio: studio, selectedItem: $selectedItem)
                }
            }
            .sheet(isPresented: $showCustomizeSheet) {
                HomeCustomizationView()
            }
            .onChange(of: StorageService.shared.settings.heroCarouselSource) { _, _ in
                Task { await viewModel.refresh() }
            }
        }
    }
}

// MARK: - Studio Hub Model
struct StudioHub: Identifiable {
    let id: String
    let name: String
    let logoURL: String?
    let companyIds: [Int]
    
    static var defaultStudios: [StudioHub] {
        [
            StudioHub(id: "marvel", name: "Marvel Studios", logoURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b9/Marvel_Logo.svg/1200px-Marvel_Logo.svg.png", companyIds: [420]),
            StudioHub(id: "dc", name: "DC Studios", logoURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3d/DC_Comics_logo.svg/1200px-DC_Comics_logo.svg.png", companyIds: [128064, 174, 429]),
            StudioHub(id: "pixar", name: "Pixar", logoURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a4/Pixar_Animation_Studios_logo.svg/1200px-Pixar_Animation_Studios_logo.svg.png", companyIds: [3]),
            StudioHub(id: "disney", name: "Walt Disney Pictures", logoURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/6/6c/Walt_Disney_Pictures_2011_logo.svg/1200px-Walt_Disney_Pictures_2011_logo.svg.png", companyIds: [2]),
            StudioHub(id: "warner", name: "Warner Bros.", logoURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/6/64/Warner_Bros_logo.svg/1200px-Warner_Bros_logo.svg.png", companyIds: [174, 17, 429]),
            StudioHub(id: "universal", name: "Universal Pictures", logoURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/0/0f/Universal_Pictures_2024_%282%29.svg/1200px-Universal_Pictures_2024_%282%29.svg.png", companyIds: [33]),
            StudioHub(id: "paramount", name: "Paramount Pictures", logoURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/8/89/Paramount_Pictures_2022_%28Blue%29.svg/1200px-Paramount_Pictures_2022_%28Blue%29.svg.png", companyIds: [4]),
            StudioHub(id: "sony", name: "Sony Pictures", logoURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/d/d3/Sony_Pictures_Television_logo.svg/1200px-Sony_Pictures_Television_logo.svg.png", companyIds: [34]),
            StudioHub(id: "lionsgate", name: "Lionsgate", logoURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3e/Lionsgate_2024.svg/1200px-Lionsgate_2024.svg.png", companyIds: [1632]),
            StudioHub(id: "a24", name: "A24", logoURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/6/68/A24_Logo.svg/1200px-A24_Logo.svg.png", companyIds: [41077])
        ]
    }
}

// MARK: - Browse View Model
@MainActor
class BrowseViewModel: ObservableObject {
    @Published var heroItems: [MediaItem] = []
    @Published var rows: [MediaRow] = []
    @Published var networkHubs: [NetworkHub] = []
    @Published var studioHubs: [StudioHub] = []
    @Published var selectedStudio: StudioHub?
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
        
        // Load studio hubs
        studioHubs = StudioHub.defaultStudios
        
        // Load hero items based on user's selected source (concurrently)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadHeroItems() }
            group.addTask { await self.loadBrowseRows() }
        }
    }
    
    private func loadHeroItems() async {
        let source = StorageService.shared.settings.heroCarouselSource
        
        do {
            let items: [MediaItem]
            switch source {
            case .trendingMovies, .mdblistTrending:
                // Fallback mdblistTrending to trendingMovies
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
        // Wait for any in-flight load to finish to avoid clearing data mid-load
        while isLoading {
            try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s
        }

        rows = []
        heroItems = []
        networkHubs = []
        studioHubs = []
        await loadContent()
    }
    
    private func loadBrowseRows() async {
        var configs = StorageService.shared.browseRows.filter { $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
        
        // If no enabled configs, use defaults
        if configs.isEmpty {
            configs = BrowseRowConfig.defaultRows.filter { $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
        }
        
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
            return try await TMDBService.shared.getTrending(mediaType: .movie, timeWindow: "day").results
        case .trendingTV:
            return try await TMDBService.shared.getTrending(mediaType: .tv, timeWindow: "day").results
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
        
        // Skip Disney Channel since it requires MDBList (removed)
        if hub.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "disney channel" {
            await MainActor.run {
                self.movies = []
                self.tvShows = []
                self.isLoading = false
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



// MARK: - Studio Hubs Row
struct StudioHubsRow: View {
    let studios: [StudioHub]
    let onStudioTap: (StudioHub) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Studios")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(studios) { studio in
                        StudioHubCard(studio: studio)
                            .onTapGesture {
                                onStudioTap(studio)
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct StudioHubCard: View {
    let studio: StudioHub
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(width: 100, height: 56)
                
                if let logoURL = studio.logoURL, let url = URL(string: logoURL) {
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
                            Text(studio.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal, 4)
                        @unknown default:
                            Text(studio.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                } else {
                    Text(studio.name)
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

// MARK: - Studio Hub Sheet
struct StudioHubSheet: View {
    let studio: StudioHub
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var movies: [MediaItem] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                if let logoURL = studio.logoURL, let url = URL(string: logoURL) {
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
                            ForEach(movies) { item in
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
        
        do {
            let response = try await TMDBService.shared.discoverMoviesByCompany(companyIds: studio.companyIds)
            await MainActor.run { movies = response.results }
        } catch {
            print("Error loading studio movies: \(error)")
        }
        
        await MainActor.run { isLoading = false }
    }
}

// MARK: - Browse Customize Sheet (Legacy - kept for backwards compatibility)
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


