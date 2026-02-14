//
//  ScoutAgeGateManager.swift
//  WatchGuide-MovieandTVtracker
//
//  Manages content restriction state based on the "Include Adult Content" toggle in Settings.
//  Toggle OFF = restricted mode (family-friendly, 16 and under).
//  Toggle ON = unrestricted mode (18+).
//

import Foundation
import SwiftUI

@MainActor
class ScoutAgeGateManager: ObservableObject {
    static let shared = ScoutAgeGateManager()
    
    private init() {}
    
    /// True when "Include Adult Content" toggle is ON — no content restrictions.
    var isUnrestricted: Bool {
        StorageService.shared.settings.includeAdult
    }
    
    /// True when "Include Adult Content" toggle is OFF — restricted / family-friendly mode.
    var isRestricted: Bool {
        !StorageService.shared.settings.includeAdult
    }
    
    /// Human-readable label for the current mode.
    var modeLabel: String {
        isUnrestricted ? "Unrestricted mode (18+)" : "Restricted mode (16 and under)"
    }
}
