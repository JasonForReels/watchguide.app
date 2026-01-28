//
//  AIService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

actor AIService {
    static let shared = AIService()
    
    // Poe API endpoint - using the correct format for Poe's bot API
    private let baseURL = "https://api.poe.com/bot/"
    
    private var apiKey: String {
        ApiKeyManager.shared.get(key: "POE_API_KEY") ?? ""
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
        
        // Build the full message with context
        let systemPrompt = buildSystemPrompt(likedItems: likedItems)
        
        // Build conversation context
        var conversationContext = ""
        let recentHistory = conversationHistory.suffix(6)
        for msg in recentHistory {
            let role = msg.role == "user" ? "User" : "Assistant"
            conversationContext += "\(role): \(msg.content)\n\n"
        }
        
        let fullMessage = """
        \(systemPrompt)
        
        Conversation so far:
        \(conversationContext)
        
        User: \(message)
        
        Assistant:
        """
        
        // Poe API request format - using gpt-4o-mini-search model
        let requestBody: [String: Any] = [
            "query": [
                [
                    "role": "user",
                    "content": fullMessage
                ]
            ],
            "user_id": "watchguide_user",
            "conversation_id": UUID().uuidString
        ]
        
        // Use gpt-4o-mini-search on Poe for web search capabilities
        var request = URLRequest(url: URL(string: "\(baseURL)gpt-4o-mini-search")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        // Debug: print the response for troubleshooting
        if let responseString = String(data: data, encoding: .utf8) {
            print("Poe API Response (\(httpResponse.statusCode)): \(responseString)")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: data, encoding: .utf8) {
                throw AIError.apiError("Error \(httpResponse.statusCode): \(responseString)")
            }
            throw AIError.httpError(httpResponse.statusCode)
        }
        
        // Parse Poe response
        let decoder = JSONDecoder()
        let poeResponse = try decoder.decode(PoeResponse.self, from: data)
        
        guard let content = poeResponse.text else {
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

// MARK: - Poe Response Models
struct PoeResponse: Codable {
    let text: String?
    let status: String?
    
    enum CodingKeys: String, CodingKey {
        case text
        case status
    }
}

struct PoeErrorResponse: Codable {
    let error: String?
    let message: String?
}