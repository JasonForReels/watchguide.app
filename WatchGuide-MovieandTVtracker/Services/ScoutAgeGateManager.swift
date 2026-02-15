//
//  ScoutAgeGateManager.swift
//  WatchGuide-MovieandTVtracker
//
//  Manages content restriction state based on profiles and the Kids Profile toggle.
//  Scout AI ALWAYS has content filtering enforced (required for App Store 13+ rating).
//  The "Include Adult Content" toggle only affects TMDB browse results, NOT Scout AI.
//  Profiles integrate with age groups: Kids (6-12), Teen (13-17), Adult (18+).
//  Kids Profile ON = extra-strict kids mode + Scout AI hidden.
//

import Foundation
import SwiftUI

@MainActor
class ScoutAgeGateManager: ObservableObject {
    static let shared = ScoutAgeGateManager()
    
    private init() {}
    
    /// True when Kids Profile is active — content is restricted to 13 and under.
    var isKidsProfile: Bool {
        ProfileService.shared.activeProfile?.isKids == true || StorageService.shared.settings.isKidsProfile
    }
    
    /// The active age group from the profile system
    var activeAgeGroup: AgeGroup {
        ProfileService.shared.activeProfile?.ageGroup ?? (isKidsProfile ? .kids : .adult)
    }
    
    /// Scout AI content filtering is ALWAYS on. This property indicates whether
    /// the extra-strict kids mode is active (which adds additional restrictions
    /// beyond the baseline 13+ safety filter).
    var isKidsRestricted: Bool {
        isKidsProfile || activeAgeGroup == .kids
    }
    
    /// Scout AI always has content safety enforced. This is no longer toggleable.
    /// The "Include Adult Content" setting only affects TMDB browse results.
    var isUnrestricted: Bool {
        false // Scout AI content filtering is always on
    }
    
    /// Content filtering is always active for Scout AI.
    var isRestricted: Bool {
        true // Always restricted for App Store 13+ compliance
    }
    
    /// Whether Scout AI should be completely hidden (only available for 18+ adult profiles).
    var isScoutHidden: Bool {
        isKidsProfile || activeAgeGroup != .adult
    }
    
    /// Human-readable label for the current mode.
    var modeLabel: String {
        if isKidsProfile {
            return "Kids mode (6-12)"
        }
        switch activeAgeGroup {
        case .kids:
            return "Kids mode (6-12)"
        case .teen:
            return "Teen mode (13-17)"
        case .adult:
            return "Content filtered (13+ safe)"
        }
    }
}
