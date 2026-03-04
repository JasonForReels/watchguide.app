//
//  ProfileModels.swift
//  WatchGuide-MovieandTVtracker
//
//  Profile system models for multi-profile support
//

import Foundation
import SwiftUI

// MARK: - Age Group
enum AgeGroup: String, Codable, CaseIterable, Identifiable {
    case kids = "kids"           // 6-12 (auto-set for Kids profiles)
    case teen = "teen"           // 13-17
    case adult = "adult"         // 18+
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .kids: return "Kids (6-12)"
        case .teen: return "Teen (13-17)"
        case .adult: return "Adult (18+)"
        }
    }
    
    var ageRange: String {
        switch self {
        case .kids: return "6-12"
        case .teen: return "13-17"
        case .adult: return "18+"
        }
    }
    
    var isRestricted: Bool {
        self == .kids || self == .teen
    }
}

// MARK: - Profile Avatar
enum ProfileAvatar: String, Codable, CaseIterable, Identifiable {
    case popcorn = "popcorn.fill"
    case film = "film.fill"
    case tv = "tv.fill"
    case star = "star.fill"
    case heart = "heart.fill"
    case sparkles = "sparkles"
    case gamecontroller = "gamecontroller.fill"
    case music = "music.note"
    case book = "book.fill"
    case globe = "globe"
    case pawprint = "pawprint.fill"
    case leaf = "leaf.fill"
    
    var id: String { rawValue }
}

// MARK: - Profile Color
enum ProfileColor: String, Codable, CaseIterable, Identifiable {
    case blue = "blue"
    case red = "red"
    case green = "green"
    case orange = "orange"
    case purple = "purple"
    case pink = "pink"
    case teal = "teal"
    case yellow = "yellow"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .blue: return .blue
        case .red: return .red
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .pink: return .pink
        case .teal: return .teal
        case .yellow: return .yellow
        }
    }
}

// MARK: - Hero Carousel Aspect
enum HeroCarouselAspect: String, Codable, CaseIterable, Identifiable {
    case landscape = "landscape"
    case portrait = "portrait"
    
    var id: String { rawValue }
    
    var aspectRatio: CGFloat {
        switch self {
        case .landscape:
            return 16.0 / 9.0
        case .portrait:
            return 2.0 / 3.0
        }
    }
}

// MARK: - User Profile
struct UserProfile: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var avatar: ProfileAvatar
    var color: ProfileColor
    var ageGroup: AgeGroup
    var isKids: Bool        // Locked kids profile (like Netflix Kids)
    var dateOfBirth: Date?  // Used to verify age
    var heroCarouselWidthRatio: Double?
    var heroCarouselAspect: HeroCarouselAspect?
    let createdAt: Date
    var updatedAt: Date
    
    init(
        name: String,
        avatar: ProfileAvatar = .popcorn,
        color: ProfileColor = .blue,
        ageGroup: AgeGroup = .adult,
        isKids: Bool = false,
        dateOfBirth: Date? = nil,
        heroCarouselWidthRatio: Double? = nil,
        heroCarouselAspect: HeroCarouselAspect? = nil
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.avatar = avatar
        self.color = color
        self.ageGroup = ageGroup
        self.isKids = isKids
        self.dateOfBirth = dateOfBirth
        self.heroCarouselWidthRatio = heroCarouselWidthRatio
        self.heroCarouselAspect = heroCarouselAspect
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Computed age from date of birth
    var computedAge: Int? {
        guard let dob = dateOfBirth else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: dob, to: Date())
        return components.year
    }
    
    /// Creates the default "Kids" profile (locked, age 6-12)
    static func kidsProfile(name: String = "Kids") -> UserProfile {
        UserProfile(
            name: name,
            avatar: .pawprint,
            color: .green,
            ageGroup: .kids,
            isKids: true,
            dateOfBirth: nil
        )
    }
    
    static func == (lhs: UserProfile, rhs: UserProfile) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.avatar == rhs.avatar &&
        lhs.color == rhs.color &&
        lhs.ageGroup == rhs.ageGroup &&
        lhs.isKids == rhs.isKids &&
        lhs.dateOfBirth == rhs.dateOfBirth &&
        lhs.heroCarouselWidthRatio == rhs.heroCarouselWidthRatio &&
        lhs.heroCarouselAspect == rhs.heroCarouselAspect
    }
}


// MARK: - Synced Profile (Supabase)
struct SyncedProfile: Codable {
    let userId: String
    let profileId: String
    let name: String
    let avatar: String
    let color: String
    let ageGroup: String
    let isKids: Bool
    let dateOfBirth: String?
    // NOTE: hero_carousel_width_ratio and hero_carousel_aspect are stored
    // locally only — they are NOT columns in the Supabase profiles table.
    let createdAt: Date?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case profileId = "profile_id"
        case name
        case avatar
        case color
        case ageGroup = "age_group"
        case isKids = "is_kids"
        case dateOfBirth = "date_of_birth"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // Explicitly encode all keys (including nil as null) to avoid PGRST102
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(profileId, forKey: .profileId)
        try container.encode(name, forKey: .name)
        try container.encode(avatar, forKey: .avatar)
        try container.encode(color, forKey: .color)
        try container.encode(ageGroup, forKey: .ageGroup)
        try container.encode(isKids, forKey: .isKids)
        try container.encode(dateOfBirth, forKey: .dateOfBirth)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
