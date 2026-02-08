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
        // This is the key: telling WKWebView that NO media types require a user
        // gesture to begin playback. This allows the embedded YouTube iframe to
        // autoplay WITH sound on real devices.
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator

        context.coordinator.loadedVideoKey = videoKey
        loadEmbed(into: webView)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload if the video key actually changed
        guard context.coordinator.loadedVideoKey != videoKey else { return }
        context.coordinator.loadedVideoKey = videoKey
        loadEmbed(into: webView)
    }

    private func loadEmbed(into webView: WKWebView) {
        let autoplayParam = autoPlay ? "1" : "0"
        let muteParam = isMuted ? "1" : "0"

        // Simple iframe embed – WKWebView's configuration handles autoplay permission.
        // No YouTube IFrame JS API needed. This avoids error 150/152 in most cases
        // and lets the webview's mediaTypesRequiringUserActionForPlayback do its job.
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
          src="https://www.youtube-nocookie.com/embed/\(videoKey)?playsinline=1&autoplay=\(autoplayParam)&mute=\(muteParam)&rel=0&modestbranding=1&controls=1&iv_load_policy=3"
          allow="autoplay; encrypted-media; picture-in-picture"
          allowfullscreen>
        </iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var loadedVideoKey: String = ""
    }
}

#if DEBUG
#Preview {
    YouTubePlayerView(videoKey: "dQw4w9WgXcQ", autoPlay: false, isMuted: true)
        .frame(height: 240)
}
#endif

