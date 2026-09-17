//
//  WatchHourService.swift
//  WatchGuide-MovieandTVtracker
//
//  WatchHour — starts a watch session when the user taps Watch / Continue
//  Watching, prompts once the estimated runtime elapses (Finished / Still
//  Watching / On Hold), and records viewing history, statistics, streaks,
//  ratings, and watch time. Data is persisted via StorageService and synced
//  across devices through the cloud snapshot.
//

import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Current Device

enum WatchHourDevice {
    /// A friendly, non-identifying label for the current device.
    static var currentName: String {
        #if os(tvOS)
        return "Apple TV"
        #elseif os(macOS)
        return "Mac"
        #elseif canImport(UIKit)
        return UIDevice.current.model   // "iPhone" / "iPad"
        #else
        return "This Device"
        #endif
    }
}

// MARK: - WatchHour Service

@MainActor
final class WatchHourService: ObservableObject {
    static let shared = WatchHourService()

    #if !os(tvOS)
    private let notificationCenter = UNUserNotificationCenter.current()
    #endif

    // Notification category + actions. `nonisolated` so the notification
    // delegate (a nonisolated context) can reference them.
    nonisolated static let sessionCategoryID = "WATCHHOUR_SESSION"
    nonisolated static let finishedAction = "WATCHHOUR_FINISHED"
    nonisolated static let stillWatchingAction = "WATCHHOUR_STILL_WATCHING"
    nonisolated static let holdAction = "WATCHHOUR_HOLD"

    /// Follow-up prompt delay used after the user replies "Still Watching".
    private static let followUpMinutes = 20

    /// Fallback runtimes used when TMDB doesn't report one.
    private static let defaultMovieRuntime = 110
    private static let defaultEpisodeRuntime = 42

    private init() {}

    // MARK: - Derived State

    var activeSessions: [WatchSession] {
        StorageService.shared.watchSessions
            .filter { $0.status == .active }
            .sorted { $0.startTime > $1.startTime }
    }

    var onHoldSessions: [WatchSession] {
        StorageService.shared.watchSessions
            .filter { $0.status == .onHold }
            .sorted { $0.startTime > $1.startTime }
    }

    var history: [WatchHistoryEntry] {
        StorageService.shared.watchHistory
    }

    var stats: WatchStats {
        WatchStats.compute(from: StorageService.shared.watchHistory)
    }

    // MARK: - Start a Session

    /// Begins a WatchHour session for the given title, recording the runtime,
    /// device, and provider, then schedules the "still watching?" prompt.
    func startSession(
        for item: SavedMediaItem,
        episode: ContinueWatchingEpisode?,
        providerName: String?,
        deepLinkURL: URL?
    ) async {
        let runtime = await estimateRuntimeMinutes(for: item, episode: episode)

        // Replace any existing active session for the same title.
        for existing in StorageService.shared.watchSessions
        where existing.status == .active
            && existing.mediaId == item.mediaId
            && existing.mediaType == item.mediaType {
            StorageService.shared.removeWatchSession(id: existing.id)
        }

        let session = WatchSession(
            id: UUID().uuidString,
            mediaId: item.mediaId,
            mediaType: item.mediaType,
            title: item.title,
            posterPath: item.posterPath,
            seasonNumber: episode?.seasonNumber,
            episodeNumber: episode?.episodeNumber,
            episodeTitle: episode?.title,
            startTime: Date(),
            estimatedRuntimeMinutes: runtime,
            deviceName: WatchHourDevice.currentName,
            providerName: providerName,
            status: .active,
            deepLinkURL: deepLinkURL?.absoluteString
        )

        StorageService.shared.upsertWatchSession(session)
        await scheduleSessionPrompt(for: session)
    }

    // MARK: - Session Responses

    /// The user finished the title: record history, advance Continue Watching.
    func finish(_ session: WatchSession, rating: Int? = nil) async {
        cancelPrompt(forSessionId: session.id)
        recordHistory(from: session, minutes: session.estimatedRuntimeMinutes, rating: rating)
        StorageService.shared.removeWatchSession(id: session.id)

        if let cwItem = StorageService.shared.continueWatching
            .first(where: { $0.id == session.continueWatchingItemId }) {
            await ContinueWatchingService.shared.markAsWatched(cwItem)
        }
    }

    /// The user is still watching: keep the session active and re-prompt later.
    func stillWatching(_ session: WatchSession) async {
        guard session.status == .active else { return }
        await scheduleSessionPrompt(for: session, afterMinutes: Self.followUpMinutes)
    }

    /// The user put the title on hold: pause the session, keep it resumable.
    func putOnHold(_ session: WatchSession) {
        cancelPrompt(forSessionId: session.id)
        var updated = session
        updated.status = .onHold
        StorageService.shared.upsertWatchSession(updated)
    }

    /// Resume a previously held session and re-arm the prompt.
    func resume(_ session: WatchSession) async {
        var updated = session
        updated.status = .active
        StorageService.shared.upsertWatchSession(updated)
        await scheduleSessionPrompt(for: updated)
    }

    /// Discard a session without recording history.
    func dismissSession(_ session: WatchSession) {
        cancelPrompt(forSessionId: session.id)
        StorageService.shared.removeWatchSession(id: session.id)
    }

    /// Apply or change a rating on a history entry.
    func rate(_ entry: WatchHistoryEntry, rating: Int) {
        StorageService.shared.updateWatchHistoryRating(entryId: entry.id, rating: rating)
    }

    func clearHistory() {
        StorageService.shared.clearWatchHistory()
    }

    /// Routes a notification action response to the matching handler.
    func handleNotificationResponse(sessionId: String, action: String) async {
        guard let session = StorageService.shared.watchSessions.first(where: { $0.id == sessionId }) else { return }
        switch action {
        case Self.finishedAction:
            await finish(session)
        case Self.stillWatchingAction:
            await stillWatching(session)
        case Self.holdAction:
            putOnHold(session)
        default:
            break
        }
    }

    // MARK: - History Recording

    private func recordHistory(from session: WatchSession, minutes: Int, rating: Int?) {
        let entry = WatchHistoryEntry(
            id: session.id,
            mediaId: session.mediaId,
            mediaType: session.mediaType,
            title: session.title,
            posterPath: session.posterPath,
            seasonNumber: session.seasonNumber,
            episodeNumber: session.episodeNumber,
            episodeTitle: session.episodeTitle,
            watchedAt: Date(),
            minutesWatched: minutes,
            rating: rating,
            deviceName: session.deviceName
        )
        StorageService.shared.appendWatchHistory(entry)
    }

    // MARK: - Runtime Estimation

    private func estimateRuntimeMinutes(for item: SavedMediaItem, episode: ContinueWatchingEpisode?) async -> Int {
        if item.mediaType == .movie {
            if let details = try? await TMDBService.shared.getMovieDetails(id: item.mediaId),
               let runtime = details.runtime, runtime > 0 {
                return runtime
            }
            return Self.defaultMovieRuntime
        } else {
            if let details = try? await TMDBService.shared.getTVShowDetails(id: item.mediaId),
               let runtime = details.episodeRunTime?.first, runtime > 0 {
                return runtime
            }
            return Self.defaultEpisodeRuntime
        }
    }

    // MARK: - Notifications

    private func scheduleSessionPrompt(for session: WatchSession, afterMinutes: Int? = nil) async {
        #if os(tvOS)
        return
        #else
        let granted = await requestNotificationPermission()
        guard granted else { return }

        let identifier = Self.notificationId(forSessionId: session.id)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Still watching \(session.title)?"
        if let code = session.episodeCode {
            content.body = "\(code) — Finished, still watching, or on hold?"
        } else {
            content.body = "Finished, still watching, or on hold?"
        }
        content.sound = .default
        content.categoryIdentifier = Self.sessionCategoryID
        content.userInfo = ["watchHourSessionId": session.id]

        let minutes = afterMinutes ?? session.estimatedRuntimeMinutes
        let interval = max(TimeInterval(minutes * 60), 60) // at least 60s
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try? await notificationCenter.add(request)
        #endif
    }

    private func cancelPrompt(forSessionId id: String) {
        #if !os(tvOS)
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [Self.notificationId(forSessionId: id)]
        )
        #endif
    }

    static func notificationId(forSessionId id: String) -> String {
        "watchhour_session_\(id)"
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
