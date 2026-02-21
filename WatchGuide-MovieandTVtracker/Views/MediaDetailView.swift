//
//  MediaDetailView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if canImport(SafariServices)
import SafariServices
#endif
#if !os(tvOS)
import YouTubePlayerKit
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
    @State private var selectedSeason: Season?
    @State private var selectedPerson: SelectedPerson?
    @State private var selectedCompanyHub: CompanyHub?
    @State private var selectedCompanyItem: MediaItem?

    @State private var selectedTrailer: Video?
    @State private var safariItem: SafariItem?
    @State private var showInlineTrailer = false

    init(item: MediaItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: MediaDetailViewModel(item: item))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero Header (inline player or static backdrop)
                    headerSection
                    
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
                            
                            #if !os(tvOS)
                            if let trailer = viewModel.preferredTrailer {
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
                        }
                        
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
                                Text("Overview")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                
                                Text(overview)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        }
                        
                        if viewModel.isMovie {
                            PostCreditsScoutSection(
                                summary: viewModel.postCreditsSummary,
                                isLoading: viewModel.isPostCreditsLoading,
                                errorMessage: viewModel.postCreditsError,
                                onCheck: {
                                    Task { await viewModel.fetchPostCreditsWorthIt() }
                                }
                            )
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
                                    link: viewModel.watchProvidersLink
                                )
                                .padding(.horizontal)
                            }
                        }
                        
                        // Collection
                        if let collectionInfo = viewModel.collectionInfo, !viewModel.collectionItems.isEmpty {
                            CollectionRowView(
                                collectionName: collectionInfo.name,
                                items: viewModel.collectionItems,
                                onItemTap: { _ in }
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
                                onItemTap: { _ in }
                            )
                        }
                        
                        // Recommendations
                        if !viewModel.recommendations.isEmpty {
                            MediaRowView(
                                title: "Recommended",
                                items: viewModel.recommendations,
                                onItemTap: { _ in }
                            )
                        }
                        
                        // Additional Info
                        additionalInfoSection
                    }
                    .padding(.vertical, 24)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .task {
            await viewModel.loadDetails()
        }
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
        #if os(iOS)
        .sheet(item: $safariItem) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        #endif
    }
    
    // MARK: - Header Section (Auto-Playing Trailer)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var headerPlayerVM = DetailHeaderPlayerViewModel()
    @State private var headerTrailerReady = false
    
    private var headerSection: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width * 9.0 / 16.0
            let isCompact = verticalSizeClass == .compact
            
            ZStack(alignment: .bottomLeading) {
                // Layer 0: Black base
                Color.black
                
                // Layer 1: Trailer video (underneath the backdrop)
                #if !os(tvOS)
                if headerTrailerReady, let player = headerPlayerVM.player {
                    YouTubePlayerKit.YouTubePlayerView(player)
                        .frame(width: width, height: height)
                        .allowsHitTesting(false)
                }
                #endif
                
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
                .opacity(headerTrailerReady ? 0 : 1)
                .animation(.easeInOut(duration: 0.8), value: headerTrailerReady)
                
                // Layer 3: Gradient overlay
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7), .black.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width, height: height)
                
                // Layer 4: Content overlay
                VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
                    // Type badge
                    Text(item.resolvedMediaType == .movie ? "MOVIE" : "TV SHOW")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    
                    // Logo or Title — show logo when available, text fallback otherwise
                    if let logoURL = resolvedDetailLogoURL(width: width, height: height) {
                        AsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .renderingMode(.original)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: min(width * 0.55, 280), maxHeight: isCompact ? 50 : 65)
                                    .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 3)
                            default:
                                Text(item.displayTitle)
                                    .font(isCompact ? .title3 : .title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .lineLimit(isCompact ? 2 : 3)
                            }
                        }
                    } else {
                        Text(item.displayTitle)
                            .font(isCompact ? .title3 : .title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(isCompact ? 2 : 3)
                    }
                    
                    // Meta info
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
                    
                    // Genres
                    if let genres = viewModel.genres {
                        Text(genres)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .padding(isCompact ? 12 : 16)
                .padding(.bottom, isCompact ? 4 : 8)
                
                // Layer 5: Mute button (top-right, only when trailer is playing)
                if headerTrailerReady {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                headerPlayerVM.toggleMute()
                            } label: {
                                Image(systemName: headerPlayerVM.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(.black.opacity(0.5)))
                            }
                            .padding(.top, 8)
                            .padding(.trailing, 12)
                        }
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: width, height: height)
        }
        .aspectRatio(16.0/9.0, contentMode: .fit)
        #if !os(tvOS)
        .onChange(of: viewModel.preferredTrailer?.key) { _, newKey in
            if let key = newKey, headerPlayerVM.player == nil {
                headerPlayerVM.setup(videoKey: key)
            }
        }
        .onReceive(viewModel.$preferredTrailer) { trailer in
            // Catch the initial value that onChange might miss
            if let key = trailer?.key, headerPlayerVM.player == nil {
                headerPlayerVM.setup(videoKey: key)
            }
        }
        .onReceive(headerPlayerVM.$isReady) { ready in
            if ready {
                withAnimation(.easeInOut(duration: 0.6)) {
                    headerTrailerReady = true
                }
            }
        }
        #endif
        .onDisappear {
            headerPlayerVM.teardown()
        }
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
                    .fill(Color(.systemGray4))
            }
        }
    }
    
    /// Resolves the logo URL for the detail header: FanArt.tv full URL first, TMDB path second
    private func resolvedDetailLogoURL(width: CGFloat, height: CGFloat) -> URL? {
        if let fullStr = viewModel.logoFullURL, let url = URL(string: fullStr) { return url }
        if let path = viewModel.logoPath { return TMDBService.shared.imageURL(path: path, size: .logo) }
        return nil
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
            .background(.ultraThinMaterial)
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
        .onHover { hovering in
            isHovered = hovering
        }
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
            .navigationBarTitleDisplayMode(.inline)
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
                        .fill(Color(.systemGray5))
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
            skipMapError = "Scout AI isn’t configured."
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
                model: .gemini25Flash,
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
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

// MARK: - Post-Credits Scout
private struct PostCreditsScoutSection: View {
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
                Spacer()
                if summary != nil || errorMessage != nil {
                    Button("Check again") {
                        onCheck()
                    }
                    .font(.caption)
                }
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Scout is checking the web...")
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
                    Text("Ask Scout if it’s worth staying")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
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

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                            radius: 6,
                            x: 0,
                            y: 3
                        )

                    if let url = logoURL {
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

                Text(company.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
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
    @Published var postCreditsSummary: String?
    @Published var postCreditsError: String?
    @Published var isPostCreditsLoading = false
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
            postCreditsError = "Scout AI isn’t configured. Add your API key in Settings."
            return
        }

        if AIMessageQuota.remainingMessages() <= 0 {
            postCreditsError = "Daily Scout limit reached. Try again tomorrow."
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
                model: .gemini25Flash,
                restrictedMode: false
            )
            postCreditsSummary = response
            postCreditsError = nil
            AIMessageQuota.consumeMessage()
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
            
            // Videos
            group.addTask { @MainActor in
                do {
                    let videosResponse = try await TMDBService.shared.getMovieVideos(id: movieId)
                    self.videos = videosResponse.results
                    self.preferredTrailer = self.computePreferredTrailer(from: self.videos)
                } catch {
                    print("Error loading videos: \(error)")
                }
            }
            
            // Watch providers
            group.addTask { @MainActor in
                do {
                    let providers = try await TMDBService.shared.getMovieWatchProviders(id: movieId)
                    if let regionData = providers.results?[region] {
                        self.watchProviders = regionData
                        self.watchProvidersLink = regionData.link
                    }
                } catch {
                    print("Error loading providers: \(error)")
                }
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
            
            // Videos
            group.addTask { @MainActor in
                do {
                    let videosResponse = try await TMDBService.shared.getTVShowVideos(id: tvId)
                    self.videos = videosResponse.results
                    self.preferredTrailer = self.computePreferredTrailer(from: self.videos)
                } catch {
                    print("Error loading videos: \(error)")
                }
            }
            
            // Watch providers
            group.addTask { @MainActor in
                do {
                    let providers = try await TMDBService.shared.getTVShowWatchProviders(id: tvId)
                    if let regionData = providers.results?[region] {
                        self.watchProviders = regionData
                        self.watchProvidersLink = regionData.link
                    }
                } catch {
                    print("Error loading providers: \(error)")
                }
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
        return anyTeaser
    }
}

// MARK: - Detail Header Player ViewModel
/// Manages a YouTube player for the detail page header auto-play trailer.
/// Similar to HeroPlayerViewModel but simplified — always auto-plays muted,
/// loops, and has no external mute integration.
#if !os(tvOS)
class DetailHeaderPlayerViewModel: ObservableObject {
    @Published var player: YouTubePlayer?
    @Published var isReady = false
    @Published var isMuted = true
    
    private var stateCancellable: AnyCancellable?
    
    @MainActor
    func setup(videoKey: String) {
        guard player == nil else { return }
        
        let startMuted = StorageService.shared.settings.autoPlayTrailersMuted
        isMuted = startMuted
        
        let ytPlayer = YouTubePlayer(
            source: .video(id: videoKey),
            parameters: .init(
                autoPlay: true,
                loopEnabled: true,
                showControls: false,
                showFullscreenButton: false,
                keyboardControlsDisabled: true,
                restrictRelatedVideosToSameChannel: true
            ),
            configuration: .init(
                allowsInlineMediaPlayback: true,
                openURLAction: .init { _, _ in }
            )
        )
        
        player = ytPlayer
        
        stateCancellable = ytPlayer.statePublisher.sink { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .ready = state {
                    self.isReady = true
                    Task {
                        // Always mute first to satisfy iOS autoplay policy
                        try? await ytPlayer.mute()
                        try? await ytPlayer.play()
                        if !self.isMuted {
                            try? await ytPlayer.unmute()
                        }
                    }
                }
            }
        }
    }
    
    func teardown() {
        Task { @MainActor in
            if let p = player {
                try? await p.pause()
            }
            player = nil
            isReady = false
            stateCancellable = nil
        }
    }
    
    func toggleMute() {
        isMuted.toggle()
        guard let p = player else { return }
        Task {
            if isMuted {
                try? await p.mute()
            } else {
                try? await p.unmute()
            }
        }
    }
}
#else
class DetailHeaderPlayerViewModel: ObservableObject {
    @Published var isReady = false
    @Published var isMuted = true
    
    @MainActor
    func setup(videoKey: String) {
    }
    
    func teardown() {
    }
    
    func toggleMute() {
    }
}
#endif

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
