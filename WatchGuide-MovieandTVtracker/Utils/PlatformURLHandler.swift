import Foundation

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum PlatformURLHandler {
    static func canOpenURL(_ url: URL) -> Bool {
        #if os(iOS) || os(tvOS)
        return UIApplication.shared.canOpenURL(url)
        #elseif os(macOS)
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
        #else
        return false
        #endif
    }

    static func openURL(_ url: URL) {
        #if os(iOS) || os(tvOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
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
