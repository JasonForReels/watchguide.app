//
//  WatchHourModels.swift
//  WatchGuide-MovieandTVtracker
//
//  WatchHour — WatchGuide's built-in watch-session tracking hub.
//  These models describe an active watch session, a completed history
//  entry, and the aggregate viewing statistics derived from history.
//

import Foundation

// MARK: - Watch Session Status

enum WatchSessionStatus: String, Codable {
    case active
    case finished
    case onHold
}

// MARK: - Watch Session

/// An in-flight (or on-hold) WatchHour tracking session. Created when the user
/// taps **Watch** / **Continue Watching** on a title, before opening the
/// streaming service. Synced across devices via the cloud snapshot so the user
/// can see what they're currently watching from anywhere.
struct WatchSession: Identifiable, Codable, Hashable {
    let id: String
    let mediaId: Int
    let mediaType: MediaType
    let title: String
    let posterPath: String?

    // TV episode context (nil for movies).
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeTitle: String?

    let startTime: Date
    let estimatedRuntimeMinutes: Int
    let deviceName: String
    let providerName: String?
    var status: WatchSessionStatus
    var deepLinkURL: String?

    var isMovie: Bool { mediaType == .movie }

    /// When the estimated runtime is expected to elapse.
    var expectedEndTime: Date {
        startTime.addingTimeInterval(TimeInterval(estimatedRuntimeMinutes * 60))
    }

    var episodeCode: String? {
        guard let season = seasonNumber, let episode = episodeNumber else { return nil }
        return "S\(season) E\(episode)"
    }

    /// Identifier matching the corresponding `ContinueWatchingItem` (`"type-id"`).
    var continueWatchingItemId: String { "\(mediaType.rawValue)-\(mediaId)" }
}

// MARK: - Watch History Entry

/// A completed viewing record written when a session is finished. Powers the
/// viewing history, statistics, streaks, watch time, and (optional) ratings.
struct WatchHistoryEntry: Identifiable, Codable, Hashable {
    let id: String
    let mediaId: Int
    let mediaType: MediaType
    let title: String
    let posterPath: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeTitle: String?
    let watchedAt: Date
    let minutesWatched: Int
    var rating: Int?          // 1...5 stars, optional
    let deviceName: String

    var episodeCode: String? {
        guard let season = seasonNumber, let episode = episodeNumber else { return nil }
        return "S\(season) E\(episode)"
    }
}

// MARK: - Watch Statistics

/// Aggregate viewing statistics computed from the watch history.
struct WatchStats: Equatable {
    var totalMinutes: Int
    var totalSessions: Int
    var moviesWatched: Int
    var episodesWatched: Int
    var currentStreakDays: Int
    var longestStreakDays: Int
    var lastWatchedDate: Date?

    static let empty = WatchStats(
        totalMinutes: 0,
        totalSessions: 0,
        moviesWatched: 0,
        episodesWatched: 0,
        currentStreakDays: 0,
        longestStreakDays: 0,
        lastWatchedDate: nil
    )

    /// Human-readable total watch time, e.g. "12h 30m" or "45m".
    var totalTimeFormatted: String {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return "\(hours)h \(minutes)m"
    }

    static func compute(from history: [WatchHistoryEntry], calendar: Calendar = .current) -> WatchStats {
        guard !history.isEmpty else { return .empty }

        let totalMinutes = history.reduce(0) { $0 + $1.minutesWatched }
        let movies = history.filter { $0.mediaType == MediaType.movie }.count
        let episodes = history.filter { $0.mediaType == MediaType.tv }.count
        let last = history.map { $0.watchedAt }.max()

        let days = Set(history.map { calendar.startOfDay(for: $0.watchedAt) }).sorted()
        let (current, longest) = streaks(days: days, calendar: calendar)

        return WatchStats(
            totalMinutes: totalMinutes,
            totalSessions: history.count,
            moviesWatched: movies,
            episodesWatched: episodes,
            currentStreakDays: current,
            longestStreakDays: longest,
            lastWatchedDate: last
        )
    }

    /// Computes the current and longest consecutive-day watch streaks.
    private static func streaks(days: [Date], calendar: Calendar) -> (current: Int, longest: Int) {
        guard !days.isEmpty else { return (0, 0) }

        // Longest run of consecutive days.
        var longest = 1
        var run = 1
        if days.count > 1 {
            for i in 1..<days.count {
                if let nextDay = calendar.date(byAdding: .day, value: 1, to: days[i - 1]),
                   calendar.isDate(nextDay, inSameDayAs: days[i]) {
                    run += 1
                } else {
                    run = 1
                }
                longest = max(longest, run)
            }
        }

        // Current streak, counting back from today (allowing "yesterday" grace).
        let daySet = Set(days)
        let today = calendar.startOfDay(for: Date())
        var cursor = today
        if !daySet.contains(today) {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), daySet.contains(yesterday) {
                cursor = yesterday
            } else {
                return (0, longest)
            }
        }

        var current = 0
        while daySet.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return (current, longest)
    }
}
