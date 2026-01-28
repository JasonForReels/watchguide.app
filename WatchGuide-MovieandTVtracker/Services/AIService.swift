//
//  AIService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

actor AIService {
    static let shared = AIService()
    
    // Poe API endpoint for chat completions
    private let baseURL = "https://api.poe.com/bot/chat_completions"
    
    private var apiKey: String {
        ApiKeyManager.shared.get(key: "POE_API_KEY") ?? ""
    }
    
    private init() {}
    
    var isAvailable: Bool {
        !apiKey.isEmpty
    }
    
    // MARK: - Available Models
    enum ChronModel: String, CaseIterable {
        case hermes3 = "nousresearch/hermes-3-llama-3.1-405b:free"
        case gpt4oMini = "gpt-4o-mini"
        
        var displayName: String {
            switch self {
            case .hermes3: return "Hermes 3 (Free)"
            case .gpt4oMini: return "GPT-4o Mini"
            }
        }
        
        // Normalize model for Poe API
        var poeModelName: String {
            switch self {
            case .hermes3: return "nousresearch/hermes-3-llama-3.1-405b:free"
            case .gpt4oMini: return "gpt-4o-mini"
            }
        }
    }
    
    // MARK: - Chat Message
    struct ChatMessage: Codable, Identifiable {
        let id: String
        let role: String
        let content: String
        let timestamp: Date
        var trailerKey: String?
        var trailerTitle: String?
        
        init(role: String, content: String, trailerKey: String? = nil, trailerTitle: String? = nil) {
            self.id = UUID().uuidString
            self.role = role
            self.content = content
            self.timestamp = Date()
            self.trailerKey = trailerKey
            self.trailerTitle = trailerTitle
        }
    }
    
    // MARK: - Trailer Response
    struct TrailerResponse {
        let content: String
        let trailerKey: String
        let trailerTitle: String
    }
    
    // MARK: - Send Message (Main Entry Point)
    func sendMessage(
        _ message: String,
        conversationHistory: [ChatMessage],
        likedItems: [SavedMediaItem],
        webSearchEnabled: Bool = true,
        model: ChronModel = .hermes3
    ) async throws -> (String, TrailerResponse?) {
        guard !apiKey.isEmpty else {
            throw AIError.noApiKey
        }
        
        // TRAILER SHORT-CIRCUIT: Check if user is asking for a trailer
        if let trailerResponse = await checkForTrailerRequest(message) {
            return (trailerResponse.content, trailerResponse)
        }
        
        // Otherwise, proceed with Poe API call
        let response = try await sendMessageToPoe(
            message,
            conversationHistory: conversationHistory,
            likedItems: likedItems,
            webSearchEnabled: webSearchEnabled,
            model: model
        )
        
        return (response, nil)
    }
    
    // MARK: - Trailer Short-Circuit
    private func checkForTrailerRequest(_ message: String) async -> TrailerResponse? {
        let lowercased = message.lowercased()
        
        // Check for trailer-related keywords
        let trailerKeywords = ["trailer", "teaser", "preview", "watch the trailer", "show trailer", "play trailer", "first trailer"]
        let hasTrailerIntent = trailerKeywords.contains { lowercased.contains($0) }
        
        guard hasTrailerIntent else { return nil }
        
        // Parse title from the query
        let title = parseTitle(from: message)
        guard !title.isEmpty else { return nil }
        
        // Determine if looking for "first trailer" specifically
        let wantsFirstTrailer = lowercased.contains("first") || lowercased.contains("original") || lowercased.contains("initial")
        
        // Search TMDB for the title
        do {
            let searchResults = try await TMDBService.shared.searchMulti(query: title)
            guard let bestMatch = searchResults.results.first else { return nil }
            
            // Fetch videos for the matched item
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
            
            // Select the best trailer using heuristics
            let trailer = selectBestTrailer(from: videos.results, preferFirst: wantsFirstTrailer)
            guard let selectedTrailer = trailer else { return nil }
            
            // Compose verified summary
            let yearString = mediaDetails.year ?? "Unknown year"
            let summary = composeTrailerSummary(
                title: mediaDetails.title,
                year: yearString,
                trailerName: selectedTrailer.name,
                overview: mediaDetails.overview
            )
            
            return TrailerResponse(
                content: summary,
                trailerKey: selectedTrailer.key,
                trailerTitle: mediaDetails.title
            )
        } catch {
            print("Trailer lookup failed: \(error), falling back to Poe")
            return nil
        }
    }
    
    private func parseTitle(from message: String) -> String {
        var cleaned = message.lowercased()
        
        // Remove common trailer-related phrases
        let phrasesToRemove = [
            "show me the trailer for",
            "show trailer for",
            "play the trailer for",
            "play trailer for",
            "find the trailer for",
            "find trailer for",
            "get the trailer for",
            "get trailer for",
            "watch the trailer for",
            "watch trailer for",
            "first trailer for",
            "trailer for",
            "teaser for",
            "show me",
            "play",
            "find",
            "get",
            "watch",
            "trailer",
            "teaser",
            "the first",
            "official",
            "please",
            "can you",
            "could you"
        ]
        
        for phrase in phrasesToRemove {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: " ")
        }
        
        // Clean up whitespace and return
        return cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func selectBestTrailer(from videos: [Video], preferFirst: Bool) -> Video? {
        // Filter to only YouTube trailers (excluding teasers, final trailers, etc.)
        let trailers = videos.filter {
            $0.site.lowercased() == "youtube" &&
            $0.type == "Trailer"
        }
        
        guard !trailers.isEmpty else { return nil }
        
        // Keywords that indicate this is NOT a standard "Official Trailer"
        let excludeKeywords = ["final", "teaser", "tv spot", "featurette", "clip", "behind", "making of", "interview", "red band"]
        
        // Keywords that indicate this IS an official trailer we want
        let preferKeywords = ["official trailer", "theatrical trailer", "main trailer"]
        
        // Score and sort trailers
        let scored = trailers.map { video -> (video: Video, score: Int) in
            var score = 0
            let nameLower = video.name.lowercased()
            
            // Strong preference for official trailers
            if video.official == true {
                score += 100
            }
            
            // Boost for preferred keywords
            for keyword in preferKeywords {
                if nameLower.contains(keyword) {
                    score += 50
                    break
                }
            }
            
            // Penalize excluded keywords (final trailer, teaser, etc.)
            for keyword in excludeKeywords {
                if nameLower.contains(keyword) {
                    score -= 200
                    break
                }
            }
            
            // Simple "trailer" in name is good
            if nameLower.contains("trailer") && !nameLower.contains("teaser") {
                score += 20
            }
            
            // Numbered trailers (Trailer 2, Trailer 3) get lower priority than first/main
            if nameLower.contains("trailer 2") || nameLower.contains("trailer 3") || nameLower.contains("trailer #2") || nameLower.contains("trailer #3") {
                score -= 30
            }
            
            return (video, score)
        }
        
        // Sort by score descending, then by date
        let sorted = scored.sorted { item1, item2 in
            if item1.score != item2.score {
                return item1.score > item2.score
            }
            // If scores equal and preferFirst, sort by date ascending (oldest first)
            if preferFirst, let date1 = item1.video.publishedAt, let date2 = item2.video.publishedAt {
                return date1 < date2
            }
            return false
        }
        
        // Return the best scoring trailer
        return sorted.first?.video
    }
    
    private func composeTrailerSummary(title: String, year: String, trailerName: String, overview: String?) -> String {
        var summary = "Here's the trailer for **\(title)** (\(year)):\n\n"
        summary += "**\(trailerName)**\n\n"
        
        if let overview = overview, !overview.isEmpty {
            let shortOverview = String(overview.prefix(200))
            let truncated = overview.count > 200 ? "\(shortOverview)..." : shortOverview
            summary += "_\(truncated)_"
        }
        
        return summary
    }
    
    // MARK: - Send Message to Poe
    private func sendMessageToPoe(
        _ message: String,
        conversationHistory: [ChatMessage],
        likedItems: [SavedMediaItem],
        webSearchEnabled: Bool,
        model: ChronModel
    ) async throws -> String {
        // Build the system prompt with context
        let systemPrompt = buildSystemPrompt(likedItems: likedItems, webSearchEnabled: webSearchEnabled)
        
        // Build OpenAI-style messages array
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // Add recent conversation history
        let recentHistory = conversationHistory.suffix(6)
        for msg in recentHistory {
            messages.append(["role": msg.role, "content": msg.content])
        }
        
        // Add the current user message with optional web search hint
        var userMessage = message
        if webSearchEnabled {
            userMessage = "\(message) --web_search true"
        }
        messages.append(["role": "user", "content": userMessage])
        
        // Get the Poe model name
        let poeModel = model.poeModelName
        
        // Poe API request format
        let requestBody: [String: Any] = [
            "model": poeModel,
            "messages": messages,
            "max_tokens": 1024,
            "temperature": 0.7
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 90
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        // Debug logging
        if let responseString = String(data: data, encoding: .utf8) {
            print("Poe API Response (\(httpResponse.statusCode)): \(responseString)")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: data, encoding: .utf8) {
                throw AIError.apiError("Error \(httpResponse.statusCode): \(responseString)")
            }
            throw AIError.httpError(httpResponse.statusCode)
        }
        
        // Parse response
        let decoder = JSONDecoder()
        let poeResponse = try decoder.decode(PoeResponse.self, from: data)
        
        guard let content = poeResponse.choices.first?.message.content else {
            throw AIError.noContent
        }
        
        return content
    }
    
    // MARK: - Build System Prompt
    private func buildSystemPrompt(likedItems: [SavedMediaItem], webSearchEnabled: Bool) -> String {
        var prompt = """
        You are Chron, a friendly and knowledgeable AI assistant for WatchGuide, a movie and TV discovery app. Your role is to help users discover great content, answer questions about movies and TV shows, and provide personalized recommendations.

        Style Guidelines:
        - Be concise but informative - aim for focused, fact-checked summaries
        - When recommending content, explain why it might appeal to the user
        - Use markdown formatting: **bold** for titles, _italic_ for emphasis
        - Format links as [text](url) when referencing external resources
        - Use bullet points or numbered lists when listing multiple items
        - Keep responses conversational and friendly

        Important:
        - If asked about trailers, mention that users can ask "Show me the trailer for [title]" for quick access
        - Consider the user's preferences based on their liked items when making recommendations
        - Provide accurate information about plot, cast, ratings, and streaming availability
        - If you're uncertain about something, acknowledge it
        
        """
        
        // Add web search context if enabled
        if webSearchEnabled {
            prompt += """
            
            Web Search Enabled:
            - You have access to web search for up-to-date information
            - Use this to provide current release dates, streaming availability, and recent entertainment news
            - Always cite information as being current when using web search results
            
            """
        }
        
        // Inject liked items context for personalization
        if !likedItems.isEmpty {
            prompt += "\n**User's Liked Items** (use this to personalize recommendations):\n"
            for item in likedItems.prefix(20) {
                let typeStr = item.mediaType == .movie ? "Movie" : "TV"
                prompt += "- \(item.title) (\(typeStr), \(item.year ?? "unknown year"))\n"
            }
        }
        
        return prompt
    }
    
    // MARK: - Quick Actions
    func getSimilarRecommendations(for title: String, mediaType: MediaType) async throws -> String {
        let message = "Suggest 5 \(mediaType == .movie ? "movies" : "TV shows") similar to '\(title)'. For each, briefly explain what makes it similar and why fans might enjoy it."
        let (response, _) = try await sendMessage(message, conversationHistory: [], likedItems: [])
        return response
    }
    
    func getMediaSummary(title: String, overview: String?) async throws -> String {
        let message = "Give me a brief, engaging summary of '\(title)'. Include: genre, tone, notable aspects, and who would enjoy it. \(overview != nil ? "Context: \(overview!)" : "")"
        let (response, _) = try await sendMessage(message, conversationHistory: [], likedItems: [])
        return response
    }
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
            return "Poe API key not configured. Please add your API key in Settings."
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

// MARK: - Poe Response Models
struct PoeResponse: Codable {
    let id: String?
    let choices: [PoeChoice]
    let model: String?
    let usage: PoeUsage?
}

struct PoeChoice: Codable {
    let index: Int?
    let message: PoeMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct PoeMessage: Codable {
    let role: String
    let content: String
}

struct PoeUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}