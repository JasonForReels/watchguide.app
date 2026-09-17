//
//  AtlasHUDOrb.swift
//  WatchGuide-MovieandTVtracker
//
//  The always-there presence: a small draggable orb layered over the app that
//  opens Atlas from any screen. Tap for chat, long-press for voice. It carries
//  a dot when the proactive engine has something timely to say, and it snaps to
//  whichever side of the screen it was dropped nearest.
//
//  Visually it's clear Liquid Glass tinted by the active persona: a lens you
//  read *through*, so a poster or a row of artwork behind it stays legible.
//  The long-press-for-voice affordance is drawn as a filling ring so it's
//  discoverable instead of hidden.
//
//  It rests centred above the tab bar by default, and docks to whichever of
//  three positions it's dropped nearest — bottom centre, or either side edge
//  — so it can be pushed out of the way of anything it covers.
//
//  Off-limits on tvOS (no direct manipulation) and hidden entirely when the
//  user turns it off in Settings.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if !os(tvOS)

// MARK: - Orb

struct AtlasHUDOrb: View {
    let onTap: () -> Void
    let onLongPress: () -> Void

    @AppStorage(AtlasPersona.storageKey) private var personaRaw = AtlasPersona.default.rawValue
    @AppStorage("atlas_hud_x") private var storedX: Double = -1
    @AppStorage("atlas_hud_y") private var storedY: Double = -1

    @ObservedObject private var proactive = AtlasProactiveEngine.shared
    @ObservedObject private var viewModel = AIAssistantViewModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var dragOffset: CGSize = .zero
    @State private var isPressed = false
    @State private var isDragging = false
    /// 0…1 fill of the ring that previews the long-press-for-voice gesture.
    @State private var holdProgress: CGFloat = 0
    /// 0…1 sweep of the attention ring, only animated when a briefing is unseen.
    @State private var pingPhase: CGFloat = 0
    /// The mark starts erased and draws itself on as the orb appears — so
    /// leaving Atlas brings the seven circles back one at a time. The tap that
    /// opens Atlas sets it again, erasing them in the opposite order.
    @State private var isMarkErased = true

    private var persona: AtlasPersona {
        AtlasPersona(rawValue: personaRaw) ?? .default
    }

    private let diameter: CGFloat = 54
    private let edgeInset: CGFloat = 16
    private let holdDuration: Double = 0.45
    /// Gap between the orb and the bottom of the screen, enough to sit above
    /// the tab bar and the home indicator without touching either.
    private let tabBarClearance: CGFloat = 96
    /// How much closer bottom centre feels than it measures, in points.
    private let homeDockPull: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let resting = restingPosition(in: geometry.size)

            orb
                .position(x: resting.x + dragOffset.width,
                          y: resting.y + dragOffset.height)
                .gesture(dragGesture(in: geometry.size, from: resting))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: storedX)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: storedY)
        }
        .ignoresSafeArea(.keyboard)
        .task(id: proactive.hasUnseenBriefing) {
            pingPhase = 0
            guard proactive.hasUnseenBriefing, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.9).repeatForever(autoreverses: false)) {
                pingPhase = 1
            }
        }
    }

    private var orb: some View {
        ZStack {
            attentionRing
            glassBody
            holdRing
            icon
            badge
        }
        .scaleEffect(orbScale)
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isPressed)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: isDragging)
        .contentShape(Circle())
        .onTapGesture {
            impact(.light)
            proactive.markBriefingSeen()
            isMarkErased = true
            onTap()
        }
        .onLongPressGesture(minimumDuration: holdDuration) {
            impact(.medium)
            proactive.markBriefingSeen()
            isMarkErased = true
            onLongPress()
        } onPressingChanged: { pressing in
            isPressed = pressing
            withAnimation(pressing ? .linear(duration: holdDuration)
                                   : .easeOut(duration: 0.18)) {
                holdProgress = pressing ? 1 : 0
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Atlas")
        .accessibilityHint("Double tap to chat. Touch and hold for voice.")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(proactive.hasUnseenBriefing ? "Has an update for you" : "")
        .task { isMarkErased = false }
    }

    private var orbScale: CGFloat {
        if isPressed { return 0.88 }
        if isDragging { return 1.08 }
        return 1
    }

    // MARK: Layers

    /// Glass disc, persona-tinted, with a lit rim so the edge catches light
    /// instead of reading as a flat white outline.
    private var glassBody: some View {
        Circle()
            .fill(.clear)
            .frame(width: diameter, height: diameter)
            .modifier(OrbGlassBackground(tint: persona.accentColor))
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            // Kept deliberately soft: a heavy shadow would darken the very
            // content the clear lens exists to let you keep reading.
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.16),
                    radius: isDragging ? 18 : 10,
                    y: isDragging ? 9 : 5)
            .shadow(color: persona.accentColor.opacity(0.22), radius: 7, y: 2)
    }

    private var icon: some View {
        AtlasMark(size: 23,
                  tint: .white,
                  isThinking: viewModel.isThinking,
                  isErased: isMarkErased)
            // On clear glass the backdrop can be anything, so the mark carries
            // its own contrast rather than relying on the material behind it.
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.25), radius: 1)
            .opacity(holdProgress > 0.02 ? 0.85 : 1)
    }

    /// Fills clockwise while the user holds, previewing the voice gesture.
    @ViewBuilder
    private var holdRing: some View {
        if holdProgress > 0.01 {
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(Color.white.opacity(0.95),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: diameter - 4, height: diameter - 4)
        }
    }

    /// A single expanding ring instead of a permanently pulsing halo — it only
    /// runs when there is actually something to look at.
    @ViewBuilder
    private var attentionRing: some View {
        if proactive.hasUnseenBriefing && !reduceMotion {
            Circle()
                .strokeBorder(persona.accentColor.opacity(0.7 * (1 - Double(pingPhase))),
                              lineWidth: 2)
                .frame(width: diameter + pingPhase * 30,
                       height: diameter + pingPhase * 30)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if proactive.hasUnseenBriefing {
            Circle()
                .fill(Color.red)
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .shadow(color: .red.opacity(0.5), radius: 4)
                .offset(x: diameter * 0.34, y: -diameter * 0.34)
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Placement

    /// Where the orb sits when it isn't being dragged. Stored as a fraction of
    /// the container so it survives rotation and different device sizes.
    private func restingPosition(in size: CGSize) -> CGPoint {
        guard storedX >= 0, storedY >= 0 else { return bottomCentreDock(in: size) }
        return CGPoint(x: storedX * size.width, y: storedY * size.height)
    }

    /// The home position: centred, floating clear of the tab bar.
    private func bottomCentreDock(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height - diameter / 2 - tabBarClearance)
    }

    /// The positions the orb is allowed to come to rest in. Bottom centre is
    /// home; the two side docks exist so it can be moved off anything it hides.
    private func docks(in size: CGSize, droppedAt dropped: CGPoint) -> [CGPoint] {
        let minY = diameter / 2 + 60          // clear of nav bars
        let maxY = size.height - diameter / 2 - tabBarClearance
        let sideY = min(max(dropped.y, minY), max(minY, maxY))

        return [
            bottomCentreDock(in: size),
            CGPoint(x: diameter / 2 + edgeInset, y: sideY),
            CGPoint(x: size.width - diameter / 2 - edgeInset, y: sideY)
        ]
    }

    private func dragGesture(in size: CGSize, from resting: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    impact(.soft)
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                let dropped = CGPoint(x: resting.x + value.translation.width,
                                      y: resting.y + value.translation.height)

                // Settle into whichever dock the drop landed nearest. Bottom
                // centre gets a pull bonus so it stays the natural home.
                let candidates = docks(in: size, droppedAt: dropped)
                let snapped = candidates.enumerated().min { lhs, rhs in
                    distance(from: dropped, to: lhs.element) - (lhs.offset == 0 ? homeDockPull : 0)
                        < distance(from: dropped, to: rhs.element) - (rhs.offset == 0 ? homeDockPull : 0)
                }?.element ?? candidates[0]

                isDragging = false
                dragOffset = .zero
                storedX = snapped.x / max(size.width, 1)
                storedY = snapped.y / max(size.height, 1)
                impact(.rigid)
            }
    }

    private func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - Feedback

    private func impact(_ style: HapticStyle) {
        #if canImport(UIKit) && !os(watchOS)
        UIImpactFeedbackGenerator(style: style.uiStyle).impactOccurred()
        #endif
    }

    private enum HapticStyle {
        case light, medium, soft, rigid

        #if canImport(UIKit) && !os(watchOS)
        var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light:  return .light
            case .medium: return .medium
            case .soft:   return .soft
            case .rigid:  return .rigid
            }
        }
        #endif
    }
}

// MARK: - Glass background

/// Clear Liquid Glass where it exists, a thin material everywhere else. The
/// point of `.clear` over `.regular` is transparency: it refracts what's behind
/// it instead of frosting it, so artwork under the orb stays readable. The tint
/// is kept low for the same reason — it should colour the lens, not fill it.
private struct OrbGlassBackground: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            content.glassEffect(.clear.tint(tint.opacity(0.26)).interactive(), in: .circle)
        } else {
            content.background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle().fill(
                            LinearGradient(
                                colors: [tint.opacity(0.4), tint.opacity(0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
            )
        }
    }
}

// MARK: - Attachment

/// Layers Atlas over a screen. The orb is the resting state; engaging it swaps
/// in `AtlasDockBar`, which takes over the bottom of the screen from the tab
/// bar. There is no Atlas page — the bar grows in place instead.
struct AtlasHUDModifier: ViewModifier {
    @AppStorage(AtlasHUDModifier.enabledKey) private var isHUDEnabled = true
    @ObservedObject private var proactive = AtlasProactiveEngine.shared
    @ObservedObject private var dock = AtlasDockState.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showVoice = false

    static let enabledKey = "atlas_hud_enabled"

    private var showsOrb: Bool {
        #if os(macOS)
        // macOS opens Atlas from its own button beside the tab bar instead.
        false
        #else
        isHUDEnabled && !dock.isEngaged
        #endif
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        if showsOrb {
                            AtlasHUDOrb(
                                onTap: { dock.engage() },
                                onLongPress: { showVoice = true }
                            )
                            // Shrinking toward the bottom edge as the bar grows
                            // out of it reads as one object changing shape.
                            .transition(.scale(scale: 0.4, anchor: .bottom)
                                .combined(with: .opacity))
                        }

                        if dock.isEngaged {
                            AtlasDockBar(
                                availableHeight: geometry.size.height,
                                onVoice: { showVoice = true }
                            )
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .animation(AtlasDockState.transition, value: showsOrb)
            .task { proactive.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { proactive.refresh() }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showVoice) {
                AtlasVoiceView()
            }
            .onChange(of: showVoice) { _, presented in
                if presented { dock.dismiss() }
            }
            #endif
    }
}

extension View {
    /// Adds Atlas: the floating orb, and the dock bar it becomes.
    func atlasHUD() -> some View {
        modifier(AtlasHUDModifier())
    }
}

#endif
