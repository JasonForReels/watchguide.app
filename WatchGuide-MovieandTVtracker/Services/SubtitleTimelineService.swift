//
//  SubtitleTimelineService.swift
//  WatchGuide-MovieandTVtracker
//
//  Watch-Along — fetches timed English subtitles for a movie or episode from
//  OpenSubtitles, parses them into cues, and matches a snippet of dialogue
//  heard through the microphone back to a position in the timeline. The
//  timeline is also the spoiler boundary: Atlas is only ever given cues that
//  end before the viewer's current position.
//

import Foundation

struct SubtitleCue: Hashable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    /// Lower-cased, punctuation-free words used for matching.
    let tokens: [String]
}

struct SubtitleTimeline {
    let cues: [SubtitleCue]

    var duration: TimeInterval { cues.last?.end ?? 0 }

    /// Every cue that has finished by `time` — nothing after it.
    func cues(upTo time: TimeInterval) -> [SubtitleCue] {
        cues.filter { $0.end <= time }
    }

    /// Dialogue up to `time`, newest last, trimmed to roughly `characterBudget`.
    func transcript(upTo time: TimeInterval, characterBudget: Int = 12_000) -> String {
        var lines: [String] = []
        var used = 0
        for cue in cues(upTo: time).reversed() {
            let line = "[\(Self.clock(cue.start))] \(cue.text)"
            if used + line.count > characterBudget { break }
            lines.append(line)
            used += line.count + 1
        }
        return lines.reversed().joined(separator: "\n")
    }

    struct Match {
        /// Position in the title at the moment the matched speech ended.
        let time: TimeInterval
        /// 0...1 share of heard words found in the matched window.
        let confidence: Double
    }

    /// Finds where `heard` best lines up with the subtitle timeline.
    ///
    /// Scores every window of a few consecutive cues by word-bigram overlap
    /// (bigrams keep common words like "I" and "you" from matching everywhere),
    /// breaking ties toward `near` so a re-sync prefers the expected position.
    func match(heard: String, near: TimeInterval? = nil) -> Match? {
        let heardTokens = SubtitleTimelineService.tokenize(heard)
        guard heardTokens.count >= 4 else { return nil }
        let heardBigrams = Set(zip(heardTokens, heardTokens.dropFirst()).map { "\($0) \($1)" })
        guard !heardBigrams.isEmpty else { return nil }

        let window = 4
        var best: (index: Int, score: Double)?
        for i in cues.indices {
            let slice = cues[i..<min(i + window, cues.count)]
            let tokens = slice.flatMap(\.tokens)
            guard tokens.count >= 2 else { continue }
            let bigrams = Set(zip(tokens, tokens.dropFirst()).map { "\($0) \($1)" })
            var score = Double(heardBigrams.intersection(bigrams).count) / Double(heardBigrams.count)
            if let near, abs(cues[i].start - near) < 120 { score += 0.05 }
            if score > (best?.score ?? 0) { best = (i, score) }
        }

        guard let best, best.score >= 0.35 else { return nil }

        // The speech ended in whichever cue holds the most recently heard
        // phrase. Ranking by position in what was heard (not by cue order)
        // stops a repeated phrase in a later line from pulling the clock ahead.
        let slice = cues[best.index..<min(best.index + window, cues.count)]
        let orderedHeard = zip(heardTokens, heardTokens.dropFirst()).map { "\($0) \($1)" }
        var lastSpoken = slice.first!
        var latestHeardIndex = -1
        for cue in slice {
            let cueBigrams = Set(zip(cue.tokens, cue.tokens.dropFirst()).map { "\($0) \($1)" })
            if let index = orderedHeard.lastIndex(where: cueBigrams.contains), index > latestHeardIndex {
                latestHeardIndex = index
                lastSpoken = cue
            }
        }
        return Match(time: lastSpoken.end, confidence: min(best.score, 1))
    }

    static func clock(_ time: TimeInterval) -> String {
        let total = Int(max(time, 0))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

enum SubtitleTimelineError: LocalizedError {
    case missingApiKey
    case noSubtitles
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey: return "Add an OpenSubtitles API key to use Watch-Along."
        case .noSubtitles: return "No English subtitles were found for this title yet."
        case .downloadFailed(let reason): return "Couldn't load subtitles: \(reason)"
        }
    }
}

actor SubtitleTimelineService {
    static let shared = SubtitleTimelineService()
    static let apiKeyName = "OPENSUBTITLES_API_KEY"

    private let baseURL = URL(string: "https://api.opensubtitles.com/api/v1")!
    private var memoryCache: [String: SubtitleTimeline] = [:]

    private init() {}

    static var hasApiKey: Bool {
        !(ApiKeyManager.shared.get(key: apiKeyName) ?? "").isEmpty
    }

    /// Loads the timeline for a movie, or for an episode when `season` and
    /// `episode` are given (`tmdbId` is then the show's id).
    func timeline(tmdbId: Int, season: Int? = nil, episode: Int? = nil) async throws -> SubtitleTimeline {
        let cacheKey = [tmdbId, season ?? -1, episode ?? -1].map(String.init).joined(separator: "_")
        if let cached = memoryCache[cacheKey] { return cached }
        if let data = try? Data(contentsOf: diskURL(for: cacheKey)),
           let srt = String(data: data, encoding: .utf8) {
            let timeline = SubtitleTimeline(cues: Self.parseSRT(srt))
            if !timeline.cues.isEmpty {
                memoryCache[cacheKey] = timeline
                return timeline
            }
        }

        // Shared cache: one user's download serves everyone, keeping us far
        // below the OpenSubtitles daily download quota.
        let sharedKey = "watchalong_srt_\(cacheKey)"
        if let shared = await SupabaseCacheService.shared.get(key: sharedKey, as: SharedSRT.self) {
            let timeline = SubtitleTimeline(cues: Self.parseSRT(shared.srt))
            if !timeline.cues.isEmpty {
                memoryCache[cacheKey] = timeline
                try? shared.srt.data(using: .utf8)?.write(to: diskURL(for: cacheKey))
                return timeline
            }
        }

        guard let apiKey = ApiKeyManager.shared.get(key: Self.apiKeyName), !apiKey.isEmpty else {
            throw SubtitleTimelineError.missingApiKey
        }

        let fileId = try await searchFileId(tmdbId: tmdbId, season: season, episode: episode, apiKey: apiKey)
        let srt = try await download(fileId: fileId, apiKey: apiKey)
        let timeline = SubtitleTimeline(cues: Self.parseSRT(srt))
        guard !timeline.cues.isEmpty else { throw SubtitleTimelineError.noSubtitles }

        memoryCache[cacheKey] = timeline
        try? srt.data(using: .utf8)?.write(to: diskURL(for: cacheKey))
        if let payload = try? JSONEncoder().encode(SharedSRT(srt: srt)) {
            await SupabaseCacheService.shared.set(key: sharedKey, source: .watchalong, responseData: payload, ttlSeconds: 60 * 60 * 24 * 90)
        }
        return timeline
    }

    private struct SharedSRT: Codable { let srt: String }

    // MARK: - OpenSubtitles

    private func request(_ url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("WatchGuide v4", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            struct Attributes: Decodable {
                struct File: Decodable { let file_id: Int }
                let files: [File]
                let download_count: Int?
                let hearing_impaired: Bool?
            }
            let attributes: Attributes
        }
        let data: [Item]
    }

    private func searchFileId(tmdbId: Int, season: Int?, episode: Int?, apiKey: String) async throws -> Int {
        var components = URLComponents(url: baseURL.appendingPathComponent("subtitles"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "languages", value: "en"), URLQueryItem(name: "order_by", value: "download_count")]
        if let season, let episode {
            items += [
                URLQueryItem(name: "parent_tmdb_id", value: String(tmdbId)),
                URLQueryItem(name: "season_number", value: String(season)),
                URLQueryItem(name: "episode_number", value: String(episode)),
            ]
        } else {
            items.append(URLQueryItem(name: "tmdb_id", value: String(tmdbId)))
        }
        // OpenSubtitles answers unsorted query strings with a 301 redirect.
        components.queryItems = items.sorted { $0.name < $1.name }

        let (data, response) = try await URLSession.shared.data(for: request(components.url!, apiKey: apiKey))
        try Self.checkStatus(response, data: data)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)

        // Prefer regular subtitles: hearing-impaired tracks add "[door creaks]"
        // cues that never match what the microphone hears.
        let ranked = decoded.data.sorted { ($0.attributes.hearing_impaired ?? false ? 1 : 0) < ($1.attributes.hearing_impaired ?? false ? 1 : 0) }
        guard let fileId = ranked.first(where: { !$0.attributes.files.isEmpty })?.attributes.files.first?.file_id else {
            throw SubtitleTimelineError.noSubtitles
        }
        return fileId
    }

    private func download(fileId: Int, apiKey: String) async throws -> String {
        var linkRequest = request(baseURL.appendingPathComponent("download"), apiKey: apiKey)
        linkRequest.httpMethod = "POST"
        linkRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        linkRequest.httpBody = try JSONSerialization.data(withJSONObject: ["file_id": fileId, "sub_format": "srt"])

        let (data, response) = try await URLSession.shared.data(for: linkRequest)
        try Self.checkStatus(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let link = json["link"] as? String,
              let url = URL(string: link) else {
            throw SubtitleTimelineError.downloadFailed("no download link")
        }

        let (fileData, fileResponse) = try await URLSession.shared.data(from: url)
        try Self.checkStatus(fileResponse, data: fileData)
        guard let srt = String(data: fileData, encoding: .utf8) ?? String(data: fileData, encoding: .isoLatin1) else {
            throw SubtitleTimelineError.downloadFailed("unreadable file")
        }
        return srt
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw SubtitleTimelineError.missingApiKey
        case 406, 429: throw SubtitleTimelineError.downloadFailed("daily subtitle limit reached")
        default: throw SubtitleTimelineError.downloadFailed("HTTP \(http.statusCode)")
        }
    }

    private func diskURL(for key: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchAlongSubtitles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(key).srt")
    }

    // MARK: - Parsing

    static func parseSRT(_ srt: String) -> [SubtitleCue] {
        let normalized = srt.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1]) else { continue }
            let text = lines[(timingIndex + 1)...]
                .joined(separator: " ")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\{[^}]+\\}", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: text, tokens: tokenize(text)))
        }
        return cues.sorted { $0.start < $1.start }
    }

    private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        // 00:01:02,345 (optionally with trailing position info)
        let trimmed = raw.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
        let pieces = trimmed.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard pieces.count == 3,
              let h = Double(pieces[0]), let m = Double(pieces[1]), let s = Double(pieces[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\\[[^\\]]*\\]|\\([^)]*\\)", with: " ", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
