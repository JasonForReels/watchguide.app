import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

actor AppleIntelligenceSearchService {
    static let shared = AppleIntelligenceSearchService()

    private init() {}

    func candidateQueries(for query: String) async -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        var candidates: [String] = []
        let optimized = await optimizedQuery(for: trimmedQuery)
        candidates.append(optimized)

        let heuristic = heuristicQuery(from: trimmedQuery)
        if !heuristic.isEmpty {
            candidates.append(heuristic)
        }

        candidates.append(trimmedQuery)
        return uniqueQueries(candidates)
    }

    func optimizedQuery(for query: String) async -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return query }

        #if canImport(FoundationModels)
        if #available(iOS 18.0, macOS 15.0, *) {
            do {
                let instructions = """
                Rewrite movie and TV search requests into a short TMDB-style query.
                Keep only title-like keywords, names, genres, years, and moods.
                Return plain text only, with no explanation.
                """

                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: trimmedQuery)
                let optimized = response.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")

                if !optimized.isEmpty {
                    return optimized
                }
            } catch {
                return trimmedQuery
            }
        }
        #endif

        return trimmedQuery
    }

    private func heuristicQuery(from query: String) -> String {
        let lowercased = query.lowercased()
        let fillerPhrases = [
            "give me", "show me", "find me", "i want", "please", "something",
            "movies", "movie", "tv shows", "tv show", "series", "starring", "with"
        ]

        var cleaned = lowercased
        for phrase in fillerPhrases {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: " ")
        }

        let tokens = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }

        let stopWords: Set<String> = [
            "the", "and", "for", "that", "this", "from", "into", "about", "like",
            "please", "want", "need", "can", "you", "me", "my", "some", "any"
        ]

        let filtered = tokens.filter { !stopWords.contains($0) }
        return filtered.prefix(6).joined(separator: " ")
    }

    private func uniqueQueries(_ queries: [String]) -> [String] {
        var seen: Set<String> = []
        var unique: [String] = []

        for query in queries {
            let normalized = query
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty else { continue }
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            unique.append(query.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return unique
    }
}
