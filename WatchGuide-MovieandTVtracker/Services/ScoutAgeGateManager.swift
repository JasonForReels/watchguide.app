//
//  ScoutAgeGateManager.swift
//  WatchGuide-MovieandTVtracker
//
//  Manages content restriction state based on the "Include Adult Content" toggle in Settings
//  and the Kids Profile toggle.
//  Toggle OFF = restricted mode (family-friendly, 16 and under).
//  Toggle ON = unrestricted mode (18+).
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
        StorageService.shared.settings.isKidsProfile
    }
    
    /// True when "Include Adult Content" toggle is ON and NOT a kids profile — no content restrictions.
    var isUnrestricted: Bool {
        !isKidsProfile && StorageService.shared.settings.includeAdult
    }
    
    /// True when "Include Adult Content" toggle is OFF or kids profile is active — restricted / family-friendly mode.
    var isRestricted: Bool {
        isKidsProfile || !StorageService.shared.settings.includeAdult
    }
    
    /// Whether Scout AI should be completely hidden (kids profile = 13 and under).
    var isScoutHidden: Bool {
        isKidsProfile
    }
    
    /// Human-readable label for the current mode.
    var modeLabel: String {
        if isKidsProfile {
            return "Kids mode (13 and under)"
        }
        return isUnrestricted ? "Unrestricted mode (18+)" : "Restricted mode (16 and under)"
    }
}
