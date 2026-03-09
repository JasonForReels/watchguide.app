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
    enum ButtonShape: String, Codable, CaseIterable {
        case roundedRectangle = "rounded_rectangle"
        case capsule = "capsule"
        case circle = "circle"

        var displayName: String {
            switch self {
            case .roundedRectangle: return "Rounded"
            case .capsule: return "Capsule"
            case .circle: return "Circle"
            }
        }
    }

    enum BackgroundStyle: String, Codable, CaseIterable {
        case solid = "solid"
        case glass = "glass"
        case outline = "outline"
        case gradient = "gradient"
        case dark = "dark"

        var displayName: String {
            switch self {
            case .solid: return "Solid"
            case .glass: return "Glass"
            case .outline: return "Outline"
            case .gradient: return "Gradient"
            case .dark: return "Dark"
            }
        }
    }

    let id: String
    let name: String
    let logoPath: String?
    let companyIds: [Int]
    let networkIds: [Int]
    var isEnabled: Bool
    var buttonShape: ButtonShape?
    var backgroundStyle: BackgroundStyle?
    let createdAt: Date
    
    init(
        name: String,
        logoPath: String? = nil,
        companyIds: [Int] = [],
        networkIds: [Int] = [],
        buttonShape: ButtonShape? = nil,
        backgroundStyle: BackgroundStyle? = nil
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.logoPath = logoPath
        self.companyIds = companyIds
        self.networkIds = networkIds
        self.isEnabled = true
        self.buttonShape = buttonShape
        self.backgroundStyle = backgroundStyle
        self.createdAt = Date()
    }

    init(
        id: String,
        name: String,
        logoPath: String?,
        companyIds: [Int],
        networkIds: [Int],
        isEnabled: Bool,
        buttonShape: ButtonShape?,
        backgroundStyle: BackgroundStyle?,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.logoPath = logoPath
        self.companyIds = companyIds
        self.networkIds = networkIds
        self.isEnabled = isEnabled
        self.buttonShape = buttonShape
        self.backgroundStyle = backgroundStyle
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case logoPath
        case companyIds
        case networkIds
        case isEnabled
        case buttonShape
        case backgroundStyle
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        logoPath = try container.decodeIfPresent(String.self, forKey: .logoPath)
        companyIds = try container.decodeIfPresent([Int].self, forKey: .companyIds) ?? []
        networkIds = try container.decodeIfPresent([Int].self, forKey: .networkIds) ?? []
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        buttonShape = try container.decodeIfPresent(ButtonShape.self, forKey: .buttonShape)
        backgroundStyle = try container.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
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
    case customLists = "custom_lists"
    case mdblistPair = "mdblist_pair"
    
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
        case .customLists: return "Custom Lists (Movies + TV)"
        case .mdblistPair: return "MDBList Pair (Movies + TV)"
        }
    }
}

// MARK: - User Settings
struct UserSettings: Codable, Equatable {
    var region: String
    var includeAdult: Bool
    var useAppleIntelligenceSearch: Bool
    var preferredLanguage: String
    var autoPlayTrailers: Bool
    var autoPlayTrailersMuted: Bool
    var compactMode: Bool
    var ambientModeEnabled: Bool
    var heroCarouselSource: HeroCarouselSource
    var heroCarouselCustomMovieListId: String?
    var heroCarouselCustomShowListId: String?
    var heroCarouselMDBListMovieId: String?
    var heroCarouselMDBListShowId: String?
    var isKidsProfile: Bool
    var parentPasscode: String?  // 4-digit passcode set by parent to lock age-restricted settings
    
    init() {
        self.region = Locale.current.region?.identifier ?? "US"
        self.includeAdult = false
        self.useAppleIntelligenceSearch = false
        self.preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        self.autoPlayTrailers = false
        self.autoPlayTrailersMuted = true
        self.compactMode = false
        self.ambientModeEnabled = false
        self.heroCarouselSource = .trendingMovies
        self.heroCarouselCustomMovieListId = nil
        self.heroCarouselCustomShowListId = nil
        self.heroCarouselMDBListMovieId = nil
        self.heroCarouselMDBListShowId = nil
        self.isKidsProfile = false
        self.parentPasscode = nil
    }

    enum CodingKeys: String, CodingKey {
        case region
        case includeAdult
        case useAppleIntelligenceSearch
        case preferredLanguage
        case autoPlayTrailers
        case autoPlayTrailersMuted
        case compactMode
        case ambientModeEnabled
        case heroCarouselSource
        case heroCarouselCustomMovieListId
        case heroCarouselCustomShowListId
        case heroCarouselMDBListMovieId
        case heroCarouselMDBListShowId
        case isKidsProfile
        case parentPasscode
    }

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        region = try container.decodeIfPresent(String.self, forKey: .region) ?? region
        includeAdult = try container.decodeIfPresent(Bool.self, forKey: .includeAdult) ?? includeAdult
        useAppleIntelligenceSearch = try container.decodeIfPresent(Bool.self, forKey: .useAppleIntelligenceSearch) ?? useAppleIntelligenceSearch
        preferredLanguage = try container.decodeIfPresent(String.self, forKey: .preferredLanguage) ?? preferredLanguage
        autoPlayTrailers = try container.decodeIfPresent(Bool.self, forKey: .autoPlayTrailers) ?? autoPlayTrailers
        autoPlayTrailersMuted = try container.decodeIfPresent(Bool.self, forKey: .autoPlayTrailersMuted) ?? autoPlayTrailersMuted
        compactMode = try container.decodeIfPresent(Bool.self, forKey: .compactMode) ?? compactMode
        ambientModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .ambientModeEnabled) ?? ambientModeEnabled
        if let sourceRaw = try container.decodeIfPresent(String.self, forKey: .heroCarouselSource),
           let source = HeroCarouselSource(rawValue: sourceRaw) {
            heroCarouselSource = source
        }
        heroCarouselCustomMovieListId = try container.decodeIfPresent(String.self, forKey: .heroCarouselCustomMovieListId)
        heroCarouselCustomShowListId = try container.decodeIfPresent(String.self, forKey: .heroCarouselCustomShowListId)
        heroCarouselMDBListMovieId = try container.decodeIfPresent(String.self, forKey: .heroCarouselMDBListMovieId)
        heroCarouselMDBListShowId = try container.decodeIfPresent(String.self, forKey: .heroCarouselMDBListShowId)
        isKidsProfile = try container.decodeIfPresent(Bool.self, forKey: .isKidsProfile) ?? isKidsProfile
        parentPasscode = try container.decodeIfPresent(String.self, forKey: .parentPasscode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(region, forKey: .region)
        try container.encode(includeAdult, forKey: .includeAdult)
        try container.encode(useAppleIntelligenceSearch, forKey: .useAppleIntelligenceSearch)
        try container.encode(preferredLanguage, forKey: .preferredLanguage)
        try container.encode(autoPlayTrailers, forKey: .autoPlayTrailers)
        try container.encode(autoPlayTrailersMuted, forKey: .autoPlayTrailersMuted)
        try container.encode(compactMode, forKey: .compactMode)
        try container.encode(ambientModeEnabled, forKey: .ambientModeEnabled)
        try container.encode(heroCarouselSource.rawValue, forKey: .heroCarouselSource)
        try container.encode(heroCarouselCustomMovieListId, forKey: .heroCarouselCustomMovieListId)
        try container.encode(heroCarouselCustomShowListId, forKey: .heroCarouselCustomShowListId)
        try container.encode(heroCarouselMDBListMovieId, forKey: .heroCarouselMDBListMovieId)
        try container.encode(heroCarouselMDBListShowId, forKey: .heroCarouselMDBListShowId)
        try container.encode(isKidsProfile, forKey: .isKidsProfile)
        try container.encode(parentPasscode, forKey: .parentPasscode)
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

// MARK: - Custom Hub Source
enum CustomHubSource: String, Codable {
    case json = "json"
    case mdblist = "mdblist"
    
    var displayName: String {
        switch self {
        case .json: return "JSON URL"
        case .mdblist: return "MDBList"
        }
    }
}

// MARK: - Custom JSON Hub
/// Represents a user-defined hub loaded from an external JSON URL or MDBList.
/// The JSON file is expected to contain an array of objects with TMDB IDs.
/// Supports multiple MDBList sources that are merged into a single hub.
struct CustomJSONHub: Identifiable, Codable {
    let id: String
    var name: String
    var jsonURL: String
    var iconURL: String?
    var imageURL: String?
    var brandColor: String?
    var items: [SavedMediaItem]
    var isEnabled: Bool
    var sortOrder: Int
    var lastSynced: Date?
    let createdAt: Date
    var source: CustomHubSource
    var mdblistId: String?
    /// Multiple MDBList list paths (e.g. ["garycrawfordgc/disney-shows", "garycrawfordgc/disney-movies"])
    var mdblistIds: [String]?
    var rowName: String?
    
    init(name: String, jsonURL: String, iconURL: String? = nil, brandColor: String? = nil, source: CustomHubSource = .json) {
        self.id = UUID().uuidString
        self.name = name
        self.jsonURL = jsonURL
        self.iconURL = iconURL
        self.imageURL = nil
        self.brandColor = brandColor
        self.items = []
        self.isEnabled = true
        self.sortOrder = 0
        self.lastSynced = nil
        self.createdAt = Date()
        self.source = source
        self.mdblistId = nil
        self.mdblistIds = nil
        self.rowName = nil
    }
    
    /// Full init used when restoring from cloud sync
    init(id: String, name: String, jsonURL: String, iconURL: String?, brandColor: String?, isEnabled: Bool, sortOrder: Int, lastSynced: Date?, createdAt: Date) {
        self.id = id
        self.name = name
        self.jsonURL = jsonURL
        self.iconURL = iconURL
        self.imageURL = nil
        self.brandColor = brandColor
        self.items = []
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.lastSynced = lastSynced
        self.createdAt = createdAt
        self.source = .json
        self.mdblistId = nil
        self.mdblistIds = nil
        self.rowName = nil
    }
    
    /// All resolved MDBList list paths for this hub (backward-compatible).
    /// Prefers `mdblistIds` if present; falls back to single `mdblistId`.
    var resolvedMDBListIds: [String] {
        if let ids = mdblistIds, !ids.isEmpty { return ids }
        if let single = mdblistId, !single.isEmpty { return [single] }
        // Try extracting from legacy mdblist:// URL
        if jsonURL.hasPrefix("mdblist://") {
            let path = String(jsonURL.dropFirst("mdblist://".count))
            if !path.isEmpty { return [path] }
        }
        return []
    }
    
    /// The label displayed on the Browse page hub button
    var displayRowName: String {
        rowName?.isEmpty == false ? rowName! : name
    }
}

/// A single entry from the external JSON file.
/// Supports flexible formats: { "tmdb_id": 123, "media_type": "movie", "title": "..." }
struct ExternalJSONEntry: Codable {
    let tmdbId: Int?
    let mediaType: String?
    let title: String?
    let imdbId: String?
    let year: Int?
    
    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case mediaType = "media_type"
        case title
        case imdbId = "imdb_id"
        case year
    }
}

// MARK: - Hidden Default Sections
/// Tracks which built-in browse page sections are hidden by the user.
struct HiddenDefaultSections: Codable, Equatable {
    var hideStudiosRow: Bool = false
    var hideNetworksRow: Bool = false
    var hideForYouRow: Bool = false
    var hideDiscoverSection: Bool = false
    
    static let `default` = HiddenDefaultSections()
}

// MARK: - Browse Section Order
/// Controls the order and visibility of top-level sections on the Browse page.
/// Each section has a type, an enabled flag, and a sort order.
struct BrowseSectionItem: Identifiable, Codable, Equatable {
    let id: String
    let sectionType: BrowseSectionType
    var isEnabled: Bool
    var sortOrder: Int
    
    enum BrowseSectionType: String, Codable, Equatable {
        case networks = "networks"
        case rows = "rows"        // The content rows (Trending, Popular, etc.)
        case studios = "studios"
        case customHubs = "custom_hubs"
        case forYou = "for_you"
        case discover = "discover"
    }
    
    var displayName: String {
        switch sectionType {
        case .networks: return "Networks (Streaming)"
        case .rows: return "Content Rows"
        case .studios: return "Studios"
        case .customHubs: return "Custom Hubs"
        case .forYou: return "For You (AI Picks)"
        case .discover: return "Discover Section"
        }
    }
    
    var iconName: String {
        switch sectionType {
        case .networks: return "tv.fill"
        case .rows: return "film.stack"
        case .studios: return "building.2.fill"
        case .customHubs: return "star.circle.fill"
        case .forYou: return "heart.text.square.fill"
        case .discover: return "safari.fill"
        }
    }
    
    static var defaultSections: [BrowseSectionItem] {
        [
            BrowseSectionItem(id: "sec_networks", sectionType: .networks, isEnabled: true, sortOrder: 0),
            BrowseSectionItem(id: "sec_rows", sectionType: .rows, isEnabled: true, sortOrder: 1),
            BrowseSectionItem(id: "sec_studios", sectionType: .studios, isEnabled: true, sortOrder: 2),
            BrowseSectionItem(id: "sec_custom_hubs", sectionType: .customHubs, isEnabled: true, sortOrder: 3),
            BrowseSectionItem(id: "sec_for_you", sectionType: .forYou, isEnabled: true, sortOrder: 4),
            BrowseSectionItem(id: "sec_discover", sectionType: .discover, isEnabled: true, sortOrder: 5),
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
