//
//  MediaDetailView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if canImport(SafariServices)
import SafariServices
#endif
#if canImport(AppIntents)
import AppIntents
#endif
import Combine

// MARK: - Person Selection Model
struct SelectedPerson: Identifiable {
    let id: Int
    let name: String
    let profilePath: String?
}

struct MediaDetailView: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MediaDetailViewModel
    @ObservedObject private var storage = StorageService.shared
    @State private var selectedSeason: Season?
    @State private var selectedPerson: SelectedPerson?
    @State private var selectedCompanyHub: CompanyHub?
    @State private var selectedCompanyItem: MediaItem?
    @State private var showWatchAlong = false
    @State private var selectedItem: MediaItem?

    @State private var selectedTrailer: Video?
    @State private var safariItem: SafariItem?
    @State private var showInlineTrailer = false
    @State private var selectedStreamingCountry: StreamingCountry?
    @State private var showKeepStub = false
    @State private var overviewExpanded = false
    @ObservedObject private var stubStore = TicketStubStore.shared

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompactWidth: Bool { horizontalSizeClass == .compact }
    #endif

    init(item: MediaItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: MediaDetailViewModel(item: item))
    }

#if canImport(AppIntents)
    private var onscreenEntity: OnscreenMediaEntity {
        let castNames = viewModel.cast.prefix(8).map { $0.name }
        let companyNames = viewModel.productionCompanies.prefix(6).map { $0.name }
        let safeOverview = (viewModel.overview ?? item.overview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return OnscreenMediaEntity(
            id: "\(item.resolvedMediaType.rawValue)-\(item.id)",
            title: item.displayTitle,
            mediaType: item.resolvedMediaType == .movie ? "Movie" : "TV Show",
            year: item.year,
            overview: safeOverview,
            genres: viewModel.genres,
            runtime: viewModel.runtime,
            cast: castNames,
            productionCompanies: companyNames
        )
    }
#endif
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero Header (inline player or static backdrop)
                headerSection
                    #if os(tvOS)
                    .focusSection()
                    #endif
                
                // Content
                VStack(spacing: 24) {
                    // Quick Actions
                    if let savedItem = viewModel.savedItem {
                        ListActionsView(
                            mediaId: item.id,
                            mediaType: item.resolvedMediaType,
                            savedItem: savedItem
                        )
                        .padding(.horizontal)
                    }

                        #if !os(tvOS)
                        stubSection
                            .padding(.horizontal)
                        #endif
                        
                        #if !os(tvOS)
                        // Show the inline Play Trailer button only when the header
                        // is NOT already auto-playing a trailer in the background.
                        if !shouldShowDetailTrailer, let trailer = viewModel.preferredTrailer {
                            if showInlineTrailer {
                                // Inline embedded trailer player (autoplay muted)
                                VStack(alignment: .leading, spacing: 8) {
                                    EmbeddedTrailerPlayer(
                                        videoKey: trailer.key,
                                        title: trailer.name
                                    )
                                    .padding(.horizontal)
                                    
                                    Button {
                                        withAnimation(.easeOut(duration: 0.25)) {
                                            showInlineTrailer = false
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "xmark")
                                                .font(.caption2.weight(.bold))
                                            Text("Hide Trailer")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            } else {
                                PlayTrailerButton {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        showInlineTrailer = true
                                    }
                                }
                                .padding(.horizontal)
                                .transition(.opacity)
                            }
                        }
                        #endif
                        
                        // Ratings
                        if viewModel.ratings != nil || viewModel.tmdbRating != nil {
                            RatingsView(
                                ratings: viewModel.ratings,
                                tmdbRating: viewModel.tmdbRating
                            )
                            .padding(.horizontal)
                        }

                        if viewModel.hasQuickStats {
                            DetailQuickStatsRow(
                                runtime: viewModel.runtime,
                                genres: viewModel.genres,
                                certificate: viewModel.certificate,
                                budget: viewModel.budget,
                                revenue: viewModel.revenue,
                                originCountry: viewModel.originCountry
                            )
                            .padding(.horizontal)
                        }
                        
                        if let certificate = viewModel.certificate, !certificate.isEmpty {
                            ParentRatingSection(certificate: certificate)
                                .padding(.horizontal)
                        }
                        
                        // Overview
                        if let overview = viewModel.overview, !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("About")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Text(overview)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .lineLimit(overviewExpanded ? nil : 4)
                                    .animation(WGMotion.smooth, value: overviewExpanded)

                                if overview.count > 220 {
                                    Button(overviewExpanded ? "Less" : "More") {
                                        overviewExpanded.toggle()
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .tint(Reel.accent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        }
                        
                        #if os(iOS)
                        WatchAlongEntryCard { showWatchAlong = true }
                            .padding(.horizontal)
                        #endif

                        #if !os(tvOS)
                        if viewModel.isMovie {
                            PostCreditsScoutSection(
                                stingers: viewModel.creditsStingers,
                                summary: viewModel.postCreditsSummary,
                                isLoading: viewModel.isPostCreditsLoading,
                                errorMessage: viewModel.postCreditsError,
                                onCheck: {
                                    Task { await viewModel.fetchPostCreditsWorthIt() }
                                }
                            )
                            .padding(.horizontal)
                        }

                        DeepDiveSection(
                            item: item,
                            crew: viewModel.crew,
                            budget: viewModel.budget,
                            revenue: viewModel.revenue,
                            isWatched: StorageService.shared.watched.contains {
                                $0.mediaId == item.id && $0.mediaType == item.resolvedMediaType
                            },
                            onQuotaReached: { viewModel.showUpgradePaywall = true }
                        )
                        .padding(.horizontal)
                        #endif

                        if let leaving = viewModel.leavingSoon {
                            LeavingSoonBanner(providerName: leaving.providerName, leavesOn: leaving.date)
                                .padding(.horizontal)
                        }

                        // Where to Watch
                        if viewModel.watchProviders != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Where to Watch")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)
                                
                                WatchProvidersView(
                                    providers: viewModel.watchProviders,
                                    link: viewModel.watchProvidersLink,
                                    mediaTitle: item.title ?? item.name ?? "",
                                    alternateTitle: item.originalTitle ?? item.originalName,
                                    mediaType: item.resolvedMediaType,
                                    year: String((item.releaseDate ?? item.firstAirDate ?? "").prefix(4)),
                                    deepLinks: viewModel.deepLinks
                                )
                                .padding(.horizontal)
                            }
                        }
                        
                        // Streaming availability by country (map on iOS/iPadOS, list on tvOS)
                        if !viewModel.allWatchProviderRegions.isEmpty,
                           StreamingMapView.hasStreamingAvailability(in: viewModel.allWatchProviderRegions) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Available Around the World")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)
                                
                                StreamingMapView(
                                    allRegions: viewModel.allWatchProviderRegions,
                                    mediaTitle: item.title ?? item.name ?? "",
                                    alternateTitle: item.originalTitle ?? item.originalName,
                                    mediaType: item.resolvedMediaType,
                                    year: String((item.releaseDate ?? item.firstAirDate ?? "").prefix(4)),
                                    deepLinks: viewModel.deepLinks,
                                    selectedCountry: $selectedStreamingCountry
                                )
                                .padding(.horizontal)
                            }
                        }
                        
                        // Collection
                        if let collectionInfo = viewModel.collectionInfo, !viewModel.collectionItems.isEmpty {
                            CollectionRowView(
                                collectionName: collectionInfo.name,
                                items: viewModel.collectionItems,
                                onItemTap: { item in
                                    selectedItem = item
                                }
                            )
                        }
                        
                        // TV Show Seasons
                        if let seasons = viewModel.seasons, !seasons.isEmpty {
                            seasonsSection(seasons: seasons)
                        }
                        
                        // Other videos (clips, featurettes, etc.)
                        let nonTrailerVideos = viewModel.videos.filter { v in
                            let type = v.type.lowercased()
                            return type != "trailer" && type != "teaser"
                        }
                        if !nonTrailerVideos.isEmpty {
                            VideoRowView(videos: nonTrailerVideos, title: "More Videos")
                        }
                        
                        // Cast
                        if !viewModel.cast.isEmpty {
                            CastRowView(cast: viewModel.cast) { member in
                                selectedPerson = SelectedPerson(id: member.id, name: member.name, profilePath: member.profilePath)
                            }
                        }
                        
                        // Crew
                        if !viewModel.crew.isEmpty {
                            CrewRowView(crew: viewModel.crew) { member in
                                selectedPerson = SelectedPerson(id: member.id, name: member.name, profilePath: member.profilePath)
                            }
                        }

                        if !viewModel.productionCompanies.isEmpty {
                            TitleProductionCompaniesRow(companies: viewModel.productionCompanies) { company in
                                selectedCompanyHub = CompanyHub(
                                    name: company.name,
                                    companyIds: [company.id],
                                    networkIds: []
                                )
                            }
                        }
                        
                        // Similar
                        if !viewModel.similar.isEmpty {
                            MediaRowView(
                                title: "Similar",
                                items: viewModel.similar,
                                onItemTap: { item in
                                    selectedItem = item
                                }
                            )
                        }
                        
                        // Recommendations
                        if !viewModel.recommendations.isEmpty {
                            MediaRowView(
                                title: "Recommended",
                                items: viewModel.recommendations,
                                onItemTap: { item in
                                    selectedItem = item
                                }
                            )
                        }
                        
                        // Additional Info
                        additionalInfoSection
                    }
                    .padding(.vertical, 24)
                }
            }
        #if os(tvOS)
        .defaultScrollAnchor(.top)
        #endif
        .ignoresSafeArea(edges: .top)
        .background {
            // Poster-lit, like Tonight: the page takes its colour from the artwork.
            ZStack {
                Color.black
                AsyncImageView(url: TMDBService.shared.imageURL(path: item.posterPath, size: .small), cornerRadius: 0)
                    .scaledToFill()
                    .blur(radius: 90)
                    .saturation(1.3)
                    .opacity(0.45)
                LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
        .colorScheme(.dark)
        .task {
            await viewModel.loadDetails()
        }
#if canImport(AppIntents)
        .userActivity("com.watchguide.media.onscreen") { activity in
            activity.title = "Viewing \(item.displayTitle)"
            if #available(iOS 18.0, macOS 15.0, *) {
                let entity = onscreenEntity
                activity.appEntityIdentifier = EntityIdentifier(for: entity)
                Task {
                    await OnscreenMediaEntityRegistry.shared.register(entity)
                }
            }
        }
        .onDisappear {
            if #available(iOS 18.0, macOS 15.0, *) {
                Task {
                    await OnscreenMediaEntityRegistry.shared.unregister(entityID: "\(item.resolvedMediaType.rawValue)-\(item.id)")
                }
            }
        }
#endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showWatchAlong) {
            WatchAlongLauncherView(item: item, seasons: viewModel.seasons ?? [])
        }
        #endif
        .sheet(item: $selectedSeason) { season in
            SeasonDetailSheet(
                tvId: item.id,
                showTitle: item.displayTitle,
                season: season
            )
        }
        .sheet(item: $selectedPerson) { person in
            PersonDetailView(
                personId: person.id,
                personName: person.name,
                profilePath: person.profilePath
            )
        }
        .sheet(item: $selectedCompanyHub) { hub in
            CompanyHubSheet(companyHub: hub, selectedItem: $selectedCompanyItem)
        }
        .sheet(item: $selectedCompanyItem) { item in
            MediaDetailView(item: item)
        }
        .sheet(item: $selectedItem) { item in
            MediaDetailView(item: item)
        }
        #if !os(tvOS)
        .sheet(item: $selectedStreamingCountry) { country in
            CountryStreamingDetailView(
                country: country,
                mediaTitle: item.title ?? item.name ?? "",
                alternateTitle: item.originalTitle ?? item.originalName,
                mediaType: item.resolvedMediaType,
                year: String((item.releaseDate ?? item.firstAirDate ?? "").prefix(4)),
                deepLinks: viewModel.deepLinks,
                savedMediaItem: viewModel.savedItem
            )
        }
        #endif
        #if os(iOS)
        .sheet(item: $safariItem) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        #endif
        #if !os(tvOS)
        .sheet(isPresented: $showKeepStub) {
            NavigationStack {
                KeepStubSheet(item: item) { verdict, company, note in
                    stubStore.tear(for: item, verdict: verdict, company: company, note: note)
                }
            }
            .presentationDetents([.medium, .large])
        }
        #endif
        .sheet(isPresented: $viewModel.showUpgradePaywall) {
            WGUnlimitedPaywallView()
        }
    }
    
    // MARK: - Header Section (Auto-Playing Trailer)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var shouldShowDetailTrailer: Bool {
        storage.settings.showTrailersInMediaDetail
    }
    
    private var headerSection: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width * 9.0 / 16.0
            let isCompact = verticalSizeClass == .compact
            
            ZStack(alignment: .bottomLeading) {
                // Layer 0: Black base
                Color.black
                
                // Layer 1: Trailer video (underneath the backdrop)
                if shouldShowDetailTrailer, let trailerKey = viewModel.preferredTrailer?.key {
                    EmbeddedTrailerPlayer(
                        videoKey: trailerKey,
                        title: viewModel.preferredTrailer?.name ?? item.displayTitle,
                        compact: false,
                        autoPlay: true,
                        showsControls: false,
                        contentMode: .fill,
                        cornerRadius: 0
                    )
                        .frame(width: width, height: height)
                        .clipped()
                        .allowsHitTesting(false)
                }
                
                // Layer 2: Backdrop — fades out when trailer is ready
                Group {
                    if let fanartStr = viewModel.fanartBackdropURL, let fanartURL = URL(string: fanartStr) {
                        AsyncImage(url: fanartURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                tmdbBackdropImage
                            }
                        }
                    } else {
                        tmdbBackdropImage
                    }
                }
                .frame(width: width, height: height)
                .clipped()
                .opacity((shouldShowDetailTrailer && viewModel.preferredTrailer != nil) ? 0 : 1)
                .animation(.easeInOut(duration: 0.8), value: viewModel.preferredTrailer?.key)
                
                // Layer 3: Gradient overlay
                #if os(tvOS)
                // tvOS: subtle bottom fade only — keeps the trailer visible
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.55),
                        .init(color: .black.opacity(0.6), location: 0.85),
                        .init(color: .black.opacity(0.95), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width, height: height)
                #else
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7), .black.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width, height: height)
                #endif
                
                // Layer 4: Content overlay
                VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
                    if shouldShowDetailTrailer && viewModel.preferredTrailer != nil {
                        // Trailer playing: only keep the title logo/text visible over video.
                        if let logoURL = resolvedDetailLogoURL(width: width, height: height) {
                            AsyncImage(url: logoURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .renderingMode(.original)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: min(width * 0.42, 210), maxHeight: isCompact ? 36 : 48)
                                        .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 3)
                                default:
                                    Text(item.displayTitle)
                                        .font(isCompact ? .subheadline : .headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .lineLimit(isCompact ? 2 : 3)
                                }
                            }
                        } else {
                            Text(item.displayTitle)
                                .font(isCompact ? .subheadline : .headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .lineLimit(isCompact ? 2 : 3)
                        }
                    } else {
                        // No trailer: show full metadata header as before.
                        Text(item.resolvedMediaType == .movie ? "MOVIE" : "TV SHOW")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(4)

                        if let logoURL = resolvedDetailLogoURL(width: width, height: height) {
                            AsyncImage(url: logoURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .renderingMode(.original)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: min(width * 0.42, 210), maxHeight: isCompact ? 36 : 48)
                                        .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 3)
                                default:
                                    Text(item.displayTitle)
                                        .font(isCompact ? .subheadline : .headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .lineLimit(isCompact ? 2 : 3)
                                }
                            }
                        } else {
                            Text(item.displayTitle)
                                .font(isCompact ? .subheadline : .headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .lineLimit(isCompact ? 2 : 3)
                        }
                        
                        HStack(spacing: 12) {
                            if let year = item.year {
                                Text(year)
                            }
                            
                            if let runtime = viewModel.runtime {
                                Text(runtime)
                            }
                            
                            if let rating = item.voteAverage, rating > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                    Text(String(format: "%.1f", rating))
                                }
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        
                        if let genres = viewModel.genres {
                            Text(genres)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(isCompact ? 12 : 16)
                .padding(.bottom, isCompact ? 4 : 8)
                
                #if os(tvOS)
                // tvOS: transparent focusable button overlay (same pattern as HeroCarouselView)
                // Makes the header the first focusable element so tvOS doesn't auto-scroll past it.
                Button {
                    // No-op — the header is just a cinematic trailer display
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TVOSCarouselButtonStyle())
                #endif
            }
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                #if os(tvOS)
                .buttonStyle(.plain)
                #else
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Close")
                #endif
                #if os(tvOS)
                .padding(.leading, 60)
                .padding(.top, 40)
                #else
                .padding(.leading, 20)
                .padding(.top, 50)
                #endif
            }
        }
        .aspectRatio(16.0/9.0, contentMode: .fit)
    }
    
    /// TMDB backdrop (used as fallback)
    private var tmdbBackdropImage: some View {
        AsyncImage(url: TMDBService.shared.imageURL(path: item.backdropPath, size: .backdrop)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            default:
                Rectangle()
                    .fill(Color.gray.opacity(0.35))
            }
        }
    }
    
    /// Resolves the logo URL for the detail header: FanArt.tv full URL first, TMDB path second
    private func resolvedDetailLogoURL(width: CGFloat, height: CGFloat) -> URL? {
        if let fullStr = viewModel.logoFullURL, let url = URL(string: fullStr) { return url }
        if let path = viewModel.logoPath { return TMDBService.shared.imageURL(path: path, size: .logo) }
        return nil
    }
    
    // MARK: - Ticket Stubs

    private var stubsForItem: [TicketStub] {
        stubStore.stubs.filter { $0.mediaId == item.id && $0.mediaType == item.resolvedMediaType }
    }

    /// "Keep a Ticket Stub" plus any stubs already kept for this title, so a
    /// rewatch shows its history right where you'd log the next one.
    @ViewBuilder
    private var stubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showKeepStub = true
            } label: {
                Label(stubsForItem.isEmpty ? "I Watched This" : "Watched Again", systemImage: "ticket.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Reel.accent)

            if !stubsForItem.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(stubsForItem) { stub in
                            StubCard(stub: stub).frame(width: 300)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Seasons Section
    private func seasonsSection(seasons: [Season]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seasons")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(seasons.filter { $0.seasonNumber > 0 }) { season in
                        SeasonCard(season: season)
                            .onTapGesture {
                                selectedSeason = season
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Additional Info Section
    private var additionalInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.title3)
                .fontWeight(.bold)
            
            let columns: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 12) {
                if let status = viewModel.status {
                    InfoRow(label: "Status", value: status)
                }
                
                if let originalTitle = viewModel.originalTitle {
                    InfoRow(label: "Original Title", value: originalTitle)
                }
                
                if let budget = viewModel.budget {
                    InfoRow(label: "Budget", value: budget)
                }
                
                if let revenue = viewModel.revenue {
                    InfoRow(label: "Revenue", value: revenue)
                }
            }
        }
        .padding(.horizontal)
    }

}

// MARK: - Play Trailer Button
struct PlayTrailerButton: View {
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.headline)
                Text("Play Trailer")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2))
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play Trailer")
    }
}

// MARK: - SafariView
#if os(iOS)
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = .white
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif

struct SafariItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Season Card
struct SeasonCard: View {
    let season: Season
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImageView(posterPath: season.posterPath)
                .frame(width: 100, height: 150)
                .shadow(radius: isHovered ? 8 : 4)
                .scaleEffect(isHovered ? 1.03 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.0), value: isHovered)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(season.name ?? "Season \(season.seasonNumber)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if let count = season.episodeCount {
                    Text("\(count) episodes")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 100, alignment: .leading)
        }
        #if !os(tvOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }
}

// MARK: - Season Detail Sheet
struct SeasonDetailSheet: View {
    let tvId: Int
    let showTitle: String
    let season: Season
    @Environment(\.dismiss) private var dismiss
    @State private var episodes: [Episode] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    List(episodes) { episode in
                        EpisodeRow(
                            showTitle: showTitle,
                            seasonNumber: season.seasonNumber,
                            episode: episode
                        )
                    }
                }
            }
            .navigationTitle(season.name ?? "Season \(season.seasonNumber)")
            #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            await loadEpisodes()
        }
    }
    
    private func loadEpisodes() async {
        do {
            let details = try await TMDBService.shared.getSeasonDetails(tvId: tvId, seasonNumber: season.seasonNumber)
            episodes = details.episodes ?? []
        } catch {
            print("Error loading episodes: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Episode Row
struct EpisodeRow: View {
    let showTitle: String
    let seasonNumber: Int
    let episode: Episode
    @State private var skipMapSummary: String?
    @State private var skipMapError: String?
    @State private var isLoadingSkipMap = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Still image
            AsyncImage(url: TMDBService.shared.imageURL(path: episode.stillPath, size: .backdropSmall)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    Rectangle()
                        .fill(Color.gray.opacity(0.18))
                }
            }
            .frame(width: 120, height: 68)
            .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("E\(episode.episodeNumber)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(episode.name ?? "Episode \(episode.episodeNumber)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if isLoadingSkipMap {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Checking skip‑map…")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                } else if let skipMapSummary {
                    Text(skipMapSummary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else if let skipMapError {
                    Text(skipMapError)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    Button("Check skip‑map") {
                        Task { await fetchSkipMap() }
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.plain)
                }
                
                HStack(spacing: 8) {
                    if let runtime = episode.runtime {
                        Text("\(runtime)m")
                            .font(.caption2)
                    }
                    if let rating = episode.voteAverage, rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 8))
                            Text(String(format: "%.1f", rating))
                                .font(.caption2)
                        }
                    }
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func fetchSkipMap() async {
        guard !isLoadingSkipMap else { return }
        let aiAvailable = await AIService.shared.isAvailable
        guard aiAvailable else {
            skipMapError = "Atlas AI isn’t configured."
            return
        }

        isLoadingSkipMap = true
        skipMapError = nil

        let episodeTitle = episode.name ?? "Episode \(episode.episodeNumber)"
        let prompt = """
        For \(showTitle) S\(seasonNumber)E\(episode.episodeNumber) “\(episodeTitle)”, find skip-map timings.
        Respond ONLY like: “Intro: Xm Ys • Recap: Xm Ys • Post‑credits: Xm Ys/None”.
        If unknown, use “Unknown” for that part. Keep it short.
        """

        do {
            let (response, _) = try await AIService.shared.sendMessage(
                prompt,
                conversationHistory: [],
                likedItems: [],
                webSearchEnabled: true,
                model: .geminiFlashLite,
                restrictedMode: false
            )
            skipMapSummary = response
            skipMapError = nil
        } catch {
            skipMapSummary = nil
            skipMapError = "Couldn’t check right now."
        }

        isLoadingSkipMap = false
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - Detail Quick Stats
struct DetailQuickStatsRow: View {
    let runtime: String?
    let genres: String?
    let certificate: String?
    let budget: String?
    let revenue: String?
    let originCountry: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                if let runtime = runtime {
                    QuickStatItem(icon: "clock", label: "Runtime", value: runtime)
                }
                if let genres = genres {
                    QuickStatItem(icon: "film", label: "Genre", value: firstValue(from: genres))
                }
                if let certificate = certificate, !certificate.isEmpty {
                    QuickStatItem(icon: "exclamationmark.shield", label: "Certificate", value: certificate)
                }
                if let budget = budget {
                    QuickStatItem(icon: "briefcase", label: "Budget", value: budget)
                }
                if let revenue = revenue {
                    QuickStatItem(icon: "dollarsign", label: "Revenue", value: revenue)
                }
                if let originCountry = originCountry {
                    QuickStatItem(icon: "map", label: "Origin", value: originCountry)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func firstValue(from csv: String) -> String {
        csv.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? csv
    }
}

struct QuickStatItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Parent Rating
private struct ParentRatingSection: View {
    let certificate: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Parent Guide")
                .font(.title3)
                .fontWeight(.bold)

            HStack(spacing: 6) {
                Text("Rating")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(certificate)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.12))
            .cornerRadius(12)
        }
    }
}

// MARK: - Post-Credits Scout
private struct PostCreditsScoutSection: View {
    let stingers: CreditsStingers?
    let summary: String?
    let isLoading: Bool
    let errorMessage: String?
    let onCheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Post‑Credits Check")
                    .font(.title3)
                    .fontWeight(.bold)

                if !AIMessageQuota.isUnlimited() && !AIMessageQuota.canUsePostCreditsThisMonth() {
                    WGUnlimitedLockButton()
                }

                Spacer()
                if summary != nil || errorMessage != nil {
                    Button("Check again") {
                        onCheck()
                    }
                    .font(.caption)
                }
            }

            if let stingers {
                CreditsStingerBadge(stingers: stingers)
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Atlas is checking the web...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let summary {
                Text(summary)
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Button(action: onCheck) {
                    Text("Ask Atlas if it’s worth staying")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.12))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Credits Stinger Badge

/// Mid/post-credits scenes as tagged by TMDB keywords. Free and instant —
/// the Atlas check below adds whether the scene is worth waiting for.
struct CreditsStingers: Equatable {
    static let duringCreditsKeywordId = 179430
    static let afterCreditsKeywordId = 179431

    let duringCredits: Bool
    let afterCredits: Bool

    /// Nil when TMDB has no stinger tags — absence isn't proof there's no scene.
    init?(keywords: [Keyword]) {
        let ids = Set(keywords.map(\.id))
        duringCredits = ids.contains(Self.duringCreditsKeywordId)
        afterCredits = ids.contains(Self.afterCreditsKeywordId)
        guard duringCredits || afterCredits else { return nil }
    }

    var summary: String {
        switch (duringCredits, afterCredits) {
        case (true, true): return "Mid-credits and post-credits scenes"
        case (true, false): return "Mid-credits scene"
        default: return "Post-credits scene"
        }
    }
}

private struct CreditsStingerBadge: View {
    let stingers: CreditsStingers

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.tv")
                .font(.title3)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Stay for the credits")
                    .font(.subheadline.weight(.semibold))
                Text(stingers.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Production Companies Row
struct TitleProductionCompaniesRow: View {
    let companies: [ProductionCompany]
    let onCompanyTap: (ProductionCompany) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Production Companies")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(companies) { company in
                        TitleProductionCompanyCard(company: company) {
                            onCompanyTap(company)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct TitleProductionCompanyCard: View {
    let company: ProductionCompany
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #endif
    private var isSearchlight: Bool { company.id == 127929 || company.name == "Searchlight Pictures" }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    #if os(tvOS)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.clear)
                    #else
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                            radius: 6,
                            x: 0,
                            y: 3
                        )
                    #endif

                    if isSearchlight {
                        Image("SearchlightLogo")
                            .resizable()
                            .scaledToFit()
                            .padding(16)
                    } else if let url = logoURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                            case .empty:
                                ProgressView()
                            default:
                                Image(systemName: "film")
                                    .font(.title2.weight(.semibold))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(16)
                    } else {
                        Image(systemName: "film")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 180, height: 100)
                #if os(tvOS)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(isFocused ? 0.96 : 0.18), lineWidth: isFocused ? 2.6 : 1.1)
                )
                .shadow(color: Color.black.opacity(isFocused ? 0.4 : 0.16), radius: isFocused ? 18 : 6, x: 0, y: isFocused ? 10 : 3)
                .scaleEffect(isFocused ? 1.08 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isFocused)
                #endif

                Text(company.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        #if os(tvOS)
        .buttonStyle(TVOSTransparentButtonStyle(cornerRadius: 18))
        .focused($isFocused)
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var logoURL: URL? {
        if let tmdbURL = TMDBService.shared.imageURL(path: company.logoPath, size: .logo) {
            return tmdbURL
        }
        return TitleProductionCompanyCard.fallbackLogoURL(for: company.id)
    }

    private static func fallbackLogoURL(for companyId: Int) -> URL? {
        switch companyId {
        case 4:
            return URL(string: "https://cdn.brandfetch.io/idrAEeTLeo/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1757576972155")
        case 2:
            return URL(string: "https://cdn.brandfetch.io/idxASqzkm_/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1675929043591")
        case 127928:
            return URL(string: "https://cdn.brandfetch.io/id80eyhRc1/w/820/h/683/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1667562091650")
        case 174:
            return URL(string: "https://cdn.brandfetch.io/idxBWIwtz0/w/405/h/396/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1768344714851")
        case 3:
            return URL(string: "https://cdn.brandfetch.io/idYVybSjsA/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1764458646138")
        default:
            return nil
        }
    }
}

// MARK: - Media Detail View Model
@MainActor
class MediaDetailViewModel: ObservableObject {
    let item: MediaItem
    
    @Published var overview: String?
    @Published var runtime: String?
    @Published var genres: String?
    @Published var status: String?
    @Published var originalTitle: String?
    @Published var budget: String?
    @Published var revenue: String?
    @Published var tmdbRating: Double?
    @Published var ratings: RatingsSummary?
    @Published var originCountry: String?
    @Published var certificate: String?
    @Published var cast: [CastMember] = []
    @Published var crew: [CrewMember] = []
    @Published var videos: [Video] = []
    @Published var preferredTrailer: Video?
    @Published var similar: [MediaItem] = []
    @Published var recommendations: [MediaItem] = []
    @Published var watchProviders: WatchProviderRegion?
    @Published var watchProvidersLink: String?
    @Published var deepLinks: [StreamingDeepLink] = []
    @Published var allWatchProviderRegions: [String: WatchProviderRegion] = [:]
    @Published var seasons: [Season]?
    @Published var savedItem: SavedMediaItem?
    @Published var logoPath: String?
    /// Full URL string for the logo (FanArt.tv or TMDB). Takes precedence over logoPath.
    @Published var logoFullURL: String?
    /// Full URL string for the FanArt.tv backdrop (nil = use TMDB)
    @Published var fanartBackdropURL: String?
    @Published var collectionInfo: CollectionInfo?
    @Published var collectionItems: [MediaItem] = []
    @Published var productionCompanies: [ProductionCompany] = []
    @Published var creditsStingers: CreditsStingers?
    @Published var postCreditsSummary: String?
    @Published var postCreditsError: String?
    @Published var isPostCreditsLoading = false
    @Published var showUpgradePaywall = false
    /// IMDb ID resolved from TMDB details, used for Trailerio addon fetch on tvOS.
    private var imdbId: String?
    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    var isMovie: Bool {
        item.resolvedMediaType == .movie
    }

    /// Earliest announced departure from a streaming service showing this title.
    /// Limited to the user's StreamQ services when they've picked any.
    var leavingSoon: (providerName: String, date: Date)? {
        guard let region = watchProviders else { return nil }
        let selected = Set(StorageService.shared.settings.streamqServiceIds)
        let now = Date()
        let providers = (region.flatrate ?? []) + (region.free ?? []) + (region.ads ?? [])
        return providers
            .filter { selected.isEmpty || selected.contains($0.providerId) }
            .compactMap { provider -> (providerName: String, date: Date)? in
                guard let date = StreamingDeepLinkService.leavingDate(forTMDBProviderId: provider.providerId, from: deepLinks),
                      date > now else { return nil }
                return (provider.providerName, date)
            }
            .min { $0.date < $1.date }
    }

    var hasQuickStats: Bool {
        runtime != nil
        || genres != nil
        || (certificate != nil && !(certificate?.isEmpty ?? true))
        || budget != nil
        || revenue != nil
        || originCountry != nil
    }
    
    init(item: MediaItem) {
        self.item = item
    }

    func fetchPostCreditsWorthIt() async {
        guard isMovie else { return }
        guard !isPostCreditsLoading else { return }

        let aiAvailable = await AIService.shared.isAvailable
        if !aiAvailable {
            postCreditsError = "Atlas AI isn’t configured. Add your API key in Settings."
            return
        }

        if !AIMessageQuota.canUsePostCreditsThisMonth() {
            showUpgradePaywall = true
            return
        }

        isPostCreditsLoading = true
        postCreditsError = nil

        let title = item.displayTitle
        let yearSuffix = item.year.map { " (\($0))" } ?? ""
        let prompt = "For \(title)\(yearSuffix), is the post-credits scene worth staying for? Answer ONLY in this format: \"Worth it: Yes/No — short reason (<=12 words).\" If unknown, use \"Worth it: Unknown — reason.\""

        do {
            let (response, _) = try await AIService.shared.sendMessage(
                prompt,
                conversationHistory: [],
                likedItems: [],
                webSearchEnabled: true,
                model: .geminiFlashLite,
                restrictedMode: false
            )
            postCreditsSummary = response
            postCreditsError = nil
            AIMessageQuota.consumePostCredits()
        } catch {
            postCreditsSummary = nil
            postCreditsError = "Couldn’t check right now. Please try again."
        }

        isPostCreditsLoading = false
    }
    
    func loadDetails() async {
        if item.resolvedMediaType == .movie {
            await loadMovieDetails()
        } else {
            await loadTVDetails()
        }
    }
    
    private func loadMovieDetails() async {
        let movieId = item.id
        let region = StorageService.shared.settings.region
        
        // Phase 1: Load core details first (needed for collection lookup & savedItem)
        do {
            let details = try await TMDBService.shared.getMovieDetails(id: movieId)
            
            overview = details.overview
            runtime = details.runtimeFormatted
            genres = details.genres?.map { $0.name }.joined(separator: ", ")
            status = details.status
            originalTitle = details.originalTitle != details.title ? details.originalTitle : nil
            tmdbRating = details.voteAverage
            productionCompanies = details.productionCompanies ?? []
            originCountry = details.productionCountries?.first?.name
            if let budgetValue = details.budget, budgetValue > 0 {
                budget = currencyFormatter.string(from: NSNumber(value: budgetValue))
            }
            if let revenueValue = details.revenue, revenueValue > 0 {
                revenue = currencyFormatter.string(from: NSNumber(value: revenueValue))
            }
            
            savedItem = SavedMediaItem(from: details)
            collectionInfo = details.belongsToCollection
            imdbId = details.imdbId
        } catch {
            print("Error loading movie details: \(error)")
            overview = item.overview
        }
        
        // Phase 2: Load everything else concurrently
        await withTaskGroup(of: Void.self) { group in
            // Collection items
            if let collection = collectionInfo {
                group.addTask { @MainActor in
                    do {
                        let details = try await TMDBService.shared.getCollectionDetails(id: collection.id)
                        self.collectionItems = details.parts
                            .filter { $0.id != movieId }
                            .sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }
                    } catch {
                        print("Error loading collection: \(error)")
                    }
                }
            }
            
            // Title logo — FanArt.tv primary, TMDB fallback
            group.addTask { @MainActor in
                // Try FanArt.tv first
                if let fanartLogo = await FanArtService.shared.getBestLogoURL(tmdbId: movieId, mediaType: .movie) {
                    self.logoFullURL = fanartLogo.absoluteString
                } else {
                    // TMDB fallback
                    do {
                        let logos = try await TMDBService.shared.getMediaLogos(mediaType: .movie, id: movieId)
                        self.logoPath = self.selectPreferredLogo(from: logos)
                    } catch {
                        print("Error loading movie logos: \(error)")
                    }
                }
            }
            
            // FanArt backdrop
            group.addTask { @MainActor in
                if let fanartBG = await FanArtService.shared.getBestBackdropURL(tmdbId: movieId, mediaType: .movie) {
                    self.fanartBackdropURL = fanartBG.absoluteString
                }
            }
            
            // Mid/post-credits scene tags
            group.addTask { @MainActor in
                let keywords = await TMDBService.shared.getKeywords(id: movieId, mediaType: .movie)
                self.creditsStingers = CreditsStingers(keywords: keywords)
            }

            // Certification
            group.addTask { @MainActor in
                do {
                    let certification = try await TMDBService.shared.getMovieCertification(id: movieId)
                    self.certificate = certification
                } catch {
                    print("Error loading movie certification: \(error)")
                }
            }
            
            // Credits
            group.addTask { @MainActor in
                do {
                    let credits = try await TMDBService.shared.getMovieCredits(id: movieId)
                    self.cast = credits.cast ?? []
                    self.crew = credits.crew ?? []
                } catch {
                    print("Error loading credits: \(error)")
                }
            }
            
            // Videos + Trailerio addon fetch
            group.addTask { @MainActor in
                do {
                    let videosResponse = try await TMDBService.shared.getMovieVideos(id: movieId)
                    self.videos = videosResponse.results
                } catch {
                    print("Error loading videos: \(error)")
                }

                // Fetch Trailerio / addon trailers (Direct URLs playable via AVPlayer on tvOS)
                if let imdbId = self.imdbId {
                    let addons = StorageService.shared.settings.trailerAddons
                    let addonVideos = await TrailerAddonService.shared.fetchTrailers(
                        imdbID: imdbId,
                        mediaType: .movie,
                        addons: addons
                    )
                    self.videos.append(contentsOf: addonVideos)
                }

                self.preferredTrailer = self.computePreferredTrailer(from: self.videos)
            }
            
            // Watch providers + deep links
            group.addTask { @MainActor in
                do {
                    let providers = try await TMDBService.shared.getMovieWatchProviders(id: movieId)
                    if let allResults = providers.results {
                        self.allWatchProviderRegions = allResults
                    }
                    if let regionData = providers.results?[region] {
                        self.watchProviders = regionData
                        self.watchProvidersLink = regionData.link
                    }
                } catch {
                    print("Error loading providers: \(error)")
                }
                // Fetch MOTN deep links for the user's region
                let links = await StreamingDeepLinkService.shared.fetchDeepLinks(
                    tmdbId: movieId,
                    mediaType: .movie,
                    country: region
                )
                self.deepLinks = links
            }
            
            // Similar
            group.addTask { @MainActor in
                do {
                    let similarResponse = try await TMDBService.shared.getSimilarMovies(id: movieId)
                    self.similar = similarResponse.results
                } catch {
                    print("Error loading similar: \(error)")
                }
            }
            
            // Recommendations
            group.addTask { @MainActor in
                do {
                    let recsResponse = try await TMDBService.shared.getMovieRecommendations(id: movieId)
                    self.recommendations = recsResponse.results
                } catch {
                    print("Error loading recommendations: \(error)")
                }
            }
            
            // Ratings — MDBList primary (has RT, IMDb, Meta, etc.), OMDb fallback
            group.addTask { @MainActor in
                // Try MDBList first
                if let mdbRatings = await MDBListService.shared.getRatingsSummary(tmdbId: movieId, mediaType: .movie) {
                    self.ratings = mdbRatings
                } else {
                    // OMDb fallback (needs IMDb ID from TMDB details)
                    do {
                        let movieDetails = try await TMDBService.shared.getMovieDetails(id: movieId)
                        if let imdbId = movieDetails.imdbId {
                            self.ratings = await OMDbService.shared.getRatingsSummary(imdbId: imdbId)
                        }
                    } catch {
                        print("Error loading movie ratings fallback: \(error)")
                    }
                }
            }
        }
    }
    
    private func loadTVDetails() async {
        let tvId = item.id
        let region = StorageService.shared.settings.region
        
        // Phase 1: Load core details first (needed for savedItem, seasons)
        do {
            let details = try await TMDBService.shared.getTVShowDetails(id: tvId)
            
            overview = details.overview
            genres = details.genres?.map { $0.name }.joined(separator: ", ")
            status = details.status
            originalTitle = details.originalName != details.name ? details.originalName : nil
            tmdbRating = details.voteAverage
            seasons = details.seasons
            productionCompanies = details.productionCompanies ?? []
            originCountry = details.originCountry?.first
            if let episodeRuntime = details.episodeRunTime?.first {
                runtime = "\(episodeRuntime)m per episode"
            }
            
            savedItem = SavedMediaItem(from: details)
            imdbId = details.externalIds?.imdbId
        } catch {
            print("Error loading TV details: \(error)")
            overview = item.overview
        }
        
        // Phase 2: Load everything else concurrently
        await withTaskGroup(of: Void.self) { group in
            // Title logo — FanArt.tv primary, TMDB fallback
            group.addTask { @MainActor in
                if let fanartLogo = await FanArtService.shared.getBestLogoURL(tmdbId: tvId, mediaType: .tv) {
                    self.logoFullURL = fanartLogo.absoluteString
                } else {
                    do {
                        let logos = try await TMDBService.shared.getMediaLogos(mediaType: .tv, id: tvId)
                        self.logoPath = self.selectPreferredLogo(from: logos)
                    } catch {
                        print("Error loading TV logos: \(error)")
                    }
                }
            }
            
            // FanArt backdrop
            group.addTask { @MainActor in
                if let fanartBG = await FanArtService.shared.getBestBackdropURL(tmdbId: tvId, mediaType: .tv) {
                    self.fanartBackdropURL = fanartBG.absoluteString
                }
            }
            
            // Certification
            group.addTask { @MainActor in
                do {
                    let certification = try await TMDBService.shared.getTVCertification(id: tvId)
                    self.certificate = certification
                } catch {
                    print("Error loading TV certification: \(error)")
                }
            }
            
            // Credits
            group.addTask { @MainActor in
                do {
                    let credits = try await TMDBService.shared.getTVShowCredits(id: tvId)
                    self.cast = credits.cast ?? []
                    self.crew = credits.crew ?? []
                } catch {
                    print("Error loading credits: \(error)")
                }
            }
            
            // Videos + Trailerio addon fetch
            group.addTask { @MainActor in
                do {
                    let videosResponse = try await TMDBService.shared.getTVShowVideos(id: tvId)
                    self.videos = videosResponse.results
                } catch {
                    print("Error loading videos: \(error)")
                }

                // Fetch Trailerio / addon trailers (Direct URLs playable via AVPlayer on tvOS)
                if let imdbId = self.imdbId {
                    let addons = StorageService.shared.settings.trailerAddons
                    let addonVideos = await TrailerAddonService.shared.fetchTrailers(
                        imdbID: imdbId,
                        mediaType: .tv,
                        addons: addons
                    )
                    self.videos.append(contentsOf: addonVideos)
                }

                self.preferredTrailer = self.computePreferredTrailer(from: self.videos)
            }
            
            // Watch providers + deep links
            group.addTask { @MainActor in
                do {
                    let providers = try await TMDBService.shared.getTVShowWatchProviders(id: tvId)
                    if let allResults = providers.results {
                        self.allWatchProviderRegions = allResults
                    }
                    if let regionData = providers.results?[region] {
                        self.watchProviders = regionData
                        self.watchProvidersLink = regionData.link
                    }
                } catch {
                    print("Error loading providers: \(error)")
                }
                // Fetch MOTN deep links for the user's region
                let links = await StreamingDeepLinkService.shared.fetchDeepLinks(
                    tmdbId: tvId,
                    mediaType: .tv,
                    country: region
                )
                self.deepLinks = links
            }
            
            // Similar
            group.addTask { @MainActor in
                do {
                    let similarResponse = try await TMDBService.shared.getSimilarTVShows(id: tvId)
                    self.similar = similarResponse.results
                } catch {
                    print("Error loading similar: \(error)")
                }
            }
            
            // Recommendations
            group.addTask { @MainActor in
                do {
                    let recsResponse = try await TMDBService.shared.getTVShowRecommendations(id: tvId)
                    self.recommendations = recsResponse.results
                } catch {
                    print("Error loading recommendations: \(error)")
                }
            }
            
            // Ratings — MDBList primary (has RT, IMDb, Meta, etc.), OMDb fallback
            group.addTask { @MainActor in
                // Try MDBList first
                if let mdbRatings = await MDBListService.shared.getRatingsSummary(tmdbId: tvId, mediaType: .tv) {
                    self.ratings = mdbRatings
                } else {
                    // OMDb fallback (needs IMDb ID via external IDs)
                    do {
                        let details = try await TMDBService.shared.getTVShowDetails(id: tvId)
                        if let imdbId = details.externalIds?.imdbId {
                            self.ratings = await OMDbService.shared.getRatingsSummary(imdbId: imdbId)
                        }
                    } catch {
                        print("Error loading TV ratings: \(error)")
                    }
                }
            }
        }
    }
    
    private func selectPreferredLogo(from logos: [MediaImage]) -> String? {
        if let english = logos.first(where: { $0.iso639_1 == "en" }) {
            return english.filePath
        }
        return logos.first?.filePath
    }

    private func computePreferredTrailer(from videos: [Video]) -> Video? {
        // Prefer direct-play (Trailerio/addon) trailers on all platforms — VPN-safe, no WKWebView needed
        let directTrailers = videos.filter { $0.site.lowercased() == "direct" && $0.type.lowercased() == "trailer" }
        if let direct = directTrailers.first { return direct }
        let anyDirect = videos.first { $0.site.lowercased() == "direct" }
        if let direct = anyDirect { return direct }

        let yt = videos.filter { $0.site.lowercased() == "youtube" }
        let filtered = yt.filter { video in
            let name = video.name.lowercased()
            let type = video.type.lowercased()
            let isTrailer = type == "trailer" || type == "teaser"
            let isFinal = name.contains("final trailer") || name.contains("final teaser") || name.contains("final")
            return isTrailer && !isFinal
        }
        let officialTrailer = filtered.first { $0.type.lowercased() == "trailer" && ($0.official == true) }
        if let t = officialTrailer { return t }
        let officialTeaser = filtered.first { $0.type.lowercased() == "teaser" && ($0.official == true) }
        if let t = officialTeaser { return t }
        let anyTrailer = filtered.first { $0.type.lowercased() == "trailer" }
        if let t = anyTrailer { return t }
        let anyTeaser = filtered.first { $0.type.lowercased() == "teaser" }
        if let t = anyTeaser { return t }
        return fallbackTrailerForItem()
    }

    private func fallbackTrailerForItem() -> Video? {
        let title = item.displayTitle.lowercased()
        if title == "the fantastic four: first steps" {
            return Video(
                id: "yt_pAsmrKyMqaA",
                key: "pAsmrKyMqaA",
                name: "The Fantastic Four: First Steps | Trailer",
                site: "YouTube",
                type: "Trailer",
                official: true,
                publishedAt: nil
            )
        }
        return nil
    }
}

#Preview {
    MediaDetailView(item: MediaItem(
        id: 550,
        title: "Fight Club",
        name: nil,
        originalTitle: nil,
        originalName: nil,
        overview: "A ticking-Loss control specialist forms an underground club with a soap salesman.",
        posterPath: nil,
        backdropPath: nil,
        releaseDate: "1999-10-15",
        firstAirDate: nil,
        voteAverage: 8.4,
        voteCount: nil,
        popularity: nil,
        genreIds: nil,
        mediaType: "movie",
        adult: nil,
        originalLanguage: nil
    ))
}
