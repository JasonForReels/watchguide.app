//
//  AIMessageQuota.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

struct AIMessageQuota {

    // MARK: - Subscription Tier

    enum SubscriptionTier {
        case free, plus, unlimited
    }

    static func currentTier() -> SubscriptionTier {
        if UserDefaults.standard.bool(forKey: ScoutSubscriptionService.entitlementActiveKey) {
            return .unlimited
        }
        if UserDefaults.standard.bool(forKey: ScoutSubscriptionService.plusEntitlementActiveKey) {
            return .plus
        }
        return .free
    }

    static func isUnlimited() -> Bool { currentTier() == .unlimited }
    static func isPlusOrAbove() -> Bool { currentTier() != .free }

    // MARK: - Tier Limits

    static let freeMessagesPerDay = 5
    static let plusMessagesPerDay = 15

    static let freeTripPlansPerMonth = 1
    static let plusTripPlansPerMonth = 3

    static let freePostCreditsPerMonth = 4
    static let plusPostCreditsPerMonth = 12

    static let freeDeepDivesPerMonth = 3
    static let plusDeepDivesPerMonth = 15

    static let freeCustomLists = 3
    static let plusCustomLists = 10

    // MARK: - UserDefaults Keys

    private static let dailyMessageDateKey = "scout_daily_message_date"
    private static let dailyMessageCountKey = "scout_daily_message_count"
    private static let monthlyTripDateKey = "scout_monthly_trip_date"
    private static let monthlyTripCountKey = "scout_monthly_trip_count"
    private static let monthlyPostCreditsDateKey = "scout_monthly_post_credits_date"
    private static let monthlyPostCreditsCountKey = "scout_monthly_post_credits_count"
    private static let monthlyDeepDiveDateKey = "scout_monthly_deep_dive_date"
    private static let monthlyDeepDiveCountKey = "scout_monthly_deep_dive_count"

    // MARK: - Messages

    static func dailyMessageLimit() -> Int {
        switch currentTier() {
        case .free:      return freeMessagesPerDay
        case .plus:      return plusMessagesPerDay
        case .unlimited: return Int.max
        }
    }

    static func remainingMessages() -> Int {
        guard currentTier() != .unlimited else { return Int.max }
        let used = currentDailyMessageCount()
        return max(0, dailyMessageLimit() - used)
    }

    static func consumeMessage() {
        guard currentTier() != .unlimited else { return }
        let used = currentDailyMessageCount()
        UserDefaults.standard.set(used + 1, forKey: dailyMessageCountKey)
    }

    // MARK: - Trip Plans

    static func monthlyTripLimit() -> Int {
        switch currentTier() {
        case .free:      return freeTripPlansPerMonth
        case .plus:      return plusTripPlansPerMonth
        case .unlimited: return Int.max
        }
    }

    static func remainingTripPlansThisMonth() -> Int {
        guard currentTier() != .unlimited else { return Int.max }
        let used = currentMonthlyTripCount()
        return max(0, monthlyTripLimit() - used)
    }

    static func canCreateTripPlanThisMonth() -> Bool {
        remainingTripPlansThisMonth() > 0
    }

    static func consumeTripPlan() {
        guard currentTier() != .unlimited else { return }
        let used = currentMonthlyTripCount()
        UserDefaults.standard.set(used + 1, forKey: monthlyTripCountKey)
    }

    // MARK: - Post-Credits

    static func monthlyPostCreditsLimit() -> Int {
        switch currentTier() {
        case .free:      return freePostCreditsPerMonth
        case .plus:      return plusPostCreditsPerMonth
        case .unlimited: return Int.max
        }
    }

    static func remainingPostCreditsThisMonth() -> Int {
        guard currentTier() != .unlimited else { return Int.max }
        let used = currentMonthlyPostCreditsCount()
        return max(0, monthlyPostCreditsLimit() - used)
    }

    static func canUsePostCreditsThisMonth() -> Bool {
        remainingPostCreditsThisMonth() > 0
    }

    static func consumePostCredits() {
        guard currentTier() != .unlimited else { return }
        let used = currentMonthlyPostCreditsCount()
        UserDefaults.standard.set(used + 1, forKey: monthlyPostCreditsCountKey)
    }

    // MARK: - Deep Dive

    static func monthlyDeepDiveLimit() -> Int {
        switch currentTier() {
        case .free:      return freeDeepDivesPerMonth
        case .plus:      return plusDeepDivesPerMonth
        case .unlimited: return Int.max
        }
    }

    static func canUseDeepDiveThisMonth() -> Bool {
        guard currentTier() != .unlimited else { return true }
        return currentMonthlyDeepDiveCount() < monthlyDeepDiveLimit()
    }

    static func consumeDeepDive() {
        guard currentTier() != .unlimited else { return }
        UserDefaults.standard.set(currentMonthlyDeepDiveCount() + 1, forKey: monthlyDeepDiveCountKey)
    }

    // MARK: - Custom Lists

    static func maxCustomLists() -> Int {
        switch currentTier() {
        case .free:      return freeCustomLists
        case .plus:      return plusCustomLists
        case .unlimited: return Int.max
        }
    }

    static func canCreateCustomList(currentCount: Int) -> Bool {
        currentCount < maxCustomLists()
    }

    private static func currentDailyMessageCount() -> Int {
        let today = currentDayToken()
        let storedDate = UserDefaults.standard.string(forKey: dailyMessageDateKey)
        if storedDate != today {
            UserDefaults.standard.set(today, forKey: dailyMessageDateKey)
            UserDefaults.standard.set(0, forKey: dailyMessageCountKey)
            return 0
        }
        return UserDefaults.standard.integer(forKey: dailyMessageCountKey)
    }

    private static func currentMonthlyTripCount() -> Int {
        let month = currentMonthToken()
        let storedMonth = UserDefaults.standard.string(forKey: monthlyTripDateKey)
        if storedMonth != month {
            UserDefaults.standard.set(month, forKey: monthlyTripDateKey)
            UserDefaults.standard.set(0, forKey: monthlyTripCountKey)
            return 0
        }
        return UserDefaults.standard.integer(forKey: monthlyTripCountKey)
    }

    private static func currentMonthlyDeepDiveCount() -> Int {
        let month = currentMonthToken()
        if UserDefaults.standard.string(forKey: monthlyDeepDiveDateKey) != month {
            UserDefaults.standard.set(month, forKey: monthlyDeepDiveDateKey)
            UserDefaults.standard.set(0, forKey: monthlyDeepDiveCountKey)
            return 0
        }
        return UserDefaults.standard.integer(forKey: monthlyDeepDiveCountKey)
    }

    private static func currentMonthlyPostCreditsCount() -> Int {
        let month = currentMonthToken()
        let storedMonth = UserDefaults.standard.string(forKey: monthlyPostCreditsDateKey)
        if storedMonth != month {
            UserDefaults.standard.set(month, forKey: monthlyPostCreditsDateKey)
            UserDefaults.standard.set(0, forKey: monthlyPostCreditsCountKey)
            return 0
        }
        return UserDefaults.standard.integer(forKey: monthlyPostCreditsCountKey)
    }

    private static func currentDayToken() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func currentMonthToken() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }
}
