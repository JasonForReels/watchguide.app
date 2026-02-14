//
//  ScoutAgeGateManager.swift
//  WatchGuide-MovieandTVtracker
//
//  Manages Scout age verification state.
//  Unverified users (guest or under 18) get content filtering.
//  Verified 18+ users get full Scout access.
//

import Foundation
import SwiftUI

@MainActor
class ScoutAgeGateManager: ObservableObject {
    static let shared = ScoutAgeGateManager()
    
    /// Whether the user has passed age verification this session
    @Published var isAgeVerified: Bool = false
    
    /// Date of birth provided during verification (not persisted)
    @Published var verifiedBirthDate: Date?
    
    private init() {}
    
    /// Returns true if the user is signed in AND has verified they are 18+
    var isUnrestricted: Bool {
        AuthService.shared.isAuthenticated && isAgeVerified
    }
    
    /// Verify age from a birth date. Returns true if 18+.
    func verify(birthDate: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: now)
        let age = ageComponents.year ?? 0
        
        if age >= 18 {
            verifiedBirthDate = birthDate
            isAgeVerified = true
            return true
        }
        
        isAgeVerified = false
        verifiedBirthDate = nil
        return false
    }
    
    /// Reset verification (e.g., when leaving Scout tab or on each visit)
    func resetVerification() {
        isAgeVerified = false
        verifiedBirthDate = nil
    }
}
