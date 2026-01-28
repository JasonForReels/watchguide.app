//
//  AIService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

actor AIService {
    static let shared = AIService()
    
    // OpenRouter API for GPT-4o-mini
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
        
        // Build messages array for OpenRouter
        var messages: [[String: String]] = []
        
        // Add system prompt
        let systemPrompt = buildSystemPrompt(likedItems: likedItems)
        messages.append(["role": "system", "content": systemPrompt])
        
        // Add conversation history (last 6 messages for context)
        let recentHistory = conversationHistory.suffix(6)
        for msg in recentHistory {
            messages.append(["role": msg.role, "content": msg.content])
        }
        
        // Add current message
        messages.append(["role": "user", "content": message])
        
        // Build request for OpenRouter API
        let requestBody: [String: Any] = [
            "model": "openai/gpt-4o-mini",
            "messages": messages
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("WatchGuide", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60
        
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
        
        // Parse OpenRouter response (OpenAI-compatible format)
        let decoder = JSONDecoder()
        let openAIResponse = try decoder.decode(OpenAIResponse.self, from: data)
        
        guard let content = openAIResponse.choices.first?.message.content else {
            throw AIError.noContent
        }
        
        return content
    }
    
    // MARK: - Build System Prompt
    private func buildSystemPrompt(likedItems: [SavedMediaItem]) -> String {
        var prompt = """
        You are Chron, a friendly and knowledgeable AI assistant for WatchGuide, a movie and TV discovery app. Your role is to help users discover great content, answer questions about movies and TV shows, and provide personalized recommendations.
        
        Guidelines:
        - Be concise but informative
        - When recommending content, explain why it might appeal to the user
        - If asked about specific titles, provide accurate information about plot, cast, ratings, and where to watch
        - Consider the user's preferences based on their liked items when making recommendations
        - Be conversational and friendly
        - If you don't know something specific, admit it rather than making up information
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

// MARK: - OpenAI Response Models
struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
    }
    
    struct Message: Codable {
        let content: String
    }
}

struct OpenAIErrorResponse: Codable {
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let message: String
    }
}