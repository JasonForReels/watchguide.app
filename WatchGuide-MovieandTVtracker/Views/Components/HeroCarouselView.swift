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
                    
                    // Find the best trailer (official trailer preferred)
                    let trailer = videos.results
                        .filter { $0.site.lowercased() == "youtube" && ($0.type == "Trailer" || $0.type == "Teaser") }
                        .sorted { v1, v2 in
                            // Prefer official trailers
                            if v1.official == true && v2.official != true { return true }
                            if v2.official == true && v1.official != true { return false }
                            // Then prefer "Trailer" over "Teaser"
                            if v1.type == "Trailer" && v2.type != "Trailer" { return true }
                            return false
                        }
                        .first
                    
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
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Video or Backdrop
            if showTrailer && !trailerFailed, let trailer = trailer, autoPlayEnabled && isCurrentSlide {
                YouTubePlayerView(
                    videoKey: trailer.key,
                    autoPlay: true,
                    isMuted: false,
                    onReady: {
                        trailerReady = true
                    },
                    onError: { error in
                        print("Trailer error: \(error)")
                        trailerFailed = true
                        showTrailer = false
                        isPlayingTrailer = false
                    },
                    onEnded: {
                        // Trailer finished playing, advance to next
                        showTrailer = false
                        isPlayingTrailer = false
                        onTrailerEnded?()
                    }
                )
                .frame(width: width, height: 400)
                .clipped()
                .transition(.opacity)
            } else {
                // Backdrop image
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
                .frame(width: width, height: 400)
                .clipped()
            }
            
            // Gradient overlay (lighter when video is playing)
            LinearGradient(
                colors: [.clear, .black.opacity(showTrailer && !trailerFailed ? 0.5 : 0.7), .black.opacity(showTrailer && !trailerFailed ? 0.7 : 0.9)],
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
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showTrailer = true
                                isPlayingTrailer = true
                            }
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
                if !showTrailer || trailerFailed, let overview = item.overview, !overview.isEmpty {
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
                showTrailer = false
            } else if autoPlayEnabled && trailer != nil && !trailerFailed {
                // Auto-start trailer when sliding to this item (with delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if isCurrentSlide && !trailerFailed {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showTrailer = true
                            isPlayingTrailer = true
                        }
                    }
                }
            }
        }
        .onAppear {
            // Reset failed state when appearing
            trailerFailed = false
            
            // Start trailer if this is the first slide and autoplay is enabled
            if isCurrentSlide && autoPlayEnabled && trailer != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if isCurrentSlide && !trailerFailed {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showTrailer = true
                            isPlayingTrailer = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - YouTube Player View
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
        contentController.add(context.coordinator, name: "playerStateChange")
        contentController.add(context.coordinator, name: "playerEnded")
        
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences = preferences
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.configuration.allowsAirPlayForMediaPlayback = true
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only load if video key changed
        guard context.coordinator.currentVideoKey != videoKey else { return }
        context.coordinator.currentVideoKey = videoKey
        
        let muteParam = isMuted ? 1 : 0
        let autoPlayParam = autoPlay ? 1 : 0
        
        // Use Invidious proxy (inv.nadeko.net) which reliably bypasses YouTube embedding restrictions
        // Invidious is an open-source alternative YouTube frontend that allows unrestricted embedding
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; overflow: hidden; background: #000; }
                #player-container { position: absolute; top: 50%; left: 50%; width: 177.78vh; height: 100vh; min-width: 100%; min-height: 56.25vw; transform: translate(-50%, -50%); }
                #player { width: 100%; height: 100%; border: none; background: #000; }
                .loading { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); color: #fff; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
                .spinner { width: 40px; height: 40px; border: 3px solid rgba(255,255,255,0.3); border-top-color: #fff; border-radius: 50%; animation: spin 1s linear infinite; margin: 0 auto 10px; }
                @keyframes spin { to { transform: rotate(360deg); } }
                .error-container { display: none; position: absolute; top: 0; left: 0; width: 100%; height: 100%; background: #000; color: #fff; justify-content: center; align-items: center; flex-direction: column; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
                .error-container.show { display: flex; }
            </style>
        </head>
        <body>
            <div id="loading" class="loading">
                <div class="spinner"></div>
                <div>Loading trailer...</div>
            </div>
            <div id="player-container">
                <iframe id="player" 
                    src="https://inv.nadeko.net/embed/\(videoKey)?autoplay=\(autoPlayParam)&mute=\(muteParam)&quality=hd720&local=true" 
                    allow="autoplay; fullscreen; picture-in-picture; encrypted-media" 
                    allowfullscreen>
                </iframe>
            </div>
            <div id="error" class="error-container">
                <p>Trailer unavailable</p>
            </div>
            <script>
                var hasNotifiedReady = false;
                var hasEnded = false;
                var loadTimeout;
                
                // Hide loading when iframe loads
                document.getElementById('player').onload = function() {
                    document.getElementById('loading').style.display = 'none';
                    if (!hasNotifiedReady) {
                        hasNotifiedReady = true;
                        try {
                            window.webkit.messageHandlers.playerReady.postMessage('ready');
                        } catch(e) {}
                    }
                    clearTimeout(loadTimeout);
                };
                
                document.getElementById('player').onerror = function() {
                    document.getElementById('player-container').style.display = 'none';
                    document.getElementById('loading').style.display = 'none';
                    document.getElementById('error').classList.add('show');
                    try {
                        window.webkit.messageHandlers.playerError.postMessage('Error loading video');
                    } catch(e) {}
                };
                
                // Timeout for loading - if not loaded in 8 seconds, show error
                loadTimeout = setTimeout(function() {
                    if (!hasNotifiedReady) {
                        // Try to notify ready anyway - video might be playing
                        hasNotifiedReady = true;
                        document.getElementById('loading').style.display = 'none';
                        try {
                            window.webkit.messageHandlers.playerReady.postMessage('ready');
                        } catch(e) {}
                    }
                }, 8000);
                
                // Estimate video end based on typical trailer length (2-3 minutes)
                setTimeout(function() {
                    if (!hasEnded) {
                        hasEnded = true;
                        try {
                            window.webkit.messageHandlers.playerEnded.postMessage('ended');
                        } catch(e) {}
                    }
                }, 150000); // 2.5 minutes fallback
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: URL(string: "https://inv.nadeko.net"))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onError: onError, onEnded: onEnded)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var currentVideoKey: String?
        var onReady: (() -> Void)?
        var onError: ((String) -> Void)?
        var onEnded: (() -> Void)?
        
        init(onReady: (() -> Void)?, onError: ((String) -> Void)?, onEnded: (() -> Void)?) {
            self.onReady = onReady
            self.onError = onError
            self.onEnded = onEnded
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "playerReady" {
                DispatchQueue.main.async {
                    self.onReady?()
                }
            } else if message.name == "playerError", let errorMsg = message.body as? String {
                DispatchQueue.main.async {
                    self.onError?(errorMsg)
                }
            } else if message.name == "playerEnded" {
                DispatchQueue.main.async {
                    self.onEnded?()
                }
            }
            // playerStateChange can be used for debugging if needed
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Don't call onReady here - wait for YouTube API callback
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError?(error.localizedDescription)
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError?(error.localizedDescription)
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
