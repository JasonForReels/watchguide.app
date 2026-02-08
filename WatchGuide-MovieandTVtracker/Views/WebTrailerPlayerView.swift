import SwiftUI
import WebKit

struct WebTrailerPlayerView: UIViewRepresentable {
    let videoKey: String
    var autoplay: Bool
    var muted: Bool

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

        // Reduce WebKit process pressure by sharing process pool
        config.processPool = WebTrailerProcessPool.shared

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator

        context.coordinator.currentVideoKey = videoKey
        context.coordinator.currentMuted = muted
        context.coordinator.currentAutoplay = autoplay
        context.coordinator.webView = webView

        // Defer the actual load until the webview is in the window hierarchy.
        // Loading immediately from makeUIView can trigger sandbox extension failures
        // because the WKWebView process hasn't fully attached yet.
        context.coordinator.pendingLoad = { [weak webView] in
            guard let wv = webView else { return }
            Self.loadEmbed(into: wv, videoKey: videoKey, autoplay: autoplay, muted: muted, coordinator: context.coordinator)
        }

        // Schedule the deferred load — gives UIKit one layout pass to attach the view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            context.coordinator.pendingLoad?()
            context.coordinator.pendingLoad = nil
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let coord = context.coordinator

        if coord.currentVideoKey != videoKey {
            coord.currentVideoKey = videoKey
            coord.currentMuted = muted
            coord.currentAutoplay = autoplay
            coord.retryCount = 0
            Self.loadEmbed(into: uiView, videoKey: videoKey, autoplay: autoplay, muted: muted, coordinator: coord)
            return
        }

        if coord.currentMuted != muted {
            coord.currentMuted = muted
            let muteCmd = muted ? "mute" : "unmute"
            let js = """
            try {
                var iframe = document.querySelector('iframe');
                if (iframe) {
                    iframe.contentWindow.postMessage('{"event":"command","func":"\(muteCmd)","args":""}', '*');
                }
            } catch(e) {}
            """
            uiView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    /// Loads the YouTube embed HTML into the webview.
    /// Static so it can be called from coordinator callbacks without capturing `self`.
    static func loadEmbed(into webView: WKWebView, videoKey: String, autoplay: Bool, muted: Bool, coordinator: Coordinator) {
        let autoplayParam = autoplay ? "1" : "0"
        let muteParam = muted ? "1" : "0"

        // Build a minimal HTML page with only an iframe — no JS API, no extra scripts.
        // The WKWebView configuration (mediaTypesRequiringUserActionForPlayback = [])
        // handles autoplay permission. This avoids the extra WebKit subprocess overhead
        // that the IFrame JS API requires.
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
          id="yt"
          src="https://www.youtube.com/embed/\(videoKey)?playsinline=1&autoplay=\(autoplayParam)&mute=\(muteParam)&controls=0&modestbranding=1&rel=0&loop=1&playlist=\(videoKey)&enablejsapi=1&iv_load_policy=3&fs=0&disablekb=1&origin=https://www.youtube.com"
          allow="autoplay; encrypted-media"
          allowfullscreen>
        </iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        coordinator.retryCount = 0
    }

    // MARK: - Shared process pool (reduces GPU/WebContent process spawning)

    private final class WebTrailerProcessPool {
        static let shared = WKProcessPool()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var currentVideoKey: String = ""
        var currentMuted: Bool = true
        var currentAutoplay: Bool = false
        weak var webView: WKWebView?
        var retryCount = 0
        var pendingLoad: (() -> Void)?
        private let maxRetries = 3

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // After the HTML loads, give YouTube a moment, then verify the iframe rendered.
            // If the web content process was killed before the iframe could load, reload.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self = self else { return }
                webView.evaluateJavaScript("document.querySelector('iframe') !== null") { result, error in
                    if let exists = result as? Bool, !exists, self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        print("WebTrailerPlayer: iframe missing after load, reloading (attempt \(self.retryCount))")
                        WebTrailerPlayerView.loadEmbed(
                            into: webView,
                            videoKey: self.currentVideoKey,
                            autoplay: self.currentAutoplay,
                            muted: self.currentMuted,
                            coordinator: self
                        )
                    } else if error != nil, self.retryCount < self.maxRetries {
                        // JS eval itself failed — process likely crashed
                        self.retryCount += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            WebTrailerPlayerView.loadEmbed(
                                into: webView,
                                videoKey: self.currentVideoKey,
                                autoplay: self.currentAutoplay,
                                muted: self.currentMuted,
                                coordinator: self
                            )
                        }
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let host = url.host?.lowercased() ?? ""
                // Allow: initial about:blank, youtube embeds, google (for consent)
                if navigationAction.targetFrame?.isMainFrame == true &&
                   !host.isEmpty &&
                   !host.contains("youtube.com") &&
                   !host.contains("youtube-nocookie.com") &&
                   !host.contains("google.com") &&
                   url.scheme != "about" {
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard retryCount < maxRetries else { return }
            retryCount += 1
            let delay = Double(retryCount) * 0.8 // progressive backoff
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                WebTrailerPlayerView.loadEmbed(
                    into: webView,
                    videoKey: self.currentVideoKey,
                    autoplay: self.currentAutoplay,
                    muted: self.currentMuted,
                    coordinator: self
                )
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // Provisional navigation failure (e.g. sandbox extension error before page even loads)
            guard retryCount < maxRetries else { return }
            retryCount += 1
            let delay = Double(retryCount) * 1.0
            print("WebTrailerPlayer: provisional navigation failed, retrying in \(delay)s — \(error.localizedDescription)")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                WebTrailerPlayerView.loadEmbed(
                    into: webView,
                    videoKey: self.currentVideoKey,
                    autoplay: self.currentAutoplay,
                    muted: self.currentMuted,
                    coordinator: self
                )
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // The web content process was killed (GPU exit / RBS assertion failure).
            // Wait a beat for the system to stabilise, then reload.
            guard retryCount < maxRetries else { return }
            retryCount += 1
            let delay = Double(retryCount) * 1.2
            print("WebTrailerPlayer: web content process terminated, reloading in \(delay)s (attempt \(retryCount))")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                WebTrailerPlayerView.loadEmbed(
                    into: webView,
                    videoKey: self.currentVideoKey,
                    autoplay: self.currentAutoplay,
                    muted: self.currentMuted,
                    coordinator: self
                )
            }
        }
    }
}
