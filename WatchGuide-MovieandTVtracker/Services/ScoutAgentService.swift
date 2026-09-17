import Foundation

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

enum ScoutAgentAction: String {
    case none = "none"
    case addToWatchlist = "add_to_watchlist"
    case openDetails = "open_details"
    case openPersonPage = "open_person_page"
}

enum ScoutAgentTargetType: String {
    case movie = "movie"
    case tv = "tv"
    case person = "person"
}

struct ScoutAgentDecision {
    let action: ScoutAgentAction
    let title: String?
    let targetType: ScoutAgentTargetType?
}

private struct ScoutLookupHints {
    let title: String?
    let personName: String?
    let premiseKeywords: [String]
    let year: Int?
}

private struct ParsedAgentQuery {
    let cleanedQuery: String
    let year: Int?
}

struct ScoutAgentRoute: Identifiable {
    let id = UUID()
    let query: String
    let searchType: MediaType?
    let opensMediaDetail: Bool
    let opensPersonPage: Bool
    let preferredItem: MediaItem?
    let preferredPerson: Person?
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

    nonisolated func looksLikeNavigationOnlyCommand(_ text: String) -> Bool {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "take me to",
            "go to",
            "open",
            "show me"
        ]

        guard prefixes.contains(where: { lowercased.hasPrefix($0) }) else { return false }
        return !lowercased.contains("watchlist")
    }

    var canUseAgentActions: Bool {
        #if canImport(FoundationModels) && !os(tvOS)
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
        guard looksLikeAgentCommand(userMessage) else { return nil }

        let heuristicDecision = finalizeDecision(
            heuristicDecision(for: userMessage),
            conversationHistory: conversationHistory
        )

        guard canUseAgentActions else { return heuristicDecision }

        let recentHistory = conversationHistory.suffix(6).map {
            "\($0.role.capitalized): \($0.content)"
        }.joined(separator: "\n\n")

        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 18.0, macOS 15.0, *) {
            do {
                let instructions = """
                You convert movie assistant follow-up commands into app actions.
                Infer the target title from the recent conversation when the person says things like "it", "that", or "more details".
                Only return one of these actions:
                - none
                - add_to_watchlist
                - open_details
                - open_person_page
                Return exactly three lines:
                ACTION: <action>
                TITLE: <title or empty>
                TYPE: <movie, tv, person, or empty>
                """

                let session = LanguageModelSession(instructions: instructions)
                let prompt = """
                Recent conversation:
                \(recentHistory)

                New user message:
                \(userMessage)
                """
                let response = try await session.respond(to: prompt)
                let parsed = parseDecision(from: response.content)
                return finalizeDecision(parsed, conversationHistory: conversationHistory) ?? heuristicDecision
            } catch {
                return heuristicDecision
            }
        }
        #endif

        return heuristicDecision
    }

    func resolveMediaItem(for title: String, preferredType: MediaType? = nil) async -> MediaItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let parsedQuery = parsedAgentQuery(from: trimmedTitle)

        if let directMatch = await resolveDirectSearchMatch(
            for: parsedQuery.cleanedQuery,
            preferredType: preferredType,
            year: parsedQuery.year
        ) {
            return directMatch
        }

        let hints = await lookupHints(for: parsedQuery.cleanedQuery)
        if let hintTitle = hints.title,
           normalizedTitle(hintTitle) != normalizedTitle(parsedQuery.cleanedQuery),
           let hintMatch = await resolveDirectSearchMatch(
                for: hintTitle,
                preferredType: preferredType,
                year: hints.year ?? parsedQuery.year
           ) {
            return hintMatch
        }

        if let personName = hints.personName,
           let creditMatch = await resolveCreditMatch(
                personName: personName,
                hints: hints,
                originalQuery: parsedQuery.cleanedQuery,
                preferredType: preferredType
           ) {
            return creditMatch
        }

        if let fallback = await resolveDirectSearchMatch(
            for: fallbackQuery(from: parsedQuery.cleanedQuery, hints: hints),
            preferredType: preferredType,
            year: hints.year ?? parsedQuery.year
        ) {
            return fallback
        }

        return nil
    }

    func resolvePerson(for name: String) async -> Person? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        do {
            let response = try await TMDBService.shared.searchPerson(query: trimmedName)
            return response.results.first(where: { normalizedTitle($0.name) == normalizedTitle(trimmedName) }) ?? response.results.first
        } catch {
            return nil
        }
    }

    private func resolveDirectSearchMatch(for query: String, preferredType: MediaType?, year: Int? = nil) async -> MediaItem? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        do {
            let candidates: [MediaItem]
            if preferredType == .movie {
                candidates = try await TMDBService.shared.searchMovies(query: trimmedQuery, year: year).results
            } else if preferredType == .tv {
                candidates = try await TMDBService.shared.searchTV(query: trimmedQuery, year: year).results
            } else {
                candidates = try await TMDBService.shared.searchMulti(query: trimmedQuery).results.filter {
                    $0.resolvedMediaType == .movie || $0.resolvedMediaType == .tv
                }
            }
            let typedCandidates = filtered(candidates, for: preferredType)

            if let exactMatch = typedCandidates.first(where: {
                normalizedTitle($0.displayTitle) == normalizedTitle(trimmedQuery)
            }) {
                return exactMatch
            }

            return typedCandidates.first ?? candidates.first
        } catch {
            return nil
        }
    }

    private func lookupHints(for query: String) async -> ScoutLookupHints {
        return parseLookupHints(from: "", originalQuery: query)
    }

    private func parseLookupHints(from text: String, originalQuery: String) -> ScoutLookupHints {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let title = sanitizedTitle(valueForPrefix("TITLE:", in: lines))
        let personName = sanitizedTitle(valueForPrefix("PERSON:", in: lines)) ?? fallbackPersonName(from: originalQuery)
        let plotLine = sanitizedTitle(valueForPrefix("PLOT:", in: lines))
        let premiseKeywords = parsePremiseKeywords(plotLine, originalQuery: originalQuery)
        let year = valueForPrefix("YEAR:", in: lines).flatMap { Int($0) }

        return ScoutLookupHints(
            title: title,
            personName: personName,
            premiseKeywords: premiseKeywords,
            year: year
        )
    }

    private func resolveCreditMatch(
        personName: String,
        hints: ScoutLookupHints,
        originalQuery: String,
        preferredType: MediaType?
    ) async -> MediaItem? {
        do {
            let personResponse = try await TMDBService.shared.searchPerson(query: personName)
            guard let person = personResponse.results.first else { return nil }

            async let movieCreditsTask = TMDBService.shared.getPersonMovieCredits(id: person.id)
            async let tvCreditsTask = TMDBService.shared.getPersonTVCredits(id: person.id)

            let movieCredits = try await movieCreditsTask
            let tvCredits = try await tvCreditsTask

            let credits = (movieCredits.cast ?? []) + (tvCredits.cast ?? [])
            let filtered = deduplicatedMediaItems(credits).filter {
                $0.resolvedMediaType == .movie || $0.resolvedMediaType == .tv
            }
            let typedFiltered = self.filtered(filtered, for: preferredType)

            return bestCreditMatch(in: typedFiltered.isEmpty ? filtered : typedFiltered, hints: hints, originalQuery: originalQuery)
        } catch {
            return nil
        }
    }

    private func bestCreditMatch(
        in items: [MediaItem],
        hints: ScoutLookupHints,
        originalQuery: String
    ) -> MediaItem? {
        let normalizedQueryKeywords = keywordSet(from: originalQuery)

        return items
            .map { item in
                (item, score(item: item, hints: hints, queryKeywords: normalizedQueryKeywords))
            }
            .sorted {
                if $0.1 == $1.1 {
                    return ($0.0.popularity ?? 0) > ($1.0.popularity ?? 0)
                }
                return $0.1 > $1.1
            }
            .first(where: { $0.1 > 0 })?
            .0
    }

    private func score(item: MediaItem, hints: ScoutLookupHints, queryKeywords: Set<String>) -> Int {
        var total = 0
        let normalizedDisplayTitle = normalizedTitle(item.displayTitle)
        let overviewKeywords = keywordSet(from: item.overview ?? "")

        if let title = hints.title, normalizedDisplayTitle == normalizedTitle(title) {
            total += 120
        } else if let title = hints.title, normalizedDisplayTitle.contains(normalizedTitle(title)) {
            total += 80
        }

        if let year = hints.year, item.year == String(year) {
            total += 20
        }

        let premiseMatches = hints.premiseKeywords.filter { keyword in
            overviewKeywords.contains(keyword) || normalizedDisplayTitle.contains(keyword)
        }
        total += premiseMatches.count * 18

        let queryMatches = queryKeywords.filter { keyword in
            overviewKeywords.contains(keyword) || normalizedDisplayTitle.contains(keyword)
        }
        total += queryMatches.count * 8

        return total
    }

    private func fallbackQuery(from query: String, hints: ScoutLookupHints) -> String {
        if !hints.premiseKeywords.isEmpty {
            return hints.premiseKeywords.joined(separator: " ")
        }

        if let personName = hints.personName {
            return personName
        }

        return query
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

    private func heuristicDecision(for userMessage: String) -> ScoutAgentDecision? {
        let lowercased = userMessage.lowercased()
        let targetType = inferredTargetType(from: lowercased)
        let explicitTitle = explicitCommandTitle(from: userMessage, targetType: targetType)

        if lowercased.contains("watchlist") || lowercased.contains("save") || lowercased.contains("add it") || lowercased.contains("add that") {
            return ScoutAgentDecision(action: .addToWatchlist, title: explicitTitle, targetType: targetType)
        }

        let personPhrases = [
            "actor page",
            "actress page",
            "person page",
            "cast page",
            "celebrity page"
        ]

        if personPhrases.contains(where: { lowercased.contains($0) }) || (targetType == .person && lowercased.contains("page")) {
            return ScoutAgentDecision(action: .openPersonPage, title: explicitTitle, targetType: .person)
        }

        if let explicitTitle {
            let navigationPrefixes = ["take me to", "go to", "open", "show me"]
            if navigationPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
                let resolvedTargetType = targetType ?? inferredEntityType(from: explicitTitle)
                let action: ScoutAgentAction = resolvedTargetType == .person ? .openPersonPage : .openDetails
                let finalTargetType = resolvedTargetType == .person ? ScoutAgentTargetType.person : resolvedTargetType
                return ScoutAgentDecision(action: action, title: explicitTitle, targetType: finalTargetType)
            }
        }

        let detailPhrases = [
            "more details",
            "see more details",
            "take me to see more details",
            "show me more details",
            "open details",
            "take me there",
            "open it",
            "show it"
        ]

        if detailPhrases.contains(where: { lowercased.contains($0) }) {
            return ScoutAgentDecision(action: .openDetails, title: explicitTitle, targetType: targetType)
        }

        return nil
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
        let typeLine = lines.first(where: { $0.uppercased().hasPrefix("TYPE:") })
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
        let rawType = typeLine?
            .split(separator: ":", maxSplits: 1)
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let action = ScoutAgentAction(rawValue: rawAction) ?? .none
        let title = sanitizedTitle(rawTitle)
        let targetType = rawType.flatMap(ScoutAgentTargetType.init(rawValue:))
        return ScoutAgentDecision(action: action, title: title, targetType: targetType)
    }

    private func finalizeDecision(
        _ decision: ScoutAgentDecision?,
        conversationHistory: [AIService.ChatMessage]
    ) -> ScoutAgentDecision? {
        let action = decision?.action ?? .none
        guard action != .none else { return nil }

        if let title = decision?.title {
            return ScoutAgentDecision(action: action, title: title, targetType: decision?.targetType)
        }

        if let fallbackTitle = fallbackTitle(from: conversationHistory) {
            return ScoutAgentDecision(action: action, title: fallbackTitle, targetType: decision?.targetType)
        }

        return nil
    }

    private func fallbackTitle(from conversationHistory: [AIService.ChatMessage]) -> String? {
        let recentUserMessages = conversationHistory.reversed().filter { $0.role == "user" }

        for message in recentUserMessages {
            let candidate = sanitizedTitle(message.content)
            guard let candidate else { continue }
            guard !looksLikeAgentCommand(candidate) else { continue }
            return candidate
        }

        return nil
    }

    private func sanitizedTitle(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        guard !trimmed.isEmpty else { return nil }

        let invalidValues = [
            "none",
            "null",
            "n/a",
            "unknown",
            "not provided",
            "no title",
            "it",
            "that",
            "this",
            "there",
            "here",
            "that one",
            "this one",
            "the one",
            "movie",
            "tv show",
            "show",
            "actor",
            "actress",
            "person",
            "page",
            "details"
        ]
        if invalidValues.contains(trimmed.lowercased()) {
            return nil
        }

        return trimmed
    }

    private func valueForPrefix(_ prefix: String, in lines: [String]) -> String? {
        lines.first(where: { $0.uppercased().hasPrefix(prefix) })?
            .split(separator: ":", maxSplits: 1)
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fallbackPersonName(from query: String) -> String? {
        let words = query.split(separator: " ").map(String.init)
        var current: [String] = []
        var best: [String] = []

        for word in words {
            let trimmed = word.trimmingCharacters(in: CharacterSet.punctuationCharacters)
            guard !trimmed.isEmpty else { continue }

            if trimmed.first?.isUppercase == true {
                current.append(trimmed)
            } else {
                if current.count >= 2 {
                    best = current
                    break
                }
                current.removeAll()
            }
        }

        if best.isEmpty, current.count >= 2 {
            best = current
        }

        return best.isEmpty ? nil : best.joined(separator: " ")
    }

    private func parsePremiseKeywords(_ plotLine: String?, originalQuery: String) -> [String] {
        if let plotLine, !plotLine.isEmpty {
            let parsed = plotLine
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { $0.count >= 3 }
            if !parsed.isEmpty {
                return Array(parsed.prefix(6))
            }
        }

        return Array(keywordSet(from: originalQuery).prefix(6))
    }

    private func parsedAgentQuery(from text: String) -> ParsedAgentQuery {
        let pattern = #"(?i)\bfrom\s+(19|20)\d{2}\b|\b(19|20)\d{2}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return ParsedAgentQuery(cleanedQuery: text, year: nil)
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        var year: Int?
        var cleaned = text

        for match in matches.reversed() {
            guard let range = Range(match.range, in: cleaned) else { continue }
            let matched = String(cleaned[range])
            let digits = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if year == nil, let parsed = Int(String(digits.suffix(4))) {
                year = parsed
            }
            cleaned.removeSubrange(range)
        }

        cleaned = cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))

        return ParsedAgentQuery(cleanedQuery: cleaned.isEmpty ? text : cleaned, year: year)
    }

    private func keywordSet(from text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "that", "one", "movie", "show", "series", "where", "with", "from",
            "stars", "starring", "about", "details", "take", "into", "open",
            "more", "please", "just", "like"
        ]

        return Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !stopWords.contains($0) }
        )
    }

    private func deduplicatedMediaItems(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = "\(item.resolvedMediaType.rawValue)-\(item.id)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func normalizedTitle(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }

    private func filtered(_ items: [MediaItem], for preferredType: MediaType?) -> [MediaItem] {
        guard let preferredType else { return items }
        return items.filter { $0.resolvedMediaType == preferredType }
    }

    private func inferredTargetType(from lowercased: String) -> ScoutAgentTargetType? {
        if lowercased.contains("actor") || lowercased.contains("actress") || lowercased.contains("person") || lowercased.contains("cast") {
            return .person
        }
        if lowercased.contains("tv show") || lowercased.contains("series") {
            return .tv
        }
        if lowercased.contains("movie") || lowercased.contains("film") {
            return .movie
        }
        return nil
    }

    private func inferredEntityType(from text: String) -> ScoutAgentTargetType? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let words = trimmed.split(separator: " ")
        if words.count >= 2 && words.allSatisfy({ $0.first?.isUppercase == true || Int($0) != nil }) {
            return .person
        }

        return nil
    }

    private func explicitCommandTitle(from userMessage: String, targetType: ScoutAgentTargetType?) -> String? {
        var cleaned = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements = [
            "take me to see more details",
            "take me to",
            "show me more details",
            "show me",
            "open details for",
            "open details",
            "open",
            "go to",
            "page",
            "details",
            "actor",
            "actress",
            "person",
            "cast",
            "movie",
            "film",
            "tv show",
            "tv series",
            "series"
        ]

        for phrase in replacements {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: "", options: [.caseInsensitive, .regularExpression])
        }

        cleaned = cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))

        guard let title = sanitizedTitle(cleaned), !(targetType == nil && title.count < 2) else { return nil }
        return title
    }
}
