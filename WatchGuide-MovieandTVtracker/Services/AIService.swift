//
//  AIService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

actor AIService {
    static let shared = AIService()
    
    // OpenRouter API endpoint - reliable and supports many models
    private let baseURL = "https://openrouter.ai/api/v1/chat/completions"
    
    private var apiKey: String {
        ApiKeyManager.shared.get(key: "OPENROUTER_API_KEY") ?? ""
    }
    
    private init() {}
    
    var isAvailable: Bool {
        !apiKey.isEmpty
    }
    
    // MARK: - Chat Message
    struct ChatMessage: Codable, Identifiable {
        let id: String
        let role: String
        let content: String
        let timestamp: Date
        
        init(role: String, content: String) {
            self.id = UUID().uuidString
            self.role = role
            self.content = content
            self.timestamp = Date()
        }
    }
    
    // MARK: - Send Message
    func sendMessage(
        _ message: String,
        conversationHistory: [ChatMessage],
        likedItems: [SavedMediaItem]
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AIError.noApiKey
        }
        
        // Build the system prompt with context
        let systemPrompt = buildSystemPrompt(likedItems: likedItems)
        
        // Build messages array for OpenRouter
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // Add recent conversation history
        let recentHistory = conversationHistory.suffix(6)
        for msg in recentHistory {
            messages.append(["role": msg.role, "content": msg.content])
        }
        
        // Add the current user message
        messages.append(["role": "user", "content": message])
        
        // OpenRouter API request format with Hermes 3 405B free model and web search
        let requestBody: [String: Any] = [
            "model": "nousresearch/hermes-3-llama-3.1-405b:free",
            "messages": messages,
            "max_tokens": 1024,
            "temperature": 0.7,
            "plugins": [
                ["id": "web"]
            ]
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("WatchGuide App", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 90 // Longer timeout for web search
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        // Debug: print the response for troubleshooting
        if let responseString = String(data: data, encoding: .utf8) {
            print("OpenRouter API Response (\(httpResponse.statusCode)): \(responseString)")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: data, encoding: .utf8) {
                throw AIError.apiError("Error \(httpResponse.statusCode): \(responseString)")
            }
            throw AIError.httpError(httpResponse.statusCode)
        }
        
        // Parse OpenRouter response
        let decoder = JSONDecoder()
        let openRouterResponse = try decoder.decode(OpenRouterResponse.self, from: data)
        
        guard let content = openRouterResponse.choices.first?.message.content else {
            throw AIError.noContent
        }
        
        return content
    }
    
    // MARK: - Build System Prompt
    private func buildSystemPrompt(likedItems: [SavedMediaItem]) -> String {
        var prompt = """
        You are Chron, a friendly and knowledgeable AI assistant for WatchGuide, a movie and TV discovery app. Your role is to help users discover great content, answer questions about movies and TV shows, and provide personalized recommendations.
        
        You have web search capabilities, so you can look up current information about movies, TV shows, release dates, cast, reviews, and entertainment news.
        
        Guidelines:
        - Be concise but informative
        - When recommending content, explain why it might appeal to the user
        - If asked about specific titles, provide accurate information about plot, cast, ratings, and where to watch
        - Use web search to get the latest information about new releases, streaming availability, and current entertainment news
        - Consider the user's preferences based on their liked items when making recommendations
        - Be conversational and friendly
        - If you don't know something specific, use web search to find accurate information
        - Format responses nicely with bullet points or numbered lists when appropriate
        
        """
        
        // Add user preferences context
        if !likedItems.isEmpty {
            prompt += "\nThe user has liked these titles (use this to personalize recommendations):\n"
            for item in likedItems.prefix(20) {
                prompt += "- \(item.title) (\(item.mediaType.rawValue), \(item.year ?? "unknown year"))\n"
            }
        }
        
        return prompt
    }
    
    // MARK: - Quick Actions
    func getSimilarRecommendations(for title: String, mediaType: MediaType) async throws -> String {
        let message = "Suggest 5 \(mediaType == .movie ? "movies" : "TV shows") similar to '\(title)'. For each, briefly explain what makes it similar and why fans might enjoy it."
        return try await sendMessage(message, conversationHistory: [], likedItems: [])
    }
    
    func getMediaSummary(title: String, overview: String?) async throws -> String {
        let message = "Give me a brief, engaging summary of '\(title)'. Include: genre, tone, notable aspects, and who would enjoy it. \(overview != nil ? "Context: \(overview!)" : "")"
        return try await sendMessage(message, conversationHistory: [], likedItems: [])
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
            return "OpenRouter API key not configured. Please add your API key in Settings."
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

// MARK: - OpenRouter Response Models
struct OpenRouterResponse: Codable {
    let id: String?
    let choices: [OpenRouterChoice]
    let model: String?
    let usage: OpenRouterUsage?
}

struct OpenRouterChoice: Codable {
    let index: Int?
    let message: OpenRouterMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct OpenRouterMessage: Codable {
    let role: String
    let content: String
}

struct OpenRouterUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}