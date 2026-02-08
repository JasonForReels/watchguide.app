//
//  YouTubePlayerView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import WebKit

struct YouTubePlayerView: UIViewRepresentable {
    let videoKey: String
    var autoPlay: Bool = false
    var isMuted: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Share process pool to reduce GPU/WebContent process spawning
        config.processPool = YouTubePlayerProcessPool.shared

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator

        context.coordinator.loadedVideoKey = videoKey
        context.coordinator.autoPlay = autoPlay
        context.coordinator.isMuted = isMuted
        context.coordinator.webView = webView

        // Defer load to allow view hierarchy attachment (avoids sandbox extension errors)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.loadEmbed(into: webView, videoKey: videoKey, autoPlay: autoPlay, isMuted: isMuted, coordinator: context.coordinator)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedVideoKey != videoKey else { return }
        context.coordinator.loadedVideoKey = videoKey
        context.coordinator.autoPlay = autoPlay
        context.coordinator.isMuted = isMuted
        context.coordinator.retryCount = 0
        Self.loadEmbed(into: webView, videoKey: videoKey, autoPlay: autoPlay, isMuted: isMuted, coordinator: context.coordinator)
    }

    static func loadEmbed(into webView: WKWebView, videoKey: String, autoPlay: Bool, isMuted: Bool, coordinator: Coordinator) {
        let autoplayParam = autoPlay ? "1" : "0"
        let muteParam = isMuted ? "1" : "0"

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"/>
        <style>
          *{margin:0;padding:0}
          html,body{width:100%;height:100%;background:#000;overflow:hidden}
          iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}
        </style>
        </head>
        <body>
        <iframe
          src="https://www.youtube.com/embed/\(videoKey)?playsinline=1&autoplay=\(autoplayParam)&mute=\(muteParam)&rel=0&modestbranding=1&controls=1&iv_load_policy=3&enablejsapi=1&origin=https://www.youtube.com"
          allow="autoplay; encrypted-media; picture-in-picture"
          allowfullscreen>
        </iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        coordinator.retryCount = 0
    }

    private final class YouTubePlayerProcessPool {
        static let shared = WKProcessPool()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var loadedVideoKey: String = ""
        var autoPlay: Bool = false
        var isMuted: Bool = false
        weak var webView: WKWebView?
        var retryCount = 0
        private let maxRetries = 3

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let host = url.host?.lowercased() ?? ""
                if navigationAction.targetFrame?.isMainFrame == true &&
                   !host.isEmpty &&
                   !host.contains("youtube.com") && !host.contains("youtube-nocookie.com") &&
                   !host.contains("google.com") &&
                   url.scheme != "about" {
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            retryLoad(into: webView, delay: Double(retryCount + 1) * 0.8)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            retryLoad(into: webView, delay: Double(retryCount + 1) * 1.0)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            retryLoad(into: webView, delay: Double(retryCount + 1) * 1.2)
        }

        private func retryLoad(into webView: WKWebView, delay: Double) {
            guard retryCount < maxRetries else { return }
            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                YouTubePlayerView.loadEmbed(
                    into: webView,
                    videoKey: self.loadedVideoKey,
                    autoPlay: self.autoPlay,
                    isMuted: self.isMuted,
                    coordinator: self
                )
            }
        }
    }
}

#if DEBUG
#Preview {
    YouTubePlayerView(videoKey: "dQw4w9WgXcQ", autoPlay: false, isMuted: true)
        .frame(height: 240)
}
#endif

