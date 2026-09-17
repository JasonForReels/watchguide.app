//
//  WatchGuideIntents.swift
//  WatchGuide-MovieandTVtracker
//
//  Siri & App Intents for hands-free watchlist management and search.
//

#if canImport(AppIntents)
import AppIntents
import Foundation

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels

// MARK: - @Generable types for similar-movie recommendations

@available(iOS 18.0, macOS 15.0, *)
@Generable(description: "A single movie recommendation")
struct SiriMovieRecommendation {
    @Guide(description: "The exact, official movie title")
    var title: String

    @Guide(description: "One short sentence explaining why it is similar")
    var reason: String
}

@available(iOS 18.0, macOS 15.0, *)
@Generable(description: "A list of similar movie recommendations")
struct SiriSimilarMoviesOutput {
    @Guide(description: "Exactly 5 movies similar to the requested title")
    var movies: [SiriMovieRecommendation]
}
#endif

// MARK: - Add to Watchlist

struct AddToWatchlistIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Watchlist"
    static var description = IntentDescription(
        "Add a movie or TV show to your Watch Guide watchlist.",
        categoryName: "Watchlist"
    )

    @Parameter(title: "Title", description: "The name of the movie or TV show to add.")
    var mediaTitle: String

    @Parameter(title: "Type", description: "Movie or TV Show.", default: .movie)
    var mediaType: WatchGuideMediaTypeParam

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$mediaTitle) to my watchlist") {
            \.$mediaType
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let searchType: MediaType = mediaType == .tv ? .tv : .movie
        guard let item = await resolveMediaItem(title: mediaTitle, type: searchType) else {
            return .result(dialog: "I couldn't find \"\(mediaTitle)\". Try a different title.")
        }

        let savedItem = SavedMediaItem(from: item)
        await MainActor.run {
            StorageService.shared.addToWantToWatch(savedItem)
        }

        return .result(dialog: "Added \"\(item.displayTitle)\" to your watchlist. 🍿")
    }
}

// MARK: - Remove from Watchlist

struct RemoveFromWatchlistIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove from Watchlist"
    static var description = IntentDescription(
        "Remove a movie or TV show from your Watch Guide watchlist.",
        categoryName: "Watchlist"
    )

    @Parameter(title: "Title", description: "The name of the movie or TV show to remove.")
    var mediaTitle: String

    static var parameterSummary: some ParameterSummary {
        Summary("Remove \(\.$mediaTitle) from my watchlist")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let match = await findInWatchlist(title: mediaTitle)
        guard let match else {
            return .result(dialog: "I couldn't find \"\(mediaTitle)\" in your watchlist.")
        }

        await MainActor.run {
            StorageService.shared.removeFromWantToWatch(match)
        }

        return .result(dialog: "Removed \"\(match.title)\" from your watchlist.")
    }
}

// MARK: - Mark as Watched

struct MarkAsWatchedIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark as Watched"
    static var description = IntentDescription(
        "Mark a movie or TV show as watched in Watch Guide.",
        categoryName: "Watchlist"
    )

    @Parameter(title: "Title", description: "The name of the movie or TV show you watched.")
    var mediaTitle: String

    @Parameter(title: "Type", description: "Movie or TV Show.", default: .movie)
    var mediaType: WatchGuideMediaTypeParam

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$mediaTitle) as watched") {
            \.$mediaType
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // First check if it's already in watchlist
        if let existing = await findInWatchlist(title: mediaTitle) {
            await MainActor.run {
                StorageService.shared.removeFromWantToWatch(existing)
                StorageService.shared.addToWatched(existing)
            }
            return .result(dialog: "Marked \"\(existing.title)\" as watched. ✅")
        }

        // Otherwise search TMDB and add directly to watched
        let searchType: MediaType = mediaType == .tv ? .tv : .movie
        guard let item = await resolveMediaItem(title: mediaTitle, type: searchType) else {
            return .result(dialog: "I couldn't find \"\(mediaTitle)\". Try a different title.")
        }

        let savedItem = SavedMediaItem(from: item)
        await MainActor.run {
            StorageService.shared.addToWatched(savedItem)
        }

        return .result(dialog: "Marked \"\(item.displayTitle)\" as watched. ✅")
    }
}

// MARK: - Search Media (Opens App with Typewriter Animation)

struct SearchMediaIntent: AppIntent {
    static var title: LocalizedStringResource = "Search in Watch Guide"
    static var description = IntentDescription(
        "Search for a movie or TV show in Watch Guide.",
        categoryName: "Search"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Query", description: "What to search for.")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search for \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Route through ScoutAgentRouteCenter to trigger typewriter animation in SearchView
        let route = ScoutAgentRoute(
            query: query,
            searchType: nil,
            opensMediaDetail: false,
            opensPersonPage: false,
            preferredItem: nil,
            preferredPerson: nil
        )
        ScoutAgentRouteCenter.shared.queue(route)

        return .result()
    }
}

// MARK: - Get Up Next

struct GetUpNextIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Next on My Watchlist"
    static var description = IntentDescription(
        "See what's next on your Watch Guide watchlist.",
        categoryName: "Watchlist"
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Show what's next on my watchlist")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let items: [SavedMediaItem] = await MainActor.run {
            Array(StorageService.shared.wantToWatch.prefix(5))
        }

        guard !items.isEmpty else {
            return .result(dialog: "Your watchlist is empty. Add some movies or shows to get started!")
        }

        let titles = items.enumerated().map { index, item in
            "\(index + 1). \(item.title)"
        }.joined(separator: "\n")

        let count = items.count
        let header = count == 1 ? "Here's what's next:" : "Here are your next \(count) titles:"

        return .result(dialog: "\(header)\n\(titles)")
    }
}

// MARK: - Find Similar Movies
//
// Step 1 of the two-step flow:
//   "Find movies similar to Interstellar in WatchGuide"
//   → Siri reads a numbered list; each title is something the user can open.
//
// On-device path: FoundationModels @Generable → spoken recommendations + reasons
// Fallback:       TMDB /movie/{id}/similar → spoken title list

struct FindSimilarMoviesIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Similar Movies"
    static var description = IntentDescription(
        "Finds movies similar to one you name, using on-device intelligence.",
        categoryName: "Discover"
    )

    @Parameter(title: "Movie", description: "The movie you want recommendations for.")
    var movieTitle: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find movies similar to \(\.$movieTitle)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = movieTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "What movie would you like recommendations for?")
        }

        // Both paths produce a dialog string; a single return at the end keeps
        // the opaque return type consistent for the compiler.
        var dialog = ""

        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 18.0, macOS 15.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability, model.supportsLocale(Locale.current) {
                dialog = try await buildDialogViaFoundationModels(title: trimmed, model: model)
            }
        }
        #endif

        if dialog.isEmpty {
            dialog = try await buildDialogViaTMDB(title: trimmed)
        }

        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }

    // MARK: On-device path — builds a dialog string using @Generable structured output

    #if canImport(FoundationModels) && !os(tvOS)
    @available(iOS 18.0, macOS 15.0, *)
    private func buildDialogViaFoundationModels(title: String, model: SystemLanguageModel) async throws -> String {
        let instructions = """
        You are a film expert. Given a movie title, recommend exactly 5 similar movies
        the person is likely to enjoy based on genre, tone, themes, or director style.
        Only recommend real, well-known movies. Keep each reason to one sentence.
        """

        let session  = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: "Find 5 movies similar to \"\(title)\".",
            generating: SiriSimilarMoviesOutput.self
        )

        let lines = response.content.movies.enumerated().map { i, m in
            "\(i + 1). \(m.title) — \(m.reason)"
        }.joined(separator: "\n")

        return """
        Here are 5 movies similar to \(title):

        \(lines)

        Say "Open [title] in WatchGuide" to jump to any of these.
        """
    }
    #endif

    // MARK: TMDB fallback — uses /movie/{id}/similar

    private func buildDialogViaTMDB(title: String) async throws -> String {
        guard let match = await resolveMediaItem(title: title, type: .movie) else {
            return "I couldn't find \"\(title)\". Try a different title."
        }

        let similar = try await TMDBService.shared.getSimilarMovies(id: match.id)
        let top5    = Array(similar.results.prefix(5))

        guard !top5.isEmpty else {
            return "I found \"\(match.displayTitle)\" but couldn't find similar movies right now."
        }

        let lines = top5.enumerated().map { i, m in
            "\(i + 1). \(m.displayTitle)"
        }.joined(separator: "\n")

        return """
        Here are movies similar to \(match.displayTitle):

        \(lines)

        Say "Open [title] in WatchGuide" to jump to any of these.
        """
    }
}

// MARK: - Open Movie in WatchGuide
//
// Step 2 of the flow — triggered after the user hears the list:
//   "Open Arrival in WatchGuide"
//   → Resolves the title to a TMDB MediaItem, then opens directly to that detail page.
//   The resolved preferredItem is what tells the app which page to push — without it
//   the route falls through to the default tab.

struct OpenMovieInAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Movie in WatchGuide"
    static var description = IntentDescription(
        "Opens a specific movie's page directly inside WatchGuide.",
        categoryName: "Discover"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Movie", description: "The movie to open.")
    var movieTitle: String

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$movieTitle) in WatchGuide")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = movieTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Which movie would you like to open?")
        }

        // Resolve to a real TMDB item so the app can push directly to the detail page.
        // Checking TV as well since the user might say a show name.
        let movieMatch = await resolveMediaItem(title: trimmed, type: .movie)
        let tvMatch    = await resolveMediaItem(title: trimmed, type: .tv)
        let resolved   = movieMatch ?? tvMatch

        guard let item = resolved else {
            return .result(dialog: "I couldn't find \"\(trimmed)\" in WatchGuide. Try a different title.")
        }

        let route = ScoutAgentRoute(
            query: trimmed,
            searchType: item.resolvedMediaType,
            opensMediaDetail: true,
            opensPersonPage: false,
            preferredItem: item,
            preferredPerson: nil
        )

        await MainActor.run {
            ScoutAgentRouteCenter.shared.queue(route)
        }

        return .result(dialog: "Opening \(item.displayTitle) in WatchGuide.")
    }
}

// MARK: - Smart Categorize
//
// This intent runs entirely on-device using Apple Intelligence (FoundationModels).
// It does NOT require the app to be open — Siri invokes it as a background intent
// and reads the result dialog back to the user.
// `openAppWhenRun` is false by default, so no app launch occurs.

struct SmartCategorizeIntent: AppIntent {
    static var title: LocalizedStringResource = "Organize My Lists with AI"
    static var description = IntentDescription(
        "Analyses your watch history and automatically creates smart custom lists — entirely on-device, with no data sent to the cloud.",
        categoryName: "Lists"
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Organize my Watch Guide lists with AI")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Check Apple Intelligence availability before touching the model.
        // Return a human-readable Siri dialog for every failure case rather than throwing,
        // so Siri always has something useful to say.
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 18.0, macOS 15.0, *) {
            let model = SystemLanguageModel.default
            if case .unavailable(let reason) = model.availability {
                switch reason {
                case .deviceNotEligible:
                    return .result(dialog: "Smart categorization requires an Apple Intelligence-capable device.")
                case .appleIntelligenceNotEnabled:
                    return .result(dialog: "Please enable Apple Intelligence in Settings > Apple Intelligence & Siri, then try again.")
                default:
                    return .result(dialog: "Apple Intelligence isn't ready right now. Try again in a moment.")
                }
            }
            guard model.supportsLocale(Locale.current) else {
                return .result(dialog: "Apple Intelligence doesn't support your current language for smart categorization yet.")
            }
        } else {
            return .result(dialog: "Smart categorization requires iOS 18 or later with Apple Intelligence.")
        }
        #else
        return .result(dialog: "Smart categorization is not available on this platform.")
        #endif

        // History check
        let hasHistory = await MainActor.run {
            !StorageService.shared.watched.isEmpty || !StorageService.shared.liked.isEmpty
        }
        guard hasHistory else {
            return .result(dialog: "Your watch history is empty. Mark some titles as watched first, then ask me to organize your lists.")
        }

        // Run the on-device Foundation Models path — no network, fully private
        do {
            let count = try await TraktSmartCategorizationService.shared.generateSmartListsOnDevice()

            if count > 0 {
                let names = await MainActor.run {
                    StorageService.shared.customLists.suffix(count).map(\.name).joined(separator: ", ")
                }
                return .result(dialog: "Done! I created \(count) smart list\(count == 1 ? "" : "s") from your history using Apple Intelligence: \(names).")
            } else {
                return .result(dialog: "Your smart lists are already up to date. Delete existing ones if you'd like a fresh set.")
            }
        } catch SmartCategorizationError.appleIntelligenceUnavailable {
            return .result(dialog: "Apple Intelligence isn't available right now. Try again in a moment.")
        } catch SmartCategorizationError.unsupportedLocale {
            return .result(dialog: "Apple Intelligence doesn't support your current language for this feature.")
        } catch SmartCategorizationError.emptyHistory {
            return .result(dialog: "Your watch history is empty. Mark some titles as watched first.")
        }
    }
}

// MARK: - Media Type Parameter

enum WatchGuideMediaTypeParam: String, AppEnum {
    case movie
    case tv

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Media Type"
    static var caseDisplayRepresentations: [WatchGuideMediaTypeParam: DisplayRepresentation] = [
        .movie: "Movie",
        .tv: "TV Show"
    ]
}

// MARK: - Helper Functions

/// Resolve a title to a TMDB MediaItem via search
private func resolveMediaItem(title: String, type: MediaType) async -> MediaItem? {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    do {
        let results: [MediaItem]
        if type == .tv {
            results = try await TMDBService.shared.searchTV(query: trimmed).results
        } else {
            results = try await TMDBService.shared.searchMovies(query: trimmed).results
        }

        // Prefer exact title match, then fall back to first result
        let normalizedQuery = trimmed.lowercased()
        if let exactMatch = results.first(where: {
            $0.displayTitle.lowercased() == normalizedQuery
        }) {
            return exactMatch
        }

        return results.first
    } catch {
        return nil
    }
}

/// Find a saved item in the watchlist by fuzzy title match
private func findInWatchlist(title: String) async -> SavedMediaItem? {
    let normalizedQuery = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else { return nil }

    let items: [SavedMediaItem] = await MainActor.run {
        StorageService.shared.wantToWatch
    }

    // Try exact match first
    if let exact = items.first(where: { $0.title.lowercased() == normalizedQuery }) {
        return exact
    }

    // Try contains match
    if let partial = items.first(where: { $0.title.lowercased().contains(normalizedQuery) }) {
        return partial
    }

    // Try query contains item title
    return items.first(where: { normalizedQuery.contains($0.title.lowercased()) })
}

#endif
