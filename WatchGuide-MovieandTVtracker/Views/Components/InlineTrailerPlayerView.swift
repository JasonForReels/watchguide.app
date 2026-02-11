//
//  InlineTrailerPlayerView.swift
//  WatchGuide-MovieandTVtracker
//
//  Inline YouTube trailer player for the hero carousel.
//  Uses WKWebView with YouTube IFrame API for muted autoplay.
//

import SwiftUI
import WebKit

struct InlineTrailerPlayerView: UIViewRepresentable {
    let videoKey: String
    @Binding var isMuted: Bool
    @Binding var isPlaying: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        // Register message handler BEFORE creating the web view
        contentController.add(context.coordinator, name: "playerState")
        
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        webView.isUserInteractionEnabled = false
        
        context.coordinator.webView = webView
        
        let html = generateHTML(videoKey: videoKey)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let currentMuted = isMuted
        if currentMuted != context.coordinator.lastKnownMuteState {
            context.coordinator.lastKnownMuteState = currentMuted
            if currentMuted {
                webView.evaluateJavaScript("muteVideo();", completionHandler: nil)
            } else {
                webView.evaluateJavaScript("unmuteVideo();", completionHandler: nil)
            }
        }
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "playerState")
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
    }
    
    private func generateHTML(videoKey: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
            * { margin: 0; padding: 0; }
            html, body { width: 100%; height: 100%; overflow: hidden; background: #000; }
            #player-container {
                position: absolute;
                top: 50%; left: 50%;
                width: 300%; height: 300%;
                transform: translate(-50%, -50%);
            }
            #player {
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
            var playerReady = false;
            
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
                        'disablekb': 1,
                        'fs': 0,
                        'cc_load_policy': 0,
                        'loop': 1,
                        'playlist': '\(videoKey)'
                    },
                    events: {
                        'onReady': onPlayerReady,
                        'onStateChange': onPlayerStateChange,
                        'onError': onPlayerError
                    }
                });
            }
            
            function onPlayerReady(event) {
                playerReady = true;
                event.target.mute();
                event.target.playVideo();
            }
            
            function onPlayerStateChange(event) {
                try {
                    if (event.data == YT.PlayerState.PLAYING) {
                        window.webkit.messageHandlers.playerState.postMessage('playing');
                    } else if (event.data == YT.PlayerState.ENDED) {
                        window.webkit.messageHandlers.playerState.postMessage('ended');
                    } else if (event.data == YT.PlayerState.PAUSED) {
                        window.webkit.messageHandlers.playerState.postMessage('paused');
                    } else if (event.data == YT.PlayerState.BUFFERING) {
                        window.webkit.messageHandlers.playerState.postMessage('buffering');
                    }
                } catch(e) {}
            }
            
            function onPlayerError(event) {
                try {
                    window.webkit.messageHandlers.playerState.postMessage('error');
                } catch(e) {}
            }
            
            function muteVideo() {
                if (playerReady && player && player.mute) { player.mute(); }
            }
            
            function unmuteVideo() {
                if (playerReady && player && player.unMute) { player.unMute(); }
            }
            
            function pauseVideo() {
                if (playerReady && player && player.pauseVideo) { player.pauseVideo(); }
            }
            
            function playVideo() {
                if (playerReady && player && player.playVideo) { player.playVideo(); }
            }
        </script>
        </body>
        </html>
        """
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: InlineTrailerPlayerView
        weak var webView: WKWebView?
        var lastKnownMuteState: Bool = true
        
        init(_ parent: InlineTrailerPlayerView) {
            self.parent = parent
            self.lastKnownMuteState = parent.isMuted
            super.init()
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let state = message.body as? String else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch state {
                case "playing":
                    self.parent.isPlaying = true
                case "ended", "paused", "error":
                    self.parent.isPlaying = false
                case "buffering":
                    break // Keep current state while buffering
                default:
                    break
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("InlineTrailerPlayer navigation failed: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("InlineTrailerPlayer provisional navigation failed: \(error.localizedDescription)")
        }
    }
}
