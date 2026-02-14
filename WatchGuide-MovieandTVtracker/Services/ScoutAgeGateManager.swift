//
//  ScoutAgeGateManager.swift
//  WatchGuide-MovieandTVtracker
//
//  Manages Scout age verification state.
//  Logged-in users must verify DOB once per session.
//  Guest users get content filtering on explicit words.
//  Under-18 users (logged-in but failed DOB) get full restriction.
//

import Foundation
import SwiftUI

@MainActor
class ScoutAgeGateManager: ObservableObject {
    static let shared = ScoutAgeGateManager()
    
    /// Whether the logged-in user has completed DOB verification this session
    @Published var isAgeVerified: Bool = false
    
    /// Whether the logged-in user was verified as under 18
    @Published var isUnder18: Bool = false
    
    /// Whether the DOB popup should be shown
    @Published var showDOBPrompt: Bool = false
    
    private init() {}
    
    /// True if the user should have NO content restrictions at all.
    /// Only true if signed in AND verified 18+.
    var isUnrestricted: Bool {
        AuthService.shared.isAuthenticated && isAgeVerified && !isUnder18
    }
    
    /// True if the user is signed in but verified under 18 —
    /// they should get the refusal for ALL messages (not just explicit ones).
    var isUnder18Restricted: Bool {
        AuthService.shared.isAuthenticated && isAgeVerified && isUnder18
    }
    
    /// Verify age from a birth date. Returns true if 18+.
    func verify(birthDate: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: now)
        let age = ageComponents.year ?? 0
        
        isAgeVerified = true
        
        if age >= 18 {
            isUnder18 = false
            return true
        }
        
        isUnder18 = true
        return false
    }
    
    /// Trigger DOB prompt for a logged-in user who hasn't verified yet
    func promptIfNeeded() {
        if AuthService.shared.isAuthenticated && !isAgeVerified {
            showDOBPrompt = true
        }
    }
    
    /// Reset verification (e.g., on sign out)
    func resetVerification() {
        isAgeVerified = false
        isUnder18 = false
        showDOBPrompt = false
    }
}
