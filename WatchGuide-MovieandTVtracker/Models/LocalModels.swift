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

// MARK: - Network Hub (Streaming Services)
struct NetworkHub: Identifiable, Codable {
    let id: String
    let name: String
    let logoURL: String?
    let networkIds: [Int]
    let providerIds: [Int]
    let regions: [String]
    var isEnabled: Bool
    var sortOrder: Int
    let createdAt: Date
    
    init(name: String, logoURL: String? = nil, networkIds: [Int] = [], providerIds: [Int] = [], regions: [String] = []) {
        self.id = UUID().uuidString
        self.name = name
        self.logoURL = logoURL
        self.networkIds = networkIds
        self.providerIds = providerIds
        self.regions = regions
        self.isEnabled = true
        self.sortOrder = 0
        self.createdAt = Date()
    }
    
    // Default streaming hubs
    static var defaultHubs: [NetworkHub] {
        [
            NetworkHub(
                name: "Disney+",
                logoURL: "https://lumiere-a.akamaihd.net/v1/images/a8e5567d1658de062d95d079ebf536b0_4096x2309_6dedcc02.png",
                networkIds: [2739], // Disney+ network
                providerIds: [337], // Disney+ provider
                regions: ["US", "GB", "CA", "AU", "DE", "FR", "JP", "KR", "IN", "BR", "ZA", "NZ", "IT", "ES", "MX", "AR", "NL", "BE", "CH", "AT", "SE", "NO", "DK", "FI", "PT", "IE", "SG", "MY", "TH", "ID", "PH", "TW", "HK"]
            ),
            NetworkHub(
                name: "Netflix",
                logoURL: "https://images.ctfassets.net/y2ske730sjqp/821Wg4N9hJD8vs5FBcCGg/9eaf66123397cc61be14e40174123c40/Vector__3_.svg?w=460",
                networkIds: [213], // Netflix network
                providerIds: [8], // Netflix provider
                regions: ["US", "GB", "CA", "AU", "DE", "FR", "JP", "KR", "IN", "BR", "ZA", "NZ", "IT", "ES", "MX", "AR", "NL", "BE", "CH", "AT", "SE", "NO", "DK", "FI", "PT", "IE", "SG", "MY", "TH", "ID", "PH", "TW", "HK", "PL", "CZ", "RO", "TR", "EG", "SA", "AE", "IL", "CO", "CL", "PE", "VE"]
            ),
            NetworkHub(
                name: "Showmax",
                logoURL: "https://cdn.cookielaw.org/logos/17e5cb00-ad90-47f5-a58d-77597d9d2c16/0195cf57-93d1-7335-bc7f-50dce1b350c2/469bb55b-c92e-4a70-8669-d0f24734a079/Showmax_logo_full.png",
                networkIds: [],
                providerIds: [55], // Showmax provider
                regions: ["ZA", "NG", "KE", "GH", "UG", "TZ", "ZW", "ZM", "BW", "NA", "MZ", "MW", "RW", "MU", "ET", "CI", "SN", "CM", "CD", "AO"]
            ),
            NetworkHub(
                name: "Max",
                logoURL: "https://upload.wikimedia.org/wikipedia/commons/b/b3/HBO_Max_%282025%29.svg",
                networkIds: [49, 3186], // HBO, Max networks
                providerIds: [384, 1899], // HBO Max / Max provider IDs
                regions: ["US", "BR", "MX", "AR", "CL", "CO", "PE", "CR", "PA", "EC", "DO", "GT", "HN", "SV", "NI", "BO", "PY", "UY", "PT", "ES", "SE", "NO", "DK", "FI", "PL", "CZ", "RO", "HU", "BG", "HR", "SK", "SI", "BA", "RS", "NL", "BE"]
            ),
            NetworkHub(
                name: "Peacock",
                logoURL: "https://upload.wikimedia.org/wikipedia/commons/d/d3/NBCUniversal_Peacock_Logo.svg",
                networkIds: [6, 453], // NBC, Peacock networks
                providerIds: [386, 387], // Peacock provider IDs
                regions: ["US", "GB", "IE", "IT", "DE", "AT", "CH"]
            ),
            NetworkHub(
                name: "Paramount+",
                logoURL: "https://upload.wikimedia.org/wikipedia/commons/e/ea/Paramount%2B_logo.png",
                networkIds: [4330, 16, 2552], // Paramount+, CBS networks
                providerIds: [531, 582], // Paramount+ provider IDs
                regions: ["US", "CA", "GB", "AU", "DE", "AT", "CH", "IT", "FR", "ES", "MX", "BR", "AR", "CL", "CO", "PE", "KR", "SE", "NO", "DK", "FI", "NL", "BE", "IE"]
            ),
            NetworkHub(
                name: "Disney Channel",
                logoURL: "https://i.ibb.co/XZWP8tTs/disney-channel-seeklogo.png",
                networkIds: [],
                providerIds: [],
                regions: []
            ),
        ]
    }
}

// MARK: - Company Hub (Legacy - keeping for compatibility)
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

// MARK: - Imported List Source
enum ImportedListSource: String, Codable {
    case publicMetaDB = "publicmetadb"
    case mdblist = "mdblist"
    
    var displayName: String {
        switch self {
        case .publicMetaDB: return "PublicMetaDB"
        case .mdblist: return "MDBList"
        }
    }
    
    var iconName: String {
        switch self {
        case .publicMetaDB: return "list.bullet.clipboard"
        case .mdblist: return "list.star"
        }
    }
    
    var iconColor: String {
        switch self {
        case .publicMetaDB: return "orange"
        case .mdblist: return "purple"
        }
    }
}

// MARK: - Imported List (PublicMetaDB & MDBList)
struct ImportedListItem: Identifiable, Codable {
    let id: String
    var name: String
    var listId: String
    var items: [SavedMediaItem]
    var lastSynced: Date?
    let createdAt: Date
    var showOnHome: Bool
    var customName: String?
    var source: ImportedListSource
    
    init(name: String, listId: String, showOnHome: Bool = false, source: ImportedListSource = .publicMetaDB) {
        self.id = UUID().uuidString
        self.name = name
        self.listId = listId
        self.items = []
        self.lastSynced = nil
        self.createdAt = Date()
        self.showOnHome = showOnHome
        self.customName = nil
        self.source = source
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
    case mdblistTrending = "mdblist_trending"
    
    var displayName: String {
        switch self {
        case .trendingMovies: return "Trending Movies"
        case .trendingTV: return "Trending TV Shows"
        case .popularMovies: return "Popular Movies"
        case .popularTV: return "Popular TV Shows"
        case .nowPlayingMovies: return "Now Playing"
        case .topRatedMovies: return "Top Rated Movies"
        case .upcomingMovies: return "Upcoming Movies"
        case .mdblistTrending: return "Trending (MDBList)"
        }
    }
}

// MARK: - User Settings
struct UserSettings: Codable, Equatable {
    var region: String
    var includeAdult: Bool
    var preferredLanguage: String
    var autoPlayTrailers: Bool
    var autoPlayTrailersMuted: Bool
    var compactMode: Bool
    var ambientModeEnabled: Bool
    var heroCarouselSource: HeroCarouselSource
    
    init() {
        self.region = Locale.current.region?.identifier ?? "US"
        self.includeAdult = false
        self.preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        self.autoPlayTrailers = false
        self.autoPlayTrailersMuted = true
        self.compactMode = false
        self.ambientModeEnabled = false
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
        case trendingPeople = "trending_people"
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
            BrowseRowConfig(id: "3", title: "Trending Actors", endpoint: .trendingPeople, isEnabled: true, sortOrder: 2),
            BrowseRowConfig(id: "4", title: "Popular Movies", endpoint: .popularMovies, isEnabled: true, sortOrder: 3),
            BrowseRowConfig(id: "5", title: "Popular TV Shows", endpoint: .popularTV, isEnabled: true, sortOrder: 4),
            BrowseRowConfig(id: "6", title: "Now Playing", endpoint: .nowPlayingMovies, isEnabled: true, sortOrder: 5),
            BrowseRowConfig(id: "7", title: "Top Rated Movies", endpoint: .topRatedMovies, isEnabled: true, sortOrder: 6),
            BrowseRowConfig(id: "8", title: "Top Rated TV Shows", endpoint: .topRatedTV, isEnabled: true, sortOrder: 7),
            BrowseRowConfig(id: "9", title: "Upcoming Movies", endpoint: .upcomingMovies, isEnabled: true, sortOrder: 8),
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
