//
//  AtlasVoiceQuota.swift
//  WatchGuide-MovieandTVtracker
//
//  Time-based daily quota for Ask Atlas voice sessions.
//
//  A live voice session isn't a discrete "message", so it's metered by
//  seconds-of-conversation per day rather than message count. This mirrors
//  the tier model in `AIMessageQuota` and reads the same entitlement keys.
//

import Foundation

struct AtlasVoiceQuota {

    // MARK: - Tier Limits (seconds per day)

    /// Free users get a short daily taste of voice mode.
    static let freeSecondsPerDay = 180        // 3 minutes
    /// WatchGuide Pro users get a generous daily allowance.
    static let plusSecondsPerDay = 1_200      // 20 minutes
    // Unlimited tier has no daily budget (Int.max).

    /// Per-session caps prevent a forgotten-open mic from draining the whole
    /// daily budget in one sitting. Unlimited has no per-session cap.
    static let freeSessionCapSeconds = 180    // 3 minutes
    static let plusSessionCapSeconds = 600    // 10 minutes

    // MARK: - UserDefaults Keys

    private static let dailyVoiceDateKey = "atlas_voice_daily_date"
    private static let dailyVoiceSecondsKey = "atlas_voice_daily_seconds"

    // MARK: - Daily Budget

    /// Total seconds available per day for the current tier.
    static func dailyLimitSeconds() -> Int {
        switch AIMessageQuota.currentTier() {
        case .free:      return freeSecondsPerDay
        case .plus:      return plusSecondsPerDay
        case .unlimited: return Int.max
        }
    }

    /// Seconds of voice still available today for the current tier.
    static func remainingSecondsToday() -> Int {
        guard AIMessageQuota.currentTier() != .unlimited else { return Int.max }
        let used = currentDailySeconds()
        return max(0, dailyLimitSeconds() - used)
    }

    /// Maximum length of a single session, or `nil` for unlimited.
    static func sessionCapSeconds() -> Int? {
        switch AIMessageQuota.currentTier() {
        case .free:      return freeSessionCapSeconds
        case .plus:      return plusSessionCapSeconds
        case .unlimited: return nil
        }
    }

    /// The budget a new session may run for: the smaller of the per-session cap
    /// and whatever remains of today's daily budget. `nil` means unlimited.
    static func availableSessionSeconds() -> Int? {
        if AIMessageQuota.currentTier() == .unlimited { return nil }
        let remainingToday = remainingSecondsToday()
        if let cap = sessionCapSeconds() {
            return min(cap, remainingToday)
        }
        return remainingToday
    }

    /// Whether the user has any voice time left to start a session.
    static func canStartSession() -> Bool {
        if AIMessageQuota.currentTier() == .unlimited { return true }
        return remainingSecondsToday() > 0
    }

    /// Record consumed voice time once a session ends.
    static func consume(seconds: Int) {
        guard AIMessageQuota.currentTier() != .unlimited, seconds > 0 else { return }
        let used = currentDailySeconds()
        UserDefaults.standard.set(used + seconds, forKey: dailyVoiceSecondsKey)
    }

    // MARK: - Internal

    private static func currentDailySeconds() -> Int {
        let today = currentDayToken()
        let storedDate = UserDefaults.standard.string(forKey: dailyVoiceDateKey)
        if storedDate != today {
            UserDefaults.standard.set(today, forKey: dailyVoiceDateKey)
            UserDefaults.standard.set(0, forKey: dailyVoiceSecondsKey)
            return 0
        }
        return UserDefaults.standard.integer(forKey: dailyVoiceSecondsKey)
    }

    private static func currentDayToken() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
