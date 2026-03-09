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

    static func openAppSettings() {
        #if os(iOS) || os(tvOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(privacyURL)
        }
        #endif
    }
}

enum PlatformClipboard {
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
