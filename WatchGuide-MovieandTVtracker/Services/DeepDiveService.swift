//
//  DeepDiveService.swift
//  WatchGuide-MovieandTVtracker
//
//  Generates Deep Dive content with Atlas and shares it across users through
//  the Supabase cache, so each title is only generated once.
//

import Foundation

enum DeepDiveError: LocalizedError {
    case aiUnavailable
    case quotaReached
    case unreadableResponse

    var errorDescription: String? {
        switch self {
        case .aiUnavailable: return "Atlas AI isn’t configured. Add your API key in Settings."
        case .quotaReached: return "You’ve used this month’s Deep Dives."
        case .unreadableResponse: return "Atlas couldn’t put this together. Please try again."
        }
    }
}

@MainActor
final class DeepDiveService {
    static let shared = DeepDiveService()

    /// Content about a finished film rarely changes; keep it for 30 days.
    private let ttlSeconds = 2_592_000
    private var memoryCache: [String: Data] = [:]

    private init() {}

    // MARK: - Public

    func safeContent(for context: DeepDiveContext) async throws -> DeepDiveSafeContent {
        try await load(key: cacheKey("safe", context), context: context, prompt: safePrompt(context))
    }

    func spoilerContent(for context: DeepDiveContext) async throws -> DeepDiveSpoilerContent {
        try await load(key: cacheKey("spoiler", context), context: context, prompt: spoilerPrompt(context))
    }

    // MARK: - Loading

    private func cacheKey(_ part: String, _ context: DeepDiveContext) -> String {
        "deepdive:v1:\(context.mediaType.rawValue):\(context.tmdbId):\(part)"
    }

    private func load<T: Decodable>(key: String, context: DeepDiveContext, prompt: String) async throws -> T {
        if let data = memoryCache[key], let value = try? JSONDecoder().decode(T.self, from: data) {
            return value
        }
        // Cached results are free to read — only fresh generations use quota.
        if let data = await SupabaseCacheService.shared.get(key: key),
           let value = try? JSONDecoder().decode(T.self, from: data) {
            memoryCache[key] = data
            return value
        }

        guard await AIService.shared.isAvailable else { throw DeepDiveError.aiUnavailable }
        guard AIMessageQuota.canUseDeepDiveThisMonth() else { throw DeepDiveError.quotaReached }

        let (response, _) = try await AIService.shared.sendMessage(
            prompt,
            conversationHistory: [],
            likedItems: [],
            webSearchEnabled: true,
            model: .geminiFlashLite,
            restrictedMode: false
        )

        guard let data = Self.extractJSON(from: response),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw DeepDiveError.unreadableResponse
        }

        AIMessageQuota.consumeDeepDive()
        memoryCache[key] = data
        await SupabaseCacheService.shared.set(key: key, source: .deepdive, responseData: data, ttlSeconds: ttlSeconds)
        return value
    }

    /// Models often wrap JSON in prose or ``` fences; take the outermost object.
    nonisolated static func extractJSON(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(text[start...end]).data(using: .utf8)
    }

    // MARK: - Prompts

    private func header(_ context: DeepDiveContext) -> String {
        var lines = ["Title: \(context.title)\(context.year.map { " (\($0))" } ?? "")",
                     "Type: \(context.mediaType == .tv ? "TV series" : "Film")"]
        if !context.keyCrewSummary.isEmpty { lines.append("Verified crew (from TMDB):\n\(context.keyCrewSummary)") }
        if let budget = context.budget { lines.append("Budget: \(budget)") }
        if let revenue = context.revenue { lines.append("Box office: \(revenue)") }
        if let source = context.adaptationKeyword { lines.append("TMDB tag: \(source)") }
        return lines.joined(separator: "\n")
    }

    private let rules = """
    Rules: use the verified crew names above instead of guessing. Write in your own words; never quote \
    reviews or articles. If you're unsure of a fact, leave it out. Reply with ONLY a JSON object, no other text.
    """

    private func safePrompt(_ context: DeepDiveContext) -> String {
        """
        \(header(context))

        Write a spoiler-free deep dive into how this was made. Do not reveal any plot beyond the premise.
        - "craft": 4 notes, one each for cinematography, music/score, editing and production design. \
        "person" is who was responsible (or null). "note" is 1–2 sentences on a specific technique or choice.
        - "making": 4–6 events in order from development to release (casting, shoot, reshoots, release, \
        budget vs box office). "when" is a year or short date (or null). "detail" is 1–2 sentences.

        \(rules)
        Format: {"craft":[{"area":"","person":"","note":""}],"making":[{"phase":"","when":"","detail":""}]}
        """
    }

    private func spoilerPrompt(_ context: DeepDiveContext) -> String {
        """
        \(header(context))

        The viewer has finished this and wants spoilers.
        - "source": the original work it's adapted from, e.g. "Novel by Frank Herbert", or null if it isn't an adaptation.
        - "adaptation": if adapted, 3–5 notable changes from the source, each with a short "why" (or null). Empty array otherwise.
        - "endingQuick": what happens at the end, in 1–2 sentences.
        - "endingFull": a clear explanation of the ending and anything ambiguous, 2 short paragraphs.
        - "endingThemes": what the ending means thematically, plus any widely discussed interpretations, 1–2 short paragraphs.
        \(context.mediaType == .tv ? "For a series, explain the ending of the most recent season." : "")

        \(rules)
        Format: {"source":null,"adaptation":[{"change":"","why":""}],"endingQuick":"","endingFull":"","endingThemes":""}
        """
    }
}
