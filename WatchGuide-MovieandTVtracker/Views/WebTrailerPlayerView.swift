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

        // Share process pool to reduce GPU/WebContent process spawning
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

        // Defer loading until the webview is attached to the window hierarchy.
        // This avoids sandbox extension failures on real devices.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.loadEmbed(into: webView, videoKey: videoKey, coordinator: context.coordinator)
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
            Self.loadEmbed(into: uiView, videoKey: videoKey, coordinator: coord)
            return
        }

        // Handle mute/unmute toggle via postMessage (user gesture driven from SwiftUI)
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
    /// KEY FIX: Always start muted (mute=1) so WebKit allows autoplay without
    /// the error 152-4 / GPU process crash. The `muted` and `playsinline`
    /// attributes on the iframe plus `autoplay` satisfy WebKit's autoplay policy.
    /// Users can unmute via the SwiftUI button which triggers a postMessage command.
    static func loadEmbed(into webView: WKWebView, videoKey: String, coordinator: Coordinator) {
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
          src="https://www.youtube.com/embed/\(videoKey)?playsinline=1&autoplay=1&mute=1&controls=0&modestbranding=1&rel=0&loop=1&playlist=\(videoKey)&enablejsapi=1&iv_load_policy=3&fs=0&disablekb=1&origin=https://www.youtube.com"
          allow="autoplay; encrypted-media"
          allowfullscreen
          playsinline
          muted
          autoplay>
        </iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        coordinator.retryCount = 0
    }

    // MARK: - Shared process pool

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
        private let maxRetries = 3

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // After load, verify the iframe rendered. If the web content process
            // was killed before the iframe could load, retry.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self = self else { return }
                webView.evaluateJavaScript("document.querySelector('iframe') !== null") { result, error in
                    if let exists = result as? Bool, !exists, self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        WebTrailerPlayerView.loadEmbed(
                            into: webView,
                            videoKey: self.currentVideoKey,
                            coordinator: self
                        )
                    } else if error != nil, self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            WebTrailerPlayerView.loadEmbed(
                                into: webView,
                                videoKey: self.currentVideoKey,
                                coordinator: self
                            )
                        }
                    }
                }
            }

            // If the caller wanted unmuted, send unmute after the video is likely playing
            if !currentMuted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    guard let self = self, !self.currentMuted else { return }
                    let js = """
                    try {
                        var iframe = document.querySelector('iframe');
                        if (iframe) {
                            iframe.contentWindow.postMessage('{"event":"command","func":"unMute","args":""}', '*');
                        }
                    } catch(e) {}
                    """
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let host = url.host?.lowercased() ?? ""
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
            retryIfNeeded(webView: webView, delay: Double(retryCount + 1) * 0.8)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            retryIfNeeded(webView: webView, delay: Double(retryCount + 1) * 1.0)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            retryIfNeeded(webView: webView, delay: Double(retryCount + 1) * 1.2)
        }

        private func retryIfNeeded(webView: WKWebView, delay: Double) {
            guard retryCount < maxRetries else { return }
            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                WebTrailerPlayerView.loadEmbed(
                    into: webView,
                    videoKey: self.currentVideoKey,
                    coordinator: self
                )
            }
        }
    }
}
