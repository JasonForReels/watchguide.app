//
//  InAppYouTubePlayer.swift
//  WatchGuide-MovieandTVtracker
//
//  Custom embedded YouTube player using WKWebView + YouTube IFrame Player API.
//  Autoplays muted with a native SwiftUI unmute button overlay.
//  Uses direct YouTube embed URL navigation (not loadHTMLString) to send
//  proper HTTP Referer headers and avoid YouTube Error 153.
//

import SwiftUI
import WebKit

// MARK: - YouTube Player State
class YouTubePlayerState: ObservableObject {
    @Published var isMuted: Bool = true
    @Published var isPlaying: Bool = false
    @Published var isReady: Bool = false
    @Published var hasError: Bool = false
}

// MARK: - WKWebView YouTube Embed Player (navigates to embed URL directly)
struct YouTubeEmbedPlayer: UIViewRepresentable {
    let videoKey: String
    @ObservedObject var playerState: YouTubePlayerState

    func makeCoordinator() -> Coordinator {
        Coordinator(playerState: playerState)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "playerEvent")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        // Allow YouTube inspecting back navigation
        webView.allowsBackForwardNavigationGestures = false

        // Build the embed URL with all required params
        var components = URLComponents(string: "https://www.youtube.com/embed/\(videoKey)")!
        components.queryItems = [
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "mute", value: "1"),
            URLQueryItem(name: "controls", value: "0"),
            URLQueryItem(name: "showinfo", value: "0"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "modestbranding", value: "1"),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "iv_load_policy", value: "3"),
            URLQueryItem(name: "fs", value: "0"),
            URLQueryItem(name: "disablekb", value: "1"),
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "origin", value: "https://www.youtube.com"),
            URLQueryItem(name: "widget_referrer", value: "https://www.youtube.com"),
        ]

        if let url = components.url {
            let request = URLRequest(url: url)
            webView.load(request)
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.syncMuteState(playerState.isMuted)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var playerState: YouTubePlayerState
        weak var webView: WKWebView?
        private var lastSentMuteState: Bool? = nil
        private var injectedAPI = false
        private var readyCheckTimer: Timer?

        init(playerState: YouTubePlayerState) {
            self.playerState = playerState
        }

        deinit {
            readyCheckTimer?.invalidate()
        }

        func syncMuteState(_ isMuted: Bool) {
            guard lastSentMuteState != isMuted else { return }
            lastSentMuteState = isMuted
            let js = isMuted
                ? "try { document.querySelector('video').muted = true; } catch(e) {}"
                : "try { document.querySelector('video').muted = false; } catch(e) {}"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        // MARK: WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let event = dict["event"] as? String else { return }

            DispatchQueue.main.async { [weak self] in
                switch event {
                case "ready":
                    self?.playerState.isReady = true
                case "playing":
                    self?.playerState.isPlaying = true
                    if !(self?.playerState.isReady ?? false) {
                        self?.playerState.isReady = true
                    }
                case "paused":
                    self?.playerState.isPlaying = false
                case "error":
                    self?.playerState.hasError = true
                default:
                    break
                }
            }
        }

        // MARK: WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !injectedAPI else { return }
            injectedAPI = true

            // Inject a script that listens to the HTML5 <video> element events
            // and reports them back to native via messageHandler.
            let js = """
            (function() {
                function setup() {
                    var video = document.querySelector('video');
                    if (!video) return false;
                    video.addEventListener('playing', function() {
                        window.webkit.messageHandlers.playerEvent.postMessage({event: 'playing'});
                    });
                    video.addEventListener('pause', function() {
                        window.webkit.messageHandlers.playerEvent.postMessage({event: 'paused'});
                    });
                    video.addEventListener('ended', function() {
                        video.currentTime = 0;
                        video.play();
                    });
                    video.addEventListener('error', function() {
                        window.webkit.messageHandlers.playerEvent.postMessage({event: 'error'});
                    });
                    window.webkit.messageHandlers.playerEvent.postMessage({event: 'ready'});
                    return true;
                }
                if (!setup()) {
                    var observer = new MutationObserver(function(mutations, obs) {
                        if (setup()) { obs.disconnect(); }
                    });
                    observer.observe(document.body, {childList: true, subtree: true});
                    setTimeout(function() { observer.disconnect(); }, 15000);
                }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)

            // Also start a timer to poll for the video element as a backup
            startReadyCheck()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            // Allow the initial embed URL and YouTube internal navigations
            if let host = url?.host?.lowercased(),
               (host.contains("youtube.com") || host.contains("youtube-nocookie.com") ||
                host.contains("ytimg.com") || host.contains("google.com") ||
                host.contains("googleapis.com") || host.contains("googlevideo.com") ||
                host.contains("gstatic.com") || host.contains("ggpht.com")) {
                decisionHandler(.allow)
                return
            }
            // Allow about:blank and data URLs
            if let scheme = url?.scheme, (scheme == "about" || scheme == "data") {
                decisionHandler(.allow)
                return
            }
            // Block everything else (user-initiated external navigations)
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.playerState.hasError = true
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.playerState.hasError = true
            }
        }

        private func startReadyCheck() {
            var attempts = 0
            readyCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                attempts += 1
                guard let self, let wv = self.webView else {
                    timer.invalidate()
                    return
                }
                if self.playerState.isReady {
                    timer.invalidate()
                    return
                }
                if attempts > 10 {
                    timer.invalidate()
                    // After 10 seconds, if no video found, mark as error
                    if !self.playerState.isReady {
                        DispatchQueue.main.async {
                            self.playerState.hasError = true
                        }
                    }
                    return
                }
                // Check if a video element exists and is playing
                let checkJS = """
                (function() {
                    var v = document.querySelector('video');
                    if (v && v.readyState >= 2) return 'ready';
                    return 'waiting';
                })();
                """
                wv.evaluateJavaScript(checkJS) { result, _ in
                    if let status = result as? String, status == "ready" {
                        DispatchQueue.main.async {
                            self.playerState.isReady = true
                        }
                        timer.invalidate()
                    }
                }
            }
        }
    }
}

// MARK: - Embedded Trailer Player View (autoplay muted + custom controls)
struct EmbeddedTrailerPlayer: View {
    let videoKey: String
    let title: String
    var compact: Bool = false
    @StateObject private var playerState = YouTubePlayerState()
    @State private var showControls = true
    @State private var controlsTimer: Timer?

    var body: some View {
        ZStack {
            // Black background while loading
            Color.black

            // YouTube Embed Player (loads embed URL directly for proper Referer)
            YouTubeEmbedPlayer(videoKey: videoKey, playerState: playerState)
                .opacity(playerState.isReady ? 1 : 0)
                .animation(.easeIn(duration: 0.3), value: playerState.isReady)

            // Loading state
            if !playerState.isReady && !playerState.hasError {
                ZStack {
                    // Show thumbnail while loading
                    AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoKey)/maxresdefault.jpg")) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(16.0/9.0, contentMode: .fill)
                        }
                    }

                    Color.black.opacity(0.4)

                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }
            }

            // Error state — fallback to thumbnail with play button
            if playerState.hasError {
                TrailerErrorFallback(videoKey: videoKey, title: title, compact: compact)
            }

            // Custom controls overlay
            if playerState.isReady && !playerState.hasError {
                controlsOverlay
            }
        }
        .aspectRatio(16.0/9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14))
        .onAppear {
            scheduleControlsHide()
        }
        .onDisappear {
            controlsTimer?.invalidate()
        }
    }

    private var controlsOverlay: some View {
        ZStack {
            // Tap area to toggle controls
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                    if showControls {
                        scheduleControlsHide()
                    }
                }

            if showControls {
                // Bottom bar with mute + title
                VStack {
                    Spacer()

                    HStack(spacing: 12) {
                        // Mute/Unmute button
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                playerState.isMuted.toggle()
                            }
                            scheduleControlsHide()
                        } label: {
                            Image(systemName: playerState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }

                        if !compact {
                            Text(title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                        }

                        Spacer()

                        // Type badge
                        Text("TRAILER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.ultraThinMaterial))
                    }
                    .padding(.horizontal, compact ? 8 : 12)
                    .padding(.bottom, compact ? 8 : 10)
                    .padding(.top, 20)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .transition(.opacity)
            }
        }
    }

    private func scheduleControlsHide() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.3)) {
                    showControls = false
                }
            }
        }
    }
}

// MARK: - Error Fallback (thumbnail with play button, opens sheet)
private struct TrailerErrorFallback: View {
    let videoKey: String
    let title: String
    var compact: Bool = false
    @State private var showPlayer = false

    var body: some View {
        ZStack {
            AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoKey)/maxresdefault.jpg")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(16.0/9.0, contentMode: .fill)
                default:
                    Color(.systemGray5)
                }
            }

            Color.black.opacity(0.35)

            Button {
                showPlayer = true
            } label: {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.5))
                        .frame(width: compact ? 40 : 56, height: compact ? 40 : 56)

                    Image(systemName: "play.fill")
                        .font(compact ? .body : .title3)
                        .foregroundColor(.white)
                        .offset(x: 2)
                }
            }
            .sheet(isPresented: $showPlayer) {
                YouTubePlayerSheet(videoKey: videoKey, title: title)
            }
        }
    }
}

// MARK: - Full Screen YouTube Player Sheet (fallback)
struct YouTubePlayerSheet: View {
    let videoKey: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack {
                    Spacer()
                    // Use the same embed player (it gets a fresh WKWebView instance)
                    EmbeddedTrailerPlayer(
                        videoKey: videoKey,
                        title: title
                    )
                    .padding(.horizontal)
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.white.opacity(0.25))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Legacy InAppYouTubePlayer (kept for API compat)
struct InAppYouTubePlayer: View {
    let videoKey: String
    var autoplay: Bool = true

    var body: some View {
        EmbeddedTrailerPlayer(videoKey: videoKey, title: "Trailer")
    }
}
