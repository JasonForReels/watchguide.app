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
    @State private var showTwentiethCenturySheet = false
    @State private var showWarnerBrosSheet = false
    @State private var showDreamWorksSheet = false
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
                    
                    // Browse Rows with 20th Century Studios button inserted
                    ForEach(Array(viewModel.rows.enumerated()), id: \.element.title) { index, row in
                        if !row.items.isEmpty {
                            MediaRowView(
                                title: row.title,
                                items: row.items,
                                onItemTap: { item in
                                    selectedItem = item
                                }
                            )
                        }
                        
                        // Insert Studios buttons after Trending TV Shows row
                        if row.title == "Trending TV Shows" {
                            StudiosHubRow(
                                onTwentiethCenturyTap: {
                                    showTwentiethCenturySheet = true
                                },
                                onWarnerBrosTap: {
                                    showWarnerBrosSheet = true
                                },
                                onDreamWorksTap: {
                                    showDreamWorksSheet = true
                                }
                            )
                            .padding(.horizontal)
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
            .sheet(isPresented: $showTwentiethCenturySheet) {
                TwentiethCenturyStudiosSheet(selectedItem: $selectedItem)
            }
            .sheet(isPresented: $showWarnerBrosSheet) {
                WarnerBrosSheet(selectedItem: $selectedItem)
            }
            .sheet(isPresented: $showDreamWorksSheet) {
                DreamWorksSheet(selectedItem: $selectedItem)
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

// MARK: - Studios Hub Row
struct StudiosHubRow: View {
    let onTwentiethCenturyTap: () -> Void
    let onWarnerBrosTap: () -> Void
    let onDreamWorksTap: () -> Void
    
    var body: some View {
        HStack(spacing: 32) {
            TwentiethCenturyStudiosButton(action: onTwentiethCenturyTap)
            WarnerBrosButton(action: onWarnerBrosTap)
            DreamWorksButton(action: onDreamWorksTap)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - 20th Century Studios Button
struct TwentiethCenturyStudiosButton: View {
    let action: () -> Void
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.15), radius: isPressed ? 8 : 4, y: isPressed ? 4 : 2)
                    
                    AsyncImage(url: URL(string: "https://i.ibb.co/0VZ8BZdZ/20th-century-studios-seeklogo.png")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 60, height: 60)
                        case .failure, .empty:
                            Text("20th")
                                .font(.caption)
                                .fontWeight(.bold)
                        @unknown default:
                            ProgressView()
                        }
                    }
                }
                .scaleEffect(isPressed ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            
            Text("20th Century")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Warner Bros Button
struct WarnerBrosButton: View {
    let action: () -> Void
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.15), radius: isPressed ? 8 : 4, y: isPressed ? 4 : 2)
                    
                    AsyncImage(url: URL(string: "https://i.ibb.co/wZ1HR70w/Pik-Png-com-warner-bros-logo-png-1514023.png")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 60, height: 60)
                        case .failure, .empty:
                            Text("WB")
                                .font(.caption)
                                .fontWeight(.bold)
                        @unknown default:
                            ProgressView()
                        }
                    }
                }
                .scaleEffect(isPressed ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            
            Text("Warner Bros")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - DreamWorks Button
struct DreamWorksButton: View {
    let action: () -> Void
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.15), radius: isPressed ? 8 : 4, y: isPressed ? 4 : 2)
                    
                    AsyncImage(url: URL(string: "https://i.ibb.co/ZRKVxnCG/Dream-Works-Animation-2016-Moon-Boy-svg.png")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 60, height: 60)
                        case .failure, .empty:
                            Text("DW")
                                .font(.caption)
                                .fontWeight(.bold)
                        @unknown default:
                            ProgressView()
                        }
                    }
                }
                .scaleEffect(isPressed ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            
            Text("DreamWorks")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 20th Century Studios Sheet
struct TwentiethCenturyStudiosSheet: View {
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var allItems: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedTab = 0
    
    private var movies: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .movie }
    }
    
    private var tvShows: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .tv }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                AsyncImage(url: URL(string: "https://i.ibb.co/0VZ8BZdZ/20th-century-studios-seeklogo.png")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60)
                    default:
                        EmptyView()
                    }
                }
                .padding(.vertical, 16)
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    let items = selectedTab == 0 ? movies : tvShows
                    
                    if items.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: selectedTab == 0 ? "film" : "tv")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No \(selectedTab == 0 ? "movies" : "TV shows") found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                            ], spacing: 20) {
                                ForEach(items) { item in
                                    SavedMediaPosterCard(item: item)
                                        .onTapGesture {
                                            // Convert SavedMediaItem to MediaItem
                                            let mediaItem = MediaItem(
                                                id: item.mediaId,
                                                title: item.mediaType == .movie ? item.title : nil,
                                                name: item.mediaType == .tv ? item.title : nil,
                                                originalTitle: nil,
                                                originalName: nil,
                                                overview: item.overview,
                                                posterPath: item.posterPath,
                                                backdropPath: item.backdropPath,
                                                releaseDate: item.year,
                                                firstAirDate: item.year,
                                                voteAverage: item.voteAverage,
                                                voteCount: nil,
                                                popularity: nil,
                                                genreIds: nil,
                                                mediaType: item.mediaType.rawValue,
                                                adult: nil,
                                                originalLanguage: nil
                                            )
                                            selectedItem = mediaItem
                                            dismiss()
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("20th Century Studios")
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
        error = nil
        
        do {
            // Fetch from MDBList: dualipafan01/20th-century-studios
            allItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: "dualipafan01/20th-century-studios")
            if allItems.isEmpty {
                error = "No content found in this list."
            }
        } catch {
            self.error = "Failed to load content. Please try again."
            print("20th Century Studios error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Warner Bros Sheet
struct WarnerBrosSheet: View {
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var allItems: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedTab = 0
    
    private var movies: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .movie }
    }
    
    private var tvShows: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .tv }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                AsyncImage(url: URL(string: "https://i.ibb.co/wZ1HR70w/Pik-Png-com-warner-bros-logo-png-1514023.png")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60)
                    default:
                        EmptyView()
                    }
                }
                .padding(.vertical, 16)
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    let items = selectedTab == 0 ? movies : tvShows
                    
                    if items.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: selectedTab == 0 ? "film" : "tv")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No \(selectedTab == 0 ? "movies" : "TV shows") found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                            ], spacing: 20) {
                                ForEach(items) { item in
                                    SavedMediaPosterCard(item: item)
                                        .onTapGesture {
                                            // Convert SavedMediaItem to MediaItem
                                            let mediaItem = MediaItem(
                                                id: item.mediaId,
                                                title: item.mediaType == .movie ? item.title : nil,
                                                name: item.mediaType == .tv ? item.title : nil,
                                                originalTitle: nil,
                                                originalName: nil,
                                                overview: item.overview,
                                                posterPath: item.posterPath,
                                                backdropPath: item.backdropPath,
                                                releaseDate: item.year,
                                                firstAirDate: item.year,
                                                voteAverage: item.voteAverage,
                                                voteCount: nil,
                                                popularity: nil,
                                                genreIds: nil,
                                                mediaType: item.mediaType.rawValue,
                                                adult: nil,
                                                originalLanguage: nil
                                            )
                                            selectedItem = mediaItem
                                            dismiss()
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Warner Bros")
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
        error = nil
        
        do {
            // Fetch from MDBList: dualipafan01/warner-bros
            allItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: "dualipafan01/warner-bros")
            if allItems.isEmpty {
                error = "No content found in this list."
            }
        } catch {
            self.error = "Failed to load content. Please try again."
            print("Warner Bros error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - DreamWorks Sheet
struct DreamWorksSheet: View {
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var allItems: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedTab = 0
    
    private var movies: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .movie }
    }
    
    private var tvShows: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .tv }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                AsyncImage(url: URL(string: "https://i.ibb.co/ZRKVxnCG/Dream-Works-Animation-2016-Moon-Boy-svg.png")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60)
                    default:
                        EmptyView()
                    }
                }
                .padding(.vertical, 16)
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    let items = selectedTab == 0 ? movies : tvShows
                    
                    if items.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: selectedTab == 0 ? "film" : "tv")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No \(selectedTab == 0 ? "movies" : "TV shows") found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                            ], spacing: 20) {
                                ForEach(items) { item in
                                    SavedMediaPosterCard(item: item)
                                        .onTapGesture {
                                            // Convert SavedMediaItem to MediaItem
                                            let mediaItem = MediaItem(
                                                id: item.mediaId,
                                                title: item.mediaType == .movie ? item.title : nil,
                                                name: item.mediaType == .tv ? item.title : nil,
                                                originalTitle: nil,
                                                originalName: nil,
                                                overview: item.overview,
                                                posterPath: item.posterPath,
                                                backdropPath: item.backdropPath,
                                                releaseDate: item.year,
                                                firstAirDate: item.year,
                                                voteAverage: item.voteAverage,
                                                voteCount: nil,
                                                popularity: nil,
                                                genreIds: nil,
                                                mediaType: item.mediaType.rawValue,
                                                adult: nil,
                                                originalLanguage: nil
                                            )
                                            selectedItem = mediaItem
                                            dismiss()
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("DreamWorks")
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
        error = nil
        
        do {
            // Fetch from MDBList: dualipafan01/dreamworks
            allItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: "dualipafan01/dreamworks")
            if allItems.isEmpty {
                error = "No content found in this list."
            }
        } catch {
            self.error = "Failed to load content. Please try again."
            print("DreamWorks error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Browse View Model
@MainActor
class BrowseViewModel: ObservableObject {
    @Published var heroItems: [MediaItem] = []
    @Published var rows: [MediaRow] = []
    @Published var networkHubs: [NetworkHub] = []
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


