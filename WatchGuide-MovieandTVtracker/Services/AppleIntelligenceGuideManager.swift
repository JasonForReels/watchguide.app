import Foundation
#if os(iOS)
import UIKit
#endif

#if canImport(ImagePlayground)
import ImagePlayground
#endif

struct AppleIntelligenceCapabilityReport {
    let platformName: String
    let isAppleIntelligenceAvailableNow: Bool
    let availabilitySummary: String
    let supportsNaturalLanguageSearch: Bool
    let supportsImagePlayground: Bool
    let supportsOnscreenAwareness: Bool
    let supportsVisualIntelligence: Bool
}

enum AppleIntelligenceCapabilityService {
    static func currentReport() -> AppleIntelligenceCapabilityReport {
        let platformName = currentPlatformName
        let availability = availabilityTuple

        return AppleIntelligenceCapabilityReport(
            platformName: platformName,
            isAppleIntelligenceAvailableNow: availability.isAvailable,
            availabilitySummary: availability.summary,
            supportsNaturalLanguageSearch: availability.isAvailable,
            supportsImagePlayground: imagePlaygroundSupported,
            supportsOnscreenAwareness: onscreenAwarenessSupported,
            supportsVisualIntelligence: visualIntelligenceSupported
        )
    }

    private static var availabilityTuple: (isAvailable: Bool, summary: String) {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            if PlatformCompatibility.isDesignedForiPadOnMac {
                return (true, "Apple Intelligence may be available on this Apple-silicon Mac (iPad app).")
            }
            #if canImport(UIKit)
            if UIDevice.current.userInterfaceIdiom == .pad {
                return (true, "Apple Intelligence may be available on this iPad.")
            } else {
                return (true, "Apple Intelligence may be available on this iPhone.")
            }
            #else
            return (true, "Apple Intelligence may be available on this iOS device.")
            #endif
        }
        return (false, "Requires iOS 18 or later for Apple Intelligence features.")
        #elseif os(macOS)
        if #available(macOS 15.0, *) {
            #if arch(arm64)
            return (true, "Apple Intelligence may be available on this Apple-silicon Mac.")
            #else
            return (false, "Apple Intelligence requires Apple-silicon Mac hardware.")
            #endif
        }
        return (false, "Requires macOS 15 or later for Apple Intelligence features.")
        #else
        return (false, "Apple Intelligence is not supported on this platform.")
        #endif
    }

    private static var imagePlaygroundSupported: Bool {
        #if canImport(ImagePlayground)
        if #available(iOS 18.2, macOS 15.2, *) {
            return true
        }
        #endif
        return false
    }

    private static var onscreenAwarenessSupported: Bool {
        if #available(iOS 18.0, macOS 15.0, *) {
            return true
        }
        return false
    }

    private static var visualIntelligenceSupported: Bool {
        return PlatformCompatibility.supportsVisualIntelligence
    }

    private static var currentPlatformName: String {
        #if os(iOS)
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return "Mac (Apple silicon, iPad app)"
        }
        #if canImport(UIKit)
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return "iPad (including M-series)"
        default:
            return "iPhone"
        }
        #else
        return "iOS Device"
        #endif
        #elseif os(macOS)
        #if arch(arm64)
        return "Mac (Apple silicon)"
        #else
        return "Mac (Intel)"
        #endif
        #else
        return "Apple Device"
        #endif
    }
}

@MainActor
final class AppleIntelligenceGuideManager: ObservableObject {
    static let shared = AppleIntelligenceGuideManager()

    @Published var isGuidePresented = false

    private let seenGuideVersionKey = "watchguide_ai_guide_seen_version"

    private init() {}

    func presentIfNeededAfterUpdate() {
        let currentVersion = appVersion
        let seenVersion = UserDefaults.standard.string(forKey: seenGuideVersionKey)

        guard seenVersion != currentVersion else { return }

        UserDefaults.standard.set(currentVersion, forKey: seenGuideVersionKey)
        isGuidePresented = true
    }

    func presentManually() {
        isGuidePresented = true
    }

    func open(_ destination: AppleIntelligenceGuideDestination) {
        NotificationCenter.default.post(
            name: .appleIntelligenceGuideOpenDestination,
            object: destination
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}

enum AppleIntelligenceGuideDestination {
    case search
    case scout
    case browse
}

extension Notification.Name {
    static let appleIntelligenceGuideOpenDestination = Notification.Name("appleIntelligenceGuideOpenDestination")
}
