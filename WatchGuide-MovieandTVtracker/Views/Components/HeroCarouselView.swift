//
//  HeroCarouselView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import WebKit

struct HeroCarouselView: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    
    @State private var currentIndex = 0
    @State private var timer: Timer?
    @State private var trailers: [Int: Video] = [:] // mediaId -> trailer
    @State private var isPlayingTrailer = false
    
    private var autoPlayEnabled: Bool {
        StorageService.shared.settings.autoPlayTrailers
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background blur
                if let currentItem = items[safe: currentIndex] {
                    BackdropImageView(backdropPath: currentItem.backdropPath)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 30)
                        .opacity(0.5)
                }
                
                // Main carousel
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HeroSlideView(
                            item: item,
                            width: geometry.size.width,
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
        }
        .frame(height: 400)
        .onAppear {
            startAutoScroll()
            loadTrailers()
        }
        .onDisappear {
            stopAutoScroll()
        }
        .onChange(of: currentIndex) { _, _ in
            // Reset trailer state when switching slides
            isPlayingTrailer = false
            // Restart auto-scroll timer after manual swipe
            restartAutoScroll()
        }
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
            for item in items.prefix(10) {
                do {
                    let videos: VideosResponse
                    if item.resolvedMediaType == .movie {
                        videos = try await TMDBService.shared.getMovieVideos(id: item.id)
                    } else {
                        videos = try await TMDBService.shared.getTVShowVideos(id: item.id)
                    }
                    
                    // Find the best trailer (official trailer preferred, exclude teasers/final trailers)
                    let trailer = selectBestOfficialTrailer(from: videos.results)
                    
                    if let trailer = trailer {
                        await MainActor.run {
                            trailers[item.id] = trailer
                        }
                    }
                } catch {
                    print("Error loading trailer for \(item.displayTitle): \(error)")
                }
            }
        }
    }
    
    private func selectBestOfficialTrailer(from videos: [Video]) -> Video? {
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
}

// MARK: - Hero Slide View
struct HeroSlideView: View {
    let item: MediaItem
    let width: CGFloat
    let trailer: Video?
    let isCurrentSlide: Bool
    let autoPlayEnabled: Bool
    @Binding var isPlayingTrailer: Bool
    var onTrailerEnded: (() -> Void)?
    
    @State private var showTrailer = false
    @State private var trailerReady = false
    @State private var trailerFailed = false
    @State private var trailerKey: String = ""
    
    private var shouldShowTrailer: Bool {
        showTrailer && !trailerFailed && trailer != nil && autoPlayEnabled && isCurrentSlide && !trailerKey.isEmpty
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Always show backdrop first as base layer
            backdropView
                .frame(width: width, height: 400)
                .clipped()
            
            // Video overlay (only when ready and valid)
            if shouldShowTrailer {
                YouTubePlayerView(
                    videoKey: trailerKey,
                    autoPlay: true,
                    isMuted: false,
                    onReady: {
                        trailerReady = true
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
                        // Trailer finished playing, advance to next
                        DispatchQueue.main.async {
                            showTrailer = false
                            isPlayingTrailer = false
                            onTrailerEnded?()
                        }
                    }
                )
                .frame(width: width, height: 400)
                .clipped()
                .transition(.opacity)
            }
            
            // Gradient overlay (lighter when video is playing)
            LinearGradient(
                colors: [.clear, .black.opacity(shouldShowTrailer ? 0.5 : 0.7), .black.opacity(shouldShowTrailer ? 0.7 : 0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Content
            VStack(alignment: .leading, spacing: 12) {
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
                
                // Title
                Text(item.displayTitle)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                
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
                
                // Overview (hide when trailer is playing)
                if !shouldShowTrailer, let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: isCurrentSlide) { _, newValue in
            if !newValue {
                // Stop trailer when sliding away
                stopTrailer()
            } else if autoPlayEnabled && trailer != nil && !trailerFailed {
                // Auto-start trailer when sliding to this item (with delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if isCurrentSlide && !trailerFailed {
                        startTrailer()
                    }
                }
            }
        }
        .onAppear {
            // Reset states when appearing
            trailerFailed = false
            trailerReady = false
            trailerKey = ""
            
            // Start trailer if this is the first slide and autoplay is enabled
            if isCurrentSlide && autoPlayEnabled && trailer != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if isCurrentSlide && !trailerFailed {
                        startTrailer()
                    }
                }
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
        
        // Only load if video key changed
        guard context.coordinator.currentVideoKey != videoKey else { return }
        context.coordinator.currentVideoKey = videoKey
        context.coordinator.hasErrored = false
        
        loadYouTubePlayer(webView: webView)
    }
    
    private func loadYouTubePlayer(webView: WKWebView) {
        let sanitizedKey = videoKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? videoKey
        let autoPlayValue = autoPlay ? 1 : 0
        let muteValue = isMuted ? 1 : 0
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; overflow: hidden; background: #000; }
                #player-wrapper {
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
                .loading {
                    position: absolute;
                    top: 50%;
                    left: 50%;
                    transform: translate(-50%, -50%);
                    color: #fff;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    text-align: center;
                    z-index: 10;
                }
                .spinner {
                    width: 40px;
                    height: 40px;
                    border: 3px solid rgba(255,255,255,0.3);
                    border-top-color: #fff;
                    border-radius: 50%;
                    animation: spin 1s linear infinite;
                    margin: 0 auto 10px;
                }
                @keyframes spin { to { transform: rotate(360deg); } }
                .hidden { display: none; }
            </style>
        </head>
        <body>
            <div id="loading" class="loading">
                <div class="spinner"></div>
                <div>Loading trailer...</div>
            </div>
            <div id="player-wrapper">
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
                
                function onYouTubeIframeAPIReady() {
                    player = new YT.Player('player', {
                        videoId: '\(sanitizedKey)',
                        playerVars: {
                            'autoplay': \(autoPlayValue),
                            'mute': \(muteValue),
                            'controls': 0,
                            'disablekb': 1,
                            'fs': 0,
                            'iv_load_policy': 3,
                            'modestbranding': 1,
                            'playsinline': 1,
                            'rel': 0,
                            'showinfo': 0,
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
                
                function onPlayerReady(event) {
                    document.getElementById('loading').classList.add('hidden');
                    
                    if (!hasNotifiedReady) {
                        hasNotifiedReady = true;
                        try {
                            window.webkit.messageHandlers.playerReady.postMessage('ready');
                        } catch(e) {}
                    }
                    
                    if (\(autoPlayValue) === 1) {
                        event.target.playVideo();
                    }
                }
                
                function onPlayerStateChange(event) {
                    try {
                        window.webkit.messageHandlers.playerStateChange.postMessage(event.data);
                    } catch(e) {}
                    
                    // YT.PlayerState.ENDED = 0
                    if (event.data === 0 && !hasNotifiedEnded) {
                        hasNotifiedEnded = true;
                        try {
                            window.webkit.messageHandlers.playerEnded.postMessage('ended');
                        } catch(e) {}
                    }
                }
                
                function onPlayerError(event) {
                    if (hasNotifiedError) return;
                    hasNotifiedError = true;
                    
                    var errorMsg = 'Unknown error';
                    switch(event.data) {
                        case 2: errorMsg = 'Invalid video ID'; break;
                        case 5: errorMsg = 'HTML5 player error'; break;
                        case 100: errorMsg = 'Video not found'; break;
                        case 101:
                        case 150: errorMsg = 'Embedding not allowed'; break;
                    }
                    
                    try {
                        window.webkit.messageHandlers.playerError.postMessage(errorMsg);
                    } catch(e) {}
                }
                
                // Fallback timeout
                setTimeout(function() {
                    if (!hasNotifiedReady && !hasNotifiedError) {
                        hasNotifiedError = true;
                        try {
                            window.webkit.messageHandlers.playerError.postMessage('Timeout loading player');
                        } catch(e) {}
                    }
                }, 15000);
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

#Preview {
    HeroCarouselView(items: [], onItemTap: { _ in })
}
