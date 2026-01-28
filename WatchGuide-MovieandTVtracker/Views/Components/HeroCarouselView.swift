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

// MARK: - YouTube Player View with Multiple Proxy Fallback
struct YouTubePlayerView: UIViewRepresentable {
    let videoKey: String
    var autoPlay: Bool = false
    var isMuted: Bool = false
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?
    var onEnded: (() -> Void)?
    
    // Multiple Invidious/Piped proxies to try in order
    static let proxyURLs = [
        "https://inv.nadeko.net",
        "https://invidious.jing.rocks",
        "https://yewtu.be",
        "https://vid.puffyan.us",
        "https://invidious.nerdvpn.de"
    ]
    
    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "playerReady")
        contentController.add(context.coordinator, name: "playerError")
        contentController.add(context.coordinator, name: "playerStateChange")
        contentController.add(context.coordinator, name: "playerEnded")
        contentController.add(context.coordinator, name: "tryNextProxy")
        
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
        // Validate video key before loading
        guard !videoKey.isEmpty else {
            DispatchQueue.main.async {
                self.onError?("Invalid video key")
            }
            return
        }
        
        // Only load if video key changed
        guard context.coordinator.currentVideoKey != videoKey else { return }
        context.coordinator.currentVideoKey = videoKey
        context.coordinator.currentProxyIndex = 0
        context.coordinator.webView = webView
        context.coordinator.hasErrored = false
        
        loadWithProxy(webView: webView, proxyIndex: 0, context: context)
    }
    
    private func loadWithProxy(webView: WKWebView, proxyIndex: Int, context: Context) {
        let muteParam = isMuted ? 1 : 0
        let autoPlayParam = autoPlay ? 1 : 0
        
        // Sanitize video key to prevent injection
        let sanitizedKey = videoKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? videoKey
        let proxiesJSON = Self.proxyURLs.map { "\"\($0)\"" }.joined(separator: ",")
        
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
                .loading { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); color: #fff; font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; z-index: 10; }
                .spinner { width: 40px; height: 40px; border: 3px solid rgba(255,255,255,0.3); border-top-color: #fff; border-radius: 50%; animation: spin 1s linear infinite; margin: 0 auto 10px; }
                @keyframes spin { to { transform: rotate(360deg); } }
                .error-container { display: none; position: absolute; top: 0; left: 0; width: 100%; height: 100%; background: #000; color: #fff; justify-content: center; align-items: center; flex-direction: column; font-family: -apple-system, BlinkMacSystemFont, sans-serif; z-index: 20; }
                .error-container.show { display: flex; }
                .proxy-status { font-size: 11px; color: rgba(255,255,255,0.5); margin-top: 8px; }
            </style>
        </head>
        <body>
            <div id="loading" class="loading">
                <div class="spinner"></div>
                <div>Loading trailer...</div>
                <div id="proxy-status" class="proxy-status"></div>
            </div>
            <div id="player-container">
                <iframe id="player" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen></iframe>
            </div>
            <div id="error" class="error-container">
                <p>Trailer unavailable</p>
            </div>
            <script>
                var proxies = [\(proxiesJSON)];
                var currentProxyIndex = \(proxyIndex);
                var videoKey = '\(sanitizedKey)';
                var autoPlay = \(autoPlayParam);
                var mute = \(muteParam);
                var hasNotifiedReady = false;
                var hasNotifiedError = false;
                var hasEnded = false;
                var loadTimeout;
                var proxyTimeout;
                
                function updateStatus(msg) {
                    var el = document.getElementById('proxy-status');
                    if (el) el.textContent = msg;
                }
                
                function showError(msg) {
                    if (hasNotifiedError) return;
                    hasNotifiedError = true;
                    
                    var playerContainer = document.getElementById('player-container');
                    var loading = document.getElementById('loading');
                    var error = document.getElementById('error');
                    
                    if (playerContainer) playerContainer.style.display = 'none';
                    if (loading) loading.style.display = 'none';
                    if (error) error.classList.add('show');
                    
                    try {
                        window.webkit.messageHandlers.playerError.postMessage(msg || 'Unknown error');
                    } catch(e) {
                        console.error('Failed to send error message:', e);
                    }
                }
                
                function tryProxy(index) {
                    if (hasNotifiedError) return;
                    
                    if (index >= proxies.length) {
                        showError('All proxies failed');
                        return;
                    }
                    
                    currentProxyIndex = index;
                    var proxy = proxies[index];
                    updateStatus('Trying server ' + (index + 1) + '/' + proxies.length + '...');
                    
                    var player = document.getElementById('player');
                    if (!player) {
                        showError('Player element not found');
                        return;
                    }
                    
                    try {
                        player.src = proxy + '/embed/' + videoKey + '?autoplay=' + autoPlay + '&mute=' + mute + '&quality=hd720&local=true';
                    } catch(e) {
                        console.error('Failed to set player src:', e);
                        tryProxy(index + 1);
                        return;
                    }
                    
                    // Set timeout for this proxy - if no load in 8 seconds, try next
                    clearTimeout(proxyTimeout);
                    proxyTimeout = setTimeout(function() {
                        if (!hasNotifiedReady && !hasNotifiedError) {
                            console.log('Proxy ' + index + ' timed out, trying next...');
                            tryProxy(index + 1);
                        }
                    }, 8000);
                }
                
                var player = document.getElementById('player');
                if (player) {
                    player.onload = function() {
                        clearTimeout(proxyTimeout);
                        var loading = document.getElementById('loading');
                        if (loading) loading.style.display = 'none';
                        
                        if (!hasNotifiedReady && !hasNotifiedError) {
                            hasNotifiedReady = true;
                            try {
                                window.webkit.messageHandlers.playerReady.postMessage('ready');
                            } catch(e) {
                                console.error('Failed to send ready message:', e);
                            }
                        }
                        clearTimeout(loadTimeout);
                    };
                    
                    player.onerror = function(e) {
                        clearTimeout(proxyTimeout);
                        console.error('Player error:', e);
                        tryProxy(currentProxyIndex + 1);
                    };
                }
                
                // Overall timeout - if nothing works in 25 seconds, give up
                loadTimeout = setTimeout(function() {
                    if (!hasNotifiedReady && !hasNotifiedError) {
                        showError('Timeout');
                    }
                }, 25000);
                
                // Estimate video end based on typical trailer length (2.5 minutes)
                setTimeout(function() {
                    if (!hasEnded && hasNotifiedReady && !hasNotifiedError) {
                        hasEnded = true;
                        try {
                            window.webkit.messageHandlers.playerEnded.postMessage('ended');
                        } catch(e) {
                            console.error('Failed to send ended message:', e);
                        }
                    }
                }, 150000);
                
                // Start with first proxy
                tryProxy(0);
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: URL(string: Self.proxyURLs[0]))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onError: onError, onEnded: onEnded)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var currentVideoKey: String?
        var currentProxyIndex: Int = 0
        var webView: WKWebView?
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
            if message.name == "playerReady" {
                DispatchQueue.main.async {
                    self.onReady?()
                }
            } else if message.name == "playerError", let errorMsg = message.body as? String {
                guard !hasErrored else { return }
                hasErrored = true
                DispatchQueue.main.async {
                    self.onError?(errorMsg)
                }
            } else if message.name == "playerEnded" {
                DispatchQueue.main.async {
                    self.onEnded?()
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Don't call onReady here - wait for JavaScript callback
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
                self.onError?("Provisional navigation failed: \(error.localizedDescription)")
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
