//
//  DeepDiveModels.swift
//  WatchGuide-MovieandTVtracker
//
//  Structured Atlas output for the Deep Dive section on title pages.
//

import Foundation

enum DeepDiveTab: String, CaseIterable, Identifiable {
    case craft = "Craft"
    case making = "The Making Of"
    case adaptation = "Adaptation"
    case ending = "Ending Explained"

    var id: String { rawValue }

    /// Tabs that reveal plot details are locked until the title is watched.
    var isSpoiler: Bool { self == .adaptation || self == .ending }

    var systemImage: String {
        switch self {
        case .craft: return "camera.aperture"
        case .making: return "film.stack"
        case .adaptation: return "book.closed"
        case .ending: return "sparkles"
        }
    }
}

enum EndingDepth: String, CaseIterable, Identifiable {
    case quick = "Quick"
    case full = "Full"
    case themes = "Themes"
    var id: String { rawValue }
}

struct CraftNote: Codable, Hashable {
    let area: String
    let person: String?
    let note: String
}

struct MakingOfEvent: Codable, Hashable {
    let phase: String
    let when: String?
    let detail: String
}

struct AdaptationChange: Codable, Hashable {
    let change: String
    let why: String?
}

/// Spoiler-free half: generated once per title, safe to show before watching.
struct DeepDiveSafeContent: Codable, Equatable {
    let craft: [CraftNote]
    let making: [MakingOfEvent]
}

/// Spoiler half: only requested after the user unlocks it.
struct DeepDiveSpoilerContent: Codable, Equatable {
    let source: String?
    let adaptation: [AdaptationChange]
    let endingQuick: String
    let endingFull: String
    let endingThemes: String
}

/// Facts from TMDB passed to Atlas so it explains real data rather than inventing it.
struct DeepDiveContext {
    let tmdbId: Int
    let mediaType: MediaType
    let title: String
    let year: String?
    let crew: [CrewMember]
    let budget: String?
    let revenue: String?
    let keywords: [String]

    /// TMDB tags adaptations with keywords like "based on novel or book".
    var adaptationKeyword: String? {
        keywords.first { $0.lowercased().hasPrefix("based on") }
    }

    var keyCrewSummary: String {
        let jobs = ["Director", "Screenplay", "Writer", "Director of Photography",
                    "Original Music Composer", "Editor", "Production Design", "Costume Design", "Novel"]
        let lines = jobs.compactMap { job -> String? in
            let names = crew.filter { $0.job == job }.map(\.name)
            guard !names.isEmpty else { return nil }
            return "\(job): \(Array(Set(names)).sorted().joined(separator: ", "))"
        }
        return lines.joined(separator: "\n")
    }
}
