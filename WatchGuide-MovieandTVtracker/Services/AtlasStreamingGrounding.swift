//
//  AtlasStreamingGrounding.swift
//  WatchGuide-MovieandTVtracker
//
//  "Where is Lanterns streaming?" is a question about *right now*, and a model's
//  training data is the one source guaranteed to be out of date on it — which is
//  how Atlas ended up reporting a show as still in development. Availability is
//  also the one thing this app already knows authoritatively, from the same TMDB
//  watch-provider data the detail screens draw on.
//
//  So availability questions get grounded before they reach the model: pull the
//  title out of the question, look it up on TMDB, and hand the model the real
//  providers for the user's own region as context it is told to trust over its
//  own memory. Anything that isn't an availability question is left alone.
//

import Foundation

enum AtlasStreamingGrounding {

    // MARK: - Detection

    /// True when the message is asking where something can be watched. Kept
    /// separate from the extraction so routing can ask cheaply.
    static func isAvailabilityQuestion(_ message: String) -> Bool {
        extractTitle(from: message) != nil
    }

    // MARK: - Context

    /// A block of real TMDB availability for the title in `message`, or nil when
    /// the message isn't an availability question. Never throws: grounding is an
    /// improvement on the answer, not a precondition for it, so a TMDB failure
    /// just means the model answers the way it would have anyway.
    static func contextBlock(for message: String) async -> String? {
        guard let title = extractTitle(from: message) else { return nil }

        let region = await MainActor.run { StorageService.shared.settings.region }
        let regionCode = region.isEmpty ? "US" : region.uppercased()

        do {
            let results = try await TMDBService.shared.searchMulti(query: title)
            guard let match = results.results.first(where: {
                $0.resolvedMediaType == .movie || $0.resolvedMediaType == .tv
            }) else {
                return """
                TMDB lookup for "\(title)" (run just now) returned no matching film or series. \
                Tell the user you couldn't find that title rather than describing it from memory.
                """
            }

            return match.resolvedMediaType == .movie
                ? try await movieBlock(id: match.id, region: regionCode)
                : try await tvBlock(id: match.id, region: regionCode)
        } catch {
            return nil
        }
    }

    private static func movieBlock(id: Int, region: String) async throws -> String {
        async let detailsTask = TMDBService.shared.getMovieDetails(id: id)
        async let providersTask = TMDBService.shared.getMovieWatchProviders(id: id)
        async let datesTask = TMDBService.shared.getMovieReleaseDates(id: id)
        let details = try await detailsTask
        let providers = try? await providersTask
        let dates = try? await datesTask

        let today = todayString()
        var lines = ["Title: \(details.title) (film)"]
        if let status = details.status, !status.isEmpty { lines.append("Status: \(status)") }

        // A film's own `release_date` doesn't say whether that date was a cinema
        // opening or a streaming drop. The release-dates endpoint does, and the
        // difference is most of the answer for anything released recently.
        let entries = regionEntries(dates, region: region)
        let theatrical = earliest(entries, types: [2, 3])
            ?? details.releaseDate.map { String($0.prefix(10)) }
        let digital = earliest(entries, types: [4])

        if let theatrical, !theatrical.isEmpty {
            lines.append("Cinema release: \(theatrical)")
        } else {
            lines.append("Cinema release: not announced on TMDB")
        }
        if let digital, !digital.isEmpty {
            lines.append("Digital release: \(digital)")
        }

        lines.append(movieAvailability(
            region: region,
            status: details.status,
            providers: providerSummary(providers?.results?[region]),
            theatrical: theatrical,
            digital: digital,
            today: today
        ))

        return wrap(lines, region: region)
    }

    private static func tvBlock(id: Int, region: String) async throws -> String {
        async let detailsTask = TMDBService.shared.getTVShowDetails(id: id)
        async let providersTask = TMDBService.shared.getTVShowWatchProviders(id: id)
        let details = try await detailsTask
        let providers = try? await providersTask

        var lines = ["Title: \(details.name) (series)"]
        if let status = details.status, !status.isEmpty { lines.append("Status: \(status)") }
        if let date = details.firstAirDate, !date.isEmpty {
            lines.append("First air date: \(date)")
        } else {
            lines.append("First air date: not yet announced on TMDB")
        }
        // For a show that hasn't aired, the network is the whole answer — it's
        // where it will land, which is what the user is really asking.
        if let networks = details.networks, !networks.isEmpty {
            lines.append("Network / home service: \(networks.map(\.name).joined(separator: ", "))")
        }
        if let seasons = details.numberOfSeasons, seasons > 0 {
            lines.append("Seasons released so far: \(seasons)")
        }

        lines.append(seriesAvailability(
            region: region,
            providers: providerSummary(providers?.results?[region]),
            firstAir: details.firstAirDate.map { String($0.prefix(10)) },
            networks: details.networks?.map(\.name) ?? [],
            today: todayString()
        ))

        return wrap(lines, region: region)
    }

    /// The same distinction on the TV side: a series with no provider has either
    /// not premiered, or has aired and simply isn't carried in this region.
    private static func seriesAvailability(
        region: String,
        providers: String?,
        firstAir: String?,
        networks: [String],
        today: String
    ) -> String {
        if let providers { return "Streaming in \(region) — \(providers)" }

        let home = networks.isEmpty ? nil : networks.joined(separator: ", ")

        guard let firstAir, !firstAir.isEmpty, firstAir <= today else {
            let when = (firstAir?.isEmpty == false) ? "premieres \(firstAir!)" : "has no announced premiere date"
            let expected = home.map { " It is expected on \($0)." } ?? ""
            return "NOT PREMIERED YET — this series \(when) and is not streaming anywhere.\(expected)"
        }

        let origin = home.map { " It aired on \($0)." } ?? ""
        return "ALREADY AIRED, NOT CARRIED IN \(region) — the series premiered \(firstAir) but no service "
            + "in \(region) currently streams, rents, or sells it.\(origin) It exists and has aired; it "
            + "just isn't available there right now."
    }

    /// The distinction that matters, and that a bare provider list can't make:
    /// a film with nothing listed may be unreleased, in its cinema run, out of
    /// cinemas but not yet streaming, or old and simply not carried here. Those
    /// are four different answers and only one of them is "not out".
    private static func movieAvailability(
        region: String,
        status: String?,
        providers: String?,
        theatrical: String?,
        digital: String?,
        today: String
    ) -> String {
        if let providers {
            // A recent release can be on PVOD and still in cinemas at once.
            if let theatrical, theatrical <= today, daysBetween(theatrical, today) <= cinemaRunDays {
                return "Streaming in \(region) — \(providers). Released in cinemas on "
                    + "\(theatrical), recently enough that it may also still be showing there."
            }
            return "Streaming in \(region) — \(providers)"
        }

        // Nothing carries it. Which of the four cases is it?
        let unreleasedStatuses = ["planned", "in production", "post production", "rumored", "canceled", "cancelled"]
        let isUnreleasedStatus = unreleasedStatuses.contains(status?.lowercased() ?? "")

        guard let theatrical, !theatrical.isEmpty, theatrical <= today, !isUnreleasedStatus else {
            let when = (theatrical?.isEmpty == false) ? "due in cinemas on \(theatrical!)" : "with no release date announced"
            return "NOT RELEASED YET — this film is \(when). It is not in cinemas and not streaming."
        }

        let age = daysBetween(theatrical, today)

        if let digital, !digital.isEmpty {
            if digital > today {
                return "IN CINEMAS NOW — released \(theatrical) and playing in cinemas. Not streaming "
                    + "yet; its digital release is scheduled for \(digital). It IS released — never say otherwise."
            }
            return "NOT CURRENTLY AVAILABLE IN \(region) — it had its cinema run (from \(theatrical)) "
                + "and its digital release (\(digital)), but no service in \(region) currently streams, "
                + "rents, or sells it. It is released; it just isn't carried here right now."
        }

        if age <= cinemaRunDays {
            return "IN CINEMAS NOW — released \(theatrical), \(age) days ago, and no service carries it "
                + "yet, which is what a film still in its cinema run looks like. It IS released and is "
                + "playing in cinemas — never say otherwise. No digital date has been announced."
        }

        if age <= postCinemaDays {
            return "OUT OF CINEMAS, NOT STREAMING YET — released \(theatrical), \(age) days ago, so its "
                + "cinema run has most likely finished, but no service in \(region) carries it and no "
                + "digital date is listed. It is released; it is in the gap between cinemas and streaming."
        }

        return "NOT CURRENTLY AVAILABLE IN \(region) — released \(theatrical), \(age) days ago. It is "
            + "long out of cinemas and no service in \(region) streams, rents, or sells it. It is an old "
            + "release that simply isn't carried here right now, not an upcoming one."
    }

    /// Typical theatrical exclusivity. Past this a film has usually left cinemas,
    /// so the absence of a provider stops meaning "still in its run".
    private static let cinemaRunDays = 90
    /// Past this the film is old rather than between windows.
    private static let postCinemaDays = 240

    /// The region's providers as one line, or nil when nothing is listed —
    /// callers decide what "nothing" means, since it carries four different
    /// meanings depending on where the title is in its life.
    private static func providerSummary(_ region: WatchProviderRegion?) -> String? {
        guard let region else { return nil }

        var parts: [String] = []
        func add(_ label: String, _ providers: [WatchProvider]?) {
            guard let providers, !providers.isEmpty else { return }
            parts.append("\(label): \(providers.map(\.providerName).joined(separator: ", "))")
        }
        add("Included with subscription", region.flatrate)
        add("Free", region.free)
        add("Free with ads", region.ads)
        add("Rent", region.rent)
        add("Buy", region.buy)

        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    /// Release-date entries for the user's region, falling back to US — a film
    /// with no entry for a small market still has a useful global picture.
    private static func regionEntries(
        _ dates: MovieReleaseDatesResponse?, region: String
    ) -> [MovieReleaseDate]? {
        dates?.results.first(where: { $0.iso3166_1 == region })?.releaseDates
            ?? dates?.results.first(where: { $0.iso3166_1 == "US" })?.releaseDates
    }

    /// Earliest date among the given TMDB release types, as `yyyy-MM-dd`.
    private static func earliest(_ entries: [MovieReleaseDate]?, types: Set<Int>) -> String? {
        entries?.compactMap { entry -> String? in
            guard let type = entry.type, types.contains(type),
                  let date = entry.releaseDate, date.count >= 10 else { return nil }
            return String(date.prefix(10))
        }.min()
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Whole days between two `yyyy-MM-dd` strings; 0 if either won't parse.
    private static func daysBetween(_ from: String, _ to: String) -> Int {
        guard let start = dayFormatter.date(from: from),
              let end = dayFormatter.date(from: to) else { return 0 }
        return Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// `yyyy-MM-dd` today, for plain string comparison against TMDB dates.
    private static func todayString() -> String {
        dayFormatter.string(from: Date())
    }

    private static func wrap(_ lines: [String], region: String) -> String {
        """
        Live TMDB availability for the title the user asked about, retrieved just now \
        for their region (\(region)). This is current and authoritative — use it instead \
        of your own knowledge of what is released or where it streams, and do not claim a \
        title is unreleased or in development if the data below says otherwise. If no \
        provider is listed, say it isn't streaming in their region yet and name the \
        network it's expected on when one is given, rather than guessing at a service. \
        A film that is out in cinemas but carried by no service is PLAYING IN CINEMAS — \
        say that, and never describe it as unreleased or still to come.

        \(lines.joined(separator: "\n"))
        """
    }

    // MARK: - Title extraction

    /// Pulls the title out of an availability question, or returns nil when the
    /// message isn't one. Ordered most specific first — "where is X streaming"
    /// has to win over the looser "is X streaming".
    static func extractTitle(from message: String) -> String? {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text)
            else { continue }

            if let title = clean(String(text[range])) { return title }
        }
        return nil
    }

    private static let patterns: [String] = [
        // where is X streaming / where's X available
        #"\bwhere(?:'s|\s+is|\s+are)\s+(.+?)\s+(?:streaming|available|showing|playing|to\s+watch)\b"#,
        // where / how can i watch X
        #"\b(?:where|how)\s+(?:can|could|do|does|should|would)\s+(?:i|we|you|someone)\s+(?:watch|stream|see|find)\s+(.+)"#,
        // where to watch X
        #"\bwhere\s+to\s+(?:watch|stream|find)\s+(.+)"#,
        // what streaming service has X / which platform is X on — this shape
        // ends on a dangling "on" often enough to swallow it here. Deliberately
        // not a global rule: titles really do end in "On" (Carry On), and the
        // other patterns don't strand a preposition the way this one does.
        #"\b(?:what|which)\s+(?:streaming\s+)?(?:service|platform|channel|app|site)s?\s+(?:has|have|is|are|carries|carry|shows?|streams?)\s+(.+?)(?:\s+on)?\s*[?.!]*$"#,
        // is X on netflix / is X streaming on disney+
        #"\b(?:is|are)\s+(.+?)\s+(?:streaming\s+)?on\s+\w"#,
        // can i watch X
        #"\bcan\s+(?:i|we|you)\s+(?:watch|stream)\s+(.+)"#,
        // is X in cinemas / in theaters / out in cinemas
        #"\b(?:is|are)\s+(.+?)\s+(?:still\s+)?(?:out\s+)?(?:in|at|on)\s+(?:the\s+)?(?:cinemas?|theat(?:er|re)s?|imax)\b"#,
        // what cinemas is X playing at
        #"\b(?:what|which)\s+(?:cinemas?|theat(?:er|re)s?)\s+(?:is|are)\s+(.+?)\s+(?:in|at|playing|showing|on)\b"#,
        // is X streaming / is X available (loosest — last)
        #"\b(?:is|are)\s+(.+?)\s+(?:streaming|available)\b"#
    ]

    /// Trailing filler that clings to a spoken title — "…streaming right now?",
    /// "…available anywhere", "…on Netflix".
    private static let trailingNoise = [
        "streaming", "available", "online", "right now", "now", "anywhere",
        "currently", "at the moment", "yet", "these days", "tonight", "today",
        "for free", "free", "to watch", "to stream", "in the us", "in the uk",
        "in the usa", "near me", "please", "atlas",
        "playing", "showing", "in cinemas", "in theaters", "in theatres",
        "at the cinema", "in the cinema", "out"
    ]

    /// Leading noise that describes the thing rather than naming it. Only these
    /// exact openers are stripped — a bare "the" is left alone, because plenty of
    /// titles start with it.
    private static let leadingNoise = ["the show", "the movie", "the series", "the film", "the tv show"]

    private static func clean(_ raw: String) -> String? {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "?!.,;:\"'“”‘’ "))

        var changed = true
        while changed {
            changed = false
            let lower = title.lowercased()

            for noise in leadingNoise where lower.hasPrefix(noise + " ") {
                title = String(title.dropFirst(noise.count)).trimmingCharacters(in: .whitespaces)
                changed = true
                break
            }

            let lowerAgain = title.lowercased()
            for noise in trailingNoise where lowerAgain.hasSuffix(" " + noise) {
                title = String(title.dropLast(noise.count)).trimmingCharacters(in: .whitespaces)
                changed = true
                break
            }

            let trimmed = title.trimmingCharacters(in: CharacterSet(charactersIn: "?!.,;:\"'“”‘’ "))
            if trimmed != title { title = trimmed; changed = true }
        }

        // A one-character remainder is noise, not a title. So is a bare pronoun,
        // which means the question referred to something earlier in the chat and
        // there's nothing here to look up.
        guard title.count > 1,
              !["it", "this", "that", "them", "they", "he", "she"].contains(title.lowercased())
        else { return nil }

        return title
    }
}
