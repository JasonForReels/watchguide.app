import SwiftUI

struct MarvelHubView: View {
    @State private var movies: [MediaItem] = []
    @State private var loading = true
    @State private var selectedItem: MediaItem?
    @State private var selectedCollection: HubCollection?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let marvelCompanyId = 420
    private let marvelRed = Color(red: 0.9, green: 0.11, blue: 0.14)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    Color(red: 0.05, green: 0.0, blue: 0.0).ignoresSafeArea()
                    ProgressView().tint(marvelRed).scaleEffect(1.2)
                }
            } else {
                NavigationStack {
                    ZStack(alignment: .top) {
                        Color(red: 0.05, green: 0.0, blue: 0.0).ignoresSafeArea()
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                // Cinematic hero with red energy tint
                                heroSection
                                
                                // Marvel Studios logo with red glow
                                Image("Marvel Studios")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.white)
                                    .frame(height: 50)
                                    .shadow(color: marvelRed.opacity(0.7), radius: 25)
                                    .padding(.top, -50)
                                    .padding(.bottom, 8)
                                
                                // Cinematic red divider
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, marvelRed.opacity(0.6), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 1.5)
                                    .padding(.horizontal, 60)
                                    .padding(.bottom, 20)
                                
                                // Collections
                                if !collections.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 24) {
                                            ForEach(collections) { collection in
                                                FranchiseCircleButton(collection: collection) {
                                                    selectedCollection = collection
                                                }
                                            }
                                        }
                                        .padding(.horizontal, horizontalSizeClass == .regular ? 40 : 20)
                                    }
                                    .padding(.vertical, 20)
                                }
                                
                                VStack(spacing: horizontalSizeClass == .regular ? 64 : 32) {
                                    if !featuredItems.isEmpty {
                                        MediaRowView(
                                            title: "MCU Highlights",
                                            items: featuredItems,
                                            limit: 10,
                                            onItemTap: { selectedItem = $0 },
                                            isImmersiveStyle: true
                                        )
                                    }
                                    
                                    if !movieItems.isEmpty {
                                        MediaRowView(
                                            title: "Marvel Films",
                                            items: movieItems,
                                            limit: 15,
                                            onItemTap: { selectedItem = $0 },
                                            isImmersiveStyle: true
                                        )
                                    }
                                    
                                    if !seriesItems.isEmpty {
                                        MediaRowView(
                                            title: "Marvel Series",
                                            items: seriesItems,
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
                        
                        navBar
                    }
                    #if os(tvOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #elseif os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
                }
                .mediaDetailPresentation(item: $selectedItem)
                .fullScreenCover(item: $selectedCollection) { collection in
                    HubCollectionView(collection: collection)
                }
            }
        }
        .task { await loadContent() }
    }
    
    // MARK: - Sections
    
    private var heroSection: some View {
        HeroCarouselView(
            items: Array(movies.prefix(10)),
            onItemTap: { selectedItem = $0 },
            aspectRatio: horizontalSizeClass == .regular ? 16/9 : 10/12,
            isPortrait: horizontalSizeClass != .regular,
            isEdgeToEdge: true,
            externalVisibilityOverride: true,
            isImmersiveStyle: true
        )
        .overlay(
            ZStack {
                // Red-tinted cinematic gradient
                LinearGradient(
                    colors: [.clear, marvelRed.opacity(0.12), Color(red: 0.05, green: 0.0, blue: 0.0).opacity(0.9)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                // Subtle red vignette on edges
                RadialGradient(
                    colors: [.clear, marvelRed.opacity(0.08)],
                    center: .center,
                    startRadius: 200,
                    endRadius: 600
                )
                .blendMode(.screen)
            }
            .padding(.top, 200)
            .allowsHitTesting(false)
        )
    }
    
    private var navBar: some View {
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
    
    private var featuredItems: [MediaItem] { Array(movies.prefix(15)) }
    private var movieItems: [MediaItem] { movies.filter { $0.resolvedMediaType == .movie } }
    private var seriesItems: [MediaItem] { movies.filter { $0.resolvedMediaType == .tv } }

    // MARK: - Data Loading

    private func loadContent() async {
        loading = true
        do {
            let companyId = marvelCompanyId
            let finalItems: [MediaItem] = try await Task.detached(priority: .userInitiated) {
                var allFetchedItems: [MediaItem] = []
                var seenIds = Set<String>()

                func addBatch(_ items: [MediaItem]) {
                    for item in items {
                        let id = "\(item.resolvedMediaType.rawValue)-\(item.id)"
                        if !seenIds.contains(id) { seenIds.insert(id); allFetchedItems.append(item) }
                    }
                }

                let firstMoviePage = try await TMDBService.shared.discoverMoviesByCompany(companyIds: [companyId], page: 1)
                addBatch(firstMoviePage.results)
                let moviePages = min(firstMoviePage.totalPages ?? 1, 5)
                if moviePages > 1 {
                    try await withThrowingTaskGroup(of: [MediaItem].self) { group in
                        for page in 2...moviePages {
                            group.addTask { try await TMDBService.shared.discoverMoviesByCompany(companyIds: [companyId], page: page).results }
                        }
                        for try await r in group { addBatch(r) }
                    }
                }

                let firstTVPage = try await TMDBService.shared.discoverTVByCompany(companyIds: [companyId], page: 1)
                addBatch(firstTVPage.results)
                let tvPages = min(firstTVPage.totalPages ?? 1, 5)
                if tvPages > 1 {
                    try await withThrowingTaskGroup(of: [MediaItem].self) { group in
                        for page in 2...tvPages {
                            group.addTask { try await TMDBService.shared.discoverTVByCompany(companyIds: [companyId], page: page).results }
                        }
                        for try await r in group { addBatch(r) }
                    }
                }

                let now = Date()
                let filtered = allFetchedItems.filter { item in
                    let dateStr = item.releaseDate ?? item.firstAirDate ?? ""
                    if let date = TMDBService.shared.date(from: dateStr), date <= now {
                        return Calendar.current.component(.year, from: date) >= 2008
                    }
                    return false
                }
                return filtered.sorted {
                    ($0.releaseDate ?? $0.firstAirDate ?? "") > ($1.releaseDate ?? $1.firstAirDate ?? "")
                }
            }.value

            await MainActor.run {
                self.movies = finalItems
                self.loading = false
            }
        } catch {
            await MainActor.run { self.loading = false }
        }
    }
    
    private var collections: [HubCollection] {
        [
            HubCollection(
                id: 1001,
                name: "Avengers",
                logoAssetName: "",
                backgroundColor: marvelRed,
                customItems: [
                    .init(id: "24428", type: .movie),  // The Avengers
                    .init(id: "99861", type: .movie),  // Age of Ultron
                    .init(id: "299536", type: .movie), // Infinity War
                    .init(id: "299534", type: .movie)  // Endgame
                ]
            ),
            HubCollection(
                id: 1002,
                name: "Spider-Man",
                logoAssetName: "",
                backgroundColor: Color(red: 0.7, green: 0.1, blue: 0.1),
                customItems: [
                    .init(id: "315635", type: .movie), // Homecoming
                    .init(id: "429617", type: .movie), // Far From Home
                    .init(id: "634649", type: .movie)  // No Way Home
                ]
            ),
            HubCollection(
                id: 1003,
                name: "Guardians",
                logoAssetName: "",
                backgroundColor: Color(red: 0.2, green: 0.1, blue: 0.5),
                customItems: [
                    .init(id: "118340", type: .movie), // Guardians 1
                    .init(id: "283995", type: .movie), // Guardians 2
                    .init(id: "447365", type: .movie)  // Guardians 3
                ]
            )
        ]
    }
}
