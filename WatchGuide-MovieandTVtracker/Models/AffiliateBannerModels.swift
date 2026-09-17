//
//  AffiliateBannerModels.swift
//  WatchGuide-MovieandTVtracker
//
//  Codable models for the remote affiliate banner JSON config.
//

import Foundation

// MARK: - Remote JSON Root

struct AffiliateBannerConfig: Codable {
    let version: Int
    let banners: [AffiliateBanner]
}

// MARK: - Single Banner Definition

struct AffiliateBanner: Codable, Identifiable {
    let id: String
    let active: Bool
    let priority: Int
    let partnerName: String
    let title: String
    let subtitle: String
    let affiliateUrl: String
    let imageUrl: String
    let logoUrl: String
    let style: String
    let placements: [String]
    let countries: [String]
    let platforms: [String]
    let startDate: String?
    let endDate: String?

    enum CodingKeys: String, CodingKey {
        case id, active, priority, title, subtitle, style, placements, countries, platforms
        case partnerName = "partner_name"
        case affiliateUrl = "affiliate_url"
        case imageUrl = "image_url"
        case logoUrl = "logo_url"
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

// MARK: - Placement Enum

enum BannerPlacement: String, CaseIterable {
    case browseHeader = "browse_header"
    case browseFooter = "browse_footer"
    case discover = "discover"
    case search = "search"
    case detail = "detail"
    case settings = "settings"
    case lists = "lists"
    case friends = "friends"
    case personDetail = "person_detail"
    case moreHub = "more_hub"
    case aiRecommend = "ai_recommend"
}

// MARK: - Style Enum

enum BannerStyle: String {
    case fullImage = "full_image"
    case label = "label"
    case card = "card"
}
