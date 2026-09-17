//
//  WatchGuideShortcuts.swift
//  WatchGuide-MovieandTVtracker
//
//  Surfaces App Intents in the Shortcuts app and Siri suggestions.
//

#if canImport(AppIntents)
import AppIntents

struct WatchGuideShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddToWatchlistIntent(),
            phrases: [
                "Add to my watchlist in \(.applicationName)",
                "Save to my watchlist in \(.applicationName)"
            ],
            shortTitle: "Add to Watchlist",
            systemImageName: "bookmark.fill"
        )

        AppShortcut(
            intent: RemoveFromWatchlistIntent(),
            phrases: [
                "Remove from my watchlist in \(.applicationName)",
                "Delete from my watchlist in \(.applicationName)"
            ],
            shortTitle: "Remove from Watchlist",
            systemImageName: "bookmark.slash"
        )

        AppShortcut(
            intent: MarkAsWatchedIntent(),
            phrases: [
                "Mark as watched in \(.applicationName)",
                "I watched something in \(.applicationName)"
            ],
            shortTitle: "Mark as Watched",
            systemImageName: "checkmark.circle.fill"
        )

        AppShortcut(
            intent: SearchMediaIntent(),
            phrases: [
                "Search in \(.applicationName)",
                "Find something in \(.applicationName)",
                "Look up in \(.applicationName)"
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )

        AppShortcut(
            intent: GetUpNextIntent(),
            phrases: [
                "What's next on my watchlist in \(.applicationName)",
                "Show my watchlist in \(.applicationName)",
                "What should I watch in \(.applicationName)"
            ],
            shortTitle: "Up Next",
            systemImageName: "list.bullet"
        )

        AppShortcut(
            intent: SmartCategorizeIntent(),
            phrases: [
                "Organize my lists in \(.applicationName)",
                "Create smart lists in \(.applicationName)",
                "Categorize my watch history in \(.applicationName)"
            ],
            shortTitle: "Smart Categorize",
            systemImageName: "wand.and.sparkles"
        )

        AppShortcut(
            intent: FindSimilarMoviesIntent(),
            phrases: [
                "Find similar movies in \(.applicationName)",
                "Recommend movies in \(.applicationName)",
                "What should I watch in \(.applicationName)"
            ],
            shortTitle: "Find Similar Movies",
            systemImageName: "film.stack"
        )

        AppShortcut(
            intent: OpenMovieInAppIntent(),
            phrases: [
                "Open a movie in \(.applicationName)",
                "Show a movie in \(.applicationName)"
            ],
            shortTitle: "Open Movie",
            systemImageName: "play.circle"
        )

        // Apple Intelligence extras. These are always registered — each intent
        // gates on device capability at run time and tells Siri why it can't
        // help, which reads better than the phrase silently not existing.
        AppShortcut(
            intent: AskWatchGuideIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) about a movie"
            ],
            shortTitle: "Ask Watch Guide",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: PickTonightsWatchIntent(),
            phrases: [
                "Pick something to watch in \(.applicationName)",
                "What should I watch tonight in \(.applicationName)"
            ],
            shortTitle: "Pick Tonight's Watch",
            systemImageName: "moon.stars"
        )
    }
}

#endif
