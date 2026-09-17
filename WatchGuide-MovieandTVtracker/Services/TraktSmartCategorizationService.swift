//
//  TraktSmartCategorizationService.swift
//  WatchGuide-MovieandTVtracker
//
//  Data pipeline:
//    Trakt-synced SavedMediaItem array
//      → enrich()          adds recency, quality, and type signals
//      → buildRichPrompt() formats into a structured text block
//      → LanguageModelSession / cloud AI provider
//      → @Generable SmartCategorizationOutput
//      → applyCategories() creates CustomList entries in StorageService
//

import Foundation

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

// MARK: - @Generable output schema
//
// These two structs define the exact shape the on-device model must produce.
// `@Generable` uses constrained sampling so the output is always valid —
// no JSON parsing, no try/catch around decode.

#if canImport(FoundationModels) && !os(tvOS)
@available(iOS 18.0, macOS 15.0, *)
@Generable(description: "A smart custom viewing list derived from watch history")
struct SmartCategory {
    @Guide(description: "Creative, evocative list name that reflects a real pattern — e.g. 'Sunday Morning Comfort Shows', 'Late-Night Thriller Binges', 'All-Time Favourites'")
    var name: String

    @Guide(description: "One sentence that explains what unites this list")
    var listDescription: String

    @Guide(description: "SF Symbol icon name, e.g. sofa.fill, bolt.fill, moon.stars.fill, crown.fill, film.fill, popcorn.fill")
    var iconName: String

    @Guide(description: "Exact titles from the watch history that belong in this list")
    var matchingTitles: [String]
}

@available(iOS 18.0, macOS 15.0, *)
@Generable(description: "Full smart-categorisation result")
struct SmartCategorizationOutput {
    @Guide(description: "3 to 5 distinct, creative categories based on the viewing history")
    var categories: [SmartCategory]
}
#endif

// MARK: - Enriched watch entry
//
// Before sending titles to the model we attach three extra signals:
//   • recencyLabel  — how recently the user watched it (from SavedMediaItem.addedAt)
//   • qualityHint   — "highly rated" when TMDB voteAverage ≥ 8.0
//   • typeLabel     — "Movie" or "TV Show"
//
// Example prompt line:
//   Interstellar (Movie, 2014) — watched this month — highly rated

private struct WatchEntry {
    let item: SavedMediaItem
    let recencyLabel: String
    let qualityHint: String?

    // The single line that goes into the prompt for this title.
    var promptLine: String {
        let year    = item.year.map { ", \($0)" } ?? ""
        let type    = item.mediaType == .movie ? "Movie" : "TV Show"
        var line    = "\(item.title) (\(type)\(year)) — watched \(recencyLabel)"
        if let q = qualityHint { line += " — \(q)" }
        return line
    }
}

// MARK: - Errors

enum SmartCategorizationError: LocalizedError {
    case appleIntelligenceUnavailable
    case unsupportedLocale
    case emptyHistory

    var errorDescription: String? {
        switch self {
        case .appleIntelligenceUnavailable:
            return "Apple Intelligence isn't available on this device. Enable it in Settings > Apple Intelligence & Siri."
        case .unsupportedLocale:
            return "Apple Intelligence doesn't support your current language for this feature."
        case .emptyHistory:
            return "Your watch history is empty. Mark some titles as watched first."
        }
    }
}

// MARK: - Service

actor TraktSmartCategorizationService {
    static let shared = TraktSmartCategorizationService()
    private init() {}

    /// On-device only path — used by the Siri App Intent.
    /// Throws `SmartCategorizationError` if Apple Intelligence is unavailable so
    /// the intent can return a human-readable Siri dialog instead of a crash.
    func generateSmartListsOnDevice() async throws -> Int {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 18.0, macOS 15.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw SmartCategorizationError.appleIntelligenceUnavailable
            }
            guard model.supportsLocale(Locale.current) else {
                throw SmartCategorizationError.unsupportedLocale
            }
            return try await generateSmartListsUsing(.foundationModels)
        }
        #endif
        throw SmartCategorizationError.appleIntelligenceUnavailable
    }

    /// Full path — used by the in-app wand button.
    /// Falls back to a cloud AI provider when Apple Intelligence is unavailable.
    func generateSmartLists() async throws -> Int {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 18.0, macOS 15.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability, model.supportsLocale(Locale.current) {
                return try await generateSmartListsUsing(.foundationModels)
            }
        }
        #endif
        return try await generateSmartListsUsing(.cloudAPI)
    }

    // MARK: - Shared core

    private enum GenerationBackend { case foundationModels, cloudAPI }

    private func generateSmartListsUsing(_ backend: GenerationBackend) async throws -> Int {
        // 1. Collect — Trakt-resolved SavedMediaItem objects already in StorageService
        let watched = await MainActor.run { StorageService.shared.watched }
        let liked   = await MainActor.run { StorageService.shared.liked }

        var seen     = Set<String>()
        var combined = [SavedMediaItem]()
        for item in (liked + watched) where seen.insert(item.id).inserted {
            combined.append(item)
        }
        guard !combined.isEmpty else { return 0 }
        let capped = Array(combined.prefix(60))

        // 2. Enrich each item with recency and quality signals
        let entries = enrich(capped)

        // 3. Generate categories via the chosen backend
        let categories: [SmartCategoryData]
        switch backend {
        case .foundationModels:
            #if canImport(FoundationModels) && !os(tvOS)
            if #available(iOS 18.0, macOS 15.0, *) {
                categories = try await generateWithFoundationModels(entries: entries)
            } else {
                throw SmartCategorizationError.appleIntelligenceUnavailable
            }
            #else
            throw SmartCategorizationError.appleIntelligenceUnavailable
            #endif
        case .cloudAPI:
            categories = try await generateWithCloudAPI(entries: entries)
        }

        // 4. Map back to SavedMediaItems and write CustomLists to StorageService
        return try await applyCategories(categories, from: capped)
    }

    // MARK: - Step 2: Enrich raw items with signals

    private func enrich(_ items: [SavedMediaItem]) -> [WatchEntry] {
        let now      = Date()
        let calendar = Calendar.current

        return items.map { item in
            // Recency derived from addedAt (the date Trakt sync wrote the item)
            let daysAgo = calendar.dateComponents([.day], from: item.addedAt, to: now).day ?? 999
            let recency: String = switch daysAgo {
            case ..<7:    "this week"
            case ..<30:   "this month"
            case ..<90:   "in the last few months"
            case ..<365:  "earlier this year"
            default:      "a while ago"
            }

            // Quality signal from TMDB community score stored on the item
            let quality: String? = (item.voteAverage ?? 0) >= 8.0 ? "highly rated" : nil

            return WatchEntry(item: item, recencyLabel: recency, qualityHint: quality)
        }
    }

    // MARK: - Step 3a: Build the structured text prompt

    private func buildRichPrompt(from entries: [WatchEntry]) -> String {
        let lines = entries.map(\.promptLine).joined(separator: "\n")
        return """
        Watch history — each line: title (type, year) — recency — quality:
        \(lines)

        Using the recency and quality signals above, create 3 to 5 smart custom lists. \
        Look for patterns such as: recent binge sessions, comfort rewatches, \
        genre clusters, mood-based groups, or all-time highly rated picks. \
        Only use titles that appear verbatim in the list above.
        """
    }

    // MARK: - Step 3b: FoundationModels path (on-device, privacy-preserving)

    #if canImport(FoundationModels) && !os(tvOS)
    @available(iOS 18.0, macOS 15.0, *)
    private func generateWithFoundationModels(entries: [WatchEntry]) async throws -> [SmartCategoryData] {
        let model = SystemLanguageModel.default

        // System instructions set the persona and rules once;
        // the per-request prompt carries the actual data.
        let instructions = """
        You are a personalized viewing curator running entirely on-device. \
        Analyse the user's watch history — including recency (when they watched) \
        and quality (how highly rated) — to create insightful smart lists. \
        Patterns to look for:
        • Genre or mood clusters (action, sci-fi, comfort TV, dark thrillers)
        • Recency: recent discoveries or current obsessions vs. all-time classics
        • Quality filters: only the highest-rated picks the user has seen
        • Binge groups: a cluster of related titles watched closely together
        Rules:
        — Only assign titles that appear verbatim in the input.
        — Keep list names short, evocative, and specific.
        — Descriptions must be one sentence.
        """

        let session  = LanguageModelSession(model: model, instructions: instructions)
        let prompt   = buildRichPrompt(from: entries)

        // respond(to:generating:) uses constrained sampling — the model is
        // structurally forced to emit valid SmartCategorizationOutput JSON.
        let response = try await session.respond(to: prompt, generating: SmartCategorizationOutput.self)

        return response.content.categories.map {
            SmartCategoryData(
                name: $0.name,
                listDescription: $0.listDescription,
                iconName: $0.iconName,
                matchingTitles: $0.matchingTitles
            )
        }
    }
    #endif

    // MARK: - Step 3c: Cloud fallback (when Apple Intelligence unavailable)

    private func generateWithCloudAPI(entries: [WatchEntry]) async throws -> [SmartCategoryData] {
        let provider = AtlasAIProvider.gemini
        let apiKey = provider.apiKey
        guard !apiKey.isEmpty else { throw AIError.noApiKey }

        let systemPrompt = """
        You are a personalized viewing curator. Given a watch history with recency and quality signals, \
        create 3 to 5 smart custom lists based on genuine patterns. \
        Only assign titles from the input. No explanation, no code fences. \
        Respond ONLY with a raw JSON array: \
        [{"name":"...","listDescription":"...","iconName":"...","matchingTitles":["..."]}]
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user",   "content": buildRichPrompt(from: entries)]
        ]

        let body: [String: Any] = [
            "model":      "gemini-2.5-flash-lite",
            "messages":   messages,
            "max_tokens": 2000,
            "temperature": 0.7,
            "stream":     false
        ]

        guard let url = URL(string: provider.baseURL) else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AIError.invalidResponse
        }

        let llm = try JSONDecoder().decode(LLMResponse.self, from: data)
        guard var content = llm.choices.first?.message.content, !content.isEmpty else {
            throw AIError.noContent
        }

        // Strip any markdown fences the model added despite instructions
        content = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = content.firstIndex(of: "["), let end = content.lastIndex(of: "]") {
            content = String(content[start...end])
        }

        struct CategoryPayload: Codable {
            let name: String
            let listDescription: String
            let iconName: String
            let matchingTitles: [String]
        }

        let parsed = try JSONDecoder().decode([CategoryPayload].self, from: Data(content.utf8))
        return parsed.map {
            SmartCategoryData(
                name: $0.name,
                listDescription: $0.listDescription,
                iconName: $0.iconName,
                matchingTitles: $0.matchingTitles
            )
        }
    }

    // MARK: - Step 4: Map model output back to SavedMediaItems → CustomList

    private func applyCategories(_ categories: [SmartCategoryData], from items: [SavedMediaItem]) async throws -> Int {
        let existingNames = Set(await MainActor.run {
            StorageService.shared.customLists.map { $0.name.lowercased() }
        })

        // O(1) lookup by lowercased title
        let byTitle: [String: SavedMediaItem] = Dictionary(
            items.map { ($0.title.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var listsCreated = 0

        for cat in categories {
            guard !cat.name.isEmpty,
                  !existingNames.contains(cat.name.lowercased()) else { continue }

            // Match each model-generated title back to its SavedMediaItem.
            // Try exact lowercase first; fall back to substring containment.
            let matched: [SavedMediaItem] = cat.matchingTitles.compactMap { title in
                let lower = title.lowercased()
                if let exact = byTitle[lower] { return exact }
                return items.first {
                    $0.title.lowercased().contains(lower) || lower.contains($0.title.lowercased())
                }
            }

            // Preserve order, remove duplicates
            var deduped  = [SavedMediaItem]()
            var seenIds  = Set<String>()
            for item in matched where seenIds.insert(item.id).inserted {
                deduped.append(item)
            }
            guard !deduped.isEmpty else { continue }

            let icon = isValidSymbolName(cat.iconName) ? cat.iconName : "sparkles"

            let list = await MainActor.run {
                StorageService.shared.createCustomListAndReturn(
                    name: cat.name,
                    description: cat.listDescription,
                    iconName: icon
                )
            }
            guard let list else { continue }

            let itemsToAdd = deduped
            await MainActor.run {
                for item in itemsToAdd {
                    StorageService.shared.addToCustomList(listId: list.id, item: item)
                }
            }

            listsCreated += 1
        }

        return listsCreated
    }

    // MARK: - Internal transfer type

    private struct SmartCategoryData {
        let name: String
        let listDescription: String
        let iconName: String
        let matchingTitles: [String]
    }

    // Guard against the model hallucinating a multi-word or empty icon name
    private func isValidSymbolName(_ name: String) -> Bool {
        !name.isEmpty && name.count < 60 && !name.contains(" ")
    }
}
