//
//  LocalModels.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

// MARK: - List Types
enum ListType: String, Codable, CaseIterable, Identifiable {
    case wantToWatch = "want_to_watch"
    case watched = "watched"
    case liked = "liked"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .wantToWatch: return "Want to Watch"
        case .watched: return "Watched"
        case .liked: return "Liked"
        case .custom: return "Custom"
        }
    }
    
    var iconName: String {
        switch self {
        case .wantToWatch: return "bookmark.fill"
        case .watched: return "checkmark.circle.fill"
        case .liked: return "heart.fill"
        case .custom: return "folder.fill"
        }
    }
}

// MARK: - Saved Media Item
struct SavedMediaItem: Identifiable, Codable, Hashable {
    let id: String
    let mediaId: Int
    let mediaType: MediaType
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let year: String?
    let voteAverage: Double?
    let overview: String?
    let addedAt: Date
    
    init(from mediaItem: MediaItem) {
        self.id = "\(mediaItem.resolvedMediaType.rawValue)-\(mediaItem.id)"
        self.mediaId = mediaItem.id
        self.mediaType = mediaItem.resolvedMediaType
        self.title = mediaItem.displayTitle
        self.posterPath = mediaItem.posterPath
        self.backdropPath = mediaItem.backdropPath
        self.year = mediaItem.year
        self.voteAverage = mediaItem.voteAverage
        self.overview = mediaItem.overview
        self.addedAt = Date()
    }
    
    init(from movie: MovieDetails) {
        self.id = "movie-\(movie.id)"
        self.mediaId = movie.id
        self.mediaType = .movie
        self.title = movie.title
        self.posterPath = movie.posterPath
        self.backdropPath = movie.backdropPath
        self.year = movie.year
        self.voteAverage = movie.voteAverage
        self.overview = movie.overview
        self.addedAt = Date()
    }
    
    init(from tvShow: TVShowDetails) {
        self.id = "tv-\(tvShow.id)"
        self.mediaId = tvShow.id
        self.mediaType = .tv
        self.title = tvShow.name
        self.posterPath = tvShow.posterPath
        self.backdropPath = tvShow.backdropPath
        self.year = tvShow.year
        self.voteAverage = tvShow.voteAverage
        self.overview = tvShow.overview
        self.addedAt = Date()
    }
}

// MARK: - Custom List
struct CustomList: Identifiable, Codable {
    let id: String
    var name: String
    var description: String?
    var iconName: String
    var items: [SavedMediaItem]
    var displayStyle: DisplayStyle
    let createdAt: Date
    var updatedAt: Date
    
    enum DisplayStyle: String, Codable, CaseIterable {
        case row
        case grid
        
        var displayName: String {
            switch self {
            case .row: return "Row"
            case .grid: return "Grid"
            }
        }
    }
    
    init(name: String, description: String? = nil, iconName: String = "folder.fill", displayStyle: DisplayStyle = .row) {
        self.id = UUID().uuidString
        self.name = name
        self.description = description
        self.iconName = iconName
        self.items = []
        self.displayStyle = displayStyle
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Company Hub
struct CompanyHub: Identifiable, Codable {
    let id: String
    let name: String
    let logoPath: String?
    let companyIds: [Int]
    let networkIds: [Int]
    var isEnabled: Bool
    let createdAt: Date
    
    init(name: String, logoPath: String? = nil, companyIds: [Int] = [], networkIds: [Int] = []) {
        self.id = UUID().uuidString
        self.name = name
        self.logoPath = logoPath
        self.companyIds = companyIds
        self.networkIds = networkIds
        self.isEnabled = true
        self.createdAt = Date()
    }
}

// MARK: - PublicMetaDB List
struct ImportedListItem: Identifiable, Codable {
    let id: String
    var name: String
    var listId: String
    var items: [SavedMediaItem]
    var lastSynced: Date?
    let createdAt: Date
    var showOnHome: Bool
    var customName: String?
    
    init(name: String, listId: String, showOnHome: Bool = false) {
        self.id = UUID().uuidString
        self.name = name
        self.listId = listId
        self.items = []
        self.lastSynced = nil
        self.createdAt = Date()
        self.showOnHome = showOnHome
        self.customName = nil
    }
    
    var displayName: String {
        customName ?? name
    }
}

// MARK: - Custom Home Row
struct CustomHomeRow: Identifiable, Codable {
    let id: String
    var name: String
    var rowType: CustomRowType
    var sortOrder: Int
    var isEnabled: Bool
    let createdAt: Date
    
    // For imported list rows
    var importedListId: String?
    
    // For custom hub rows
    var hubImageURL: String?
    var items: [SavedMediaItem]?
    
    enum CustomRowType: String, Codable {
        case importedList = "imported_list"
        case customHub = "custom_hub"
    }
    
    init(name: String, rowType: CustomRowType, sortOrder: Int = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.rowType = rowType
        self.sortOrder = sortOrder
        self.isEnabled = true
        self.createdAt = Date()
        self.importedListId = nil
        self.hubImageURL = nil
        self.items = nil
    }
    
    static func importedListRow(name: String, listId: String, sortOrder: Int = 0) -> CustomHomeRow {
        var row = CustomHomeRow(name: name, rowType: .importedList, sortOrder: sortOrder)
        row.importedListId = listId
        return row
    }
    
    static func hubRow(name: String, imageURL: String?, sortOrder: Int = 0) -> CustomHomeRow {
        var row = CustomHomeRow(name: name, rowType: .customHub, sortOrder: sortOrder)
        row.hubImageURL = imageURL
        row.items = []
        return row
    }
}

// MARK: - Hero Carousel Source
enum HeroCarouselSource: String, Codable, CaseIterable {
    case trendingMovies = "trending_movies"
    case trendingTV = "trending_tv"
    case popularMovies = "popular_movies"
    case popularTV = "popular_tv"
    case nowPlayingMovies = "now_playing_movies"
    case topRatedMovies = "top_rated_movies"
    case upcomingMovies = "upcoming_movies"
    
    var displayName: String {
        switch self {
        case .trendingMovies: return "Trending Movies"
        case .trendingTV: return "Trending TV Shows"
        case .popularMovies: return "Popular Movies"
        case .popularTV: return "Popular TV Shows"
        case .nowPlayingMovies: return "Now Playing"
        case .topRatedMovies: return "Top Rated Movies"
        case .upcomingMovies: return "Upcoming Movies"
        }
    }
}

// MARK: - User Settings
struct UserSettings: Codable, Equatable {
    var region: String
    var includeAdult: Bool
    var preferredLanguage: String
    var autoPlayTrailers: Bool
    var compactMode: Bool
    var heroCarouselSource: HeroCarouselSource
    
    init() {
        self.region = Locale.current.region?.identifier ?? "US"
        self.includeAdult = false
        self.preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        self.autoPlayTrailers = false
        self.compactMode = false
        self.heroCarouselSource = .trendingMovies
    }
}

// MARK: - Browse Row Configuration
struct BrowseRowConfig: Identifiable, Codable {
    let id: String
    let title: String
    let endpoint: BrowseEndpoint
    var isEnabled: Bool
    var sortOrder: Int
    
    enum BrowseEndpoint: String, Codable {
        case trendingMovies = "trending_movies"
        case trendingTV = "trending_tv"
        case popularMovies = "popular_movies"
        case popularTV = "popular_tv"
        case topRatedMovies = "top_rated_movies"
        case topRatedTV = "top_rated_tv"
        case nowPlayingMovies = "now_playing_movies"
        case airingTodayTV = "airing_today_tv"
        case upcomingMovies = "upcoming_movies"
        case onTheAirTV = "on_the_air_tv"
    }
    
    static var defaultRows: [BrowseRowConfig] {
        [
            BrowseRowConfig(id: "1", title: "Trending Movies", endpoint: .trendingMovies, isEnabled: true, sortOrder: 0),
            BrowseRowConfig(id: "2", title: "Trending TV Shows", endpoint: .trendingTV, isEnabled: true, sortOrder: 1),
            BrowseRowConfig(id: "3", title: "Popular Movies", endpoint: .popularMovies, isEnabled: true, sortOrder: 2),
            BrowseRowConfig(id: "4", title: "Popular TV Shows", endpoint: .popularTV, isEnabled: true, sortOrder: 3),
            BrowseRowConfig(id: "5", title: "Now Playing", endpoint: .nowPlayingMovies, isEnabled: true, sortOrder: 4),
            BrowseRowConfig(id: "6", title: "Top Rated Movies", endpoint: .topRatedMovies, isEnabled: true, sortOrder: 5),
            BrowseRowConfig(id: "7", title: "Top Rated TV Shows", endpoint: .topRatedTV, isEnabled: true, sortOrder: 6),
            BrowseRowConfig(id: "8", title: "Upcoming Movies", endpoint: .upcomingMovies, isEnabled: true, sortOrder: 7),
        ]
    }
}

// MARK: - Search History
struct SearchHistoryItem: Identifiable, Codable {
    let id: String
    let query: String
    let timestamp: Date
    
    init(query: String) {
        self.id = UUID().uuidString
        self.query = query
        self.timestamp = Date()
    }
}
