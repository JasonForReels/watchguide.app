//
//  AIService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

// MARK: - For You @Generable schema
//
// On-device recommendation output. `@Generable` uses constrained sampling so the
// model is structurally forced to emit a valid result — no JSON parsing required.
#if canImport(FoundationModels) && !os(tvOS)
@available(iOS 18.0, macOS 15.0, *)
@Generable(description: "A single movie or TV show recommendation")
struct ForYouRecommendation {
    @Guide(description: "The exact title of a real movie or TV show the user would enjoy")
    var title: String

    @Guide(description: "The type of the title — either \"movie\" or \"tv\"")
    var type: String
}

@available(iOS 18.0, macOS 15.0, *)
@Generable(description: "Personalized For You recommendations")
struct ForYouRecommendationOutput {
    @Guide(description: "Exactly 10 recommended titles the user would enjoy and has not already liked")
    var recommendations: [ForYouRecommendation]
}
#endif

// MARK: - AI Providers & Model Catalog

/// Backend an AI model is served from. Every provider here exposes an
/// OpenAI-compatible `/chat/completions` endpoint, so the request building and
/// SSE parsing are shared — only the URL, key, and web-search hook differ.
///
/// Poe is metered against a personal Poe subscription rather than per-token
/// billing, so its models only appear once a `POE_API_KEY` is present.
enum AtlasAIProvider: String, Codable, CaseIterable {
    case openrouter
    case gemini
    case huggingface
    case cloudflare
    case poe

    var baseURL: String {
        switch self {
        case .openrouter: return "https://openrouter.ai/api/v1/chat/completions"
        // Google's OpenAI-compatible Gemini endpoint — same request/SSE shape.
        case .gemini:     return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        // Hugging Face Inference Providers OpenAI-compatible router.
        case .huggingface: return "https://router.huggingface.co/v1/chat/completions"
        // Cloudflare Workers AI OpenAI-compatible endpoint. The account ID is part
        // of the path, so it's injected from the catalog (Keychain or bundled).
        case .cloudflare:
            return "https://api.cloudflare.com/client/v4/accounts/\(AIModelCatalog.cloudflareAccountId)/ai/v1/chat/completions"
        // Poe's OpenAI-compatible endpoint. Model ids are Poe bot names.
        case .poe:        return "https://api.poe.com/v1/chat/completions"
        }
    }

    var apiKeyName: String {
        switch self {
        case .openrouter: return "OPENROUTER_API_KEY"
        case .gemini:     return "GEMINI_API_KEY"
        case .huggingface: return "HUGGINGFACE_API_KEY"
        case .cloudflare: return "CLOUDFLARE_API_KEY"
        case .poe:        return "POE_API_KEY"
        }
    }

    var displayName: String {
        switch self {
        case .openrouter: return "OpenRouter"
        case .gemini:     return "Google Gemini"
        case .huggingface: return "Hugging Face"
        case .cloudflare: return "Cloudflare Workers AI"
        case .poe:        return "Poe"
        }
    }

    /// Resolved API key — Keychain first, falling back to the bundled default.
    var apiKey: String {
        let stored = ApiKeyManager.shared.get(key: apiKeyName) ?? ""
        if !stored.isEmpty { return stored }
        switch self {
        case .openrouter:  return AIModelCatalog.bundledOpenRouterKey
        case .gemini:      return AIModelCatalog.bundledGeminiKey
        case .huggingface: return AIModelCatalog.bundledHuggingFaceKey
        case .cloudflare:  return AIModelCatalog.bundledCloudflareKey
        case .poe:         return AIModelCatalog.bundledPoeKey
        }
    }
}

/// A user-selectable model shown in the Atlas model picker.
struct AIModelOption: Identifiable, Hashable {
    let id: String            // "auto", or the model id sent to the API
    let displayName: String
    let provider: AtlasAIProvider
    let supportsThinking: Bool
    let isAutomatic: Bool      // the "Auto" entry picks a model per message
}

/// Catalog of every model the picker can offer, plus the persisted-selection key.
enum AIModelCatalog {
    /// Bundled OpenRouter key, used when the Keychain has none. Persisted on first use.
    static let bundledOpenRouterKey = ""

    /// Bundled Google Gemini API key, used when the Keychain has none.
    static let bundledGeminiKey = ""

    /// Bundled Hugging Face token (needs "Make calls to Inference Providers"
    /// permission). Paste an `hf_…` token here to enable the Hugging Face models.
    static let bundledHuggingFaceKey = ""

    /// Bundled Cloudflare Workers AI API token — the same token used for image
    /// generation in CloudflareImageService. A Workers AI token works for both
    /// the `/ai/run/` (images) and `/ai/v1/chat/completions` (text) endpoints.
    static let bundledCloudflareKey = ""

    /// Bundled Poe key. Deliberately empty: unlike the other providers, Poe's key
    /// ships encrypted in `ENCRYPTED_KEYS.plist` as `POE_API_KEY` and is decrypted
    /// into the Keychain by `ApiKeyManager` at launch, so there's no plaintext key
    /// in source. This constant only exists so the provider's key lookup and
    /// `persistKey` have the same shape as the others.
    static let bundledPoeKey = ""

    /// Cloudflare account ID — required because it's part of the Workers AI URL.
    /// Same account used by CloudflareImageService.
    static let bundledCloudflareAccountId = "b91363256309bc68156bb2e194d96cbf"

    /// Resolved Cloudflare account ID — Keychain first, then the bundled default.
    static var cloudflareAccountId: String {
        let stored = ApiKeyManager.shared.get(key: "CLOUDFLARE_ACCOUNT_ID") ?? ""
        return stored.isEmpty ? bundledCloudflareAccountId : stored
    }

    /// TEMP: when non-nil, every request is forced to this single model and the
    /// picker shows only it — all other models are disabled. Set to `nil` to
    /// restore Auto + the full model list.
    ///
    /// Currently `nil`: Atlas defaults to OpenRouter's Auto router, which picks a
    /// model per request, with Gemini grounding for live/rumour queries.
    static let forcedModelId: String? = nil

    /// UserDefaults key the picker writes and `AIService` reads.
    static let selectionDefaultsKey = "preferredAIModelId"

    /// Sentinel id — `resolveModel` intercepts "auto" and picks a model per
    /// message via `automaticScoutModel` rather than sending "auto" to a provider.
    /// Kept as its own id (not "openrouter/auto") so existing stored selections
    /// and the picker's default keep working, and so it doesn't collide with the
    /// explicit "Auto Router" entry below.
    static let auto = AIModelOption(
        id: "auto", displayName: "Auto", provider: .gemini,
        supportsThinking: false, isAutomatic: true
    )

    static let openRouterModels: [AIModelOption] = [
        AIModelOption(id: "openrouter/fusion", displayName: "Fusion", provider: .openrouter, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "openrouter/auto", displayName: "Auto Router", provider: .openrouter, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "anthropic/claude-sonnet-4", displayName: "Claude Sonnet 4", provider: .openrouter, supportsThinking: true, isAutomatic: false),
        AIModelOption(id: "openai/gpt-5", displayName: "GPT-5", provider: .openrouter, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "google/gemini-2.5-flash", displayName: "Gemini 2.5 Flash", provider: .openrouter, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "x-ai/grok-4.6", displayName: "Grok 4.6", provider: .openrouter, supportsThinking: true, isAutomatic: false),
        AIModelOption(id: "openai/gpt-5-nano", displayName: "GPT-5 Nano", provider: .openrouter, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "deepseek/deepseek-chat-v3.1", displayName: "DeepSeek V3.1", provider: .openrouter, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "meta-llama/llama-4-maverick", displayName: "Llama 4 Maverick", provider: .openrouter, supportsThinking: false, isAutomatic: false)
    ]

    /// Zero-token-cost OpenRouter models (the `:free` tier). Rate-limited and the
    /// roster rotates, so `openrouter/free` (a router over whatever is free right
    /// now) leads the list as the robust default. Note: attaching the web plugin
    /// is still billed even on these — true free web search uses the RAG path.
    /// Verified live against OpenRouter's `/models` endpoint. The roster rotates
    /// often — most of the previous entries here (DeepSeek R1, Llama 3.3 70B,
    /// Qwen3 Coder, Mistral Small, Gemma 3) had already been retired and were
    /// returning errors. Re-check this list when models start failing.
    static let openRouterFreeModels: [AIModelOption] = [
        AIModelOption(id: "openrouter/free", displayName: "Free Auto Router", provider: .openrouter, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "nvidia/nemotron-3-ultra-550b-a55b:free", displayName: "Nemotron 3 Ultra (Free)", provider: .openrouter, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "nvidia/nemotron-3-super-120b-a12b:free", displayName: "Nemotron 3 Super (Free)", provider: .openrouter, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "google/gemma-4-31b-it:free", displayName: "Gemma 4 31B (Free)", provider: .openrouter, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "google/gemma-4-26b-a4b-it:free", displayName: "Gemma 4 26B (Free)", provider: .openrouter, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "openai/gpt-oss-20b:free", displayName: "GPT-OSS 20B (Free)", provider: .openrouter, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "nvidia/nemotron-nano-12b-v2-vl:free", displayName: "Nemotron Nano 12B VL (Free)", provider: .openrouter, supportsThinking: false, isAutomatic: false)
    ]

    /// Google Gemini models served via Google's native API (OpenAI-compatible endpoint).
    static let geminiModels: [AIModelOption] = [
        AIModelOption(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", provider: .gemini, supportsThinking: true, isAutomatic: false),
        // Flash-Lite has the higher free ceiling (1,000/day, 15 RPM vs 250/day, 10 RPM).
        AIModelOption(id: "gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash Lite", provider: .gemini, supportsThinking: false, isAutomatic: false)
    ]

    /// Hugging Face Inference Providers models (OpenAI-compatible router).
    /// IDs are `org/model-name`; the router auto-routes to the fastest backend.
    static let huggingFaceModels: [AIModelOption] = [
        AIModelOption(id: "meta-llama/Llama-3.3-70B-Instruct", displayName: "Llama 3.3 70B", provider: .huggingface, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "deepseek-ai/DeepSeek-R1", displayName: "DeepSeek R1", provider: .huggingface, supportsThinking: true, isAutomatic: false),
        AIModelOption(id: "Qwen/Qwen2.5-72B-Instruct", displayName: "Qwen 2.5 72B", provider: .huggingface, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "openai/gpt-oss-120b", displayName: "GPT-OSS 120B", provider: .huggingface, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "moonshotai/Kimi-K2-Instruct-0905", displayName: "Kimi K2", provider: .huggingface, supportsThinking: false, isAutomatic: false)
    ]

    /// Cloudflare Workers AI models (OpenAI-compatible endpoint). Billed in
    /// Neurons — Granite 4.0 Micro is the cheapest text model on the platform
    /// (1,542 neurons/M input, 10,158 neurons/M output) and supports tool use.
    /// Web search comes from the keyless RAG path, like the other free providers.
    static let cloudflareModels: [AIModelOption] = [
        AIModelOption(id: "@cf/ibm-granite/granite-4.0-h-micro", displayName: "Granite 4.0 Micro (Cheapest)", provider: .cloudflare, supportsThinking: false, isAutomatic: false)
    ]

    /// Poe models, served over Poe's OpenAI-compatible endpoint. Ids are Poe bot
    /// names exactly as Poe spells them.
    static let poeModels: [AIModelOption] = [
        AIModelOption(id: "Gemini-2.5-Flash", displayName: "Gemini 2.5 Flash (Poe)", provider: .poe, supportsThinking: true, isAutomatic: false),
        AIModelOption(id: "Claude-Sonnet-4.5", displayName: "Claude Sonnet 4.5 (Poe)", provider: .poe, supportsThinking: true, isAutomatic: false),
        AIModelOption(id: "GPT-5", displayName: "GPT-5 (Poe)", provider: .poe, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "GPT-5-nano", displayName: "GPT-5 Nano (Poe)", provider: .poe, supportsThinking: false, isAutomatic: false),
        AIModelOption(id: "Web-Search", displayName: "Web Search (Poe)", provider: .poe, supportsThinking: false, isAutomatic: false)
    ]

    /// True when Poe has a usable key — Keychain first, then the bundled default.
    static var isPoeConfigured: Bool {
        !AtlasAIProvider.poe.apiKey.isEmpty
    }

    /// Every model that exists, ignoring the temporary forced-model switch.
    static var allFull: [AIModelOption] {
        [auto] + openRouterModels + openRouterFreeModels + geminiModels + huggingFaceModels + cloudflareModels + poeModels
    }

    /// Models shown in the picker. When a model is forced, only that one appears.
    static var all: [AIModelOption] {
        if let forcedModelId, let forced = allFull.first(where: { $0.id == forcedModelId }) {
            return [forced]
        }
        return allFull
    }

    static func option(id: String) -> AIModelOption? { allFull.first { $0.id == id } }

    /// Models offered in the Atlas picker beside "Auto".
    ///
    /// Deliberately Gemini-only: the bundled OpenRouter key belongs to an account
    /// with no credits, so every paid OpenRouter model returns 402. Those entries
    /// stay in `openRouterModels` for anyone who supplies their own key, but the
    /// picker must not hand users a model that cannot answer.
    /// Poe joins the picker only when a key is configured; without one every Poe
    /// request would 401, and the picker must not offer a model that can't answer.
    static var chatModels: [AIModelOption] {
        isPoeConfigured ? geminiModels + poeModels : geminiModels
    }

    /// Whether a model id is a zero-token-cost OpenRouter free-tier model.
    static func isFreeModel(_ id: String) -> Bool {
        id == "openrouter/free" || id.hasSuffix(":free")
    }
}

actor AIService {
    static let shared = AIService()
    
    private init() {}

    /// True when at least one provider has a usable key. Providers carry bundled
    /// keys, so this is normally true — it goes false only if every key is blank.
    var isAvailable: Bool {
        AtlasAIProvider.allCases.contains { !$0.apiKey.isEmpty }
    }

    // MARK: - Available Models
    enum ChronModel: String, CaseIterable {
        /// Cheapest/highest-quota flavour — the default workhorse.
        case geminiFlashLite = "gemini-2.5-flash-lite"
        /// Live/current-info queries; served by a model with search grounding.
        case webGrounded = "web-grounded"
        /// Heavier reasoning and multimodal turns.
        case deepReasoning = "deep-reasoning"

        var displayName: String {
            switch self {
            case .geminiFlashLite: return "Gemini 2.5 Flash Lite"
            case .webGrounded:     return "Gemini 2.5 Flash (Web)"
            case .deepReasoning:   return "Gemini 2.5 Flash"
            }
        }

        /// Provider that serves this flavour. These used to be implicitly Poe;
        /// each now maps to an equivalent on a provider we actually ship.
        var provider: AtlasAIProvider { .gemini }

        /// Model id as the serving provider names it. `rawValue` is kept as the
        /// stable internal flavour name so prompt styling and persisted values
        /// don't change; this is what actually goes on the wire.
        var providerModelId: String {
            switch self {
            case .geminiFlashLite: return "gemini-2.5-flash-lite"
            // 2.5 Flash carries Google Search grounding and accepts images, which
            // the web-search and image-attachment paths both depend on.
            case .webGrounded:     return "gemini-2.5-flash"
            case .deepReasoning:   return "gemini-2.5-flash"
            }
        }

        var modelName: String {
            return self.rawValue
        }

        var supportsThinking: Bool {
            switch self {
            case .deepReasoning, .webGrounded: return true
            case .geminiFlashLite: return false
            }
        }
    }
    
    // MARK: - Chat Message
    struct ChatMessage: Codable, Identifiable {
        let id: String
        let role: String
        var content: String
        let timestamp: Date
        var trailerKey: String?
        var trailerTitle: String?
        var thinkingContent: String?
        /// Base64-encoded JPEGs of images the user attached to this message (for
        /// display in the bubble). The images are sent to the model separately.
        var imageBase64s: [String]?

        init(role: String, content: String, trailerKey: String? = nil, trailerTitle: String? = nil, thinkingContent: String? = nil, imageBase64s: [String]? = nil) {
            self.id = UUID().uuidString
            self.role = role
            self.content = content
            self.timestamp = Date()
            self.trailerKey = trailerKey
            self.trailerTitle = trailerTitle
            self.thinkingContent = thinkingContent
            self.imageBase64s = imageBase64s
        }
    }
    
    // MARK: - Trailer Response
    struct TrailerResponse {
        let content: String
        let trailerKey: String
        let trailerTitle: String
    }
    
    // MARK: - Fetch Trailer by Title (public, for post-processing)
    /// Searches TMDB for the given title and returns the best trailer video key + title.
    func fetchTrailer(for title: String) async -> (key: String, title: String)? {
        do {
            let searchResults = try await TMDBService.shared.searchMulti(query: title)
            guard let bestMatch = searchResults.results.first(where: { $0.resolvedMediaType == .movie || $0.resolvedMediaType == .tv }) else { return nil }
            
            let videos: VideosResponse
            let displayTitle: String
            
            if bestMatch.resolvedMediaType == .movie {
                videos = try await TMDBService.shared.getMovieVideos(id: bestMatch.id)
                displayTitle = bestMatch.title ?? bestMatch.name ?? title
            } else {
                videos = try await TMDBService.shared.getTVShowVideos(id: bestMatch.id)
                displayTitle = bestMatch.name ?? bestMatch.title ?? title
            }
            
            let trailer = selectBestTrailer(from: videos.results, preferFirst: false)
            guard let selected = trailer else { return nil }
            
            return (selected.key, displayTitle)
        } catch {
            print("fetchTrailer failed for '\(title)': \(error)")
            return nil
        }
    }
    
    /// Strips app control tags from text that is about to be shown to the user.
    ///
    /// The typed extractors below pull out the tags we act on, but they only run
    /// once the response is complete. While a reply streams in, a tag arrives
    /// character by character — so the raw `[TRAILER:` … `]` is visible in the
    /// bubble until the stream ends. This also catches tags the model invents or
    /// malforms, which no extractor would match and which would otherwise stay on
    /// screen permanently.
    ///
    /// Only ALL-CAPS `[NAME:` … `]` tags are removed, so markdown links such as
    /// `[Dune](https://…)` are left untouched.
    static func strippingControlTags(_ text: String) -> String {
        var cleaned = text
        // Complete tags anywhere in the text.
        cleaned = cleaned.replacingOccurrences(
            of: "\\[[A-Z][A-Z0-9_]*:[^\\]]*\\]",
            with: "",
            options: .regularExpression
        )
        // A tag still being streamed: opening bracket with no closing one yet.
        cleaned = cleaned.replacingOccurrences(
            of: "\\[[A-Z][A-Z0-9_]*(:[^\\]]*)?$",
            with: "",
            options: .regularExpression
        )
        // Collapse the blank lines a removed trailing tag leaves behind.
        cleaned = cleaned.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts [TRAILER:Title] tags from AI response text.
    /// Returns array of titles and the cleaned text with tags removed.
    static func extractTrailerTags(from text: String) -> (cleanedText: String, titles: [String]) {
        var cleaned = text
        var titles: [String] = []
        
        // Match [TRAILER:Some Title Here]
        let pattern = "\\[TRAILER:([^\\]]+)\\]"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            for match in matches.reversed() {
                if let titleRange = Range(match.range(at: 1), in: cleaned),
                   let fullRange = Range(match.range, in: cleaned) {
                    let title = String(cleaned[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty {
                        titles.insert(title, at: 0)
                    }
                    cleaned.replaceSubrange(fullRange, with: "")
                }
            }
        }
        
        // Clean up leftover whitespace
        cleaned = cleaned
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return (cleaned, titles)
    }
    
    // MARK: - Filter Panel Model
    struct AIFilterPanel {
        var title: String
        var companyOptions: [String]
        var company: String
        var yearFromOptions: [String]
        var yearFrom: String
        var genreOptions: [String]
        var genre: String
        var streamingOptions: [String]
        var streaming: String
    }

    /// Extracts [FILTER_PANEL:title=X|company_opts=A,B|company=A|year_opts=2000,2010|year_from=2000|genre_opts=Action,Drama|genre=Action|streaming_opts=Netflix,Disney+|streaming=Disney+] tag.
    static func extractFilterPanelTag(from text: String) -> (cleanedText: String, panel: AIFilterPanel?) {
        var cleaned = text
        let pattern = "\\[FILTER_PANEL:([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let innerRange = Range(match.range(at: 1), in: cleaned),
              let fullRange = Range(match.range, in: cleaned) else {
            return (cleaned, nil)
        }

        var title = "", company = "", yearFrom = "", genre = "", streaming = ""
        var companyOptions: [String] = []
        var yearFromOptions: [String] = []
        var genreOptions: [String] = []
        var streamingOptions: [String] = []

        for pair in cleaned[innerRange].components(separatedBy: "|") {
            let kv = pair.components(separatedBy: "=")
            guard kv.count >= 2 else { continue }
            let key   = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = kv[1...].joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
            func opts(_ raw: String) -> [String] {
                raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            switch key {
            case "title":          title          = value
            case "company_opts":   companyOptions  = opts(value)
            case "company":        company         = value
            case "year_opts":      yearFromOptions = opts(value)
            case "year_from":      yearFrom        = value
            case "genre_opts":     genreOptions    = opts(value)
            case "genre":          genre           = value
            case "streaming_opts": streamingOptions = opts(value)
            case "streaming":      streaming       = value
            default: break
            }
        }

        cleaned.replaceSubrange(fullRange, with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        let panel = AIFilterPanel(
            title: title,
            companyOptions: companyOptions, company: company,
            yearFromOptions: yearFromOptions, yearFrom: yearFrom,
            genreOptions: genreOptions, genre: genre,
            streamingOptions: streamingOptions, streaming: streaming
        )
        return (cleaned, panel)
    }

    /// Extracts [PLAYLIST:Title1|Title2|Title3] tags from AI response text.
    /// Returns array of titles and the cleaned text with tags removed.
    static func extractPlaylistTags(from text: String) -> (cleanedText: String, titles: [String]) {
        var cleaned = text
        var titles: [String] = []
        
        let pattern = "\\[PLAYLIST:([^\\]]+)\\]"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            for match in matches.reversed() {
                if let listRange = Range(match.range(at: 1), in: cleaned),
                   let fullRange = Range(match.range, in: cleaned) {
                    let listStr = String(cleaned[listRange])
                    let items = listStr.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    titles.append(contentsOf: items)
                    cleaned.replaceSubrange(fullRange, with: "")
                }
            }
        }
        
        cleaned = cleaned
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        return (cleaned, titles)
    }
    
    // MARK: - Stream Callback
    enum StreamEvent {
        case thinking(String)       // Accumulated thinking text
        case content(String)        // Accumulated content text
        case done                   // Stream finished
        case error(Error)           // Error occurred
    }

    private enum ScoutTaskKind {
        case webSearch
        case complexReasoning
    }
    
    // MARK: - Send Message (Non-streaming, for quick actions)
    func sendMessage(
        _ message: String,
        conversationHistory: [ChatMessage],
        likedItems: [SavedMediaItem],
        webSearchEnabled: Bool = true,
        model: ChronModel? = nil,
        restrictedMode: Bool = false
    ) async throws -> (String, TrailerResponse?) {
        guard isAvailable else {
            throw AIError.noApiKey
        }

        // TRAILER SHORT-CIRCUIT
        if let trailerResponse = await checkForTrailerRequest(message) {
            return (trailerResponse.content, trailerResponse)
        }

        if await shouldUseFoundationModels(for: message, webSearchEnabled: webSearchEnabled) {
            do {
                let response = try await sendMessageWithFoundationModels(
                    message,
                    conversationHistory: conversationHistory,
                    likedItems: likedItems,
                    restrictedMode: restrictedMode
                )
                return (response, nil)
            } catch {
                // Fall through to the cloud if the on-device model is unavailable at runtime.
            }
        }
        
        var fullContent = ""
        for await event in streamMessage(message, conversationHistory: conversationHistory, likedItems: likedItems, webSearchEnabled: webSearchEnabled, model: model, restrictedMode: restrictedMode) {
            switch event {
            case .content(let text):
                fullContent = text
            case .done:
                break
            case .error(let error):
                throw error
            case .thinking:
                break
            }
        }
        
        return (fullContent, nil)
    }
    
    // MARK: - Stream Message (Main streaming entry point)
    func streamMessage(
        _ message: String,
        conversationHistory: [ChatMessage],
        likedItems: [SavedMediaItem],
        webSearchEnabled: Bool = true,
        model: ChronModel? = nil,
        restrictedMode: Bool = false,
        imageDataURLs: [String] = []
    ) -> AsyncStream<StreamEvent> {
        // Attached images require a vision-capable model and the cloud path —
        // force the multimodal flavour and skip on-device routing.
        let effectiveModel = !imageDataURLs.isEmpty ? (model ?? .deepReasoning) : model
        return AsyncStream { continuation in
            Task {
                do {
                    if imageDataURLs.isEmpty,
                       await self.shouldUseFoundationModels(for: message, webSearchEnabled: webSearchEnabled) {
                        do {
                            try await self.performFoundationModelsStreamRequest(
                                message: message,
                                conversationHistory: conversationHistory,
                                likedItems: likedItems,
                                restrictedMode: restrictedMode,
                                continuation: continuation
                            )
                            return
                        } catch {
                            // Fall through to the cloud if the on-device path fails after the initial gate.
                        }
                    }

                    try await self.performStreamRequest(
                        message: message,
                        conversationHistory: conversationHistory,
                        likedItems: likedItems,
                        webSearchEnabled: webSearchEnabled,
                        model: effectiveModel,
                        restrictedMode: restrictedMode,
                        imageDataURLs: imageDataURLs,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }
        }
    }

    private func shouldUseFoundationModels(for message: String, webSearchEnabled: Bool) async -> Bool {
        // TEMP: a forced model takes over completely — no on-device routing.
        guard AIModelCatalog.forcedModelId == nil else { return false }
        // An explicit model pick (anything but "Auto") must be honoured — never
        // silently answer on-device when the user chose a specific cloud model.
        guard !hasExplicitModelSelection else { return false }
        guard await isFoundationModelsEnabledInSettings else { return false }
        guard await AppleIntelligenceSearchService.shared.canUseNaturalResponseFormatting else { return false }
        return !requestNeedsLiveWebSearch(message, webSearchEnabled: webSearchEnabled)
    }

    /// True when the user has picked a specific model in the Atlas selector
    /// (i.e. anything other than "Auto").
    private var hasExplicitModelSelection: Bool {
        let id = UserDefaults.standard.string(forKey: AIModelCatalog.selectionDefaultsKey) ?? "auto"
        return id != "auto"
    }

    private var isFoundationModelsEnabledInSettings: Bool {
        get async {
            await MainActor.run {
                StorageService.shared.settings.useAppleIntelligenceSearch
            }
        }
    }

    private func requestNeedsLiveWebSearch(_ message: String, webSearchEnabled: Bool) -> Bool {
        guard webSearchEnabled else { return false }

        let lowercased = message.lowercased()
        let webKeywords = [
            "latest", "news", "current", "currently", "today", "tonight", "this week",
            "opening weekend", "box office", "gross", "ratings", "reviews", "cast",
            "release date", "release dates", "awards", "oscar", "emmy", "internet",
            "online", "search the web", "look it up", "what happened", "source", "sources",
            "recent", "updated", "update", "how much did", "how much has", "weekend gross",
            // Forward-looking queries that need live info. Deliberately excludes
            // rumour/leak/speculation terms — see `rumourSeekingKeywords` below.
            "spoiler", "spoilers", "confirmed", "announced", "renewed", "cancelled", "canceled",
            "upcoming", "sequel", "casting", "who is playing", "is it true",
            "when does", "when is", "when will", "set to", "release window",
            // Availability moves constantly — licences lapse, shows change home
            // — so it can never be answered from training data.
            "streaming", "stream", "where can i watch", "where to watch",
            "watch online", "available on", "what platform", "which platform",
            "which service", "what service",
            // Theatrical availability moves just as fast as streaming.
            "playing", "in cinemas", "in theaters", "in theatres", "showtimes",
            "at the cinema", "still in cinemas", "out in cinemas"
        ]

        // Rumour-hunting phrasings are never routed to web search: searching is
        // what surfaces the unverified reporting we don't want to relay. These
        // queries fall through to the model, which the system prompt instructs to
        // answer with "no official announcement" rather than speculate.
        guard !Self.rumourSeekingKeywords.contains(where: { lowercased.contains($0) }) else {
            return false
        }

        return webKeywords.contains(where: { lowercased.contains($0) })
    }

    /// Phrasings that signal the user is fishing for unconfirmed information.
    private static let rumourSeekingKeywords = [
        "rumour", "rumours", "rumored", "rumoured", "rumor", "rumors",
        "leak", "leaks", "leaked", "speculation", "speculate",
        "reportedly", "insider", "scoop", "fan theory", "theories"
    ]

    private func sendMessageWithFoundationModels(
        _ message: String,
        conversationHistory: [ChatMessage],
        likedItems: [SavedMediaItem],
        restrictedMode: Bool
    ) async throws -> String {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 18.0, macOS 15.0, *) {
            let response = try await foundationModelsResponse(
                to: message,
                conversationHistory: conversationHistory,
                likedItems: likedItems,
                restrictedMode: restrictedMode
            )
            return response
        }
        #endif

        throw AIError.apiError("Apple Intelligence isn’t available on this device.")
    }

    private func performFoundationModelsStreamRequest(
        message: String,
        conversationHistory: [ChatMessage],
        likedItems: [SavedMediaItem],
        restrictedMode: Bool,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) async throws {
        let response = try await sendMessageWithFoundationModels(
            message,
            conversationHistory: conversationHistory,
            likedItems: likedItems,
            restrictedMode: restrictedMode
        )

        let wordChunks = chunkedResponseWords(from: response)
        var accumulatedContent = ""

        for chunk in wordChunks {
            accumulatedContent += chunk
            continuation.yield(.content(accumulatedContent))
            try? await Task.sleep(nanoseconds: 35_000_000)
        }

        continuation.yield(.done)
        continuation.finish()
    }

    private func chunkedResponseWords(from response: String) -> [String] {
        let tokens = response.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return [response] }

        var chunks: [String] = []
        for token in tokens {
            chunks.append(String(token) + " ")
        }

        if let last = chunks.indices.last {
            chunks[last] = chunks[last].trimmingCharacters(in: .whitespaces)
        }

        return chunks
    }

    private func foundationModelsResponse(
        to message: String,
        conversationHistory: [ChatMessage],
        likedItems: [SavedMediaItem],
        restrictedMode: Bool
    ) async throws -> String {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 18.0, macOS 15.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw AIError.apiError("Apple Intelligence isn’t available on this device.")
            }
            guard model.supportsLocale(Locale.current) else {
                throw AIError.apiError("Apple Intelligence doesn’t support the current locale.")
            }

            let systemPrompt = buildSystemPrompt(
                likedItems: likedItems,
                webSearchEnabled: false,
                restrictedMode: restrictedMode,
                model: .deepReasoning,
                personalization: await AtlasPersonalization.current()
            )

            let recentHistory = conversationHistory.suffix(6).map {
                "\($0.role.capitalized): \($0.content)"
            }.joined(separator: "\n\n")

            let prompt = """
            Recent conversation:
            \(recentHistory)

            New user message:
            \(message)
            """

            let session = LanguageModelSession(model: model, instructions: systemPrompt)
            let response = try await session.respond(to: prompt)
            let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? response.content : trimmed
        }
        #endif

        throw AIError.apiError("Apple Intelligence isn’t available on this device.")
    }
    
    // MARK: - Perform Stream Request
    private func performStreamRequest(
        message: String,
        conversationHistory: [ChatMessage],
        likedItems: [SavedMediaItem],
        webSearchEnabled: Bool,
        model: ChronModel?,
        restrictedMode: Bool,
        imageDataURLs: [String] = [],
        continuation: AsyncStream<StreamEvent>.Continuation
    ) async throws {
        let resolved = resolveModel(explicit: model, message: message, webSearchEnabled: webSearchEnabled)
        let provider = resolved.provider
        let providerKey = provider.apiKey

        guard !providerKey.isEmpty else {
            throw AIError.noApiKey
        }

        // Gemini's NATIVE endpoint supports real Google Search grounding. Prefer it
        // when web search is on; if it errors before streaming (e.g. an incompatible
        // key), fall through to the OpenAI-compatible path + free DuckDuckGo RAG.
        if provider == .gemini && webSearchEnabled {
            do {
                try await performGeminiGroundedStreamRequest(
                    message: message,
                    conversationHistory: conversationHistory,
                    likedItems: likedItems,
                    restrictedMode: restrictedMode,
                    resolved: resolved,
                    apiKey: providerKey,
                    continuation: continuation
                )
                return
            } catch {
                // Fall back to the standard path below (no content was yielded yet).
            }
        }

        let systemPrompt = buildSystemPrompt(
            likedItems: likedItems,
            webSearchEnabled: webSearchEnabled,
            restrictedMode: restrictedMode,
            model: resolved.promptModel,
            personalization: await AtlasPersonalization.current()
        )

        // Models without a built-in web search (free OpenRouter models and the
        // Gemini OpenAI endpoint) get genuinely-free web context via keyless
        // search (RAG) when the query looks like it needs current info.
        let needsFreeWebContext = provider == .gemini
            || provider == .huggingface
            || provider == .cloudflare
            || (provider == .poe && resolved.modelId != "Web-Search")
            || (provider == .openrouter && AIModelCatalog.isFreeModel(resolved.modelId))
        let useFreeRAG = needsFreeWebContext
            && requestNeedsLiveWebSearch(message, webSearchEnabled: webSearchEnabled)
        let ragContext = useFreeRAG ? await FreeWebSearchService.shared.contextBlock(for: message) : nil

        // "Where is X streaming" is answered from TMDB, not from the model's
        // memory of what had been released when it was trained.
        let streamingContext = await AtlasStreamingGrounding.contextBlock(for: message)

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        if let streamingContext {
            messages.append(["role": "system", "content": streamingContext])
        }

        if let ragContext {
            messages.append([
                "role": "system",
                "content": """
                Live web search results for the user's question (retrieved just now). \
                Use these for any current facts, numbers, or dates, and cite sources as markdown links. \
                If they don't cover the question, say so rather than guessing.

                \(ragContext)
                """
            ])
        }

        let recentHistory = conversationHistory.suffix(6)
        for msg in recentHistory {
            messages.append(["role": msg.role, "content": msg.content])
        }

        // The final user turn carries any attached images as OpenAI-style
        // multimodal content: a text part followed by one image_url part each.
        if imageDataURLs.isEmpty {
            messages.append(["role": "user", "content": message])
        } else {
            var parts: [[String: Any]] = [["type": "text", "text": message]]
            for url in imageDataURLs {
                parts.append(["type": "image_url", "image_url": ["url": url]])
            }
            messages.append(["role": "user", "content": parts])
        }

        var requestBody: [String: Any] = [
            "model": resolved.modelId,
            "messages": messages,
            "max_tokens": 8192,
            "temperature": 0.7,
            "stream": true
        ]

        // Enable web search using each provider's own mechanism.
        if webSearchEnabled {
            switch provider {
            case .openrouter:
                // Free models use the keyless RAG context above instead of the
                // paid plugin; paid models get OpenRouter's built-in web plugin.
                if !AIModelCatalog.isFreeModel(resolved.modelId) {
                    requestBody["plugins"] = [["id": "web"]]
                }
            case .poe:
                // Poe has no request-level web flag — search comes from picking
                // the "Web-Search" bot, so other bots use the RAG context above.
                break
            case .gemini, .huggingface, .cloudflare:
                break // These use the keyless RAG context injected above.
            }
        }

        guard let url = URL(string: provider.baseURL) else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(providerKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // OpenRouter uses these for app attribution / leaderboard ranking.
        if provider == .openrouter {
            request.addValue("https://watchguide.app", forHTTPHeaderField: "HTTP-Referer")
            request.addValue("WatchGuide", forHTTPHeaderField: "X-Title")
        }
        request.timeoutInterval = 90

        // Candidate model chain. Free OpenRouter models frequently 429 under shared
        // upstream load, so on a rate-limit/server error fall back to the free
        // auto-router and a couple of alternates before surfacing an error.
        var candidates = [resolved.modelId]
        if provider == .openrouter, AIModelCatalog.isFreeModel(resolved.modelId) {
            for fallback in ["openrouter/free", "deepseek/deepseek-r1:free", "meta-llama/llama-3.3-70b-instruct:free"]
            where !candidates.contains(fallback) {
                candidates.append(fallback)
            }
        }

        var bytes: URLSession.AsyncBytes?
        let maxAttemptsPerCandidate = 3
        candidateLoop: for candidate in candidates {
            requestBody["model"] = candidate
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            for attempt in 0..<maxAttemptsPerCandidate {
                let (responseBytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIError.invalidResponse
                }

                if (200...299).contains(httpResponse.statusCode) {
                    bytes = responseBytes
                    break candidateLoop
                }

                // Drain the error body before deciding whether to retry.
                var errorBody = ""
                for try await line in responseBytes.lines { errorBody += line }

                let status = httpResponse.statusCode
                guard isRetryableStatus(status) else {
                    throw AIError.apiError(friendlyOpenRouterError(status: status, body: errorBody, provider: provider))
                }

                // Transient overload/rate-limit: back off and retry the same model.
                if attempt < maxAttemptsPerCandidate - 1 {
                    try? await Task.sleep(nanoseconds: backoffNanoseconds(attempt: attempt))
                    continue
                }
                // Retries exhausted for this model — fall through to the next
                // fallback candidate, or surface the error if this was the last.
                if candidate == candidates.last {
                    throw AIError.apiError(friendlyOpenRouterError(status: status, body: errorBody, provider: provider))
                }
            }
        }

        guard let bytes else {
            throw AIError.invalidResponse
        }

        // Parse SSE stream
        var accumulatedContent = ""
        var accumulatedThinking = ""
        var isInThinking = false
        
        for try await line in bytes.lines {
            // SSE lines start with "data: "
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            
            if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                let finalContent = await finalizeScoutResponse(
                    accumulatedContent,
                    for: message
                )
                if finalContent != accumulatedContent {
                    continuation.yield(.content(finalContent))
                }
                continuation.yield(.done)
                continuation.finish()
                return
            }
            
            guard let data = jsonString.data(using: .utf8) else { continue }
            
            do {
                let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
                if let delta = chunk.choices.first?.delta {
                    // Check for thinking/reasoning content
                    if let reasoning = delta.reasoning ?? delta.reasoning_content {
                        accumulatedThinking += reasoning
                        isInThinking = true
                        continuation.yield(.thinking(accumulatedThinking))
                    }
                    
                    // Regular content
                    if let content = delta.content, !content.isEmpty {
                        if isInThinking {
                            isInThinking = false
                        }
                        accumulatedContent += content
                        continuation.yield(.content(accumulatedContent))
                    }
                }
            } catch {
                // Skip malformed chunks
                continue
            }
        }
        
        // If we exit the loop without [DONE]
        continuation.yield(.done)
        continuation.finish()
    }

    // MARK: - Gemini Native (Google Search grounding)
    /// Streams from Gemini's native `streamGenerateContent` endpoint with the
    /// `google_search` tool enabled — real Google Search grounding with citations.
    /// Throws before yielding on HTTP errors so the caller can fall back cleanly.
    private func performGeminiGroundedStreamRequest(
        message: String,
        conversationHistory: [ChatMessage],
        likedItems: [SavedMediaItem],
        restrictedMode: Bool,
        resolved: ResolvedModel,
        apiKey: String,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) async throws {
        let systemPrompt = buildSystemPrompt(
            likedItems: likedItems,
            webSearchEnabled: true,
            restrictedMode: restrictedMode,
            model: resolved.promptModel,
            personalization: await AtlasPersonalization.current()
        )

        // Google Search can still land on a stale listicle for "where is X
        // streaming", so TMDB goes in alongside it as the authority on
        // availability — same grounding the non-Gemini path gets.
        let streamingContext = await AtlasStreamingGrounding.contextBlock(for: message)
        let instruction = streamingContext.map { "\(systemPrompt)\n\n\($0)" } ?? systemPrompt

        // Gemini uses "user"/"model" roles and puts the system prompt in a
        // dedicated field. The model decides on its own when to run a search.
        var contents: [[String: Any]] = []
        for msg in conversationHistory.suffix(6) {
            let role = msg.role == "assistant" ? "model" : "user"
            contents.append(["role": role, "parts": [["text": msg.content]]])
        }
        contents.append(["role": "user", "parts": [["text": message]]])

        let requestBody: [String: Any] = [
            "system_instruction": ["parts": [["text": instruction]]],
            "contents": contents,
            "tools": [["google_search": [String: Any]()]],
            "generationConfig": ["temperature": 0.7, "maxOutputTokens": 8192]
        ]

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(resolved.modelId):streamGenerateContent?alt=sse"
        guard let url = URL(string: endpoint) else { throw AIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 90

        // Gemini's grounded endpoint frequently returns 503 ("model is
        // overloaded") under load. Retry with backoff before giving up so the
        // caller's fallback path is only used for genuine, persistent failures.
        let maxAttempts = 3
        var bytes: URLSession.AsyncBytes?
        for attempt in 0..<maxAttempts {
            let (responseBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }
            if (200...299).contains(httpResponse.statusCode) {
                bytes = responseBytes
                break
            }
            var errorBody = ""
            for try await line in responseBytes.lines { errorBody += line }
            let status = httpResponse.statusCode
            if isRetryableStatus(status), attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: backoffNanoseconds(attempt: attempt))
                continue
            }
            throw AIError.apiError("Gemini \(status): \(errorBody.prefix(200))")
        }
        guard let bytes else { throw AIError.invalidResponse }

        var accumulatedContent = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard let data = jsonString.data(using: .utf8) else { continue }

            guard let chunk = try? JSONDecoder().decode(GeminiStreamResponse.self, from: data) else { continue }
            let text = chunk.candidates?.first?.content?.parts?.compactMap(\.text).joined() ?? ""
            if !text.isEmpty {
                accumulatedContent += text
                continuation.yield(.content(accumulatedContent))
            }
        }

        let finalContent = await finalizeScoutResponse(
            accumulatedContent,
            for: message
        )
        if finalContent != accumulatedContent {
            continuation.yield(.content(finalContent))
        }
        continuation.yield(.done)
        continuation.finish()
    }

    // MARK: - Trailer Short-Circuit
    private func checkForTrailerRequest(_ message: String) async -> TrailerResponse? {
        let lowercased = message.lowercased()
        
        let trailerKeywords = ["trailer", "teaser", "preview", "watch the trailer", "show trailer", "play trailer", "first trailer"]
        let hasTrailerIntent = trailerKeywords.contains { lowercased.contains($0) }
        
        guard hasTrailerIntent else { return nil }
        
        let title = parseTitle(from: message)
        guard !title.isEmpty else { return nil }
        
        let wantsFirstTrailer = lowercased.contains("first") || lowercased.contains("original") || lowercased.contains("initial")
        
        do {
            let searchResults = try await TMDBService.shared.searchMulti(query: title)
            guard let bestMatch = searchResults.results.first else { return nil }
            
            let videos: VideosResponse
            let mediaDetails: (title: String, year: String?, overview: String?)
            
            if bestMatch.resolvedMediaType == .movie {
                videos = try await TMDBService.shared.getMovieVideos(id: bestMatch.id)
                let details = try await TMDBService.shared.getMovieDetails(id: bestMatch.id)
                mediaDetails = (details.title, details.year, details.overview)
            } else {
                videos = try await TMDBService.shared.getTVShowVideos(id: bestMatch.id)
                let details = try await TMDBService.shared.getTVShowDetails(id: bestMatch.id)
                mediaDetails = (details.name, details.year, details.overview)
            }
            
            let trailer = selectBestTrailer(from: videos.results, preferFirst: wantsFirstTrailer)
            guard let selectedTrailer = trailer else { return nil }
            
            let yearString = mediaDetails.year ?? "Unknown year"
            let summary = "**\(mediaDetails.title)** (\(yearString)) — \(selectedTrailer.name)"
            
            return TrailerResponse(
                content: summary,
                trailerKey: selectedTrailer.key,
                trailerTitle: mediaDetails.title
            )
        } catch {
            print("Trailer lookup failed: \(error), falling back to LLM")
            return nil
        }
    }
    
    private func parseTitle(from message: String) -> String {
        var cleaned = message.lowercased()
        
        let phrasesToRemove = [
            "show me the trailer for", "show trailer for",
            "play the trailer for", "play trailer for",
            "find the trailer for", "find trailer for",
            "get the trailer for", "get trailer for",
            "watch the trailer for", "watch trailer for",
            "first trailer for", "trailer for", "teaser for",
            "show me", "play", "find", "get", "watch",
            "trailer", "teaser", "the first", "official",
            "please", "can you", "could you"
        ]
        
        for phrase in phrasesToRemove {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: " ")
        }
        
        return cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func selectBestTrailer(from videos: [Video], preferFirst: Bool) -> Video? {
        let trailers = videos.filter {
            $0.site.lowercased() == "youtube" && $0.type == "Trailer"
        }
        guard !trailers.isEmpty else { return nil }
        
        let excludeKeywords = ["final", "teaser", "tv spot", "featurette", "clip", "behind", "making of", "interview", "red band"]
        let preferKeywords = ["official trailer", "theatrical trailer", "main trailer"]
        
        let scored = trailers.map { video -> (video: Video, score: Int) in
            var score = 0
            let nameLower = video.name.lowercased()
            
            if video.official == true { score += 100 }
            for keyword in preferKeywords {
                if nameLower.contains(keyword) { score += 50; break }
            }
            for keyword in excludeKeywords {
                if nameLower.contains(keyword) { score -= 200; break }
            }
            if nameLower.contains("trailer") && !nameLower.contains("teaser") { score += 20 }
            if nameLower.contains("trailer 2") || nameLower.contains("trailer 3") || nameLower.contains("trailer #2") || nameLower.contains("trailer #3") {
                score -= 30
            }
            return (video, score)
        }
        
        let sorted = scored.sorted { item1, item2 in
            if item1.score != item2.score { return item1.score > item2.score }
            if preferFirst, let date1 = item1.video.publishedAt, let date2 = item2.video.publishedAt {
                return date1 < date2
            }
            return false
        }
        
        return sorted.first?.video
    }
    
    // MARK: - Build System Prompt
    private func buildSystemPrompt(
        likedItems: [SavedMediaItem],
        webSearchEnabled: Bool,
        restrictedMode: Bool = false,
        model: ChronModel,
        personalization: AtlasPersonalization = .none
    ) -> String {
        var prompt = """
        You are Atlas, an AI movie & TV assistant. Concise but complete — never cut off mid-sentence.

        Rules:
        - For simple questions: 2-4 sentences, straight to the point
        - For recommendations: give exactly 2 movies and 2 TV shows. Each with **Title** (Movie/Show) + a short reason (one line). Always finish the full list
        - Use **bold** for titles. No fluff, no disclaimers, no preamble
        - Be casual and fun, like texting a film-buff friend
        - Use bullet points for lists
        - TRAILER EMBEDDING: When discussing a specific movie or TV show and a trailer would be relevant or helpful (e.g., the user asks about a specific title, asks what something looks like, asks if something is good, etc.), include the tag [TRAILER:Exact Title] at the END of your response. This will automatically embed the trailer. Use the exact official title. Only include ONE trailer tag per response. Do NOT mention or explain the tag — just place it at the very end.
        - LIST CREATION: When a user asks for a list, playlist, or recommendations, respond with 1-2 casual sentences, then include [FILTER_PANEL:...] at the very END. Use | to separate fields and , to separate options within a field. Build it like this: title=<compelling list name>|company_opts=<ALL relevant studios comma-separated>|company=|year_opts=<relevant individual years comma-separated e.g. 2000,2005,2008,2012,2019>|year_from=<auto-picked earliest year>|genre_opts=<all relevant genres comma-separated>|genre=<auto-picked genre>|streaming_opts=<all relevant services comma-separated>|streaming=. FRANCHISE NAMES: When the user says "Marvel", "DC", "Star Wars", "Disney", "Pixar", etc. — this means ALL content from that franchise regardless of which studio made it. List every studio that has produced content for that franchise in company_opts, but leave company= BLANK so the full franchise is included. Do NOT narrow a franchise name to a single studio. STREAMING IS OPTIONAL — always leave streaming blank (streaming=) unless the user specifically mentioned a streaming service. If you genuinely cannot determine what the user means, ask for clarification in your 1-2 sentence response AND still include the [FILTER_PANEL:...] tag with best guess. Do NOT generate a PLAYLIST tag yet. Do NOT explain the tag.
        - PLAYLIST GENERATION: When you receive a message starting with "Create a full playlist titled", respond ONLY with the [PLAYLIST:Title1|Title2|...] tag containing EVERY matching title. NO cap — if there are 40, include all 40. Use official titles separated by | with no spaces around the pipe. No other text.
        - If the user explicitly asks for a trailer, ALWAYS include the [TRAILER:Title] tag.
        - NO RUMOURS: Never repeat rumours, leaks, insider claims, "reportedly"/"sources say" reports, or speculation — not even to summarise or debunk them. Only state what has been officially announced, confirmed, or released. If something is unannounced or unconfirmed, say plainly that there is no official announcement yet and stop there. Never guess at future casting, plots, renewals, or release dates, and never present a fan theory as information.
        - NEVER include "Related searches", "Related questions", "People also ask", or similar sections in your response. Only answer the question directly.
        - Always finish your response completely. Never stop mid-sentence or mid-number.
        - CRITICAL: NEVER repeat yourself. State facts exactly ONCE. If you mention box office numbers, dates, or any data, say it ONE time only. Do NOT restate or rephrase the same information a second time. Your response must be concise with zero redundancy.
        """

        // Persona, memory, and app control — the layers that make Atlas feel
        // like the same assistant across chat, voice, and briefings.
        if !personalization.characterPrompt.isEmpty {
            prompt += "\n\n" + personalization.characterPrompt
        }
        prompt += personalization.addressPrompt
        if personalization.actionsEnabled {
            prompt += AtlasActionCenter.promptInstructions
        }
        if personalization.memoryEnabled {
            prompt += AtlasMemoryStore.promptInstructions
        }
        prompt += personalization.memoryBlock
        prompt += personalization.stateBlock

        switch model {
        case .webGrounded:
            prompt += "\n- This request needs web-aware, current information. Prioritize fresh, source-backed answers, and discard any search result that is a rumour, leak, or unconfirmed report rather than repeating it."
        case .deepReasoning:
            prompt += "\n- This request needs stronger reasoning and synthesis. Focus on judgment, tradeoffs, and coherent recommendations."
        case .geminiFlashLite:
            break
        }
        
        // ALWAYS enforce content safety — required for App Store 13+ rating
        prompt += ContentFilterService.shared.alwaysOnSafetyPrompt
        
        // Add extra restrictions for kids mode
        if restrictedMode {
            prompt += ContentFilterService.shared.kidsModeSystemPrompt
        }
        
        if webSearchEnabled {
            prompt += """
            
            
            CRITICAL — WEB SEARCH INSTRUCTIONS:
            - You MUST use web search for ANY question involving numbers, stats, box office, ratings, release dates, cast info, awards, or current events. ALWAYS search — never guess or rely on training data for factual/numerical questions.
            - When reporting box office numbers: search for the LATEST figures. Box office numbers change daily/weekly. Always report the most current worldwide gross, domestic gross, and international gross separately. Use trusted sources like Box Office Mojo, The Numbers, or Deadline.
            - NEVER round or estimate numbers. Give exact figures from your search results (e.g., "$356.2 million" not "around $350 million").
            - If you find conflicting numbers from different sources, use the most recent source and mention the date.
            - Include source URLs in your response. Format them as markdown links like [Source Name](https://url). Put source links naturally in the text or at the end.
            - Do NOT say you cannot look things up or that you don't have access to real-time data. You DO have web search — use it for every factual query.
            - Double-check your numbers. If a movie is still in theaters, explicitly note that numbers are still updating.
            - IMPORTANT: Even if multiple search results contain the same data, only state each fact ONCE. Synthesize all sources into a single, non-repetitive answer. Never duplicate paragraphs or bullet points.
            """
        }
        
        if !likedItems.isEmpty {
            prompt += "\n\nUser's taste (liked): "
            let titles = likedItems.prefix(15).map { "\($0.title) (\($0.mediaType == .movie ? "M" : "TV"))" }
            prompt += titles.joined(separator: ", ")
        }
        
        return prompt
    }

    // MARK: - Model Resolution

    /// The concrete model + provider a request will use, plus a `ChronModel` whose
    /// flavour drives the system prompt and reformat gating (OpenRouter models map
    /// to the closest flavour purely for prompt-style purposes).
    private struct ResolvedModel {
        let provider: AtlasAIProvider
        let modelId: String
        let promptModel: ChronModel
    }

    /// Resolves the model for a request. Priority:
    /// 1. An explicit `ChronModel` passed by internal callers.
    /// 2. The user's picked model from the Atlas model selector.
    /// 3. Automatic model selection based on the message.
    private func resolveModel(explicit: ChronModel?, message: String, webSearchEnabled: Bool) -> ResolvedModel {
        // TEMP: a forced model overrides everything (explicit picks, stored
        // selection, and auto-routing) so the whole app runs on one model.
        if let forcedId = AIModelCatalog.forcedModelId, let option = AIModelCatalog.option(id: forcedId) {
            // Hybrid web search: live/current-info queries (rumours, box office,
            // news, release dates, cast…) need real search. The cheap forced
            // model only has the weak keyless RAG, so route those to Gemini's
            // native Google Search grounding when a Gemini key is available.
            // Everything else stays on the cheap forced model.
            if webSearchEnabled,
               requestNeedsLiveWebSearch(message, webSearchEnabled: webSearchEnabled),
               !AtlasAIProvider.gemini.apiKey.isEmpty,
               let gemini = AIModelCatalog.geminiModels.first {
                persistKey(for: .gemini)
                return ResolvedModel(provider: .gemini, modelId: gemini.id, promptModel: promptModel(for: gemini))
            }
            persistKey(for: option.provider)
            return ResolvedModel(provider: option.provider, modelId: option.id, promptModel: promptModel(for: option))
        }

        if let explicit {
            persistKey(for: explicit.provider)
            return ResolvedModel(provider: explicit.provider, modelId: explicit.providerModelId, promptModel: explicit)
        }

        let storedId = UserDefaults.standard.string(forKey: AIModelCatalog.selectionDefaultsKey) ?? "auto"
        if storedId != "auto", let option = AIModelCatalog.option(id: storedId) {
            persistKey(for: option.provider)
            return ResolvedModel(provider: option.provider, modelId: option.id, promptModel: promptModel(for: option))
        }

        let auto = automaticScoutModel(for: message, webSearchEnabled: webSearchEnabled)
        persistKey(for: auto.provider)
        return ResolvedModel(provider: auto.provider, modelId: auto.providerModelId, promptModel: auto)
    }

    /// Maps a model option to the closest `ChronModel` flavour for prompt styling.
    private func promptModel(for option: AIModelOption) -> ChronModel {
        ChronModel(rawValue: option.id) ?? (option.supportsThinking ? .deepReasoning : .geminiFlashLite)
    }

    /// Persists a provider's bundled key into the Keychain the first time it's needed.
    private func persistKey(for provider: AtlasAIProvider) {
        let name = provider.apiKeyName
        guard (ApiKeyManager.shared.get(key: name) ?? "").isEmpty else { return }
        switch provider {
        case .openrouter:  _ = ApiKeyManager.shared.set(key: name, value: AIModelCatalog.bundledOpenRouterKey)
        case .gemini:      _ = ApiKeyManager.shared.set(key: name, value: AIModelCatalog.bundledGeminiKey)
        case .huggingface:
            guard !AIModelCatalog.bundledHuggingFaceKey.isEmpty else { break }
            _ = ApiKeyManager.shared.set(key: name, value: AIModelCatalog.bundledHuggingFaceKey)
        case .cloudflare:
            guard !AIModelCatalog.bundledCloudflareKey.isEmpty else { break }
            _ = ApiKeyManager.shared.set(key: name, value: AIModelCatalog.bundledCloudflareKey)
        case .poe:
            guard !AIModelCatalog.bundledPoeKey.isEmpty else { break }
            _ = ApiKeyManager.shared.set(key: name, value: AIModelCatalog.bundledPoeKey)
        }
    }

    private func automaticScoutModel(for message: String, webSearchEnabled: Bool) -> ChronModel {
        let taskKind = classifyScoutTask(message: message, webSearchEnabled: webSearchEnabled)
        switch taskKind {
        case .webSearch:
            return .webGrounded
        case .complexReasoning:
            return .deepReasoning
        }
    }

    private func classifyScoutTask(message: String, webSearchEnabled: Bool) -> ScoutTaskKind {
        let lowercased = message.lowercased()

        let webKeywords = [
            "latest", "news", "current", "currently", "today", "tonight", "this week",
            "opening weekend", "box office", "gross", "ratings", "reviews", "cast",
            "release date", "release dates", "awards", "oscar", "emmy", "internet",
            "online", "search the web", "look it up", "what happened", "source", "sources",
            "streaming", "stream", "where can i watch", "where to watch",
            "watch online", "available on", "playing", "in cinemas",
            "in theaters", "in theatres", "showtimes"
        ]
        let complexKeywords = [
            "recommend", "compare", "versus", "vs", "explain", "analyze", "analysis",
            "why should", "which should", "best for me", "based on", "if i liked",
            "deeper", "complex", "plan", "rank", "break down", "help me decide"
        ]

        if webSearchEnabled && webKeywords.contains(where: { lowercased.contains($0) }) {
            return .webSearch
        }

        if complexKeywords.contains(where: { lowercased.contains($0) }) || message.count > 140 {
            return .complexReasoning
        }

        return webSearchEnabled ? .webSearch : .complexReasoning
    }

    private func finalizeScoutResponse(
        _ response: String,
        for userMessage: String
    ) async -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return response }

        // Polish on-device when Apple Intelligence is available — free, private,
        // and no extra network round trip. Otherwise the model's own output
        // stands: the old cloud reformat pass existed only to clean up Poe's
        // responses, and cost a second API call to do it.
        if await AppleIntelligenceSearchService.shared.canUseNaturalResponseFormatting {
            return await AppleIntelligenceSearchService.shared.naturalLanguageResponse(
                for: trimmed,
                userQuery: userMessage
            )
        }

        return trimmed
    }

    // MARK: - Transient-error retry helpers

    /// Status codes worth retrying — transient rate-limits and server/overload
    /// errors (e.g. Gemini's 503 "model is overloaded").
    private func isRetryableStatus(_ status: Int) -> Bool {
        status == 429 || status == 529 || (500...599).contains(status)
    }

    /// Exponential backoff (with a little jitter) before retrying a transient
    /// AI-provider error: ~0.7s, ~1.4s, ~2.8s …
    private func backoffNanoseconds(attempt: Int) -> UInt64 {
        let base = 0.7 * pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0...0.3)
        return UInt64((base + jitter) * 1_000_000_000)
    }

    /// Turns raw provider error responses into a short, user-readable message.
    private func friendlyOpenRouterError(status: Int, body: String, provider: AtlasAIProvider) -> String {
        switch status {
        case 429:
            return "This free model is busy right now (rate-limited). Try again in a moment, or pick a different model from the selector at the top."
        case 402:
            return "This model needs OpenRouter credits. Pick a free model instead."
        case 401, 403:
            return "The \(provider.displayName) API key was rejected. Check the key in Settings."
        case 500, 502, 503, 504, 529:
            return "The AI service is temporarily overloaded. Please try again in a moment."
        default:
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
            return detail.isEmpty ? "Something went wrong (error \(status))." : "Error \(status): \(detail)"
        }
    }

    
    // MARK: - Quick Actions
    func getSimilarRecommendations(for title: String, mediaType: MediaType) async throws -> String {
        let message = "5 \(mediaType == .movie ? "movies" : "shows") like '\(title)'. Title + one-line why."
        let (response, _) = try await sendMessage(message, conversationHistory: [], likedItems: [])
        return response
    }
    
    func getMediaSummary(title: String, overview: String?) async throws -> String {
        let message = "Quick take on '\(title)' — genre, vibe, who it's for. 2-3 sentences max."
        let (response, _) = try await sendMessage(message, conversationHistory: [], likedItems: [])
        return response
    }
    
    // MARK: - For You Recommendations
    /// Round-robin model selection for For You row
    private static var forYouModelIndex = 0
    private static let forYouModels: [ChronModel] = [.geminiFlashLite, .deepReasoning]
    
    private func nextForYouModel() -> ChronModel {
        let model = Self.forYouModels[Self.forYouModelIndex % Self.forYouModels.count]
        Self.forYouModelIndex += 1
        return model
    }
    
    /// Gets personalized "For You" recommendations based on liked items.
    /// Returns an array of (title, mediaType) tuples that can be searched on TMDB.
    ///
    /// Prefers the on-device Apple Intelligence model ("Siri AI") when available —
    /// it powers the recommendation algorithm privately and offline. Falls back to
    /// a cloud provider when Apple Intelligence is unavailable or disabled.
    func getForYouRecommendations(likedItems: [SavedMediaItem]) async throws -> [(title: String, mediaType: String)] {
        guard !likedItems.isEmpty else { return [] }

        // Primary engine: on-device Apple Intelligence.
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 18.0, macOS 15.0, *), await canUseFoundationModelsForRecommendations {
            do {
                let results = try await getForYouRecommendationsWithFoundationModels(likedItems: likedItems)
                if !results.isEmpty { return results }
            } catch {
                print("For You: Apple Intelligence failed, falling back to cloud — \(error)")
            }
        }
        #endif

        // Cloud fallback.
        return try await getForYouRecommendationsViaCloud(likedItems: likedItems)
    }

    /// Whether the on-device Apple Intelligence model can power recommendations right now.
    /// Honours the user's Apple Intelligence setting and the device/locale availability.
    private var canUseFoundationModelsForRecommendations: Bool {
        get async {
            guard await isFoundationModelsEnabledInSettings else { return false }
            #if canImport(FoundationModels) && !os(tvOS)
            if #available(iOS 18.0, macOS 15.0, *) {
                let model = SystemLanguageModel.default
                if case .available = model.availability, model.supportsLocale(Locale.current) {
                    return true
                }
            }
            #endif
            return false
        }
    }

    #if canImport(FoundationModels) && !os(tvOS)
    /// On-device recommendation generation using Apple Intelligence with constrained sampling.
    @available(iOS 18.0, macOS 15.0, *)
    private func getForYouRecommendationsWithFoundationModels(
        likedItems: [SavedMediaItem]
    ) async throws -> [(title: String, mediaType: String)] {
        let model = SystemLanguageModel.default

        let likedTitles = likedItems.prefix(15).map { item in
            "\(item.title) (\(item.mediaType == .movie ? "Movie" : "TV"))"
        }.joined(separator: ", ")

        let instructions = """
        You are a personalized recommendation engine running entirely on-device. \
        Given a user's liked movies and TV shows, suggest exactly 10 real titles they would enjoy. \
        Mix movies and TV shows. Favour lesser-known gems and recent releases the user likely hasn't seen. \
        Never suggest a title the user already likes. \
        Set each "type" to "movie" or "tv".
        """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let prompt  = "Liked titles: \(likedTitles)"

        // respond(to:generating:) is constrained — the model must emit valid output.
        let response = try await session.respond(to: prompt, generating: ForYouRecommendationOutput.self)

        return response.content.recommendations.compactMap { rec in
            let title = rec.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let type = rec.type.lowercased().hasPrefix("tv") ? "tv" : "movie"
            return (title, type)
        }
    }
    #endif

    /// Cloud fallback. Routes through the same provider abstraction as chat, so
    /// this path can never quietly diverge onto a provider of its own.
    private func getForYouRecommendationsViaCloud(likedItems: [SavedMediaItem]) async throws -> [(title: String, mediaType: String)] {
        guard !likedItems.isEmpty else { return [] }

        let model = nextForYouModel()
        let provider = model.provider
        let providerKey = provider.apiKey
        guard !providerKey.isEmpty else { throw AIError.noApiKey }
        persistKey(for: provider)

        let likedTitles = likedItems.prefix(15).map { item in
            "\(item.title) (\(item.mediaType == .movie ? "Movie" : "TV"))"
        }.joined(separator: ", ")
        
        let systemPrompt = """
        You are a recommendation engine. Given a user's liked titles, suggest exactly 10 titles they would enjoy.
        Mix movies and TV shows. Focus on lesser-known gems and recent releases they likely haven't seen yet.
        Do NOT suggest titles the user already likes.
        
        RESPOND ONLY with a JSON array. No markdown, no explanation, no code fences, no thinking text. Just raw JSON.
        Format: [{"title":"Movie or Show Name","type":"movie"},{"title":"Another Title","type":"tv"}]
        The "type" field must be either "movie" or "tv".
        """
        
        let userMessage = "Liked: \(likedTitles)"
        
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage]
        ]
        
        let requestBody: [String: Any] = [
            "model": model.providerModelId,
            "messages": messages,
            "max_tokens": 600,
            "temperature": 0.9,
            "stream": false
        ]

        guard let url = URL(string: provider.baseURL) else { throw AIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(providerKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 45
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            print("For You API error \(httpResponse.statusCode): \(body.prefix(300))")
            throw AIError.httpError(httpResponse.statusCode)
        }
        
        let llmResponse = try JSONDecoder().decode(LLMResponse.self, from: data)
        guard let content = llmResponse.choices.first?.message.content, !content.isEmpty else {
            throw AIError.noContent
        }
        
        // Parse the JSON array from the response — handle various LLM output quirks
        var cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to extract JSON array if there's surrounding text
        if let startIdx = cleaned.firstIndex(of: "["),
           let endIdx = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[startIdx...endIdx])
        }
        
        guard let jsonData = cleaned.data(using: .utf8) else {
            print("For You: could not convert cleaned content to data")
            throw AIError.noContent
        }
        
        struct Rec: Codable {
            let title: String
            let type: String
        }
        
        do {
            let recs = try JSONDecoder().decode([Rec].self, from: jsonData)
            let results = recs.map { ($0.title, $0.type) }
            if results.isEmpty { throw AIError.noContent }
            return results
        } catch {
            print("For You JSON parse error: \(error), raw content: \(cleaned.prefix(500))")
            throw AIError.noContent
        }
    }
}

// MARK: - Stream Chunk Model
struct StreamChunk: Codable {
    let choices: [StreamChoice]
}

struct StreamChoice: Codable {
    let delta: StreamDelta?
}

struct StreamDelta: Codable {
    let role: String?
    let content: String?
    let reasoning: String?
    let reasoning_content: String?
}

// MARK: - Gemini Native Stream Models
struct GeminiStreamResponse: Codable {
    let candidates: [GeminiCandidate]?
}

struct GeminiCandidate: Codable {
    let content: GeminiContent?
}

struct GeminiContent: Codable {
    let parts: [GeminiPart]?
    let role: String?
}

struct GeminiPart: Codable {
    let text: String?
}

// MARK: - Errors
enum AIError: LocalizedError {
    case noApiKey
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noContent
    
    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "AI API key not configured. Please add an AI provider key in Settings."
        case .invalidResponse:
            return "Invalid response from AI service"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return message
        case .noContent:
            return "No response content"
        }
    }
}

// MARK: - LLM Response Models (OpenAI-compatible, kept for non-stream fallback)
struct LLMResponse: Codable {
    let id: String?
    let choices: [LLMChoice]
    let model: String?
    let usage: LLMUsage?
}

struct LLMChoice: Codable {
    let index: Int?
    let message: LLMMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct LLMMessage: Codable {
    let role: String
    let content: String?
}

struct LLMUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}
