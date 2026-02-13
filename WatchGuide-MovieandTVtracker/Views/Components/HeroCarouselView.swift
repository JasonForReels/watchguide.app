//
//  HeroCarouselView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import Combine
import YouTubePlayerKit

struct HeroCarouselView: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    
    @State private var currentIndex = 0
    @StateObject private var trailerLoader = HeroTrailerLoader()
    @StateObject private var timerManager = CarouselTimerManager()
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main carousel — edge-to-edge
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    GeometryReader { geometry in
                        HeroCarouselSlide(
                            item: item,
                            isActive: index == currentIndex,
                            trailerKey: trailerLoader.trailerKeys[item.id],
                            onTap: { onItemTap(item) },
                            geometry: geometry,
                            colorScheme: colorScheme,
                            onTrailerDurationKnown: { duration in
                                // When the active slide reports its trailer duration,
                                // update the timer to match
                                if index == currentIndex {
                                    timerManager.setDuration(duration)
                                }
                            },
                            onTrailerReady: {
                                // Pause auto-scroll timer until duration is known
                                if index == currentIndex {
                                    timerManager.pause()
                                }
                            }
                        )
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Page indicators / progress bar
            CarouselPageIndicator(
                totalPages: min(items.count, 10),
                currentPage: currentIndex,
                progress: timerManager.progress,
                isTrailerPlaying: timerManager.isTrailerPlaying
            )
            .padding(.bottom, 16)
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
            withAnimation(.easeInOut(duration: 0.9)) {
                currentIndex = (currentIndex + 1) % items.count
            }
        }
        .onChange(of: currentIndex) { _, _ in
            // Reset timer for new slide — default 8s, will update if trailer reports duration
            timerManager.reset(defaultDuration: 8)
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
    
    private var timer: Timer?
    private var isPaused = false
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var duration: TimeInterval = 8
    
    func reset(defaultDuration: TimeInterval) {
        timer?.invalidate()
        stopDisplayLink()
        isPaused = false
        shouldAdvance = false
        progress = 0
        isTrailerPlaying = false
        duration = defaultDuration
        startTimer(interval: defaultDuration)
    }
    
    func setDuration(_ duration: TimeInterval) {
        timer?.invalidate()
        stopDisplayLink()
        isPaused = false
        // Use trailer duration but clamp between 15s and 180s
        let clamped = min(max(duration, 15), 180)
        self.duration = clamped
        isTrailerPlaying = true
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
                self?.shouldAdvance = true
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
        guard isTrailerPlaying else {
            stopDisplayLink()
            return
        }
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
    
    func loadTrailers(for items: [MediaItem]) async {
        await withTaskGroup(of: (Int, String?).self) { group in
            for item in items.prefix(10) {
                group.addTask {
                    do {
                        let videos: VideosResponse
                        if item.resolvedMediaType == .movie {
                            videos = try await TMDBService.shared.getMovieVideos(id: item.id)
                        } else {
                            videos = try await TMDBService.shared.getTVShowVideos(id: item.id)
                        }
                        let key = HeroTrailerLoader.pickTrailerKey(from: videos.results)
                        return (item.id, key)
                    } catch {
                        return (item.id, nil)
                    }
                }
            }
            for await (id, key) in group {
                if let key = key {
                    trailerKeys[id] = key
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
    let onTap: () -> Void
    let geometry: GeometryProxy
    let colorScheme: ColorScheme
    var onTrailerDurationKnown: ((TimeInterval) -> Void)?
    var onTrailerReady: (() -> Void)?
    
    @State private var showTrailer = false
    @StateObject private var playerVM = HeroPlayerViewModel()
    
    private var slideWidth: CGFloat { geometry.size.width }
    private var slideHeight: CGFloat { geometry.size.height }
    
    /// True when the YouTube player is loaded and ready — backdrop should hide
    private var trailerIsVisible: Bool {
        showTrailer && playerVM.isReady
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
            }
            
            // Layer 2: Backdrop image — fades out once the trailer is ready
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
            
            // Layer 4: Content overlay — title, meta, controls
            // Hidden when trailer is actively playing to show clean video
            if !trailerIsVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Spacer()
                    
                    Text(item.displayTitle)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    
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
                .transition(.opacity)
            }
            
            // Layer 5: Trailer-playing overlay — mute button + TRAILER badge
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
                
                // Bottom-left: small title + TRAILER badge
                VStack(alignment: .leading, spacing: 6) {
                    Spacer()
                    HStack(spacing: 10) {
                        Text(item.displayTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        
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
        .onChange(of: playerVM.isReady) { _, ready in
            if ready && isActive {
                onTrailerReady?()
                // Fetch the video duration and report it to the carousel timer
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
    }
    
    private var backdropImage: some View {
        AsyncImage(url: TMDBService.shared.imageURL(path: item.backdropPath, size: .backdrop)) { phase in
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
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
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
    
    @MainActor
    func setup(videoKey: String) {
        guard player == nil else { return }
        
        let startMuted = StorageService.shared.settings.autoPlayTrailersMuted
        isMuted = startMuted
        
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
                allowsInlineMediaPlayback: true
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
                        if self.isMuted {
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
    }
    
    func teardown() {
        Task { @MainActor in
            if let p = player {
                try? await p.pause()
            }
            player = nil
            isReady = false
            stateCancellable = nil
        }
    }
    
    func toggleMute() {
        isMuted.toggle()
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

// MARK: - Carousel Page Indicator (Dots ↔ Progress Bar)
/// Seamlessly morphs between page dots and a continuous progress bar
/// when a trailer is playing. The transition mimics Apple's indicator style.
struct CarouselPageIndicator: View {
    let totalPages: Int
    let currentPage: Int
    let progress: CGFloat
    let isTrailerPlaying: Bool
    
    /// Whether we're showing the progress bar (lags slightly for smooth transition)
    @State private var showingBar = false
    
    // Layout constants
    private let dotSize: CGFloat = 8
    private let activeDotWidth: CGFloat = 24
    private let dotSpacing: CGFloat = 8
    private let barHeight: CGFloat = 4
    private let barWidth: CGFloat = 200
    
    var body: some View {
        ZStack {
            // Dots mode
            if !showingBar {
                dotsView
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            
            // Progress bar mode
            if showingBar {
                progressBarView
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .center)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showingBar)
        .onChange(of: isTrailerPlaying) { _, playing in
            if playing {
                // Slight delay before morphing to bar so it feels intentional
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingBar = true
                }
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingBar = false
                }
            }
        }
    }
    
    // MARK: - Dots
    private var dotsView: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.35))
                    .frame(
                        width: index == currentPage ? activeDotWidth : dotSize,
                        height: dotSize
                    )
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentPage)
    }
    
    // MARK: - Progress Bar
    private var progressBarView: some View {
        ZStack(alignment: .leading) {
            // Track
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: barWidth, height: barHeight)
            
            // Fill
            Capsule()
                .fill(Color.white.opacity(0.9))
                .frame(width: max(barHeight, barWidth * progress), height: barHeight)
                .animation(.linear(duration: 0.05), value: progress)
        }
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
