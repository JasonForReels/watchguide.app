//
//  AIService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

actor AIService {
    static let shared = AIService()
    
    // Poe OpenAI-compatible API endpoint
    private let baseURL = "https://api.poe.com/v1/chat/completions"
    
    private var apiKey: String {
        return ApiKeyManager.shared.get(key: "POE_API_KEY") ?? ""
    }
    
    private init() {}
    
    var isAvailable: Bool {
        !apiKey.isEmpty
    }
    
    // MARK: - Available Models
    enum ChronModel: String, CaseIterable {
        case gemini25Flash = "Gemini-2.5-Flash"
        case gemini20Flash = "Gemini-2.0-Flash"
        case gpt5Nano = "GPT-5-nano"
        
        var displayName: String {
            switch self {
            case .gemini25Flash: return "Gemini 2.5 Flash"
            case .gemini20Flash: return "Gemini 2.0 Flash"
            case .gpt5Nano: return "GPT-5 Nano"
            }
        }
        
        var modelName: String {
            return self.rawValue
        }
        
        var supportsThinking: Bool {
            switch self {
            case .gemini25Flash: return true
            case .gemini20Flash, .gpt5Nano: return false
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
        
        init(role: String, content: String, trailerKey: String? = nil, trailerTitle: String? = nil, thinkingContent: String? = nil) {
            self.id = UUID().uuidString
            self.role = role
            self.content = content
            self.timestamp = Date()
            self.trailerKey = trailerKey
            self.trailerTitle = trailerTitle
            self.thinkingContent = thinkingContent
        }
    }
    
    // MARK: - Trailer Response
    struct TrailerResponse {
        let content: String
        let trailerKey: String
        let trailerTitle: String
    }
    
    // MARK: - Stream Callback
    enum StreamEvent {
        case thinking(String)       // Accumulated thinking text
        case content(String)        // Accumulated content text
        case done                   // Stream finished
        case error(Error)           // Error occurred
    }
    
    // MARK: - Send Message (Non-streaming, for quick actions)
    func sendMessage(
        _ message: String,
        conversationHistory: [ChatMessage],
        likedItems: [SavedMediaItem],
        webSearchEnabled: Bool = true,
        model: ChronModel = .gemini25Flash
    ) async throws -> (String, TrailerResponse?) {
        guard !apiKey.isEmpty else {
            throw AIError.noApiKey
        }
        
        // TRAILER SHORT-CIRCUIT
        if let trailerResponse = await checkForTrailerRequest(message) {
            return (trailerResponse.content, trailerResponse)
        }
        
        var fullContent = ""
        for await event in streamMessage(message, conversationHistory: conversationHistory, likedItems: likedItems, webSearchEnabled: webSearchEnabled, model: model) {
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
        model: ChronModel = .gemini25Flash
    ) -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            Task {
                do {
                    try await self.performStreamRequest(
                        message: message,
                        conversationHistory: conversationHistory,
                        likedItems: likedItems,
                        webSearchEnabled: webSearchEnabled,
                        model: model,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }
        }
    }
    
    // MARK: - Perform Stream Request
    private func performStreamRequest(
        message: String,
        conversationHistory: [ChatMessage],
        likedItems: [SavedMediaItem],
        webSearchEnabled: Bool,
        model: ChronModel,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) async throws {
        guard !apiKey.isEmpty else {
            throw AIError.noApiKey
        }
        
        let systemPrompt = buildSystemPrompt(likedItems: likedItems, webSearchEnabled: webSearchEnabled)
        
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        let recentHistory = conversationHistory.suffix(6)
        for msg in recentHistory {
            messages.append(["role": msg.role, "content": msg.content])
        }
        messages.append(["role": "user", "content": message])
        
        var requestBody: [String: Any] = [
            "model": model.modelName,
            "messages": messages,
            "max_tokens": 1200,
            "temperature": 0.7,
            "stream": true
        ]
        
        // Enable web search via Poe's extra_body parameter
        if webSearchEnabled {
            requestBody["web_search"] = true
        }
        
        guard let url = URL(string: baseURL) else {
            throw AIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 90
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Read the error body
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw AIError.apiError("Error \(httpResponse.statusCode): \(errorBody.prefix(300))")
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
    private func buildSystemPrompt(likedItems: [SavedMediaItem], webSearchEnabled: Bool) -> String {
        var prompt = """
        You are Chron, an AI movie & TV assistant. Concise but complete — never cut off mid-sentence.

        Rules:
        - For simple questions: 2-4 sentences, straight to the point
        - For recommendations: give exactly 2 movies and 2 TV shows. Each with **Title** (Movie/Show) + a short reason (one line). Always finish the full list
        - Use **bold** for titles. No fluff, no disclaimers, no preamble
        - Be casual and fun, like texting a film-buff friend
        - Use bullet points for lists
        - For trailer requests, tell users to ask "trailer for [title]"
        """
        
        if webSearchEnabled {
            prompt += """
            
            - You have web search enabled. When asked about current events, box office numbers, release dates, recent news, ratings, or any factual data that may change over time, USE web search to find up-to-date information. Always provide specific numbers and facts when available.
            - Do NOT say you cannot look things up or that you don't have access to real-time data. You DO have web search — use it.
            """
        }
        
        if !likedItems.isEmpty {
            prompt += "\n\nUser's taste (liked): "
            let titles = likedItems.prefix(15).map { "\($0.title) (\($0.mediaType == .movie ? "M" : "TV"))" }
            prompt += titles.joined(separator: ", ")
        }
        
        return prompt
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
            return "AI API key not configured. Please add your Poe API key in Settings."
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