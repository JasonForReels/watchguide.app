//
//  HeroCarouselView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import Combine
import YouTubePlayerKit

// MARK: - Hero Carousel Mute Manager
/// Shared manager that allows external views (e.g. detail sheets) to request the hero carousel
/// to mute/unmute its trailer audio automatically.
@MainActor
class HeroCarouselMuteManager: ObservableObject {
    static let shared = HeroCarouselMuteManager()
    
    /// When true, all hero carousel players should be muted (e.g. a detail page is open)
    @Published var isExternallyMuted = false
}

struct HeroCarouselView: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    
    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @StateObject private var trailerLoader = HeroTrailerLoader()
    @StateObject private var timerManager = CarouselTimerManager()
    @Environment(\.colorScheme) private var colorScheme
    
    // Transition animation — Apple-style spring
    private let slideSpring: Animation = .interpolatingSpring(
        mass: 1.0, stiffness: 170, damping: 24, initialVelocity: 0
    )
    
    var body: some View {
        GeometryReader { outerGeo in
            let width = outerGeo.size.width
            let height = outerGeo.size.height
            
            ZStack(alignment: .bottom) {
                // Carousel slides
                ZStack {
                    ForEach(Array(items.prefix(10).enumerated()), id: \.element.id) { index, item in
                        let offset = slideOffset(for: index, containerWidth: width)
                        let scaleVal = slideScale(for: index, containerWidth: width)
                        let opacityVal = slideOpacity(for: index, containerWidth: width)
                        
                        HeroCarouselSlide(
                            item: item,
                            isActive: index == currentIndex && !isDragging,
                            trailerKey: trailerLoader.trailerKeys[item.id],
                            logoURL: trailerLoader.logoURLs[item.id],
                            fanartBackdropURL: trailerLoader.fanartBackdropURLs[item.id],
                            onTap: { onItemTap(item) },
                            slideSize: CGSize(width: width, height: height),
                            colorScheme: colorScheme,
                            trailerPhase: timerManager.trailerPhase,
                            onTrailerDurationKnown: { duration in
                                if index == currentIndex {
                                    timerManager.setDuration(duration)
                                }
                            },
                            onTrailerReady: {
                                if index == currentIndex {
                                    timerManager.pause()
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
                                advanceTo(index: (currentIndex + 1) % items.count)
                            } else if value.translation.width > threshold || velocity > 150 {
                                // Swipe right → previous
                                advanceTo(index: (currentIndex - 1 + items.count) % items.count)
                            } else {
                                // Snap back
                                withAnimation(slideSpring) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                
                // Page indicators / progress bar
                CarouselPageIndicator(
                    totalPages: min(items.count, 10),
                    currentPage: currentIndex,
                    progress: timerManager.progress,
                    isTrailerPlaying: timerManager.isTrailerPlaying
                )
                .padding(.bottom, 16)
            }
        }
        .aspectRatio(16.0/10.0, contentMode: .fit)
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
        .padding(.horizontal, 12)
        .onReceive(timerManager.$shouldAdvance) { advance in
            guard advance, items.count > 1 else { return }
            timerManager.shouldAdvance = false
            advanceTo(index: (currentIndex + 1) % items.count)
        }
        .onChange(of: items.count) { _, newCount in
            if newCount == 0 { currentIndex = 0 }
            else if currentIndex >= newCount { currentIndex = 0 }
        }
        .onAppear {
            timerManager.reset(defaultDuration: 8)
        }
        .task {
            await trailerLoader.loadTrailers(for: items)
        }
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
        timerManager.reset(defaultDuration: 8)
    }
}

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
    
    private var timer: Timer?
    private var isPaused = false
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var duration: TimeInterval = 8
    
    /// How long to show the backdrop after a trailer finishes before advancing
    static let postTrailerBackdropDuration: TimeInterval = 3.0
    /// Extra grace period for the progress-bar → dots morph animation
    static let morphGracePeriod: TimeInterval = 1.2
    
    func reset(defaultDuration: TimeInterval) {
        timer?.invalidate()
        stopDisplayLink()
        isPaused = false
        shouldAdvance = false
        progress = 0
        isTrailerPlaying = false
        trailerPhase = .backdrop
        duration = defaultDuration
        startTime = CACurrentMediaTime()
        startTimer(interval: defaultDuration)
        // Always run display link so the dot progress fills during backdrop too
        startDisplayLink()
    }
    
    func setDuration(_ duration: TimeInterval) {
        timer?.invalidate()
        stopDisplayLink()
        isPaused = false
        let clamped = min(max(duration, 15), 180)
        self.duration = clamped
        isTrailerPlaying = true
        trailerPhase = .playing
        startTime = CACurrentMediaTime()
        startTimer(interval: clamped)
        startDisplayLink()
    }
    
    func pause() {
        timer?.invalidate()
        isPaused = true
    }
    
    private func startTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.isTrailerPlaying {
                    // 1. Transition indicator back to dots
                    self.isTrailerPlaying = false
                    self.stopDisplayLink()
                    // 2. Enter post-trailer phase — show backdrop with title
                    withAnimation(.easeInOut(duration: 0.6)) {
                        self.trailerPhase = .postTrailer
                    }
                    // 3. After backdrop display + morph grace, advance
                    let totalWait = CarouselTimerManager.morphGracePeriod + CarouselTimerManager.postTrailerBackdropDuration
                    DispatchQueue.main.asyncAfter(deadline: .now() + totalWait) {
                        self.shouldAdvance = true
                    }
                } else {
                    self.shouldAdvance = true
                }
            }
        }
    }
    
    // MARK: - Display Link for smooth progress
    private func startDisplayLink() {
        stopDisplayLink()
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in
            self?.updateProgress()
        }, selector: #selector(DisplayLinkTarget.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
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
        displayLink?.invalidate()
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
    @Published var trailerKeys: [Int: String] = [:]
    /// item.id → full logo URL string (FanArt.tv primary, TMDB fallback path prefixed with scheme)
    @Published var logoURLs: [Int: String] = [:]
    /// item.id → full backdrop URL string from FanArt.tv (nil = use TMDB backdrop)
    @Published var fanartBackdropURLs: [Int: String] = [:]
    
    func loadTrailers(for items: [MediaItem]) async {
        // Load trailers, logos (FanArt→TMDB), and backdrops in parallel
        await withTaskGroup(of: (Int, String?, String?, String?).self) { group in
            for item in items.prefix(10) {
                group.addTask {
                    var trailerKey: String?
                    var logoURL: String?
                    var backdropURL: String?
                    
                    // Fetch trailer
                    do {
                        let videos: VideosResponse
                        if item.resolvedMediaType == .movie {
                            videos = try await TMDBService.shared.getMovieVideos(id: item.id)
                        } else {
                            videos = try await TMDBService.shared.getTVShowVideos(id: item.id)
                        }
                        trailerKey = HeroTrailerLoader.pickTrailerKey(from: videos.results)
                    } catch {}
                    
                    // Fetch logo — FanArt.tv first, TMDB fallback
                    if let fanartLogo = await FanArtService.shared.getBestLogoURL(tmdbId: item.id, mediaType: item.resolvedMediaType) {
                        logoURL = fanartLogo.absoluteString
                    } else {
                        // TMDB fallback
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
                    
                    return (item.id, trailerKey, logoURL, backdropURL)
                }
            }
            for await (id, key, logo, backdrop) in group {
                if let key = key {
                    trailerKeys[id] = key
                }
                if let logo = logo {
                    logoURLs[id] = logo
                }
                if let backdrop = backdrop {
                    fanartBackdropURLs[id] = backdrop
                }
            }
        }
    }
    
    /// Picks the best trailer key from a list of videos.
    /// Broadened logic: accepts official trailers first, then teasers, then any YouTube video.
    nonisolated static func pickTrailerKey(from videos: [Video]) -> String? {
        let yt = videos.filter { $0.site.lowercased() == "youtube" }
        guard !yt.isEmpty else { return nil }
        
        // Priority 1: Official trailer (not a "final" one to avoid spoilers)
        let officialTrailers = yt.filter { v in
            v.type.lowercased() == "trailer" && v.official == true
        }
        let nonFinalOfficialTrailers = officialTrailers.filter { v in
            let name = v.name.lowercased()
            return !name.contains("final trailer") && !name.contains("final teaser")
        }
        if let pick = nonFinalOfficialTrailers.first ?? officialTrailers.first {
            return pick.key
        }
        
        // Priority 2: Any trailer (official or not)
        let anyTrailers = yt.filter { $0.type.lowercased() == "trailer" }
        if let pick = anyTrailers.first {
            return pick.key
        }
        
        // Priority 3: Official teaser
        let officialTeasers = yt.filter { v in
            v.type.lowercased() == "teaser" && v.official == true
        }
        if let pick = officialTeasers.first {
            return pick.key
        }
        
        // Priority 4: Any teaser
        let anyTeasers = yt.filter { $0.type.lowercased() == "teaser" }
        if let pick = anyTeasers.first {
            return pick.key
        }
        
        // Priority 5: Any YouTube clip/featurette as last resort
        return yt.first?.key
    }
}

// MARK: - Hero Carousel Slide
struct HeroCarouselSlide: View {
    let item: MediaItem
    let isActive: Bool
    let trailerKey: String?
    /// Full URL string for the logo (FanArt.tv or TMDB)
    let logoURL: String?
    /// Full URL string for the FanArt.tv backdrop (nil = use TMDB)
    let fanartBackdropURL: String?
    let onTap: () -> Void
    let slideSize: CGSize
    let colorScheme: ColorScheme
    let trailerPhase: TrailerPhase
    var onTrailerDurationKnown: ((TimeInterval) -> Void)?
    var onTrailerReady: (() -> Void)?
    
    @State private var showTrailer = false
    @StateObject private var playerVM = HeroPlayerViewModel()
    
    private var slideWidth: CGFloat { slideSize.width }
    private var slideHeight: CGFloat { slideSize.height }
    
    /// True when the YouTube player is loaded and ready — backdrop should hide
    private var trailerIsVisible: Bool {
        showTrailer && playerVM.isReady && trailerPhase == .playing
    }
    
    /// True when we're in the post-trailer backdrop reveal
    private var isPostTrailer: Bool {
        trailerPhase == .postTrailer && showTrailer
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Layer 0: Black base so there's no flash when backdrop fades
            Color.black
            
            // Layer 1: Trailer video (rendered first / bottom of stack)
            if showTrailer, let player = playerVM.player {
                YouTubePlayerKit.YouTubePlayerView(player)
                    .frame(width: slideWidth, height: slideHeight)
                    .allowsHitTesting(false)
                    .opacity(isPostTrailer ? 0 : 1)
                    .animation(.easeInOut(duration: 0.8), value: isPostTrailer)
            }
            
            // Layer 2: Backdrop image — fades out for trailer, fades back for post-trailer
            backdropImage
                .opacity(trailerIsVisible ? 0 : 1)
                .animation(.easeInOut(duration: 0.6), value: trailerIsVisible)
                .allowsHitTesting(false)
            
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
                .frame(height: slideHeight * 0.55)
            }
            .allowsHitTesting(false)
            
            // Layer 4: Content overlay — logo/title, meta (shown when NOT playing trailer)
            if !trailerIsVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Spacer()
                    
                    // Show logo if available, otherwise fall back to text title
                    if let logoURLStr = logoURL,
                       let resolvedLogoURL = URL(string: logoURLStr) {
                        AsyncImage(url: resolvedLogoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: slideWidth * 0.55, maxHeight: 60)
                                    .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
                            default:
                                backdropTitleText
                            }
                        }
                    } else {
                        backdropTitleText
                    }
                    
                    HStack(spacing: 12) {
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
                    .font(.subheadline)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.animation(.easeInOut(duration: 0.5)))
            }
            
            // Layer 5: Trailer-playing overlay — mute button + logo + TRAILER badge
            if trailerIsVisible {
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
                            .background(Capsule().fill(.ultraThinMaterial))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
        .frame(width: slideWidth, height: slideHeight)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onChange(of: isActive) { _, active in
            if active {
                startTrailerIfNeeded()
            } else {
                stopTrailer()
            }
        }
        .onChange(of: trailerPhase) { _, phase in
            // When entering post-trailer, pause the YouTube player
            if phase == .postTrailer, let p = playerVM.player {
                Task { try? await p.pause() }
            }
        }
        .onChange(of: playerVM.isReady) { _, ready in
            if ready && isActive {
                onTrailerReady?()
                if let p = playerVM.player {
                    Task {
                        if let duration = try? await p.getDuration() {
                            let seconds = duration.converted(to: .seconds).value
                            if seconds > 0 {
                                onTrailerDurationKnown?(seconds)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if isActive {
                startTrailerIfNeeded()
            }
        }
        .onDisappear {
            stopTrailer()
        }
        // Fix: when the trailer key arrives *after* the first slide is already active,
        // onChange(of: isActive) won't re-fire because isActive was always true.
        // Watch for the trailer key itself so the first slide starts its trailer.
        .onChange(of: trailerKey) { _, newKey in
            if isActive && newKey != nil && !showTrailer {
                startTrailerIfNeeded()
            }
        }
    }
    
    /// Large text fallback for backdrop view when logo isn't available
    private var backdropTitleText: some View {
        Text(item.displayTitle)
            .font(.title)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
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
    
    /// Resolved backdrop URL: FanArt.tv when available, otherwise TMDB
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
                    .fill(Color(.systemGray5))
                    .overlay { ProgressView() }
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                // If FanArt backdrop failed, try TMDB directly
                if fanartBackdropURL != nil {
                    AsyncImage(url: TMDBService.shared.imageURL(path: item.backdropPath, size: .backdrop)) { fallbackPhase in
                        switch fallbackPhase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .overlay {
                                    Image(systemName: "film")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                }
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "film")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        }
                }
            @unknown default:
                Rectangle().fill(Color(.systemGray5))
            }
        }
        .frame(width: slideWidth, height: slideHeight)
        .clipped()
    }
    
    private func startTrailerIfNeeded() {
        guard let key = trailerKey else { return }
        showTrailer = true
        playerVM.setup(videoKey: key)
    }
    
    private func stopTrailer() {
        showTrailer = false
        playerVM.teardown()
    }
}

// MARK: - Hero Player ViewModel
class HeroPlayerViewModel: ObservableObject {
    @Published var player: YouTubePlayer?
    @Published var isReady = false
    @Published var isMuted = true
    
    private var stateCancellable: AnyCancellable?
    private var externalMuteCancellable: AnyCancellable?
    /// Tracks the user's chosen mute state before external muting was applied
    private var userMutePreference: Bool = true
    
    @MainActor
    func setup(videoKey: String) {
        guard player == nil else { return }
        
        let startMuted = StorageService.shared.settings.autoPlayTrailersMuted
        isMuted = startMuted
        userMutePreference = startMuted
        
        let ytPlayer = YouTubePlayer(
            source: .video(id: videoKey),
            parameters: .init(
                autoPlay: true,
                loopEnabled: false,
                showControls: false,
                showFullscreenButton: false,
                keyboardControlsDisabled: true,
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
        
        stateCancellable = ytPlayer.statePublisher.sink { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isReady = true
                    Task {
                        // If externally muted, always mute regardless of user preference
                        let shouldMute = self.isMuted || HeroCarouselMuteManager.shared.isExternallyMuted
                        if shouldMute {
                            try? await ytPlayer.mute()
                        } else {
                            try? await ytPlayer.unmute()
                        }
                        // Ensure playback starts
                        try? await ytPlayer.play()
                    }
                default:
                    break
                }
            }
        }
        
        // Observe external mute requests (e.g. when a detail page opens)
        externalMuteCancellable = HeroCarouselMuteManager.shared.$isExternallyMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] externallyMuted in
                guard let self = self, let p = self.player, self.isReady else { return }
                if externallyMuted {
                    // Save current user preference before forcing mute
                    self.userMutePreference = self.isMuted
                    self.isMuted = true
                    Task { try? await p.mute() }
                } else {
                    // Restore the user's preference when external mute is lifted
                    self.isMuted = self.userMutePreference
                    Task {
                        if self.userMutePreference {
                            try? await p.mute()
                        } else {
                            try? await p.unmute()
                        }
                    }
                }
            }
    }
    
    func teardown() {
        Task { @MainActor in
            if let p = player {
                try? await p.pause()
            }
            player = nil
            isReady = false
            stateCancellable = nil
            externalMuteCancellable = nil
        }
    }
    
    func toggleMute() {
        isMuted.toggle()
        userMutePreference = isMuted
        guard let p = player else { return }
        Task {
            if isMuted {
                try? await p.mute()
            } else {
                try? await p.unmute()
            }
        }
    }
}

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
    private let dotHeight: CGFloat = 4
    private let inactiveDotWidth: CGFloat = 16
    private let activeDotWidth: CGFloat = 32
    private let trailerActiveDotWidth: CGFloat = 48
    private let dotSpacing: CGFloat = 6
    
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
