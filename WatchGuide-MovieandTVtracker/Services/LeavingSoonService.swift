//
//  LeavingSoonService.swift
//  WatchGuide-MovieandTVtracker
//
//  Scans the Want to Watch list for titles about to leave the user's
//  streaming services (via MOTN `expiresOn`) and schedules reminders.
//

import Foundation
#if !os(tvOS)
import UserNotifications
#endif

struct LeavingSoonEntry: Identifiable, Hashable {
    let item: SavedMediaItem
    let providerId: Int
    let providerName: String
    let leavesOn: Date

    var id: String { "\(item.id)_\(providerId)" }

    var daysLeft: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.startOfDay(for: leavesOn)
        return max(0, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    var countdownText: String {
        switch daysLeft {
        case 0: return "Leaves today"
        case 1: return "Leaves tomorrow"
        default: return "Leaves in \(daysLeft) days"
        }
    }
}

@MainActor
final class LeavingSoonService: ObservableObject {
    static let shared = LeavingSoonService()

    static let categoryID = "LEAVING_SOON_REMINDER"

    @Published private(set) var entries: [LeavingSoonEntry] = []
    @Published private(set) var isScanning = false

    /// Only surface titles leaving within this window.
    private let lookahead: TimeInterval = 30 * 86400
    /// Remind this many days before the title leaves.
    private let reminderLeadDays = 3
    /// Keeps MOTN usage bounded for very long watchlists.
    private let maxItemsPerScan = 80
    private let scanInterval: TimeInterval = 12 * 3600

    private static let lastScanKey = "leaving_soon_last_scan"
    private static let notifiedKey = "leaving_soon_notified_ids"

    /// Entries live in memory, so the first call after launch always rescans.
    private var hasScannedThisLaunch = false

    private init() {}

    /// Providers to check: the user's StreamQ services, or every mapped
    /// service when they haven't picked any yet.
    private var providerIds: [Int] {
        let selected = StorageService.shared.settings.streamqServiceIds
        if !selected.isEmpty { return selected }
        return StreamingService.allServices.map(\.id)
    }

    func scanIfNeeded() async {
        let last = UserDefaults.standard.double(forKey: Self.lastScanKey)
        guard last == 0 || Date().timeIntervalSince1970 - last >= scanInterval || !hasScannedThisLaunch else { return }
        await scan()
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        hasScannedThisLaunch = true
        defer { isScanning = false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastScanKey)

        let region = StorageService.shared.settings.region
        let providers = providerIds
        let items = StorageService.shared.wantToWatch
            .filter { $0.mediaType != .person }
            .prefix(maxItemsPerScan)
        let now = Date()
        let horizon = now.addingTimeInterval(lookahead)

        var found: [LeavingSoonEntry] = []
        for saved in items {
            let links = await StreamingDeepLinkService.shared.fetchDeepLinks(
                tmdbId: saved.mediaId,
                mediaType: saved.mediaType,
                country: region
            )
            // One entry per title: the earliest departure among the user's services.
            let soonest = providers
                .compactMap { id -> (Int, Date)? in
                    guard let date = StreamingDeepLinkService.leavingDate(forTMDBProviderId: id, from: links),
                          date > now, date <= horizon else { return nil }
                    return (id, date)
                }
                .min { $0.1 < $1.1 }
            if let (providerId, date) = soonest {
                found.append(LeavingSoonEntry(
                    item: saved,
                    providerId: providerId,
                    providerName: Self.providerName(for: providerId),
                    leavesOn: date
                ))
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        entries = found.sorted { $0.leavesOn < $1.leavesOn }
        #if !os(tvOS)
        await scheduleReminders(for: entries)
        #endif
    }

    /// The latest scan result for a title, if it is leaving one of the user's services.
    func entry(mediaId: Int, mediaType: MediaType) -> LeavingSoonEntry? {
        entries.first { $0.item.mediaId == mediaId && $0.item.mediaType == mediaType }
    }

    static func providerName(for providerId: Int) -> String {
        StreamingService.allServices.first { $0.id == providerId }?.name ?? "your service"
    }

    // MARK: - Notifications

    #if !os(tvOS)
    private func scheduleReminders(for entries: [LeavingSoonEntry]) async {
        var notified = Set(UserDefaults.standard.stringArray(forKey: Self.notifiedKey) ?? [])
        let pending = entries.filter { !notified.contains(Self.notificationId(for: $0)) }
        guard !pending.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }

        let calendar = Calendar.current
        for entry in pending {
            let id = Self.notificationId(for: entry)
            let content = UNMutableNotificationContent()
            content.title = "Leaving \(entry.providerName) soon"
            content.body = "\(entry.item.title) leaves \(entry.providerName) on \(entry.leavesOn.formatted(.dateTime.month(.wide).day())). Watch it before it's gone."
            content.sound = .default
            content.categoryIdentifier = Self.categoryID
            content.userInfo = ["deepLink": "watchguide://media/\(entry.item.mediaType.rawValue)/\(entry.item.mediaId)"]

            // 7pm, `reminderLeadDays` before it leaves — or in an hour if that's already past.
            var fireDate = calendar.date(byAdding: .day, value: -reminderLeadDays, to: entry.leavesOn) ?? entry.leavesOn
            fireDate = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: fireDate) ?? fireDate
            let trigger: UNNotificationTrigger
            if fireDate > Date() {
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            } else {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
            }

            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            notified.insert(id)
        }
        UserDefaults.standard.set(Array(notified), forKey: Self.notifiedKey)
    }

    private static func notificationId(for entry: LeavingSoonEntry) -> String {
        "leaving_\(entry.id)_\(Int(entry.leavesOn.timeIntervalSince1970))"
    }
    #endif
}
