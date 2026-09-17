//
//  TasteRecommender.swift
//  WatchGuide-MovieandTVtracker
//
//  Personal recommendations powered by GPT-5 Nano (via Poe). The model
//  reads the user's Liked and Watched lists, suggests titles in the same vein,
//  and every suggestion is resolved to a real TMDB entry (matched on title,
//  type and year) with anything already watched or liked filtered out.
//  Feeds both the For You row and the Tonight deck.
//

import Foundation

@MainActor
final class TasteRecommender {
    static let shared = TasteRecommender()

    enum Kind { case any, movies, shows }

    private let modelId = "GPT-5-nano" // Poe bot name

    /// Cache keyed by kind + a taste fingerprint so For You and Tonight don't
    /// hit the model twice for the same lists.
    private var cache: [String: [MediaItem]] = [:]

    private init() {}

    var hasTaste: Bool {
        let s = StorageService.shared
        return !s.liked.isEmpty || !s.watched.isEmpty
    }

    func recommendations(kind: Kind = .any, count: Int = 15, refresh: Bool = false) async -> [MediaItem] {
        let storage = StorageService.shared
        let liked = storage.liked
        let watched = storage.watched
        guard !liked.isEmpty || !watched.isEmpty else { return [] }

        let fingerprint = (liked.prefix(25) + watched.prefix(25)).map(\.id).joined(separator: "|")
        let cacheKey = "\(kind)-\(fingerprint)"
        if !refresh, let cached = cache[cacheKey], !cached.isEmpty {
            return cached.filter { !isKnown($0) }
        }

        var suggestions: [(title: String, type: String, year: Int?)] = []
        do {
            suggestions = try await askModel(liked: liked, watched: watched, kind: kind, count: count)
        } catch {
            print("TasteRecommender: GPT-5 Nano failed — \(error)")
        }

        var resolved = await resolve(suggestions, kind: kind)

        // If the model was unreachable or matched too little, lean on TMDB's own
        // "similar" graph seeded from the same lists rather than generic trending.
        if resolved.count < 6 {
            resolved = dedupe(resolved + (await similarFromTMDB(seeds: liked + watched, kind: kind)))
        }

        cache[cacheKey] = resolved
        return resolved
    }

    // MARK: - Model

    private func askModel(
        liked: [SavedMediaItem],
        watched: [SavedMediaItem],
        kind: Kind,
        count: Int
    ) async throws -> [(title: String, type: String, year: Int?)] {
        let provider = AtlasAIProvider.poe
        let key = provider.apiKey
        guard !key.isEmpty else { throw AIError.noApiKey }

        func line(_ item: SavedMediaItem) -> String {
            let type = item.mediaType == .movie ? "movie" : "tv"
            return "\(item.title) (\(item.year ?? "?"), \(type))"
        }
        let likedList = liked.prefix(30).map(line).joined(separator: "; ")
        // Watched-but-not-liked still signals taste, just more weakly.
        let likedIds = Set(liked.map(\.id))
        let watchedList = watched.filter { !likedIds.contains($0.id) }.prefix(30).map(line).joined(separator: "; ")

        let kindRule: String
        switch kind {
        case .any:    kindRule = "Mix movies and TV shows."
        case .movies: kindRule = "Only movies (type \"movie\")."
        case .shows:  kindRule = "Only TV shows (type \"tv\")."
        }

        let system = """
        You are a film and TV recommendation engine. Study the user's LIKED titles (strong signal) and \
        WATCHED titles (weaker signal): their genres, tone, themes, era, pacing, creators and cast. \
        Recommend \(count) real, released titles that are genuinely similar to what they like — the kind of \
        thing a friend with the same taste would suggest. \(kindRule) \
        Never include any title from either list, and no sequels/spin-offs of them unless clearly a strong fit. \
        Prefer specific matches over generic blockbusters.
        Respond with ONLY a JSON object, no prose, no code fences:
        {"recommendations":[{"title":"Exact Title","type":"movie","year":2019}]}
        "type" is "movie" or "tv". "year" is the release (or first air) year.
        """
        let user = """
        LIKED: \(likedList.isEmpty ? "none" : likedList)
        WATCHED: \(watchedList.isEmpty ? "none" : watchedList)
        """

        let body: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            // GPT-5 Nano is a reasoning model: keep reasoning minimal and leave
            // headroom, otherwise the whole budget goes to thinking and content
            // comes back empty. It also rejects non-default temperature.
            "reasoning_effort": "minimal",
            "max_tokens": 2500,
            "stream": false
        ]

        guard let url = URL(string: provider.baseURL) else { throw AIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

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

    private func parse(_ content: String) -> [(title: String, type: String, year: Int?)] {
        struct Rec: Decodable {
            let title: String
            let type: String?
            let year: YearValue?
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
            return (title, type, rec.year?.value)
        }
    }

    // MARK: - TMDB resolution

    private func resolve(_ suggestions: [(title: String, type: String, year: Int?)], kind: Kind) async -> [MediaItem] {
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

        let ordered = results.sorted { $0.0 < $1.0 }.compactMap(\.1)
        return dedupe(ordered.filter { $0.posterPath != nil && matches(kind, $0) && !isKnown($0) })
    }

    private func similarFromTMDB(seeds: [SavedMediaItem], kind: Kind) async -> [MediaItem] {
        let tmdb = TMDBService.shared
        var out: [MediaItem] = []
        for seed in seeds.prefix(4) {
            let r = seed.mediaType == .tv
                ? try? await tmdb.getSimilarTVShows(id: seed.mediaId)
                : try? await tmdb.getSimilarMovies(id: seed.mediaId)
            out += (r?.results ?? []).prefix(8)
        }
        return dedupe(out.filter { $0.posterPath != nil && matches(kind, $0) && !isKnown($0) })
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
    }

    private func dedupe(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert("\($0.resolvedMediaType.rawValue)-\($0.id)").inserted }
    }
}
