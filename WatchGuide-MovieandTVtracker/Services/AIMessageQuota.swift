//
//  AIMessageQuota.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

struct AIMessageQuota {
    static let freeMessagesPerDay = 5
    static let freeTripPlansPerMonth = 1
    static let freePostCreditsPerMonth = 4

    private static let dailyMessageDateKey = "scout_daily_message_date"
    private static let dailyMessageCountKey = "scout_daily_message_count"
    private static let monthlyTripDateKey = "scout_monthly_trip_date"
    private static let monthlyTripCountKey = "scout_monthly_trip_count"
    private static let monthlyPostCreditsDateKey = "scout_monthly_post_credits_date"
    private static let monthlyPostCreditsCountKey = "scout_monthly_post_credits_count"

    static func isUnlimited() -> Bool {
        UserDefaults.standard.bool(forKey: ScoutSubscriptionService.entitlementActiveKey)
    }

    static func remainingMessages() -> Int {
        guard !isUnlimited() else { return Int.max }
        let used = currentDailyMessageCount()
        return max(0, freeMessagesPerDay - used)
    }

    static func consumeMessage() {
        guard !isUnlimited() else { return }
        let used = currentDailyMessageCount()
        UserDefaults.standard.set(used + 1, forKey: dailyMessageCountKey)
    }

    static func remainingTripPlansThisMonth() -> Int {
        guard !isUnlimited() else { return Int.max }
        let used = currentMonthlyTripCount()
        return max(0, freeTripPlansPerMonth - used)
    }

    static func canCreateTripPlanThisMonth() -> Bool {
        remainingTripPlansThisMonth() > 0
    }

    static func consumeTripPlan() {
        guard !isUnlimited() else { return }
        let used = currentMonthlyTripCount()
        UserDefaults.standard.set(used + 1, forKey: monthlyTripCountKey)
    }

    static func remainingPostCreditsThisMonth() -> Int {
        guard !isUnlimited() else { return Int.max }
        let used = currentMonthlyPostCreditsCount()
        return max(0, freePostCreditsPerMonth - used)
    }

    static func canUsePostCreditsThisMonth() -> Bool {
        remainingPostCreditsThisMonth() > 0
    }

    static func consumePostCredits() {
        guard !isUnlimited() else { return }
        let used = currentMonthlyPostCreditsCount()
        UserDefaults.standard.set(used + 1, forKey: monthlyPostCreditsCountKey)
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
