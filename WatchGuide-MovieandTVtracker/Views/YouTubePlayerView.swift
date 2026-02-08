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

    // Use youtube-nocookie.com to avoid embed restriction errors (150/152)
    private static let embedHost = "https://www.youtube-nocookie.com"

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
        let effectiveMute = autoPlay ? true : isMuted
        let autoplayParam = autoPlay ? "1" : "0"
        let muteParam = effectiveMute ? "1" : "0"
        // CRITICAL: origin must match the embed host domain exactly
        let urlString = "\(Self.embedHost)/embed/\(videoKey)?playsinline=1&autoplay=\(autoplayParam)&mute=\(muteParam)&enablejsapi=1&origin=\(Self.embedHost)&rel=0&modestbranding=1"
        guard let url = URL(string: urlString) else { return }
        let request = URLRequest(url: url)
        if webView.url?.absoluteString != url.absoluteString {
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

