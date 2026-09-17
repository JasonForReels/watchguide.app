//
//  WGMotion.swift
//  WatchGuide-MovieandTVtracker
//
//  A single motion vocabulary for the app. Everything here follows the way the
//  system frameworks move: springs rather than eased durations, interruptible,
//  driven by the user's gesture where possible, and quiet enough that you feel
//  it more than you notice it. Every effect degrades to a plain cross-fade
//  under Reduce Motion.
//

import SwiftUI

// MARK: - Timing

enum WGMotion {
    /// Default for state flips — selection, toggles, badge counts.
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.84)

    /// Layout changes that move a lot of pixels; slower so it reads as one move.
    static let smooth = Animation.spring(response: 0.52, dampingFraction: 0.92)

    /// Reserved for moments of delight — a save landing, a card flipping in.
    static let bouncy = Animation.spring(response: 0.44, dampingFraction: 0.66)

    /// Finger-down/up. Fast enough to feel connected to the touch.
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.72)

    /// Content arriving on screen.
    static let reveal = Animation.spring(response: 0.55, dampingFraction: 0.86)

    /// Staggered entrance delay. Capped so a long list never feels like it is
    /// dealing cards at the user — the last item should still land quickly.
    static func stagger(_ index: Int, step: Double = 0.04, cap: Double = 0.32) -> Double {
        min(Double(max(index, 0)) * step, cap)
    }

    /// Resolves an animation against the Reduce Motion setting.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }
}

// MARK: - Press feedback

/// The press behaviour used across every tappable card and pill in the app:
/// a small scale-in with a matching dim, springing back on release. The scale
/// is deliberately shallow — large poster art distorts badly if you squash it.
struct WGPressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var dims: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? scale : 1.0))
            .opacity(dims && configuration.isPressed ? 0.86 : 1.0)
            .animation(WGMotion.resolved(WGMotion.press, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
            #if os(iOS)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.5),
                             trigger: configuration.isPressed) { _, pressed in pressed }
            #endif
    }
}

extension ButtonStyle where Self == WGPressButtonStyle {
    static var wgPress: WGPressButtonStyle { WGPressButtonStyle() }

    /// Deeper press for small controls, where a 4% change is invisible.
    static var wgPressDeep: WGPressButtonStyle { WGPressButtonStyle(scale: 0.92) }
}

// MARK: - Scroll-driven effects

private struct WGCarouselItemModifier: ViewModifier {
    var minScale: CGFloat
    var minOpacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.scrollTransition(.interactive, axis: .horizontal) { view, phase in
                view
                    .scaleEffect(phase.isIdentity ? 1.0 : minScale, anchor: .center)
                    .opacity(phase.isIdentity ? 1.0 : minOpacity)
                    .blur(radius: phase.isIdentity ? 0 : 1.2)
            }
        }
    }
}

private struct WGSectionRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // tvOS scrolling is driven by the focus engine rather than the finger,
        // so a viewport-based reveal fights it instead of following it.
        #if os(tvOS)
        content
        #else
        if reduceMotion {
            content
        } else {
            content.scrollTransition(.animated(WGMotion.reveal), axis: .vertical) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1.0 : 0)
                    .offset(y: phase.value < 0 ? -16 : 16)
                    .scaleEffect(phase.isIdentity ? 1.0 : 0.97, anchor: .top)
            }
        }
        #endif
    }
}

private struct WGStaggeredAppearModifier: ViewModifier {
    let index: Int
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : 12)
            .onAppear {
                guard !hasAppeared else { return }
                withAnimation(
                    WGMotion.resolved(WGMotion.reveal, reduceMotion: reduceMotion)
                        .delay(reduceMotion ? 0 : WGMotion.stagger(index))
                ) {
                    hasAppeared = true
                }
            }
    }
}

extension View {
    /// Ties a card's scale and focus to its position in a horizontal carousel,
    /// so the row responds continuously to the drag rather than snapping.
    func wgCarouselItem(minScale: CGFloat = 0.94, minOpacity: Double = 0.78) -> some View {
        modifier(WGCarouselItemModifier(minScale: minScale, minOpacity: minOpacity))
    }

    /// Fades and lifts a whole section as it enters the viewport of a vertical
    /// feed. Use on rows, not on individual cards — stacking both reads as noise.
    func wgSectionReveal() -> some View {
        modifier(WGSectionRevealModifier())
    }

    /// One-shot staggered entrance for grids and stacks that are not inside a
    /// scroll view we control. Prefer `wgCarouselItem` when there is a scroll.
    func wgStaggeredAppear(index: Int) -> some View {
        modifier(WGStaggeredAppearModifier(index: index))
    }
}

// MARK: - Transitions

/// For content that resolves in place after a network round-trip — a badge, a
/// score, a provider logo. It blurs in rather than sliding, so a late arrival
/// does not look like a new item the user just inserted.
struct WGBadgeArrivalTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .blur(radius: phase.isIdentity ? 0 : 6)
            .opacity(phase.isIdentity ? 1 : 0)
            .scaleEffect(phase.isIdentity ? 1 : 0.92)
    }
}

extension Transition where Self == WGBadgeArrivalTransition {
    static var wgBadgeArrival: WGBadgeArrivalTransition { .init() }
}

// MARK: - Zoom transitions

/// The namespace backing poster → detail zoom transitions. Held in the
/// environment so a card anywhere in the tree can act as a transition source
/// without every intermediate view having to forward a `Namespace.ID`.
private struct WGZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var wgZoomNamespace: Namespace.ID? {
        get { self[WGZoomNamespaceKey.self] }
        set { self[WGZoomNamespaceKey.self] = newValue }
    }
}

private struct WGZoomSourceModifier: ViewModifier {
    let id: String
    @Environment(\.wgZoomNamespace) private var namespace

    func body(content: Content) -> some View {
        #if os(iOS)
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// The namespace is passed explicitly here rather than read from the
/// environment: the detail screen is presented in a `fullScreenCover`, and a
/// presented scene is not guaranteed to inherit custom environment values.
private struct WGZoomDestinationModifier: ViewModifier {
    let id: String?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        #if os(iOS)
        if let id {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Marks this view as the thing the detail screen grows out of.
    func wgZoomSource(id: String) -> some View {
        modifier(WGZoomSourceModifier(id: id))
    }

    /// Applied to the presented detail screen to complete the zoom.
    func wgZoomDestination(id: String?, in namespace: Namespace.ID) -> some View {
        modifier(WGZoomDestinationModifier(id: id, namespace: namespace))
    }
}

/// Identifiers for zoom sources. Media appears in many rows at once, so the
/// id has to include where it was tapped or several sources claim the same id
/// and the system picks an arbitrary one to fly from.
enum WGZoomID {
    static func media(_ id: Int, context: String) -> String {
        "media-\(id)-\(context)"
    }
}

/// Remembers which card started the current presentation. The detail screen is
/// presented from a modifier that only receives the item, so without this it
/// has no way to tell which of the several rows showing that title the user
/// actually tapped — and the zoom would fly from the wrong poster.
@MainActor
enum WGZoom {
    private(set) static var activeSourceID: String?

    /// Call from a card's tap handler, immediately before presenting.
    static func willPresent(_ id: String) {
        activeSourceID = id
    }

    static func didDismiss() {
        activeSourceID = nil
    }
}
