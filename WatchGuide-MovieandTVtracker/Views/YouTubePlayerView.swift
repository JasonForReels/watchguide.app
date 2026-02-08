//
//  YouTubePlayerView.swift
//  WatchGuide-MovieandTVtracker
//
//  Full-controls YouTube player for the AI trailer sheet.
//  ALWAYS starts MUTED so WebKit allows autoplay.
//  Unmute happens via user gesture → postMessage to iframe.

import SwiftUI
import WebKit

// Shared across the app – avoids spawning extra GPU/WebContent processes.
private let sharedPool = WKProcessPool()

struct YouTubePlayerView: UIViewRepresentable {
    let videoKey: String
    var autoPlay: Bool = false
    var isMuted: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    // ── Create WKWebView on the MAIN THREAD ──
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback          = true     // playsinline
        cfg.mediaTypesRequiringUserActionForPlayback = [] // no gesture needed
        cfg.processPool = sharedPool

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces         = false
        wv.backgroundColor            = .black
        wv.isOpaque                   = false
        wv.navigationDelegate         = context.coordinator

        context.coordinator.videoKey = videoKey
        context.coordinator.muted    = true       // ALWAYS muted first

        // Load immediately – always muted
        loadPage(wv, key: videoKey, auto: autoPlay)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        let c = context.coordinator

        // Video changed → full reload (muted)
        if c.videoKey != videoKey {
            c.videoKey = videoKey
            c.muted    = true
            c.retries  = 0
            loadPage(wv, key: videoKey, auto: autoPlay)
            return
        }

        // Mute / unmute via postMessage (enablejsapi=1)
        if c.muted != isMuted {
            c.muted = isMuted
            let fn = isMuted ? "mute" : "unMute"
            wv.evaluateJavaScript(
                "document.querySelector('iframe').contentWindow.postMessage(" +
                "JSON.stringify({event:'command',func:'\(fn)',args:''}),'*');",
                completionHandler: nil
            )
        }
    }

    // ────────────────────────────────────────────────────
    // Plain <iframe> – NO YouTube IFrame Player API JS.
    // Starts muted → WebKit autoplay policy satisfied.
    // controls=1 for full player experience.
    // enablejsapi=1 so we can postMessage mute/unMute.
    // ────────────────────────────────────────────────────
    private func loadPage(_ wv: WKWebView, key: String, auto: Bool) {
        let ap = auto ? 1 : 0
        let src = "https://www.youtube.com/embed/\(key)"
            + "?playsinline=1&autoplay=\(ap)&mute=1"
            + "&controls=1&modestbranding=1&rel=0"
            + "&iv_load_policy=3&enablejsapi=1"

        let html = """
        <!DOCTYPE html>
        <html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>*{margin:0;padding:0}html,body{width:100%;height:100%;background:#000;overflow:hidden}
        iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="\(src)"
                allow="autoplay; encrypted-media"
                allowfullscreen frameborder="0"
                playsinline muted autoplay>
        </iframe>
        </body></html>
        """
        wv.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    // MARK: – Coordinator
    class Coordinator: NSObject, WKNavigationDelegate {
        var videoKey = ""
        var muted    = true
        var retries  = 0

        func webView(_ wv: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url,
                  let host = url.host?.lowercased(),
                  action.targetFrame?.isMainFrame == true,
                  !host.isEmpty,
                  url.scheme != "about" else {
                decisionHandler(.allow); return
            }
            let ok = host.contains("youtube.com")
                  || host.contains("youtube-nocookie.com")
                  || host.contains("google.com")
                  || host.contains("googleapis.com")
                  || host.contains("googlevideo.com")
            decisionHandler(ok ? .allow : .cancel)
        }

        func webView(_ wv: WKWebView, didFail n: WKNavigation!, withError e: Error) { retry(wv) }
        func webView(_ wv: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { retry(wv) }
        func webViewWebContentProcessDidTerminate(_ wv: WKWebView) { retry(wv) }

        private func retry(_ wv: WKWebView) {
            guard retries < 2 else { return }
            retries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(retries) * 1.5) { [weak self] in
                guard let self else { return }
                let src = "https://www.youtube.com/embed/\(self.videoKey)"
                    + "?playsinline=1&autoplay=1&mute=1"
                    + "&controls=1&modestbranding=1&rel=0"
                    + "&iv_load_policy=3&enablejsapi=1"
                let html = "<!DOCTYPE html><html><head><meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no\"><style>*{margin:0;padding:0}html,body{width:100%;height:100%;background:#000;overflow:hidden}iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style></head><body><iframe src=\"\(src)\" allow=\"autoplay; encrypted-media\" allowfullscreen frameborder=\"0\" playsinline muted autoplay></iframe></body></html>"
                wv.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
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

