// VisualIntelligenceIntents.swift
//
// VisualIntelligence is an iOS-device-only framework. It MUST NOT be imported
// on simulator or Mac Catalyst targets because the framework .tbd does not
// exist for x86_64 and the linker will fail with "framework not found".
//
// The entire VisualIntelligence-dependent section is gated behind a nested
// #if canImport(VisualIntelligence) so the import (and its auto-link record)
// is ONLY emitted when the framework actually exists in the SDK being compiled
// against. On x86_64 simulator, canImport evaluates to false → no import →
// no auto-link record → no linker error.

import Foundation

// MARK: - Device-only gate (excludes simulator & Mac Catalyst)
#if os(iOS) && !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
import AppIntents
import Vision
import CoreVideo
import CoreImage

// MARK: - VisualIntelligence-specific code (only when framework exists)
#if canImport(VisualIntelligence)
import VisualIntelligence

@available(iOS 18.0, *)
enum VisualPosterAction: String, AppEnum {
    case openDetails
    case openTrailer
    case addToWatchlist

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Poster Action")

    static var caseDisplayRepresentations: [VisualPosterAction: DisplayRepresentation] = [
        .openDetails: DisplayRepresentation(title: "Open Details"),
        .openTrailer: DisplayRepresentation(title: "Watch Trailer"),
        .addToWatchlist: DisplayRepresentation(title: "Add to Watchlist")
    ]
}

@available(iOS 18.0, *)
struct VisualPosterMatchEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Movie or TV Match"
    static var defaultQuery = VisualPosterMatchEntityQuery()

    let id: String
    let mediaId: Int
    let mediaType: MediaType
    let title: String
    let year: String?
    let overview: String?
    let posterPath: String?
    let posterData: Data?

    var displayRepresentation: DisplayRepresentation {
        let subtitle = [mediaType.displayName, year].compactMap { $0 }.joined(separator: " • ")
        let image: DisplayRepresentation.Image? = {
            guard let posterData, !posterData.isEmpty else { return nil }
            return .init(data: posterData)
        }()
        if subtitle.isEmpty {
            return DisplayRepresentation(title: "\(title)", image: image)
        }
        return DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)", image: image)
    }
}

@available(iOS 18.0, *)
struct VisualPosterMatchEntityQuery: EntityQuery {
    func entities(for identifiers: [VisualPosterMatchEntity.ID]) async throws -> [VisualPosterMatchEntity] {
        await VisualPosterMatchRegistry.shared.entities(for: identifiers)
    }

    func suggestedEntities() async throws -> [VisualPosterMatchEntity] {
        await VisualPosterMatchRegistry.shared.suggestedEntities()
    }
}

@available(iOS 18.0, *)
actor VisualPosterMatchRegistry {
    static let shared = VisualPosterMatchRegistry()

    private var entitiesByID: [String: VisualPosterMatchEntity] = [:]
    private var recentIDs: [String] = []

    func register(_ entities: [VisualPosterMatchEntity]) {
        for entity in entities {
            entitiesByID[entity.id] = entity
            recentIDs.removeAll { $0 == entity.id }
            recentIDs.insert(entity.id, at: 0)
        }
        if recentIDs.count > 30 {
            recentIDs = Array(recentIDs.prefix(30))
        }
    }

    func entities(for identifiers: [String]) -> [VisualPosterMatchEntity] {
        identifiers.compactMap { entitiesByID[$0] }
    }

    func suggestedEntities() -> [VisualPosterMatchEntity] {
        recentIDs.compactMap { entitiesByID[$0] }
    }
}

@available(iOS 18.0, *)
struct VisualPosterIntentValueQuery: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [VisualPosterMatchEntity] {
        guard PlatformCompatibility.supportsVisualIntelligence else { return [] }

        let labels = input.labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let specificLabels = Self.specificLabels(from: labels)

        let ocrText: [String]
        if let pixelBufferSource = input.pixelBuffer {
            ocrText = pixelBufferSource.withUnsafeBuffer { pixelBuffer in
                Self.extractLikelyTitlePhrases(from: pixelBuffer)
            }
        } else {
            ocrText = []
        }

        let textDrivenQueries = Self.makeTitleSearchQueries(from: ocrText)

        var queryCandidates: [String] = []
        queryCandidates.append(contentsOf: textDrivenQueries)
        if !specificLabels.isEmpty {
            queryCandidates.append(contentsOf: specificLabels)
            queryCandidates.append(specificLabels.joined(separator: " "))
        }
        if queryCandidates.isEmpty {
            let fallbackLabels = Self.fallbackLabels(from: labels)
            queryCandidates.append(contentsOf: fallbackLabels)
            if !fallbackLabels.isEmpty {
                queryCandidates.append(fallbackLabels.joined(separator: " "))
            }
        }
        queryCandidates = Self.uniqueNormalized(queryCandidates)

        guard !queryCandidates.isEmpty else { return [] }

        var entitiesByKey: [String: VisualPosterMatchEntity] = [:]

        for candidate in queryCandidates.prefix(8) {
            do {
                let response = try await TMDBService.shared.searchMulti(query: candidate)
                let candidates = response.results
                    .filter { $0.resolvedMediaType == .movie || $0.resolvedMediaType == .tv }
                    .prefix(20)

                for item in candidates {
                    let mediaType = item.resolvedMediaType
                    let key = "\(mediaType.rawValue)-\(item.id)"
                    guard entitiesByKey[key] == nil else { continue }

                    let entity = VisualPosterMatchEntity(
                        id: key,
                        mediaId: item.id,
                        mediaType: mediaType,
                        title: item.displayTitle,
                        year: item.year,
                        overview: item.overview,
                        posterPath: item.posterPath,
                        posterData: nil
                    )
                    entitiesByKey[key] = entity
                }
            } catch {
                continue
            }
        }

        let posterQuery = (labels + ocrText).joined(separator: " ").lowercased()
        let scoringQueries = Self.uniqueNormalized(textDrivenQueries + queryCandidates)
        let entities = Array(entitiesByKey.values).sorted { lhs, rhs in
            let lhsScore = Self.score(entity: lhs, with: scoringQueries, posterQuery: posterQuery)
            let rhsScore = Self.score(entity: rhs, with: scoringQueries, posterQuery: posterQuery)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return (lhs.year ?? "") > (rhs.year ?? "")
        }
        let enriched = await Self.enrichWithPosterData(entities, limit: 12)
        await VisualPosterMatchRegistry.shared.register(enriched)
        return enriched
    }

    private static func uniqueNormalized(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in raw {
            let normalized = value
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.count >= 2 else { continue }
            let key = normalized.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(normalized)
        }
        return result
    }

    private static func makeTitleSearchQueries(from ocrLines: [String]) -> [String] {
        guard !ocrLines.isEmpty else { return [] }
        var queries: [String] = []
        let cleaned = ocrLines.map(cleanOCRLine).filter { !$0.isEmpty }
        queries.append(contentsOf: cleaned)
        if cleaned.count >= 2 {
            for index in 0..<(cleaned.count - 1) {
                queries.append(cleaned[index] + " " + cleaned[index + 1])
            }
        }
        if !cleaned.isEmpty {
            queries.append(cleaned.prefix(3).joined(separator: " "))
        }
        return uniqueNormalized(queries)
    }

    private static func cleanOCRLine(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: "[^A-Za-z0-9 '&:-]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(
            of: "\\b(19|20)\\d{2}\\b$", with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        if titleNoiseWords.contains(lower) { return "" }
        let tokens = meaningfulTokens(in: lower)
        if tokens.isEmpty { return "" }
        return value
    }

    private static func meaningfulTokens(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .filter { !titleNoiseWords.contains($0) }
    }

    private static let titleNoiseWords: Set<String> = [
        "home", "watch", "now", "showing", "only", "cinema", "movie", "movies",
        "imax", "dolby", "screen", "book", "tickets", "ticket", "coming", "soon",
        "the", "and", "for", "with", "from", "new"
    ]

    private struct OCRTextCandidate { let text: String; let score: Double }

    private static func extractLikelyTitlePhrases(from pixelBuffer: CVPixelBuffer) -> [String] {
        var weightedCandidates: [OCRTextCandidate] = []
        let baseHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        weightedCandidates.append(contentsOf: recognizeTextCandidates(using: baseHandler, variantWeight: 1.0))
        let baseImage = CIImage(cvPixelBuffer: pixelBuffer)
        for (index, variant) in ocrVariants(from: baseImage).enumerated() {
            let handler = VNImageRequestHandler(ciImage: variant, options: [:])
            let weight: Double
            switch index {
            case 1: weight = 1.2
            case 2: weight = 1.5
            case 3, 4: weight = 1.1
            default: weight = 1.0
            }
            weightedCandidates.append(contentsOf: recognizeTextCandidates(using: handler, variantWeight: weight))
        }
        var bestScoreByKey: [String: Double] = [:]
        var phraseByKey: [String: String] = [:]
        for candidate in weightedCandidates {
            let cleaned = cleanOCRLine(candidate.text)
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            if candidate.score > (bestScoreByKey[key] ?? 0) {
                bestScoreByKey[key] = candidate.score
                phraseByKey[key] = cleaned
            }
        }
        let ranked = bestScoreByKey.sorted { $0.value > $1.value }.compactMap { phraseByKey[$0.key] }
        return uniqueNormalized(Array(ranked.prefix(20)))
    }

    private static func recognizeTextCandidates(using handler: VNImageRequestHandler, variantWeight: Double) -> [OCRTextCandidate] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.005
        request.recognitionLanguages = ["en-US"]
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.flatMap { observation in
                let textHeight = Double(observation.boundingBox.height)
                let centerY = Double(observation.boundingBox.midY)
                let centerBias = 1.0 - min(abs(centerY - 0.5), 0.5) * 2.0
                return observation.topCandidates(2).map { candidate in
                    let normalizedText = candidate.string
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let hasDigit = normalizedText.rangeOfCharacter(from: .decimalDigits) != nil
                    let wordCount = normalizedText.split(separator: " ").count
                    let titleLikeBoost: Double = (hasDigit || wordCount >= 2) ? 1.4 : 0.8
                    let score = Double(candidate.confidence) * (0.8 + textHeight * 3.0 + centerBias * 1.2) * titleLikeBoost * variantWeight
                    return OCRTextCandidate(text: normalizedText, score: score)
                }
            }.filter { $0.text.count >= 3 }
        } catch { return [] }
    }

    private static func ocrVariants(from image: CIImage) -> [CIImage] {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else { return [image] }
        var variants: [CIImage] = [image]
        let contrastBoosted = image
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.15, kCIInputBrightnessKey: -0.04, kCIInputContrastKey: 1.45])
            .applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": 0.9, "inputShadowAmount": 0.2])
            .cropped(to: extent)
        variants.append(contrastBoosted)
        let centerRect = CGRect(x: extent.minX + extent.width * 0.1, y: extent.minY + extent.height * 0.08, width: extent.width * 0.8, height: extent.height * 0.84).integral
        variants.append(image.cropped(to: centerRect))
        let lowerRect = CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: extent.height * 0.62).integral
        variants.append(image.cropped(to: lowerRect))
        let upperRect = CGRect(x: extent.minX, y: extent.minY + extent.height * 0.33, width: extent.width, height: extent.height * 0.67).integral
        variants.append(image.cropped(to: upperRect))
        let mirrored = horizontallyMirrored(image, extent: extent)
        variants.append(mirrored)
        variants.append(horizontallyMirrored(contrastBoosted, extent: extent))
        variants.append(horizontallyMirrored(image.cropped(to: centerRect), extent: centerRect))
        return variants
    }

    private static func horizontallyMirrored(_ image: CIImage, extent: CGRect) -> CIImage {
        let translation = CGAffineTransform(translationX: extent.maxX + extent.minX, y: 0)
        let mirror = CGAffineTransform(scaleX: -1, y: 1)
        return image.transformed(by: mirror.concatenating(translation)).cropped(to: extent)
    }

    private static func specificLabels(from labels: [String]) -> [String] {
        let generic: Set<String> = ["poster", "movie poster", "tv poster", "advertisement", "ad", "label", "text", "graphics", "art", "design", "illustration", "image", "photo"]
        return labels.compactMap { raw in
            let normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !generic.contains(normalized), normalized.count >= 3 else { return nil }
            return normalized
        }
    }

    private static func fallbackLabels(from labels: [String]) -> [String] {
        let ignore: Set<String> = ["poster", "movie poster", "tv poster", "image", "photo", "graphic", "text"]
        return labels.compactMap { label in
            let value = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 2, !ignore.contains(value) else { return nil }
            return value
        }
    }

    private static func score(entity: VisualPosterMatchEntity, with queries: [String], posterQuery: String) -> Int {
        let title = entity.title.lowercased()
        let overview = (entity.overview ?? "").lowercased()
        var score = 0
        if entity.mediaType == .movie, posterQuery.contains("poster") { score += 4 }
        if posterQuery.contains("legends"), title.contains("legends") { score += 3 }
        else if !posterQuery.contains("legends"), title.contains("legends") { score -= 6 }
        for query in queries {
            let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = meaningfulTokens(in: normalizedQuery)
            guard !tokens.isEmpty else { continue }
            let hasMultipleMeaningfulTokens = tokens.count >= 2
            let containsDigit = normalizedQuery.rangeOfCharacter(from: .decimalDigits) != nil
            if normalizedQuery.count >= 5, (hasMultipleMeaningfulTokens || containsDigit), title.contains(normalizedQuery) { score += 20 }
            for token in tokens {
                if title.contains(token) { score += hasMultipleMeaningfulTokens ? 4 : 1 }
                else if overview.contains(token) { score += 1 }
            }
        }
        return score
    }

    private static func enrichWithPosterData(_ entities: [VisualPosterMatchEntity], limit: Int) async -> [VisualPosterMatchEntity] {
        guard !entities.isEmpty else { return entities }
        let prefix = Array(entities.prefix(limit))
        let suffix = Array(entities.dropFirst(limit))
        var enrichedByID: [String: Data] = [:]
        await withTaskGroup(of: (String, Data?).self) { group in
            for entity in prefix {
                group.addTask {
                    guard let posterPath = entity.posterPath else { return (entity.id, nil) }
                    guard let url = TMDBService.shared.imageURL(path: posterPath, size: .small) else { return (entity.id, nil) }
                    do { let (data, _) = try await URLSession.shared.data(from: url); return (entity.id, data) }
                    catch { return (entity.id, nil) }
                }
            }
            for await (id, data) in group {
                if let data, !data.isEmpty { enrichedByID[id] = data }
            }
        }
        let enrichedPrefix = prefix.map { entity in
            VisualPosterMatchEntity(id: entity.id, mediaId: entity.mediaId, mediaType: entity.mediaType, title: entity.title, year: entity.year, overview: entity.overview, posterPath: entity.posterPath, posterData: enrichedByID[entity.id])
        }
        return enrichedPrefix + suffix
    }
}

@available(iOS 18.0, *)
struct OpenVisualPosterMatchIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open in WatchGuide"
    static var description = IntentDescription("Open a matched movie or TV show in WatchGuide and optionally add it to watchlist.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Title")
    var target: VisualPosterMatchEntity

    @Parameter(title: "Action")
    var action: VisualPosterAction?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard PlatformCompatibility.supportsVisualIntelligence else { return .result() }
        let mappedAction: VisualIntentAction
        switch action ?? .openDetails {
        case .openDetails: mappedAction = .openDetails
        case .openTrailer: mappedAction = .openTrailer
        case .addToWatchlist: mappedAction = .addToWatchlist
        }
        await VisualIntentRouteCenter.shared.queue(
            VisualIntentRoute(mediaId: target.mediaId, mediaType: target.mediaType, action: mappedAction)
        )
        return .result()
    }
}
#endif // canImport(VisualIntelligence)

// These intents do NOT depend on VisualIntelligence — only AppIntents.
@available(iOS 18.0, *)
struct OpenWatchGuideIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Watch Guide"
    static var description = IntentDescription("Open the Watch Guide app.")
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult { return .result() }
}

@available(iOS 18.0, *)
struct WatchGuideAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenWatchGuideIntent(),
            phrases: ["Open \(.applicationName)", "Show \(.applicationName)", "Launch \(.applicationName)"],
            shortTitle: "Open Watch Guide",
            systemImageName: "popcorn.fill"
        )
    }
}
#endif // os(iOS) && !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
