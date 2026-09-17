//
//  TimelinesView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct Timeline: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let accentColor: Color

    static let marvelCinematicUniverse = Timeline(
        id: "mcu",
        title: "Marvel Cinematic Universe",
        subtitle: "Chronological release order",
        accentColor: .red
    )
}

struct TimelineEntry: Identifiable {
    let id = UUID()
    let title: String
    let releaseDate: String

    let searchTitle: String?
    let searchYear: Int?
    let fixedTmdbId: Int?
    let fixedMediaType: MediaType?

    init(
        title: String,
        releaseDate: String,
        searchTitle: String? = nil,
        searchYear: Int? = nil,
        fixedTmdbId: Int? = nil,
        fixedMediaType: MediaType? = nil
    ) {
        self.title = title
        self.releaseDate = releaseDate
        self.searchTitle = searchTitle
        self.searchYear = searchYear
        self.fixedTmdbId = fixedTmdbId
        self.fixedMediaType = fixedMediaType
    }

    var displayTitle: String {
        title
    }

    var resolvedSearchTitle: String {
        searchTitle ?? title
    }

    var resolvedSearchYear: Int? {
        searchYear
    }

    var releaseYear: Int? {
        let digits = releaseDate.filter { $0.isNumber }
        if digits.count >= 4, let year = Int(digits.suffix(4)) {
            return year
        }
        return nil
    }

    var isSeasonEntry: Bool {
        title.contains(" S1") || title.contains(" S2") || title.contains(" S3")
    }

    var baseTitleForSearch: String {
        var cleaned = resolvedSearchTitle
        if let range = cleaned.range(of: " S1") { cleaned.removeSubrange(range) }
        if let range = cleaned.range(of: " S2") { cleaned.removeSubrange(range) }
        if let range = cleaned.range(of: " S3") { cleaned.removeSubrange(range) }
        return cleaned
    }
}

struct TimelinesView: View {
    private let timelines: [Timeline] = [
        .marvelCinematicUniverse
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Timelines") {
                    ForEach(timelines) { timeline in
                        NavigationLink(destination: MCUTimelineView(timeline: timeline)) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(timeline.accentColor.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "film.stack")
                                            .foregroundColor(timeline.accentColor)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(timeline.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(timeline.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Timelines")
        }
    }
}

struct MCUTimelineView: View {
    let timeline: Timeline

    private enum TimelineDisplayMode: String, CaseIterable {
        case mcu = "MCU"
        case release = "Release"
        case multiverse = "Multiverse"
    }

    private let chronologicalEntries: [TimelineEntry] = [
        TimelineEntry(title: "Eyes of Wakanda", releaseDate: "1260 BC-Mar 1896 (S1)"),
        TimelineEntry(title: "Captain America: The First Avenger", releaseDate: "Mar 1942-Mar 1945; 2011 (present day)"),
        TimelineEntry(title: "Marvel Studios One Shot: Agent Carter", releaseDate: "Mar 1946", searchTitle: "Marvel One-Shot: Agent Carter"),
        TimelineEntry(title: "Captain Marvel", releaseDate: "Jun 1995"),
        TimelineEntry(title: "Iron Man", releaseDate: "Jan-May 2008"),
        TimelineEntry(title: "Iron Man 2", releaseDate: "Apr-May 2010"),
        TimelineEntry(title: "The Incredible Hulk", releaseDate: "Apr-Jul 2010", searchYear: 2008, fixedTmdbId: 1724, fixedMediaType: .movie),
        TimelineEntry(title: "Marvel Studios One Shot: A Funny Thing Happened on the Way to Thor’s Hammer", releaseDate: "May 2010", searchTitle: "Marvel One-Shot: A Funny Thing Happened on the Way to Thor's Hammer"),
        TimelineEntry(title: "Thor", releaseDate: "May 2010"),
        TimelineEntry(title: "Marvel Studios One Shot: The Consultant", releaseDate: "Jul 2010", searchTitle: "Marvel One-Shot: The Consultant"),
        TimelineEntry(title: "The Avengers", releaseDate: "May 2012"),
        TimelineEntry(title: "Marvel Studios One Shot: Item 47", releaseDate: "May 2012", searchTitle: "Marvel One-Shot: Item 47"),
        TimelineEntry(title: "Thor: The Dark World", releaseDate: "Nov 2013"),
        TimelineEntry(title: "Iron Man 3", releaseDate: "Dec 2013-Jan 2014"),
        TimelineEntry(title: "Marvel Studios One Shot: All Hail the King", releaseDate: "2014", searchTitle: "Marvel One-Shot: All Hail the King"),
        TimelineEntry(title: "Captain America: The Winter Soldier", releaseDate: "Mar-Apr 2014"),
        TimelineEntry(title: "Guardians of the Galaxy", releaseDate: "2014"),
        TimelineEntry(title: "Guardians of the Galaxy Vol. 2", releaseDate: "2014"),
        TimelineEntry(title: "I Am Groot S1", releaseDate: "2014 (S1)"),
        TimelineEntry(title: "I Am Groot S2", releaseDate: "2014 (S2)"),
        TimelineEntry(title: "Daredevil S1", releaseDate: "2014 (S1)"),
        TimelineEntry(title: "Jessica Jones S1", releaseDate: "Jan-Mar 2015 (S1)"),
        TimelineEntry(title: "Avengers: Age of Ultron", releaseDate: "Apr 2015"),
        TimelineEntry(title: "Ant-Man", releaseDate: "Aug 2015"),
        TimelineEntry(title: "Daredevil S2", releaseDate: "Oct-Nov 2015 (S2)"),
        TimelineEntry(title: "Luke Cage S1", releaseDate: "Oct-Dec 2015 (S1)"),
        TimelineEntry(title: "Iron Fist S1", releaseDate: "Feb-Mar 2016 (S1)"),
        TimelineEntry(title: "The Defenders", releaseDate: "May 2016"),
        TimelineEntry(title: "Captain America: Civil War", releaseDate: "May-Jun 2016"),
        TimelineEntry(title: "Black Widow", releaseDate: "Jun 2016"),
        TimelineEntry(title: "Black Panther", releaseDate: "Jun 2016"),
        TimelineEntry(title: "Spider-Man: Homecoming", releaseDate: "Sep 2016"),
        TimelineEntry(title: "The Punisher S1", releaseDate: "Nov-Dec 2016 (S1)"),
        TimelineEntry(title: "Doctor Strange", releaseDate: "Feb 2016-Feb 2017"),
        TimelineEntry(title: "Jessica Jones S2", releaseDate: "Apr-May 2017 (S2)"),
        TimelineEntry(title: "Luke Cage S2", releaseDate: "Aug-Sep 2017 (S2)"),
        TimelineEntry(title: "Iron Fist S2", releaseDate: "Sep 2017 (S2)"),
        TimelineEntry(title: "Daredevil S3", releaseDate: "Oct 2017 (S3)"),
        TimelineEntry(title: "Thor: Ragnarok", releaseDate: "Nov 2017"),
        TimelineEntry(title: "The Punisher S2", releaseDate: "Dec 2017-Jan 2018 (S2)"),
        TimelineEntry(title: "Jessica Jones S3", releaseDate: "2018 (S3)"),
        TimelineEntry(title: "Ant-Man and the Wasp", releaseDate: "Apr-May 2018"),
        TimelineEntry(title: "Avengers: Infinity War", releaseDate: "May 2018"),
        TimelineEntry(title: "Avengers: Endgame", releaseDate: "Oct 2023"),
        TimelineEntry(title: "Loki S1", releaseDate: "2012 (Time Heist) / TVA"),
        TimelineEntry(title: "What If…? S1", releaseDate: "Post-Loki S1 (S1)", searchTitle: "What If...?"),
        TimelineEntry(title: "WandaVision", releaseDate: "Nov 2023"),
        TimelineEntry(title: "Shang-Chi and the Legend of the Ten Rings", releaseDate: "Mar-Apr 2024"),
        TimelineEntry(title: "The Falcon and the Winter Soldier", releaseDate: "Apr-May 2024"),
        TimelineEntry(title: "Spider-Man: Far From Home", releaseDate: "Jun-Jul 2024"),
        TimelineEntry(title: "Eternals", releaseDate: "Oct 2024"),
        TimelineEntry(title: "Doctor Strange in the Multiverse of Madness", releaseDate: "Nov-Dec 2024", searchYear: 2022),
        TimelineEntry(title: "Hawkeye", releaseDate: "Dec 2024"),
        TimelineEntry(title: "Moon Knight", releaseDate: "Apr-May 2025"),
        TimelineEntry(title: "Black Panther: Wakanda Forever", releaseDate: "May 2025"),
        TimelineEntry(title: "Echo", releaseDate: "May 2025"),
        TimelineEntry(title: "She-Hulk: Attorney at Law", releaseDate: "2025 (S1)", searchTitle: "She-Hulk: Attorney at Law"),
        TimelineEntry(title: "Ms. Marvel", releaseDate: "Sep 2025"),
        TimelineEntry(title: "Thor: Love and Thunder", releaseDate: "Oct 2025"),
        TimelineEntry(title: "Ironheart", releaseDate: "Sep-Oct 2025 (S1)"),
        TimelineEntry(title: "Werewolf By Night", releaseDate: "Oct-Nov 2025", searchTitle: "Werewolf by Night"),
        TimelineEntry(title: "The Guardians of the Galaxy Holiday Special", releaseDate: "Dec 2025", searchTitle: "The Guardians of the Galaxy Holiday Special"),
        TimelineEntry(title: "Ant-Man and the Wasp: Quantumania", releaseDate: "Jul 2026"),
        TimelineEntry(title: "Guardians of the Galaxy Vol. 3", releaseDate: "2026"),
        TimelineEntry(title: "Secret Invasion", releaseDate: "Oct-Nov 2026"),
        TimelineEntry(title: "The Marvels", releaseDate: "Nov 2026"),
        TimelineEntry(title: "Loki S2", releaseDate: "TVA (S2)"),
        TimelineEntry(title: "What If…? S2", releaseDate: "Post-Loki S1 (S2)", searchTitle: "What If...?"),
        TimelineEntry(title: "Deadpool & Wolverine", releaseDate: "Earth-10005 to Earth-616/TVA/Void", searchTitle: "Deadpool & Wolverine"),
        TimelineEntry(title: "Agatha All Along", releaseDate: "Nov 2026"),
        TimelineEntry(title: "What If…? S3", releaseDate: "Post-Loki S1 (S3)", searchTitle: "What If...?"),
        TimelineEntry(title: "Daredevil: Born Again", releaseDate: "Dec 2026-Apr 2027 (S1)"),
        TimelineEntry(title: "Captain America: Brave New World", releaseDate: "Apr 2027"),
        TimelineEntry(title: "Thunderbolts*", releaseDate: "Oct 2027", searchTitle: "Thunderbolts"),
        TimelineEntry(title: "Wonder Man", releaseDate: "Late 2025-Mid 2027 (S1)", searchYear: 2026),
        TimelineEntry(title: "Spider-Man: Brand New Day", releaseDate: "2028"),
        TimelineEntry(title: "Avengers: Doomsday", releaseDate: "2028")
    ]

    private let multiverseEntries: [TimelineEntry] = [
        TimelineEntry(title: "Iron Man", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "The Incredible Hulk", releaseDate: "Earth-616 • Sacred Timeline", searchYear: 2008, fixedTmdbId: 1724, fixedMediaType: .movie),
        TimelineEntry(title: "Iron Man 2", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Thor", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Captain America: The First Avenger", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "The Avengers", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Iron Man 3", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Thor: The Dark World", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Captain America: The Winter Soldier", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Guardians of the Galaxy", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Guardians of the Galaxy Vol. 2", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Avengers: Age of Ultron", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Ant-Man", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Captain America: Civil War", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Black Panther", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Spider-Man: Homecoming", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Doctor Strange", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Thor: Ragnarok", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Avengers: Infinity War", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Ant-Man and the Wasp", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Captain Marvel", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Avengers: Endgame", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Spider-Man: Far From Home", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "WandaVision", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "The Falcon and the Winter Soldier", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Hawkeye", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Moon Knight", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Ms. Marvel", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Secret Invasion", releaseDate: "Earth-616 • Sacred Timeline"),
        TimelineEntry(title: "Shang-Chi and the Legend of the Ten Rings", releaseDate: "Earth-616 • Phase 4-5 continuation"),
        TimelineEntry(title: "Eternals", releaseDate: "Earth-616 • Phase 4-5 continuation"),
        TimelineEntry(title: "Thor: Love and Thunder", releaseDate: "Earth-616 • Phase 4-5 continuation"),
        TimelineEntry(title: "Black Panther: Wakanda Forever", releaseDate: "Earth-616 • Phase 4-5 continuation"),
        TimelineEntry(title: "Ant-Man and the Wasp: Quantumania", releaseDate: "Earth-616 • Phase 4-5 continuation"),
        TimelineEntry(title: "Guardians of the Galaxy Vol. 3", releaseDate: "Earth-616 • Phase 4-5 continuation"),
        TimelineEntry(title: "The Marvels", releaseDate: "Earth-616 • Phase 4-5 continuation"),
        TimelineEntry(title: "Loki S1", releaseDate: "Earth-616 Branch • Loki escape / TVA branch", searchTitle: "Loki"),
        TimelineEntry(title: "Doctor Strange in the Multiverse of Madness", releaseDate: "Earth-838 • Illuminati timeline"),
        TimelineEntry(title: "Spider-Man", releaseDate: "Earth-96283 • Raimi timeline"),
        TimelineEntry(title: "Spider-Man 2", releaseDate: "Earth-96283 • Raimi timeline"),
        TimelineEntry(title: "Spider-Man 3", releaseDate: "Earth-96283 • Raimi timeline"),
        TimelineEntry(title: "The Amazing Spider-Man", releaseDate: "Earth-120703 • Webb timeline"),
        TimelineEntry(title: "The Amazing Spider-Man 2", releaseDate: "Earth-120703 • Webb timeline"),
        TimelineEntry(title: "X-Men", releaseDate: "Earth-10005 • Original X-Men timeline"),
        TimelineEntry(title: "X2: X-Men United", releaseDate: "Earth-10005 • Original X-Men timeline", searchTitle: "X2"),
        TimelineEntry(title: "X-Men: The Last Stand", releaseDate: "Earth-10005 • Original X-Men timeline"),
        TimelineEntry(title: "The Wolverine", releaseDate: "Earth-10005 • Original X-Men timeline"),
        TimelineEntry(title: "X-Men: First Class", releaseDate: "Earth-10005 • Revised timeline"),
        TimelineEntry(title: "X-Men: Days of Future Past", releaseDate: "Earth-10005 • Revised timeline"),
        TimelineEntry(title: "X-Men: Apocalypse", releaseDate: "Earth-10005 • Revised timeline"),
        TimelineEntry(title: "Dark Phoenix", releaseDate: "Earth-10005 • Revised timeline"),
        TimelineEntry(title: "Logan", releaseDate: "Earth-17315 • Future branch from Earth-10005"),
        TimelineEntry(title: "Deadpool", releaseDate: "Earth-10005 • Loose-canon side timeline"),
        TimelineEntry(title: "Deadpool 2", releaseDate: "Earth-10005 • Loose-canon side timeline"),
        TimelineEntry(title: "What If…? S1", releaseDate: "TRN Multiverse • Captain Carter / Zombies / Ultron Wins", searchTitle: "What If...?"),
        TimelineEntry(title: "What If…? S2", releaseDate: "TRN Multiverse • Separate branching realities", searchTitle: "What If...?"),
        TimelineEntry(title: "What If…? S3", releaseDate: "TRN Multiverse • Separate branching realities", searchTitle: "What If...?"),
        TimelineEntry(title: "Spider-Man: No Way Home", releaseDate: "Multiverse Event • Earth-616 / Earth-96283 / Earth-120703"),
        TimelineEntry(title: "Doctor Strange in the Multiverse of Madness", releaseDate: "Multiverse Event • Earth-616 / Earth-838 / Incursions"),
        TimelineEntry(title: "Loki S2", releaseDate: "Multiverse Event • Infinite timelines / Kang variants", searchTitle: "Loki")
    ]

    @State private var posterItems: [UUID: MediaItem] = [:]
    @State private var ratingsByEntry: [UUID: RatingsSummary] = [:]
    @State private var releaseDatesByEntry: [UUID: String] = [:]
    @State private var isLoadingPosters = false
    @State private var displayMode: TimelineDisplayMode = .mcu
    @State private var selectedItem: MediaItem?

    private var activeChronologicalEntries: [TimelineEntry] {
        displayMode == .multiverse ? multiverseEntries : chronologicalEntries
    }

    private var chronologicalNumbers: [UUID: Int] {
        var map: [UUID: Int] = [:]
        var index = 1
        for entry in activeChronologicalEntries {
            map[entry.id] = index
            index += 1
        }
        return map
    }

    private var orderedEntries: [TimelineEntry] {
        switch displayMode {
        case .mcu:
            return chronologicalEntries
        case .release:
            return chronologicalEntries.sorted { left, right in
                let leftDate = parsedReleaseDate(for: left)
                let rightDate = parsedReleaseDate(for: right)
                switch (leftDate, rightDate) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default:
                    return (chronologicalNumbers[left.id] ?? 0) < (chronologicalNumbers[right.id] ?? 0)
                }
            }
        case .multiverse:
            return multiverseEntries
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Timeline", selection: $displayMode) {
                ForEach(TimelineDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(orderedEntries) { entry in
                        if let item = posterItems[entry.id] {
                            Button {
                                selectedItem = item
                            } label: {
                                TimelineEntryRow(
                                    entry: entry,
                                    mediaItem: item,
                                    ratings: ratingsByEntry[entry.id],
                                    releaseDateText: releaseDatesByEntry[entry.id],
                                    chronologicalNumber: chronologicalNumbers[entry.id],
                                    accentColor: timeline.accentColor
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        } else {
                            TimelineEntryRow(
                                entry: entry,
                                mediaItem: posterItems[entry.id],
                                ratings: ratingsByEntry[entry.id],
                                releaseDateText: releaseDatesByEntry[entry.id],
                                chronologicalNumber: chronologicalNumbers[entry.id],
                                accentColor: timeline.accentColor
                            )
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(timeline.title)
        #if !os(macOS) && !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .mediaDetailPresentation(item: $selectedItem)
        .task { await loadPosters() }
    }

    private func loadPosters() async {
        if isLoadingPosters { return }
        isLoadingPosters = true

        for entry in chronologicalEntries + multiverseEntries {
            if posterItems[entry.id] != nil { continue }
            do {
                if let fixedId = entry.fixedTmdbId, let fixedType = entry.fixedMediaType {
                    let picked: MediaItem
                    switch fixedType {
                    case .movie:
                        let details = try await TMDBService.shared.getMovieDetails(id: fixedId)
                        picked = MediaItem(
                            id: details.id,
                            title: details.title,
                            name: nil,
                            originalTitle: details.originalTitle,
                            originalName: nil,
                            overview: details.overview,
                            posterPath: details.posterPath,
                            backdropPath: details.backdropPath,
                            releaseDate: details.releaseDate,
                            firstAirDate: nil,
                            voteAverage: details.voteAverage,
                            voteCount: nil,
                            popularity: nil,
                            genreIds: nil,
                            mediaType: "movie",
                            adult: nil,
                            originalLanguage: nil
                        )
                    case .tv:
                        let details = try await TMDBService.shared.getTVShowDetails(id: fixedId)
                        picked = MediaItem(
                            id: details.id,
                            title: nil,
                            name: details.name,
                            originalTitle: nil,
                            originalName: details.originalName,
                            overview: details.overview,
                            posterPath: details.posterPath,
                            backdropPath: details.backdropPath,
                            releaseDate: nil,
                            firstAirDate: details.firstAirDate,
                            voteAverage: details.voteAverage,
                            voteCount: nil,
                            popularity: nil,
                            genreIds: nil,
                            mediaType: "tv",
                            adult: nil,
                            originalLanguage: nil
                        )
                    case .person:
                        continue
                    }
                    await MainActor.run {
                        posterItems[entry.id] = picked
                        if let releaseText = releaseText(for: picked) {
                            releaseDatesByEntry[entry.id] = releaseText
                        }
                    }
                    if ratingsByEntry[entry.id] == nil {
                        let ratings = await MDBListService.shared.getRatingsSummary(
                            tmdbId: picked.id,
                            mediaType: picked.resolvedMediaType
                        )
                        await MainActor.run {
                            if let ratings { ratingsByEntry[entry.id] = ratings }
                        }
                    }
                    continue
                }

                let response: TMDBResponse<MediaItem>
                if let preferred = preferredMediaType(for: entry) {
                    switch preferred {
                    case .movie:
                        response = try await TMDBService.shared.searchMovies(
                            query: entry.baseTitleForSearch,
                            year: entry.resolvedSearchYear,
                            page: 1
                        )
                    case .tv:
                        response = try await TMDBService.shared.searchTV(
                            query: entry.baseTitleForSearch,
                            year: entry.resolvedSearchYear,
                            page: 1
                        )
                    case .person:
                        response = try await TMDBService.shared.searchMulti(
                            query: entry.baseTitleForSearch,
                            page: 1
                        )
                    }
                } else {
                    response = try await TMDBService.shared.searchMulti(
                        query: entry.baseTitleForSearch,
                        page: 1
                    )
                }
                if let picked = pickBestMatch(from: response.results, for: entry) {
                    await MainActor.run {
                        posterItems[entry.id] = picked
                        if let releaseText = releaseText(for: picked) {
                            releaseDatesByEntry[entry.id] = releaseText
                        }
                    }
                    if ratingsByEntry[entry.id] == nil {
                        let ratings = await MDBListService.shared.getRatingsSummary(
                            tmdbId: picked.id,
                            mediaType: picked.resolvedMediaType
                        )
                        await MainActor.run {
                            if let ratings {
                                ratingsByEntry[entry.id] = ratings
                            }
                        }
                    }
                }
            } catch {
                print("Timeline poster search failed for \(entry.title): \(error)")
            }
        }

        isLoadingPosters = false
    }

    private func pickBestMatch(from results: [MediaItem], for entry: TimelineEntry) -> MediaItem? {
        let preferred = preferredMediaType(for: entry)
        if let preferred {
            if let match = results.first(where: { $0.resolvedMediaType == preferred }) {
                return match
            }
        }
        return results.first
    }

    private func preferredMediaType(for entry: TimelineEntry) -> MediaType? {
        let title = entry.displayTitle.lowercased()
        if entry.isSeasonEntry { return .tv }
        let tvKeywords = [
            "daredevil", "jessica jones", "luke cage", "iron fist", "defenders",
            "punisher", "wandavision", "falcon and the winter soldier", "hawkeye",
            "moon knight", "echo", "she-hulk", "ms. marvel", "secret invasion",
            "loki", "what if", "agatha", "born again", "eyes of wakanda", "ironheart"
        ]
        if tvKeywords.contains(where: { title.contains($0) }) { return .tv }
        if title.contains("one shot") || title.contains("one-shot") { return .movie }
        return nil
    }

    private func parsedReleaseDate(for entry: TimelineEntry) -> Date? {
        if let dateString = releaseDatesByEntry[entry.id] {
            return parseDate(dateString)
        }
        return nil
    }

    private func releaseText(for item: MediaItem) -> String? {
        if let dateString = item.releaseDate ?? item.firstAirDate, !dateString.isEmpty {
            return formattedDate(dateString)
        }
        return nil
    }

    private func formattedDate(_ input: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        if let date = parser.date(from: input) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
        return input
    }

    private func parseDate(_ input: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.date(from: input)
    }
}

struct TimelineEntryRow: View {
    let entry: TimelineEntry
    let mediaItem: MediaItem?
    let ratings: RatingsSummary?
    let releaseDateText: String?
    let chronologicalNumber: Int?
    let accentColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TimelinePoster(mediaItem: mediaItem, accentColor: accentColor)

            VStack(alignment: .leading, spacing: 8) {
                if let imdb = ratings?.imdbRating, imdb != "N/A" {
                    LogoScoreRow(
                        logoName: "F154F6CE-7602-4A20-8AC1-94F19395B5FC_IMDb_Logo_Rectangle_svg",
                        value: imdb,
                        logoHeight: 14
                    )
                }

                if ratings?.rottenTomatoesScore != nil || ratings?.rottenTomatoesAudienceScore != nil {
                    RTRatingsStack(
                        criticsScore: ratings?.rottenTomatoesScore,
                        audienceScore: ratings?.rottenTomatoesAudienceScore
                    )
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(entry.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.trailing)

                Text(releaseLine)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(chronologyLine)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gray.opacity(0.12))
        )
    }

    private var releaseLine: String {
        let dateText = releaseDateText ?? (entry.releaseDate.isEmpty ? "TBD" : entry.releaseDate)
        return "Release: \(dateText)"
    }

    private var chronologyLine: String {
        if let number = chronologicalNumber {
            return "Chronological: #\(number)"
        }
        return "Chronological: —"
    }
}

struct LogoScoreRow: View {
    let logoName: String
    let value: String
    let logoHeight: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(logoName)
                .resizable()
                .scaledToFit()
                .frame(height: logoHeight)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct RTRatingsStack: View {
    let criticsScore: String?
    let audienceScore: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let criticsScore {
                LogoScoreRow(
                    logoName: "F209AC62-E462-4675-B076-F6764418CC33_Fresh_Tomato_logo_svg",
                    value: criticsScore,
                    logoHeight: 14
                )
            }

            if let audienceScore {
                LogoScoreRow(
                    logoName: "B07B3FD9-0C00-485E-BB1D-142B7A766C33_Rotten_Tomatoes_positive_audience",
                    value: audienceScore,
                    logoHeight: 14
                )
            }
        }
    }
}

struct TimelinePoster: View {
    let mediaItem: MediaItem?
    let accentColor: Color
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let posterSize = ResponsiveSizing.compactPosterSize(horizontalSizeClass: horizontalSizeClass)
        PosterImageView(posterPath: mediaItem?.posterPath, size: .small)
        .frame(width: posterSize.width, height: posterSize.height)
    }
}

#Preview {
    TimelinesView()
}
