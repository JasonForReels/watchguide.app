//
//  ContinueWatchingService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
final class ContinueWatchingService: ObservableObject {
    static let shared = ContinueWatchingService()

    #if !os(tvOS)
    private let notificationCenter = UNUserNotificationCenter.current()
    #endif
    private static let reminderDelaySeconds: TimeInterval = 3 * 60 * 60 // 3 hours

    private init() {}

    // MARK: - Computed Lists

    var continueWatchingItems: [ContinueWatchingItem] {
        StorageService.shared.continueWatching.filter { $0.status == .inProgress }
    }

    var upNextItems: [ContinueWatchingItem] {
        StorageService.shared.continueWatching.filter {
            $0.status == .inProgress && $0.nextEpisode != nil && $0.show.mediaType == .tv
        }
    }

    // MARK: - Record Deep Link Taps

    func recordTVEpisodeDeepLinkTap(
        show: SavedMediaItem,
        episode: ContinueWatchingEpisode,
        providers: WatchProviderRegion?,
        providersLink: String?,
        deepLinkURL: URL?
    ) async {
        var item = ContinueWatchingItem(
            show: show,
            progress: -1,
            status: .inProgress,
            lastEpisode: episode,
            nextEpisode: nil,
            upcomingEpisode: nil,
            providers: providers,
            providersLink: providersLink,
            lastUpdated: Date(),
            source: .deepLink,
            deepLinkURL: deepLinkURL?.absoluteString,
            reminderScheduled: false
        )

        // Compute next episode from TMDB
        if let nextEp = await fetchNextEpisode(
            tvId: show.mediaId,
            afterSeason: episode.seasonNumber,
            afterEpisode: episode.episodeNumber
        ) {
            item = item.withNextEpisode(nextEp)
        }

        StorageService.shared.upsertContinueWatchingItem(item)
        await scheduleWatchedReminder(for: item)

        // Start a WatchHour tracking session for this title.
        await WatchHourService.shared.startSession(
            for: show,
            episode: episode,
            providerName: nil,
            deepLinkURL: deepLinkURL
        )
    }

    func recordMovieDeepLinkTap(
        movie: SavedMediaItem,
        providers: WatchProviderRegion?,
        providersLink: String?,
        deepLinkURL: URL?
    ) async {
        let item = ContinueWatchingItem(
            show: movie,
            progress: -1,
            status: .inProgress,
            lastEpisode: nil,
            nextEpisode: nil,
            upcomingEpisode: nil,
            providers: providers,
            providersLink: providersLink,
            lastUpdated: Date(),
            source: .deepLink,
            deepLinkURL: deepLinkURL?.absoluteString,
            reminderScheduled: false
        )

        StorageService.shared.upsertContinueWatchingItem(item)
        await scheduleWatchedReminder(for: item)

        // Start a WatchHour tracking session for this movie.
        await WatchHourService.shared.startSession(
            for: movie,
            episode: nil,
            providerName: nil,
            deepLinkURL: deepLinkURL
        )
    }

    // MARK: - Mark as Watched / Remove

    func markAsWatched(_ item: ContinueWatchingItem) async {
        #if !os(tvOS)
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: ["continue_watching_reminder_\(item.id)"]
        )
        #endif

        // For TV shows with a next episode, advance to the next episode
        // instead of marking the entire show as watched.
        if item.show.mediaType == .tv, let next = item.nextEpisode {
            let advancedItem = ContinueWatchingItem(
                show: item.show,
                progress: -1,
                status: .inProgress,
                lastEpisode: next,
                nextEpisode: nil,
                upcomingEpisode: nil,
                providers: item.providers,
                providersLink: item.providersLink,
                lastUpdated: Date(),
                source: item.source,
                deepLinkURL: item.deepLinkURL,
                reminderScheduled: false
            )

            // Fetch the episode after the new current one
            if let newNext = await fetchNextEpisode(
                tvId: item.show.mediaId,
                afterSeason: next.seasonNumber,
                afterEpisode: next.episodeNumber
            ) {
                StorageService.shared.upsertContinueWatchingItem(
                    advancedItem.withNextEpisode(newNext)
                )
            } else {
                // No more episodes — this is the last one
                StorageService.shared.upsertContinueWatchingItem(advancedItem)
            }
            return
        }

        // Movie or final episode — mark as fully watched
        var updated = item
        updated.status = .watched
        StorageService.shared.upsertContinueWatchingItem(updated)
    }

    func removeItem(_ item: ContinueWatchingItem) {
        StorageService.shared.removeContinueWatchingItem(id: item.id)

        #if !os(tvOS)
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: ["continue_watching_reminder_\(item.id)"]
        )
        #endif
    }

    // MARK: - Next Episode Lookup

    private func fetchNextEpisode(
        tvId: Int,
        afterSeason: Int,
        afterEpisode: Int
    ) async -> ContinueWatchingEpisode? {
        do {
            let seasonDetails = try await TMDBService.shared.getSeasonDetails(
                tvId: tvId, seasonNumber: afterSeason
            )
            let episodes = seasonDetails.episodes ?? []

            // Try next episode in same season
            if let nextEp = episodes.first(where: { $0.episodeNumber == afterEpisode + 1 }) {
                return ContinueWatchingEpisode(
                    seasonNumber: afterSeason,
                    episodeNumber: nextEp.episodeNumber,
                    title: nextEp.name,
                    overview: nextEp.overview,
                    airDate: nextEp.airDate
                )
            }

            // Try first episode of next season
            let nextSeasonDetails = try await TMDBService.shared.getSeasonDetails(
                tvId: tvId, seasonNumber: afterSeason + 1
            )
            if let firstEp = nextSeasonDetails.episodes?.first {
                return ContinueWatchingEpisode(
                    seasonNumber: afterSeason + 1,
                    episodeNumber: firstEp.episodeNumber,
                    title: firstEp.name,
                    overview: firstEp.overview,
                    airDate: firstEp.airDate
                )
            }
        } catch {
            // Season doesn't exist or network error
        }
        return nil
    }

    // MARK: - Notifications

    private func scheduleWatchedReminder(for item: ContinueWatchingItem) async {
        #if os(tvOS)
        return
        #else
        let granted = await requestNotificationPermission()
        guard granted else { return }

        let identifier = "continue_watching_reminder_\(item.id)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        if let episode = item.lastEpisode {
            content.title = "Did you finish watching?"
            content.body = "\(item.show.title) \(episode.code) — Mark as watched?"
        } else {
            content.title = "Did you finish watching?"
            content.body = "\(item.show.title) — Mark as watched?"
        }
        content.sound = .default
        content.categoryIdentifier = "CONTINUE_WATCHING_REMINDER"
        content.userInfo = ["continueWatchingItemId": item.id]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Self.reminderDelaySeconds,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        try? await notificationCenter.add(request)

        // Mark as scheduled
        var updated = item
        updated.reminderScheduled = true
        StorageService.shared.upsertContinueWatchingItem(updated)
        #endif
    }

    private func requestNotificationPermission() async -> Bool {
        #if os(tvOS)
        return false
        #else
        do {
            return try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
        #endif
    }
}
