//
//  AtlasProactiveEngine.swift
//  WatchGuide-MovieandTVtracker
//
//  Makes Atlas speak first. Everything here is derived locally from
//  StorageService — no network call, no model call — so a briefing is instant,
//  works offline, and costs nothing. The result feeds three places:
//
//    1. the HUD orb badge (something worth saying),
//    2. the opening message when the user starts a new Atlas conversation,
//    3. a `promptContext` block so Atlas always knows what the user is mid-way
//       through without having to ask.
//

import Foundation
import Combine
#if canImport(UserNotifications) && !os(tvOS)
import UserNotifications
#endif

@MainActor
final class AtlasProactiveEngine: ObservableObject {
    static let shared = AtlasProactiveEngine()

    /// One thing worth mentioning, ordered by how timely it is.
    struct BriefingItem: Identifiable, Equatable {
        enum Kind: Int, Comparable {
            case releasingNow = 0    // out now / out this week
            case nextEpisode  = 1    // you're mid-show, here's the next one
            case releasingSoon = 2   // dated, coming up
            case stalled      = 3    // untouched for weeks
            case nudge        = 4    // generic queue nudge

            static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
        }

        let id = UUID()
        let kind: Kind
        let text: String
        let sfSymbol: String
        /// Title this item is about, so a tap can open it.
        let relatedTitle: String?
    }

    struct Briefing: Equatable {
        let opener: String
        let items: [BriefingItem]
        let generatedAt: Date

        var isEmpty: Bool { items.isEmpty }
    }

    @Published private(set) var briefing: Briefing?
    /// True when there's a briefing the user hasn't opened yet — drives the
    /// dot on the HUD orb.
    @Published private(set) var hasUnseenBriefing = false

    static let dailyBriefingKey = "atlas_daily_briefing_enabled"
    private static let lastSeenKey = "atlas_briefing_last_seen"
    private static let notificationID = "atlas_daily_briefing"

    /// Don't re-badge more than once every few hours, however often the app is
    /// resumed — a companion that pings constantly stops being one.
    private static let rebadgeInterval: TimeInterval = 6 * 60 * 60

    private init() {}

    // MARK: - Building

    /// Recomputes the briefing from current storage. Cheap; safe to call on
    /// every foreground.
    func refresh() {
        let persona = AtlasPersona.current
        let items = buildItems()

        briefing = Briefing(
            opener: items.isEmpty
                ? persona.emptyBriefingLine
                : persona.briefingOpener(name: AtlasPersona.userName),
            items: items,
            generatedAt: Date()
        )

        let lastSeen = UserDefaults.standard.object(forKey: Self.lastSeenKey) as? Date
        let stale = lastSeen.map { Date().timeIntervalSince($0) > Self.rebadgeInterval } ?? true
        hasUnseenBriefing = !items.isEmpty && stale
    }

    func markBriefingSeen() {
        hasUnseenBriefing = false
        UserDefaults.standard.set(Date(), forKey: Self.lastSeenKey)
    }

    private func buildItems() -> [BriefingItem] {
        let storage = StorageService.shared
        var items: [BriefingItem] = []
        let now = Date()

        // 1. Shows you're in the middle of, with a concrete next episode.
        for entry in storage.continueWatching where entry.status == .inProgress {
            guard let next = entry.nextEpisode else { continue }
            let episodeName = next.title.map { " — \($0)" } ?? ""
            items.append(BriefingItem(
                kind: .nextEpisode,
                text: "\(entry.show.title) \(next.code) is up next\(episodeName)",
                sfSymbol: "play.circle.fill",
                relatedTitle: entry.show.title
            ))
        }

        // 2. Shows you started and left alone for a while.
        for entry in storage.continueWatching where entry.status == .inProgress {
            let idleDays = Calendar.current.dateComponents(
                [.day], from: entry.lastUpdated, to: now
            ).day ?? 0
            guard idleDays >= 21, entry.nextEpisode == nil else { continue }
            items.append(BriefingItem(
                kind: .stalled,
                text: "You haven't been back to \(entry.show.title) in \(idleDays) days",
                sfSymbol: "clock.badge.exclamationmark",
                relatedTitle: entry.show.title
            ))
        }

        // 3. Watchlist titles that just landed or are about to.
        for saved in storage.wantToWatch {
            guard let releaseDate = Self.parseDate(saved.releaseDate) else { continue }
            let days = Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: now),
                to: Calendar.current.startOfDay(for: releaseDate)
            ).day ?? 0

            if days <= 0 && days >= -10 {
                items.append(BriefingItem(
                    kind: .releasingNow,
                    text: days == 0
                        ? "\(saved.title) is out today"
                        : "\(saved.title) came out \(abs(days)) day\(abs(days) == 1 ? "" : "s") ago",
                    sfSymbol: "sparkles",
                    relatedTitle: saved.title
                ))
            } else if days > 0 && days <= 21 {
                items.append(BriefingItem(
                    kind: .releasingSoon,
                    text: "\(saved.title) arrives in \(days) day\(days == 1 ? "" : "s")",
                    sfSymbol: "calendar",
                    relatedTitle: saved.title
                ))
            }
        }

        // 4. Nothing timely — fall back to a nudge, but only if there's
        //    actually something in the queue to nudge about.
        if items.isEmpty, let oldest = storage.wantToWatch.min(by: { $0.addedAt < $1.addedAt }) {
            let waitingDays = Calendar.current.dateComponents(
                [.day], from: oldest.addedAt, to: now
            ).day ?? 0
            if waitingDays >= 14 {
                items.append(BriefingItem(
                    kind: .nudge,
                    text: "\(oldest.title) has been on your watchlist for \(waitingDays) days",
                    sfSymbol: "bookmark",
                    relatedTitle: oldest.title
                ))
            }
        }

        return Array(
            items.sorted { ($0.kind, $0.text) < ($1.kind, $1.text) }.prefix(5)
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    // MARK: - Prompt context

    /// Current-state block injected into Atlas's system prompt so it can open a
    /// conversation already knowing where the user is.
    var promptContext: String {
        let storage = StorageService.shared
        var lines: [String] = []

        let inProgress = storage.continueWatching.filter { $0.status == .inProgress }
        if !inProgress.isEmpty {
            let described = inProgress.prefix(4).map { entry -> String in
                if let next = entry.nextEpisode {
                    return "\(entry.show.title) (next: \(next.code))"
                }
                return entry.show.title
            }
            lines.append("Currently watching: " + described.joined(separator: ", "))
        }

        if !storage.wantToWatch.isEmpty {
            let recent = storage.wantToWatch
                .sorted { $0.addedAt > $1.addedAt }
                .prefix(8)
                .map(\.title)
            lines.append("Watchlist (\(storage.wantToWatch.count) total, most recent): " + recent.joined(separator: ", "))
        }

        if let items = briefing?.items, !items.isEmpty {
            lines.append("Timely right now: " + items.map(\.text).joined(separator: "; "))
        }

        guard !lines.isEmpty else { return "" }

        return """


        THE USER'S CURRENT STATE (live app data — use it to be specific, and don't ask for \
        information that's already here):
        \(lines.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    // MARK: - Opening message

    /// The message Atlas leads with when a conversation starts. Returns nil when
    /// there's nothing worth saying unprompted.
    func openingMessage() -> String? {
        guard let briefing, !briefing.isEmpty else { return nil }
        let body = briefing.items.prefix(3).map { "• \($0.text)" }.joined(separator: "\n")
        return "\(briefing.opener)\n\n\(body)"
    }

    // MARK: - Daily briefing notification

    #if canImport(UserNotifications) && !os(tvOS)
    /// Schedules (or cancels) a 9am local reminder carrying the top briefing
    /// line. Off by default; the toggle lives in Settings.
    func syncDailyBriefingNotification() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])

        guard UserDefaults.standard.bool(forKey: Self.dailyBriefingKey) else { return }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        refresh()
        guard let top = briefing?.items.first else { return }

        let content = UNMutableNotificationContent()
        content.title = "Atlas"
        content.body = top.text
        content.sound = .default

        var components = DateComponents()
        components.hour = 9
        components.minute = 0

        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await center.add(request)
    }
    #endif
}
