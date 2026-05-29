//
//  StreamingHubViews.swift
//  WatchGuide-MovieandTVtracker
//
//  Unique hub views for each major streaming service.
//

import SwiftUI

// MARK: - Shared Streaming Hub Data Loader

private func loadStreamingContent(providerIds: [Int], networkIds: [Int] = []) async throws -> [MediaItem] {
    let region = StorageService.shared.settings.region.isEmpty ? "US" : StorageService.shared.settings.region
    
    return try await Task.detached(priority: .userInitiated) {
        var allItems: [MediaItem] = []
        var seenIds = Set<String>()
        
        func addBatch(_ items: [MediaItem]) {
            for item in items {
                let id = "\(item.resolvedMediaType.rawValue)-\(item.id)"
                if !seenIds.contains(id) {
                    seenIds.insert(id)
                    allItems.append(item)
                }
            }
        }
        
        // Fetch movies by provider
        if !providerIds.isEmpty {
            let firstMoviePage = try await TMDBService.shared.discoverMoviesWithProvider(providerIds: providerIds, region: region, page: 1)
            addBatch(firstMoviePage.results)
            let moviePages = min(firstMoviePage.totalPages ?? 1, 3)
            if moviePages > 1 {
                try await withThrowingTaskGroup(of: [MediaItem].self) { group in
                    for page in 2...moviePages {
                        group.addTask {
                            try await TMDBService.shared.discoverMoviesWithProvider(providerIds: providerIds, region: region, page: page).results
                        }
                    }
                    for try await r in group { addBatch(r) }
                }
            }
            
            // Fetch TV by provider
            let firstTVPage = try await TMDBService.shared.discoverTVWithProvider(providerIds: providerIds, region: region, page: 1)
            addBatch(firstTVPage.results)
            let tvPages = min(firstTVPage.totalPages ?? 1, 3)
            if tvPages > 1 {
                try await withThrowingTaskGroup(of: [MediaItem].self) { group in
                    for page in 2...tvPages {
                        group.addTask {
                            try await TMDBService.shared.discoverTVWithProvider(providerIds: providerIds, region: region, page: page).results
                        }
                    }
                    for try await r in group { addBatch(r) }
                }
            }
        }
        
        // Also fetch TV by network IDs if available
        if !networkIds.isEmpty {
            let firstNetPage = try await TMDBService.shared.discoverTVByNetwork(networkIds: networkIds, page: 1)
            addBatch(firstNetPage.results)
            let netPages = min(firstNetPage.totalPages ?? 1, 3)
            if netPages > 1 {
                try await withThrowingTaskGroup(of: [MediaItem].self) { group in
                    for page in 2...netPages {
                        group.addTask {
                            try await TMDBService.shared.discoverTVByNetwork(networkIds: networkIds, page: page).results
                        }
                    }
                    for try await r in group { addBatch(r) }
                }
            }
        }
        
        // Filter unreleased and sort by popularity
        let now = Date()
        let filtered = allItems.filter { item in
            let dateStr = item.releaseDate ?? item.firstAirDate ?? ""
            if let date = TMDBService.shared.date(from: dateStr) {
                return date <= now
            }
            return true
        }
        return filtered.sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
    }.value
}


// MARK: - Netflix Hub
// Design: Cinematic dark with signature red accents, dramatic gradient overlays

struct NetflixHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true
    @State private var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private let brandRed = Color(red: 0.89, green: 0.07, blue: 0.13)
    
    var body: some View {
        Group {
            if loading {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView().tint(brandRed).scaleEffect(1.2)
                }
            } else {
                NavigationStack {
                    ZStack(alignment: .top) {
                        Color.black.ignoresSafeArea()
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                // Cinematic hero with red tinted gradient
                                netflixHero
                                
                                // Netflix "N" Logo
                                netflixLogo
                                
                                VStack(spacing: horizontalSizeClass == .regular ? 64 : 32) {
                                    if !featuredItems.isEmpty {
                                        MediaRowView(
                                            title: "Top Picks",
                                            items: featuredItems,
                                            limit: 10,
                                            onItemTap: { selectedItem = $0 },
                                            isImmersiveStyle: true
                                        )
                                    }
                                    
                                    if !movies.isEmpty {
                                        MediaRowView(
                                            title: "Movies",
                                            items: movies,
                                            limit: 15,
                                            onItemTap: { selectedItem = $0 },
                                            isImmersiveStyle: true
                                        )
                                    }
                                    
                                    if !series.isEmpty {
                                        MediaRowView(
                                            title: "Series",
                                            items: series,
                                            limit: 15,
                                            onItemTap: { selectedItem = $0 },
                                            isImmersiveStyle: true
                                        )
                                    }
                                    
                                    Color.clear.frame(height: 100)
                                }
                                .padding(.top, horizontalSizeClass == .regular ? 40 : 20)
                            }
                        }
                        .scrollIndicators(.hidden)
                        #if os(iOS)
                        .ignoresSafeArea(edges: .top)
                        #endif
                        
                        dismissBar
                    }
                    #if os(tvOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #elseif os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
                }
                .mediaDetailPresentation(item: $selectedItem)
            }
        }
        .task { await loadContent() }
    }
    
    private var netflixHero: some View {
        HeroCarouselView(
            items: Array(items.prefix(10)),
            onItemTap: { selectedItem = $0 },
            aspectRatio: horizontalSizeClass == .regular ? 16/9 : 10/12,
            isPortrait: horizontalSizeClass != .regular,
            isEdgeToEdge: true,
            externalVisibilityOverride: true,
            isImmersiveStyle: true
        )
        .overlay(
            LinearGradient(
                colors: [.clear, brandRed.opacity(0.15), Color.black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            .padding(.top, 200)
            .allowsHitTesting(false)
        )
    }
    
    private var netflixLogo: some View {
        Image("Netflix_Logomark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 50)
            .shadow(color: brandRed.opacity(0.6), radius: 20)
            .padding(.top, -50)
            .padding(.bottom, 20)
    }
    
    private var dismissBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 60 : 20)
        .padding(.top, horizontalSizeClass == .regular ? 80 : 50)
        .background(
            LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
    
    private var featuredItems: [MediaItem] { Array(items.prefix(15)) }
    private var movies: [MediaItem] { items.filter { $0.resolvedMediaType == .movie } }
    private var series: [MediaItem] { items.filter { $0.resolvedMediaType == .tv } }
    
    private func loadContent() async {
        loading = true
        do {
            // Netflix: provider 8, network 213
            items = try await loadStreamingContent(providerIds: [8], networkIds: [213])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Disney+ Hub
// Design: Enchanted midnight blue with starfield-inspired accents and magical gradients

struct DisneyPlusHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true
    @State private var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private let brandBlue = Color(red: 0.04, green: 0.11, blue: 0.42)
    private let accentBlue = Color(red: 0.11, green: 0.33, blue: 0.87)
    
    var body: some View {
        Group {
            if loading {
                ZStack {
                    LinearGradient(colors: [brandBlue, Color.black], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.2)
                }
            } else {
                NavigationStack {
                    ZStack(alignment: .top) {
                        LinearGradient(colors: [brandBlue.opacity(0.4), Color.black], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                disneyHero
                                
                                // Disney+ logo
                                Image("Disney+_2024")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.white)
                                    .frame(height: 50)
                                    .shadow(color: accentBlue.opacity(0.8), radius: 30)
                                    .padding(.top, -50)
                                    .padding(.bottom, 20)
                                
                                VStack(spacing: horizontalSizeClass == .regular ? 64 : 32) {
                                    if !featuredItems.isEmpty {
                                        MediaRowView(
                                            title: "Featured",
                                            items: featuredItems,
                                            limit: 10,
                                            onItemTap: { selectedItem = $0 },
                                            isImmersiveStyle: true
                                        )
                                    }
                                    if !movies.isEmpty {
                                        MediaRowView(title: "Movies", items: movies, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    if !series.isEmpty {
                                        MediaRowView(title: "Series", items: series, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    Color.clear.frame(height: 100)
                                }
                                .padding(.top, horizontalSizeClass == .regular ? 40 : 20)
                            }
                        }
                        .scrollIndicators(.hidden)
                        #if os(iOS)
                        .ignoresSafeArea(edges: .top)
                        #endif
                        
                        dismissBar(accentColor: accentBlue)
                    }
                    #if os(tvOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #elseif os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
                }
                .mediaDetailPresentation(item: $selectedItem)
            }
        }
        .task { await loadContent() }
    }
    
    private var disneyHero: some View {
        HeroCarouselView(
            items: Array(items.prefix(10)),
            onItemTap: { selectedItem = $0 },
            aspectRatio: horizontalSizeClass == .regular ? 16/9 : 10/12,
            isPortrait: horizontalSizeClass != .regular,
            isEdgeToEdge: true,
            externalVisibilityOverride: true,
            isImmersiveStyle: true
        )
        .overlay(
            LinearGradient(
                colors: [.clear, brandBlue.opacity(0.3), Color.black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            .padding(.top, 200)
            .allowsHitTesting(false)
        )
    }
    
    private var featuredItems: [MediaItem] { Array(items.prefix(15)) }
    private var movies: [MediaItem] { items.filter { $0.resolvedMediaType == .movie } }
    private var series: [MediaItem] { items.filter { $0.resolvedMediaType == .tv } }
    
    private func loadContent() async {
        loading = true
        do {
            // Disney+: provider 337, network 2739
            items = try await loadStreamingContent(providerIds: [337], networkIds: [2739])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - HBO Max Hub
// Design: Rich purple-to-black atmosphere, bold typography, prestige cinema feel

struct HBOMaxHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true
    @State private var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private let brandPurple = Color(red: 0.29, green: 0.09, blue: 0.55)
    private let brandBlue = Color(red: 0.0, green: 0.21, blue: 0.69)
    
    var body: some View {
        Group {
            if loading {
                ZStack {
                    LinearGradient(colors: [brandPurple.opacity(0.6), Color.black], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.2)
                }
            } else {
                NavigationStack {
                    ZStack(alignment: .top) {
                        Color.black.ignoresSafeArea()
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                hboHero
                                
                                // Max logo
                                Image("HBO_Max_(2025)")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.white)
                                    .frame(height: 40)
                                    .shadow(color: brandPurple.opacity(0.7), radius: 25)
                                    .padding(.top, -50)
                                    .padding(.bottom, 20)
                                
                                VStack(spacing: horizontalSizeClass == .regular ? 64 : 32) {
                                    if !featuredItems.isEmpty {
                                        MediaRowView(title: "Prestige Picks", items: featuredItems, limit: 10, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    if !movies.isEmpty {
                                        MediaRowView(title: "Films", items: movies, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    if !series.isEmpty {
                                        MediaRowView(title: "Originals & Series", items: series, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    Color.clear.frame(height: 100)
                                }
                                .padding(.top, horizontalSizeClass == .regular ? 40 : 20)
                            }
                        }
                        .scrollIndicators(.hidden)
                        #if os(iOS)
                        .ignoresSafeArea(edges: .top)
                        #endif
                        
                        dismissBar(accentColor: brandPurple)
                    }
                    #if os(tvOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #elseif os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
                }
                .mediaDetailPresentation(item: $selectedItem)
            }
        }
        .task { await loadContent() }
    }
    
    private var hboHero: some View {
        HeroCarouselView(
            items: Array(items.prefix(10)),
            onItemTap: { selectedItem = $0 },
            aspectRatio: horizontalSizeClass == .regular ? 16/9 : 10/12,
            isPortrait: horizontalSizeClass != .regular,
            isEdgeToEdge: true,
            externalVisibilityOverride: true,
            isImmersiveStyle: true
        )
        .overlay(
            ZStack {
                // Diagonal prestige gradient
                LinearGradient(
                    colors: [.clear, brandPurple.opacity(0.2), Color.black.opacity(0.9)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .padding(.top, 200)
            .allowsHitTesting(false)
        )
    }
    
    private var featuredItems: [MediaItem] { Array(items.prefix(15)) }
    private var movies: [MediaItem] { items.filter { $0.resolvedMediaType == .movie } }
    private var series: [MediaItem] { items.filter { $0.resolvedMediaType == .tv } }
    
    private func loadContent() async {
        loading = true
        do {
            // HBO Max / Max: provider 1899 (Max), network 49 (HBO)
            items = try await loadStreamingContent(providerIds: [1899], networkIds: [49])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Paramount+ Hub
// Design: Mountain-peak inspired, deep blue gradient with crisp white accents

struct ParamountPlusHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true
    @State private var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private let brandBlue = Color(red: 0.0, green: 0.33, blue: 0.87)
    
    var body: some View {
        Group {
            if loading {
                ZStack {
                    LinearGradient(colors: [brandBlue.opacity(0.5), Color.black], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.2)
                }
            } else {
                NavigationStack {
                    ZStack(alignment: .top) {
                        LinearGradient(colors: [brandBlue.opacity(0.15), Color.black], startPoint: .top, endPoint: .center)
                            .ignoresSafeArea()
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                paramountHero
                                
                                // Paramount+ logo
                                Image("Paramount+_logo")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.white)
                                    .frame(height: 44)
                                    .shadow(color: brandBlue.opacity(0.6), radius: 20)
                                    .padding(.top, -50)
                                    .padding(.bottom, 20)
                                
                                VStack(spacing: horizontalSizeClass == .regular ? 64 : 32) {
                                    if !featuredItems.isEmpty {
                                        MediaRowView(title: "Trending", items: featuredItems, limit: 10, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    if !movies.isEmpty {
                                        MediaRowView(title: "Movies", items: movies, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    if !series.isEmpty {
                                        MediaRowView(title: "Series", items: series, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    Color.clear.frame(height: 100)
                                }
                                .padding(.top, horizontalSizeClass == .regular ? 40 : 20)
                            }
                        }
                        .scrollIndicators(.hidden)
                        #if os(iOS)
                        .ignoresSafeArea(edges: .top)
                        #endif
                        
                        dismissBar(accentColor: brandBlue)
                    }
                    #if os(tvOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #elseif os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
                }
                .mediaDetailPresentation(item: $selectedItem)
            }
        }
        .task { await loadContent() }
    }
    
    private var paramountHero: some View {
        HeroCarouselView(
            items: Array(items.prefix(10)),
            onItemTap: { selectedItem = $0 },
            aspectRatio: horizontalSizeClass == .regular ? 16/9 : 10/12,
            isPortrait: horizontalSizeClass != .regular,
            isEdgeToEdge: true,
            externalVisibilityOverride: true,
            isImmersiveStyle: true
        )
        .overlay(
            LinearGradient(
                colors: [.clear, brandBlue.opacity(0.15), Color.black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            .padding(.top, 200)
            .allowsHitTesting(false)
        )
    }
    
    private var featuredItems: [MediaItem] { Array(items.prefix(15)) }
    private var movies: [MediaItem] { items.filter { $0.resolvedMediaType == .movie } }
    private var series: [MediaItem] { items.filter { $0.resolvedMediaType == .tv } }
    
    private func loadContent() async {
        loading = true
        do {
            // Paramount+: provider 531, network 4330
            items = try await loadStreamingContent(providerIds: [531], networkIds: [4330])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Apple TV+ Hub
// Design: Clean minimalist black with subtle warm white accents, Apple-esque editorial layout

struct AppleTVPlusHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true
    @State private var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private let warmGray = Color(red: 0.65, green: 0.65, blue: 0.67)
    
    var body: some View {
        Group {
            if loading {
                ZStack {
                    Color(red: 0.06, green: 0.06, blue: 0.06).ignoresSafeArea()
                    ProgressView().tint(warmGray).scaleEffect(1.2)
                }
            } else {
                NavigationStack {
                    ZStack(alignment: .top) {
                        Color(red: 0.06, green: 0.06, blue: 0.06).ignoresSafeArea()
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                appleHero
                                
                                // Apple TV+ wordmark
                                HStack(spacing: 6) {
                                    Image(systemName: "appletv.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.white)
                                }
                                .shadow(color: warmGray.opacity(0.3), radius: 15)
                                .padding(.top, -45)
                                .padding(.bottom, 20)
                                
                                VStack(spacing: horizontalSizeClass == .regular ? 64 : 32) {
                                    if !featuredItems.isEmpty {
                                        MediaRowView(title: "Editor's Picks", items: featuredItems, limit: 10, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    if !movies.isEmpty {
                                        MediaRowView(title: "Films", items: movies, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    if !series.isEmpty {
                                        MediaRowView(title: "Apple Originals", items: series, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    Color.clear.frame(height: 100)
                                }
                                .padding(.top, horizontalSizeClass == .regular ? 40 : 20)
                            }
                        }
                        .scrollIndicators(.hidden)
                        #if os(iOS)
                        .ignoresSafeArea(edges: .top)
                        #endif
                        
                        dismissBar(accentColor: warmGray)
                    }
                    #if os(tvOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #elseif os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
                }
                .mediaDetailPresentation(item: $selectedItem)
            }
        }
        .task { await loadContent() }
    }
    
    private var appleHero: some View {
        HeroCarouselView(
            items: Array(items.prefix(10)),
            onItemTap: { selectedItem = $0 },
            aspectRatio: horizontalSizeClass == .regular ? 16/9 : 10/12,
            isPortrait: horizontalSizeClass != .regular,
            isEdgeToEdge: true,
            externalVisibilityOverride: true,
            isImmersiveStyle: true
        )
        .overlay(
            LinearGradient(
                colors: [.clear, Color(red: 0.06, green: 0.06, blue: 0.06).opacity(0.5), Color(red: 0.06, green: 0.06, blue: 0.06)],
                startPoint: .center,
                endPoint: .bottom
            )
            .padding(.top, 200)
            .allowsHitTesting(false)
        )
    }
    
    private var featuredItems: [MediaItem] { Array(items.prefix(15)) }
    private var movies: [MediaItem] { items.filter { $0.resolvedMediaType == .movie } }
    private var series: [MediaItem] { items.filter { $0.resolvedMediaType == .tv } }
    
    private func loadContent() async {
        loading = true
        do {
            // Apple TV+: provider 350, network 2552
            items = try await loadStreamingContent(providerIds: [350], networkIds: [2552])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Peacock Hub
// Design: Vibrant gradient fan inspired by the Peacock feather motif

struct PeacockHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true
    @State private var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private let peacockGreen = Color(red: 0.0, green: 0.65, blue: 0.45)
    private let peacockBlue = Color(red: 0.0, green: 0.35, blue: 0.7)
    
    var body: some View {
        Group {
            if loading {
                ZStack {
                    LinearGradient(colors: [peacockBlue.opacity(0.4), Color.black], startPoint: .topTrailing, endPoint: .bottomLeading)
                        .ignoresSafeArea()
                    ProgressView().tint(peacockGreen).scaleEffect(1.2)
                }
            } else {
                NavigationStack {
                    ZStack(alignment: .top) {
                        Color.black.ignoresSafeArea()
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                peacockHero
                                
                                // Peacock wordmark
                                Text("PEACOCK")
                                    .font(.system(size: 26, weight: .black, design: .default))
                                    .tracking(6)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [peacockGreen, peacockBlue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: peacockGreen.opacity(0.4), radius: 15)
                                    .padding(.top, -45)
                                    .padding(.bottom, 20)
                                
                                VStack(spacing: horizontalSizeClass == .regular ? 64 : 32) {
                                    if !featuredItems.isEmpty {
                                        MediaRowView(title: "Popular Now", items: featuredItems, limit: 10, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    if !movies.isEmpty {
                                        MediaRowView(title: "Movies", items: movies, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    if !series.isEmpty {
                                        MediaRowView(title: "Shows", items: series, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    Color.clear.frame(height: 100)
                                }
                                .padding(.top, horizontalSizeClass == .regular ? 40 : 20)
                            }
                        }
                        .scrollIndicators(.hidden)
                        #if os(iOS)
                        .ignoresSafeArea(edges: .top)
                        #endif
                        
                        dismissBar(accentColor: peacockGreen)
                    }
                    #if os(tvOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #elseif os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
                }
                .mediaDetailPresentation(item: $selectedItem)
            }
        }
        .task { await loadContent() }
    }
    
    private var peacockHero: some View {
        HeroCarouselView(
            items: Array(items.prefix(10)),
            onItemTap: { selectedItem = $0 },
            aspectRatio: horizontalSizeClass == .regular ? 16/9 : 10/12,
            isPortrait: horizontalSizeClass != .regular,
            isEdgeToEdge: true,
            externalVisibilityOverride: true,
            isImmersiveStyle: true
        )
        .overlay(
            LinearGradient(
                colors: [.clear, peacockBlue.opacity(0.15), Color.black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            .padding(.top, 200)
            .allowsHitTesting(false)
        )
    }
    
    private var featuredItems: [MediaItem] { Array(items.prefix(15)) }
    private var movies: [MediaItem] { items.filter { $0.resolvedMediaType == .movie } }
    private var series: [MediaItem] { items.filter { $0.resolvedMediaType == .tv } }
    
    private func loadContent() async {
        loading = true
        do {
            // Peacock: provider 386, network 3353
            items = try await loadStreamingContent(providerIds: [386], networkIds: [3353])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Shared Dismiss Bar

private func dismissBar(accentColor: Color) -> some View {
    StreamingDismissBar(accentColor: accentColor)
}

private struct StreamingDismissBar: View {
    let accentColor: Color
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 60 : 20)
        .padding(.top, horizontalSizeClass == .regular ? 80 : 50)
        .background(
            LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}
