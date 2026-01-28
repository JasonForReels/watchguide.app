//
//  AIService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

actor AIService {
    static let shared = AIService()
    
    private var apiKey: String {
        ApiKeyManager.shared.get(key: "OPENAI_API_KEY") ?? ""
    }
    
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
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
        
        var messages: [[String: String]] = []
        
        // System prompt with context
        let systemPrompt = buildSystemPrompt(likedItems: likedItems)
        messages.append(["role": "system", "content": systemPrompt])
        
        // Add conversation history (last 10 messages)
        let recentHistory = conversationHistory.suffix(10)
        for msg in recentHistory {
            messages.append(["role": msg.role, "content": msg.content])
        }
        
        // Add current message
        messages.append(["role": "user", "content": message])
        
        // Build request
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "max_tokens": 1024,
            "temperature": 0.7
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw AIError.apiError(errorResponse.error.message)
            }
            throw AIError.httpError(httpResponse.statusCode)
        }
        
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = decoded.choices.first?.message.content else {
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
            return "OpenAI API key not configured"
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
