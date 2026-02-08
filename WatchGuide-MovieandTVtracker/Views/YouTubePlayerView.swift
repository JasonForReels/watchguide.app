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

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // On real devices, autoplay requires mute=1. Force mute when autoplay is on.
        let effectiveMute = autoPlay ? true : isMuted
        let autoplayParam = autoPlay ? "1" : "0"
        let muteParam = effectiveMute ? "1" : "0"
        let urlString = "https://www.youtube-nocookie.com/embed/\(videoKey)?playsinline=1&autoplay=\(autoplayParam)&mute=\(muteParam)&enablejsapi=1&origin=https://www.youtube.com"
        guard let url = URL(string: urlString) else { return }
        let request = URLRequest(url: url)
        if webView.url != url {
            webView.load(request)
        }
    }
}

#if DEBUG
#Preview {
    YouTubePlayerView(videoKey: "dQw4w9WgXcQ", autoPlay: false, isMuted: true)
        .frame(height: 240)
}
#endif

