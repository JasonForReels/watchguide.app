import SwiftUI

struct ImmersiveHubLayout<Logo: View>: View {
    let items: [MediaItem]
    let logo: Logo
    let backgroundColor: Color
    let collections: [HubCollection]
    
    @State private var localSelectedItem: MediaItem?
    @State private var selectedCollection: HubCollection?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var osTVOS: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }
    
    init(items: [MediaItem], logo: Logo, backgroundColor: Color, collections: [HubCollection] = []) {
        self.items = items
        self.logo = logo
        self.backgroundColor = backgroundColor
        self.collections = collections
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                backgroundColor.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        heroSection
                        
                        logoHeader
                        
                        VStack(spacing: horizontalSizeClass == .regular ? 64 : 32) {
                            if !collections.isEmpty {
                                collectionsSection
                                    .padding(.vertical, 20)
                            }
                            
                            if !featuredItems.isEmpty {
                                MediaRowView(
                                    title: "Featured",
                                    items: featuredItems,
                                    limit: 10,
                                    onItemTap: { localSelectedItem = $0 },
                                    onSeeAll: nil,
                                    isImmersiveStyle: true
                                )
                            }
                            
                            if !movies.isEmpty {
                                MediaRowView(
                                    title: "Movies",
                                    items: movies,
                                    limit: 15,
                                    onItemTap: { localSelectedItem = $0 },
                                    onSeeAll: nil,
                                    isImmersiveStyle: true
                                )
                            }
                            
                            if !series.isEmpty {
                                MediaRowView(
                                    title: "Series",
                                    items: series,
                                    limit: 15,
                                    onItemTap: { localSelectedItem = $0 },
                                    onSeeAll: nil,
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
                
                customNavigationBar
            }
            #if os(tvOS)
            .toolbar(.hidden, for: .navigationBar)
            #elseif os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        .toolbar(.hidden, for: .navigationBar)
        .mediaDetailPresentation(item: $localSelectedItem)
        .fullScreenCover(item: $selectedCollection) { collection in
            HubCollectionView(collection: collection)
        }
    }
    
    // MARK: - Sections
    
    private var collectionsSection: some View {
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
    }
    
    private var heroSection: some View {
        HeroCarouselView(
            items: Array(items.prefix(10)),
            onItemTap: { item in
                localSelectedItem = item
            },
            aspectRatio: horizontalSizeClass == .regular ? 16/9 : 10/12,
            isPortrait: horizontalSizeClass != .regular,
            isEdgeToEdge: true,
            externalVisibilityOverride: true,
            isImmersiveStyle: true
        )
        .overlay(
            LinearGradient(
                colors: [.clear, backgroundColor.opacity(0.3), backgroundColor.opacity(0.8)],
                startPoint: .center,
                endPoint: .bottom
            )
            .padding(.top, 200)
            .allowsHitTesting(false)
        )
    }

    private var logoHeader: some View {
        logo
            .aspectRatio(contentMode: .fit)
            .frame(height: osTVOS ? 110 : 50)
            .shadow(color: .black.opacity(0.5), radius: 20)
            .padding(.top, osTVOS ? -100 : -50) // Pull it up to overlap slightly with the gradient
            .padding(.bottom, 20)
    }
    
    private var customNavigationBar: some View {
        HStack(spacing: 20) {
            Button {
                dismiss()
            } label: {
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
        .padding(.top, horizontalSizeClass == .regular ? (osTVOS ? 40 : 80) : 50)
        #if os(tvOS)
        .padding(.horizontal, 40)
        #endif
        .background(
            LinearGradient(
                colors: [.black.opacity(0.3), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
    
    private var featuredItems: [MediaItem] {
        Array(items.prefix(15))
    }
    
    private var movies: [MediaItem] {
        items.filter { $0.resolvedMediaType == .movie }
    }
    
    private var series: [MediaItem] {
        items.filter { $0.resolvedMediaType == .tv }
    }
}
