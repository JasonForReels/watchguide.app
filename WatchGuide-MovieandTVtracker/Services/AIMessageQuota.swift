//
//  AIMessageQuota.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation

struct AIMessageQuota {
    static func remainingMessages() -> Int {
        return Int.max
    }

    static func consumeMessage() {
    }
}
