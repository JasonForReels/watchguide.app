//
//  InAppYouTubePlayer.swift
//  WatchGuide-MovieandTVtracker
//
//  Custom embedded YouTube player using WKWebView + YouTube IFrame Player API.
//  Autoplays muted with a native SwiftUI unmute button overlay.
//
//  Uses loadHTMLString with an https:// baseURL so WKWebView sends
//  a proper HTTP Referer header (required by YouTube since July 2025
//  to avoid Error 153 / "embedder.identity.missing.referrer").
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

// MARK: - WKWebView YouTube Embed Player
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
        contentController.add(context.coordinator, name: "ytEvent")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false

        // Key fix: loadHTMLString with an https baseURL makes WKWebView
        // send a valid Referer header on the iframe sub-request, which is
        // what YouTube checks to allow embed playback.
        let html = Self.buildHTML(videoKey: videoKey)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.syncMuteState(playerState.isMuted)
    }

    // MARK: - HTML Builder (YouTube IFrame Player API)
    private static func buildHTML(videoKey: String) -> String {
        // We use the official YouTube IFrame Player API so we get proper
        // onReady / onStateChange / onError callbacks.  The page has
        // referrerpolicy="strict-origin-when-cross-origin" both as a
        // <meta> tag and on the <iframe> element itself.
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        html,body{width:100%;height:100%;overflow:hidden;background:#000}
        #player{position:absolute;top:0;left:0;width:100%;height:100%}
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script>
        var tag=document.createElement('script');
        tag.src='https://www.youtube.com/iframe_api';
        var fs=document.getElementsByTagName('script')[0];
        fs.parentNode.insertBefore(tag,fs);

        var ytPlayer;
        function onYouTubeIframeAPIReady(){
            ytPlayer=new YT.Player('player',{
                videoId:'\(videoKey)',
                playerVars:{
                    autoplay:1,
                    mute:1,
                    controls:0,
                    showinfo:0,
                    rel:0,
                    modestbranding:1,
                    playsinline:1,
                    iv_load_policy:3,
                    fs:0,
                    disablekb:1,
                    origin:'https://www.youtube.com'
                },
                events:{
                    onReady:function(e){
                        window.webkit.messageHandlers.ytEvent.postMessage({event:'ready'});
                        e.target.playVideo();
                    },
                    onStateChange:function(e){
                        var s=e.data;
                        if(s===1){
                            window.webkit.messageHandlers.ytEvent.postMessage({event:'playing'});
                        }else if(s===2){
                            window.webkit.messageHandlers.ytEvent.postMessage({event:'paused'});
                        }else if(s===0){
                            ytPlayer.seekTo(0);
                            ytPlayer.playVideo();
                        }
                    },
                    onError:function(e){
                        window.webkit.messageHandlers.ytEvent.postMessage({event:'error',code:e.data});
                    }
                }
            });
        }

        function mutePlayer(){if(ytPlayer&&ytPlayer.mute)ytPlayer.mute();}
        function unmutePlayer(){if(ytPlayer&&ytPlayer.unMute)ytPlayer.unMute();}
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var playerState: YouTubePlayerState
        weak var webView: WKWebView?
        private var lastSentMuteState: Bool? = nil
        private var readyTimeoutTimer: Timer?

        init(playerState: YouTubePlayerState) {
            self.playerState = playerState
        }

        deinit {
            readyTimeoutTimer?.invalidate()
        }

        func syncMuteState(_ isMuted: Bool) {
            guard lastSentMuteState != isMuted else { return }
            lastSentMuteState = isMuted
            let js = isMuted ? "mutePlayer();" : "unmutePlayer();"
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
                    self?.readyTimeoutTimer?.invalidate()
                case "playing":
                    self?.playerState.isPlaying = true
                    if !(self?.playerState.isReady ?? false) {
                        self?.playerState.isReady = true
                        self?.readyTimeoutTimer?.invalidate()
                    }
                case "paused":
                    self?.playerState.isPlaying = false
                case "error":
                    self?.playerState.hasError = true
                    self?.readyTimeoutTimer?.invalidate()
                default:
                    break
                }
            }
        }

        // MARK: WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Start a timeout — if the YT API never fires onReady, mark error
            readyTimeoutTimer?.invalidate()
            readyTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !self.playerState.isReady {
                        self.playerState.hasError = true
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // The initial load is about:blank → loadHTMLString, then the
            // iframe navigates to youtube.com.  Allow all YouTube-related
            // domains plus about/data schemes.
            if let url = navigationAction.request.url {
                let scheme = url.scheme?.lowercased() ?? ""
                if scheme == "about" || scheme == "data" {
                    decisionHandler(.allow)
                    return
                }
                if let host = url.host?.lowercased(),
                   host.contains("youtube.com") || host.contains("youtube-nocookie.com") ||
                   host.contains("ytimg.com") || host.contains("google.com") ||
                   host.contains("googleapis.com") || host.contains("googlevideo.com") ||
                   host.contains("gstatic.com") || host.contains("ggpht.com") {
                    decisionHandler(.allow)
                    return
                }
            }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.playerState.hasError = true
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // Don't treat cancellation (e.g. blocked external nav) as fatal
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            DispatchQueue.main.async { [weak self] in
                self?.playerState.hasError = true
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

            // YouTube Embed Player
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

// MARK: - Error Fallback (thumbnail with play button, opens YouTube app/Safari)
private struct TrailerErrorFallback: View {
    let videoKey: String
    let title: String
    var compact: Bool = false

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
                // Open in YouTube app or Safari as last resort
                if let url = URL(string: "https://www.youtube.com/watch?v=\(videoKey)") {
                    UIApplication.shared.open(url)
                }
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
