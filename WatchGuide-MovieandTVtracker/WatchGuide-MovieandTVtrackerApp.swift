//
//  WatchGuide_MovieandTVtrackerApp.swift
//  WatchGuide-MovieandTVtracker
//
//  Created by Neel Makhecha on 9/5/25.
//

import SwiftUI
#if canImport(CoreSpotlight) && !os(tvOS)
import CoreSpotlight
#endif

// MARK: - Notification Delegate

#if !os(tvOS)
import UserNotifications
class ContinueWatchingNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ContinueWatchingNotificationDelegate()

    private static let categoryID = "CONTINUE_WATCHING_REMINDER"
    private static let markWatchedAction = "MARK_WATCHED"
    private static let notYetAction = "NOT_YET"

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let markWatched = UNNotificationAction(
            identifier: Self.markWatchedAction,
            title: "Mark as Watched",
            options: []
        )
        let notYet = UNNotificationAction(
            identifier: Self.notYetAction,
            title: "Not Yet",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [markWatched, notYet],
            intentIdentifiers: [],
            options: []
        )

        // WatchHour session prompt: Finished / Still Watching / On Hold.
        let finished = UNNotificationAction(
            identifier: WatchHourService.finishedAction,
            title: "Finished",
            options: []
        )
        let stillWatching = UNNotificationAction(
            identifier: WatchHourService.stillWatchingAction,
            title: "Still Watching",
            options: []
        )
        let onHold = UNNotificationAction(
            identifier: WatchHourService.holdAction,
            title: "On Hold",
            options: []
        )
        let watchHourCategory = UNNotificationCategory(
            identifier: WatchHourService.sessionCategoryID,
            actions: [finished, stillWatching, onHold],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category, watchHourCategory])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        let userInfo = response.notification.request.content.userInfo

        // WatchHour session prompt responses.
        if categoryIdentifier == WatchHourService.sessionCategoryID {
            let sessionId = userInfo["watchHourSessionId"] as? String
            let action = response.actionIdentifier
            Task { @MainActor in
                if let sessionId {
                    await WatchHourService.shared.handleNotificationResponse(sessionId: sessionId, action: action)
                }
                completionHandler()
            }
            return
        }

        if categoryIdentifier == LeavingSoonService.categoryID {
            #if os(iOS)
            if let link = userInfo["deepLink"] as? String, let url = URL(string: link) {
                Task { @MainActor in UIApplication.shared.open(url) }
            }
            #endif
            completionHandler()
            return
        }

        guard categoryIdentifier == Self.categoryID else {
            completionHandler()
            return
        }

        let itemId = userInfo["continueWatchingItemId"] as? String

        Task { @MainActor in
            if response.actionIdentifier == Self.markWatchedAction, let itemId {
                if let item = StorageService.shared.continueWatching.first(where: { $0.id == itemId }) {
                    await ContinueWatchingService.shared.markAsWatched(item)
                }
            }
            // "NOT_YET" or default dismiss — do nothing, item stays in progress
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
#endif

@main
struct WatchGuide_MovieandTVtrackerApp: App {
    #if !os(tvOS)
    @StateObject private var scoutSubscription = ScoutSubscriptionService.shared
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if !os(tvOS)
        ContinueWatchingNotificationDelegate.shared.setup()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .preferredColorScheme(.dark)
                #if !os(tvOS)
                .task {
                    await scoutSubscription.prepare()
                    #if os(iOS)
                    _ = ReleaseActivityManager.shared // Initialize the manager
                    #endif

                    // Register App Shortcuts so Siri can discover them
                    #if canImport(AppIntents)
                    WatchGuideShortcuts.updateAppShortcutParameters()
                    #endif

                    // Daily MOTN deep link cache warm-up (background, non-blocking)
                    Task.detached(priority: .utility) {
                        await StreamingDeepLinkService.shared.warmCacheIfNeeded()
                        await LeavingSoonService.shared.scanIfNeeded()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await scoutSubscription.prepare()
                        #if os(iOS)
                        _ = ReleaseActivityManager.shared // Ensure manager is alive
                        #endif
                        await LeavingSoonService.shared.scanIfNeeded()
                    }
                }
                #endif
                // Handle Spotlight search result taps
                #if canImport(CoreSpotlight) && !os(tvOS)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    handleSpotlightActivity(activity)
                }
                #endif
                // Handle watchguide:// deep link URLs (from Spotlight contentURL)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    // MARK: - Deep Link Handling

    /// Handle a Spotlight search result tap — extracts the media identifier and
    /// routes through ScoutAgentRouteCenter to open the detail page.
    private func handleSpotlightActivity(_ activity: NSUserActivity) {
        #if canImport(CoreSpotlight) && !os(tvOS)
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
        guard let parsed = SpotlightIndexingService.parseSpotlightIdentifier(identifier) else { return }

        openMediaDetail(mediaId: parsed.mediaId, mediaType: parsed.mediaType)
        #endif
    }

    /// Handle watchguide:// URLs.
    ///
    /// Two shapes: `watchguide://media/{mediaType}/{mediaId}` from Spotlight, and
    /// the bare destinations the Control Center controls use — `watchguide://atlas`,
    /// `//search`, `//watchlist`, `//scanner`, `//tonight`.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "watchguide" else { return }

        // A bare destination has no path, so it arrives entirely as the host.
        if let host = url.host,
           let destination = WatchGuideQuickRouteCenter.Destination(rawValue: host) {
            Task { @MainActor in
                WatchGuideQuickRouteCenter.shared.open(destination)
            }
            return
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        // Expected: ["media", "movie" or "tv", "123"]
        guard pathComponents.count >= 3,
              pathComponents[0] == "media",
              let mediaType = MediaType(rawValue: pathComponents[1]),
              let mediaId = Int(pathComponents[2]) else { return }

        openMediaDetail(mediaId: mediaId, mediaType: mediaType)
    }

    /// Fetch the title from TMDB and route to the Search tab with a detail open.
    private func openMediaDetail(mediaId: Int, mediaType: MediaType) {
        Task { @MainActor in
            // Look up the title so we can use the typewriter animation
            let title: String
            do {
                if mediaType == .movie {
                    let details = try await TMDBService.shared.getMovieDetails(id: mediaId)
                    title = details.title
                } else {
                    let details = try await TMDBService.shared.getTVShowDetails(id: mediaId)
                    title = details.name
                }
            } catch {
                // Fallback: just search by ID
                title = "\(mediaId)"
            }

            let route = ScoutAgentRoute(
                query: title,
                searchType: mediaType == .movie ? .movie : .tv,
                opensMediaDetail: true,
                opensPersonPage: false,
                preferredItem: nil,
                preferredPerson: nil
            )
            ScoutAgentRouteCenter.shared.queue(route)
        }
    }
}
