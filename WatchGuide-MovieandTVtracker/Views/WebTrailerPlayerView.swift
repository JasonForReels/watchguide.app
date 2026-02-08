import SwiftUI
import WebKit

// Shared process pool – one for the entire app so iOS doesn't keep
// spawning GPU / WebContent / Networking sub-processes.
private let sharedProcessPool = WKProcessPool()

struct WebTrailerPlayerView: UIViewRepresentable {
    let videoKey: String
    var autoplay: Bool
    var muted: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // ── KEY: WebKit autoplay policy ──
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.processPool = sharedProcessPool

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator

        context.coordinator.currentVideoKey = videoKey
        context.coordinator.currentMuted = muted

        // Load immediately on main thread
        loadEmbed(into: webView, videoKey: videoKey, muted: true)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator

        // Video changed → reload
        if coord.currentVideoKey != videoKey {
            coord.currentVideoKey = videoKey
            coord.currentMuted = muted
            coord.retryCount = 0
            loadEmbed(into: webView, videoKey: videoKey, muted: true)
            return
        }

        // Mute state changed → post command via JS
        if coord.currentMuted != muted {
            coord.currentMuted = muted
            let cmd = muted ? "mute" : "unMute"
            let js = "document.querySelector('iframe').contentWindow.postMessage('{\"event\":\"command\",\"func\":\"\(cmd)\",\"args\":\"\"}','*');"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // Plain <iframe> embed.  NO YouTube IFrame Player API JS library.
    //
    // The <iframe> tag itself carries the HTML attributes WebKit checks
    // BEFORE deciding whether to allow autoplay:
    //   • allow="autoplay"   – Permissions-Policy for the frame
    //   • muted attribute     – on the wrapper (informational)
    //   • The embed URL has mute=1 & autoplay=1 & playsinline=1
    //
    // This avoids the race condition where the YT IFrame API's own
    // bootstrap tries to play-with-sound before onReady fires, which
    // is the actual trigger for error 152-4.
    // ──────────────────────────────────────────────────────────────────
    private func loadEmbed(into webView: WKWebView, videoKey: String, muted: Bool) {
        let muteParam = muted ? 1 : 0
        let embedURL = "https://www.youtube.com/embed/\(videoKey)?playsinline=1&autoplay=1&mute=\(muteParam)&controls=0&modestbranding=1&rel=0&iv_load_policy=3&fs=0&disablekb=1&loop=1&playlist=\(videoKey)&enablejsapi=1"

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
        var currentVideoKey = ""
        var currentMuted = true
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
                let muteParam = self.currentMuted ? 1 : 0
                let embedURL = "https://www.youtube.com/embed/\(self.currentVideoKey)?playsinline=1&autoplay=1&mute=\(muteParam)&controls=0&modestbranding=1&rel=0&iv_load_policy=3&fs=0&disablekb=1&loop=1&playlist=\(self.currentVideoKey)&enablejsapi=1"
                let html = """
                <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><style>*{margin:0;padding:0}html,body{width:100%;height:100%;background:#000;overflow:hidden}iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style></head><body><iframe src="\(embedURL)" allow="autoplay; encrypted-media" allowfullscreen playsinline muted autoplay></iframe></body></html>
                """
                webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
            }
        }
    }
}
