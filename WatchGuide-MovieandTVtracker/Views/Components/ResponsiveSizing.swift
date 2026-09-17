//
//  ResponsiveSizing.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ResponsiveSizing {
    static func screenWidth() -> CGFloat {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return activeScene.screen.bounds.width
        }

        if let firstScene = scenes.first {
            return firstScene.screen.bounds.width
        }

        return 800
        #else
        return 800
        #endif
    }

    static func posterSize(horizontalSizeClass: UserInterfaceSizeClass?) -> CGSize {
        let width = screenWidth()
        let isRegular = horizontalSizeClass == .regular
        let posterWidth = isRegular ? min(max(width * 0.19, 140), 220) : min(max(width * 0.30, 110), 150)
        return CGSize(width: posterWidth, height: posterWidth * 1.5)
    }

    static func gridPosterWidth(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        #if os(tvOS)
        return 220
        #else
        let width = screenWidth()
        let isRegular = horizontalSizeClass == .regular
        return isRegular ? min(max(width * 0.19, 140), 220) : min(max(width * 0.30, 120), 150)
        #endif
    }

    static func compactPosterSize(horizontalSizeClass: UserInterfaceSizeClass?) -> CGSize {
        let base = posterSize(horizontalSizeClass: horizontalSizeClass)
        return CGSize(width: base.width * 0.42, height: base.height * 0.42)
    }

    static func avatarSize(horizontalSizeClass: UserInterfaceSizeClass?, base: CGFloat = 80) -> CGFloat {
        let isRegular = horizontalSizeClass == .regular
        return isRegular ? min(max(base * 0.9, 64), 96) : base
    }

    static func providerLogoSize(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        let isRegular = horizontalSizeClass == .regular
        return isRegular ? 44 : 48
    }

    static func hubLogoHeight(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        let isRegular = horizontalSizeClass == .regular
        return isRegular ? 36 : 40
    }

    static func videoCardSize(horizontalSizeClass: UserInterfaceSizeClass?) -> CGSize {
        let width = screenWidth()
        let isRegular = horizontalSizeClass == .regular
        let cardWidth = isRegular ? min(max(width * 0.30, 220), 300) : min(max(width * 0.62, 220), 300)
        return CGSize(width: cardWidth, height: cardWidth * 0.5625)
    }

    static func hubHeroHeight(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        let width = screenWidth()
        let isRegular = horizontalSizeClass == .regular
        let aspect: CGFloat = isRegular ? 2.2 : (16.0 / 10.0)
        return width / aspect
    }

    static func studioHubButtonWidth(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat {
        #if canImport(UIKit)
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return 116
        case .phone:
            if horizontalSizeClass == .regular {
                return 108
            }
            if verticalSizeClass == .compact {
                return 102
            }
            return 96
        default:
            return 102
        }
        #else
        return horizontalSizeClass == .regular ? 112 : 96
        #endif
    }

    static func studioHubButtonHeight(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat {
        #if canImport(UIKit)
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return 72
        case .phone:
            return verticalSizeClass == .compact ? 62 : 58
        default:
            return 62
        }
        #else
        return horizontalSizeClass == .regular ? 68 : 58
        #endif
    }

    static func studioHubLogoWidth(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat {
        studioHubButtonWidth(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        ) * 0.72
    }

    static func studioHubLogoHeight(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat {
        studioHubButtonHeight(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        ) * 0.72
    }

    static func studioHubHeaderLogoHeight(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        horizontalSizeClass == .regular ? 86 : 72
    }

    /// Diameter of the circular studio / streaming hub buttons on the browse screen.
    ///
    /// Driven by the width of the row's own container rather than by the device, so
    /// the buttons grow with the window — landscape, iPad, Split View and Slide Over
    /// all get a size that matches the space they actually have.
    static func hubCircleButtonSize(containerWidth: CGFloat) -> CGFloat {
        #if os(tvOS)
        return 140
        #else
        guard containerWidth > 0 else { return 62 }
        return min(max(containerWidth * 0.155, 56), 104)
        #endif
    }

    /// Gap between hub buttons, kept proportional to their diameter.
    static func hubCircleButtonSpacing(containerWidth: CGFloat) -> CGFloat {
        #if os(tvOS)
        return 32
        #else
        return min(max(hubCircleButtonSize(containerWidth: containerWidth) * 0.26, 14), 28)
        #endif
    }
}
