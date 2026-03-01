import Foundation

struct SterKinekorSession: Identifiable, Hashable {
    let id: String
    let date: Date
    let timeLabel: String
    let bookingPath: String

    var bookingURL: URL? {
        URL(string: "https://www.sterkinekor.com\(bookingPath)")
    }
}

struct SterKinekorDateShowtimes: Identifiable, Hashable {
    let date: Date
    let sessions: [SterKinekorSession]

    var id: String {
        Self.dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum SterKinekorShowtimesError: LocalizedError {
    case invalidURL
    case noDatesFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Ster-Kinekor URL."
        case .noDatesFound:
            return "No upcoming showtimes found for this movie at this location."
        }
    }
}

final class SterKinekorShowtimesService {
    static let shared = SterKinekorShowtimesService()

    private init() {}

    private let session = URLSession.shared
    private let calendar = Calendar(identifier: .gregorian)

    private lazy var dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private lazy var gaDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'Z"
        return formatter
    }()

    func locationSlug(from raw: String) -> String {
        let lowered = raw.lowercased()
        let normalizedChars = lowered.map { char -> Character in
            if char.isLetter || char.isNumber || char == " " || char == "-" {
                return char
            }
            return " "
        }

        return String(normalizedChars)
            .split(whereSeparator: { $0 == " " || $0 == "-" })
            .joined(separator: "-")
    }

    func fetchShowtimes(
        movieTitle: String,
        locationSlug: String,
        lookaheadDays: Int = 10
    ) async throws -> [SterKinekorDateShowtimes] {
        let now = Date()
        let days = max(1, lookaheadDays)

        var allByDate: [SterKinekorDateShowtimes] = []

        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let html = try await fetchProgramHTML(locationSlug: locationSlug, date: date)
            let sessions = parseSessions(from: html, forMovieTitle: movieTitle)
            if !sessions.isEmpty {
                let sorted = sessions.sorted { $0.date < $1.date }
                allByDate.append(SterKinekorDateShowtimes(date: date, sessions: sorted))
            }
        }

        if allByDate.isEmpty {
            throw SterKinekorShowtimesError.noDatesFound
        }

        return allByDate.sorted { $0.date < $1.date }
    }

    // MARK: - Networking

    private func fetchProgramHTML(locationSlug: String, date: Date) async throws -> String {
        var components = URLComponents(string: "https://www.sterkinekor.com/program")
        components?.queryItems = [
            URLQueryItem(name: "location", value: locationSlug),
            URLQueryItem(name: "date", value: dayFormatter.string(from: date))
        ]
        guard let url = components?.url else { throw SterKinekorShowtimesError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (WatchGuide-MovieandTVtracker)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, _) = try await session.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Parsing

    private func parseSessions(from html: String, forMovieTitle targetTitle: String) -> [SterKinekorSession] {
        let starts = html.ranges(of: "movie-card-with-show-times py-0 all-content-has-been-loaded")
        guard !starts.isEmpty else { return [] }

        let titleRegex = try? NSRegularExpression(
            pattern: "<a[^>]*class=\"movieDetailsCard__title[^>]*>(.*?)</a>",
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )
        let showtimeRegex = try? NSRegularExpression(
            pattern: "showCategoriesModal\\('([^']+)'\\);\\s*sendGA\\('[^']*',\\s*'([^']+?)'[^\\)]*\\)[\\s\\S]*?<span[^>]*>([^<]+)</span>",
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )

        guard let titleRegex, let showtimeRegex else { return [] }

        var sessions: [SterKinekorSession] = []
        let targetNormalized = normalizedTitle(targetTitle)

        for index in 0..<starts.count {
            let start = starts[index].lowerBound
            let end = (index + 1 < starts.count) ? starts[index + 1].lowerBound : html.endIndex
            let segment = String(html[start..<end])

            guard let movieTitle = firstMatch(in: segment, regex: titleRegex, group: 1)?
                .htmlDecoded?
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  isLikelyMatch(target: targetNormalized, candidate: normalizedTitle(movieTitle)) else {
                continue
            }

            let nsRange = NSRange(segment.startIndex..<segment.endIndex, in: segment)
            let matches = showtimeRegex.matches(in: segment, options: [], range: nsRange)
            for match in matches {
                guard
                    let bookingRange = Range(match.range(at: 1), in: segment),
                    let rawDateRange = Range(match.range(at: 2), in: segment),
                    let labelRange = Range(match.range(at: 3), in: segment)
                else { continue }

                let bookingPath = String(segment[bookingRange])
                let rawGA = String(segment[rawDateRange])
                let timeLabel = String(segment[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                let cleanedGA = rawGA.components(separatedBy: " (").first ?? rawGA
                guard let date = gaDateFormatter.date(from: cleanedGA) else { continue }

                let id = "\(bookingPath)|\(Int(date.timeIntervalSince1970))"
                sessions.append(
                    SterKinekorSession(
                        id: id,
                        date: date,
                        timeLabel: timeLabel,
                        bookingPath: bookingPath
                    )
                )
            }
        }

        return Array(Set(sessions))
    }

    private func firstMatch(in text: String, regex: NSRegularExpression, group: Int) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let resultRange = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[resultRange])
    }

    private func normalizedTitle(_ title: String) -> String {
        let lowered = title.lowercased()
        let chars = lowered.map { char -> Character in
            if char.isLetter || char.isNumber || char == " " {
                return char
            }
            return " "
        }
        return String(chars)
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLikelyMatch(target: String, candidate: String) -> Bool {
        if target.isEmpty || candidate.isEmpty { return false }
        if target == candidate { return true }
        if target.contains(candidate) || candidate.contains(target) { return true }

        let t = Set(target.split(separator: " ").map(String.init))
        let c = Set(candidate.split(separator: " ").map(String.init))
        let overlap = t.intersection(c).count
        return overlap >= 2
    }
}

private extension String {
    var htmlDecoded: String? {
        guard let data = data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil).string
    }

    func ranges(of search: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var startIndex = self.startIndex
        while let range = self.range(of: search, options: [], range: startIndex..<self.endIndex) {
            ranges.append(range)
            startIndex = range.upperBound
        }
        return ranges
    }
}
