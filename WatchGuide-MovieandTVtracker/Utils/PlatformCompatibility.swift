import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - YouTube Availability

/// Tracks whether YouTube embeds are usable in the current session.
///
/// When the first embedded YouTube player detects a bot/sign-in wall (common when a VPN is
/// active), it calls `markBlocked()`. All subsequent `EmbeddedTrailerPlayer` instances check
/// `shouldSkipYouTube` and immediately jump to direct-media fallbacks (e.g. Trailio) without
/// ever loading the YouTube embed.
///
/// The flag is session-scoped (resets on app relaunch) so that if the user disconnects their
/// VPN mid-session the next launch will try YouTube again.
final class YouTubeAvailability: ObservableObject, @unchecked Sendable {
    static let shared = YouTubeAvailability()

    /// When `true`, YouTube embeds should not be attempted.
    @Published private(set) var shouldSkipYouTube: Bool = false

    private init() {}

    /// Called by any trailer player that encounters YouTube bot-detection / sign-in walls.
    /// Once set, all players in the session will skip YouTube and use direct sources.
    func markBlocked() {
        DispatchQueue.main.async {
            guard !self.shouldSkipYouTube else { return }
            self.shouldSkipYouTube = true
        }
    }
}

enum PlatformCompatibility {
    static var isDesignedForiPadOnMac: Bool {
        #if os(iOS)
        return ProcessInfo.processInfo.isiOSAppOnMac
        #else
        return false
        #endif
    }

    static var isIPhone: Bool {
        #if os(iOS) && canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    static var supportsVisualIntelligence: Bool {
        return false
    }

    static var supportsInAppVisualScanner: Bool {
        #if os(iOS) && canImport(UIKit) && !targetEnvironment(macCatalyst)
        return !isDesignedForiPadOnMac
        #else
        return false
        #endif
    }

    static var supportsInAppSafari: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    static var supportsLiveActivities: Bool {
        #if canImport(ActivityKit) && os(iOS)
        return true
        #else
        return false
        #endif
    }

    static var supportsAppleWallet: Bool {
        #if canImport(PassKit) && os(iOS)
        return true
        #else
        return false
        #endif
    }
}

