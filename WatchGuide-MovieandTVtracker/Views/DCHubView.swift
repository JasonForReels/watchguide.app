import SwiftUI

struct DCHubView: View {
    @State private var movies: [MediaItem] = []
    @State private var loading = true
    @State private var selectedItem: MediaItem?
    @State private var selectedCollection: HubCollection?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dcCompanyIds = [429, 184898]
    private let dcBlue = Color(red: 0.02, green: 0.05, blue: 0.2)
    private let accentGold = Color(red: 0.85, green: 0.72, blue: 0.3)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    dcBlue.ignoresSafeArea()
                    ProgressView().tint(accentGold).scaleEffect(1.2)
                }
            } else {
                NavigationStack {
                    ZStack(alignment: .top) {
                        dcBlue.ignoresSafeArea()
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                heroSection
                                
                                // DC logo with gold accent glow
                                Image("DC Comics")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.white)
                                    .frame(height: 50)
                                    .shadow(color: accentGold.opacity(0.5), radius: 25)
                                    .padding(.top, -50)
                                    .padding(.bottom, 8)
                                
                                // Gold accent line
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, accentGold.opacity(0.5), .clear],
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
                                            title: "DC Spotlight",
                                            items: featuredItems,
                                            limit: 10,
                                            onItemTap: { selectedItem = $0 },
                                            isImmersiveStyle: true
                                        )
                                    }
                                    
                                    if !movieItems.isEmpty {
                                        MediaRowView(title: "DC Films", items: movieItems, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
                                    }
                                    
                                    if !seriesItems.isEmpty {
                                        MediaRowView(title: "DC Series", items: seriesItems, limit: 15, onItemTap: { selectedItem = $0 }, isImmersiveStyle: true)
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
                // Deep navy-to-black with golden edge tints
                LinearGradient(
                    colors: [.clear, dcBlue.opacity(0.4), dcBlue.opacity(0.95)],
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
            let companyIds = dcCompanyIds
            let finalItems: [MediaItem] = try await Task.detached(priority: .userInitiated) {
                var allFetchedItems: [MediaItem] = []
                var seenIds = Set<String>()

                func addBatch(_ items: [MediaItem]) {
                    for item in items {
                        let id = "\(item.resolvedMediaType.rawValue)-\(item.id)"
                        if !seenIds.contains(id) { seenIds.insert(id); allFetchedItems.append(item) }
                    }
                }

                for companyId in companyIds {
                    let firstMoviePage = try await TMDBService.shared.discoverMoviesByCompany(companyIds: [companyId], page: 1)
                    addBatch(firstMoviePage.results)
                    let moviePages = min(firstMoviePage.totalPages ?? 1, 3)
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
                }

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
                id: 2001,
                name: "Batman",
                logoAssetName: "",
                backgroundColor: Color(red: 0.1, green: 0.1, blue: 0.1),
                backdropAssetName: "dc_backdrop",
                customItems: [
                    .init(id: "272", type: .movie),
                    .init(id: "155", type: .movie),
                    .init(id: "49026", type: .movie),
                    .init(id: "414906", type: .movie)
                ]
            ),
            HubCollection(
                id: 2002,
                name: "Superman",
                logoAssetName: "",
                backgroundColor: Color(red: 0.05, green: 0.1, blue: 0.4),
                backdropAssetName: "dc_backdrop",
                customItems: [
                    .init(id: "1924", type: .movie),
                    .init(id: "49521", type: .movie),
                    .init(id: "209112", type: .movie)
                ]
            ),
            HubCollection(
                id: 2003,
                name: "Wonder Woman",
                logoAssetName: "",
                backgroundColor: Color(red: 0.4, green: 0.05, blue: 0.05),
                backdropAssetName: "dc_backdrop",
                customItems: [
                    .init(id: "297762", type: .movie),
                    .init(id: "464052", type: .movie)
                ]
            )
        ]
    }
}
