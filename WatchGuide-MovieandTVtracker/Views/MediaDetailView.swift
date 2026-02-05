//
//  MediaDetailView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import WebKit // For WebTrailerPlayerView usage

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
    @State private var isHeroUnmuted: Bool = false

    // Precomputed first YouTube trailer to reduce type-checking load
    private var firstYouTubeTrailer: Video? {
        viewModel.videos.first { video in
            let site = video.site.lowercased()
            let type = video.type.lowercased()
            return site == "youtube" && (type == "trailer" || type == "teaser")
        }
    }
    
    private var trailerVideos: [Video] {
        let trailers = viewModel.videos.filter { v in
            v.site.lowercased() == "youtube" &&
            v.type.lowercased() == "trailer" &&
            (v.name.lowercased().contains("official") || (v.official ?? false))
        }
        if !trailers.isEmpty {
            return trailers
        } else {
            let teasers = viewModel.videos.filter { v in
                v.site.lowercased() == "youtube" && v.type.lowercased() == "teaser"
            }
            return teasers
        }
    }
    
    private func youTubeEmbedURL(for key: String) -> URL? {
        URL(string: "https://www.youtube.com/embed/\(key)?playsinline=1")
    }
    
    init(item: MediaItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: MediaDetailViewModel(item: item))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero Header
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
                        }
                        
                        // Ratings
                        if viewModel.ratings != nil || viewModel.tmdbRating != nil {
                            RatingsView(
                                ratings: viewModel.ratings,
                                tmdbRating: viewModel.tmdbRating
                            )
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
                        
                        // TV Show Seasons
                        if let seasons = viewModel.seasons, !seasons.isEmpty {
                            seasonsSection(seasons: seasons)
                        }
                        
                        // Existing videos row
                        if !viewModel.videos.isEmpty {
                            VideoRowView(videos: viewModel.videos)
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
    }
    
    // MARK: - Header Section
    
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    private var headerSection: some View {
        if !trailerVideos.isEmpty {
            AnyView(
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let height = width * 9.0 / 16.0
                    
                    TabView {
                        ForEach(trailerVideos) { video in
                            ZStack(alignment: .bottomLeading) {
                                WebTrailerPlayerView(videoKey: video.key, autoplay: true, muted: !isHeroUnmuted)
                                    .frame(width: width, height: height)
                                    .background(Color.black)
                                
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.6), .black.opacity(0.9)],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )
                                .frame(height: height * 0.4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .allowsHitTesting(false)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(video.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 40)
                            }
                            .frame(width: width, height: height)
                        }
                    }
                    .frame(width: width, height: height)
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .onTapGesture {
                        withAnimation {
                            isHeroUnmuted = true
                        }
                    }
                    .overlay(
                        Button {
                            withAnimation {
                                isHeroUnmuted.toggle()
                            }
                        } label: {
                            Image(systemName: isHeroUnmuted ? "speaker.wave.3.fill" : "speaker.slash.fill")
                                .font(.body)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(12)
                        , alignment: .bottomTrailing
                    )
                }
                .aspectRatio(16.0/9.0, contentMode: .fit)
            )
        } else {
            AnyView(staticHeaderSection)
        }
    }
    
    private var staticHeaderSection: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width * 9.0 / 16.0
            let isCompact = verticalSizeClass == .compact
            
            ZStack(alignment: .bottomLeading) {
                // Backdrop - use aspectRatio fit to show entire image
                AsyncImage(url: TMDBService.shared.imageURL(path: item.backdropPath, size: .backdrop)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    default:
                        Rectangle()
                            .fill(Color(.systemGray4))
                    }
                }
                .frame(width: width, height: height)
                .background(Color.black)
                
                // Gradient overlay
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7), .black.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width, height: height)
                
                // Content overlay
                HStack(alignment: .bottom, spacing: isCompact ? 12 : 16) {
                    // Poster
                    PosterImageView(posterPath: item.posterPath, size: .large)
                        .frame(width: isCompact ? 80 : 110, height: isCompact ? 120 : 165)
                        .shadow(radius: 10)
                    
                    // Info
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
                        
                        // Title
                        Text(item.displayTitle)
                            .font(isCompact ? .title3 : .title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(isCompact ? 2 : 3)
                        
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
                }
                .padding(isCompact ? 12 : 16)
                .padding(.bottom, isCompact ? 4 : 8)
            }
            .frame(width: width, height: height)
        }
        .aspectRatio(16.0/9.0, contentMode: .fit)
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
                        EpisodeRow(episode: episode)
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
    let episode: Episode
    
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
    @Published var cast: [CastMember] = []
    @Published var crew: [CrewMember] = []
    @Published var videos: [Video] = []
    @Published var similar: [MediaItem] = []
    @Published var recommendations: [MediaItem] = []
    @Published var watchProviders: WatchProviderRegion?
    @Published var watchProvidersLink: String?
    @Published var seasons: [Season]?
    @Published var savedItem: SavedMediaItem?
    
    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    
    init(item: MediaItem) {
        self.item = item
    }
    
    func loadDetails() async {
        if item.resolvedMediaType == .movie {
            await loadMovieDetails()
        } else {
            await loadTVDetails()
        }
    }
    
    private func loadMovieDetails() async {
        // Load movie details
        do {
            let details = try await TMDBService.shared.getMovieDetails(id: item.id)
            
            overview = details.overview
            runtime = details.runtimeFormatted
            genres = details.genres?.map { $0.name }.joined(separator: ", ")
            status = details.status
            originalTitle = details.originalTitle != details.title ? details.originalTitle : nil
            tmdbRating = details.voteAverage
            
            if let budgetValue = details.budget, budgetValue > 0 {
                budget = currencyFormatter.string(from: NSNumber(value: budgetValue))
            }
            if let revenueValue = details.revenue, revenueValue > 0 {
                revenue = currencyFormatter.string(from: NSNumber(value: revenueValue))
            }
            
            savedItem = SavedMediaItem(from: details)
            
            // Load OMDb ratings
            if let imdbId = details.imdbId {
                ratings = await OMDbService.shared.getRatingsSummary(imdbId: imdbId)
            }
        } catch {
            print("Error loading movie details: \(error)")
            overview = item.overview
        }
        
        // Load credits
        do {
            let credits = try await TMDBService.shared.getMovieCredits(id: item.id)
            cast = credits.cast ?? []
            crew = credits.crew ?? []
        } catch {
            print("Error loading credits: \(error)")
        }
        
        // Load videos
        do {
            let videosResponse = try await TMDBService.shared.getMovieVideos(id: item.id)
            videos = videosResponse.results
        } catch {
            print("Error loading videos: \(error)")
        }
        
        // Load watch providers
        do {
            let providers = try await TMDBService.shared.getMovieWatchProviders(id: item.id)
            let region = StorageService.shared.settings.region
            if let regionData = providers.results?[region] {
                watchProviders = regionData
                watchProvidersLink = regionData.link
            }
        } catch {
            print("Error loading providers: \(error)")
        }
        
        // Load similar and recommendations
        do {
            let similarResponse = try await TMDBService.shared.getSimilarMovies(id: item.id)
            similar = similarResponse.results
            
            let recsResponse = try await TMDBService.shared.getMovieRecommendations(id: item.id)
            recommendations = recsResponse.results
        } catch {
            print("Error loading similar: \(error)")
        }
    }
    
    private func loadTVDetails() async {
        // Load TV details
        do {
            let details = try await TMDBService.shared.getTVShowDetails(id: item.id)
            
            overview = details.overview
            genres = details.genres?.map { $0.name }.joined(separator: ", ")
            status = details.status
            originalTitle = details.originalName != details.name ? details.originalName : nil
            tmdbRating = details.voteAverage
            seasons = details.seasons
            
            if let episodeRuntime = details.episodeRunTime?.first {
                runtime = "\(episodeRuntime)m per episode"
            }
            
            savedItem = SavedMediaItem(from: details)
            
            // Load OMDb ratings
            if let imdbId = details.externalIds?.imdbId {
                ratings = await OMDbService.shared.getRatingsSummary(imdbId: imdbId)
            }
        } catch {
            print("Error loading TV details: \(error)")
            overview = item.overview
        }
        
        // Load credits
        do {
            let credits = try await TMDBService.shared.getTVShowCredits(id: item.id)
            cast = credits.cast ?? []
            crew = credits.crew ?? []
        } catch {
            print("Error loading credits: \(error)")
        }
        
        // Load videos
        do {
            let videosResponse = try await TMDBService.shared.getTVShowVideos(id: item.id)
            videos = videosResponse.results
        } catch {
            print("Error loading videos: \(error)")
        }
        
        // Load watch providers
        do {
            let providers = try await TMDBService.shared.getTVShowWatchProviders(id: item.id)
            let region = StorageService.shared.settings.region
            if let regionData = providers.results?[region] {
                watchProviders = regionData
                watchProvidersLink = regionData.link
            }
        } catch {
            print("Error loading providers: \(error)")
        }
        
        // Load similar and recommendations
        do {
            let similarResponse = try await TMDBService.shared.getSimilarTVShows(id: item.id)
            similar = similarResponse.results
            
            let recsResponse = try await TMDBService.shared.getTVShowRecommendations(id: item.id)
            recommendations = recsResponse.results
        } catch {
            print("Error loading similar: \(error)")
        }
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

