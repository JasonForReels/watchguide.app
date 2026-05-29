//
//  VoiceModeCoordinator.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

@MainActor
final class VoiceModeCoordinator: ObservableObject {
    static let shared = VoiceModeCoordinator()

    @Published var isPresented = false

    private init() {}

    func present() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}

enum VoiceModeTab: String {
    case browse
    case search
    case scout
    case lists
    case me
}

enum VoiceDetailSection: String, CaseIterable {
    case top
    case overview
    case watchProviders
    case videos
    case cast
    case crew
    case companies
    case similar
    case recommended
    case details
    case bottom

    static let scrollOrder: [VoiceDetailSection] = [
        .top,
        .overview,
        .watchProviders,
        .videos,
        .cast,
        .crew,
        .companies,
        .similar,
        .recommended,
        .details,
        .bottom
    ]
}

enum VoiceDetailScrollDirection {
    case up
    case down
}

enum VoiceDetailCommand {
    case dismiss
    case jump(VoiceDetailSection)
    case relative(VoiceDetailScrollDirection)
}

struct VoiceCommandResult {
    let assistantText: String
}

extension Notification.Name {
    static let voiceModeSwitchTab = Notification.Name("voiceModeSwitchTab")
    static let voiceModeDetailCommand = Notification.Name("voiceModeDetailCommand")
}

@MainActor
final class VoiceCommandRouter {
    static let shared = VoiceCommandRouter()

    private init() {}

    func handle(_ transcript: String) -> VoiceCommandResult? {
        let normalized = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return nil }

        if let tab = matchedTab(in: normalized) {
            NotificationCenter.default.post(name: .voiceModeSwitchTab, object: tab)
            return VoiceCommandResult(assistantText: "Opening \(spokenLabel(for: tab)).")
        }

        if normalized.contains("close details") || normalized.contains("dismiss details") || normalized.contains("close this page") {
            NotificationCenter.default.post(name: .voiceModeDetailCommand, object: VoiceDetailCommand.dismiss)
            return VoiceCommandResult(assistantText: "Closing the details page.")
        }

        if normalized.contains("scroll down") {
            NotificationCenter.default.post(name: .voiceModeDetailCommand, object: VoiceDetailCommand.relative(.down))
            return VoiceCommandResult(assistantText: "Scrolling down.")
        }

        if normalized.contains("scroll up") {
            NotificationCenter.default.post(name: .voiceModeDetailCommand, object: VoiceDetailCommand.relative(.up))
            return VoiceCommandResult(assistantText: "Scrolling up.")
        }

        if normalized.contains("top") {
            NotificationCenter.default.post(name: .voiceModeDetailCommand, object: VoiceDetailCommand.jump(.top))
            return VoiceCommandResult(assistantText: "Going to the top.")
        }

        if normalized.contains("bottom") {
            NotificationCenter.default.post(name: .voiceModeDetailCommand, object: VoiceDetailCommand.jump(.bottom))
            return VoiceCommandResult(assistantText: "Going to the bottom.")
        }

        if normalized.contains("overview") {
            return jumpToDetailSection(.overview, response: "Jumping to the overview.")
        }

        if normalized.contains("where to watch") || normalized.contains("watch providers") || normalized.contains("streaming") {
            return jumpToDetailSection(.watchProviders, response: "Jumping to where to watch.")
        }

        if normalized.contains("videos") || normalized.contains("trailers") || normalized.contains("clips") {
            return jumpToDetailSection(.videos, response: "Jumping to videos.")
        }

        if normalized.contains("cast") {
            return jumpToDetailSection(.cast, response: "Jumping to cast.")
        }

        if normalized.contains("crew") {
            return jumpToDetailSection(.crew, response: "Jumping to crew.")
        }

        if normalized.contains("companies") || normalized.contains("studios") || normalized.contains("production companies") {
            return jumpToDetailSection(.companies, response: "Jumping to production companies.")
        }

        if normalized.contains("similar") {
            return jumpToDetailSection(.similar, response: "Jumping to similar titles.")
        }

        if normalized.contains("recommended") || normalized.contains("recommendations") {
            return jumpToDetailSection(.recommended, response: "Jumping to recommendations.")
        }

        if normalized.contains("details") {
            return jumpToDetailSection(.details, response: "Jumping to details.")
        }

        return nil
    }

    private func jumpToDetailSection(_ section: VoiceDetailSection, response: String) -> VoiceCommandResult {
        NotificationCenter.default.post(name: .voiceModeDetailCommand, object: VoiceDetailCommand.jump(section))
        return VoiceCommandResult(assistantText: response)
    }

    private func matchedTab(in transcript: String) -> VoiceModeTab? {
        if transcript.contains("browse") || transcript.contains("home") {
            return .browse
        }
        if transcript.contains("search") {
            return .search
        }
        if transcript.contains("scout") || transcript.contains("assistant") || transcript.contains("ai tab") {
            return .scout
        }
        if transcript.contains("lists") || transcript.contains("watchlist") {
            return .lists
        }
        if transcript.contains("profile") || transcript.contains("me tab") {
            return .me
        }
        return nil
    }

    private func spokenLabel(for tab: VoiceModeTab) -> String {
        switch tab {
        case .browse:
            return "Browse"
        case .search:
            return "Search"
        case .scout:
            return "Scout"
        case .lists:
            return "Lists"
        case .me:
            return "your profile"
        }
    }
}
