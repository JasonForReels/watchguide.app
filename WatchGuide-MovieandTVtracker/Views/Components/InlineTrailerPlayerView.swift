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
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        webView.isUserInteractionEnabled = false // Disable user interaction - we control via overlay
        
        context.coordinator.webView = webView
        
        let html = generateHTML(videoKey: videoKey)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Handle mute/unmute changes
        if isMuted {
            webView.evaluateJavaScript("muteVideo();", completionHandler: nil)
        } else {
            webView.evaluateJavaScript("unmuteVideo();", completionHandler: nil)
        }
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
                        'origin': 'https://www.youtube.com',
                        'loop': 1,
                        'playlist': '\(videoKey)'
                    },
                    events: {
                        'onReady': onPlayerReady,
                        'onStateChange': onPlayerStateChange
                    }
                });
            }
            
            function onPlayerReady(event) {
                event.target.mute();
                event.target.playVideo();
            }
            
            function onPlayerStateChange(event) {
                if (event.data == YT.PlayerState.PLAYING) {
                    window.webkit.messageHandlers.playerState.postMessage('playing');
                } else if (event.data == YT.PlayerState.ENDED) {
                    window.webkit.messageHandlers.playerState.postMessage('ended');
                } else if (event.data == YT.PlayerState.PAUSED) {
                    window.webkit.messageHandlers.playerState.postMessage('paused');
                }
            }
            
            function muteVideo() {
                if (player && player.mute) { player.mute(); }
            }
            
            function unmuteVideo() {
                if (player && player.unMute) { player.unMute(); }
            }
            
            function pauseVideo() {
                if (player && player.pauseVideo) { player.pauseVideo(); }
            }
            
            function playVideo() {
                if (player && player.playVideo) { player.playVideo(); }
            }
        </script>
        </body>
        </html>
        """
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: InlineTrailerPlayerView
        weak var webView: WKWebView?
        
        init(_ parent: InlineTrailerPlayerView) {
            self.parent = parent
            super.init()
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Add message handler for player state
            webView.configuration.userContentController.add(self, name: "playerState")
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let state = message.body as? String else { return }
            DispatchQueue.main.async {
                switch state {
                case "playing":
                    self.parent.isPlaying = true
                case "ended":
                    self.parent.isPlaying = false
                case "paused":
                    self.parent.isPlaying = false
                default:
                    break
                }
            }
        }
    }
}
