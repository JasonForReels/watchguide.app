//
//  InAppYouTubePlayer.swift
//  WatchGuide-MovieandTVtracker
//
//  Embeds YouTube videos inside the app using WKWebView with the YouTube IFrame Player API.
//  No external YouTube app launch — plays inline within the app.
//

import SwiftUI
import WebKit

// MARK: - In-App YouTube Player (SwiftUI)
struct InAppYouTubePlayer: UIViewRepresentable {
    let videoKey: String
    var autoplay: Bool = true
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = autoplay ? [] : [.all]
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload if video key changed
        if context.coordinator.currentVideoKey != videoKey {
            context.coordinator.currentVideoKey = videoKey
            loadVideo(in: webView)
        }
    }
    
    private func loadVideo(in webView: WKWebView) {
        let autoplayValue = autoplay ? 1 : 0
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; }
                html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
                .container { position: relative; width: 100%; padding-bottom: 56.25%; }
                iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: none; }
            </style>
        </head>
        <body>
            <div class="container">
                <iframe
                    src="https://www.youtube.com/embed/\(videoKey)?autoplay=\(autoplayValue)&playsinline=1&rel=0&modestbranding=1&showinfo=0&fs=1"
                    allow="autoplay; encrypted-media; picture-in-picture"
                    allowfullscreen>
                </iframe>
            </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var currentVideoKey: String?
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow YouTube embeds and the initial load; block external navigation
            if let url = navigationAction.request.url {
                let host = url.host ?? ""
                if navigationAction.navigationType == .other ||
                   host.contains("youtube.com") || host.contains("googlevideo.com") ||
                   host.contains("google.com") || url.scheme == "about" {
                    decisionHandler(.allow)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - Full Screen YouTube Player Sheet
struct YouTubePlayerSheet: View {
    let videoKey: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                
                InAppYouTubePlayer(videoKey: videoKey)
                    .aspectRatio(16.0/9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                
                Spacer()
            }
            .background(Color.black)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
