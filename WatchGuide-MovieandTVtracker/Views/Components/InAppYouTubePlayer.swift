//
//  InAppYouTubePlayer.swift
//  WatchGuide-MovieandTVtracker
//
//  Custom embedded YouTube player using WKWebView + YouTube IFrame Player API.
//  Autoplays muted with a native SwiftUI unmute button overlay.
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

// MARK: - WKWebView YouTube IFrame Player
struct YouTubeIFramePlayer: UIViewRepresentable {
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
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        
        let html = buildPlayerHTML(videoKey: videoKey)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        
        context.coordinator.webView = webView
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Handle mute/unmute from SwiftUI state changes
        context.coordinator.syncMuteState(playerState.isMuted)
    }
    
    private func buildPlayerHTML(videoKey: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
            * { margin: 0; padding: 0; }
            html, body { width: 100%; height: 100%; overflow: hidden; background: #000; }
            #player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script>
            var tag = document.createElement('script');
            tag.src = "https://www.youtube.com/iframe_api";
            var firstScriptTag = document.getElementsByTagName('script')[0];
            firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
            
            var player;
            
            function onYouTubeIframeAPIReady() {
                player = new YT.Player('player', {
                    videoId: '\(videoKey)',
                    playerVars: {
                        'autoplay': 1,
                        'mute': 1,
                        'controls': 0,
                        'showinfo': 0,
                        'rel': 0,
                        'modestbranding': 1,
                        'playsinline': 1,
                        'iv_load_policy': 3,
                        'fs': 0,
                        'disablekb': 1,
                        'origin': 'https://www.youtube.com'
                    },
                    events: {
                        'onReady': onPlayerReady,
                        'onStateChange': onPlayerStateChange,
                        'onError': onPlayerError
                    }
                });
            }
            
            function onPlayerReady(event) {
                event.target.mute();
                event.target.playVideo();
                window.webkit.messageHandlers.playerEvent.postMessage({event: 'ready'});
            }
            
            function onPlayerStateChange(event) {
                if (event.data == YT.PlayerState.PLAYING) {
                    window.webkit.messageHandlers.playerEvent.postMessage({event: 'playing'});
                } else if (event.data == YT.PlayerState.ENDED) {
                    player.seekTo(0);
                    player.playVideo();
                } else if (event.data == YT.PlayerState.PAUSED) {
                    window.webkit.messageHandlers.playerEvent.postMessage({event: 'paused'});
                }
            }
            
            function onPlayerError(event) {
                window.webkit.messageHandlers.playerEvent.postMessage({event: 'error', code: event.data});
            }
            
            function mutePlayer() {
                if (player && player.mute) { player.mute(); }
            }
            
            function unmutePlayer() {
                if (player && player.unMute) { player.unMute(); }
            }
            
            function togglePlay() {
                if (!player) return;
                var state = player.getPlayerState();
                if (state == YT.PlayerState.PLAYING) {
                    player.pauseVideo();
                } else {
                    player.playVideo();
                }
            }
        </script>
        </body>
        </html>
        """
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var playerState: YouTubePlayerState
        weak var webView: WKWebView?
        private var lastSentMuteState: Bool? = nil
        
        init(playerState: YouTubePlayerState) {
            self.playerState = playerState
        }
        
        func syncMuteState(_ isMuted: Bool) {
            guard lastSentMuteState != isMuted else { return }
            lastSentMuteState = isMuted
            let js = isMuted ? "mutePlayer()" : "unmutePlayer()"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let event = dict["event"] as? String else { return }
            
            DispatchQueue.main.async { [weak self] in
                switch event {
                case "ready":
                    self?.playerState.isReady = true
                case "playing":
                    self?.playerState.isPlaying = true
                case "paused":
                    self?.playerState.isPlaying = false
                case "error":
                    self?.playerState.hasError = true
                default:
                    break
                }
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow initial load and YouTube iframe requests
            if navigationAction.navigationType == .other || navigationAction.navigationType == .reload {
                decisionHandler(.allow)
                return
            }
            // Block user-initiated navigations (clicking links inside the player)
            decisionHandler(.cancel)
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
            
            // YouTube IFrame Player
            YouTubeIFramePlayer(videoKey: videoKey, playerState: playerState)
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

// MARK: - Error Fallback (opens Safari sheet)
private struct TrailerErrorFallback: View {
    let videoKey: String
    let title: String
    var compact: Bool = false
    @State private var showSafari = false
    
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
                showSafari = true
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
            .sheet(isPresented: $showSafari) {
                YouTubePlayerSheet(videoKey: videoKey, title: title)
            }
        }
    }
}

// MARK: - Full Screen YouTube Player Sheet (Safari fallback)
struct YouTubePlayerSheet: View {
    let videoKey: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            YouTubeSafariPlayer(videoKey: videoKey)
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            }
            .padding(.top, 12)
            .padding(.leading, 16)
        }
        .background(Color.black)
    }
}

// MARK: - Safari VC wrapper that auto-dismisses when user taps Done
import SafariServices

struct YouTubeSafariPlayer: UIViewControllerRepresentable {
    let videoKey: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let urlString = "https://www.youtube.com/watch?v=\(videoKey)"
        let url = URL(string: urlString) ?? URL(string: "https://www.youtube.com")!
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredBarTintColor = .black
        vc.preferredControlTintColor = .white
        vc.dismissButtonStyle = .done
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            dismiss()
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
