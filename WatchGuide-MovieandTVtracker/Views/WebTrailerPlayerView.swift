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

        // Prevent WebKit from aggressively suspending the web content process
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

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

        loadEmbed(into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let coord = context.coordinator

        if coord.currentVideoKey != videoKey {
            coord.currentVideoKey = videoKey
            coord.currentMuted = muted
            coord.currentAutoplay = autoplay
            loadEmbed(into: uiView, coordinator: coord)
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

    private func loadEmbed(into webView: WKWebView, coordinator: Coordinator) {
        let autoplayParam = autoplay ? "1" : "0"
        let muteParam = muted ? "1" : "0"

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
        // Use matching origin so YouTube's enablejsapi works correctly
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        coordinator.retryCount = 0
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var currentVideoKey: String = ""
        var currentMuted: Bool = true
        var currentAutoplay: Bool = false
        weak var webView: WKWebView?
        var retryCount = 0
        private let maxRetries = 2

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // After the HTML loads, give YouTube a moment, then check if the
            // iframe actually rendered. If the web content process was killed
            // (GPUProcessProxy::gpuProcessExited), the iframe will be blank.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                webView.evaluateJavaScript("document.querySelector('iframe') !== null") { result, _ in
                    if let exists = result as? Bool, !exists, self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        webView.reload()
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow the initial HTML load and YouTube embed iframe navigation
            if let url = navigationAction.request.url {
                let host = url.host?.lowercased() ?? ""
                if navigationAction.targetFrame?.isMainFrame == true &&
                   !host.contains("youtube.com") && !host.contains("youtube-nocookie.com") &&
                   url.scheme != "about" {
                    // Block unexpected navigations that could take over the view
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // On navigation failure, retry once
            if retryCount < maxRetries {
                retryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    webView.reload()
                }
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // The web content process was killed (this is what the GPU/RBS error indicates).
            // Reload to recover.
            if retryCount < maxRetries {
                retryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    webView.reload()
                }
            }
        }
    }
}
