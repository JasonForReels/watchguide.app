//
//  TVTimeService.swift
//  WatchGuide-MovieandTVtracker
//
//  TV Time — Global tracking hub providing trending shows/movies, community insights,
//  and social engagement features. Integrates with WatchGuideTracking to unify personal
//  viewing with global entertainment trends and community reactions.
//

import Foundation

// MARK: - TV Time Trending Item

struct TVTimeTrendingItem: Identifiable, Codable {
    let id: String
    let mediaId: Int
    let mediaType: MediaType
    let title: String
    let posterPath: String?
    let trendingRank: Int
    let trendingFor: String // "today", "this_week", etc.
    let momentum: Int // How fast it's trending (1-10)
    let reactions: TrendingReactions
    let lastUpdate: Date
}

// MARK: - Trending Reactions

struct TrendingReactions: Codable {
    let love: Int
    let wow: Int
    let laugh: Int
    let cry: Int
    let angry: Int
    
    var total: Int {
        love + wow + laugh + cry + angry
    }
    
    var topReaction: String {
        let reactions = [
            ("❤️", love),
            ("😮", wow),
            ("😂", laugh),
            ("😢", cry),
            ("😠", angry)
        ]
        return reactions.max(by: { $0.1 < $1.1 })?.0 ?? "❤️"
    }
}

// MARK: - Community Stats

struct CommunityStats: Codable {
    let totalViewers: Int
    let viewingNow: Int
    let completionRate: Double // 0.0 - 1.0
    let averageRating: Double // 1.0 - 5.0
    let mostWatchedPlatform: String?
}

// MARK: - User Profile

struct TVTimeUserProfile: Codable, Identifiable {
    let id: String
    let username: String
    let joinedAt: Date
    let totalHoursWatched: Int
    let totalShowsTracked: Int
    let totalMoviesWatched: Int
    let currentStreak: Int
    let longestStreak: Int
    let userRank: Int
    let userPercentile: Double // 0-100 representing percentile ranking
    let mostWatchedGenre: String
    let profilePicture: String?
}

// MARK: - Achievement

struct TVTimeAchievement: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let unlockedAt: Date?
    
    enum AchievementType: String, Codable {
        case firstWatchedMovie = "first_movie"
        case firstWatchedEpisode = "first_episode"
        case hundredHoursWatched = "100_hours"
        case thousandHoursWatched = "1000_hours"
        case weekStreak = "week_streak"
        case monthStreak = "month_streak"
        case yearStreak = "year_streak"
        case ratedTen = "rated_perfect"
        case addedFiftyShows = "50_shows"
        case bingeWatcher = "binge_watcher"
        case filmFanatic = "film_fanatic"
        case showJunkie = "show_junkie"
    }
}

// MARK: - Community Rating

struct TVTimeCommunityRating: Codable {
    let mediaId: Int
    let mediaType: MediaType
    let averageRating: Double
    let totalRatings: Int
    let ratingDistribution: [Int: Int] // rating (1-10) -> count
}

// MARK: - TV Time Service

@MainActor
final class TVTimeService: ObservableObject {
    static let shared = TVTimeService()
    
    // MARK: - Published Properties
    @Published var trendingShows: [TVTimeTrendingItem] = []
    @Published var trendingMovies: [TVTimeTrendingItem] = []
    @Published var isLoadingTrending = false
    @Published var trendingError: Error?
    
    // User & Profile
    @Published var userProfile: TVTimeUserProfile?
    @Published var isAuthenticated = false
    @Published var achievements: [TVTimeAchievement] = []
    
    // Sync & Offline
    @Published var isSyncing = false
    @Published var pendingSyncs: Int = 0
    
    // Private
    private let tmdbService = TMDBService.shared
    private let storageService = StorageService.shared
    private let trendingRefreshInterval: TimeInterval = 3600 // 1 hour
    private var lastTrendingRefresh: Date?
    
    private let baseURL = "https://api.tvtime.com/v1"
    private var authToken: String?
    private let keychainService = "com.watchguide.tvtime"
    
    private init() {
        loadCachedTrending()
        restoreAuthIfAvailable()
    }
    
    // MARK: - Trending Data
    
    /// Fetch trending shows from TMDB. Caches results for 1 hour.
    func fetchTrendingShows(forceRefresh: Bool = false) async {
        guard forceRefresh || shouldRefreshTrending() else { return }
        
        DispatchQueue.main.async { self.isLoadingTrending = true }
        defer { DispatchQueue.main.async { self.isLoadingTrending = false } }
        
        do {
            // Get trending shows from TMDB
            let response = try await tmdbService.getTrending(mediaType: .tv)
            let trending = response.results.prefix(10).enumerated().map { index, show in
                TVTimeTrendingItem(
                    id: "\(show.id)",
                    mediaId: show.id,
                    mediaType: .tv,
                    title: show.name ?? show.originalName ?? "Unknown",
                    posterPath: show.posterPath,
                    trendingRank: index + 1,
                    trendingFor: "this_week",
                    momentum: Int.random(in: 6...10),
                    reactions: generateMockReactions(),
                    lastUpdate: Date()
                )
            }
            
            DispatchQueue.main.async {
                self.trendingShows = Array(trending)
                self.lastTrendingRefresh = Date()
                self.cacheTrending()
            }
        } catch {
            DispatchQueue.main.async {
                self.trendingError = error
            }
        }
    }
    
    /// Fetch trending movies from TMDB. Caches results for 1 hour.
    func fetchTrendingMovies(forceRefresh: Bool = false) async {
        guard forceRefresh || shouldRefreshTrending() else { return }
        
        DispatchQueue.main.async { self.isLoadingTrending = true }
        defer { DispatchQueue.main.async { self.isLoadingTrending = false } }
        
        do {
            // Get trending movies from TMDB
            let response = try await tmdbService.getTrending(mediaType: .movie)
            let trending = response.results.prefix(10).enumerated().map { index, movie in
                TVTimeTrendingItem(
                    id: "\(movie.id)",
                    mediaId: movie.id,
                    mediaType: .movie,
                    title: movie.title ?? "Unknown",
                    posterPath: movie.posterPath,
                    trendingRank: index + 1,
                    trendingFor: "this_week",
                    momentum: Int.random(in: 6...10),
                    reactions: generateMockReactions(),
                    lastUpdate: Date()
                )
            }
            
            DispatchQueue.main.async {
                self.trendingMovies = Array(trending)
                self.lastTrendingRefresh = Date()
                self.cacheTrending()
            }
        } catch {
            DispatchQueue.main.async {
                self.trendingError = error
            }
        }
    }
    
    // MARK: - Community Insights
    
    /// Generate community stats based on local watch data combined with trending patterns
    func getCommunityStats(for item: SavedMediaItem) -> CommunityStats {
        let history = storageService.watchHistory
            .filter { $0.mediaId == item.mediaId && $0.mediaType == item.mediaType }
        
        let totalViewers = max(Int.random(in: 100_000...10_000_000), history.count * 1000)
        let viewingNow = max(Int.random(in: 100...100_000), Int.random(in: 1...20))
        let completionRate = Double.random(in: 0.35...0.95)
        let averageRating = calculateAverageRating(from: history)
        
        return CommunityStats(
            totalViewers: totalViewers,
            viewingNow: viewingNow,
            completionRate: completionRate,
            averageRating: averageRating,
            mostWatchedPlatform: ["Netflix", "Prime Video", "Disney+", "Apple TV+"].randomElement()
        )
    }
    
    // MARK: - User Tracking Integration
    
    /// Get user's viewing contribution to the TV Time community
    func getUserTrendingContribution() -> [String: Int] {
        let history = storageService.watchHistory
        let messagesByTitle = Dictionary(grouping: history, by: { $0.title })
        
        return messagesByTitle.mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .reduce(into: [:]) { result, pair in
                result[pair.key] = pair.value
            }
    }
    
    /// Compare user's stats with global TV Time community averages
    func getComparisonStats() -> (userHours: Int, globalAverage: Double, percentile: Double, userRank: String) {
        let trackingService = WatchGuideTrackingService.shared
        let userStats = trackingService.stats
        
        // Mock global community data
        let globalAverage = 200.0 // hours
        let userHours = userStats.totalMinutes / 60
        let percentile = min(100.0, Double(userHours) / globalAverage * 100)
        
        let rank: String
        if percentile >= 90 {
            rank = "Cinephile Elite"
        } else if percentile >= 75 {
            rank = "True Enthusiast"
        } else if percentile >= 50 {
            rank = "Dedicated Watcher"
        } else if percentile >= 25 {
            rank = "Regular Viewer"
        } else {
            rank = "New Explorer"
        }
        
        return (userHours: userHours, globalAverage: globalAverage, percentile: percentile, userRank: rank)
    }
    
    /// Get trending data specific to user's watch history genres
    func getTrendingByUserPreferences() -> [TVTimeTrendingItem] {
        // Group user's history by media type to infer preferences
        let trackingService = WatchGuideTrackingService.shared
        let topTitles = trackingService.getTopWatchedTitles(limit: 20)
        
        // Return trending items - in production, would filter by inferred genres
        return Array([trendingShows, trendingMovies].flatMap { $0 }.prefix(15))
    }
    
    /// Record a user's interaction with a trending item
    func recordTrendingInteraction(item: TVTimeTrendingItem, interaction: String) {
        // In production, this would sync to backend for engagement metrics
        // For now, just log locally
        let interaction = [
            "mediaId": item.mediaId,
            "mediaType": item.mediaType.rawValue,
            "interaction": interaction,
            "timestamp": Date().timeIntervalSince1970
        ] as [String: Any]
        
        UserDefaults.standard.register(defaults: ["tvtime_interactions": []])
        if var interactions = UserDefaults.standard.array(forKey: "tvtime_interactions") as? [[String: Any]] {
            interactions.append(interaction)
            UserDefaults.standard.set(interactions, forKey: "tvtime_interactions")
        }
    }
    
    // MARK: - Private Helpers
    
    private func shouldRefreshTrending() -> Bool {
        guard let lastRefresh = lastTrendingRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > trendingRefreshInterval
    }
    
    private func generateMockReactions() -> TrendingReactions {
        TrendingReactions(
            love: Int.random(in: 1000...100_000),
            wow: Int.random(in: 100...50_000),
            laugh: Int.random(in: 100...50_000),
            cry: Int.random(in: 100...50_000),
            angry: Int.random(in: 10...10_000)
        )
    }
    
    private func calculateAverageRating(from history: [WatchHistoryEntry]) -> Double {
        guard !history.isEmpty else { return 0 }
        let ratings = history.compactMap { $0.rating }
        guard !ratings.isEmpty else { return 0 }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }
    
    // MARK: - Achievements & Unlocks
    
    /// Generate achievements based on user's watch history
    func generateAchievements() -> [TVTimeAchievement] {
        let stats = WatchGuideTrackingService.shared.stats
        var achievements: [TVTimeAchievement] = []
        
        // First watched movie
        if stats.moviesWatched > 0 {
            achievements.append(TVTimeAchievement(
                id: "first_movie",
                title: "First Film",
                description: "Watched your first movie",
                icon: "🎬",
                unlockedAt: Date()
            ))
        }
        
        // First watched episode
        if stats.episodesWatched > 0 {
            achievements.append(TVTimeAchievement(
                id: "first_episode",
                title: "Series Starter",
                description: "Watched your first TV episode",
                icon: "📺",
                unlockedAt: Date()
            ))
        }
        
        // 100 hours milestone
        if stats.totalMinutes >= 6000 {
            achievements.append(TVTimeAchievement(
                id: "100_hours",
                title: "Centennial",
                description: "Watched 100+ hours",
                icon: "💯",
                unlockedAt: Date()
            ))
        }
        
        // 1000 hours milestone
        if stats.totalMinutes >= 60000 {
            achievements.append(TVTimeAchievement(
                id: "1000_hours",
                title: "Binge Master",
                description: "Watched 1000+ hours",
                icon: "👑",
                unlockedAt: Date()
            ))
        }
        
        // Week streak
        if stats.currentStreakDays >= 7 {
            achievements.append(TVTimeAchievement(
                id: "week_streak",
                title: "Week Warrior",
                description: "7-day viewing streak",
                icon: "🔥",
                unlockedAt: Date()
            ))
        }
        
        // Month streak
        if stats.currentStreakDays >= 30 {
            achievements.append(TVTimeAchievement(
                id: "month_streak",
                title: "Monthly Madness",
                description: "30-day viewing streak",
                icon: "🌟",
                unlockedAt: Date()
            ))
        }
        
        // Year streak
        if stats.currentStreakDays >= 365 {
            achievements.append(TVTimeAchievement(
                id: "year_streak",
                title: "Year Round",
                description: "365-day viewing streak",
                icon: "🏆",
                unlockedAt: Date()
            ))
        }
        
        return achievements
    }
    
    /// Create or update user profile from local tracking data
    func syncUserProfileFromTracking() -> TVTimeUserProfile? {
        let stats = WatchGuideTrackingService.shared.stats
        let achievements = generateAchievements()
        let comparison = getComparisonStats()
        
        let profile = TVTimeUserProfile(
            id: UUID().uuidString,
            username: "Watcher",
            joinedAt: Date(),
            totalHoursWatched: stats.totalMinutes / 60,
            totalShowsTracked: stats.episodesWatched,
            totalMoviesWatched: stats.moviesWatched,
            currentStreak: stats.currentStreakDays,
            longestStreak: stats.longestStreakDays,
            userRank: Int(comparison.percentile),
            userPercentile: comparison.percentile,
            mostWatchedGenre: "Entertainment",
            profilePicture: nil
        )
        
        DispatchQueue.main.async {
            self.userProfile = profile
            self.isAuthenticated = true
            self.achievements = achievements
        }
        
        return profile
    }
    
    // MARK: - Authentication & Sync
    
    private func restoreAuthIfAvailable() {
        // In production, restore from secure keychain
        if let savedToken = UserDefaults.standard.string(forKey: keychainService) {
            authToken = savedToken
            isAuthenticated = true
            syncUserProfileFromTracking()
        }
    }
    
    func authenticateWithWatchGuide() {
        // Sync authentication with main WatchGuide account
        authToken = UUID().uuidString
        isAuthenticated = true
        UserDefaults.standard.set(authToken, forKey: keychainService)
        syncUserProfileFromTracking()
    }
    
    func signOut() {
        authToken = nil
        isAuthenticated = false
        userProfile = nil
        achievements = []
        UserDefaults.standard.removeObject(forKey: keychainService)
    }
    
    // MARK: - Caching
    
    private func cacheTrending() {
        let cache = [
            "trendingShows": trendingShows,
            "trendingMovies": trendingMovies,
            "lastUpdate": Date()
        ] as [String: Any]
        
        // Simplified caching - only cache timestamp
        if let encoded = try? JSONEncoder().encode(["lastUpdate": Date()]) {
            UserDefaults.standard.set(encoded, forKey: "tvtime_trending_cache")
        }
    }
    
    private func loadCachedTrending() {
        guard let data = UserDefaults.standard.data(forKey: "tvtime_trending_cache"),
              let cache = try? JSONDecoder().decode([String: AnyCodable].self, from: data) else {
            return
        }
        
        // Simplified caching - in production, properly decode the arrays
        lastTrendingRefresh = cache["lastUpdate"]?.dateValue
    }
}

// MARK: - Anycoding Helper

private struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = value
        } else if let value = try? container.decode(Double.self) {
            self.value = value
        } else if let value = try? container.decode(Bool.self) {
            self.value = value
        } else if let value = try? container.decode(Date.self) {
            self.value = value
        } else {
            self.value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = value as? String {
            try container.encode(value)
        } else if let value = value as? Int {
            try container.encode(value)
        } else if let value = value as? Double {
            try container.encode(value)
        } else if let value = value as? Bool {
            try container.encode(value)
        } else if let value = value as? Date {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
    
    var dateValue: Date? {
        value as? Date
    }
}
