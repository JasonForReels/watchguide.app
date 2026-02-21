//
//  MediaModels.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

// MARK: - Media Type
enum MediaType: String, Codable, CaseIterable, Identifiable {
    case movie
    case tv
    case person
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .movie: return "Movies"
        case .tv: return "TV Shows"
        case .person: return "People"
        }
    }
}

// MARK: - Base Media Item
struct MediaItem: Identifiable, Codable, Hashable {
    let id: Int
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?
    let genreIds: [Int]?
    let mediaType: String?
    let adult: Bool?
    let originalLanguage: String?
    
    var displayTitle: String {
        title ?? name ?? originalTitle ?? originalName ?? "Unknown"
    }
    
    var displayDate: String? {
        releaseDate ?? firstAirDate
    }
    
    var year: String? {
        guard let date = displayDate, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }
    
    var resolvedMediaType: MediaType {
        if let mt = mediaType {
            return MediaType(rawValue: mt) ?? .movie
        }
        return title != nil ? .movie : .tv
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case originalTitle = "original_title"
        case originalName = "original_name"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity
        case genreIds = "genre_ids"
        case mediaType = "media_type"
        case adult
        case originalLanguage = "original_language"
    }
}

// MARK: - Movie Details
struct MovieDetails: Identifiable, Codable {
    let id: Int
    let title: String
    let originalTitle: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let runtime: Int?
    let voteAverage: Double?
    let voteCount: Int?
    let budget: Int?
    let revenue: Int?
    let status: String?
    let tagline: String?
    let genres: [Genre]?
    let productionCompanies: [ProductionCompany]?
    let productionCountries: [ProductionCountry]?
    let spokenLanguages: [SpokenLanguage]?
    let imdbId: String?
    let homepage: String?
    let adult: Bool?
    let belongsToCollection: CollectionInfo?
    
    var year: String? {
        guard let date = releaseDate, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }
    
    var runtimeFormatted: String? {
        guard let runtime = runtime, runtime > 0 else { return nil }
        let hours = runtime / 60
        let minutes = runtime % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, budget, revenue, status, tagline, genres, homepage, adult
        case originalTitle = "original_title"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case productionCompanies = "production_companies"
        case productionCountries = "production_countries"
        case spokenLanguages = "spoken_languages"
        case imdbId = "imdb_id"
        case belongsToCollection = "belongs_to_collection"
    }
}

// MARK: - TV Show Details
struct TVShowDetails: Identifiable, Codable {
    let id: Int
    let name: String
    let originalName: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let lastAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let episodeRunTime: [Int]?
    let status: String?
    let tagline: String?
    let type: String?
    let genres: [Genre]?
    let networks: [Network]?
    let productionCompanies: [ProductionCompany]?
    let seasons: [Season]?
    let createdBy: [Creator]?
    let homepage: String?
    let inProduction: Bool?
    let languages: [String]?
    let originCountry: [String]?
    let externalIds: ExternalIds?
    
    var year: String? {
        guard let date = firstAirDate, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }
    
    var yearRange: String? {
        guard let startYear = year else { return nil }
        if let lastDate = lastAirDate, lastDate.count >= 4 {
            let endYear = String(lastDate.prefix(4))
            if status == "Ended" || status == "Canceled" {
                return startYear == endYear ? startYear : "\(startYear)-\(endYear)"
            }
        }
        return "\(startYear)-"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, overview, status, tagline, type, genres, networks, seasons, homepage, languages
        case originalName = "original_name"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case lastAirDate = "last_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case episodeRunTime = "episode_run_time"
        case productionCompanies = "production_companies"
        case createdBy = "created_by"
        case inProduction = "in_production"
        case originCountry = "origin_country"
        case externalIds = "external_ids"
    }
}


// MARK: - Season
struct Season: Identifiable, Codable {
    let id: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let airDate: String?
    let seasonNumber: Int
    let episodeCount: Int?
    let voteAverage: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case posterPath = "poster_path"
        case airDate = "air_date"
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case voteAverage = "vote_average"
    }
}

// MARK: - Season Details
struct SeasonDetails: Identifiable, Codable {
    let id: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let airDate: String?
    let seasonNumber: Int
    let episodes: [Episode]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, overview, episodes
        case posterPath = "poster_path"
        case airDate = "air_date"
        case seasonNumber = "season_number"
    }
}

// MARK: - Episode
struct Episode: Identifiable, Codable {
    let id: Int
    let name: String?
    let overview: String?
    let stillPath: String?
    let airDate: String?
    let episodeNumber: Int
    let seasonNumber: Int
    let runtime: Int?
    let voteAverage: Double?
    let voteCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case stillPath = "still_path"
        case airDate = "air_date"
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }
}

// MARK: - Supporting Types
struct Genre: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
}

struct ProductionCompany: Identifiable, Codable {
    let id: Int
    let name: String
    let logoPath: String?
    let originCountry: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
        case originCountry = "origin_country"
    }
}

struct ProductionCountry: Codable {
    let iso31661: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case iso31661 = "iso_3166_1"
        case name
    }
}

struct SpokenLanguage: Codable {
    let iso6391: String
    let name: String
    let englishName: String?
    
    enum CodingKeys: String, CodingKey {
        case iso6391 = "iso_639_1"
        case name
        case englishName = "english_name"
    }
}

struct Network: Identifiable, Codable {
    let id: Int
    let name: String
    let logoPath: String?
    let originCountry: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
        case originCountry = "origin_country"
    }
}

struct Creator: Identifiable, Codable {
    let id: Int
    let name: String
    let profilePath: String?
    let creditId: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case profilePath = "profile_path"
        case creditId = "credit_id"
    }
}

struct CollectionInfo: Identifiable, Codable {
    let id: Int
    let name: String
    let posterPath: String?
    let backdropPath: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
}

struct ExternalIds: Codable {
    let imdbId: String?
    let tvdbId: Int?
    let facebookId: String?
    let instagramId: String?
    let twitterId: String?
    
    enum CodingKeys: String, CodingKey {
        case imdbId = "imdb_id"
        case tvdbId = "tvdb_id"
        case facebookId = "facebook_id"
        case instagramId = "instagram_id"
        case twitterId = "twitter_id"
    }
}

// MARK: - Credits
struct Credits: Codable {
    let cast: [CastMember]?
    let crew: [CrewMember]?
}

struct CastMember: Identifiable, Codable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
    let order: Int?
    let knownForDepartment: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, character, order
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
    }
}

struct CrewMember: Identifiable, Codable {
    let id: Int
    let name: String
    let job: String?
    let department: String?
    let profilePath: String?
    
    var uniqueId: String { "\(id)-\(job ?? "")" }
    
    enum CodingKeys: String, CodingKey {
        case id, name, job, department
        case profilePath = "profile_path"
    }
}

// MARK: - Videos
struct VideosResponse: Codable {
    let results: [Video]
}

struct Video: Identifiable, Codable {
    let id: String
    let key: String
    let name: String
    let site: String
    let type: String
    let official: Bool?
    let publishedAt: String?
    
    var youtubeUrl: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }
    
    var thumbnailUrl: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(key)/hqdefault.jpg")
    }
    
    enum CodingKeys: String, CodingKey {
        case id, key, name, site, type, official
        case publishedAt = "published_at"
    }
}

// MARK: - Watch Providers
struct WatchProvidersResponse: Codable {
    let results: [String: WatchProviderRegion]?
}

struct WatchProviderRegion: Codable {
    let link: String?
    let flatrate: [WatchProvider]?
    let rent: [WatchProvider]?
    let buy: [WatchProvider]?
    let free: [WatchProvider]?
    let ads: [WatchProvider]?
}

struct WatchProvider: Identifiable, Codable {
    let providerId: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int?
    
    var id: Int { providerId }
    
    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
        case displayPriority = "display_priority"
    }
}

// MARK: - Media Images (Logos)
struct MediaImagesResponse: Codable {
    let logos: [MediaImage]
}

struct MediaImage: Codable {
    let filePath: String
    let iso639_1: String?
    let width: Int?
    let height: Int?
    let voteAverage: Double?
    let voteCount: Int?
    let aspectRatio: Double?
    
    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case iso639_1 = "iso_639_1"
        case width, height
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case aspectRatio = "aspect_ratio"
    }
}

// MARK: - Person
struct Person: Identifiable, Codable {
    let id: Int
    let name: String
    let profilePath: String?
    let knownForDepartment: String?
    let knownFor: [MediaItem]?
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let popularity: Double?
    let adult: Bool?
    let imdbId: String?
    let homepage: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, biography, birthday, deathday, popularity, adult, homepage
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
        case knownFor = "known_for"
        case placeOfBirth = "place_of_birth"
        case imdbId = "imdb_id"
    }
}

// MARK: - API Responses
struct TMDBResponse<T: Codable>: Codable {
    let page: Int?
    let results: [T]
    let totalPages: Int?
    let totalResults: Int?
    
    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

struct GenresResponse: Codable {
    let genres: [Genre]
}

// MARK: - Company
struct Company: Identifiable, Codable {
    let id: Int
    let name: String
    let logoPath: String?
    let description: String?
    let headquarters: String?
    let homepage: String?
    let originCountry: String?
    let parentCompany: ParentCompany?
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, headquarters, homepage
        case logoPath = "logo_path"
        case originCountry = "origin_country"
        case parentCompany = "parent_company"
    }
}

struct ParentCompany: Identifiable, Codable {
    let id: Int
    let name: String
    let logoPath: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
    }
}

// MARK: - OMDb Ratings
struct OMDbResponse: Codable {
    let title: String?
    let year: String?
    let rated: String?
    let released: String?
    let runtime: String?
    let genre: String?
    let director: String?
    let writer: String?
    let actors: String?
    let plot: String?
    let language: String?
    let country: String?
    let awards: String?
    let poster: String?
    let ratings: [OMDbRating]?
    let metascore: String?
    let imdbRating: String?
    let imdbVotes: String?
    let imdbID: String?
    let type: String?
    let dvd: String?
    let boxOffice: String?
    let production: String?
    let website: String?
    let response: String?
    
    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case year = "Year"
        case rated = "Rated"
        case released = "Released"
        case runtime = "Runtime"
        case genre = "Genre"
        case director = "Director"
        case writer = "Writer"
        case actors = "Actors"
        case plot = "Plot"
        case language = "Language"
        case country = "Country"
        case awards = "Awards"
        case poster = "Poster"
        case ratings = "Ratings"
        case metascore = "Metascore"
        case imdbRating
        case imdbVotes
        case imdbID
        case type = "Type"
        case dvd = "DVD"
        case boxOffice = "BoxOffice"
        case production = "Production"
        case website = "Website"
        case response = "Response"
    }
}

struct OMDbRating: Codable {
    let source: String
    let value: String
    
    enum CodingKeys: String, CodingKey {
        case source = "Source"
        case value = "Value"
    }
}



// MARK: - Collection Details
struct CollectionDetails: Identifiable, Codable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let parts: [MediaItem]
    
    enum CodingKeys: String, CodingKey {
        case id, name, overview, parts
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
}

// MARK: - TV Show Airing Info (lightweight, for countdown)
struct TVShowAiringInfo: Codable {
    let id: Int
    let name: String?
    let status: String?
    let nextEpisodeToAir: NextEpisodeInfo?
    let inProduction: Bool?
    let originalLanguage: String?
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, status, overview
        case nextEpisodeToAir = "next_episode_to_air"
        case inProduction = "in_production"
        case originalLanguage = "original_language"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
}

struct NextEpisodeInfo: Codable {
    let id: Int
    let name: String?
    let airDate: String?
    let episodeNumber: Int?
    let seasonNumber: Int?
    let overview: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case airDate = "air_date"
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
    }
}

// MARK: - TMDB List Response
struct TMDBListResponse: Codable {
    let id: String?
    let name: String?
    let description: String?
    let posterPath: String?
    let backdropPath: String?
    let items: [MediaItem]
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, items
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
}
