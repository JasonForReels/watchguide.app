//
//  HeroCarouselView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import Combine
import AVKit
import AVFoundation
#if !os(tvOS)
import YouTubePlayerKit
#endif

// MARK: - Ambient Video

/// An `AVPlayer` drawn as nothing but its picture.
///
/// `VideoPlayer` was doing this job, and it brings AVKit's whole playback
/// interface along with it — transport controls, a scrubber, a title bar. On a
/// hero the footage is scenery: there is no timeline to scrub and nothing to
/// pause, and the chrome sitting over the artwork was the one thing in the
/// frame announcing that this is a video element rather than a moving picture.
/// On tvOS it was worse than cosmetic, because those controls are focusable and
/// put a second landing spot for the remote inside a stage that is supposed to
/// have exactly one.
///
/// An `AVPlayerLayer` has no interface of its own whatsoever, which is the whole
/// reason to drop to it. `resizeAspectFill` also does the cropping that callers
/// were doing by hand — laying the video out oversized and clipping it back —
/// so a 16:9 trailer fills a 2.2:1 stage without letterboxing.
struct AmbientVideoView {
    let player: AVPlayer
}

#if canImport(UIKit)

extension AmbientVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> HeroPlayerLayerView {
        let view = HeroPlayerLayerView()
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: HeroPlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

/// Backing view whose own layer *is* the player layer, so the video tracks the
/// view's bounds without any manual layout.
final class HeroPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    // swiftlint:disable:next force_cast
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

#elseif canImport(AppKit)

extension AmbientVideoView: NSViewRepresentable {
    func makeNSView(context: Context) -> HeroPlayerLayerView {
        let view = HeroPlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: HeroPlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

/// AppKit has no `layerClass` hook, so the player layer is hosted as a sublayer
/// and resized in `layout`, with implicit animations off — a CALayer would
/// otherwise animate its own frame changes and the video would visibly slide
/// into place on every resize.
final class HeroPlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

#endif

// MARK: - Hero Carousel Mute Manager
/// Shared manager that allows external views (e.g. detail sheets) to request the hero carousel
/// to pause/mute its trailer audio automatically.
@MainActor
class HeroCarouselMuteManager: ObservableObject {
    static let shared = HeroCarouselMuteManager()
    
    /// When true, all hero carousel players should be paused (e.g. a detail page is open)
    @Published var isExternallyMuted = false

    /// When true, the Browse hero carousel has scrolled off-screen and should pause
    @Published var isScrolledOffScreen = false

    /// When true, an Atlas voice session is live. Trailer audio has to get out of
    /// the way completely: the voice session owns a `.playAndRecord`/`.voiceChat`
    /// audio session, and a trailer coming ready mid-call would reconfigure the
    /// shared session to `.playback` underneath it.
    @Published var isVoiceModeActive = false

    /// The currently visible tab's raw value. Carousels on other tabs should pause.
    @Published var activeTabID: String?

    /// The viewer's mute choice, shared by every hero trailer. Muting one title
    /// mutes them all — the next slide, and every other carousel in the app —
    /// rather than each trailer starting over from the settings default.
    /// Nil until the viewer first presses the mute button.
    @Published private(set) var userMuted: Bool?

    /// Whether a trailer starting now should be muted.
    var resolvedMuted: Bool {
        userMuted ?? StorageService.shared.settings.autoPlayTrailersMuted
    }

    func setUserMuted(_ muted: Bool) {
        userMuted = muted
    }

    /// Every input `shouldPause` depends on, as one signal. Players subscribe to
    /// this rather than to individual flags, so adding a new reason to pause
    /// doesn't mean finding every `combineLatest` in the file again.
    var pauseConditionsPublisher: AnyPublisher<Void, Never> {
        Publishers.CombineLatest3($isExternallyMuted, $isVoiceModeActive, $activeTabID)
            .map { _, _, _ in () }
            .eraseToAnyPublisher()
    }

    /// Returns true if a carousel with the given tabID should be paused
    func shouldPause(tabID: String?) -> Bool {
        if isVoiceModeActive { return true }
        if isExternallyMuted { return true }
        if isScrolledOffScreen { return true }
        // If no tabID is set on the carousel, it's always considered active (e.g. hub views)
        guard let tabID else { return false }
        // If no active tab is known yet, don't pause
        guard let activeTabID else { return false }
        return tabID != activeTabID
    }
}

// MARK: - Trailer Lookup Timing

/// How long a carousel will hold a slide open waiting to hear whether it has a
/// trailer, shared by both hero styles so they behave identically.
enum HeroTrailerTiming {
    /// One turn of the hold.
    static let lookupGrace: TimeInterval = 4.0
    /// Turns allowed before the carousel gives up and moves on regardless. At
    /// four turns that is sixteen seconds past the usual grace — enough for a
    /// cold start on a slow connection, and still bounded, so a dead network
    /// parks the carousel on one slide instead of freezing it there.
    static let maxLookupExtensions = 4
}

#if os(tvOS)
// MARK: - Hero Layout (tvOS)
enum HeroCarouselLayout {
    /// Widest-possible hero shape on tvOS. Anything taller than this fills the
    /// whole screen and pushes the tab bar out of the focus engine's reach.
    static let tvMinimumAspectRatio: CGFloat = 2.2
}

// MARK: - Hero Focus State (tvOS)
/// Tracks whether a hero carousel currently holds focus.
///
/// The hero fills the top of the page as a single focusable region, so once
/// focus lands on it the tab bar collapses out of reach — there is no row above
/// it to move to. While the hero is focused we pin the tab bar visible, which
/// keeps it on screen and gives the focus engine somewhere to go on an up-swipe.
@MainActor
final class TVHeroFocusState: ObservableObject {
    static let shared = TVHeroFocusState()

    @Published var isHeroFocused = false

    private init() {}
}
#endif

struct HeroCarouselView: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    let aspectRatio: CGFloat
    let isPortrait: Bool
    let isEdgeToEdge: Bool
    let externalVisibilityOverride: Bool
    let isImmersiveStyle: Bool
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
    #if os(tvOS)
    @FocusState private var isCarouselFocused: Bool
    #endif
    @StateObject private var trailerLoader = HeroTrailerLoader()
    @StateObject private var timerManager = CarouselTimerManager()
    @Environment(\.colorScheme) private var colorScheme
    
    /// The maximum number of slides rendered in the carousel.
    private let maxSlides = 10

    #if os(tvOS)
    /// The hero has to stay shorter than the screen.
    ///
    /// A full-width 16:9 hero is exactly the height of a 1080p tvOS screen, so
    /// focusing it scrolls the page past its top and leaves the focus engine
    /// with nothing above the carousel — an up-press then has no target and the
    /// tab bar becomes unreachable for the rest of the session. Capping the
    /// aspect keeps a strip of the page above the hero, which is where the tab
    /// bar lives.
    private var tvOSAspectRatio: CGFloat { max(aspectRatio, HeroCarouselLayout.tvMinimumAspectRatio) }
    #endif

    /// The actual number of visible slides (capped at maxSlides).
    private var slideCount: Int { min(items.count, maxSlides) }

    // Transition animation — Apple-style spring
    private let slideSpring: Animation = .interpolatingSpring(
        mass: 1.0, stiffness: 170, damping: 24, initialVelocity: 0
    )
    
    init(
        items: [MediaItem],
        onItemTap: @escaping (MediaItem) -> Void,
        aspectRatio: CGFloat = 16.0 / 9.0,
        isPortrait: Bool = false,
        isEdgeToEdge: Bool = false,
        externalVisibilityOverride: Bool = false,
        isImmersiveStyle: Bool = false,
        tabID: String? = nil
    ) {
        self.items = items
        self.onItemTap = onItemTap
        self.aspectRatio = aspectRatio
        self.isPortrait = isPortrait
        self.isEdgeToEdge = isEdgeToEdge
        self.externalVisibilityOverride = externalVisibilityOverride
        self.isImmersiveStyle = isImmersiveStyle
        self.tabID = tabID
    }

    var body: some View {
        GeometryReader { outerGeo in
            let width = outerGeo.size.width
            let height = outerGeo.size.height
            
            ZStack(alignment: .bottom) {
                // Carousel slides
                ZStack {
                    ForEach(Array(items.prefix(maxSlides).enumerated()), id: \.element.id) { index, item in
                        let offset = slideOffset(for: index, containerWidth: width)
                        let scaleVal = slideScale(for: index, containerWidth: width)
                        let opacityVal = slideOpacity(for: index, containerWidth: width)
                        
                        HeroCarouselSlide(
                            item: item,
                            isActive: index == currentIndex && !isDragging,
                            preferredTrailer: trailerLoader.preferredTrailers[item.id],
                            logoURL: trailerLoader.logoURLs[item.id],
                            fanartBackdropURL: trailerLoader.fanartBackdropURLs[item.id],
                            thumbURL: trailerLoader.thumbURLs[item.id],
                            onTap: { onItemTap(item) },
                            slideSize: CGSize(width: width, height: height),
                            colorScheme: colorScheme,
                            trailerPhase: timerManager.trailerPhase,
                            backdropTimerExpired: timerManager.backdropTimerExpired,
                            showTrailers: showTrailers,
                            isPortrait: isPortrait,
                            tabID: tabID,
                            onTrailerDurationKnown: { duration in
                                if index == currentIndex {
                                    timerManager.beginTrailerPlayback(duration: duration)
                                }
                            },
                            onTrailerEnded: {
                                if index == currentIndex {
                                    timerManager.endTrailerPlayback()
                                }
                            }
                        )
                        .frame(width: width, height: height)
                        .scaleEffect(scaleVal, anchor: .center)
                        .opacity(opacityVal)
                        .offset(x: offset)
                        .zIndex(index == currentIndex ? 1 : 0)
                    }
                }
                #if !os(tvOS)
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { value in
                            // Don't allow swipe during trailer
                            guard !timerManager.isTrailerPlaying else { return }
                            isDragging = true
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            guard !timerManager.isTrailerPlaying else {
                                isDragging = false
                                dragOffset = 0
                                return
                            }
                            isDragging = false
                            let threshold: CGFloat = width * 0.15
                            let velocity = value.predictedEndTranslation.width - value.translation.width
                            
                            if value.translation.width < -threshold || velocity < -150 {
                                // Swipe left → next
                                advanceTo(index: (currentIndex + 1) % slideCount)
                            } else if value.translation.width > threshold || velocity > 150 {
                                // Swipe right → previous
                                advanceTo(index: (currentIndex - 1 + slideCount) % slideCount)
                            } else {
                                // Snap back
                                withAnimation(slideSpring) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                #endif
                
                // Page indicators / progress bar
                CarouselPageIndicator(
                    totalPages: slideCount,
                    currentPage: currentIndex,
                    progress: timerManager.progress,
                    isTrailerPlaying: timerManager.isTrailerPlaying
                )
                #if os(tvOS)
                .padding(.bottom, 40)
                #else
                .padding(.bottom, 16)
                #endif
                
                #if os(tvOS)
                // tvOS: single focusable button for select + swipe gestures for L/R
                tvOSCarouselFocusable(width: width)
                #endif
            }
        }
        #if os(tvOS)
        .aspectRatio(tvOSAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.25),
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        )
        #else
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.25 : 0.5),
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.15),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        )
        #endif
        .onReceive(timerManager.$shouldAdvance) { advance in
            guard advance, slideCount > 1 else { return }
            timerManager.shouldAdvance = false
            if shouldWaitForTrailerLookup {
                graceExtensions += 1
                timerManager.extendTrailerGrace(by: HeroTrailerTiming.lookupGrace)
                return
            }
            advanceTo(index: (currentIndex + 1) % slideCount)
        }
        .onChange(of: items.count) { _, _ in
            if slideCount == 0 { currentIndex = 0 }
            else if currentIndex >= slideCount { currentIndex = 0 }
        }
        .onAppear {
            graceExtensions = 0
            timerManager.reset(defaultDuration: CarouselTimerManager.backdropDuration)
        }
        .task {
            // Run artwork and trailer loading in parallel so trailers can arrive
            // well before the carousel's backdrop timer + grace period expire.
            if showTrailers {
                async let artwork: Void = trailerLoader.loadArtwork(for: items)
                async let trailers: Void = loadTrailersFirstSlideFirst()
                _ = await (artwork, trailers)
            } else {
                await trailerLoader.loadArtwork(for: items)
            }
        }
    }

    /// The slide that is already on screen goes to the front of the queue.
    ///
    /// Every slide's lookup used to be launched at once, so the one title with a
    /// clock running against it shared the connection with nine that had all the
    /// time in the world. Its own lookup is awaited first; the rest follow, and
    /// the loader's memo means it isn't fetched twice.
    private func loadTrailersFirstSlideFirst() async {
        let visible = Array(items.prefix(maxSlides))
        guard let first = visible[safe: currentIndex] ?? visible.first else { return }
        await trailerLoader.loadTrailers(for: [first], isPortrait: isPortrait)
        await trailerLoader.loadTrailers(for: visible, isPortrait: isPortrait)
    }

    /// Whether the slide on screen is still waiting to hear whether it has a
    /// trailer at all. A finished lookup that found nothing is an answer — the
    /// carousel moves on. Silence is not, and the fallback holds for it, up to
    /// `HeroTrailerTiming.maxLookupExtensions` turns.
    private var shouldWaitForTrailerLookup: Bool {
        guard showTrailers,
              graceExtensions < HeroTrailerTiming.maxLookupExtensions,
              let item = Array(items.prefix(maxSlides))[safe: currentIndex] else { return false }
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
    
    // MARK: - Slide Positioning
    
    /// Computes the horizontal offset for a slide based on its position relative to currentIndex
    private func slideOffset(for index: Int, containerWidth: CGFloat) -> CGFloat {
        let diff = CGFloat(index - currentIndex)
        let base = diff * containerWidth
        return base + dragOffset
    }
    
    /// Scale effect: current slide is 1.0, adjacent slides are slightly scaled down
    private func slideScale(for index: Int, containerWidth: CGFloat) -> CGFloat {
        let diff = CGFloat(index - currentIndex)
        let normalizedDrag = containerWidth > 0 ? dragOffset / containerWidth : 0
        let effectiveDiff = abs(diff + normalizedDrag)
        // Current slide: 1.0, neighboring: 0.92, further: smaller
        let scale = 1.0 - min(effectiveDiff * 0.08, 0.2)
        return max(scale, 0.8)
    }
    
    /// Opacity: current slide is 1.0, adjacent are slightly faded
    private func slideOpacity(for index: Int, containerWidth: CGFloat) -> Double {
        let diff = CGFloat(index - currentIndex)
        let normalizedDrag = containerWidth > 0 ? dragOffset / containerWidth : 0
        let effectiveDiff = abs(diff + normalizedDrag)
        let opacity = 1.0 - min(Double(effectiveDiff) * 0.4, 0.8)
        return max(opacity, 0.2)
    }
    
    // MARK: - Navigation
    
    private func advanceTo(index: Int) {
        withAnimation(slideSpring) {
            currentIndex = index
            dragOffset = 0
        }
        // Each slide gets the hold budget in full, not what the last one left.
        graceExtensions = 0
        timerManager.reset(defaultDuration: CarouselTimerManager.backdropDuration)
    }
    
    #if os(tvOS)
    /// Single focusable button for the entire carousel area.
    /// Select opens detail; Siri Remote left/right change slides.
    /// Up/down pass through to the focus system for natural vertical navigation.
    @ViewBuilder
    private func tvOSCarouselFocusable(width: CGFloat) -> some View {
        Button {
            if let item = items[safe: currentIndex] {
                onItemTap(item)
            }
        } label: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(TVOSCarouselButtonStyle())
        .focused($isCarouselFocused)
        .onChange(of: isCarouselFocused) { _, focused in
            TVHeroFocusState.shared.isHeroFocused = focused
        }
        .onDisappear {
            if isCarouselFocused { TVHeroFocusState.shared.isHeroFocused = false }
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard !timerManager.isTrailerPlaying, slideCount > 1 else { return .ignored }
            if press.key == .leftArrow {
                advanceTo(index: (currentIndex - 1 + slideCount) % slideCount)
                return .handled
            } else if press.key == .rightArrow {
                advanceTo(index: (currentIndex + 1) % slideCount)
                return .handled
            }
            return .ignored
        }
    }
    #endif
}

#if os(tvOS)
/// Button style for tvOS carousel — subtle focus highlight on the full carousel area
struct TVOSCarouselButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.25), value: isFocused)
    }
}
#endif

// MARK: - Trailer Phase
/// Describes the lifecycle of a trailer on a hero slide.
enum TrailerPhase: Equatable {
    /// No trailer loaded or slide is in its static backdrop state
    case backdrop
    /// Trailer is actively playing
    case playing
    /// Trailer finished — show backdrop briefly before advancing
    case postTrailer
}

// MARK: - Carousel Timer Manager
/// Manages the auto-scroll timer with dynamic duration based on trailer length
@MainActor
class CarouselTimerManager: ObservableObject {
    @Published var shouldAdvance = false
    /// Current progress 0…1 for the active slide (used for progress bar)
    @Published var progress: CGFloat = 0
    /// Whether a trailer is actively playing (controls dots vs progress bar)
    @Published var isTrailerPlaying = false
    /// Current trailer phase for the active slide
    @Published var trailerPhase: TrailerPhase = .backdrop
    /// Fires when the backdrop timer expires — slide should begin loading its trailer
    @Published var backdropTimerExpired = false
    
    private var timer: Timer?
    private var postTrailerTimer: Timer?
    private var isPaused = false
    private var displayLink: CADisplayLink?
    private var progressTimer: Timer?
    private var startTime: CFTimeInterval = 0
    private var duration: TimeInterval = 15
    
    /// How long to show the backdrop before starting the trailer
    static let backdropDuration: TimeInterval = 5
    /// How long to show the backdrop after a trailer finishes before advancing
    static let postTrailerBackdropDuration: TimeInterval = 6.5
    /// Extra grace period for the progress-bar → dots morph animation
    static let morphGracePeriod: TimeInterval = 1.5
    /// Extra time to allow trailer player to load before auto-advancing
    static let trailerLoadGracePeriod: TimeInterval = 8.0
    /// Ceiling on a reported trailer length — a sanity guard against bad metadata,
    /// not a playback budget. Long featurettes should still run to the end.
    static let maxTrailerDuration: TimeInterval = 600
    /// Headroom added to the backstop timer so buffering can't cut the final
    /// seconds off a trailer that is still playing.
    static let trailerTailGrace: TimeInterval = 4.0
    /// Length assumed for a trailer that never reports one — streamed trailers
    /// often read as indefinite, and YouTube's duration call can fail. The
    /// trailer still has to be revealed, or it plays audibly behind the
    /// backdrop; the player's own end-of-playback signal ends it on time.
    static let unknownTrailerDuration: TimeInterval = 180
    
    func reset(defaultDuration: TimeInterval) {
        timer?.invalidate()
        postTrailerTimer?.invalidate()
        postTrailerTimer = nil
        stopDisplayLink()
        isPaused = false
        shouldAdvance = false
        progress = 0
        isTrailerPlaying = false
        trailerPhase = .backdrop
        backdropTimerExpired = false
        duration = defaultDuration
        startTime = CACurrentMediaTime()
        startBackdropTimer(interval: defaultDuration)
        // Always run display link so the dot progress fills during backdrop too
        startDisplayLink()
    }
    
    /// Called when the trailer player reports its duration and is ready to play.
    /// Restarts the timer/progress for the trailer playback phase.
    ///
    /// The timer is a *backstop*, not the authority on when the trailer ends —
    /// `endTrailerPlayback()` is called when the player actually finishes. It is
    /// therefore given headroom: a wall-clock timer set to the exact media length
    /// will always beat the video, because playback starts a moment after this is
    /// called and any rebuffering puts it further behind.
    func beginTrailerPlayback(duration trailerDuration: TimeInterval) {
        timer?.invalidate()
        stopDisplayLink()
        isPaused = false
        // Upper bound only guards against a bogus duration; it used to be 180s,
        // which silently truncated any trailer longer than three minutes.
        let clamped = min(max(trailerDuration, 10), CarouselTimerManager.maxTrailerDuration)
        self.duration = clamped
        isTrailerPlaying = true
        trailerPhase = .playing
        startTime = CACurrentMediaTime()
        startTrailerTimer(interval: clamped + CarouselTimerManager.trailerTailGrace)
        startDisplayLink()
    }

    /// Called when the player reports the trailer genuinely finished. Ends the
    /// playing phase immediately rather than waiting out the backstop timer.
    func endTrailerPlayback() {
        guard isTrailerPlaying else { return }
        timer?.invalidate()
        finishTrailerPhase()
    }
    
    /// Called when there is no trailer for this slide — the backdrop timer
    /// should simply advance when it expires (already handled by startBackdropTimer).
    func markNoTrailer() {
        // Nothing special needed — the backdrop timer will fire shouldAdvance
    }
    
    private func startBackdropTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Signal that the backdrop period is over — slide should start trailer
                self.backdropTimerExpired = true
                // If no trailer hooks in within a short window, auto-advance
                // (This is a fallback; normally the slide will call beginTrailerPlayback)
                self.timer = Timer.scheduledTimer(withTimeInterval: CarouselTimerManager.trailerLoadGracePeriod, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self = self, !self.isTrailerPlaying else { return }
                        self.shouldAdvance = true
                    }
                }
            }
        }
    }
    
    /// Re-arms the auto-advance fallback without disturbing the dwell state.
    ///
    /// The fallback exists so a slide with no trailer still moves on. It was
    /// also, though, cutting off slides whose trailer lookup simply hadn't come
    /// back yet — which on a cold start is every time for the first slide,
    /// because its clock starts the moment the carousel appears and the
    /// lookup starts at the same instant. The carousel calls this instead of
    /// advancing while it is still waiting on an answer.
    func extendTrailerGrace(by interval: TimeInterval) {
        guard !isTrailerPlaying else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, !self.isTrailerPlaying else { return }
                self.shouldAdvance = true
            }
        }
    }

    private func startTrailerTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.finishTrailerPhase()
            }
        }
    }

    /// Leaves the playing phase: dots return, the backdrop comes back, and the
    /// slide advances after the usual grace. Shared by the backstop timer and the
    /// player's own end-of-playback callback, whichever lands first.
    private func finishTrailerPhase() {
        guard isTrailerPlaying else { return }
        // 1. Transition indicator back to dots
        isTrailerPlaying = false
        stopDisplayLink()
        // 2. Enter post-trailer phase — show backdrop with title
        withAnimation(.easeInOut(duration: 0.6)) {
            trailerPhase = .postTrailer
        }
        // 3. After backdrop display + morph grace, advance.
        // Use a stored Timer (not asyncAfter) so reset() can cancel it if the user
        // swipes to a new slide before this fires.
        let totalWait = CarouselTimerManager.morphGracePeriod + CarouselTimerManager.postTrailerBackdropDuration
        postTrailerTimer = Timer.scheduledTimer(withTimeInterval: totalWait, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.shouldAdvance = true }
        }
    }
    
    // MARK: - Display Link for smooth progress
    private func startDisplayLink() {
        stopDisplayLink()
        startTime = CACurrentMediaTime()
        #if os(macOS)
        // CADisplayLink target/selector initializer is unavailable on macOS.
        displayLink = nil
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
        #else
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in
            self?.updateProgress()
        }, selector: #selector(DisplayLinkTarget.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        #endif
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func updateProgress() {
        guard !isPaused else { return }
        let elapsed = CACurrentMediaTime() - startTime
        let newProgress = min(CGFloat(elapsed / duration), 1.0)
        progress = newProgress
        if newProgress >= 1.0 {
            stopDisplayLink()
        }
    }
    
    deinit {
        timer?.invalidate()
        postTrailerTimer?.invalidate()
        displayLink?.invalidate()
        progressTimer?.invalidate()
    }
}

/// Helper target for CADisplayLink (avoids retain cycles)
private class DisplayLinkTarget {
    let callback: () -> Void
    init(_ callback: @escaping () -> Void) { self.callback = callback }
    @objc func tick() { callback() }
}

// MARK: - Trailer Loader
@MainActor
class HeroTrailerLoader: ObservableObject {
    /// item.id → best Video to play (Direct addon URL preferred over YouTube)
    @Published var preferredTrailers: [Int: Video] = [:]
    /// item.id → full logo URL string (FanArt.tv primary, TMDB fallback path prefixed with scheme)
    @Published var logoURLs: [Int: String] = [:]
    /// item.id → full backdrop URL string from FanArt.tv (nil = use TMDB backdrop)
    @Published var fanartBackdropURLs: [Int: String] = [:]
    /// item.id → FanArt.tv thumb URL (landscape image with title text overlay)
    @Published var thumbURLs: [Int: String] = [:]
    /// Ids whose trailer lookup has come back, whether or not it found anything.
    ///
    /// A carousel needs to tell "no trailer for this title" apart from "haven't
    /// heard yet" — the first means move on, the second means wait. The absence
    /// of an entry in `preferredTrailers` says both, so completion is recorded
    /// separately. It doubles as the memo that stops a repeat call re-running
    /// lookups that are already answered.
    @Published private(set) var resolvedTrailerLookups: Set<Int> = []

    /// True once this title's trailer lookup has finished, found or not.
    func hasResolvedTrailerLookup(for id: Int) -> Bool {
        resolvedTrailerLookups.contains(id)
    }

    func loadTrailers(for items: [MediaItem], isPortrait: Bool) async {
        let addons = StorageService.shared.settings.trailerAddons
        let pending = items.prefix(10).filter { !resolvedTrailerLookups.contains($0.id) }
        guard !pending.isEmpty else { return }
        // Trailers-only: artwork is loaded separately by loadArtwork() which runs in parallel.
        await withTaskGroup(of: (Int, Video?).self) { group in
            for item in pending {
                group.addTask {
                    var allVideos: [Video] = []

                    // On tvOS, YouTubePlayerKit is unavailable so TMDB YouTube trailers can't play.
                    // Skip that fetch and go straight to Trailerio so we waste no bandwidth.
                    // On iOS/macOS, fetch TMDB videos and the IMDB ID (for Trailerio) in parallel.
                    #if os(tvOS)
                    let imdbID = await HeroTrailerLoader.fetchIMDBID(for: item)
                    if let imdbID, !imdbID.isEmpty, !addons.isEmpty {
                        let addonVideos = await TrailerAddonService.shared.fetchTrailers(
                            imdbID: imdbID,
                            mediaType: item.resolvedMediaType,
                            addons: addons
                        )
                        allVideos.append(contentsOf: addonVideos)
                    }
                    #else
                    async let youtubeVideos = HeroTrailerLoader.fetchYouTubeVideos(for: item)
                    async let imdbIDResult = HeroTrailerLoader.fetchIMDBID(for: item)

                    allVideos.append(contentsOf: await youtubeVideos)

                    if let imdbID = await imdbIDResult, !imdbID.isEmpty, !addons.isEmpty {
                        let addonVideos = await TrailerAddonService.shared.fetchTrailers(
                            imdbID: imdbID,
                            mediaType: item.resolvedMediaType,
                            addons: addons
                        )
                        allVideos.append(contentsOf: addonVideos)
                    }
                    #endif

                    let preferred = HeroTrailerLoader.pickPreferredTrailer(from: allVideos, preferPortrait: isPortrait)
                    return (item.id, preferred)
                }
            }
            for await (id, preferred) in group {
                if let preferred {
                    preferredTrailers[id] = preferred
                }
                resolvedTrailerLookups.insert(id)
            }
        }
    }
    
    /// Loads artwork (logos, backdrops, thumbs) for hero items — always called regardless of trailer setting.
    func loadArtwork(for items: [MediaItem]) async {
        await withTaskGroup(of: (Int, String?, String?, String?).self) { group in
            for item in items.prefix(10) {
                group.addTask {
                    var logoURL: String?
                    var backdropURL: String?
                    var thumbURL: String?
                    
                    // Fetch logo — FanArt.tv first, TMDB fallback
                    if let fanartLogo = await FanArtService.shared.getBestLogoURL(tmdbId: item.id, mediaType: item.resolvedMediaType) {
                        logoURL = fanartLogo.absoluteString
                    } else {
                        do {
                            let logos = try await TMDBService.shared.getMediaLogos(
                                mediaType: item.resolvedMediaType,
                                id: item.id
                            )
                            let englishLogos = logos.filter { ($0.iso639_1 == "en" || $0.iso639_1 == nil) }
                            let best = englishLogos.sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }.first
                                ?? logos.first
                            if let filePath = best?.filePath,
                               let tmdbURL = TMDBService.shared.imageURL(path: filePath, size: .logo) {
                                logoURL = tmdbURL.absoluteString
                            }
                        } catch {}
                    }
                    
                    // Fetch backdrop — FanArt.tv (if available)
                    if let fanartBG = await FanArtService.shared.getBestBackdropURL(tmdbId: item.id, mediaType: item.resolvedMediaType) {
                        backdropURL = fanartBG.absoluteString
                    }
                    
                    // Fetch thumb (text backdrop) — FanArt.tv
                    if let fanartThumb = await FanArtService.shared.getBestThumbURL(tmdbId: item.id, mediaType: item.resolvedMediaType) {
                        thumbURL = fanartThumb.absoluteString
                    }

                    // No FanArt thumb — fall back to a TMDB backdrop that has the
                    // title lettering baked in. TMDB tags those with a language
                    // code (textless art is tagged null), and `getMediaBackdrops`
                    // already sorts English-language art first, so the first entry
                    // tagged "en" is the text version.
                    if thumbURL == nil {
                        do {
                            let backdrops = try await TMDBService.shared.getMediaBackdrops(
                                mediaType: item.resolvedMediaType,
                                id: item.id
                            )
                            if let textBackdrop = backdrops.first(where: { $0.iso639_1 == "en" }),
                               let url = TMDBService.shared.imageURL(path: textBackdrop.filePath, size: .backdrop) {
                                thumbURL = url.absoluteString
                            }
                        } catch {}
                    }

                    return (item.id, logoURL, backdropURL, thumbURL)
                }
            }
            for await (id, logo, backdrop, thumb) in group {
                if let logo = logo {
                    logoURLs[id] = logo
                }
                if let backdrop = backdrop {
                    fanartBackdropURLs[id] = backdrop
                }
                if let thumb = thumb {
                    thumbURLs[id] = thumb
                }
            }
        }
    }
    
    nonisolated static func fetchYouTubeVideos(for item: MediaItem) async -> [Video] {
        do {
            if item.resolvedMediaType == .movie {
                return try await TMDBService.shared.getMovieVideos(id: item.id).results
            } else {
                return try await TMDBService.shared.getTVShowVideos(id: item.id).results
            }
        } catch { return [] }
    }

    nonisolated static func fetchIMDBID(for item: MediaItem) async -> String? {
        do {
            if item.resolvedMediaType == .movie {
                return try await TMDBService.shared.getMovieDetails(id: item.id).imdbId
            } else {
                return try await TMDBService.shared.getTVShowDetails(id: item.id).externalIds?.imdbId
            }
        } catch { return nil }
    }

    /// Picks the best trailer Video from a merged list of TMDB + addon videos.
    /// Mirrors computePreferredTrailer in MediaDetailView:
    ///   1. Direct addon trailer (Trailerio etc.) — VPN-safe, works on all platforms
    ///   2. Any other direct addon video
    ///   3. Best YouTube trailer/teaser using official/non-final priority
    /// In portrait mode, vertical YouTube trailers are preferred over landscape ones.
    nonisolated static func pickPreferredTrailer(from videos: [Video], preferPortrait: Bool) -> Video? {
        // Priority 0: Direct addon trailers (works on all platforms including tvOS)
        let directTrailers = videos.filter { $0.site.lowercased() == "direct" && $0.type.lowercased() == "trailer" }
        if let pick = directTrailers.first { return pick }
        let anyDirect = videos.first { $0.site.lowercased() == "direct" }
        if let pick = anyDirect { return pick }

        // Priority 1+: YouTube — same priority logic as MediaDetailView
        let yt = videos.filter { $0.site.lowercased() == "youtube" }
        guard !yt.isEmpty else { return nil }

        if preferPortrait {
            let verticalKeywords = ["9:16", "9x16", "vertical", "portrait", "shorts", "reel", "tiktok", "instagram"]
            let verticalTrailers = yt.filter { v in
                let name = v.name.lowercased()
                let type = v.type.lowercased()
                return verticalKeywords.contains { name.contains($0) } && (type == "trailer" || type == "teaser")
            }
            if let pick = verticalTrailers.first { return pick }
        }

        let filtered = yt.filter { v in
            let name = v.name.lowercased()
            let type = v.type.lowercased()
            let isTrailerOrTeaser = type == "trailer" || type == "teaser"
            let isFinal = name.contains("final trailer") || name.contains("final teaser") || name.contains("final")
            return isTrailerOrTeaser && !isFinal
        }

        if let pick = filtered.first(where: { $0.type.lowercased() == "trailer" && $0.official == true }) { return pick }
        if let pick = filtered.first(where: { $0.type.lowercased() == "teaser" && $0.official == true }) { return pick }
        if let pick = filtered.first(where: { $0.type.lowercased() == "trailer" }) { return pick }
        if let pick = filtered.first(where: { $0.type.lowercased() == "teaser" }) { return pick }

        // Last resort: any YouTube video
        return yt.first
    }
}

// MARK: - Hero Carousel Slide
struct HeroCarouselSlide: View {
    let item: MediaItem
    let isActive: Bool
    /// Best trailer to play — Direct addon URL preferred over YouTube (same logic as MediaDetailView)
    let preferredTrailer: Video?
    /// Full URL string for the logo (FanArt.tv or TMDB)
    let logoURL: String?
    /// Full URL string for the FanArt.tv backdrop (nil = use TMDB)
    let fanartBackdropURL: String?
    /// Full URL string for the FanArt.tv thumb (landscape image with title text)
    let thumbURL: String?
    let onTap: () -> Void
    let slideSize: CGSize
    let colorScheme: ColorScheme
    let trailerPhase: TrailerPhase
    /// Whether the carousel timer's backdrop period has expired (time to start trailer)
    let backdropTimerExpired: Bool
    let showTrailers: Bool
    /// Whether the carousel is in portrait (poster) orientation
    var isPortrait: Bool = false
    /// Identifies which tab this carousel belongs to (nil = always active)
    var tabID: String?
    var onTrailerDurationKnown: ((TimeInterval) -> Void)?
    /// Fired when the player reports the trailer genuinely finished, so the
    /// carousel can leave the playing phase without waiting out its backstop timer.
    var onTrailerEnded: (() -> Void)?

    @State private var showTrailer = false
    @StateObject private var playerVM = HeroPlayerViewModel()
    
    private var slideWidth: CGFloat { slideSize.width }
    private var slideHeight: CGFloat { slideSize.height }
    
    /// True when the YouTube player is loaded and ready — backdrop should hide
    private var trailerIsVisible: Bool {
        showTrailers && showTrailer && playerVM.isReady && trailerPhase == .playing
    }
    
    /// True when we're in the post-trailer backdrop reveal
    private var isPostTrailer: Bool {
        showTrailers && trailerPhase == .postTrailer && showTrailer
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Layer 0: Black base so there's no flash when backdrop fades
            Color.black
            
            // Layer 1: Trailer video (rendered first / bottom of stack)
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
                    .frame(width: slideWidth, height: slideHeight)
                    .allowsHitTesting(false)
                    .opacity(isPostTrailer ? 0 : 1)
                    .animation(.easeInOut(duration: 0.8), value: isPostTrailer)
            }
            #endif
            
            // Layer 2: Backdrop image — fades out for trailer, fades back for post-trailer
            backdropImage
                .opacity(trailerIsVisible ? 0 : 1)
                .animation(.easeInOut(duration: 0.6), value: trailerIsVisible)
                .allowsHitTesting(false)
                .overlay(alignment: .topTrailing) {
                    #if os(tvOS)
                    StreamingLogoBadge(mediaId: item.id, mediaType: item.resolvedMediaType)
                        .scaleEffect(1.5)
                        .padding(32)
                    #else
                    StreamingLogoBadge(mediaId: item.id, mediaType: item.resolvedMediaType, scale: 3.5, studioScale: 1.8)
                        .padding(16)
                    #endif
                }
            
            // Layer 3: Bottom vignette / scrim for text legibility
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.25), location: 0.25),
                        .init(color: .black.opacity(0.6), location: 0.55),
                        .init(color: .black.opacity(0.85), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: slideHeight * 0.45)
            }
            .allowsHitTesting(false)
            
            // Layer 4: Content overlay — logo/title, meta (shown when NOT playing trailer)
            if !trailerIsVisible {
                VStack(alignment: .leading, spacing: tvOSScaled(8, tv: 16)) {
                    Spacer()
                    
                    // The backdrop is chosen to carry its own title lettering, so
                    // nothing is drawn over it. Only when no text backdrop could be
                    // found does the plain title appear — never the separate logo
                    // artwork, which reads as an oversized sticker on the image.
                    if !isThumbBackdrop {
                        backdropTitleText
                    }
                    
                    HStack(spacing: tvOSScaled(12, tv: 20)) {
                        if let year = item.year {
                            Text(year)
                                .foregroundColor(.white.opacity(0.85))
                        }
                        if let rating = item.voteAverage, rating > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    #if os(tvOS)
                    .font(.title3)
                    #else
                    .font(.subheadline)
                    #endif
                }
                .padding(.horizontal, tvOSScaled(20, tv: 80))
                .padding(.bottom, tvOSScaled(32, tv: 100))
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.animation(.easeInOut(duration: 0.5)))
            }
            
            // Layer 5: Trailer-playing overlay — mute button + logo + TRAILER badge
            if showTrailers && trailerIsVisible {
                #if os(tvOS)
                // tvOS: bottom-left logo + TRAILER badge (no mute button — controlled by remote)
                VStack(alignment: .leading, spacing: 8) {
                    Spacer()
                    HStack(spacing: 14) {
                        if let logoURLStr = logoURL,
                           let resolvedLogoURL = URL(string: logoURLStr) {
                            AsyncImage(url: resolvedLogoURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 56)
                                        .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
                                default:
                                    titleTextFallback
                                }
                            }
                        } else {
                            titleTextFallback
                        }
                        
                        Text("TRAILER")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.5)))
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
                #else
                // Mute button (top-right)
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
                        .padding(.top, 52)
                        .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .transition(.opacity)

                // Bottom-left: logo + TRAILER badge
                VStack(alignment: .leading, spacing: 6) {
                    Spacer()
                    HStack(spacing: 10) {
                        // Show logo image if available, otherwise fall back to text
                        if let logoURLStr = logoURL,
                           let resolvedLogoURL = URL(string: logoURLStr) {
                            AsyncImage(url: resolvedLogoURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 32)
                                        .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                                default:
                                    // While loading or on failure, show text fallback
                                    titleTextFallback
                                }
                            }
                        } else {
                            titleTextFallback
                        }
                        
                        Text("TRAILER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background {
                                Capsule()
                                    .fill(.clear)
                                    .glassEffect(.regular, in: .capsule)
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
                #endif
            }
        }
        .frame(width: slideWidth, height: slideHeight)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        // When backdrop timer expires, start loading the trailer
        .onChange(of: backdropTimerExpired) { _, expired in
            guard showTrailers else { return }
            if expired && isActive {
                startTrailerIfNeeded()
            } else if !expired {
                stopTrailer()
            }
        }
        .onChange(of: isActive) { _, active in
            guard showTrailers else { return }
            if active {
                // If the backdrop timer has already expired by the time this slide becomes active,
                // ensure we start the trailer now.
                if backdropTimerExpired {
                    startTrailerIfNeeded()
                }
            } else {
                stopTrailer()
            }
        }
        // When the preferred trailer arrives (possibly after the backdrop timer already fired), start it.
        .onChange(of: preferredTrailer?.id) { _, newID in
            guard showTrailers else { return }
            if newID != nil && isActive && backdropTimerExpired {
                #if !os(tvOS)
                // If a YouTube player is already running but a direct URL just arrived, restart.
                if showTrailer && playerVM.avPlayer == nil {
                    stopTrailer()
                }
                #endif
                startTrailerIfNeeded()
            }
        }
        .onChange(of: trailerPhase) { _, phase in
            guard showTrailers else { return }
            if phase == .postTrailer {
                playerVM.pausePlayback()
            }
        }
        .onChange(of: playerVM.didFinishPlaying) { _, finished in
            guard showTrailers, finished, isActive else { return }
            onTrailerEnded?()
        }
        .onChange(of: playerVM.isReady) { _, ready in
            guard showTrailers, ready, isActive else { return }
            // Always reports a length — the trailer is only revealed once one
            // arrives, so a stream that never reports its own would otherwise
            // play unseen behind the backdrop.
            Task { @MainActor in
                let seconds = await playerVM.resolveTrailerDuration()
                guard isActive, showTrailer, playerVM.isReady else { return }
                onTrailerDurationKnown?(seconds)
            }
        }
        .onDisappear {
            if showTrailers {
                stopTrailer()
            }
        }
    }
    
    /// Fallback: show logo if available, otherwise text title
    @ViewBuilder
    /// Large text fallback for backdrop view when logo isn't available
    private var backdropTitleText: some View {
        Text(item.displayTitle)
            #if os(tvOS)
            .font(.system(size: 52, weight: .bold))
            #else
            .font(.title)
            #endif
            .fontWeight(.bold)
            .foregroundColor(.white)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
    }
    
    /// Returns the tvOS value on tvOS, otherwise the default value
    private func tvOSScaled<T: BinaryFloatingPoint>(_ defaultValue: T, tv tvValue: T) -> T {
        #if os(tvOS)
        return tvValue
        #else
        return defaultValue
        #endif
    }
    
    /// Small text fallback for trailer overlay when logo isn't available
    private var titleTextFallback: some View {
        Text(item.displayTitle)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .lineLimit(1)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
    }
    
    /// Whether the resolved backdrop already carries the title lettering — either a
    /// FanArt.tv thumb or a TMDB language-tagged backdrop. When true, no title is
    /// drawn on top of the image.
    private var isThumbBackdrop: Bool {
        if isPortrait { return false }
        return thumbURL != nil
    }
    
    /// Resolved image URL: In portrait mode, use poster; in landscape, prefer thumb (text backdrop) → fanart backdrop → TMDB fallback
    private var resolvedBackdropURL: URL? {
        if isPortrait {
            // Portrait mode: use poster image (w500) for better visual fit
            return TMDBService.shared.imageURL(path: item.posterPath, size: .large)
        }
        // Prefer FanArt.tv thumb (text backdrop) — has title text baked into the image
        if let thumbStr = thumbURL, let url = URL(string: thumbStr) {
            return url
        }
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
                // Fallback: in portrait mode try backdrop, in landscape try TMDB backdrop if FanArt failed
                if isPortrait {
                    // Portrait poster failed — try backdrop as fallback
                    AsyncImage(url: TMDBService.shared.imageURL(path: item.backdropPath, size: .backdrop)) { fallbackPhase in
                        switch fallbackPhase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            placeholderView
                        }
                    }
                } else if fanartBackdropURL != nil {
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
    
    private func startTrailerIfNeeded() {
        guard showTrailers else { return }
        guard !HeroCarouselMuteManager.shared.shouldPause(tabID: tabID) else { return }
        guard let trailer = preferredTrailer else { return }
        let isDirect = trailer.site.lowercased() == "direct"
        #if os(tvOS)
        // YouTubePlayerKit is unavailable on tvOS — only play direct addon URLs.
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

// MARK: - Hero Player ViewModel
#if !os(tvOS)
class HeroPlayerViewModel: ObservableObject {
    @Published var player: YouTubePlayer?
    /// Set when a Trailerio/addon direct URL is used instead of YouTube
    @Published var avPlayer: AVPlayer?
    @Published var isReady = false
    @Published var isMuted = true
    /// Flips true when the trailer actually reaches its end. The carousel listens
    /// for this rather than relying solely on a wall-clock timer, which drifts
    /// ahead of playback whenever the video buffers.
    @Published var didFinishPlaying = false

    private var endObserver: NSObjectProtocol?
    private var playbackStateCancellable: AnyCancellable?
    private var stateCancellable: AnyCancellable?
    private var pauseCancellable: AnyCancellable?
    private var sharedMuteCancellable: AnyCancellable?
    /// Owns the direct-URL player: buffering, stall recovery and ordered teardown.
    private var directSession: TrailerPlaybackSession?
    /// Tracks the user's chosen mute state before external muting was applied
    private var userMutePreference: Bool = true
    /// Whether the player was actively playing before being externally paused
    private var wasPlayingBeforePause = false
    /// The tab this player belongs to (nil = always active)
    private var tabID: String?
    
    @MainActor
    func setup(videoKey: String, tabID: String? = nil) {
        guard player == nil else { return }
        self.tabID = tabID

        let startMuted = HeroCarouselMuteManager.shared.resolvedMuted
        isMuted = startMuted
        userMutePreference = startMuted
        observeSharedMute()

        let ytPlayer = YouTubePlayer(
            source: .video(id: videoKey),
            parameters: .init(
                autoPlay: true,
                loopEnabled: false,
                showControls: false,
                showFullscreenButton: false,
                keyboardControlsDisabled: true,
                // Equivalent to rel=0 behavior in modern YouTube embeds.
                restrictRelatedVideosToSameChannel: true
            ),
            configuration: .init(
                allowsInlineMediaPlayback: true,
                openURLAction: .init { _, _ in
                    // Block all navigation to prevent Safari from opening
                }
            )
        )
        
        player = ytPlayer
        let mgr = HeroCarouselMuteManager.shared

        // `statePublisher` reports load state (ready/error); playback completion
        // comes from the separate playback-state stream.
        playbackStateCancellable = ytPlayer.playbackStatePublisher.sink { [weak self] playbackState in
            guard playbackState == .ended else { return }
            DispatchQueue.main.async { self?.didFinishPlaying = true }
        }

        stateCancellable = ytPlayer.statePublisher.sink { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isReady = true
                    Task {
                        let shouldPause = mgr.shouldPause(tabID: self.tabID)
                        let shouldMute = self.isMuted || shouldPause
                        if shouldMute {
                            try? await ytPlayer.mute()
                        } else {
                            try? await ytPlayer.unmute()
                        }
                        // Only start playback if this tab is active
                        if !shouldPause {
                            try? await ytPlayer.play()
                        }
                    }
                default:
                    break
                }
            }
        }
        
        // Observe both isExternallyMuted and activeTabID to pause/resume
        pauseCancellable = mgr.pauseConditionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self, let p = self.player, self.isReady else { return }
                let shouldPause = mgr.shouldPause(tabID: self.tabID)
                if shouldPause {
                    self.userMutePreference = self.isMuted
                    self.isMuted = true
                    self.wasPlayingBeforePause = true
                    Task {
                        try? await p.pause()
                        try? await p.mute()
                    }
                } else if self.wasPlayingBeforePause {
                    self.wasPlayingBeforePause = false
                    self.isMuted = self.userMutePreference
                    Task {
                        if self.userMutePreference {
                            try? await p.mute()
                        } else {
                            try? await p.unmute()
                        }
                        try? await p.play()
                    }
                }
            }
    }
    
    /// Sets up AVPlayer for a direct-play URL (Trailerio / addon). Preferred over YouTube when available.
    @MainActor
    func setupDirect(urlString: String, tabID: String? = nil) {
        guard avPlayer == nil, player == nil else { return }
        guard let url = URL(string: urlString) else { return }
        self.tabID = tabID

        let startMuted = HeroCarouselMuteManager.shared.resolvedMuted
        isMuted = startMuted
        userMutePreference = startMuted
        observeSharedMute()

        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let session = TrailerPlaybackSession(url: url, muted: startMuted)
        directSession = session
        let av = session.player
        avPlayer = av
        observePlaybackEnd(of: av)

        let mgr = HeroCarouselMuteManager.shared

        // Playback waits for a buffer that can actually play through, not just for
        // the item to report `.readyToPlay`.
        session.onReadyToPlay = { [weak self] in
            guard let self else { return }
            self.isReady = true
            if !mgr.shouldPause(tabID: self.tabID) {
                session.play()
            }
        }

        // An unplayable or repeatedly stalling URL is treated like a finished trailer
        // so the carousel moves on instead of holding a black slide.
        session.onFailure = { [weak self] in
            self?.didFinishPlaying = true
        }

        pauseCancellable = mgr.pauseConditionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, let p = self.avPlayer else { return }
                let shouldPause = mgr.shouldPause(tabID: self.tabID)
                if shouldPause {
                    if p.rate > 0 { self.wasPlayingBeforePause = true }
                    session.pause()
                } else if self.wasPlayingBeforePause && self.isReady {
                    self.wasPlayingBeforePause = false
                    self.isMuted = self.userMutePreference
                    p.isMuted = self.isMuted
                    session.play()
                }
            }
    }

    /// Posts `didFinishPlaying` when the item reaches its natural end.
    private func observePlaybackEnd(of player: AVPlayer) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.didFinishPlaying = true
        }
    }

    /// Pauses without tearing down — used for the post-trailer backdrop reveal. Goes
    /// through the session so it also cancels any in-flight stall recovery, which
    /// would otherwise resume playback behind the fade.
    @MainActor
    func pausePlayback() {
        directSession?.pause()
        if let p = player {
            Task { try? await p.pause() }
        }
    }

    /// The trailer's length, for the carousel's playing phase. Always returns
    /// a value: the carousel only reveals the trailer once it has one, so a
    /// length that can't be read must not leave it hidden behind the backdrop.
    @MainActor
    func resolveTrailerDuration() async -> TimeInterval {
        for attempt in 0..<4 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            if let av = avPlayer, let seconds = await Self.knownDuration(of: av) {
                return seconds
            }
            if avPlayer == nil, let p = player,
               let duration = try? await p.getDuration() {
                let seconds = duration.converted(to: .seconds).value
                if seconds > 0 { return seconds }
            }
            if avPlayer == nil && player == nil { break }
        }
        return CarouselTimerManager.unknownTrailerDuration
    }

    /// The item's own duration fills in once playback starts, including for
    /// streams whose asset reports indefinite; the asset is the fallback.
    @MainActor
    static func knownDuration(of player: AVPlayer) async -> TimeInterval? {
        guard let item = player.currentItem else { return nil }
        if item.duration.isNumeric {
            let seconds = CMTimeGetSeconds(item.duration)
            if seconds > 0 { return seconds }
        }
        if let duration = try? await item.asset.load(.duration), duration.isNumeric {
            let seconds = CMTimeGetSeconds(duration)
            if seconds > 0 { return seconds }
        }
        return nil
    }

    @MainActor
    func teardown() {
        // Close the direct session before dropping the reference: it detaches the item
        // while the player is still alive, so CoreMedia isn't left reporting a stall
        // against a session it has already discarded.
        directSession?.invalidate()
        directSession = nil
        avPlayer = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        playbackStateCancellable = nil
        didFinishPlaying = false
        if let p = player {
            Task { try? await p.pause() }
        }
        player = nil
        isReady = false
        stateCancellable = nil
        pauseCancellable = nil
        sharedMuteCancellable = nil
        wasPlayingBeforePause = false
    }

    /// Publishes the new state to every hero player; this one picks it up
    /// through `observeSharedMute` like the rest.
    @MainActor
    func toggleMute() {
        HeroCarouselMuteManager.shared.setUserMuted(!isMuted)
    }

    /// Follows the shared mute choice, so pressing mute on any hero trailer
    /// applies to this one too.
    @MainActor
    private func observeSharedMute() {
        sharedMuteCancellable = HeroCarouselMuteManager.shared.$userMuted
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                self?.applyUserMute(muted)
            }
    }

    private func applyUserMute(_ muted: Bool) {
        userMutePreference = muted
        // While externally paused the player stays silenced; the preference
        // is restored when it resumes.
        guard !wasPlayingBeforePause, isMuted != muted else { return }
        isMuted = muted
        if let av = avPlayer {
            av.isMuted = muted
            return
        }
        guard let p = player else { return }
        Task {
            if muted {
                try? await p.mute()
            } else {
                try? await p.unmute()
            }
        }
    }
}
#else
class HeroPlayerViewModel: ObservableObject {
    @Published var avPlayer: AVPlayer?
    @Published var isReady = false
    @Published var isMuted = true
    /// Flips true when the trailer actually reaches its end — see the non-tvOS
    /// view model for why the wall-clock timer alone isn't trusted.
    @Published var didFinishPlaying = false

    private var endObserver: NSObjectProtocol?
    /// Owns the player: buffering, stall recovery and ordered teardown.
    private var directSession: TrailerPlaybackSession?
    private var pauseCancellable: AnyCancellable?
    /// Whether the player was playing before being externally paused
    private var wasPlayingBeforeExternalPause = false
    /// The tab this player belongs to (nil = always active)
    private var tabID: String?
    
    @MainActor
    func setup(videoKey: String, tabID: String? = nil) {
        guard avPlayer == nil else { return }
        guard let url = URL(string: videoKey) else { return }
        self.tabID = tabID

        let startMuted = HeroCarouselMuteManager.shared.resolvedMuted
        isMuted = startMuted

        // Configure audio session for media playback
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        
        let session = TrailerPlaybackSession(url: url, muted: startMuted)
        directSession = session
        let player = session.player
        avPlayer = player

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.didFinishPlaying = true
        }

        let mgr = HeroCarouselMuteManager.shared

        // Start on a buffer that can play through, not merely on `.readyToPlay`.
        session.onReadyToPlay = { [weak self] in
            guard let self else { return }
            self.isReady = true
            // Only start playing if not paused by tab switch or detail page
            if !mgr.shouldPause(tabID: self.tabID) {
                session.play()
            }
        }

        // An unplayable or repeatedly stalling URL is treated like a finished trailer
        // so the carousel moves on instead of holding a black slide.
        session.onFailure = { [weak self] in
            self?.didFinishPlaying = true
        }

        // Observe both isExternallyMuted and activeTabID to pause/resume
        pauseCancellable = mgr.pauseConditionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self, let p = self.avPlayer else { return }
                let shouldPause = mgr.shouldPause(tabID: self.tabID)
                if shouldPause {
                    if p.rate > 0 {
                        self.wasPlayingBeforeExternalPause = true
                    }
                    session.pause()
                } else if self.wasPlayingBeforeExternalPause && self.isReady {
                    self.wasPlayingBeforeExternalPause = false
                    session.play()
                }
            }
    }

    /// Pauses without tearing down — used for the post-trailer backdrop reveal, and
    /// routed through the session so in-flight stall recovery is cancelled too.
    @MainActor
    func pausePlayback() {
        directSession?.pause()
    }

    /// See the non-tvOS view model: always yields a length so the trailer is
    /// revealed even when the stream never reports one.
    @MainActor
    func resolveTrailerDuration() async -> TimeInterval {
        for attempt in 0..<4 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            guard let av = avPlayer, let item = av.currentItem else { break }
            if item.duration.isNumeric {
                let seconds = CMTimeGetSeconds(item.duration)
                if seconds > 0 { return seconds }
            }
            if let duration = try? await item.asset.load(.duration), duration.isNumeric {
                let seconds = CMTimeGetSeconds(duration)
                if seconds > 0 { return seconds }
            }
        }
        return CarouselTimerManager.unknownTrailerDuration
    }

    @MainActor
    func teardown() {
        // Detach the item while the player is still alive — see the direct session's
        // `invalidate()` for why the order matters to CoreMedia's stall reporting.
        directSession?.invalidate()
        directSession = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        pauseCancellable = nil
        avPlayer = nil
        isReady = false
        didFinishPlaying = false
        wasPlayingBeforeExternalPause = false
    }
    
    func toggleMute() {
        isMuted.toggle()
        avPlayer?.isMuted = isMuted
    }
}
#endif

// MARK: - Carousel Page Indicator (Disney+ Style — Dots as Progress Bars)
/// Each dot doubles as a progress indicator. The currently active dot fills up
/// to show time remaining before auto-advance. During trailer playback the
/// active dot stretches wider and shows trailer progress. Dots never change
/// position — only the fill inside them animates.
struct CarouselPageIndicator: View {
    let totalPages: Int
    let currentPage: Int
    /// 0…1 progress for the current slide (backdrop timer or trailer playback)
    let progress: CGFloat
    let isTrailerPlaying: Bool
    
    // Layout constants
    #if os(tvOS)
    private let dotHeight: CGFloat = 6
    private let inactiveDotWidth: CGFloat = 28
    private let activeDotWidth: CGFloat = 52
    private let trailerActiveDotWidth: CGFloat = 72
    private let dotSpacing: CGFloat = 10
    #else
    private let dotHeight: CGFloat = 4
    private let inactiveDotWidth: CGFloat = 16
    private let activeDotWidth: CGFloat = 32
    private let trailerActiveDotWidth: CGFloat = 48
    private let dotSpacing: CGFloat = 6
    #endif
    
    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<totalPages, id: \.self) { index in
                dotCapsule(for: index)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: currentPage)
        .animation(.easeInOut(duration: 0.3), value: isTrailerPlaying)
    }
    
    @ViewBuilder
    private func dotCapsule(for index: Int) -> some View {
        let isActive = index == currentPage
        let isPast = index < currentPage
        let width: CGFloat = {
            if isActive && isTrailerPlaying { return trailerActiveDotWidth }
            if isActive { return activeDotWidth }
            return inactiveDotWidth
        }()
        
        ZStack(alignment: .leading) {
            // Track (background)
            Capsule()
                .fill(Color.white.opacity(isPast ? 0.55 : 0.25))
                .frame(width: width, height: dotHeight)
            
            // Fill (foreground) — only animates for the active dot
            if isActive {
                Capsule()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: max(dotHeight, width * progress), height: dotHeight)
                    .animation(.linear(duration: 0.06), value: progress)
            } else if isPast {
                // Past dots are fully filled
                Capsule()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: width, height: dotHeight)
            }
        }
        .frame(width: width, height: dotHeight)
    }
}

// MARK: - Array Extension
extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

#Preview {
    HeroCarouselView(items: [], onItemTap: { _ in })
}
