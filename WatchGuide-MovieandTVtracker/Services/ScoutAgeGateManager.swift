//
//  ScoutAgeGateManager.swift
//  WatchGuide-MovieandTVtracker
//
//  Manages content restriction state based on profiles, the "Include Adult Content" toggle
//  in Settings, and the Kids Profile toggle.
//  Profiles integrate with age groups: Kids (6-12), Teen (13-17), Adult (18+).
//  Kids Profile ON = restricted mode + Scout AI hidden (13 and under).
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
    
    /// True when "Include Adult Content" toggle is ON, NOT a kids profile, and age group is adult — no content restrictions.
    var isUnrestricted: Bool {
        !isKidsProfile && activeAgeGroup == .adult && StorageService.shared.settings.includeAdult
    }
    
    /// True when "Include Adult Content" toggle is OFF, kids profile is active, or age group is restricted.
    var isRestricted: Bool {
        isKidsProfile || activeAgeGroup != .adult || !StorageService.shared.settings.includeAdult
    }
    
    /// Whether Scout AI should be completely hidden (kids profile = 13 and under).
    var isScoutHidden: Bool {
        isKidsProfile
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
            return isUnrestricted ? "Unrestricted mode (18+)" : "Restricted mode (16 and under)"
        }
    }
}
