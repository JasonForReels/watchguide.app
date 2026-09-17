import Foundation
#if canImport(UIKit)
import UIKit
import Vision
import CoreImage
#endif

#if canImport(UIKit)
struct InAppVisualSearchResult: Identifiable {
    let id: String
    let item: MediaItem
    let matchedQuery: String
    let extractedText: [String]
    let rawDetectedText: [String]
    let ratingsSummary: RatingsSummary?
    let fanArtTitleName: String?
    let fanArtTitleLogoURL: URL?
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
    private let imageSession = URLSession(configuration: .ephemeral)
    private let ciContext = CIContext()

    func analyze(image: UIImage) async throws -> [InAppVisualSearchResult] {
        let ocr = try extractPosterText(from: image)
        let extractedText = ocr.cleanedLines
        let queryCandidates = makeTitleSearchQueries(from: extractedText)
        guard !queryCandidates.isEmpty else {
            throw InAppVisualSearchError.noReadableText
        }

        let detectedYears = Set((ocr.rawLines + extractedText).compactMap(Self.detectYear(in:)))
        let detectedReleaseDate = Self.detectReleaseDate(in: ocr.rawLines + extractedText)
        let sourceFeaturePrint = try generateFeaturePrint(for: image)
        var candidatesByKey: [String: (item: MediaItem, query: String, score: Double)] = [:]

        for query in queryCandidates.prefix(8) {
            let response = try await TMDBService.shared.searchMulti(query: query)
            for item in response.results where item.resolvedMediaType == .movie || item.resolvedMediaType == .tv {
                let key = "\(item.resolvedMediaType.rawValue)-\(item.id)"
                let score = Self.score(
                    item: item,
                    for: query,
                    extractedText: extractedText,
                    detectedYears: detectedYears,
                    detectedReleaseDate: detectedReleaseDate
                )
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

        var enrichedCandidates: [(item: MediaItem, query: String, score: Double, fanArtTitleName: String?, fanArtTitleLogoURL: URL?)] = []
        for candidate in rankedCandidates.prefix(8) {
            let fanArt = await FanArtService.shared.getArt(
                tmdbId: candidate.item.id,
                mediaType: candidate.item.resolvedMediaType
            )
            let fanArtTitleName = fanArt?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fanArtTitleLogoURL = await FanArtService.shared.getBestLogoURL(
                tmdbId: candidate.item.id,
                mediaType: candidate.item.resolvedMediaType
            )
            let posterSimilarityBoost = await visualPosterSimilarityBoost(
                sourceFeaturePrint: sourceFeaturePrint,
                item: candidate.item
            )
            var rescored = candidate.score
            rescored += Self.fanArtScoreBoost(
                item: candidate.item,
                fanArtTitleName: fanArtTitleName,
                extractedText: extractedText,
                detectedYears: detectedYears,
                detectedReleaseDate: detectedReleaseDate
            )
            rescored += posterSimilarityBoost
            enrichedCandidates.append((
                item: candidate.item,
                query: candidate.query,
                score: rescored,
                fanArtTitleName: fanArtTitleName,
                fanArtTitleLogoURL: fanArtTitleLogoURL
            ))
        }

        let rankedByScore = enrichedCandidates.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return (lhs.item.year ?? "") > (rhs.item.year ?? "")
        }
        let finalCandidates = prioritizeCandidatesByReleaseDate(
            rankedByScore,
            detectedReleaseDate: detectedReleaseDate
        )

        var results: [InAppVisualSearchResult] = []
        for candidate in finalCandidates.prefix(5) {
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
                    rawDetectedText: ocr.rawLines,
                    ratingsSummary: ratingsSummary,
                    fanArtTitleName: candidate.fanArtTitleName,
                    fanArtTitleLogoURL: candidate.fanArtTitleLogoURL,
                    confidence: candidate.score
                )
            )
        }
        return results
    }

    private struct OCRExtraction {
        let rawLines: [String]
        let cleanedLines: [String]
    }

    private func extractPosterText(from image: UIImage) throws -> OCRExtraction {
        guard let cgImage = image.cgImage else {
            throw InAppVisualSearchError.noReadableText
        }

        let candidateImages = makeOCRCandidateImages(from: image, cgImage: cgImage)
        var rawLines: [String] = []

        for candidateImage in candidateImages {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: candidateImage, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            rawLines.append(contentsOf: observations.compactMap { $0.topCandidates(1).first?.string })
        }

        let uniqueRawLines = Self.uniqueNormalized(rawLines)
        let cleanedLines = uniqueRawLines
            .map(Self.cleanOCRLine(_:))
            .filter { !$0.isEmpty }
        let uniqueCleanedLines = Self.uniqueNormalized(cleanedLines)

        guard !uniqueRawLines.isEmpty || !uniqueCleanedLines.isEmpty else {
            throw InAppVisualSearchError.noReadableText
        }

        return OCRExtraction(rawLines: uniqueRawLines, cleanedLines: uniqueCleanedLines)
    }

    private func makeOCRCandidateImages(from image: UIImage, cgImage: CGImage) -> [CGImage] {
        var results: [CGImage] = [cgImage]
        guard let ciImage = CIImage(image: image) else { return results }

        let variants: [CIImage] = [
            ciImage,
            ciImage.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.45,
                kCIInputSaturationKey: 0.0
            ]),
            ciImage.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: -0.7
            ]).applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.7,
                kCIInputSaturationKey: 0.0
            ]),
            ciImage.applyingFilter("CIPhotoEffectNoir")
        ]

        for variant in variants.dropFirst() {
            if let cgVariant = ciContext.createCGImage(variant, from: variant.extent) {
                results.append(cgVariant)
            }
        }
        return results
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
        detectedYears: Set<String>,
        detectedReleaseDate: DateComponents?
    ) -> Double {
        let normalizedTitle = normalized(item.displayTitle)
        let normalizedOriginal = normalized(item.originalTitle ?? item.originalName ?? "")
        let normalizedQuery = normalized(query)
        let extractedBlob = normalized(extractedText.joined(separator: " "))
        let queryTokens = meaningfulTokens(in: query.lowercased())
        let titleTokens = meaningfulTokens(in: item.displayTitle.lowercased())
        let queryDigits = numericTokens(in: query.lowercased())
        let titleDigits = numericTokens(in: item.displayTitle.lowercased() + " " + (item.originalTitle ?? item.originalName ?? "").lowercased())

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

        let digitOverlap = Set(queryDigits).intersection(titleDigits).count
        score += Double(digitOverlap * 45)

        if extractedBlob.contains(normalizedTitle) || (!normalizedOriginal.isEmpty && extractedBlob.contains(normalizedOriginal)) {
            score += 40
        }

        if let year = item.year, detectedYears.contains(year) {
            score += 28
        }

        if let detectedReleaseDate {
            score += releaseDateScoreBoost(item: item, detectedReleaseDate: detectedReleaseDate)
        }

        if normalizedQuery == normalized(queryTokens.first ?? "") || normalizedTitle == normalizedQuery {
            if let year = Int(item.year ?? "") {
                score += Double(max(year - 1990, 0)) * 0.7
            }
        }

        if let year = Int(item.year ?? "") {
            score += Double(max(year - 1990, 0)) * 0.18
        }

        score += min((item.popularity ?? 0) / 18.0, 8)
        return score
    }

    private static func fanArtScoreBoost(
        item: MediaItem,
        fanArtTitleName: String?,
        extractedText: [String],
        detectedYears: Set<String>,
        detectedReleaseDate: DateComponents?
    ) -> Double {
        guard let fanArtTitleName, !fanArtTitleName.isEmpty else { return 0 }

        let extractedBlob = normalized(extractedText.joined(separator: " "))
        let normalizedFanArtTitle = normalized(fanArtTitleName)
        let normalizedItemTitle = normalized(item.displayTitle)
        var boost = 0.0

        if extractedBlob.contains(normalizedFanArtTitle) {
            boost += 42
        }

        if normalizedFanArtTitle == normalizedItemTitle {
            boost += 16
        }

        if let year = item.year, detectedYears.contains(year) {
            boost += 8
        }

        if let detectedReleaseDate {
            boost += releaseDateScoreBoost(item: item, detectedReleaseDate: detectedReleaseDate) * 0.4
        }

        return boost
    }

    private static func releaseDateScoreBoost(item: MediaItem, detectedReleaseDate: DateComponents) -> Double {
        guard let displayDate = item.displayDate else { return 0 }
        let parts = displayDate.split(separator: "-")
        guard parts.count >= 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return 0 }

        var score = 0.0
        if let detectedYear = detectedReleaseDate.year, detectedYear == year {
            score += 34
        }
        if let detectedMonth = detectedReleaseDate.month, detectedMonth == month {
            score += 16
        }
        if let detectedDay = detectedReleaseDate.day, detectedDay == day {
            score += 16
        }
        return score
    }

    private func prioritizeCandidatesByReleaseDate(
        _ candidates: [(item: MediaItem, query: String, score: Double, fanArtTitleName: String?, fanArtTitleLogoURL: URL?)],
        detectedReleaseDate: DateComponents?
    ) -> [(item: MediaItem, query: String, score: Double, fanArtTitleName: String?, fanArtTitleLogoURL: URL?)] {
        guard let detectedReleaseDate else { return candidates }

        let exactMatches = candidates.filter { releaseDateMatchStrength(for: $0.item, detectedReleaseDate: detectedReleaseDate) >= 3 }
        if !exactMatches.isEmpty {
            return exactMatches
        }

        let monthMatches = candidates.filter { releaseDateMatchStrength(for: $0.item, detectedReleaseDate: detectedReleaseDate) >= 2 }
        if !monthMatches.isEmpty {
            return monthMatches
        }

        let yearMatches = candidates.filter { releaseDateMatchStrength(for: $0.item, detectedReleaseDate: detectedReleaseDate) >= 1 }
        if !yearMatches.isEmpty {
            return yearMatches
        }

        return candidates
    }

    private func releaseDateMatchStrength(for item: MediaItem, detectedReleaseDate: DateComponents) -> Int {
        guard let displayDate = item.displayDate else { return 0 }
        let parts = displayDate.split(separator: "-")
        guard parts.count >= 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return 0 }

        let yearMatches = detectedReleaseDate.year == year
        let monthMatches = detectedReleaseDate.month == month
        let dayMatches = detectedReleaseDate.day == day

        if yearMatches && monthMatches && dayMatches {
            return 3
        }
        if yearMatches && monthMatches {
            return 2
        }
        if yearMatches {
            return 1
        }
        return 0
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

    private static func detectReleaseDate(in values: [String]) -> DateComponents? {
        let normalizedValues = values.map {
            $0.replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "/", with: " ")
                .replacingOccurrences(of: ".", with: " ")
        }

        let patterns = [
            #"\b(\d{2})\s+(\d{2})\s+(\d{2,4})\b"#,
            #"\b(\d{2})(\d{2})(\d{2,4})\b"#
        ]

        for value in normalizedValues {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                guard let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { continue }
                guard match.numberOfRanges == 4 else { continue }

                let month = intMatch(in: value, at: match.range(at: 1))
                let day = intMatch(in: value, at: match.range(at: 2))
                var year = intMatch(in: value, at: match.range(at: 3))

                if let unwrappedYear = year, unwrappedYear < 100 {
                    year = 2000 + unwrappedYear
                }

                guard let month, let day, let year else { continue }
                guard (1...12).contains(month), (1...31).contains(day), year >= 2000 else { continue }
                return DateComponents(year: year, month: month, day: day)
            }
        }
        return nil
    }

    private static func intMatch(in source: String, at nsRange: NSRange) -> Int? {
        guard let range = Range(nsRange, in: source) else { return nil }
        return Int(source[range])
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

        if looksLikeReleaseDate(value) {
            return value
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

    private static func numericTokens(in value: String) -> [String] {
        value.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
    }

    private static func looksLikeReleaseDate(_ value: String) -> Bool {
        let compact = value.replacingOccurrences(of: " ", with: "")
        if compact.count == 6 || compact.count == 8 {
            return compact.allSatisfy(\.isNumber)
        }
        return value.range(of: #"\b\d{2}\s+\d{2}\s+\d{2,4}\b"#, options: .regularExpression) != nil
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

    private func visualPosterSimilarityBoost(
        sourceFeaturePrint: VNFeaturePrintObservation,
        item: MediaItem
    ) async -> Double {
        guard let referenceURL = await referencePosterURL(for: item) else { return 0 }
        guard let referenceImage = try? await loadImage(from: referenceURL) else { return 0 }
        guard let referenceFeaturePrint = try? generateFeaturePrint(for: referenceImage) else { return 0 }

        var distance = Float.zero
        do {
            try sourceFeaturePrint.computeDistance(&distance, to: referenceFeaturePrint)
        } catch {
            return 0
        }

        let normalizedCloseness = max(0, 1 - min(Double(distance) / 25.0, 1))
        return normalizedCloseness * 65
    }

    private func referencePosterURL(for item: MediaItem) async -> URL? {
        if let fanArtURL = await FanArtService.shared.getBestPosterURL(
            tmdbId: item.id,
            mediaType: item.resolvedMediaType
        ) {
            return fanArtURL
        }
        return TMDBService.shared.imageURL(path: item.posterPath, size: .large)
    }

    private func loadImage(from url: URL) async throws -> UIImage {
        let (data, _) = try await imageSession.data(from: url)
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        return image
    }

    private func generateFeaturePrint(for image: UIImage) throws -> VNFeaturePrintObservation {
        guard let cgImage = image.cgImage else {
            throw InAppVisualSearchError.noReadableText
        }
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first else {
            throw InAppVisualSearchError.noMatches
        }
        return result
    }
}
#endif
