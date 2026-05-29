import SwiftUI

struct PixarHubView: View {
    @State private var movies: [MediaItem] = []
    @State private var loading = true
    @State private var selectedItem: MediaItem?
    @State private var selectedCollection: HubCollection?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let pixarCompanyId = 3
    private let pixarTeal = Color(red: 0.0, green: 0.35, blue: 0.55)
    private let pixarWarm = Color(red: 0.95, green: 0.75, blue: 0.25)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.0, green: 0.05, blue: 0.1), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    ProgressView().tint(pixarWarm).scaleEffect(1.2)
                }
            } else {
                NavigationStack {
                    ZStack(alignment: .top) {
                        Color(red: 0.0, green: 0.05, blue: 0.1).ignoresSafeArea()
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                heroSection
                                
                                // Pixar logo with warm lamp glow
                                Image("Pixar")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.white)
                                    .frame(height: 44)
                                    .shadow(color: pixarWarm.opacity(0.6), radius: 25)
                                    .padding(.top, -50)
                                    .padding(.bottom, 8)
                                
                                // Warm gradient accent bar
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, pixarWarm.opacity(0.4), pixarTeal.opacity(0.3), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 2)
                                    .padding(.horizontal, 40)
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
                                            title: "Pixar Favorites",
                                            items: featuredItems,
                                            limit: 10,
                                            onItemTap: { selectedItem = $0 },
                                            isImmersiveStyle: true
                                        )
                                    }
                                    
                                    if !movieItems.isEmpty {
                                        MediaRowView(title: "Feature Films", items: movieItems, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    
                                    if !seriesItems.isEmpty {
                                        MediaRowView(title: "Shorts & Series", items: seriesItems, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
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
                // Warm teal-to-dark gradient evoking Pixar's whimsical night skies
                LinearGradient(
                    colors: [.clear, pixarTeal.opacity(0.15), Color(red: 0.0, green: 0.05, blue: 0.1).opacity(0.95)],
                    startPoint: .center,
                    endPoint: .bottom
                )
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
            let companyId = pixarCompanyId
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
                
                let now = Date()
                let filtered = allFetchedItems.filter { item in
                    let dateStr = item.releaseDate ?? item.firstAirDate ?? ""
                    if let date = TMDBService.shared.date(from: dateStr) { return date <= now }
                    return true
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
                id: 3001,
                name: "Toy Story",
                logoAssetName: "",
                backgroundColor: Color(red: 0.1, green: 0.4, blue: 0.8),
                customItems: [
                    .init(id: "862", type: .movie),
                    .init(id: "863", type: .movie),
                    .init(id: "10193", type: .movie),
                    .init(id: "301528", type: .movie)
                ]
            ),
            HubCollection(
                id: 3002,
                name: "Cars",
                logoAssetName: "",
                backgroundColor: Color(red: 0.8, green: 0.1, blue: 0.1),
                customItems: [
                    .init(id: "920", type: .movie),
                    .init(id: "49013", type: .movie),
                    .init(id: "260514", type: .movie)
                ]
            ),
            HubCollection(
                id: 3003,
                name: "The Incredibles",
                logoAssetName: "",
                backgroundColor: Color(red: 0.9, green: 0.5, blue: 0.0),
                customItems: [
                    .init(id: "9806", type: .movie),
                    .init(id: "260513", type: .movie)
                ]
            )
        ]
    }
}
