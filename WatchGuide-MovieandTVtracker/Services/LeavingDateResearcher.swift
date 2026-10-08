//
//  LeavingDateResearcher.swift
//  WatchGuide-MovieandTVtracker
//
//  Finds what is leaving each streaming service over the next two months by
//  asking Poe's gpt-5.4-nano with web search (same bot and API as Reelmeter's
//  box office updater). One request covers a whole service in one region, and
//  the answer is cached in Supabase, so cost scales with services × regions
//  rather than with users or watchlist size. Titles are then matched locally.
//
//  A daily GitHub Actions job (scripts/leaving/update.mjs) refreshes each list
//  about once a month for the main services and countries, with MOTN's
//  expiring titles as the backup when Poe fails or finds nothing, so the app
//  usually just reads the cache. The prompt here mirrors that script; keep them in sync.
//

import Foundation

actor LeavingDateResearcher {
    static let shared = LeavingDateResearcher()

    /// A title's announced departure from one service.
    struct Departure: Codable, Hashable {
        let providerId: Int
        let date: Date
    }

    /// One title from a service's leaving list. Entries from MOTN (via the
    /// monthly job) also carry a TMDB id and type ("movie" or "tv").
    private struct Listing: Codable, Hashable {
        let title: String
        let year: Int?
        let date: Date
        var tmdbId: Int? = nil
        var type: String? = nil
    }

    private struct CachedCatalog: Codable {
        let listings: [Listing]
    }

    /// Researched catalogs keyed like the Supabase cache.
    private var memory: [String: [Listing]] = [:]
    /// Catalogs being researched right now, so concurrent scans share one request.
    private var inFlight: [String: Task<[Listing]?, Never>] = [:]

    /// How far ahead to ask about.
    static let lookaheadDays = 60
    /// Leaving lists are published weeks ahead and rarely change.
    private let cacheTTL = 3 * 86400
    /// The bot sometimes misses a list that exists, so empty answers are retried sooner.
    private let emptyCacheTTL = 12 * 3600
    private let bot = "gpt-5.4-nano"
    private let endpoint = URL(string: "https://api.poe.com/v1/responses")!

    // MARK: - Public API

    /// Departures for each title (keyed by `SavedMediaItem.id`) from the given
    /// services. Services whose list couldn't be fetched are in `failed`, so the
    /// caller can keep what it knew about them.
    func departures(
        for items: [SavedMediaItem],
        providerIds: Set<Int>,
        region: String
    ) async -> (departures: [String: [Departure]], failed: Set<Int>) {
        let country = region.lowercased()
        var results: [String: [Departure]] = [:]
        var failed: Set<Int> = []

        let index = Dictionary(grouping: items) { Self.normalize($0.title) }
        let byTMDB = Dictionary(grouping: items) { "\($0.mediaType == .movie ? "movie" : "tv"):\($0.mediaId)" }

        for providerId in providerIds.sorted() {
            guard let listings = await catalog(providerId: providerId, country: country) else {
                failed.insert(providerId)
                continue
            }
            for listing in listings {
                let matches: [SavedMediaItem]
                if let tmdbId = listing.tmdbId, let type = listing.type {
                    matches = byTMDB["\(type):\(tmdbId)"] ?? []
                } else {
                    matches = (index[Self.normalize(listing.title)] ?? []).filter { Self.yearsMatch($0, listing) }
                }
                for item in matches {
                    results[item.id, default: []].append(Departure(providerId: providerId, date: listing.date))
                }
            }
        }

        return (results, failed)
    }

    // MARK: - Catalog cache

    private func catalog(providerId: Int, country: String) async -> [Listing]? {
        let key = "leaving:catalog:\(providerId):\(country)"
        if let cached = memory[key] { return cached }
        if let shared = await SupabaseCacheService.shared.get(key: key, as: CachedCatalog.self, decoder: Self.decoder) {
            memory[key] = shared.listings
            return shared.listings
        }
        if let running = inFlight[key] { return await running.value }

        let task = Task { await self.research(providerId: providerId, country: country) }
        inFlight[key] = task
        let listings = await task.value
        inFlight[key] = nil

        if let listings {
            memory[key] = listings
            store(listings, key: key)
        }
        return listings
    }

    // MARK: - Poe research

    /// Asks Poe for one service's leaving list. Returns nil when the request
    /// fails, so nothing gets cached and the service is retried next scan.
    private func research(providerId: Int, country: String) async -> [Listing]? {
        let key = AtlasAIProvider.poe.apiKey
        guard !key.isEmpty,
              let service = StreamingService.allServices.first(where: { $0.id == providerId }) else { return nil }

        let now = Date()
        let until = Calendar.current.date(byAdding: .day, value: Self.lookaheadDays, to: now) ?? now
        let today = Self.dayFormatter.string(from: now)
        let end = Self.dayFormatter.string(from: until)
        let months = Self.monthNames(from: now, to: until)
        let regionName = Locale(identifier: "en_US").localizedString(forRegionCode: country.uppercased()) ?? country.uppercased()

        let name = Self.searchName(for: service)
        let isUS = country == "us"
        let place = isUS ? "" : " \(regionName)"
        let searches = months.map { "\"leaving \(name)\(place) \($0)\"" }.joined(separator: ", ")
        // leavingsoon.com only covers the US, so other regions don't get pointed at it.
        let sources = (isUS ? "leavingsoon.com, " : "") + "What's on Netflix, JustWatch, Decider, Tom's Guide"
        // Like Reelmeter's chart pages: name the exact pages to read, or the bot
        // often stops after one search and returns an empty list.
        let pages = Self.leavingPages(providerId: providerId, country: country, from: now, to: until)
        let pageLine = pages.isEmpty ? "" : "Open these pages first and read every date on them: \(pages.joined(separator: " ")).\n"

        // Same shape as Reelmeter's prompts: the rules in the instructions, the task
        // and the exact JSON shape in the input. Otherwise the bot answers in prose.
        let instructions = """
        You are a streaming catalog data extractor. Search the web and report only titles with a \
        specific last day stated on the page. Never estimate or guess. \
        Respond with a single JSON object and nothing else.
        """
        let input = """
        Today is \(today). List every movie and TV show scheduled to leave \(name) in \(regionName) \
        between \(today) and \(end).
        \(pageLine)Also search \(searches). Good sources: \(sources), \(name)'s own announcements \
        for \(regionName).
        \(isUS ? "" : "Only use lists specifically for \(regionName). Catalogs differ by country: US lists, including Netflix's Tudum article, are wrong for \(regionName).")
        An empty list is fine.

        Return exactly this JSON shape:
        {"leaving":[{"title":"Inception","year":2010,"date":"2026-11-01"}]}
        "title" is the title only, without season info. "year" is the release year, or null if unknown. \
        "date" is the last day it is available, as YYYY-MM-DD.
        """

        let body: [String: Any] = [
            "model": bot,
            "instructions": instructions,
            "input": input,
            "tools": [["type": "web_search_preview"]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        // Searching bots can take a while.
        request.timeoutInterval = 180

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                print("LeavingDateResearcher HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) for \(service.name)")
                return nil
            }
            guard let text = Self.responsesText(data), !text.isEmpty else { return nil }
            return parse(text, until: until)
        } catch {
            print("LeavingDateResearcher error for \(service.name): \(error)")
            return nil
        }
    }

    private func parse(_ content: String, until: Date) -> [Listing]? {
        struct Row: Decodable {
            let title: String
            let year: Int?
            let date: String
        }
        struct Wrapper: Decodable { let leaving: [Row] }

        let cleaned = content.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"),
              let wrapper = try? JSONDecoder().decode(Wrapper.self, from: Data(cleaned[start...end].utf8)) else {
            return nil
        }

        let now = Date()
        var listings: Set<Listing> = []
        for row in wrapper.leaving {
            guard !row.title.isEmpty,
                  let date = Self.dayFormatter.date(from: String(row.date.prefix(10))) else { continue }
            // The listed date is the last day available — treat it as end of day.
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: date) ?? date
            guard endOfDay > now, endOfDay <= until.addingTimeInterval(86400) else { continue }
            listings.insert(Listing(title: row.title, year: row.year, date: endOfDay))
        }
        return listings.sorted { $0.date < $1.date }
    }

    // MARK: - Helpers

    /// The answer's text from a Responses API result.
    private static func responsesText(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let text = json["output_text"] as? String { return text }
        let output = json["output"] as? [[String: Any]] ?? []
        return output
            .filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .filter { $0["type"] as? String == "output_text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
    }

    private func store(_ listings: [Listing], key: String) {
        guard let data = try? Self.encoder.encode(CachedCatalog(listings: listings)) else { return }
        let ttl = listings.isEmpty ? emptyCacheTTL : cacheTTL
        Task.detached {
            await SupabaseCacheService.shared.set(key: key, source: .deeplink, responseData: data, ttlSeconds: ttl)
        }
    }

    /// Lowercased, accent-free, alphanumerics only, without a leading article,
    /// so "The Office (U.S.)" and "Office (US)" compare equal.
    private static func normalize(_ title: String) -> String {
        var s = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        s = s.replacingOccurrences(of: "&", with: "and")
        s = String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " })
        for article in ["the ", "a ", "an "] where s.hasPrefix(article) {
            s.removeFirst(article.count)
            break
        }
        return s.replacingOccurrences(of: " ", with: "")
    }

    /// Same year, give or take one (festival vs release dates). Unknown years match.
    private static func yearsMatch(_ item: SavedMediaItem, _ listing: Listing) -> Bool {
        guard let listed = listing.year, let saved = item.year.flatMap({ Int($0.prefix(4)) }) else { return true }
        return abs(listed - saved) <= 1
    }

    /// The name leaving lists use. Max went back to "HBO Max" in 2025.
    private static func searchName(for service: StreamingService) -> String {
        service.id == 384 ? "HBO Max" : service.name
    }

    /// Pages that list departures with dates, for the services and regions they cover.
    /// leavingsoon.com has monthly archives for four US services; netflix-soon.pages.dev
    /// has Netflix leaving calendars for five countries.
    private static func leavingPages(providerId: Int, country: String, from start: Date, to end: Date) -> [String] {
        var pages: [String] = []
        let slugs = [8: "netflix", 384: "max", 15: "hulu", 386: "peacock"]
        if country == "us", let slug = slugs[providerId] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy/MMMM"
            pages += monthDates(from: start, to: end).map {
                "https://leavingsoon.com/\(slug)/archive/\(formatter.string(from: $0).lowercased())"
            }
        }
        if providerId == 8, ["us", "gb", "ca", "jp", "kr"].contains(country) {
            pages.append("https://netflix-soon.pages.dev/\(country)/")
        }
        return pages
    }

    /// One date in each calendar month from `start` through `end`.
    private static func monthDates(from start: Date, to end: Date) -> [Date] {
        let calendar = Calendar.current
        var dates: [Date] = []
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        while cursor <= end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    private static func monthNames(from start: Date, to end: Date) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return monthDates(from: start, to: end).map { formatter.string(from: $0) }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
