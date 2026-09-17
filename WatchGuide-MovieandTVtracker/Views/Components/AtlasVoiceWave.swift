//
//  AtlasVoiceWave.swift
//  WatchGuide-MovieandTVtracker
//
//  The face of Atlas Voice: a live, centre-mirrored bar waveform in the shape
//  of the iOS call meter, poured into Liquid Glass.
//
//  One view serves both sizes so voice reads as the same object wherever it
//  appears — full height in the immersive call surface, and shrunk into the
//  composer's text slot when the call is running inline in the Atlas dock.
//

import SwiftUI

// MARK: - Mode

/// What the wave is doing. Drives colour, motion and how much of the live
/// level actually reaches the bars.
enum AtlasWaveMode: Equatable {
    case connecting
    case listening
    case speaking
    case muted
    case idle
}

// MARK: - Wave

struct AtlasVoiceWave: View {
    /// How large the wave is drawn. `hero` is the immersive call surface;
    /// `inline` is the composer-height version that sits in the input bar.
    enum Size {
        case hero
        case inline

        var barCount: Int { self == .hero ? 41 : 23 }
        var barWidth: CGFloat { self == .hero ? 6 : 3 }
        var barSpacing: CGFloat { self == .hero ? 6 : 3.5 }
        var height: CGFloat { self == .hero ? 132 : 34 }
        var glowRadius: CGFloat { self == .hero ? 18 : 6 }
        var horizontalPadding: CGFloat { self == .hero ? 26 : 12 }
    }

    let mode: AtlasWaveMode
    /// Live mic amplitude, 0...1. Ignored while Atlas is speaking (there is no
    /// realtime meter on the far side — playback is queued ahead of the clock).
    var level: Float = 0
    var size: Size = .hero

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: mode == .idle)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                // Glow first, so the bars sit on their own light.
                waveCanvas(time: time)
                    .blur(radius: size.glowRadius)
                    .opacity(mode == .muted ? 0.25 : 0.75)
                waveCanvas(time: time)
            }
        }
        .frame(height: size.height)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size == .hero ? 22 : 5)
        .modifier(WaveGlassBackground(tint: glassTint, isHero: size == .hero))
        .animation(.easeInOut(duration: 0.35), value: mode)
    }

    // MARK: Drawing

    private func waveCanvas(time: TimeInterval) -> some View {
        Canvas(rendersAsynchronously: false) { context, canvasSize in
            let count = size.barCount
            guard count > 1 else { return }

            let totalWidth = CGFloat(count) * size.barWidth + CGFloat(count - 1) * size.barSpacing
            let startX = (canvasSize.width - totalWidth) / 2
            let midY = canvasSize.height / 2
            let maxHalf = canvasSize.height / 2

            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: barColors),
                startPoint: CGPoint(x: 0, y: midY),
                endPoint: CGPoint(x: canvasSize.width, y: midY)
            )

            for index in 0..<count {
                let position = Double(index) / Double(count - 1)   // 0...1 across the wave
                let half = maxHalf * halfHeightFraction(at: position, time: time)
                let x = startX + CGFloat(index) * (size.barWidth + size.barSpacing)
                let rect = CGRect(
                    x: x,
                    y: midY - half,
                    width: size.barWidth,
                    height: half * 2
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: size.barWidth / 2, style: .continuous),
                    with: shading
                )
            }
        }
    }

    /// Height of one bar as a fraction of the half-height available to it.
    ///
    /// Three sines at unrelated speeds keep the crest travelling instead of
    /// pulsing in lockstep, and the sine envelope tapers the ends so the wave
    /// reads as one ribbon rather than a row of sticks.
    private func halfHeightFraction(at position: Double, time: TimeInterval) -> CGFloat {
        let envelope = pow(sin(.pi * position), 0.75)

        let travelling =
            sin(time * 2.7 + position * 8.4)
            + sin(time * 4.3 - position * 12.9) * 0.62
            + sin(time * 6.9 + position * 4.1) * 0.34
        let unit = 0.5 + 0.5 * (travelling / 1.96)   // 0...1

        let floorFraction: Double
        let reach: Double

        switch mode {
        case .listening:
            // The bars actually track the microphone here.
            floorFraction = 0.07
            reach = 0.16 + Double(min(1, max(0, level))) * 0.84
        case .speaking:
            floorFraction = 0.14
            reach = 0.86
        case .connecting:
            floorFraction = 0.05
            reach = 0.22
        case .muted, .idle:
            floorFraction = 0.05
            reach = 0.0
        }

        let fraction = envelope * (floorFraction + (1 - floorFraction) * unit * reach)
        // Never fully collapse: a hairline keeps the wave present when silent.
        return CGFloat(max(0.035, min(1.0, fraction)))
    }

    // MARK: Palette

    private var barColors: [Color] {
        switch mode {
        case .speaking:
            return [
                Color(red: 0.44, green: 0.32, blue: 0.98),
                Color(red: 0.30, green: 0.52, blue: 1.00),
                Color(red: 0.36, green: 0.80, blue: 0.99)
            ]
        case .listening:
            return [
                Color(red: 0.30, green: 0.52, blue: 1.00),
                Color(red: 0.42, green: 0.74, blue: 1.00),
                Color(red: 0.36, green: 0.90, blue: 0.96)
            ]
        case .connecting:
            return [Color.white.opacity(0.45), Color.white.opacity(0.70), Color.white.opacity(0.45)]
        case .muted:
            return [Color.orange.opacity(0.65), Color.orange.opacity(0.85), Color.orange.opacity(0.65)]
        case .idle:
            return [Color.white.opacity(0.28), Color.white.opacity(0.40), Color.white.opacity(0.28)]
        }
    }

    private var glassTint: Color {
        switch mode {
        case .speaking:  return Color(red: 0.38, green: 0.34, blue: 0.98)
        case .listening: return Color(red: 0.28, green: 0.56, blue: 1.00)
        case .muted:     return Color.orange
        default:         return Color.white
        }
    }
}

// MARK: - Glass

/// The wave lives on a clear lens — it is light, not text, so `.clear` keeps
/// the app behind it visible instead of frosting it out.
private struct WaveGlassBackground: ViewModifier {
    let tint: Color
    let isHero: Bool

    private var corner: CGFloat { isHero ? 34 : 17 }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            content
                .glassEffect(
                    .clear.tint(tint.opacity(isHero ? 0.20 : 0.14)).interactive(),
                    in: .rect(cornerRadius: corner, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [tint.opacity(0.22), tint.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
                )
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }
}

// MARK: - Call controls

/// Mute and hang-up, on the same glass as the wave. Shared by the immersive
/// call surface and the dock bar so the pair reads as one control set no
/// matter which size it is drawn at.
struct AtlasVoiceCallButton: View {
    let symbol: String
    /// Colour of the glyph.
    var tint: Color = .white
    /// Colour poured into the glass behind it. `nil` leaves it untinted.
    var glassTint: Color?
    var diameter: CGFloat = 64
    var accessibilityText: String
    let action: () -> Void

    private var glyphSize: CGFloat { diameter * 0.38 }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: diameter, height: diameter)
                .contentTransition(.symbolEffect(.replace))
                .modifier(CallButtonGlass(tint: glassTint))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }
}

private struct CallButtonGlass: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            if let tint {
                content.glassEffect(.regular.tint(tint).interactive(), in: .circle)
            } else {
                content.glassEffect(.regular.interactive(), in: .circle)
            }
        } else {
            content
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(tint?.opacity(0.85) ?? Color.white.opacity(0.12)))
                )
                .clipShape(Circle())
        }
    }
}

// MARK: - Live wave

#if os(iOS)
/// Binds the wave to a running session.
///
/// The session's `micLevel` updates ~20×/second. Reading it here rather than
/// in the bar that hosts the wave keeps those updates from re-rendering the
/// bar itself — which owns sheets, and sheets do not survive a parent that
/// rebuilds on every audio buffer.
struct AtlasVoiceLiveWave: View {
    let session: AtlasVoiceSession
    var size: AtlasVoiceWave.Size = .hero

    var body: some View {
        AtlasVoiceWave(mode: session.waveMode, level: session.micLevel, size: size)
    }
}
#endif
