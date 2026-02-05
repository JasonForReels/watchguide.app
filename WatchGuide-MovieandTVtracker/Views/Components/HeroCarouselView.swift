//
//  HeroCarouselView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import WebKit
import UIKit

struct HeroCarouselView: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    
    @State private var currentIndex = 0
    @State private var timer: Timer?
    @State private var trailers: [Int: Video] = [:] // mediaId -> trailer
    @State private var isPlayingTrailer = false
    @State private var borderRotation: Angle = .degrees(0)
    @State private var borderAnimating: Bool = true
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    private var autoPlayEnabled: Bool {
        StorageService.shared.settings.autoPlayTrailers
    }
    
    // Adaptive height based on orientation
    private var carouselHeight: CGFloat {
        verticalSizeClass == .compact ? 280 : 400
    }
    
    private var animatedBorderGradient: AngularGradient {
        let base = UIColor(ambientColor)
        // Generate complementary and analogous colors for a pleasing gradient
        let components = base.cgColor.components ?? [0.2, 0.2, 0.2, 1]
        let r = components[0], g = components[1], b = components[2]
        let lighten = Color(red: min(r + 0.2, 1), green: min(g + 0.2, 1), blue: min(b + 0.2, 1))
        let darken = Color(red: max(r - 0.2, 0), green: max(g - 0.2, 0), blue: max(b - 0.2, 0))
        let colors: [Color] = [Color(ambientColor), lighten, Color(ambientColor), darken]
        return AngularGradient(gradient: Gradient(colors: colors), center: .center, angle: borderRotation)
    }
    
    @State private var ambientColor: Color = .black
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background blur
                if let currentItem = items[safe: currentIndex] {
                    BackdropImageView(backdropPath: currentItem.backdropPath)
                        .frame(width: geometry.size.width, height: geometry.size.width * 9.0 / 16.0)
                        .blur(radius: 30)
                        .opacity(0.5)
                }
                
                // Main carousel
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HeroSlideView(
                            item: item,
                            width: geometry.size.width,
                            height: geometry.size.width * 9.0 / 16.0,
                            trailer: trailers[item.id],
                            isCurrentSlide: index == currentIndex,
                            autoPlayEnabled: autoPlayEnabled,
                            isPlayingTrailer: $isPlayingTrailer,
                            onTrailerEnded: {
                                // Advance to next item when trailer ends
                                advanceToNextItem()
                            }
                        )
                        .tag(index)
                        .onTapGesture {
                            onItemTap(item)
                        }
                        .onAppear {
                            // Update ambient color when this slide appears
                            if let path = item.backdropPath, let url = TMDBService.shared.imageURL(path: path, size: .backdrop) {
                                Task {
                                    if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                                        updateAmbientColor(from: ui)
                                    }
                                }
                            }
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<min(items.count, 10), id: \.self) { index in
                        Capsule()
                            .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                            .frame(width: index == currentIndex ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.3), value: currentIndex)
                    }
                }
                .padding(.bottom, 16)
            }
            .frame(width: geometry.size.width, height: geometry.size.width * 9.0 / 16.0)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(animatedBorderGradient, lineWidth: 2)
                    .allowsHitTesting(false)
            )
            .aspectRatio(16.0/9.0, contentMode: .fit)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .onAppear {
            startAutoScroll()
            loadTrailers()
            // After a short delay, attempt to start trailer for first item if available
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                attemptStartTrailerForFirstItem()
            }
            startBorderAnimation()
        }
        .onDisappear {
            stopAutoScroll()
            stopBorderAnimation()
        }
        .onChange(of: currentIndex) { _, _ in
            // Reset trailer state when switching slides
            isPlayingTrailer = false
            // Restart auto-scroll timer after manual swipe
            restartAutoScroll()
            // Notify other views about index change
            NotificationCenter.default.post(name: Notification.Name("HeroCarouselIndexChanged"), object: NSNumber(value: currentIndex))
        }
        .preferredColorScheme(StorageService.shared.settings.ambientModeEnabled ? .dark : nil)
    }
    
    private func advanceToNextItem() {
        withAnimation(.easeInOut(duration: 0.5)) {
            currentIndex = (currentIndex + 1) % max(items.count, 1)
        }
        isPlayingTrailer = false
        restartAutoScroll()
    }
    
    private func startAutoScroll() {
        guard !isPlayingTrailer else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { _ in
            if !isPlayingTrailer {
                withAnimation {
                    currentIndex = (currentIndex + 1) % max(items.count, 1)
                }
            }
        }
    }
    
    private func restartAutoScroll() {
        stopAutoScroll()
        startAutoScroll()
    }
    
    private func stopAutoScroll() {
        timer?.invalidate()
        timer = nil
    }
    
    private func loadTrailers() {
        Task {
            // Prioritize fetching the first item's trailer immediately so it can play
            if let first = items.first {
                do {
                    let videos: VideosResponse
                    if first.resolvedMediaType == .movie {
                        videos = try await TMDBService.shared.getMovieVideos(id: first.id)
                    } else {
                        videos = try await TMDBService.shared.getTVShowVideos(id: first.id)
                    }
                    if let best = selectBestOfficialTrailer(from: videos.results) {
                        await MainActor.run {
                            trailers[first.id] = best
                        }
                    }
                } catch {
                    print("Error loading trailer for first item: \(error)")
                }
            }
            
            // Load remaining trailers concurrently for faster loading
            await withTaskGroup(of: (Int, Video?).self) { group in
                for item in items.prefix(10).dropFirst() {
                    group.addTask {
                        do {
                            let videos: VideosResponse
                            if item.resolvedMediaType == .movie {
                                videos = try await TMDBService.shared.getMovieVideos(id: item.id)
                            } else {
                                videos = try await TMDBService.shared.getTVShowVideos(id: item.id)
                            }
                            let trailer = self.selectBestOfficialTrailer(from: videos.results)
                            return (item.id, trailer)
                        } catch {
                            print("Error loading trailer for \(item.displayTitle): \(error)")
                            return (item.id, nil)
                        }
                    }
                }
                
                for await (itemId, trailer) in group {
                    if let trailer = trailer {
                        await MainActor.run {
                            trailers[itemId] = trailer
                        }
                    }
                }
            }
        }
    }
    
    private func ensureCurrentHasTrailerOrAdvance() {
        guard autoPlayEnabled, !items.isEmpty else { return }
        let currentItem = items[currentIndex]
        if trailers[currentItem.id] != nil { return }
        if let nextIndex = items.prefix(10).firstIndex(where: { trailers[$0.id] != nil }) {
            withAnimation { currentIndex = nextIndex }
        }
    }
    
    private nonisolated func selectBestOfficialTrailer(from videos: [Video]) -> Video? {
        // Filter to only YouTube trailers (excluding teasers)
        let trailers = videos.filter {
            $0.site.lowercased() == "youtube" &&
            $0.type == "Trailer"
        }
        
        guard !trailers.isEmpty else { return nil }
        
        // Keywords that indicate this is NOT a standard "Official Trailer"
        let excludeKeywords = ["final", "teaser", "tv spot", "featurette", "clip", "behind", "making of", "interview", "red band"]
        
        // Keywords that indicate this IS an official trailer we want
        let preferKeywords = ["official trailer", "theatrical trailer", "main trailer"]
        
        // Score and sort trailers
        let scored = trailers.map { video -> (video: Video, score: Int) in
            var score = 0
            let nameLower = video.name.lowercased()
            
            // Strong preference for official trailers
            if video.official == true {
                score += 100
            }
            
            // Boost for preferred keywords
            for keyword in preferKeywords {
                if nameLower.contains(keyword) {
                    score += 50
                    break
                }
            }
            
            // Penalize excluded keywords (final trailer, teaser, etc.)
            for keyword in excludeKeywords {
                if nameLower.contains(keyword) {
                    score -= 200
                    break
                }
            }
            
            // Simple "trailer" in name is good
            if nameLower.contains("trailer") && !nameLower.contains("teaser") {
                score += 20
            }
            
            // Numbered trailers (Trailer 2, Trailer 3) get lower priority
            if nameLower.contains("trailer 2") || nameLower.contains("trailer 3") || nameLower.contains("trailer #2") || nameLower.contains("trailer #3") {
                score -= 30
            }
            
            return (video, score)
        }
        
        // Sort by score descending
        let sorted = scored.sorted { $0.score > $1.score }
        
        return sorted.first?.video
    }
    
    private func startBorderAnimation() {
        borderAnimating = true
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            borderRotation = .degrees(360)
        }
    }
    
    private func stopBorderAnimation() {
        borderAnimating = false
        borderRotation = .degrees(0)
    }
    
    private func updateAmbientColor(from uiImage: UIImage) {
        if let avg = uiImage.averageColor() {
            ambientColor = Color(avg)
        } else {
            ambientColor = .black
        }
    }
    
    private func attemptStartTrailerForFirstItem() {
        guard autoPlayEnabled, !items.isEmpty else { return }
        
        currentIndex = 0
        let firstItemId = items[0].id
        
        if trailers[firstItemId] != nil {
            // Post notification and try to start trailer soon
            NotificationCenter.default.post(name: Notification.Name("HeroCarouselIndexChanged"), object: NSNumber(value: currentIndex))
            isPlayingTrailer = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isPlayingTrailer = true
            }
            return
        }
        
        var attempts = 0
        func pollForTrailer() {
            attempts += 1
            if trailers[firstItemId] != nil {
                NotificationCenter.default.post(name: Notification.Name("HeroCarouselIndexChanged"), object: NSNumber(value: currentIndex))
                isPlayingTrailer = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isPlayingTrailer = true
                }
            } else if attempts < 15 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    pollForTrailer()
                }
            }
            // If no trailer found after polling, do nothing (do not advance)
        }
        pollForTrailer()
    }
}

// MARK: - Hero Slide View
struct HeroSlideView: View {
    let item: MediaItem
    let width: CGFloat
    var height: CGFloat = 400
    let trailer: Video?
    let isCurrentSlide: Bool
    let autoPlayEnabled: Bool
    @Binding var isPlayingTrailer: Bool
    var onTrailerEnded: (() -> Void)?
    
    @State private var showTrailer = false
    @State private var trailerReady = false
    @State private var trailerFailed = false
    @State private var trailerKey: String = ""
    @State private var isMuted: Bool = StorageService.shared.settings.autoPlayTrailersMuted
    @State private var ambientColor: Color = .black
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }
    
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    
    private var shouldShowTrailer: Bool {
        showTrailer && !trailerFailed && trailer != nil && autoPlayEnabled && isCurrentSlide && !trailerKey.isEmpty
    }
    
    // Only hide backdrop once trailer is actually ready and playing
    private var shouldHideBackdrop: Bool {
        shouldShowTrailer && trailerReady
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if StorageService.shared.settings.ambientModeEnabled {
                AmbientBackground(color: ambientColor)
            }
            
            // Show backdrop until trailer is ready and playing - with smooth fade out
            backdropView
                .frame(width: width, height: height)
                .clipped()
                .opacity(shouldHideBackdrop ? 0 : 1)
                .animation(.easeInOut(duration: 0.5), value: shouldHideBackdrop)
                .zIndex(0)
            
            // Video overlay (only when ready and valid)
            if shouldShowTrailer {
                YouTubePlayerView(
                    videoKey: trailerKey,
                    autoPlay: true,
                    isMuted: isMuted,
                    onReady: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            trailerReady = true
                        }
                    },
                    onError: { error in
                        print("Trailer error: \(error)")
                        DispatchQueue.main.async {
                            trailerFailed = true
                            showTrailer = false
                            isPlayingTrailer = false
                        }
                    },
                    onEnded: {
                        // Trailer finished playing: hide overlay and restore backdrop/title immediately
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showTrailer = false
                            }
                            isPlayingTrailer = false
                            trailerKey = ""
                            onTrailerEnded?()
                        }
                    }
                )
                .frame(width: width, height: height)
                .clipped()
                .transition(.opacity)
                .zIndex(1)
            }
            
            // Gradient overlay (lighter when video is playing)
            LinearGradient(
                colors: [.clear, .black.opacity(shouldShowTrailer ? 0.5 : 0.7), .black.opacity(shouldShowTrailer ? 0.7 : 0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            .zIndex(2)
            
            // Content - adaptive layout for landscape
            VStack(alignment: .leading, spacing: isCompactHeight ? 6 : 12) {
                HStack {
                    // Media type badge
                    Text(item.resolvedMediaType == .movie ? "Movie" : "TV Show")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    
                    Spacer()
                    
                    // Trailer play button (hide if already playing or failed)
                    if trailer != nil && autoPlayEnabled && !trailerFailed && !showTrailer {
                        Button {
                            startTrailer()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                Text("Trailer")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .foregroundColor(.white)
                    }
                }
                
                Spacer()
                
                if !(isPhone && shouldShowTrailer) {
                    Text(item.displayTitle)
                        .font(isCompactHeight ? .title2 : .title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(isCompactHeight ? 1 : 2)
                }
                
                // Info row
                HStack(spacing: 12) {
                    if let year = item.year {
                        Text(year)
                            .foregroundColor(.white.opacity(0.8))
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
                
                // Overview (hide when trailer is playing or in compact height)
                if !shouldShowTrailer && !isCompactHeight, let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            .padding(isCompactHeight ? 16 : 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zIndex(3)
        }
        .aspectRatio(16.0/9.0, contentMode: .fill)
        .preferredColorScheme(StorageService.shared.settings.ambientModeEnabled ? .dark : nil)
        .onTapGesture {
            if shouldShowTrailer && isMuted {
                isMuted = false
            }
        }
        .onChange(of: isCurrentSlide) { _, newValue in
            if !newValue {
                // Stop trailer when sliding away
                stopTrailer()
            } else if autoPlayEnabled && !trailerFailed {
                attemptAutoStartWithWait()
            }
        }
        .onChange(of: showTrailer) { oldValue, newValue in
            // Fallback: if trailer just stopped displaying while this is the current slide, advance immediately
            if oldValue == true && newValue == false && autoPlayEnabled {
                onTrailerEnded?()
            }
        }
        .onAppear {
            // Reset states when appearing
            trailerFailed = false
            trailerReady = false
            trailerKey = ""
            // Removed resetting isMuted to true here to preserve initial setting from StorageService
            // isMuted = true
            
            // Start trailer if this is the current slide and autoplay is enabled (wait if trailer not loaded yet)
            if isCurrentSlide && autoPlayEnabled {
                attemptAutoStartWithWait()
            }
        }
        .onDisappear {
            stopTrailer()
        }
    }
    
    // MARK: - Backdrop View
    @ViewBuilder
    private var backdropView: some View {
        AsyncImage(url: TMDBService.shared.imageURL(path: item.backdropPath, size: .backdrop)) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        ProgressView()
                    }
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .onAppear {
                        Task {
                            if let path = item.backdropPath, let url = TMDBService.shared.imageURL(path: path, size: .backdrop) {
                                if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                                    updateAmbientColor(from: ui)
                                }
                            }
                        }
                    }
            case .failure:
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
            @unknown default:
                Rectangle()
                    .fill(Color(.systemGray5))
            }
        }
    }
    
    // MARK: - Helper Methods
    private func startTrailer() {
        guard let trailer = trailer, !trailer.key.isEmpty else {
            trailerFailed = true
            return
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            trailerKey = trailer.key
            showTrailer = true
            isPlayingTrailer = true
        }
    }
    
    private func stopTrailer() {
        showTrailer = false
        trailerReady = false
        trailerKey = ""
    }
    
    private func updateAmbientColor(from uiImage: UIImage) {
        if let avg = uiImage.averageColor() {
            ambientColor = Color(avg)
        } else {
            ambientColor = .black
        }
    }
    
    private func attemptAutoStartWithWait() {
        guard autoPlayEnabled && isCurrentSlide && !trailerFailed else { return }
        // If we already have a trailer, start shortly
        if trailer != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if isCurrentSlide && !trailerFailed {
                    startTrailer()
                }
            }
            return
        }
        // Otherwise, poll briefly for trailer availability (up to ~2 seconds)
        var attempts = 0
        func poll() {
            attempts += 1
            if trailer != nil && isCurrentSlide && !trailerFailed {
                startTrailer()
            } else if attempts < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    poll()
                }
            }
        }
        poll()
    }
}

// MARK: - Ambient Background View
struct AmbientBackground: View {
    let color: Color
    var body: some View {
        ZStack {
            color.opacity(0.6)
            RadialGradient(colors: [color.opacity(0.7), color.opacity(0.2), .black.opacity(0.8)], center: .center, startRadius: 0, endRadius: 800)
                .blendMode(.plusLighter)
        }
        .blur(radius: 60)
        .ignoresSafeArea()
    }
}

// MARK: - YouTube Player View using YouTube IFrame API
struct YouTubePlayerView: UIViewRepresentable {
    let videoKey: String
    var autoPlay: Bool = false
    var isMuted: Bool = false
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?
    var onEnded: (() -> Void)?
    
    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "playerReady")
        contentController.add(context.coordinator, name: "playerError")
        contentController.add(context.coordinator, name: "playerEnded")
        contentController.add(context.coordinator, name: "playerStateChange")
        
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences = preferences
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard !videoKey.isEmpty else {
            DispatchQueue.main.async {
                self.onError?("Invalid video key")
            }
            return
        }
        
        if context.coordinator.currentVideoKey == videoKey && context.coordinator.lastMuteValue == isMuted {
            return
        }
        context.coordinator.currentVideoKey = videoKey
        context.coordinator.lastMuteValue = isMuted
        context.coordinator.hasErrored = false
        
        loadYouTubePlayer(webView: webView)
    }
    
    private func loadYouTubePlayer(webView: WKWebView) {
        let sanitizedKey = videoKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? videoKey
        let autoPlayValue = autoPlay ? 1 : 0
        let muteValue = isMuted ? 1 : 0
        
        // Use YouTube's official IFrame Player API for faster, more reliable loading
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; overflow: hidden; background: transparent; }
                #player-container {
                    position: absolute;
                    top: 50%;
                    left: 50%;
                    width: 177.78vh;
                    height: 100vh;
                    min-width: 100%;
                    min-height: 56.25vw;
                    transform: translate(-50%, -50%);
                }
                #player {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                }
            </style>
        </head>
        <body>
            <div id="player-container">
                <div id="player"></div>
            </div>
            
            <script>
                var tag = document.createElement('script');
                tag.src = "https://www.youtube.com/iframe_api";
                var firstScriptTag = document.getElementsByTagName('script')[0];
                firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
                
                var player;
                var hasNotifiedReady = false;
                var hasNotifiedError = false;
                var hasNotifiedEnded = false;
                var apiReady = false;
                var createAttempted = false;
                
                function notifyReady() {
                    if (!hasNotifiedReady) {
                        hasNotifiedReady = true;
                        try { window.webkit.messageHandlers.playerReady.postMessage('ready'); } catch(e) {}
                    }
                }
                
                function notifyError(msg) {
                    if (!hasNotifiedError) {
                        hasNotifiedError = true;
                        try { window.webkit.messageHandlers.playerError.postMessage(msg); } catch(e) {}
                    }
                }
                
                function notifyEnded() {
                    if (!hasNotifiedEnded) {
                        hasNotifiedEnded = true;
                        try { window.webkit.messageHandlers.playerEnded.postMessage('ended'); } catch(e) {}
                    }
                }
                
                function createPlayer() {
                    if (createAttempted) return;
                    createAttempted = true;
                    
                    player = new YT.Player('player', {
                        videoId: '\(sanitizedKey)',
                        playerVars: {
                            'autoplay': \(autoPlayValue),
                            'mute': \(muteValue),
                            'controls': 0,
                            'modestbranding': 1,
                            'rel': 0,
                            'iv_load_policy': 3,
                            'showinfo': 0,
                            'playsinline': 1,
                            'enablejsapi': 1,
                            'origin': window.location.origin
                        },
                        events: {
                            'onReady': onPlayerReady,
                            'onStateChange': onPlayerStateChange,
                            'onError': onPlayerError
                        }
                    });
                }
                
                function onYouTubeIframeAPIReady() {
                    apiReady = true;
                    createPlayer();
                }
                
                function onPlayerReady(event) {
                    notifyReady();
                    if (\(autoPlayValue) === 1) {
                        event.target.playVideo();
                    }
                }
                
                function onPlayerStateChange(event) {
                    try { window.webkit.messageHandlers.playerStateChange.postMessage(event.data); } catch(e) {}
                    
                    // State 1 = playing - notify ready when video actually starts
                    if (event.data === 1 && !hasNotifiedReady) {
                        notifyReady();
                    }
                    // State 0 = ended
                    if (event.data === 0) {
                        notifyEnded();
                    }
                }
                
                function onPlayerError(event) {
                    notifyError('YouTube error: ' + event.data);
                }
                
                // Timeout: if API doesn't load within 4 seconds, try fallback iframe
                setTimeout(function() {
                    if (!apiReady && !hasNotifiedError) {
                        // Fallback to direct iframe embed
                        var container = document.getElementById('player-container');
                        container.innerHTML = '<iframe id="fallback-player" src="https://www.youtube-nocookie.com/embed/\(sanitizedKey)?autoplay=\(autoPlayValue)&mute=\(muteValue)&controls=0&modestbranding=1&rel=0&playsinline=1" style="position:absolute;top:0;left:0;width:100%;height:100%;border:none;" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>';
                        
                        var fallbackIframe = document.getElementById('fallback-player');
                        fallbackIframe.onload = function() {
                            notifyReady();
                        };
                        
                        // Notify ready after short delay even if onload doesn't fire
                        setTimeout(function() {
                            if (!hasNotifiedReady && !hasNotifiedError) {
                                notifyReady();
                            }
                        }, 1000);
                    }
                }, 4000);
                
                // Final fallback: notify ready after 6 seconds no matter what
                setTimeout(function() {
                    if (!hasNotifiedReady && !hasNotifiedError) {
                        notifyReady();
                    }
                }, 6000);
                
                // Auto-advance after 3 minutes (typical trailer length)
                setTimeout(function() {
                    if (!hasNotifiedEnded) {
                        notifyEnded();
                    }
                }, 180000);
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onError: onError, onEnded: onEnded)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var currentVideoKey: String?
        var lastMuteValue: Bool? = nil
        var hasErrored: Bool = false
        var onReady: (() -> Void)?
        var onError: ((String) -> Void)?
        var onEnded: (() -> Void)?
        
        init(onReady: (() -> Void)?, onError: ((String) -> Void)?, onEnded: (() -> Void)?) {
            self.onReady = onReady
            self.onError = onError
            self.onEnded = onEnded
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "playerReady":
                DispatchQueue.main.async {
                    self.onReady?()
                }
            case "playerError":
                guard !hasErrored else { return }
                hasErrored = true
                let errorMsg = message.body as? String ?? "Unknown error"
                DispatchQueue.main.async {
                    self.onError?(errorMsg)
                }
            case "playerEnded":
                DispatchQueue.main.async {
                    self.onEnded?()
                }
            case "playerStateChange":
                // Can be used for additional state tracking if needed
                break
            default:
                break
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !hasErrored else { return }
            hasErrored = true
            DispatchQueue.main.async {
                self.onError?("Navigation failed: \(error.localizedDescription)")
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !hasErrored else { return }
            hasErrored = true
            DispatchQueue.main.async {
                self.onError?("Failed to load: \(error.localizedDescription)")
            }
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

// MARK: - UIImage Average Color Extension
extension UIImage {
    func averageColor() -> UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: CIVector(cgRect: extent)])
        guard let outputImage = filter?.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(bitmap[0]) / 255.0, green: CGFloat(bitmap[1]) / 255.0, blue: CGFloat(bitmap[2]) / 255.0, alpha: 1)
    }
}

#Preview {
    HeroCarouselView(items: [], onItemTap: { _ in })
}

