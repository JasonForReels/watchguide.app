//
//  AtlasActionCenter.swift
//  WatchGuide-MovieandTVtracker
//
//  Lets Atlas actually operate the app rather than only talk about it.
//
//  The model emits [ACTION:verb|argument|type] tags, which are stripped from the
//  visible reply (like [TRAILER:] and [PLAYLIST:]) and executed here against
//  StorageService / ScoutAgentRouteCenter. Every executed action produces a
//  receipt so the chat can show what actually happened — the model's claim that
//  it added something is never trusted as evidence that it did.
//

import Foundation
import Combine

// MARK: - Verbs

enum AtlasActionVerb: String, CaseIterable {
    case addToWatchlist      = "add_watchlist"
    case removeFromWatchlist = "remove_watchlist"
    case markWatched         = "mark_watched"
    case like                = "like"
    case openTitle           = "open"
    case openPerson          = "open_person"
    case navigate            = "navigate"
}

/// Screens Atlas is allowed to send the user to.
enum AtlasNavigationTarget: String, CaseIterable {
    case browse
    case search
    case lists
    case watchlist
    case myStreaming = "streaming"
    case watchHour = "watchhour"
    case me
    case settings
}

// MARK: - Requests & receipts

struct AtlasAction: Identifiable, Equatable {
    let id = UUID()
    let verb: AtlasActionVerb
    /// Title, person name, or navigation target depending on the verb.
    let argument: String
    let preferredType: MediaType?
}

struct AtlasActionReceipt: Identifiable, Equatable {
    let id = UUID()
    let verb: AtlasActionVerb
    /// Short past-tense confirmation shown under the reply ("Added Dune to your watchlist").
    let summary: String
    let succeeded: Bool
    let sfSymbol: String
}

/// Published navigation request for `ContentView` to consume. Tab switching
/// lives in the view layer, so the action center only states the intent.
struct AtlasNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let target: AtlasNavigationTarget
}

// MARK: - Center

@MainActor
final class AtlasActionCenter: ObservableObject {
    static let shared = AtlasActionCenter()

    /// Set when Atlas wants to move the user to another screen.
    @Published private(set) var pendingNavigation: AtlasNavigationRequest?

    /// User-facing switch. When off, action tags are stripped and ignored, so
    /// Atlas can still talk about doing things but can't change any data.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    static let enabledKey = "atlas_actions_enabled"

    private init() {
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
    }

    func consumeNavigation(_ id: UUID) {
        guard pendingNavigation?.id == id else { return }
        pendingNavigation = nil
    }

    // MARK: - Execution

    /// Runs the parsed actions in order, returning a receipt for each one that
    /// resolved to something real. Actions that can't be resolved (an unknown
    /// title, say) produce a failure receipt rather than silently vanishing.
    func execute(_ actions: [AtlasAction]) async -> [AtlasActionReceipt] {
        guard isEnabled else { return [] }

        var receipts: [AtlasActionReceipt] = []
        for action in actions {
            if let receipt = await execute(action) {
                receipts.append(receipt)
            }
        }
        return receipts
    }

    private func execute(_ action: AtlasAction) async -> AtlasActionReceipt? {
        switch action.verb {
        case .navigate:
            guard let target = AtlasNavigationTarget(rawValue: action.argument.lowercased()) else {
                return nil
            }
            pendingNavigation = AtlasNavigationRequest(target: target)
            return AtlasActionReceipt(
                verb: .navigate,
                summary: "Opened \(displayName(for: target))",
                succeeded: true,
                sfSymbol: "arrow.forward.circle.fill"
            )

        case .openPerson:
            guard let person = await ScoutAgentService.shared.resolvePerson(for: action.argument) else {
                return failure(action.verb, "Couldn't find \(action.argument)")
            }
            ScoutAgentRouteCenter.shared.queue(
                ScoutAgentRoute(
                    query: person.name,
                    searchType: .person,
                    opensMediaDetail: false,
                    opensPersonPage: true,
                    preferredItem: nil,
                    preferredPerson: person
                )
            )
            return AtlasActionReceipt(
                verb: .openPerson,
                summary: "Opened \(person.name)",
                succeeded: true,
                sfSymbol: "person.crop.circle.fill"
            )

        case .addToWatchlist, .removeFromWatchlist, .markWatched, .like, .openTitle:
            guard let media = await ScoutAgentService.shared.resolveMediaItem(
                for: action.argument,
                preferredType: action.preferredType
            ) else {
                return failure(action.verb, "Couldn't find \(action.argument)")
            }
            return apply(action.verb, to: media)
        }
    }

    private func apply(_ verb: AtlasActionVerb, to media: MediaItem) -> AtlasActionReceipt {
        let storage = StorageService.shared
        let saved = SavedMediaItem(from: media)
        let title = media.displayTitle
        let type = media.resolvedMediaType

        switch verb {
        case .addToWatchlist:
            if storage.isInWantToWatch(media.id, mediaType: type) {
                return AtlasActionReceipt(
                    verb: verb,
                    summary: "\(title) was already in your watchlist",
                    succeeded: true,
                    sfSymbol: "bookmark.fill"
                )
            }
            storage.addToWantToWatch(saved)
            return AtlasActionReceipt(
                verb: verb,
                summary: "Added \(title) to your watchlist",
                succeeded: true,
                sfSymbol: "bookmark.fill"
            )

        case .removeFromWatchlist:
            guard storage.isInWantToWatch(media.id, mediaType: type) else {
                return AtlasActionReceipt(
                    verb: verb,
                    summary: "\(title) wasn't in your watchlist",
                    succeeded: true,
                    sfSymbol: "bookmark.slash.fill"
                )
            }
            storage.removeFromWantToWatch(saved)
            return AtlasActionReceipt(
                verb: verb,
                summary: "Removed \(title) from your watchlist",
                succeeded: true,
                sfSymbol: "bookmark.slash.fill"
            )

        case .markWatched:
            if !storage.isInWatched(media.id, mediaType: type) {
                storage.addToWatched(saved)
            }
            return AtlasActionReceipt(
                verb: verb,
                summary: "Marked \(title) as watched",
                succeeded: true,
                sfSymbol: "checkmark.circle.fill"
            )

        case .like:
            if !storage.isInLiked(media.id, mediaType: type) {
                storage.addToLiked(saved)
            }
            return AtlasActionReceipt(
                verb: verb,
                summary: "Added \(title) to your likes",
                succeeded: true,
                sfSymbol: "heart.fill"
            )

        case .openTitle:
            ScoutAgentRouteCenter.shared.queue(
                ScoutAgentRoute(
                    query: title,
                    searchType: type,
                    opensMediaDetail: true,
                    opensPersonPage: false,
                    preferredItem: media,
                    preferredPerson: nil
                )
            )
            return AtlasActionReceipt(
                verb: verb,
                summary: "Opened \(title)",
                succeeded: true,
                sfSymbol: "film.fill"
            )

        case .openPerson, .navigate:
            // Handled before resolution; unreachable.
            return failure(verb, "Unsupported action")
        }
    }

    private func failure(_ verb: AtlasActionVerb, _ summary: String) -> AtlasActionReceipt {
        AtlasActionReceipt(verb: verb, summary: summary, succeeded: false, sfSymbol: "exclamationmark.circle")
    }

    private func displayName(for target: AtlasNavigationTarget) -> String {
        switch target {
        case .browse:      return "Browse"
        case .search:      return "Search"
        case .lists:       return "Lists"
        case .watchlist:   return "your watchlist"
        case .myStreaming: return "StreamQ"
        case .watchHour:   return "WatchHour"
        case .me:          return "your profile"
        case .settings:    return "Settings"
        }
    }

    // MARK: - Tag parsing

    /// Extracts `[ACTION:verb|argument|type]` tags. `type` is optional and only
    /// meaningful for title lookups (`movie` / `tv`).
    nonisolated static func extractActionTags(from text: String) -> (cleanedText: String, actions: [AtlasAction]) {
        var cleaned = text
        var actions: [AtlasAction] = []

        let pattern = "\\[ACTION:([^\\]]+)\\]"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            for match in matches.reversed() {
                guard let innerRange = Range(match.range(at: 1), in: cleaned),
                      let fullRange = Range(match.range, in: cleaned) else { continue }

                let parts = String(cleaned[innerRange])
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

                if let rawVerb = parts.first?.lowercased(),
                   let verb = AtlasActionVerb(rawValue: rawVerb),
                   parts.count >= 2, !parts[1].isEmpty {
                    let preferredType = parts.count >= 3 ? MediaType(rawValue: parts[2].lowercased()) : nil
                    actions.insert(
                        AtlasAction(verb: verb, argument: parts[1], preferredType: preferredType),
                        at: 0
                    )
                }
                cleaned.replaceSubrange(fullRange, with: "")
            }
        }

        cleaned = cleaned
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (cleaned, actions)
    }

    /// Instruction block describing the action vocabulary to the model.
    nonisolated static var promptInstructions: String {
        """

        - APP CONTROL: You can operate the app. When the user asks you to do something \
        (not merely discuss it), end your reply with one or more [ACTION:...] tags:
          [ACTION:add_watchlist|Exact Title|movie] or |tv — add a title to their watchlist
          [ACTION:remove_watchlist|Exact Title|movie] — remove a title from their watchlist
          [ACTION:mark_watched|Exact Title|tv] — mark a title watched
          [ACTION:like|Exact Title|movie] — add a title to their likes
          [ACTION:open|Exact Title|movie] — open a title's detail page
          [ACTION:open_person|Person Name] — open a person's page
          [ACTION:navigate|search] — go to a screen: browse, search, lists, watchlist, streaming, watchhour, me, settings
        Rules: only act when clearly asked; never act on a hypothetical or a recommendation \
        the user hasn't accepted. Use the exact official title. Say plainly what you're doing in \
        one short sentence, in the past tense, then place the tags at the very end. Do not mention \
        or explain the tags themselves, and never invent a confirmation for an action you didn't tag.
        """
    }
}
