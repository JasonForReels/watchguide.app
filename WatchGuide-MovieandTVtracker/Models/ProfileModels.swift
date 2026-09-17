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

// MARK: - Hero Carousel Style
/// Which hero carousel presentation the home screen uses.
enum HeroCarouselStyle: String, Codable, CaseIterable, Identifiable {
    /// The original bordered card that pushes slides sideways.
    case classic = "classic"
    /// Layered parallax stage: an ambient background, an alpha-channel subject
    /// cutout that moves faster in front of it, a transparent logo layer, and a
    /// gradient mask that locks the controls in place.
    case cinematic = "cinematic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .cinematic: return "Cinematic"
        }
    }

    var summary: String {
        switch self {
        case .classic:
            return "A framed card that slides between titles. Uses the artwork's own title lettering."
        case .cinematic:
            return "A layered stage with depth: artwork dissolves and pushes in behind a character cutout that moves in front of it, while the title logo and controls stay locked in place. Orientation and width don't apply."
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
    var avatarImageURL: String?  // Remote avatar image URL from avatars.json
    var heroCarouselWidthRatio: Double?
    var heroCarouselAspect: HeroCarouselAspect?
    var heroCarouselStyle: HeroCarouselStyle?
    let createdAt: Date
    var updatedAt: Date
    
    init(
        name: String,
        avatar: ProfileAvatar = .popcorn,
        color: ProfileColor = .blue,
        ageGroup: AgeGroup = .adult,
        isKids: Bool = false,
        dateOfBirth: Date? = nil,
        avatarImageURL: String? = nil,
        heroCarouselWidthRatio: Double? = nil,
        heroCarouselAspect: HeroCarouselAspect? = nil,
        heroCarouselStyle: HeroCarouselStyle? = nil
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.avatar = avatar
        self.color = color
        self.ageGroup = ageGroup
        self.isKids = isKids
        self.dateOfBirth = dateOfBirth
        self.avatarImageURL = avatarImageURL
        self.heroCarouselWidthRatio = heroCarouselWidthRatio
        self.heroCarouselAspect = heroCarouselAspect
        self.heroCarouselStyle = heroCarouselStyle
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
    
    /// Whether the profile has a custom avatar image set
    var hasCustomAvatar: Bool {
        if let url = avatarImageURL, !url.isEmpty { return true }
        return false
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
        lhs.avatarImageURL == rhs.avatarImageURL &&
        lhs.heroCarouselWidthRatio == rhs.heroCarouselWidthRatio &&
        lhs.heroCarouselAspect == rhs.heroCarouselAspect &&
        lhs.heroCarouselStyle == rhs.heroCarouselStyle
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
    let avatarImageUrl: String?
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
        case avatarImageUrl = "avatar_image_url"
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
        try container.encode(avatarImageUrl, forKey: .avatarImageUrl)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
