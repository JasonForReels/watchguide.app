//
//  ResponsiveSizing.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct ResponsiveSizing {
    static func screenWidth() -> CGFloat {
        #if canImport(UIKit)
        return UIScreen.main.bounds.width
        #else
        return 800
        #endif
    }

    static func posterSize(horizontalSizeClass: UserInterfaceSizeClass?) -> CGSize {
        let width = screenWidth()
        let isRegular = horizontalSizeClass == .regular
        let posterWidth = isRegular ? min(max(width * 0.16, 120), 160) : min(max(width * 0.30, 110), 150)
        return CGSize(width: posterWidth, height: posterWidth * 1.5)
    }

    static func gridPosterWidth(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        let width = screenWidth()
        let isRegular = horizontalSizeClass == .regular
        return isRegular ? min(max(width * 0.16, 120), 165) : min(max(width * 0.30, 120), 150)
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
}
