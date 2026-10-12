//
//  SplashScreenView.swift
//  WatchGuide-MovieandTVtracker
//
//  Glowmark launch sequence: a streak of light traces the TV's outline,
//  then dissolves outward into the halo as the icon's layers light up.
//

import SwiftUI
import AVFoundation

/// Plays the Glowmark sting. Uses the ambient category so it respects the
/// silent switch and mixes with (rather than stops) whatever is already playing.
private enum SplashSound {
    static var player: AVAudioPlayer?

    static func play() {
        guard let url = Bundle.main.url(forResource: "splash_glowmark", withExtension: "caf") else { return }
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        #endif
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.8
        player?.play()
    }
}

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var fadeOut: Double = 1.0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isActive {
            ContentView()
                .transition(.opacity)
        } else {
            GlowmarkSplashView(reduceMotion: reduceMotion)
            .opacity(fadeOut)
            .onAppear {
                if !reduceMotion { SplashSound.play() }
                DispatchQueue.main.asyncAfter(deadline: .now() + splashDuration) {
                    finishSplash()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    finishSplash()
                }
            }
            #if !os(tvOS) && !os(macOS)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            #endif
        }
    }

    private var splashDuration: TimeInterval {
        reduceMotion ? 1.2 : GlowmarkSplashView.duration
    }

    private func finishSplash() {
        guard !isActive else { return }
        if scenePhase == .background { SplashSound.player?.stop() }
        withAnimation(.easeInOut(duration: 0.35)) {
            fadeOut = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation {
                isActive = true
            }
        }
    }
}

// MARK: - Glowmark Splash

/// Every layer is driven from one clock so the sequence is deterministic:
/// streak traces the TV outline → the outline ignites and spreads into the
/// halo → frame fills in → screen powers on → beam spills out of the notch → wordmark.
private struct GlowmarkSplashView: View {
    static let duration: TimeInterval = 4.4

    let reduceMotion: Bool
    @State var start = Date()

    var body: some View {
        GeometryReader { geo in
            let side = Self.stageSide(for: geo.size)

            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = reduceMotion ? Self.duration : context.date.timeIntervalSince(start)

                ZStack {
                    background(for: geo.size)

                    VStack(spacing: side * 0.02) {
                        GlowmarkStage(t: t)
                            .frame(width: side, height: side)

                        Text("WATCH GUIDE")
                            .font(.system(size: min(max(15, side * 0.065), 28), weight: .semibold, design: .rounded))
                            .tracking(side * 0.018)
                            .foregroundStyle(.white.opacity(0.92))
                            .opacity(ease(t, 3.0, 3.5))
                            .offset(y: (1 - ease(t, 3.0, 3.5)) * 8)
                    }
                    // Gentle push-in during the outro.
                    .scaleEffect(1 + 0.05 * ease(t, 3.7, 4.7))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .onAppear { start = Date() }
    }

    /// Sized from the window, not the device, so iPad Split View, Slide Over and
    /// Stage Manager windows get phone proportions while full-screen iPad gets a
    /// larger mark that stays the same size in portrait and landscape.
    static func stageSide(for size: CGSize) -> CGFloat {
        let shortSide = min(size.width, size.height)
        let isLargeCanvas = size.width >= 600 && size.height >= 600
        let side = isLargeCanvas ? shortSide * 0.46 : size.width * 0.62
        // Leave room below for the beam and wordmark on short or landscape windows.
        return min(side, size.height * 0.5, 520)
    }

    private func background(for size: CGSize) -> some View {
        RadialGradient(
            colors: [Color(red: 0.13, green: 0.10, blue: 0.32), Glowmark.night],
            center: UnitPoint(x: 0.5, y: 0.45),
            startRadius: 0,
            // Scale the falloff with the window so large iPads don't show a hard ring.
            endRadius: max(size.width, size.height) * 0.6
        )
        .ignoresSafeArea()
    }
}

/// The icon artwork in its 1024-point design space, scaled to fit.
private struct GlowmarkStage: View {
    let t: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 1024

            ZStack(alignment: .topLeading) {
                halo(s)
                outlineGlow(s)
                beam(s)
                frame(s)
                screen(s)
                outlineStreak(s)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    // MARK: Layers

    private func halo(_ s: CGFloat) -> some View {
        // Grows out of the dissolving outline glow.
        let bloom = ease(t, 2.4, 3.1)
        return RadialGradient(
            stops: [
                .init(color: Glowmark.amber.opacity(0.9), location: 0),
                .init(color: Glowmark.coral.opacity(0.28), location: 0.55),
                .init(color: Glowmark.coral.opacity(0), location: 1)
            ],
            center: .center,
            startRadius: 0,
            endRadius: 470 * s
        )
        .frame(width: 1400 * s, height: 1400 * s)
        .position(x: 512 * s, y: 460 * s)
        .scaleEffect(0.8 + 0.2 * bloom)
        .opacity(bloom)
        .allowsHitTesting(false)
    }

    /// Once the streak closes the loop, the whole outline flares, then blurs and
    /// spreads outward until it becomes the halo.
    private func outlineGlow(_ s: CGFloat) -> some View {
        let ignite = ease(t, 2.1, 2.35)
        let spread = ease(t, 2.3, 3.0)
        return GlowmarkShapes.Frame()
            .stroke(Glowmark.amber, style: StrokeStyle(lineWidth: (30 + 110 * spread) * s, lineJoin: .round))
            .frame(width: 1024 * s, height: 1024 * s)
            .blur(radius: (16 + 70 * spread) * s)
            .scaleEffect(1 + 0.12 * spread, anchor: UnitPoint(x: 0.5, y: 0.45))
            .opacity(ignite * (1 - spread))
            .allowsHitTesting(false)
    }

    private func beam(_ s: CGFloat) -> some View {
        let reveal = ease(t, 2.65, 3.25)
        return GlowmarkShapes.Beam()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Glowmark.peach, location: 0),
                        .init(color: Glowmark.apricot.opacity(0.55), location: 0.45),
                        .init(color: Glowmark.apricot.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1024 * s, height: 1024 * s)
            .blur(radius: 22 * s)
            // Spills downward from the notch as the screen turns on.
            .mask(alignment: .top) {
                Rectangle().frame(height: (560 + 520 * reveal) * s)
            }
            .opacity(reveal)
    }

    /// A comet of light that leaves the notch tip, runs once around the TV's
    /// outline drawing it in, and arrives back at the tip — where `outlineGlow` takes over.
    private func outlineStreak(_ s: CGFloat) -> some View {
        let head = ease(t, 0.15, 2.15, cubic: false)
        let tail = max(0, head - 0.22)
        let trailFade = 1 - ease(t, 2.15, 2.45)
        let outline = GlowmarkShapes.Frame.trace(in: CGRect(x: 0, y: 0, width: 1024 * s, height: 1024 * s))
        let comet = outline.trimmedPath(from: tail, to: head)
        let spark = outline.trimmedPath(from: 0, to: max(0.001, head)).currentPoint ?? .zero

        return ZStack(alignment: .topLeading) {
            // Faint line left behind the comet.
            outline.trimmedPath(from: 0, to: head)
                .stroke(Glowmark.peach.opacity(0.55), lineWidth: 3 * s)
            comet.stroke(Glowmark.amber, style: StrokeStyle(lineWidth: 30 * s, lineCap: .round, lineJoin: .round))
                .blur(radius: 16 * s)
            comet.stroke(
                LinearGradient(colors: [Glowmark.peach, .white], startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: 8 * s, lineCap: .round, lineJoin: .round)
            )
            Circle()
                .fill(.white)
                .frame(width: 26 * s, height: 26 * s)
                .shadow(color: Glowmark.peach, radius: 22 * s)
                .shadow(color: Glowmark.amber, radius: 44 * s)
                .position(spark)
                .opacity(head > 0 ? 1 : 0)
        }
        .frame(width: 1024 * s, height: 1024 * s, alignment: .topLeading)
        .opacity(trailFade)
        .allowsHitTesting(false)
    }

    private func frame(_ s: CGFloat) -> some View {
        let appear = ease(t, 2.2, 2.55)
        return GlowmarkShapes.Frame()
            .fill(
                LinearGradient(colors: [.white, Color(red: 0.93, green: 0.90, blue: 0.97)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                // Glass rim highlight.
                GlowmarkShapes.Frame()
                    .stroke(
                        LinearGradient(colors: [.white, .white.opacity(0)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 4 * s
                    )
            }
            .frame(width: 1024 * s, height: 1024 * s)
            .shadow(color: .black.opacity(0.35), radius: 24 * s, y: 14 * s)
            .scaleEffect(0.97 + 0.03 * appear, anchor: UnitPoint(x: 0.5, y: 0.45))
            .opacity(appear)
    }

    /// Powers on like a TV: a bright line that opens vertically, flashes, then settles.
    private func screen(_ s: CGFloat) -> some View {
        let open = ease(t, 2.45, 2.8)
        let widen = ease(t, 2.4, 2.55)
        let flash = ease(t, 2.5, 2.65) * (1 - ease(t, 2.65, 3.15))
        return GlowmarkShapes.Panel()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: Color(red: 1.0, green: 0.90, blue: 0.80), location: 0),
                        .init(color: Color(red: 1.0, green: 0.64, blue: 0.45), location: 0.5),
                        .init(color: Color(red: 1.0, green: 0.35, blue: 0.27), location: 1)
                    ],
                    center: UnitPoint(x: 0.5, y: 420.0 / 1024),
                    startRadius: 0,
                    endRadius: 420 * s
                )
            )
            .overlay {
                GlowmarkShapes.Panel().fill(.white.opacity(0.85 * flash))
            }
            .frame(width: 1024 * s, height: 1024 * s)
            .shadow(color: Glowmark.coral.opacity(0.6 * open), radius: 30 * s)
            .scaleEffect(x: 0.5 + 0.5 * widen, y: max(0.01, open), anchor: UnitPoint(x: 0.5, y: 0.45))
            .opacity(widen)
    }
}

// MARK: - Shapes (1024-point icon geometry)

private enum GlowmarkShapes {
    /// White glass frame with the bookmark notch.
    struct Frame: Shape {
        static let corners: [(CGFloat, CGFloat, CGFloat)] = [
            (132, 220, 88), (892, 220, 88), (892, 700, 88),
            (597, 700, 10), (512, 580, 12), (427, 700, 10),
            (132, 700, 88)
        ]
        static let notchTip = 4

        func path(in rect: CGRect) -> Path {
            roundedPolygon(Self.corners, in: rect)
        }

        /// The same outline as one stroke that starts and ends at the notch tip,
        /// for the streak to trace.
        static func trace(in rect: CGRect) -> Path {
            let s = rect.width / 1024
            let n = corners.count
            let point = { (i: Int) in CGPoint(x: corners[i % n].0 * s, y: corners[i % n].1 * s) }
            var p = Path()
            p.move(to: point(notchTip))
            for step in 1..<n {
                let i = notchTip + step
                p.addArc(tangent1End: point(i), tangent2End: point(i + 1), radius: corners[i % n].2 * s)
            }
            p.addLine(to: point(notchTip))
            return p
        }
    }

    /// Lit screen, inset 28pt so the frame wraps the notch evenly.
    struct Panel: Shape {
        func path(in rect: CGRect) -> Path {
            roundedPolygon([
                (160, 248, 60), (864, 248, 60), (864, 672, 60),
                (611.48, 672, 8), (512, 531.56, 10), (412.52, 672, 8),
                (160, 672, 60)
            ], in: rect)
        }
    }

    /// Light falling from behind the notch.
    struct Beam: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 1024
            var p = Path()
            p.move(to: CGPoint(x: 412 * s, y: 560 * s))
            p.addLine(to: CGPoint(x: 612 * s, y: 560 * s))
            p.addLine(to: CGPoint(x: 940 * s, y: 1060 * s))
            p.addLine(to: CGPoint(x: 84 * s, y: 1060 * s))
            p.closeSubpath()
            return p
        }
    }

    private static func roundedPolygon(_ corners: [(CGFloat, CGFloat, CGFloat)], in rect: CGRect) -> Path {
        let s = rect.width / 1024
        let points = corners.map { CGPoint(x: $0.0 * s, y: $0.1 * s) }
        var p = Path()
        let last = points[points.count - 1]
        p.move(to: CGPoint(x: (last.x + points[0].x) / 2, y: (last.y + points[0].y) / 2))
        for i in points.indices {
            p.addArc(tangent1End: points[i],
                     tangent2End: points[(i + 1) % points.count],
                     radius: corners[i].2 * s)
        }
        p.closeSubpath()
        return p
    }
}

private enum Glowmark {
    static let night = Color(red: 0.043, green: 0.035, blue: 0.125)
    static let amber = Color(red: 1.0, green: 0.62, blue: 0.42)
    static let coral = Color(red: 1.0, green: 0.48, blue: 0.33)
    static let peach = Color(red: 1.0, green: 0.83, blue: 0.65)
    static let apricot = Color(red: 1.0, green: 0.70, blue: 0.49)
}

/// Progress of `t` between `from` and `to`, clamped to 0...1.
/// Ease-out cubic by default; ease-in-out sine when `cubic` is false.
private func ease(_ t: TimeInterval, _ from: TimeInterval, _ to: TimeInterval, cubic: Bool = true) -> CGFloat {
    let p = min(max((t - from) / (to - from), 0), 1)
    return CGFloat(cubic ? 1 - pow(1 - p, 3) : (1 - cos(p * .pi)) / 2)
}

#Preview {
    SplashScreenView()
}
