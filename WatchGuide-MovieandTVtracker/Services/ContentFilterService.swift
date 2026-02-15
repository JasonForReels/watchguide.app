//
//  ContentFilterService.swift
//  WatchGuide-MovieandTVtracker
//
//  Content moderation for Scout AI — ALWAYS enforced to keep app rated 13+.
//  All Scout AI output is filtered regardless of user settings.
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
        "penetration", "erection", "intercourse", "ejaculation",
        "hentai", "xxx", "dildo", "vibrator", "masturbat",
        "threesome", "foursome", "orgy", "stripper", "prostitut",
        "genitals", "genitalia", "clitoris", "labia", "scrotum",
        "semen", "sperm", "arousal", "aroused", "climax"
    ]
    
    /// Nudity keywords
    private let nudity: Set<String> = [
        "nude", "naked", "full frontal", "topless", "bottomless",
        "uncensored nudity", "nudity", "nudes", "undress",
        "unclothed", "bare breasts", "bare buttocks"
    ]
    
    /// Suggestive / mature keywords
    private let suggestiveMature: Set<String> = [
        "slut", "whore", "horny", "hard-on", "kinky", "fetish",
        "bdsm", "erotic", "sensual", "dominatrix", "submissive",
        "sadomasochism", "bondage", "voyeur", "exhibitionist",
        "seduction", "seduce", "aphrodisiac", "foreplay",
        "provocative", "risque", "lust", "lustful", "nympho",
        "orgasmic", "promiscuous", "titillat"
    ]
    
    /// Strong profanity
    private let profanity: Set<String> = [
        "fuck", "fucking", "fucked", "fucker", "fucks",
        "shit", "shitting", "shitty",
        "asshole", "motherfucker", "motherfucking", "bitch",
        "bastard", "damnit", "goddamn", "bullshit", "crap",
        "cocksucker", "dipshit", "jackass", "piss",
        "nigger", "nigga", "faggot", "retard", "retarded"
    ]
    
    /// Graphic violence
    private let graphicViolence: Set<String> = [
        "gore", "gory", "torture", "tortured", "mutilate", "mutilation",
        "decapitate", "decapitation", "rape", "raped", "raping",
        "abuse", "bloodbath", "dismember", "dismemberment",
        "eviscerate", "disembowel", "castrate", "castration",
        "infanticide", "pedophil", "paedophil", "incest",
        "necrophil", "bestiality", "zoophil", "snuff"
    ]
    
    /// Drug-related explicit content
    private let drugContent: Set<String> = [
        "cocaine", "heroin", "methamphetamine", "meth", "crack",
        "ecstasy", "mdma", "lsd", "fentanyl", "overdose",
        "shooting up", "snorting", "injecting drugs"
    ]
    
    /// Multi-word phrases to check for (lowercased)
    private let blockedPhrases: [String] = [
        "sex scene", "full frontal", "uncensored nudity",
        "sexual content", "graphic violence", "sexual act",
        "explicit content", "hard-on", "make love",
        "sex tape", "adult film", "adult movie", "adult content",
        "graphic sex", "graphic nudity", "graphic sexual",
        "sexual intercourse", "sexual assault", "child abuse",
        "child pornography", "child exploitation",
        "drug use", "drug abuse", "substance abuse",
        "self harm", "self-harm", "suicide method",
        "how to kill", "how to murder",
        "sexual fantasy", "sexual desire", "sexual pleasure",
        "erotic scene", "nude scene", "love scene",
        "blood and gore", "extreme violence", "graphic torture",
        "red band", "unrated version", "director's cut unrated"
    ]
    
    /// Partial-match patterns — check if any word CONTAINS these substrings
    private let blockedSubstrings: [String] = [
        "porn", "xxx", "nsfw", "hentai", "orgasm",
        "masturbat", "pedophil", "paedophil", "necrophil",
        "zoophil", "bestiality", "incest"
    ]
    
    /// All single-word blocklist combined
    private var allBlockedWords: Set<String> {
        explicitSexual
            .union(nudity)
            .union(suggestiveMature)
            .union(profanity)
            .union(graphicViolence)
            .union(drugContent)
    }
    
    // MARK: - Public API
    
    /// Checks if text contains blocked content. This is ALWAYS enforced for Scout AI
    /// to maintain the app's 13+ age rating on the App Store.
    /// Returns true if content is inappropriate and should be filtered.
    func containsBlockedContent(_ text: String) -> Bool {
        let lowered = text.lowercased()
        
        // Check multi-word phrases first
        for phrase in blockedPhrases {
            if lowered.contains(phrase) {
                return true
            }
        }
        
        // Check partial-match substrings (catches variations like "pornographic", "masturbating" etc.)
        for substring in blockedSubstrings {
            if lowered.contains(substring) {
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
    static let refusalMessage = "I can't help with that — let's keep things appropriate! Try asking about a movie, show, or something else I can help with."
    
    /// Checks AI output for blocked content. If any is found, replaces the
    /// entire response with the standard refusal message instead of asterisking
    /// individual words — this ensures nothing inappropriate leaks through.
    /// This is ALWAYS applied to all Scout AI output regardless of user settings.
    func filterOutput(_ text: String) -> String {
        if containsBlockedContent(text) {
            return Self.refusalMessage
        }
        return text
    }
    
    /// The content safety system prompt that is ALWAYS injected into Scout AI requests.
    /// This ensures the AI never generates content inappropriate for a 13+ rated app,
    /// regardless of the user's age profile or settings.
    var alwaysOnSafetyPrompt: String {
        """
        
        
        MANDATORY CONTENT SAFETY POLICY (ALWAYS ACTIVE — NO EXCEPTIONS):
        This app is rated 13+ on the App Store. You MUST follow these rules at ALL times, for ALL users:
        - NEVER use profanity, vulgar language, slurs, or explicit language of any kind.
        - NEVER describe, reference, or detail nudity, sexual acts, sexual content, or sexually suggestive material.
        - NEVER provide graphic descriptions of violence, gore, torture, or abuse.
        - NEVER describe drug use in graphic or instructional detail.
        - When discussing movies or shows with mature content (R-rated, NC-17, etc.), keep descriptions general and age-appropriate (e.g., "This film deals with mature themes including violence" — do NOT describe those themes in detail).
        - You MAY recommend R-rated movies/shows, but describe them in clean, non-graphic language suitable for ages 13+.
        - Do NOT recommend NC-17, X-rated, or unrated adult/pornographic content.
        - If a user asks you to generate explicit, sexual, or extremely violent content, politely decline: "I can't help with that — let's keep things appropriate! Try asking about a movie, show, or something else I can help with."
        - All language must be clean and appropriate for a general audience of ages 13 and up.
        """
    }
    
    /// Returns the kids-mode system prompt (stricter, 13 and under).
    var kidsModeSystemPrompt: String {
        """
        
        
        ADDITIONAL RESTRICTION — KIDS MODE ACTIVE (13 AND UNDER):
        You are operating in kids mode. You MUST follow these additional rules with zero exceptions:
        - ONLY recommend G-rated, PG-rated, and family-friendly content.
        - NEVER mention, describe, or reference any content involving violence, horror, scary themes, drug use, romance beyond hand-holding, or any mature themes whatsoever.
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
