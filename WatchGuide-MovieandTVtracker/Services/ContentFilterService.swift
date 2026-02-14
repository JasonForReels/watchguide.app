//
//  ContentFilterService.swift
//  WatchGuide-MovieandTVtracker
//
//  Content moderation for Scout AI — blocks 18+ content for unverified users
//

import Foundation

class ContentFilterService {
    static let shared = ContentFilterService()
    
    private init() {}
    
    // MARK: - Blocked Word Lists (case-insensitive matching)
    
    /// Explicit sexual content keywords
    private let explicitSexual: Set<String> = [
        "pussy", "cunt", "cock", "dick", "penis", "vagina", "tits", "boobs",
        "porn", "hardcore", "blowjob", "anal", "cum", "orgasm",
        "penetration", "erection", "intercourse", "ejaculation"
    ]
    
    /// Nudity keywords
    private let nudity: Set<String> = [
        "nude", "naked", "full frontal", "topless", "bottomless",
        "uncensored nudity"
    ]
    
    /// Suggestive / mature keywords
    private let suggestiveMature: Set<String> = [
        "slut", "whore", "horny", "hard-on", "kinky", "fetish",
        "bdsm", "erotic", "sensual"
    ]
    
    /// Strong profanity
    private let profanity: Set<String> = [
        "fuck", "shit", "asshole", "motherfucker", "bitch",
        "bastard", "damnit", "goddamn", "bullshit", "crap"
    ]
    
    /// Graphic violence
    private let graphicViolence: Set<String> = [
        "gore", "torture", "mutilate", "decapitate", "rape",
        "abuse", "bloodbath", "dismember"
    ]
    
    /// Multi-word phrases to check for (lowercased)
    private let blockedPhrases: [String] = [
        "sex scene", "full frontal", "uncensored nudity",
        "sexual content", "graphic violence", "sexual act",
        "explicit content", "hard-on", "make love"
    ]
    
    /// All single-word blocklist combined
    private var allBlockedWords: Set<String> {
        explicitSexual
            .union(nudity)
            .union(suggestiveMature)
            .union(profanity)
            .union(graphicViolence)
    }
    
    // MARK: - Public API
    
    /// Checks if text contains blocked content for under-18 / unverified users.
    /// Returns true if content is inappropriate and should be filtered.
    func containsBlockedContent(_ text: String) -> Bool {
        let lowered = text.lowercased()
        
        // Check multi-word phrases first
        for phrase in blockedPhrases {
            if lowered.contains(phrase) {
                return true
            }
        }
        
        // Tokenize and check single words
        let words = tokenize(lowered)
        for word in words {
            if allBlockedWords.contains(word) {
                return true
            }
        }
        
        return false
    }
    
    /// Filters/replaces blocked words in AI output text with asterisks.
    /// Returns the cleaned text.
    func filterOutput(_ text: String) -> String {
        var result = text
        
        // Replace multi-word phrases first (before tokenizing)
        for phrase in blockedPhrases {
            let pattern = "(?i)" + NSRegularExpression.escapedPattern(for: phrase)
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: String(repeating: "*", count: phrase.count)
                )
            }
        }
        
        // Replace single blocked words
        for word in allBlockedWords {
            let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: String(repeating: "*", count: word.count)
                )
            }
        }
        
        return result
    }
    
    /// Returns the family-friendly system prompt addition for unverified users.
    var restrictedModeSystemPrompt: String {
        """
        
        
        CRITICAL CONTENT RESTRICTION — ACTIVE:
        You are operating in restricted mode for users under 18. You MUST follow these rules strictly:
        - NEVER describe, reference, or suggest content involving nudity, sexual acts, explicit language, graphic violence, drug use, or mature themes.
        - NEVER use profanity or vulgar language of any kind.
        - If a user asks about a movie or show with mature content, describe it in general family-friendly terms only (e.g., "This film contains some mature themes" rather than describing them).
        - Do NOT recommend NC-17, X-rated, or unrated adult content.
        - Keep all language clean and appropriate for ages 13 and under.
        - If asked to generate explicit content, politely refuse: "I keep recommendations appropriate for all audiences. How about some great action, comedy, or family-friendly films instead?"
        - Redirect any inappropriate requests to family-friendly alternatives.
        """
    }
    
    // MARK: - Private Helpers
    
    private func tokenize(_ text: String) -> [String] {
        // Split on common delimiters, keeping words only
        let separated = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return separated.filter { !$0.isEmpty }
    }
}
