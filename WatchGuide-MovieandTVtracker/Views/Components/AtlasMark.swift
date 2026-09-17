//
//  AtlasMark.swift
//  WatchGuide-MovieandTVtracker
//
//  The Atlas mark: `circle.hexagongrid.fill`, drawn a circle at a time with the
//  SF Symbols 7 draw effects, so the seven circles arrive and leave one by one
//  rather than the whole glyph fading.
//
//    opening    tapping the orb erases the mark — .drawOff.individually.reversed
//    exiting    leaving Atlas draws it back on, one circle at a time
//    thinking   that same draw-on, run on a loop for as long as Atlas is working
//
//  A note on how these effects actually behave, because it is the opposite of
//  what the names suggest: for both .drawOn and .drawOff, `isActive: true` puts
//  the symbol in its *erased* state and `isActive: false` is what plays the
//  draw. So the booleans below read as "erased", and clearing one is what draws.
//  Neither effect repeats on its own — `.repeat` is ignored, since these are
//  transition effects rather than discrete ones — so the thinking loop toggles
//  its own flag on a timer instead.
//
//  Draw effects are iOS 26; the app's floor is iOS 26, so there's no fallback
//  path to keep in step here.
//

import SwiftUI

struct AtlasMark: View {
    /// Point size for the symbol.
    var size: CGFloat
    var weight: Font.Weight = .semibold
    var tint: Color = .white
    /// Keeps redrawing the mark, a circle at a time, while Atlas is working.
    var isThinking: Bool = false
    /// Erases the mark — a circle at a time, in reverse — while true. Clearing
    /// it draws the mark back on in the forward order.
    var isErased: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The thinking loop's own erase flag, kept separate from `isErased` so the
    /// two never fight over the same effect.
    @State private var loopErased = false

    var body: some View {
        Image(systemName: Self.symbol)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(tint)
            .symbolEffect(.drawOn.individually, isActive: loopErased)
            .symbolEffect(.drawOff.individually.reversed, isActive: isErased)
            .task(id: isThinking) { await runThinkingLoop() }
    }

    /// Erase, redraw, rest, repeat. Cancelling leaves the mark drawn, so Atlas
    /// finishing a thought always lands on the whole hexagon rather than a
    /// half-built one.
    private func runThinkingLoop() async {
        guard isThinking, !reduceMotion else {
            loopErased = false
            return
        }
        while !Task.isCancelled {
            loopErased = true
            try? await Task.sleep(for: .seconds(Self.draw))
            guard !Task.isCancelled else { break }
            loopErased = false
            try? await Task.sleep(for: .seconds(Self.draw + Self.rest))
        }
        loopErased = false
    }

    static let symbol = "circle.hexagongrid.fill"

    /// How long a full seven-circle draw takes at default speed, measured off
    /// the effect itself rather than guessed.
    private static let draw: Double = 0.45
    /// Beat at full strength between passes, so each one reads as its own sweep.
    private static let rest: Double = 0.3
}
