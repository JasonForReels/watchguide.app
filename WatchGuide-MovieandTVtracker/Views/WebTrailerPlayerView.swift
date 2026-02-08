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
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // This is the critical setting: WKWebView allows autoplay WITH sound
        // when no media types require user action. The embedded YouTube iframe
        // inherits this permission from the hosting webview.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator

        context.coordinator.currentVideoKey = videoKey
        context.coordinator.currentMuted = muted
        context.coordinator.currentAutoplay = autoplay

        loadEmbed(into: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let coord = context.coordinator

        // If the video key changed, reload entirely
        if coord.currentVideoKey != videoKey {
            coord.currentVideoKey = videoKey
            coord.currentMuted = muted
            coord.currentAutoplay = autoplay
            loadEmbed(into: uiView)
            return
        }

        // If only mute state changed, use JS postMessage to toggle mute
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

    private func loadEmbed(into webView: WKWebView) {
        let autoplayParam = autoplay ? "1" : "0"
        let muteParam = muted ? "1" : "0"

        // Pure iframe embed. WKWebView's mediaTypesRequiringUserActionForPlayback = []
        // grants autoplay permission, so YouTube will autoplay with sound if mute=0.
        // Using youtube-nocookie.com to avoid most embed-restriction errors (150/152).
        // enablejsapi=1 allows us to send postMessage commands (mute/unmute) later.
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
          src="https://www.youtube-nocookie.com/embed/\(videoKey)?playsinline=1&autoplay=\(autoplayParam)&mute=\(muteParam)&controls=0&modestbranding=1&rel=0&loop=1&playlist=\(videoKey)&enablejsapi=1&iv_load_policy=3&fs=0&disablekb=1"
          allow="autoplay; encrypted-media"
          allowfullscreen>
        </iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var currentVideoKey: String = ""
        var currentMuted: Bool = true
        var currentAutoplay: Bool = false
    }
}
