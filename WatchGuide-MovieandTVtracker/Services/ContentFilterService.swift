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
    
    /// The standard refusal message shown when blocked content is detected.
    static let refusalMessage = "Sorry, I can't help with that request, please try something else."
    
    /// Checks AI output for blocked content. If any is found, replaces the
    /// entire response with the standard refusal message instead of asterisking
    /// individual words — this ensures nothing inappropriate leaks through.
    func filterOutput(_ text: String) -> String {
        if containsBlockedContent(text) {
            return Self.refusalMessage
        }
        return text
    }
    
    /// Returns the family-friendly system prompt addition for restricted users (16 and under).
    var restrictedModeSystemPrompt: String {
        """
        
        
        CRITICAL CONTENT RESTRICTION — ACTIVE:
        You are operating in restricted mode for users under 18. You MUST follow these rules strictly:
        - NEVER describe, reference, or suggest content involving nudity, sexual acts, explicit language, graphic violence, drug use, or mature themes.
        - NEVER use profanity or vulgar language of any kind.
        - If a user asks about a movie or show with mature content, describe it in general family-friendly terms only (e.g., "This film contains some mature themes" rather than describing them).
        - Do NOT recommend NC-17, X-rated, or unrated adult content.
        - Keep all language clean and appropriate for ages 13 and under.
        - If asked to generate explicit content, politely refuse: "Sorry, I can't help with that request, please try something else."
        - Redirect any inappropriate requests to family-friendly alternatives.
        """
    }
    
    /// Returns the kids-mode system prompt (stricter, 13 and under).
    var kidsModeSystemPrompt: String {
        """
        
        
        CRITICAL CONTENT RESTRICTION — KIDS MODE ACTIVE (13 AND UNDER):
        You are operating in kids mode. You MUST follow these rules with zero exceptions:
        - ONLY recommend G-rated, PG-rated, and family-friendly content.
        - NEVER mention, describe, or reference any content involving violence, horror, scary themes, drug use, romance beyond hand-holding, or any mature themes whatsoever.
        - NEVER use any profanity, slang, or language that is not appropriate for children.
        - Keep all responses simple, upbeat, and fun.
        - If asked about a movie or show with any mature content (PG-13 or above), briefly note it's not for kids and suggest a family-friendly alternative.
        - If asked to generate any inappropriate content, politely refuse: "That's not something I can help with! How about we find a fun movie or show instead?"
        - Focus on animated movies, family comedies, adventure films, and kid-friendly TV shows.
        """
    }
    
    // MARK: - Private Helpers
    
    private func tokenize(_ text: String) -> [String] {
        // Split on common delimiters, keeping words only
        let separated = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return separated.filter { !$0.isEmpty }
    }
}
