import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum PlatformURLHandler {
    static func canOpenURL(_ url: URL) -> Bool {
        #if os(iOS) || os(tvOS)
        return UIApplication.shared.canOpenURL(url)
        #else
        return false
        #endif
    }

    static func openURL(_ url: URL) {
        #if os(iOS) || os(tvOS)
        UIApplication.shared.open(url)
        #endif
    }
}

enum PlatformClipboard {
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #endif
    }
}
