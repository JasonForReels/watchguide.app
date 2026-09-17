//
//  CinematicHeroCarouselView.swift
//  WatchGuide-MovieandTVtracker
//
//  The "Cinematic" hero style: a layered parallax stage rather than a card that
//  slides. Four layers animate at staggered rates so the frame reads as a
//  physical space with depth instead of a flat image swap:
//
//    Layer 1 — Ambient background. Backdrop art, replaced by a silent trailer
//              once the viewer has dwelled on the slide. Transitions with an
//              800ms cross-dissolve combined with a subtle 1.05x scale-up.
//    Layer 2 — Subject cutout. FanArt.tv alpha-channel character art layered
//              above the background, scaling and sliding *faster* than Layer 1
//              so subjects appear to pop out of the frame.
//    Layer 3 — Identity. Transparent logo art (or a display title) plus the
//              service badge and metadata line. Enters on a 200ms delay and
//              only fades 0 → 1, so it never fights the background motion.
//    Layer 4 — Static scaffolding. The bottom gradient mask, the action button
//              and the page dots. This layer never moves and never fades, so
//              the controls stay locked in place while artwork swaps behind it.
//
//  Rendering is virtualised: only the previous, current and next slides are
//  built. Everything else is unmounted, so no off-screen AVPlayer is retained.
//
//  Playback, artwork loading and timing are shared with the classic carousel —
//  `HeroTrailerLoader`, `CarouselTimerManager`, `HeroPlayerViewModel` and
//  `HeroCarouselMuteManager` are reused as-is so both styles behave identically.
//

import SwiftUI
import Combine
import AVKit
import AVFoundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if !os(tvOS)
import YouTubePlayerKit
#endif

// MARK: - Stage Blend Metrics

/// Depth of the fades that dissolve the stage into the page at its top and
/// bottom edges. Shared with the slide so transient chrome — the mute button —
/// can keep clear of the faded regions.
private enum HeroBlend {
    /// There is deliberately no alpha fade at the top any more. Punching the
    /// artwork out to transparent there let the page's own black through as a
    /// hard band across the top of the frame — the single most "boxed in" thing
    /// about the stage. The top scrim, which darkens rather than erases, keeps
    /// the bar above legible on its own.
    static let top: CGFloat = 0

    #if os(tvOS)
    static let topScrim: CGFloat = 260
    static let bottom: CGFloat = 112
    #else
    static let topScrim: CGFloat = 148
    static let bottom: CGFloat = 56
    #endif
}

// MARK: - Cinematic Hero Carousel

struct CinematicHeroCarouselView: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    /// Aspect ratio of the stage. Defaults to a wide 2:1 crop; callers on compact
    /// widths should pass something closer to 3:2 so the artwork isn't reduced to a slit.
    let stageAspect: CGFloat
    /// Identifies which tab this carousel belongs to, so it can be paused when off-screen.
    let tabID: String?

    @ObservedObject private var storageService = StorageService.shared
    private var showTrailers: Bool { storageService.settings.autoPlayTrailers }

    @State private var currentIndex = 0
    /// How many times the auto-advance has been held open waiting for the
    /// current slide's trailer lookup. Reset whenever a slide takes the stage.
    @State private var graceExtensions = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    /// Drives the slow push on the ambient layer. Flipped on every slide change
    /// so the animation restarts from its beginning.
    @State private var pushEngaged = false
    /// How far the stage must reach past its container on each side to meet the
    /// window edges. Scroll containers inset their content — on tvOS by the
    /// overscan margin, elsewhere by whatever content margins the platform
    /// applies — which left the hero sitting inside a black frame. A frame is
    /// what makes a hero read as a card on the page; this style is meant to be
    /// the page's top edge, so the stage cancels that inset back out.
    @State private var horizontalBleed: CGFloat = 0

    /// Ceiling on that reach: enough to clear the widest platform margin, but
    /// not so much that a hero genuinely placed in a narrow column bursts out
    /// of it.
    private static let maxHorizontalBleed: CGFloat = 130

    /// tvOS clamps the stage so it never fills the screen — see
    /// `HeroCarouselLayout.tvMinimumAspectRatio`. Every other platform uses the
    /// stage shape the caller asked for.
    private var effectiveStageAspect: CGFloat {
        #if os(tvOS)
        max(stageAspect, HeroCarouselLayout.tvMinimumAspectRatio)
        #else
        stageAspect
        #endif
    }

    #if os(tvOS)
    /// Focus lives on the "More Details" button alone — see `actionButton`.
    @FocusState private var isActionFocused: Bool
    #endif
    @StateObject private var trailerLoader = HeroTrailerLoader()
    @StateObject private var cutoutLoader = HeroCutoutLoader()
    @StateObject private var timerManager = CarouselTimerManager()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(macOS)
    /// Pointer is over the stage. Reveals the paging buttons and arms the
    /// trackpad and arrow-key handling, so those only act on the hero the
    /// viewer is actually pointing at.
    @State private var isHovering = false
    @State private var stageWidth: CGFloat = 0
    @StateObject private var inputMonitor = MacCarouselInputMonitor()
    #endif

    // MARK: Motion + timing constants

    /// Layer 1's cross-dissolve. Every layer is driven off `currentIndex`, so
    /// they share this duration and differ only in how far they travel — which
    /// is what produces the staggered, parallax read.
    private static let crossDissolve: TimeInterval = 0.8
    /// How long a viewer stays on a slide before the trailer stream is requested.
    /// Long enough to actually take in the artwork, the push and the parallax
    /// before video takes the frame over.
    private static let autoplayDwell: TimeInterval = 10.0
    /// Idle auto-rotation interval, used only when trailer autoplay is switched off.
    private static let idleRotation: TimeInterval = 6.0
    /// Layer 3 is slotted in behind the background motion rather than with it.
    private static let identityDelay: TimeInterval = 0.2

    private let maxSlides = 10
    private var slideCount: Int { min(items.count, maxSlides) }
    private var slides: [MediaItem] { Array(items.prefix(maxSlides)) }
    private var currentItem: MediaItem? { slides[safe: currentIndex] }

    /// Reduce Motion keeps the cross-dissolve — it's the thing that makes the
    /// carousel legible — but drops every scale, drift and push.
    private var dissolve: Animation {
        .easeInOut(duration: reduceMotion ? 0.35 : Self.crossDissolve)
    }

    init(
        items: [MediaItem],
        onItemTap: @escaping (MediaItem) -> Void,
        stageAspect: CGFloat = 2.0,
        tabID: String? = nil
    ) {
        self.items = items
        self.onItemTap = onItemTap
        self.stageAspect = stageAspect
        self.tabID = tabID
    }

    var body: some View {
        stage
            .onReceive(timerManager.$shouldAdvance) { shouldAdvance in
                guard shouldAdvance, slideCount > 1 else { return }
                timerManager.shouldAdvance = false
                // Don't move on from a slide that hasn't been told yet whether
                // it has a trailer — that is what left the first title of a
                // cold start silent until its second time around.
                if shouldWaitForTrailerLookup {
                    graceExtensions += 1
                    timerManager.extendTrailerGrace(by: HeroTrailerTiming.lookupGrace)
                    return
                }
                goTo(index: nextIndex)
            }
            .onChange(of: timerManager.backdropTimerExpired) { _, expired in
                // With autoplay off there is no trailer to hand over to, so the
                // dwell timer doubles as the idle rotation timer.
                guard expired, !showTrailers, slideCount > 1 else { return }
                goTo(index: nextIndex)
            }
            .onChange(of: items.count) { _, _ in
                if slideCount == 0 { currentIndex = 0 }
                else if currentIndex >= slideCount { currentIndex = 0 }
            }
            .onAppear {
                restartTimers()
                #if os(macOS)
                configureInputMonitor()
                #endif
            }
            #if os(macOS)
            .onDisappear {
                inputMonitor.stop()
                isHovering = false
            }
            #endif
            .task {
                // Artwork and trailers load in parallel — same contract as the classic
                // carousel, so trailers arrive before the dwell plus grace period expires.
                if showTrailers {
                    async let artwork: Void = trailerLoader.loadArtwork(for: items)
                    async let trailers: Void = loadTrailersFirstSlideFirst()
                    _ = await (artwork, trailers)
                } else {
                    await trailerLoader.loadArtwork(for: items)
                }
                // Cutouts run last: `loadArtwork` has already pulled and cached each
                // title's FanArt.tv record, so Layer 2 costs no extra network request.
                await cutoutLoader.load(for: items)
            }
    }

    // MARK: - Stage

    private var stage: some View {
        // GeometryReader inside, aspectRatio outside: the same sizing pattern the
        // classic carousel uses, which resolves to a finite height in a ScrollView.
        GeometryReader { geo in
            stageContent(size: geo.size)
                .onAppear {
                    updateBleed(measuredWidth: geo.size.width)
                    #if os(macOS)
                    stageWidth = geo.size.width
                    #endif
                }
                .onChange(of: geo.size.width) { _, width in
                    updateBleed(measuredWidth: width)
                    #if os(macOS)
                    stageWidth = width
                    #endif
                }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(effectiveStageAspect, contentMode: .fit)
        // Deliberately no corner radius, border or drop shadow: those are what
        // make a hero read as a card sitting *on* the page. This one runs to the
        // edges and dissolves into the page at the bottom instead.
        .clipped()
        .padding(.horizontal, -horizontalBleed)
    }

    /// `measuredWidth` is the stage *after* the current bleed has been applied,
    /// so the bleed is subtracted back out before it is compared against the
    /// window. Measuring the container rather than the result is what makes this
    /// settle on a fixed point instead of oscillating.
    private func updateBleed(measuredWidth: CGFloat) {
        guard measuredWidth > 0,
              let windowWidth = Self.hostWindowWidth(),
              windowWidth > 0 else { return }
        let containerWidth = measuredWidth - horizontalBleed * 2
        let inset = ((windowWidth - containerWidth) / 2).rounded()
        let clamped = min(max(inset, 0), Self.maxHorizontalBleed)
        if abs(clamped - horizontalBleed) > 0.5 {
            horizontalBleed = clamped
        }
    }

    /// Width of the window the stage is being drawn into, which is the width it
    /// is trying to fill.
    private static func hostWindowWidth() -> CGFloat? {
        #if canImport(UIKit)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .bounds.width
        #elseif canImport(AppKit)
        return NSApplication.shared.keyWindow?.frame.width
        #else
        return nil
        #endif
    }

    @ViewBuilder
    private func stageContent(size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Everything in here is artwork, and it is masked so the bottom edge
            // dissolves into whatever the page background is instead of ending on
            // a hard line. The identity and control layers sit outside the mask so
            // they stay fully opaque.
            ZStack(alignment: .bottomLeading) {
                Color.black

                // Layers 1 + 2 — only the neighbouring slides exist. A slide leaving
                // this window is unmounted, which tears down its player with it.
                ForEach(renderedSlides) { entry in
                    CinematicHeroSlide(
                        item: entry.item,
                        isActive: entry.index == currentIndex && !isDragging,
                        preferredTrailer: trailerLoader.preferredTrailers[entry.item.id],
                        fanartBackdropURL: trailerLoader.fanartBackdropURLs[entry.item.id],
                        cutoutURL: cutoutLoader.cutoutURLs[entry.item.id],
                        slideSize: size,
                        offsetFactor: offsetFactor(for: entry.index, containerWidth: size.width),
                        trailerPhase: timerManager.trailerPhase,
                        backdropTimerExpired: timerManager.backdropTimerExpired,
                        showTrailers: showTrailers,
                        pushEngaged: pushEngaged && entry.index == currentIndex,
                        reduceMotion: reduceMotion,
                        tabID: tabID,
                        onTrailerDurationKnown: { duration in
                            if entry.index == currentIndex {
                                timerManager.beginTrailerPlayback(duration: duration)
                            }
                        },
                        onTrailerEnded: {
                            if entry.index == currentIndex {
                                timerManager.endTrailerPlayback()
                            }
                        }
                    )
                    .frame(width: size.width, height: size.height)
                    .zIndex(entry.index == currentIndex ? 1 : 0)
                    // Not opted out of hit testing as a whole: the slide's own
                    // artwork layers are, but its mute button has to receive the
                    // click, or it falls through to the stage and opens the title.
                }

                // Layer 4a — the permanent gradient scrim. Never moves, never fades.
                scaffoldingMask(size: size)
                    .allowsHitTesting(false)
            }
            .mask(pageBlendMask(size: size))

            // Layer 3 — identity. Cross-fades with the slide, on a 200ms delay.
            ForEach(renderedSlides) { entry in
                identityBlock(for: entry.item, size: size)
                    .opacity(entry.index == currentIndex ? 1 : 0)
                    .animation(
                        .easeOut(duration: 0.5)
                            .delay(entry.index == currentIndex ? Self.identityDelay : 0),
                        value: currentIndex
                    )
            }
            .allowsHitTesting(false)

            // Layer 4b — controls and dots. Locked in place so they stay readable
            // and hittable while vibrant artwork swaps behind them.
            staticControls(size: size)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        #if !os(tvOS)
        .gesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    guard !isPagingLocked, slideCount > 1 else { return }
                    isDragging = true
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    guard !isPagingLocked, slideCount > 1 else {
                        isDragging = false
                        dragOffset = 0
                        return
                    }
                    isDragging = false
                    let threshold = size.width * 0.15
                    let velocity = value.predictedEndTranslation.width - value.translation.width

                    if value.translation.width < -threshold || velocity < -150 {
                        goTo(index: nextIndex)
                    } else if value.translation.width > threshold || velocity > 150 {
                        goTo(index: previousIndex)
                    } else {
                        withAnimation(dissolve) { dragOffset = 0 }
                    }
                }
        )
        #endif
        #if os(macOS)
        // A click on the artwork opens the title, the way a banner does anywhere
        // else on the Mac. The buttons inside the stage take their own clicks first.
        .onTapGesture {
            if let item = currentItem { onItemTap(item) }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) { isHovering = hovering }
            inputMonitor.isArmed = hovering
        }
        #endif
    }

    /// A phone locks paging while a trailer plays, so a stray swipe doesn't cut
    /// it off. Mac input — a click, a key, a two-finger swipe — is never
    /// accidental, so there the viewer can always move on.
    private var isPagingLocked: Bool {
        #if os(macOS)
        false
        #else
        timerManager.isTrailerPlaying
        #endif
    }

    #if os(macOS)
    // MARK: - Mac input

    /// Trackpad swipes follow the fingers through the same `dragOffset` a drag
    /// uses, so the parallax layers track the gesture exactly as they do on a
    /// phone, then settle with the same threshold rules.
    private func configureInputMonitor() {
        inputMonitor.onSwipeChanged = { translation in
            guard slideCount > 1 else { return }
            isDragging = true
            dragOffset = translation
        }
        inputMonitor.onSwipeEnded = { translation, flick in
            guard slideCount > 1 else { return }
            isDragging = false
            let threshold = max(stageWidth, 1) * 0.15
            if translation < -threshold || flick < -12 {
                goTo(index: nextIndex)
            } else if translation > threshold || flick > 12 {
                goTo(index: previousIndex)
            } else {
                withAnimation(dissolve) { dragOffset = 0 }
            }
        }
        inputMonitor.onArrow = { forward in
            guard slideCount > 1 else { return }
            goTo(index: forward ? nextIndex : previousIndex)
        }
        inputMonitor.start()
    }

    /// Glass paging button shown beside the dots while the pointer is over the
    /// stage. The tooltip names the title it leads to.
    private func pagingButton(forward: Bool, metrics: HeroStageMetrics) -> some View {
        let target = slides[safe: forward ? nextIndex : previousIndex]
        return Button {
            goTo(index: forward ? nextIndex : previousIndex)
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: metrics.buttonSize, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: metrics.buttonSize * 1.4, height: metrics.buttonSize * 1.4)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .pointerStyle(.link)
        .help("\(forward ? "Next" : "Previous"): \(target?.displayTitle ?? "")  (\(forward ? "→" : "←"))")
        .opacity(isHovering ? 1 : 0)
        .scaleEffect(isHovering ? 1 : 0.85)
        .allowsHitTesting(isHovering)
    }
    #endif

    // MARK: - Layer 4a: gradient mask

    /// A fixed linear scrim: solid at the bottom, tapering to clear at the top,
    /// plus a lighter left-hand wash for the identity column. It is deliberately
    /// outside the slide `ForEach` so nothing about it is tied to slide state.
    ///
    /// It reaches *fully* black at the bottom edge rather than stopping at 0.85,
    /// so the artwork has already resolved to the page's own darkness by the time
    /// the alpha blend takes over. That keeps the transition seamless over the
    /// trailer layer too, where a mask alone is least dependable.
    private func scaffoldingMask(size: CGSize) -> some View {
        // On a phone the "left side" of the frame is most of the frame, so a wash
        // graded for a wide plate sinks the whole picture into mud. Compact
        // widths get a shallower version that still seats the lettering.
        let compact = HeroStageMetrics(stageWidth: size.width).isCompact
        return ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black.opacity(0.10), location: 0.34),
                    .init(color: .black.opacity(0.42), location: 0.58),
                    .init(color: .black.opacity(0.80), location: 0.78),
                    .init(color: .black.opacity(0.96), location: 0.90),
                    .init(color: .black, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // The left-hand wash carries most of the grade. It reaches further
            // across the frame than a scrim needs to for legibility alone,
            // because what it is really doing is what a colourist would do to a
            // plate: sink one side of the image so the eye lands on the
            // lettering first and the subject second.
            LinearGradient(
                stops: compact
                    ? [
                        .init(color: .black.opacity(0.52), location: 0),
                        .init(color: .black.opacity(0.24), location: 0.32),
                        .init(color: .clear, location: 0.62)
                    ]
                    : [
                        .init(color: .black.opacity(0.78), location: 0),
                        .init(color: .black.opacity(0.46), location: 0.30),
                        .init(color: .black.opacity(0.16), location: 0.55),
                        .init(color: .clear, location: 0.78)
                    ],
                startPoint: .leading,
                endPoint: .trailing
            )
            // Top band, mirroring the bottom: resolves to solid black at the very
            // top edge so the artwork has met the page's darkness before the alpha
            // blend finishes the job. Fixed height rather than proportional, so a
            // tall stage doesn't lose a bigger slice of its artwork than a short one.
            //
            // It runs deeper than the alpha blend on purpose. Where the stage bleeds
            // up behind a navigation bar, the alpha fade alone would hand the bar's
            // buttons a fully lit frame to sit on; carrying a soft darkening past it
            // gives them a legible field without dimming the artwork any further down.
            //
            // It stops short of solid black at the very top edge on purpose.
            // Blacking the edge out gave the bar above a lit shelf to sit on
            // and cost the frame its whole top band; darkening it to two thirds
            // keeps the artwork visible right up to the edge and still gives
            // toolbar glyphs a field dark enough to read against.
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.72), location: 0),
                        .init(color: .black.opacity(0.44), location: 0.35),
                        .init(color: .black.opacity(0.18), location: 0.65),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: HeroBlend.topScrim)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Page blend

    /// Fades the artwork out at both the top and bottom edges so the stage
    /// dissolves into the page rather than stopping on a hard line at either end.
    /// Masking with alpha rather than compositing a coloured gradient means this
    /// works against whatever the page behind it happens to be, in either scheme.
    private func pageBlendMask(size: CGSize) -> some View {
        // `HeroBlend.top` is 0 because the stage used to start at the very top
        // pixel, where an alpha fade only let the page's black through as a hard
        // band. On a phone the stage is now inset below the status bar, so there
        // is page above it to dissolve into — and without a fade the artwork
        // ends on exactly the hard line that band was. The fade goes back on at
        // the only size that needs it.
        let topFade = HeroStageMetrics(stageWidth: size.width).isCompact ? 72 : HeroBlend.top
        return VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.75), location: 0.55),
                    .init(color: .black, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: topFade)

            Rectangle().fill(Color.black)

            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.75), location: 0.45),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: HeroBlend.bottom)
        }
    }

    // MARK: - Layer 3: identity

    /// Service badge, title treatment and metadata line. Pinned to a fixed height
    /// so a tall logo can never shove the static control row around.
    ///
    /// The badge carries the streaming service only — `showsStudioLogo` is off.
    /// The studio wordmark is a second piece of lettering stacked directly above
    /// the title treatment, which is itself usually a wordmark, and the pair read
    /// as competing titles.
    private func identityBlock(for item: MediaItem, size: CGSize) -> some View {
        let metrics = HeroStageMetrics(stageWidth: size.width)
        return VStack(alignment: .leading, spacing: metrics.identitySpacing) {
            Spacer(minLength: 0)

            #if os(tvOS)
            StreamingLogoBadge(
                mediaId: item.id,
                mediaType: item.resolvedMediaType,
                showsStudioLogo: false
            )
            .scaleEffect(1.6, anchor: .leading)
            #else
            StreamingLogoBadge(
                mediaId: item.id,
                mediaType: item.resolvedMediaType,
                scale: 2.0,
                showsStudioLogo: false
            )
            #endif

            titleTreatment(for: item, size: size, metrics: metrics)

            // The metadata line steps aside once the trailer is on screen — it is
            // reference text, and the footage is the thing worth looking at.
            //
            // On a phone it leaves the layout entirely rather than just fading.
            // Fading alone left the row occupying a line, and since the block is
            // bottom-aligned that empty line held the treatment up away from the
            // button. Zeroing its height wasn't enough either — the VStack still
            // spends `identitySpacing` on a zero-height row — so during playback
            // it is removed outright.
            if !(trailerActive && metrics.usesPhoneIdentity) {
                metadataRow(for: item, metrics: metrics)
                    .opacity(trailerActive ? 0 : 1)
                    .animation(.easeInOut(duration: 0.4), value: trailerActive)
            }

            // A logline, where the stage is big enough to carry one. On a
            // television the frame is mostly empty below the title, and two
            // lines of synopsis is what turns a picture with a caption into a
            // billboard for the thing itself. It goes with the metadata when
            // footage takes the frame.
            if metrics.showsSynopsis, let overview = item.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: metrics.synopsisSize, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .lineLimit(2)
                    .lineSpacing(metrics.synopsisSize * 0.24)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: size.width * metrics.synopsisWidthFraction, alignment: .leading)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                    .opacity(trailerActive ? 0 : 1)
                    .animation(.easeInOut(duration: 0.4), value: trailerActive)
            }
        }
        // Fixed height, then inset — insetting a full-width frame would push the
        // block past the stage edges.
        .frame(height: metrics.identityHeight, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, metrics.contentInset)
        .padding(
            .bottom,
            trailerActive && metrics.usesPhoneIdentity
                ? metrics.trailerIdentityBottomInset
                : metrics.identityBottomInset
        )
        .animation(.easeInOut(duration: 0.4), value: trailerActive)
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
    }

    /// Height the treatment is drawn at right now. On a phone it drops to the
    /// action button's height once footage is on screen: the metadata and
    /// synopsis have already stepped aside for the trailer, and a full-size
    /// treatment left over them is the last thing covering the picture. It
    /// shrinks rather than disappearing so the frame still says what it's
    /// showing you.
    private func currentLogoHeight(_ metrics: HeroStageMetrics) -> CGFloat {
        trailerActive && metrics.usesPhoneIdentity ? metrics.trailerLogoHeight : metrics.logoHeight
    }

    private func currentTitleSize(_ metrics: HeroStageMetrics) -> CGFloat {
        trailerActive && metrics.usesPhoneIdentity ? metrics.trailerTitleSize : metrics.titleSize
    }

    private func currentLogoWidthFraction(_ metrics: HeroStageMetrics) -> CGFloat {
        trailerActive && metrics.usesPhoneIdentity ? metrics.trailerLogoWidthFraction : metrics.logoWidthFraction
    }

    @ViewBuilder
    private func titleTreatment(for item: MediaItem, size: CGSize, metrics: HeroStageMetrics) -> some View {
        if let logoURLStr = trailerLoader.logoURLs[item.id], let logoURL = URL(string: logoURLStr) {
            AsyncImage(url: logoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: size.width * currentLogoWidthFraction(metrics),
                            maxHeight: currentLogoHeight(metrics),
                            alignment: .bottomLeading
                        )
                        // A treatment this size needs a deeper shadow than a
                        // label does, or it floats off a bright plate.
                        .shadow(color: .black.opacity(0.7), radius: metrics.logoHeight * 0.16, y: metrics.logoHeight * 0.05)
                        .animation(.easeInOut(duration: 0.4), value: trailerActive)
                default:
                    largeTitleText(for: item, size: size, metrics: metrics)
                }
            }
            .frame(maxWidth: size.width * currentLogoWidthFraction(metrics), alignment: .leading)
            .animation(.easeInOut(duration: 0.4), value: trailerActive)
        } else {
            largeTitleText(for: item, size: size, metrics: metrics)
        }
    }

    private func largeTitleText(for item: MediaItem, size: CGSize, metrics: HeroStageMetrics) -> some View {
        Text(item.displayTitle)
            .font(.system(size: currentTitleSize(metrics), weight: .heavy, design: .default))
            .tracking(-currentTitleSize(metrics) * 0.02)
            .foregroundColor(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .shadow(color: .black.opacity(0.65), radius: metrics.titleSize * 0.18, y: metrics.titleSize * 0.06)
            .frame(
                maxWidth: size.width * (metrics.logoWidthFraction + 0.1),
                maxHeight: currentLogoHeight(metrics),
                alignment: .bottomLeading
            )
            .animation(.easeInOut(duration: 0.4), value: trailerActive)
    }

    /// One quiet line of reference text, set as a single run separated by
    /// middots.
    ///
    /// The outlined "FILM" capsule and the yellow star this replaces were the
    /// two loudest things in the frame — both badges, both competing with the
    /// title treatment directly above them for the same attention. A billboard
    /// carries its caption in one weight and one colour; the picture is what is
    /// supposed to be doing the talking.
    private func metadataRow(for item: MediaItem, metrics: HeroStageMetrics) -> some View {
        HStack(spacing: metrics.metadataSize * 0.52) {
            Text(item.resolvedMediaType == .movie ? "FILM" : "SERIES")
                .tracking(metrics.metadataSize * 0.16)

            if let year = item.year {
                metadataSeparator
                Text(year)
            }

            if let rating = item.voteAverage, rating > 0 {
                metadataSeparator
                HStack(spacing: metrics.metadataSize * 0.26) {
                    Image(systemName: "star.fill")
                        .font(.system(size: metrics.metadataSize * 0.78))
                    Text(String(format: "%.1f", rating))
                }
            }

            if metrics.showsGenres, !genreNames(for: item).isEmpty {
                metadataSeparator
                Text(genreNames(for: item).joined(separator: ", "))
            }
        }
        .lineLimit(1)
        .font(.system(size: metrics.metadataSize, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.82))
        .shadow(color: .black.opacity(0.6), radius: 5, y: 2)
    }

    private var metadataSeparator: some View {
        Text("·").foregroundStyle(Color.white.opacity(0.4))
    }

    // MARK: - Layer 4b: static controls

    /// The dots sit centred on the stage rather than tucked into the trailing
    /// corner opposite the button. Pinned to the corner they read as a control
    /// bar and pull the eye to the far edge of a wide frame; centred, they read
    /// as the mark of where you are in the reel, and the corner stays empty for
    /// the subject art to occupy.
    private func staticControls(size: CGSize) -> some View {
        let metrics = HeroStageMetrics(stageWidth: size.width)
        // On a phone the frame is too narrow for a centred marker to read as
        // anything but a second control floating beside the button. Pushed to
        // the trailing edge it pairs with the button the way a page indicator
        // normally does, and the middle of the frame stays empty.
        return ZStack(alignment: metrics.isCompact ? .trailing : .center) {
            HStack {
                actionButton(metrics: metrics)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 12)
            }

            if slideCount > 1 {
                #if os(macOS)
                HStack(spacing: metrics.buttonSize * 0.9) {
                    pagingButton(forward: false, metrics: metrics)
                    CinematicPageDots(
                        totalPages: slideCount,
                        currentPage: currentIndex,
                        progress: timerManager.progress,
                        titles: slides.map(\.displayTitle),
                        onSelect: { index in
                            guard index != currentIndex else { return }
                            goTo(index: index)
                        }
                    )
                    pagingButton(forward: true, metrics: metrics)
                }
                #else
                CinematicPageDots(
                    totalPages: slideCount,
                    currentPage: currentIndex,
                    progress: timerManager.progress
                )
                #endif
            }
        }
        .padding(.horizontal, metrics.contentInset)
        // Cleared of the blend zone, so the controls always sit on solid artwork
        // rather than floating over the fade into the page.
        .padding(.bottom, metrics.controlsBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder
    private func actionButton(metrics: HeroStageMetrics) -> some View {
        #if os(tvOS)
        // The only focusable thing in the hero. The stage used to be one big
        // focusable region, which meant the whole picture lit up as a control
        // and the remote had nowhere to go from it; the artwork is something to
        // look at, and this is the one thing to press. Focus therefore moves
        // between this button, the tab bar above it and the first row below it,
        // like any other control on the page.
        Button {
            if let item = currentItem { onItemTap(item) }
        } label: {
            actionButtonLabel(metrics: metrics)
        }
        .buttonStyle(
            TVHeroActionButtonStyle(
                horizontalPadding: metrics.buttonSize * 1.5,
                verticalPadding: metrics.buttonSize * 0.7
            )
        )
        .focused($isActionFocused)
        // Left and right still page the carousel while the button holds focus.
        // Nothing else in the hero is focusable, so the focus engine has no use
        // for those presses and they would otherwise be dropped.
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard !timerManager.isTrailerPlaying, slideCount > 1 else { return .ignored }
            goTo(index: press.key == .leftArrow ? previousIndex : nextIndex)
            return .handled
        }
        .onChange(of: isActionFocused) { _, focused in
            TVHeroFocusState.shared.isHeroFocused = focused
        }
        .onDisappear {
            if isActionFocused { TVHeroFocusState.shared.isHeroFocused = false }
        }
        #else
        Button {
            if let item = currentItem { onItemTap(item) }
        } label: {
            actionButtonLabel(metrics: metrics)
        }
        // The glass style brings its own padding, capsule and interactive
        // response, so the label stays bare.
        .buttonStyle(.glass)
        // Small control size trims the glass capsule's own padding, so the call
        // to action keeps its footprint off the trailer frame.
        .controlSize(.small)
        #if os(macOS)
        .pointerStyle(.link)
        #endif
        #endif
    }

    /// Off tvOS the foreground colour is set explicitly. The glass button style
    /// tints its label from the environment's tint rather than a fixed colour,
    /// and this app ships an empty `AccentColor` asset, so leaving it to resolve
    /// on its own renders the label invisible. White is also simply the right
    /// choice there: the stage is always dark behind the control row. On tvOS
    /// the colour is left to the button style, which flips it to black when the
    /// capsule fills white on focus.
    ///
    /// `fixedSize` keeps the label at its intrinsic width so the text can never
    /// be squeezed away by the page dots sharing the row.
    private func actionButtonLabel(metrics: HeroStageMetrics) -> some View {
        HStack(spacing: metrics.buttonSize * 0.45) {
            // An info glyph rather than a play triangle: the action opens the
            // detail sheet, it doesn't start playback.
            Image(systemName: "info.circle")
            Text("More Details")
        }
        .font(.system(size: metrics.buttonSize, weight: .semibold))
        #if !os(tvOS)
        .foregroundStyle(.white)
        #endif
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Virtualised window

    /// Only the previous, current and next slides are built. A `Set` collapses the
    /// duplicate when there are exactly two slides and prev == next.
    private var renderedSlides: [RenderedSlide] {
        guard slideCount > 0 else { return [] }
        guard slideCount > 1 else {
            return slides[safe: 0].map { [RenderedSlide(index: 0, item: $0)] } ?? []
        }
        let window = Set([previousIndex, currentIndex, nextIndex])
        return window.sorted().compactMap { index in
            slides[safe: index].map { RenderedSlide(index: index, item: $0) }
        }
    }

    private var nextIndex: Int {
        slideCount > 0 ? (currentIndex + 1) % slideCount : 0
    }

    private var previousIndex: Int {
        slideCount > 0 ? (currentIndex - 1 + slideCount) % slideCount : 0
    }

    // MARK: - Slide maths

    /// Signed distance of a slide from centre, −1…1. Layers multiply this by
    /// their own travel budget, which is what staggers them.
    private func offsetFactor(for index: Int, containerWidth: CGFloat) -> CGFloat {
        guard !reduceMotion else { return index == currentIndex ? 0 : 1 }
        let diff = CGFloat(index - currentIndex)
        let normalizedDrag = containerWidth > 0 ? dragOffset / containerWidth : 0
        return max(-1, min(1, diff + normalizedDrag))
    }

    /// Advancing always kills playback first: `reset` clears `backdropTimerExpired`,
    /// which every mounted slide observes and responds to by tearing its player down
    /// and reverting to static art.
    private func goTo(index: Int) {
        withAnimation(dissolve) {
            currentIndex = index
            dragOffset = 0
        }
        restartTimers()
    }

    private func restartTimers() {
        // Each slide gets the hold budget in full, not what the last one left.
        graceExtensions = 0
        timerManager.reset(defaultDuration: showTrailers ? Self.autoplayDwell : Self.idleRotation)
        restartPush()
    }

    /// Whether the slide on stage is still waiting to hear whether it has a
    /// trailer at all.
    ///
    /// A finished lookup that found nothing is an answer, and the carousel moves
    /// on. Silence is not. On a cold start the dwell clock begins the instant
    /// the carousel appears, at the same moment the lookups do, so the first
    /// slide was routinely being advanced past while its own answer was still in
    /// flight — and by its next turn everything was cached and it played fine,
    /// which is exactly what "you have to wait a whole round" looks like.
    private var shouldWaitForTrailerLookup: Bool {
        guard showTrailers,
              graceExtensions < HeroTrailerTiming.maxLookupExtensions,
              let item = currentItem else { return false }
        // Only ever hold on the way *into* a trailer. Once one has played, the
        // post-trailer pause is the carousel working as intended and must not
        // be extended.
        guard timerManager.trailerPhase == .backdrop else { return false }
        // Nothing is going to start while playback is suppressed — a carousel on
        // a tab that isn't showing shouldn't sit on one slide waiting for it.
        guard !HeroCarouselMuteManager.shared.shouldPause(tabID: tabID) else { return false }
        // No answer yet, or an answer of yes that the player hasn't acted on.
        return !trailerLoader.hasResolvedTrailerLookup(for: item.id)
            || trailerLoader.preferredTrailers[item.id] != nil
    }

    /// The slide that is already on stage goes to the front of the queue.
    ///
    /// All ten lookups used to be launched at once, so the one title with a
    /// clock running against it shared the connection with nine that had all the
    /// time in the world. Its own lookup is awaited first; the rest follow, and
    /// the loader's memo means it isn't fetched twice.
    private func loadTrailersFirstSlideFirst() async {
        guard let first = slides[safe: currentIndex] ?? slides.first else { return }
        await trailerLoader.loadTrailers(for: [first], isPortrait: false)
        await trailerLoader.loadTrailers(for: slides, isPortrait: false)
    }

    /// Resets the push so the new slide starts from an unscaled frame. The flag has to
    /// drop without animation first, otherwise the artwork visibly snaps back.
    private func restartPush() {
        guard !reduceMotion else { return }
        var noAnimation = Transaction()
        noAnimation.disablesAnimations = true
        withTransaction(noAnimation) { pushEngaged = false }
        DispatchQueue.main.async { pushEngaged = true }
    }

    // MARK: - Metrics

    /// True while the active slide is actually showing footage.
    private var trailerActive: Bool {
        showTrailers && timerManager.trailerPhase == .playing
    }

    private func genreNames(for item: MediaItem) -> [String] {
        guard let ids = item.genreIds else { return [] }
        return ids.prefix(2).compactMap { TMDBGenreNames.name(for: $0) }
    }
}

#if os(tvOS)

// MARK: - tvOS Action Button Style

/// Focus treatment for the hero's one control.
///
/// Unfocused it is glass over the artwork, so it sits in the picture rather than
/// on top of it. Focused it fills white and inverts its label — the same
/// vocabulary every other tvOS control uses, which matters more here than
/// anywhere else on the page: it is now the only thing in the frame that *can*
/// hold focus, so the fact that it has focus has to be unmistakable.
private struct TVHeroActionButtonStyle: ButtonStyle {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                if isFocused {
                    Capsule().fill(Color.white)
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        }
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.08 : 1.0))
            .shadow(color: .black.opacity(isFocused ? 0.55 : 0), radius: 20, y: 12)
            .animation(.easeOut(duration: 0.2), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#endif

// MARK: - Stage Metrics

/// Every measurement in the identity and control layers, derived from the stage
/// it is being drawn on rather than fixed in points.
///
/// The old numbers were a single set tuned against a phone, with a second set
/// swapped in for tvOS. That is what left the stage looking like a small card
/// enlarged: on a television a 132pt treatment and a `title3` caption sit in a
/// frame nearly 900pt tall with acres of nothing around them, and every other
/// size in between — iPad, a Mac window — got the phone's numbers regardless of
/// how much frame it actually had. Here the phone stays the baseline and
/// everything grows with the stage.
private struct HeroStageMetrics {
    let contentInset: CGFloat
    let identitySpacing: CGFloat
    let identityHeight: CGFloat
    let identityBottomInset: CGFloat
    let controlsBottomInset: CGFloat
    let logoHeight: CGFloat
    /// Share of the stage width the title treatment may claim.
    let logoWidthFraction: CGFloat
    let titleSize: CGFloat
    let metadataSize: CGFloat
    let synopsisSize: CGFloat
    let synopsisWidthFraction: CGFloat
    let showsSynopsis: Bool
    let buttonSize: CGFloat
    /// A phone-width stage. Everything below the title has to earn its place at
    /// this size, so the compact branch drops the genre list and repositions the
    /// dots rather than shrinking the same four-part caption to fit.
    let isCompact: Bool
    /// The title treatment follows the phone's placement — its share of the
    /// frame, its shrink onto the action button while a trailer plays, and the
    /// metadata stepping out of the way. True on a phone-width stage, and always
    /// on the Mac so the logo sits exactly where it does on iPhone.
    let usesPhoneIdentity: Bool
    /// Whether the metadata line carries the genre list.
    let showsGenres: Bool
    /// Height the title treatment shrinks to while a trailer is on screen.
    /// Matched to the action button's own height so the two read as one row of
    /// chrome over the footage rather than a title competing with it. Only
    /// compact widths shrink; a wide stage has the room to keep the treatment.
    let trailerLogoHeight: CGFloat
    /// The text fallback's size under the same conditions.
    let trailerTitleSize: CGFloat
    /// Share of the stage width the treatment may claim while a trailer plays.
    /// Capping the height alone isn't enough: a wide wordmark stays 190pt across
    /// at 30pt tall and still reads as a full-size title over the footage. This
    /// brings its footprint down to roughly the action button's width.
    let trailerLogoWidthFraction: CGFloat
    /// Distance from the stage's bottom edge to the identity block while a
    /// trailer plays. Sits the treatment just clear of the action button's top
    /// instead of a line-height above it, so it stops floating in the middle of
    /// the footage.
    let trailerIdentityBottomInset: CGFloat

    init(stageWidth: CGFloat) {
        let width = max(stageWidth, 1)
        #if os(tvOS)
        // A television is always laid out in 1920pt, so the scale here only
        // absorbs a stage that has been placed in something narrower.
        let scale = min(1.15, max(0.8, width / 1920))
        contentInset = 90 * scale
        identitySpacing = 20 * scale
        logoHeight = 170 * scale
        logoWidthFraction = 0.46
        titleSize = 78 * scale
        metadataSize = 27 * scale
        synopsisSize = 28 * scale
        synopsisWidthFraction = 0.42
        showsSynopsis = true
        buttonSize = 24 * scale
        isCompact = false
        usesPhoneIdentity = false
        showsGenres = true
        trailerLogoHeight = logoHeight
        trailerTitleSize = titleSize
        trailerLogoWidthFraction = logoWidthFraction
        identityHeight = 400 * scale
        controlsBottomInset = HeroBlend.bottom + 22 * scale
        identityBottomInset = HeroBlend.bottom + 22 * scale + 82 * scale
        trailerIdentityBottomInset = HeroBlend.bottom + 22 * scale + 82 * scale
        #else
        // Square root growth: type scaled linearly against a 1400pt window
        // would be signage. This roughly doubles the phone's sizes by the time
        // the stage is the width of a desk display, and no further.
        let scale = min(2.1, max(1.0, (width / 390).squareRoot()))
        let compact = width < 520
        isCompact = compact
        #if os(macOS)
        let phoneIdentity = true
        #else
        let phoneIdentity = compact
        #endif
        usesPhoneIdentity = phoneIdentity
        contentInset = 20 * scale
        identitySpacing = (phoneIdentity ? 9 : 7) * scale
        // A phone gives the treatment a slightly bigger share of a smaller frame.
        // At 0.40 the title sat in the left corner like a caption; at 0.58 it
        // overpowered the frame. This sits between the two — the treatment leads
        // without becoming the whole picture.
        logoHeight = (phoneIdentity ? 46 : 42) * scale
        logoWidthFraction = phoneIdentity ? 0.48 : 0.40
        titleSize = (phoneIdentity ? 23 : 21) * scale
        metadataSize = (compact ? 11.5 : 11) * scale
        synopsisSize = 13 * scale
        synopsisWidthFraction = 0.44
        // Genres are the longest and least useful part of the caption, and on a
        // phone they're what pushes it to a fourth segment that has to be
        // truncated anyway. Type, year and rating carry the same weight in half
        // the width.
        showsGenres = !compact
        // Only where there is frame to spare: on a phone the stage is a slit
        // and the trailer is already sharing it with the title.
        // The Mac leaves it off too: a logline under the treatment lifts the
        // logo up the frame, away from where it sits on iPhone.
        showsSynopsis = !phoneIdentity && width >= 900
        let button = 11.5 * scale
        buttonSize = button
        // `button` is the label's font size; the glass capsule at
        // `.controlSize(.small)` resolves to roughly 2.6x that in height. Sizing
        // the shrunk treatment off the same number keeps the two matched if the
        // button's type ever changes.
        // Deliberately below the button's own height: sized to match it, the
        // treatment still read as a second title over the footage. A mark that
        // labels the frame wants to be smaller than the control beside it.
        trailerLogoHeight = phoneIdentity ? button * 1.9 : logoHeight
        trailerTitleSize = phoneIdentity ? button * 1.2 : titleSize
        trailerLogoWidthFraction = phoneIdentity ? 0.26 : logoWidthFraction
        // The taller compact treatment needs the block to grow with it, or the
        // fixed height clips the logo off at the top.
        identityHeight = (showsSynopsis ? 150 : (phoneIdentity ? 118 : 112)) * scale
        controlsBottomInset = HeroBlend.bottom + 8 * scale
        identityBottomInset = HeroBlend.bottom + 8 * scale + 43 * scale
        // Clears the button's capsule plus a hairline gap, rather than the 43pt
        // a full-size title block needs. The 2.0 multiplier is measured off the
        // rendered glass capsule at `.controlSize(.small)` — 23pt for an 11.5pt
        // label. An earlier 2.6 estimate overshot and left a visible gap.
        trailerIdentityBottomInset = HeroBlend.bottom + 8 * scale + button * 2.0 + 6 * scale
        #endif
    }
}

// MARK: - Rendered Slide

/// One entry in the virtualised window. Identity combines position and title so a
/// slide is rebuilt when the lineup changes under it, but preserved when only the
/// window shifts.
private struct RenderedSlide: Identifiable {
    let index: Int
    let item: MediaItem
    var id: String { "\(index)-\(item.id)" }
}

// MARK: - Cinematic Slide (Layers 1 + 2)

private struct CinematicHeroSlide: View {
    let item: MediaItem
    let isActive: Bool
    let preferredTrailer: Video?
    let fanartBackdropURL: String?
    let cutoutURL: String?
    let slideSize: CGSize
    /// Signed −1…1 distance from centre, supplied by the carousel.
    let offsetFactor: CGFloat
    let trailerPhase: TrailerPhase
    let backdropTimerExpired: Bool
    let showTrailers: Bool
    let pushEngaged: Bool
    let reduceMotion: Bool
    let tabID: String?
    let onTrailerDurationKnown: (TimeInterval) -> Void
    let onTrailerEnded: () -> Void

    @State private var showTrailer = false
    @StateObject private var playerVM = HeroPlayerViewModel()

    private var slideWidth: CGFloat { slideSize.width }
    private var slideHeight: CGFloat { slideSize.height }

    /// How far off centre this slide is, unsigned.
    private var distance: CGFloat { abs(offsetFactor) }

    private var trailerIsVisible: Bool {
        showTrailers && showTrailer && playerVM.isReady && trailerPhase == .playing
    }

    private var isPostTrailer: Bool {
        showTrailers && trailerPhase == .postTrailer && showTrailer
    }

    var body: some View {
        ZStack {
            Color.black
                .allowsHitTesting(false)

            // ── Layer 1: ambient background ──────────────────────────────────
            // The trailer sits underneath the artwork and is revealed by fading
            // the artwork out, so there is never a black frame between the two.
            ZStack {
                trailerVideo

                backdropImage
                    .opacity(trailerIsVisible ? 0 : 1)
                    .animation(.easeInOut(duration: 0.8), value: trailerIsVisible)
            }
            // Layer 1 travels the least: a 1.05x scale-up and a token drift.
            .scaleEffect(reduceMotion ? 1.0 : 1.0 + 0.05 * distance, anchor: .center)
            .offset(x: reduceMotion ? 0 : offsetFactor * slideWidth * 0.06)
            .blur(radius: reduceMotion ? 0 : 8 * distance)
            .opacity(1.0 - distance)
            .allowsHitTesting(false)

            // ── Layer 2: subject cutout ─────────────────────────────────────
            // Scales and slides faster than Layer 1, which is what makes the
            // subject read as sitting in front of the background rather than on it.
            // Under Reduce Motion the layer stays — only its travel is dropped.
            cutoutLayer
                .scaleEffect(reduceMotion ? 1.0 : 1.0 + 0.16 * distance, anchor: .bottomTrailing)
                .offset(x: reduceMotion ? 0 : offsetFactor * slideWidth * 0.24)
                .opacity(max(0, 1.0 - distance * 1.7) * (trailerIsVisible ? 0 : 1))
                .animation(.easeInOut(duration: 0.6), value: trailerIsVisible)
                .allowsHitTesting(false)

            // Mute control, present only while a trailer is actually on screen.
            #if !os(tvOS)
            if trailerIsVisible {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            playerVM.toggleMute()
                        } label: {
                            Image(systemName: playerVM.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(.black.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        // Clear of the whole top scrim. Besides keeping the control
                        // out of the faded region, this puts it below the navigation
                        // bar when the stage bleeds upward — the toolbar's own
                        // buttons occupy that same trailing corner.
                        .padding(.top, HeroBlend.topScrim + 8)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
            #endif
        }
        .frame(width: slideWidth, height: slideHeight)
        .clipped()
        .onChange(of: backdropTimerExpired) { _, expired in
            guard showTrailers else { return }
            if expired && isActive {
                startTrailerIfNeeded()
            } else if !expired {
                // Navigation reset the timer — kill playback and revert to static art.
                stopTrailer()
            }
        }
        .onChange(of: isActive) { _, active in
            guard showTrailers else { return }
            if active {
                if backdropTimerExpired { startTrailerIfNeeded() }
            } else {
                stopTrailer()
            }
        }
        .onChange(of: preferredTrailer?.id) { _, newID in
            guard showTrailers else { return }
            if newID != nil && isActive && backdropTimerExpired {
                #if !os(tvOS)
                // A direct URL arriving after a YouTube player started wins — restart on it.
                if showTrailer && playerVM.avPlayer == nil {
                    stopTrailer()
                }
                #endif
                startTrailerIfNeeded()
            }
        }
        .onChange(of: trailerPhase) { _, phase in
            guard showTrailers else { return }
            if phase == .postTrailer { playerVM.pausePlayback() }
        }
        .onChange(of: playerVM.didFinishPlaying) { _, finished in
            guard showTrailers, finished, isActive else { return }
            onTrailerEnded()
        }
        .onChange(of: playerVM.isReady) { _, ready in
            guard showTrailers, ready, isActive else { return }
            reportTrailerDuration()
        }
        .onDisappear {
            if showTrailers { stopTrailer() }
        }
    }

    // MARK: Layer 1 content

    /// Size that lays a 16:9 trailer out large enough to *cover* the stage on both
    /// axes, to be clipped back to the stage afterwards.
    ///
    /// Only the YouTube path needs this now. Its iframe letterboxes 16:9 content
    /// inside whatever frame it is handed, which on a 2:1 stage left the trailer
    /// floating in bars and reading much smaller than the artwork it replaced.
    /// `AmbientVideoView` crops in the layer instead, so the AVPlayer path is
    /// handed the stage frame directly.
    private var videoCoverSize: CGSize {
        let videoAspect: CGFloat = 16.0 / 9.0
        guard slideWidth > 0, slideHeight > 0 else { return slideSize }
        let stageAspect = slideWidth / slideHeight
        if stageAspect > videoAspect {
            // Stage is wider than the video — match width and overflow vertically.
            return CGSize(width: slideWidth, height: slideWidth / videoAspect)
        } else {
            return CGSize(width: slideHeight * videoAspect, height: slideHeight)
        }
    }

    @ViewBuilder
    private var trailerVideo: some View {
        #if os(tvOS)
        if showTrailers, showTrailer, let avPlayer = playerVM.avPlayer {
            AmbientVideoView(player: avPlayer)
                .frame(width: slideWidth, height: slideHeight)
                .allowsHitTesting(false)
                .opacity(isPostTrailer ? 0 : 1)
                .animation(.easeInOut(duration: 0.8), value: isPostTrailer)
        }
        #else
        if showTrailers, showTrailer, let avPlayer = playerVM.avPlayer {
            AmbientVideoView(player: avPlayer)
                .frame(width: slideWidth, height: slideHeight)
                .allowsHitTesting(false)
                .opacity(isPostTrailer ? 0 : 1)
                .animation(.easeInOut(duration: 0.8), value: isPostTrailer)
        } else if showTrailers, showTrailer, let player = playerVM.player {
            YouTubePlayerKit.YouTubePlayerView(player)
                .frame(width: videoCoverSize.width, height: videoCoverSize.height)
                .frame(width: slideWidth, height: slideHeight)
                .clipped()
                .allowsHitTesting(false)
                .opacity(isPostTrailer ? 0 : 1)
                .animation(.easeInOut(duration: 0.8), value: isPostTrailer)
        }
        #endif
    }

    /// Prefers textless art: this style draws its own title treatment, so a backdrop
    /// with lettering baked in would collide with the identity layer.
    private var resolvedBackdropURL: URL? {
        if let fanartStr = fanartBackdropURL, let url = URL(string: fanartStr) {
            return url
        }
        return TMDBService.shared.imageURL(path: item.backdropPath, size: .backdrop)
    }

    private var backdropImage: some View {
        AsyncImage(url: resolvedBackdropURL) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay { ProgressView() }
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                if fanartBackdropURL != nil {
                    AsyncImage(url: TMDBService.shared.imageURL(path: item.backdropPath, size: .backdrop)) { fallbackPhase in
                        switch fallbackPhase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            placeholderView
                        }
                    }
                } else {
                    placeholderView
                }
            @unknown default:
                Rectangle().fill(Color.gray.opacity(0.2))
            }
        }
        .frame(width: slideWidth, height: slideHeight)
        // The slow push. Anchored off-centre so the drift reads as a camera move.
        .scaleEffect(pushEngaged && !trailerIsVisible && !reduceMotion ? 1.12 : 1.0, anchor: .init(x: 0.42, y: 0.45))
        .animation(.easeInOut(duration: 16), value: pushEngaged)
        .clipped()
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay {
                Image(systemName: "film")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
            }
    }

    // MARK: Layer 2 content

    /// Alpha-channel subject art, bottom-right so it clears the identity column.
    /// Titles without character art on FanArt.tv simply have no Layer 2 — the
    /// stage degrades to background plus identity rather than faking a cutout.
    @ViewBuilder
    private var cutoutLayer: some View {
        if let cutoutStr = cutoutURL, let url = URL(string: cutoutStr) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .shadow(color: .black.opacity(0.5), radius: 18, x: -6, y: 10)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: slideWidth * 0.55, maxHeight: slideHeight * 0.82)
            .frame(width: slideWidth, height: slideHeight, alignment: .bottomTrailing)
            .allowsHitTesting(false)
        }
    }

    // MARK: Playback

    /// Always reports a length — the trailer is only revealed once one arrives,
    /// so a stream that never reports its own would otherwise play unseen.
    private func reportTrailerDuration() {
        Task { @MainActor in
            let seconds = await playerVM.resolveTrailerDuration()
            // The slide may have been paged away or torn down while waiting.
            guard isActive, showTrailer, playerVM.isReady else { return }
            onTrailerDurationKnown(seconds)
        }
    }

    private func startTrailerIfNeeded() {
        guard showTrailers else { return }
        guard !HeroCarouselMuteManager.shared.shouldPause(tabID: tabID) else { return }
        guard let trailer = preferredTrailer else { return }
        let isDirect = trailer.site.lowercased() == "direct"
        #if os(tvOS)
        // YouTubePlayerKit is unavailable on tvOS — only direct addon URLs can play.
        guard isDirect else { return }
        showTrailer = true
        playerVM.setup(videoKey: trailer.key, tabID: tabID)
        #else
        showTrailer = true
        if isDirect {
            playerVM.setupDirect(urlString: trailer.key, tabID: tabID)
        } else {
            playerVM.setup(videoKey: trailer.key, tabID: tabID)
        }
        #endif
    }

    private func stopTrailer() {
        showTrailer = false
        playerVM.teardown()
    }
}

// MARK: - Cutout Loader

/// Resolves the alpha-channel art used for Layer 2. Kept separate from
/// `HeroTrailerLoader` so the classic carousel, which has no cutout layer, never
/// pays for these lookups.
@MainActor
final class HeroCutoutLoader: ObservableObject {
    /// item.id → FanArt.tv character/clear art URL string.
    @Published var cutoutURLs: [Int: String] = [:]

    /// Titles already looked up, including ones with no art, so a miss isn't retried.
    private var resolved: Set<Int> = []

    func load(for items: [MediaItem]) async {
        let pending = items.prefix(10).filter { !resolved.contains($0.id) }
        guard !pending.isEmpty else { return }
        pending.forEach { resolved.insert($0.id) }

        await withTaskGroup(of: (Int, String?).self) { group in
            for item in pending {
                group.addTask {
                    let url = await FanArtService.shared.getBestCharacterArtURL(
                        tmdbId: item.id,
                        mediaType: item.resolvedMediaType
                    )
                    return (item.id, url?.absoluteString)
                }
            }
            for await (id, url) in group {
                if let url { cutoutURLs[id] = url }
            }
        }
    }
}

// MARK: - Page Dots (Layer 4)

/// Part of the static scaffolding, so it holds a constant width regardless of
/// which slide is active — only the fill inside the active dot moves.
private struct CinematicPageDots: View {
    let totalPages: Int
    let currentPage: Int
    let progress: CGFloat
    /// Slide titles, used as dot tooltips where dots are clickable.
    var titles: [String] = []
    /// When set, each dot jumps to its slide on click.
    var onSelect: ((Int) -> Void)? = nil

    #if os(tvOS)
    private let dotHeight: CGFloat = 8
    private let dotWidth: CGFloat = 8
    private let activeWidth: CGFloat = 34
    private let spacing: CGFloat = 10
    #elseif os(macOS)
    // A pointer target has to be bigger than a glance indicator.
    private let dotHeight: CGFloat = 6
    private let dotWidth: CGFloat = 6
    private let activeWidth: CGFloat = 28
    private let spacing: CGFloat = 4
    #else
    private let dotHeight: CGFloat = 4
    private let dotWidth: CGFloat = 4
    private let activeWidth: CGFloat = 20
    private let spacing: CGFloat = 6
    #endif

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(totalPages, 0), id: \.self) { index in
                if let onSelect {
                    Button { onSelect(index) } label: {
                        dot(for: index)
                            // Pads the hit area well past the drawn dot.
                            .padding(.vertical, 8)
                            .padding(.horizontal, 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .pointerStyle(.link)
                    #endif
                    .help(titles[safe: index] ?? "")
                } else {
                    dot(for: index)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentPage)
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }

    private func dot(for index: Int) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: index == currentPage ? activeWidth : dotWidth, height: dotHeight)

            if index == currentPage {
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(dotHeight, activeWidth * progress), height: dotHeight)
                    .animation(.linear(duration: 0.06), value: progress)
            }
        }
        .frame(width: index == currentPage ? activeWidth : dotWidth, height: dotHeight)
    }
}

#if os(macOS)
// MARK: - Mac Input Monitor

/// Trackpad swipes and arrow keys for the hero, active only while the pointer
/// is over it.
///
/// SwiftUI has no horizontal scroll-wheel gesture, and a two-finger swipe over
/// the hero would otherwise just go to the vertical page scroll and be dropped.
/// A local event monitor sees the swipe first. Each gesture locks to an axis in
/// its first few points of travel: horizontal ones are consumed and turned into
/// a live drag, vertical ones pass straight through so the page still scrolls.
@MainActor
final class MacCarouselInputMonitor: ObservableObject {
    /// Set while the pointer is over the stage.
    var isArmed = false
    /// Finger translation in points; positive is towards the trailing edge.
    var onSwipeChanged: ((CGFloat) -> Void)?
    /// Final translation, plus the last frame's delta as a flick measure.
    var onSwipeEnded: ((CGFloat, CGFloat) -> Void)?
    /// `true` for the next slide.
    var onArrow: ((Bool) -> Void)?

    private var monitor: Any?
    private var axisDecided = false
    private var isTracking = false
    private var swallowMomentum = false
    private var translation: CGFloat = 0
    private var lastDelta: CGFloat = 0
    private var undecidedX: CGFloat = 0
    private var undecidedY: CGFloat = 0

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
            guard let self else { return event }
            // Local monitors always run on the main thread.
            nonisolated(unsafe) let event = event
            let passesThrough = MainActor.assumeIsolated { self.handle(event) != nil }
            return passesThrough ? event : nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isArmed = false
        if isTracking { onSwipeEnded?(0, 0) }
        isTracking = false
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        event.type == .keyDown ? handleKey(event) : handleScroll(event)
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard isArmed,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              !(event.window?.firstResponder is NSText) else { return event }
        switch event.keyCode {
        case 123: onArrow?(false); return nil // ←
        case 124: onArrow?(true); return nil  // →
        default: return event
        }
    }

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        // Mouse wheels have no phases or precise deltas; leave them to the page.
        guard event.hasPreciseScrollingDeltas else { return event }

        // The inertial tail of a swipe we used must not leak into the page.
        if !event.momentumPhase.isEmpty {
            guard swallowMomentum else { return event }
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                swallowMomentum = false
            }
            return nil
        }

        // With natural scrolling the delta already follows the fingers.
        let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX

        if event.phase.contains(.began) {
            swallowMomentum = false
            axisDecided = false
            isTracking = false
            translation = 0
            undecidedX = 0
            undecidedY = 0
            guard isArmed else { return event }
        }

        if event.phase.contains(.changed) {
            if !axisDecided {
                guard isArmed else { return event }
                undecidedX += abs(event.scrollingDeltaX)
                undecidedY += abs(event.scrollingDeltaY)
                guard undecidedX + undecidedY > 6 else { return event }
                axisDecided = true
                isTracking = undecidedX > undecidedY * 1.2
            }
            guard isTracking else { return event }
            translation += dx
            lastDelta = dx
            onSwipeChanged?(translation)
            return nil
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            guard isTracking else { return event }
            isTracking = false
            swallowMomentum = true
            onSwipeEnded?(translation, event.phase.contains(.cancelled) ? 0 : lastDelta)
            return nil
        }

        return isTracking ? nil : event
    }
}
#endif

// MARK: - TMDB Genre Names

/// TMDB's genre ids are stable and documented, so the small subset needed for a
/// one-line genre label is mapped locally rather than costing a request per slide.
enum TMDBGenreNames {
    private static let names: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History",
        27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance", 878: "Sci-Fi",
        10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western",
        10759: "Action & Adventure", 10762: "Kids", 10763: "News", 10764: "Reality",
        10765: "Sci-Fi & Fantasy", 10766: "Soap", 10767: "Talk", 10768: "War & Politics"
    ]

    static func name(for id: Int) -> String? { names[id] }
}

#Preview {
    CinematicHeroCarouselView(items: [], onItemTap: { _ in })
}

#Preview("Action Button") {
    ZStack {
        Color.black
        HStack(alignment: .bottom) {
            Button {} label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("More Details")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.glass)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)

            Spacer(minLength: 12)

            CinematicPageDots(totalPages: 10, currentPage: 2, progress: 0.4)
        }
        .padding(.horizontal, 20)
    }
    .frame(width: 390, height: 120)
    .preferredColorScheme(.dark)
}
