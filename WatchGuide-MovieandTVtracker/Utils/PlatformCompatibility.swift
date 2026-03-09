import Foundation
#if canImport(UIKit)
import UIKit
#endif

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
        #if os(iOS)
        guard !isDesignedForiPadOnMac else { return false }
        guard isIPhone else { return false }
        if #available(iOS 18.0, *) {
            return true
        }
        return false
        #else
        return false
        #endif
    }
}
