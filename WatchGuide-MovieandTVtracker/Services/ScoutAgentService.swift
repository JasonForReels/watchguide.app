import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum ScoutAgentAction: String {
    case none = "none"
    case addToWatchlist = "add_to_watchlist"
    case openDetails = "open_details"
}

struct ScoutAgentDecision {
    let action: ScoutAgentAction
    let title: String?
}

struct ScoutAgentRoute: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let opensDetail: Bool
}

@MainActor
final class ScoutAgentRouteCenter: ObservableObject {
    static let shared = ScoutAgentRouteCenter()

    @Published private(set) var pendingRoute: ScoutAgentRoute?

    private init() {}

    func queue(_ route: ScoutAgentRoute) {
        pendingRoute = route
    }

    func consume(_ routeID: UUID) {
        guard pendingRoute?.id == routeID else { return }
        pendingRoute = nil
    }
}

actor ScoutAgentService {
    static let shared = ScoutAgentService()

    private init() {}

    var canUseAgentActions: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 18.0, macOS 15.0, *) {
            return AppleIntelligenceCapabilityService.currentReport().isAppleIntelligenceAvailableNow
        }
        #endif
        return false
    }

    func decision(
        for userMessage: String,
        conversationHistory: [AIService.ChatMessage]
    ) async -> ScoutAgentDecision? {
        guard canUseAgentActions else { return nil }
        guard looksLikeAgentCommand(userMessage) else { return nil }

        let recentHistory = conversationHistory.suffix(6).map {
            "\($0.role.capitalized): \($0.content)"
        }.joined(separator: "\n\n")

        #if canImport(FoundationModels)
        if #available(iOS 18.0, macOS 15.0, *) {
            do {
                let instructions = """
                You convert movie assistant follow-up commands into app actions.
                Infer the target title from the recent conversation when the person says things like "it", "that", or "more details".
                Only return one of these actions:
                - none
                - add_to_watchlist
                - open_details
                Return exactly two lines:
                ACTION: <action>
                TITLE: <title or empty>
                """

                let session = LanguageModelSession(instructions: instructions)
                let prompt = """
                Recent conversation:
                \(recentHistory)

                New user message:
                \(userMessage)
                """
                let response = try await session.respond(to: prompt)
                return parseDecision(from: response.content)
            } catch {
                return nil
            }
        }
        #endif

        return nil
    }

    func resolveMediaItem(for title: String) async -> MediaItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        do {
            let response = try await TMDBService.shared.searchMulti(query: trimmedTitle)
            let candidates = response.results.filter {
                $0.resolvedMediaType == .movie || $0.resolvedMediaType == .tv
            }

            if let exactMatch = candidates.first(where: {
                normalizedTitle($0.displayTitle) == normalizedTitle(trimmedTitle)
            }) {
                return exactMatch
            }

            return candidates.first
        } catch {
            return nil
        }
    }

    private func looksLikeAgentCommand(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let triggers = [
            "add",
            "watchlist",
            "save",
            "open",
            "details",
            "more details",
            "take me",
            "show me"
        ]
        return triggers.contains { lowercased.contains($0) }
    }

    private func parseDecision(from text: String) -> ScoutAgentDecision? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let actionLine = lines.first(where: { $0.uppercased().hasPrefix("ACTION:") }) else {
            return nil
        }

        let titleLine = lines.first(where: { $0.uppercased().hasPrefix("TITLE:") })
        let rawAction = actionLine
            .split(separator: ":", maxSplits: 1)
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "none"
        let rawTitle = titleLine?
            .split(separator: ":", maxSplits: 1)
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let action = ScoutAgentAction(rawValue: rawAction) ?? .none
        let title = rawTitle?.isEmpty == false ? rawTitle : nil
        return ScoutAgentDecision(action: action, title: title)
    }

    private func normalizedTitle(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }
}
