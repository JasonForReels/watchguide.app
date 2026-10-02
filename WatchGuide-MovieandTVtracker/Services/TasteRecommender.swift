//
//  TasteRecommender.swift
//  WatchGuide-MovieandTVtracker
//
//  Personal recommendations from the user's Liked and Watched lists. Apple's
//  models come first so taste stays private: Private Cloud Compute on iOS 27,
//  then the on-device model, and only then GPT-5 Nano (via Poe) as a fallback.
//  Every suggestion is resolved to a real TMDB entry (matched on title, type
//  and year) and carries a short "Because you loved …" reason.
//
//  Results are cached on disk, so For You and Tonight can show last session's
//  picks instantly while fresh ones generate. Titles the user skips on Tonight
//  are remembered, filtered out everywhere and fed back as a negative signal.
//  Feeds both the For You row and the Tonight deck.
//

import Foundation
#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

// MARK: - Apple model output schema

#if canImport(FoundationModels) && !os(tvOS)
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A movie or TV show the user would enjoy")
struct TastePick {
    @Guide(description: "The exact title of a real, released movie or TV show")
    var title: String

    @Guide(description: "Either \"movie\" or \"tv\"")
    var type: String

    @Guide(description: "Release year, or first air year for TV")
    var year: Int

    @Guide(description: "Under 50 characters, naming one LIKED title it resembles, e.g. \"Because you loved Dark\"")
    var reason: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Personal recommendations")
struct TastePickList {
    @Guide(description: "Recommended titles, best match first")
    var picks: [TastePick]
}
#endif

@MainActor
final class TasteRecommender {
    static let shared = TasteRecommender()

    enum Kind: String, Codable { case any, movies, shows }

    private typealias Suggestion = (title: String, type: String, year: Int?, reason: String?)

    private let modelId = "GPT-5-nano" // Poe bot name
    /// Picks older than this are regenerated, even if the lists haven't changed.
    private let freshness: TimeInterval = 24 * 60 * 60

    private struct CacheEntry: Codable {
        let fingerprint: String
        let createdAt: Date
        let items: [MediaItem]
    }

    private struct Persisted: Codable {
        var entries: [Kind: CacheEntry]
        var reasons: [String: String]
    }

    private struct Skip: Codable {
        let key: String
        let title: String
    }

    private var entries: [Kind: CacheEntry] = [:]
    private var reasons: [String: String] = [:]
    private var skips: [Skip] = []
    /// One generation per kind at a time, so For You and Tonight share a request.
    private var inFlight: [Kind: Task<[MediaItem], Never>] = [:]

    private let skipsKey = "wg.taste.skipped.v1"
    private let maxSkips = 300

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TasteRecommender.json")
    }

    private init() {
        if let url = cacheURL, let data = try? Data(contentsOf: url),
           let persisted = try? JSONDecoder().decode(Persisted.self, from: data) {
            entries = persisted.entries
            reasons = persisted.reasons
        }
        if let data = UserDefaults.standard.data(forKey: skipsKey),
           let decoded = try? JSONDecoder().decode([Skip].self, from: data) {
            skips = decoded
        }
    }

    var hasTaste: Bool {
        let s = StorageService.shared
        return !s.liked.isEmpty || !s.watched.isEmpty
    }

    // MARK: - Public

    /// Last generated picks, available immediately. May be from an earlier
    /// session; call `recommendations` to refresh.
    func cached(kind: Kind = .any) -> [MediaItem] {
        (entries[kind]?.items ?? []).filter { !isKnown($0) }
    }

    func recommendations(kind: Kind = .any, count: Int = 15, refresh: Bool = false) async -> [MediaItem] {
        let storage = StorageService.shared
        guard !storage.liked.isEmpty || !storage.watched.isEmpty else { return [] }

        let fingerprint = currentFingerprint
        if !refresh, let entry = entries[kind], entry.fingerprint == fingerprint,
           Date().timeIntervalSince(entry.createdAt) < freshness {
            let fresh = entry.items.filter { !isKnown($0) }
            if fresh.count >= 6 { return fresh }
        }

        if let running = inFlight[kind] { return await running.value }
        let task = Task { await generate(kind: kind, count: count, fingerprint: fingerprint) }
        inFlight[kind] = task
        let result = await task.value
        inFlight[kind] = nil
        return result
    }

    /// Why a title was picked, e.g. "Because you loved Dark".
    func reason(for item: MediaItem) -> String? {
        reasons[key(item)]
    }

    func noteSkipped(_ item: MediaItem) {
        let k = key(item)
        guard !skips.contains(where: { $0.key == k }) else { return }
        skips.insert(Skip(key: k, title: item.displayTitle), at: 0)
        if skips.count > maxSkips { skips.removeLast(skips.count - maxSkips) }
        persistSkips()
    }

    func unnoteSkipped(_ item: MediaItem) {
        let k = key(item)
        skips.removeAll { $0.key == k }
        persistSkips()
    }

    func isSkipped(_ item: MediaItem) -> Bool {
        let k = key(item)
        return skips.contains { $0.key == k }
    }

    // MARK: - Generation

    private var currentFingerprint: String {
        let s = StorageService.shared
        return (s.liked.prefix(25) + s.watched.prefix(25)).map(\.id).joined(separator: "|")
    }

    private func generate(kind: Kind, count: Int, fingerprint: String) async -> [MediaItem] {
        let storage = StorageService.shared
        let liked = storage.liked
        let watched = storage.watched
        let passed = skips.prefix(20).map(\.title)

        let suggestions = await suggest(liked: liked, watched: watched, passed: passed, kind: kind, count: count)
        var resolved = await resolve(suggestions, kind: kind)

        // If no model was reachable or too little matched, lean on TMDB's own
        // "similar" graph seeded from the same lists rather than generic trending.
        if resolved.count < 6 {
            resolved = dedupe(resolved + (await similarFromTMDB(seeds: liked + watched, kind: kind)))
        }

        if !resolved.isEmpty {
            entries[kind] = CacheEntry(fingerprint: fingerprint, createdAt: Date(), items: resolved)
            persistCache()
        }
        return resolved
    }

    private func suggest(
        liked: [SavedMediaItem],
        watched: [SavedMediaItem],
        passed: [String],
        kind: Kind,
        count: Int
    ) async -> [Suggestion] {
        #if canImport(FoundationModels) && !os(tvOS)
        if StorageService.shared.settings.useAppleIntelligenceSearch {
            if #available(iOS 27.0, macOS 27.0, *) {
                let pcc = PrivateCloudComputeLanguageModel()
                if pcc.isAvailable {
                    let prompt = prompt(liked: liked, watched: watched, passed: passed, limit: 30)
                    let session = LanguageModelSession(model: pcc, instructions: instructions(kind: kind, count: count))
                    if let picks = try? await respond(session, prompt: prompt), !picks.isEmpty { return picks }
                }
            }
            if #available(iOS 26.0, macOS 26.0, *) {
                let local = SystemLanguageModel.default
                if case .available = local.availability, local.supportsLocale(Locale.current) {
                    // The on-device model has a small context window: send less.
                    let prompt = prompt(liked: liked, watched: watched, passed: passed, limit: 12)
                    let session = LanguageModelSession(model: local, instructions: instructions(kind: kind, count: min(count, 10)))
                    if let picks = try? await respond(session, prompt: prompt), !picks.isEmpty { return picks }
                }
            }
        }
        #endif

        do {
            return try await askPoe(liked: liked, watched: watched, passed: passed, kind: kind, count: count)
        } catch {
            print("TasteRecommender: GPT-5 Nano failed — \(error)")
            return []
        }
    }

    #if canImport(FoundationModels) && !os(tvOS)
    @available(iOS 26.0, macOS 26.0, *)
    private func respond(_ session: LanguageModelSession, prompt: String) async throws -> [Suggestion] {
        // Constrained sampling: the model must emit a valid TastePickList.
        let response = try await session.respond(to: prompt, generating: TastePickList.self)
        return response.content.picks.compactMap { pick in
            let title = pick.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let type = pick.type.lowercased().hasPrefix("tv") ? "tv" : "movie"
            let reason = pick.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, type, pick.year > 1800 ? pick.year : nil, reason.isEmpty ? nil : reason)
        }
    }
    #endif

    private func instructions(kind: Kind, count: Int) -> String {
        let kindRule: String
        switch kind {
        case .any:    kindRule = "Mix movies and TV shows."
        case .movies: kindRule = "Only movies (type \"movie\")."
        case .shows:  kindRule = "Only TV shows (type \"tv\")."
        }
        return """
        You are a film and TV recommendation engine. Study the user's LIKED titles (strong signal) and \
        WATCHED titles (weaker signal): their genres, tone, themes, era, pacing, creators and cast. \
        PASSED titles were shown and rejected: avoid them and anything too close to them. \
        Recommend \(count) real, released titles that are genuinely similar to what they like — the kind of \
        thing a friend with the same taste would suggest. \(kindRule) \
        Never include any title from the lists, and no sequels/spin-offs of them unless clearly a strong fit. \
        Prefer specific matches over generic blockbusters. \
        Give each pick a short reason that names the one LIKED (or WATCHED) title it most resembles, \
        e.g. "Because you loved Dark".
        """
    }

    private func prompt(liked: [SavedMediaItem], watched: [SavedMediaItem], passed: [String], limit: Int) -> String {
        func line(_ item: SavedMediaItem) -> String {
            let type = item.mediaType == .movie ? "movie" : "tv"
            return "\(item.title) (\(item.year ?? "?"), \(type))"
        }
        let likedList = liked.prefix(limit).map(line).joined(separator: "; ")
        // Watched-but-not-liked still signals taste, just more weakly.
        let likedIds = Set(liked.map(\.id))
        let watchedList = watched.filter { !likedIds.contains($0.id) }.prefix(limit).map(line).joined(separator: "; ")
        let passedList = passed.prefix(limit).joined(separator: "; ")
        return """
        LIKED: \(likedList.isEmpty ? "none" : likedList)
        WATCHED: \(watchedList.isEmpty ? "none" : watchedList)
        PASSED: \(passedList.isEmpty ? "none" : passedList)
        """
    }

    // MARK: - Poe fallback

    private func askPoe(
        liked: [SavedMediaItem],
        watched: [SavedMediaItem],
        passed: [String],
        kind: Kind,
        count: Int
    ) async throws -> [Suggestion] {
        let provider = AtlasAIProvider.poe
        let key = provider.apiKey
        guard !key.isEmpty else { throw AIError.noApiKey }

        let system = instructions(kind: kind, count: count) + """

        Respond with ONLY a JSON object, no prose, no code fences:
        {"recommendations":[{"title":"Exact Title","type":"movie","year":2019,"reason":"Because you loved Dark"}]}
        "type" is "movie" or "tv". "year" is the release (or first air) year.
        """

        let body: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt(liked: liked, watched: watched, passed: passed, limit: 30)]
            ],
            // GPT-5 Nano is a reasoning model: keep reasoning minimal and leave
            // headroom, otherwise the whole budget goes to thinking and content
            // comes back empty. It also rejects non-default temperature.
            "reasoning_effort": "minimal",
            "max_tokens": 3000,
            "stream": false
        ]

        guard let url = URL(string: provider.baseURL) else { throw AIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 25

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            print("TasteRecommender HTTP \(http.statusCode): \(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
            throw AIError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(LLMResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw AIError.noContent
        }
        return parse(content)
    }

    private func parse(_ content: String) -> [Suggestion] {
        struct Rec: Decodable {
            let title: String
            let type: String?
            let year: YearValue?
            let reason: String?
        }
        // Models sometimes send the year as a string.
        enum YearValue: Decodable {
            case int(Int)
            init(from decoder: Decoder) throws {
                if let i = try? Int(from: decoder) { self = .int(i); return }
                let s = try String(from: decoder)
                guard let i = Int(s.prefix(4)) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "year"))
                }
                self = .int(i)
            }
            var value: Int { if case .int(let i) = self { return i }; return 0 }
        }
        struct Wrapper: Decodable { let recommendations: [Rec] }

        var text = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var recs: [Rec] = []
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
           let data = String(text[start...end]).data(using: .utf8),
           let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data) {
            recs = wrapper.recommendations
        } else if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]") {
            text = String(text[start...end])
            recs = (try? JSONDecoder().decode([Rec].self, from: Data(text.utf8))) ?? []
        }

        return recs.compactMap { rec in
            let title = rec.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let type = (rec.type ?? "movie").lowercased().hasPrefix("tv") ? "tv" : "movie"
            let reason = rec.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, type, rec.year?.value, reason?.isEmpty == false ? reason : nil)
        }
    }

    // MARK: - TMDB resolution

    private func resolve(_ suggestions: [Suggestion], kind: Kind) async -> [MediaItem] {
        let tmdb = TMDBService.shared
        let results = await withTaskGroup(of: (Int, MediaItem?).self) { group in
            for (index, s) in suggestions.enumerated() {
                group.addTask {
                    let isTV = s.type == "tv"
                    func search(year: Int?) async -> [MediaItem] {
                        let r = isTV
                            ? try? await tmdb.searchTV(query: s.title, year: year)
                            : try? await tmdb.searchMovies(query: s.title, year: year)
                        return r?.results ?? []
                    }
                    var candidates = await search(year: s.year)
                    if candidates.isEmpty, s.year != nil { candidates = await search(year: nil) }
                    let normalized = s.title.lowercased()
                    // Prefer an exact title match, then closest year, then first hit.
                    let best = candidates.first { $0.displayTitle.lowercased() == normalized
                        && (s.year == nil || Int($0.year ?? "") == s.year) }
                        ?? candidates.first { $0.displayTitle.lowercased() == normalized }
                        ?? candidates.first
                    return (index, best)
                }
            }
            var out: [(Int, MediaItem?)] = []
            for await r in group { out.append(r) }
            return out
        }

        let ordered = results.sorted { $0.0 < $1.0 }
        for (index, item) in ordered {
            if let item, let reason = suggestions[index].reason { reasons[key(item)] = reason }
        }
        return dedupe(ordered.compactMap(\.1).filter { $0.posterPath != nil && matches(kind, $0) && !isKnown($0) })
    }

    private func similarFromTMDB(seeds: [SavedMediaItem], kind: Kind) async -> [MediaItem] {
        let tmdb = TMDBService.shared
        let batches = await withTaskGroup(of: (Int, SavedMediaItem, [MediaItem]).self) { group in
            for (index, seed) in seeds.prefix(4).enumerated() {
                group.addTask {
                    let r = seed.mediaType == .tv
                        ? try? await tmdb.getSimilarTVShows(id: seed.mediaId)
                        : try? await tmdb.getSimilarMovies(id: seed.mediaId)
                    return (index, seed, Array((r?.results ?? []).prefix(8)))
                }
            }
            var out: [(Int, SavedMediaItem, [MediaItem])] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }
        }

        var out: [MediaItem] = []
        for (_, seed, items) in batches {
            for item in items where reasons[key(item)] == nil {
                reasons[key(item)] = "Because you liked \(seed.title)"
            }
            out += items
        }
        return dedupe(out.filter { $0.posterPath != nil && matches(kind, $0) && !isKnown($0) })
    }

    // MARK: - Helpers

    private func key(_ item: MediaItem) -> String {
        "\(item.resolvedMediaType.rawValue)-\(item.id)"
    }

    private func matches(_ kind: Kind, _ item: MediaItem) -> Bool {
        switch kind {
        case .any:    return item.resolvedMediaType != .person
        case .movies: return item.resolvedMediaType == .movie
        case .shows:  return item.resolvedMediaType == .tv
        }
    }

    private func isKnown(_ item: MediaItem) -> Bool {
        let s = StorageService.shared
        return s.isInWatched(item.id, mediaType: item.resolvedMediaType)
            || s.isInLiked(item.id, mediaType: item.resolvedMediaType)
            || isSkipped(item)
    }

    private func dedupe(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert(key($0)).inserted }
    }

    private func persistCache() {
        guard let url = cacheURL else { return }
        // Keep reasons only for titles that are still cached.
        let live = Set(entries.values.flatMap(\.items).map(key))
        reasons = reasons.filter { live.contains($0.key) }
        let persisted = Persisted(entries: entries, reasons: reasons)
        if let data = try? JSONEncoder().encode(persisted) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func persistSkips() {
        if let data = try? JSONEncoder().encode(skips) {
            UserDefaults.standard.set(data, forKey: skipsKey)
        }
    }
}
