//
//  YouTubePlayerView.swift
//  WatchGuide-MovieandTVtracker
//
//  Used in the AI trailer sheet and anywhere a full-controls YouTube
//  player is needed.  Always starts MUTED; unmute via user gesture.

import SwiftUI
import WebKit

// Shared across the app – avoids spawning extra GPU/WebContent processes.
private let sharedProcessPool = WKProcessPool()

struct YouTubePlayerView: UIViewRepresentable {
    let videoKey: String
    var autoPlay: Bool = false
    var isMuted: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // ── WebKit autoplay policy ──
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.processPool = sharedProcessPool

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator

        context.coordinator.loadedVideoKey = videoKey
        context.coordinator.isMuted = isMuted

        // Load immediately on main thread – always muted first
        loadEmbed(into: webView, videoKey: videoKey, autoPlay: autoPlay, muted: true)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator

        if coord.loadedVideoKey != videoKey {
            coord.loadedVideoKey = videoKey
            coord.isMuted = isMuted
            coord.retryCount = 0
            loadEmbed(into: webView, videoKey: videoKey, autoPlay: autoPlay, muted: true)
            return
        }

        // Mute / unmute via postMessage to the iframe (enablejsapi=1)
        if coord.isMuted != isMuted {
            coord.isMuted = isMuted
            let cmd = isMuted ? "mute" : "unMute"
            let js = "document.querySelector('iframe').contentWindow.postMessage('{\"event\":\"command\",\"func\":\"\(cmd)\",\"args\":\"\"}','*');"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // Plain <iframe> embed – NO YouTube IFrame Player API JS library.
    // Starts muted so WebKit's autoplay policy is satisfied.
    // Controls are shown (controls=1) for the full player experience.
    // enablejsapi=1 lets us postMessage mute/unMute from Swift.
    // ──────────────────────────────────────────────────────────────────
    private func loadEmbed(into webView: WKWebView, videoKey: String, autoPlay: Bool, muted: Bool) {
        let autoplayParam = autoPlay ? 1 : 0
        let muteParam = muted ? 1 : 0
        let embedURL = "https://www.youtube.com/embed/\(videoKey)?playsinline=1&autoplay=\(autoplayParam)&mute=\(muteParam)&controls=1&modestbranding=1&rel=0&iv_load_policy=3&enablejsapi=1"

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>*{margin:0;padding:0}html,body{width:100%;height:100%;background:#000;overflow:hidden}iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style>
        </head>
        <body>
        <iframe src="\(embedURL)"
                allow="autoplay; encrypted-media"
                allowfullscreen
                playsinline
                muted
                autoplay></iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate {
        var loadedVideoKey = ""
        var isMuted = true
        var retryCount = 0
        private let maxRetries = 2

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let host = url.host?.lowercased() ?? ""
                if navigationAction.targetFrame?.isMainFrame == true &&
                   !host.isEmpty &&
                   !host.contains("youtube.com") &&
                   !host.contains("youtube-nocookie.com") &&
                   !host.contains("google.com") &&
                   !host.contains("googleapis.com") &&
                   url.scheme != "about" {
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            retryIfNeeded(webView: webView)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            retryIfNeeded(webView: webView)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            retryIfNeeded(webView: webView)
        }

        private func retryIfNeeded(webView: WKWebView) {
            guard retryCount < maxRetries else { return }
            retryCount += 1
            let delay = Double(retryCount) * 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                let embedURL = "https://www.youtube.com/embed/\(self.loadedVideoKey)?playsinline=1&autoplay=1&mute=1&controls=1&modestbranding=1&rel=0&iv_load_policy=3&enablejsapi=1"
                let html = """
                <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><style>*{margin:0;padding:0}html,body{width:100%;height:100%;background:#000;overflow:hidden}iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style></head><body><iframe src="\(embedURL)" allow="autoplay; encrypted-media" allowfullscreen playsinline muted autoplay></iframe></body></html>
                """
                webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
            }
        }
    }
}

#if DEBUG
#Preview {
    YouTubePlayerView(videoKey: "dQw4w9WgXcQ", autoPlay: true, isMuted: true)
        .frame(height: 240)
}
#endif

