import Foundation
#if canImport(UIKit)
import UIKit
import Vision
#endif

#if canImport(UIKit)
struct InAppVisualSearchResult: Identifiable {
    let id: String
    let item: MediaItem
    let matchedQuery: String
    let extractedText: [String]
    let ratingsSummary: RatingsSummary?
    let confidence: Double
}

enum InAppVisualSearchError: LocalizedError {
    case noReadableText
    case noMatches

    var errorDescription: String? {
        switch self {
        case .noReadableText:
            return "No readable poster text was found. Try getting closer or improving lighting."
        case .noMatches:
            return "No close TMDB matches were found for this poster."
        }
    }
}

actor InAppVisualSearchService {
    static let shared = InAppVisualSearchService()

    func analyze(image: UIImage) async throws -> [InAppVisualSearchResult] {
        let extractedText = try extractPosterText(from: image)
        let queryCandidates = makeTitleSearchQueries(from: extractedText)
        guard !queryCandidates.isEmpty else {
            throw InAppVisualSearchError.noReadableText
        }

        let detectedYears = Set(extractedText.compactMap(Self.detectYear(in:)))
        var candidatesByKey: [String: (item: MediaItem, query: String, score: Double)] = [:]

        for query in queryCandidates.prefix(8) {
            let response = try await TMDBService.shared.searchMulti(query: query)
            for item in response.results where item.resolvedMediaType == .movie || item.resolvedMediaType == .tv {
                let key = "\(item.resolvedMediaType.rawValue)-\(item.id)"
                let score = Self.score(item: item, for: query, extractedText: extractedText, detectedYears: detectedYears)
                guard score > 0 else { continue }
                if let existing = candidatesByKey[key], existing.score >= score {
                    continue
                }
                candidatesByKey[key] = (item, query, score)
            }
        }

        let rankedCandidates = candidatesByKey.values
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.item.popularity ?? 0 > rhs.item.popularity ?? 0
            }

        guard !rankedCandidates.isEmpty else {
            throw InAppVisualSearchError.noMatches
        }

        var results: [InAppVisualSearchResult] = []
        for candidate in rankedCandidates.prefix(5) {
            let ratingsSummary = await MDBListService.shared.getRatingsSummary(
                tmdbId: candidate.item.id,
                mediaType: candidate.item.resolvedMediaType
            )
            results.append(
                InAppVisualSearchResult(
                    id: "\(candidate.item.resolvedMediaType.rawValue)-\(candidate.item.id)",
                    item: candidate.item,
                    matchedQuery: candidate.query,
                    extractedText: extractedText,
                    ratingsSummary: ratingsSummary,
                    confidence: candidate.score
                )
            )
        }
        return results
    }

    private func extractPosterText(from image: UIImage) throws -> [String] {
        guard let cgImage = image.cgImage else {
            throw InAppVisualSearchError.noReadableText
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let lines = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .map(Self.cleanOCRLine(_:))
            .filter { !$0.isEmpty }

        let uniqueLines = Self.uniqueNormalized(lines)
        guard !uniqueLines.isEmpty else {
            throw InAppVisualSearchError.noReadableText
        }
        return uniqueLines
    }

    private func makeTitleSearchQueries(from ocrLines: [String]) -> [String] {
        var queries = ocrLines
        if ocrLines.count >= 2 {
            for index in 0..<(ocrLines.count - 1) {
                queries.append("\(ocrLines[index]) \(ocrLines[index + 1])")
            }
        }
        if ocrLines.count >= 3 {
            queries.append(ocrLines.prefix(3).joined(separator: " "))
        }
        return Self.uniqueNormalized(queries)
    }

    private static func score(
        item: MediaItem,
        for query: String,
        extractedText: [String],
        detectedYears: Set<String>
    ) -> Double {
        let normalizedTitle = normalized(item.displayTitle)
        let normalizedOriginal = normalized(item.originalTitle ?? item.originalName ?? "")
        let normalizedQuery = normalized(query)
        let extractedBlob = normalized(extractedText.joined(separator: " "))
        let queryTokens = meaningfulTokens(in: query.lowercased())
        let titleTokens = meaningfulTokens(in: item.displayTitle.lowercased())

        var score = 0.0

        if normalizedTitle == normalizedQuery || normalizedOriginal == normalizedQuery {
            score += 120
        } else if normalizedTitle.contains(normalizedQuery) || normalizedQuery.contains(normalizedTitle) {
            score += 85
        } else if normalizedOriginal.contains(normalizedQuery) || normalizedQuery.contains(normalizedOriginal) {
            score += 70
        }

        let tokenOverlap = Set(queryTokens).intersection(titleTokens).count
        score += Double(tokenOverlap * 18)

        if extractedBlob.contains(normalizedTitle) || (!normalizedOriginal.isEmpty && extractedBlob.contains(normalizedOriginal)) {
            score += 40
        }

        if let year = item.year, detectedYears.contains(year) {
            score += 28
        }

        score += min((item.popularity ?? 0) / 8.0, 18)
        return score
    }

    private static func detectYear(in value: String) -> String? {
        let pattern = #"\b(19|20)\d{2}\b"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
            let range = Range(match.range, in: value)
        else {
            return nil
        }
        return String(value[range])
    }

    private static func cleanOCRLine(_ raw: String) -> String {
        let value = raw
            .replacingOccurrences(of: #"[^A-Za-z0-9 '&:\-]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lowered = value.lowercased()
        if titleNoiseWords.contains(lowered) {
            return ""
        }

        let tokens = meaningfulTokens(in: lowered)
        return tokens.isEmpty ? "" : value
    }

    private static func uniqueNormalized(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in raw {
            let normalizedValue = value
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedValue.count >= 2 else { continue }
            let key = normalizedValue.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(normalizedValue)
        }
        return result
    }

    private static func meaningfulTokens(in value: String) -> [String] {
        value.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .filter { !titleNoiseWords.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }

    private static let titleNoiseWords: Set<String> = [
        "home", "watch", "now", "showing", "only", "cinema", "movie", "movies",
        "imax", "dolby", "screen", "book", "tickets", "ticket", "coming", "soon",
        "the", "and", "for", "with", "from", "new", "experience"
    ]
}
#endif
