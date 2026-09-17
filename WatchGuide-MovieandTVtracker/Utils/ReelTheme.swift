//
//  ReelTheme.swift
//  WatchGuide-MovieandTVtracker
//
//  Shared styling for the Tonight and Ticket Stub experiences. It stays close
//  to the platform: SF type that scales with Dynamic Type, semantic colours
//  for light and dark, Liquid Glass for controls, and one warm accent.
//  What makes it WatchGuide's own is the poster-lit ambience and the ticket
//  shape, not a custom UI kit.
//

import SwiftUI

enum Reel {
    /// A warm "house lights" amber. Used sparingly for the primary action.
    static let accent = Color(red: 1.0, green: 0.62, blue: 0.2)
    /// Used for "pass" and destructive swipes.
    static let pass = Color.red
    /// Used for "save for later".
    static let save = Color.blue
}

// MARK: - Poster-lit ambience

/// A soft, blurred copy of the current poster behind the page, the way Music
/// lights Now Playing with album art. It adapts to light and dark mode.
struct PosterAmbience: View {
    let url: URL?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(uiColorCompatible: .systemBackground)
            AsyncImageView(url: url, cornerRadius: 0)
                .scaledToFill()
                .blur(radius: 80)
                .saturation(1.4)
                .opacity(colorScheme == .dark ? 0.55 : 0.35)
                .animation(.easeInOut(duration: 0.6), value: url)
            LinearGradient(
                colors: [.clear, Color(uiColorCompatible: .systemBackground).opacity(0.85)],
                startPoint: .center, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension Color {
    #if os(iOS) || os(tvOS)
    init(uiColorCompatible color: UIColor) { self.init(uiColor: color) }
    #elseif os(macOS)
    init(uiColorCompatible color: NSColor) { self.init(nsColor: color) }
    #endif
}

#if os(macOS)
extension NSColor {
    static var systemBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }
}
#endif

// MARK: - Ticket shape

/// A pass with semicircular notches cut from both sides at `notchPosition`
/// (0…1 down the height), in the style of an event ticket in Wallet.
struct TicketShape: Shape {
    var cornerRadius: CGFloat = 16
    var notchRadius: CGFloat = 10
    var notchPosition: CGFloat = 0.62

    func path(in rect: CGRect) -> Path {
        let y = rect.minY + rect.height * notchPosition
        let d = notchRadius * 2
        return Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
            .subtracting(Path(ellipseIn: CGRect(x: rect.minX - notchRadius, y: y - notchRadius, width: d, height: d)))
            .subtracting(Path(ellipseIn: CGRect(x: rect.maxX - notchRadius, y: y - notchRadius, width: d, height: d)))
    }
}

/// Dashed tear line between a ticket's notches.
struct Perforation: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.5))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}
