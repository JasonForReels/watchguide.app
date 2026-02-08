import SwiftUI
import WebKit

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: YouTubePlayerView
        
        init(parent: YouTubePlayerView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Handle script messages if needed
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "playerHandler")
        
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        
        webView.loadHTMLString(makeHTML(videoID: videoID), baseURL: nil)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    private func makeHTML(videoID: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="initial-scale=1.0, maximum-scale=1.0"/>
            <style>
                body, html {
                    margin: 0; padding: 0; background: transparent; overflow: hidden;
                    height: 100%; width: 100%;
                }
                #player {
                    position: absolute;
                    top: 0; left: 0;
                    width: 100%; height: 100%;
                }
            </style>
        </head>
        <body>
            <div id="player"></div>
            <script>
                var tag = document.createElement('script');
                tag.src = "https://www.youtube.com/iframe_api";
                var firstScriptTag = document.getElementsByTagName('script')[0];
                firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

                var player;
                function onYouTubeIframeAPIReady() {
                    player = new YT.Player('player', {
                        videoId: '\(videoID)',
                        playerVars: {
                            autoplay: 1,
                            controls: 1,
                            modestbranding: 1,
                            playsinline: 1,
                            mute: 1,
                            rel: 0,
                            fs: 0,
                            enablejsapi: 1,
                            origin: window.location.origin
                        },
                        events: {
                            'onReady': onPlayerReady,
                        }
                    });
                }
                function onPlayerReady(event) {
                    event.target.mute();
                    event.target.playVideo();
                }
                function unmuteAndPlay() {
                    if (player) {
                        player.unMute();
                        player.playVideo();
                    }
                }
            </script>
        </body>
        </html>
        """
    }
    
    func unmuteAndPlay(_ webView: WKWebView) {
        let js = "unmuteAndPlay();"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

struct YouTubePlayer: View {
    let videoID: String
    @State private var webView: WKWebView? = nil
    @State private var isMuted = true
    
    var body: some View {
        ZStack {
            YouTubePlayerView(videoID: videoID)
                .background(Color.black)
                .overlay(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            // Grab WKWebView reference for JS calls
                            DispatchQueue.main.async {
                                if webView == nil {
                                    webView = findWKWebView(in: geo)
                                }
                            }
                        }
                    }
                )
            
            if isMuted {
                Button(action: {
                    if let webView = webView {
                        webView.evaluateJavaScript("unmuteAndPlay();", completionHandler: nil)
                        isMuted = false
                    }
                }) {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Unmute and play sound")
                .transition(.opacity)
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
    }
    
    private func findWKWebView(in geo: GeometryProxy) -> WKWebView? {
        // Hacky way to find WKWebView from UIViewRepresentable
        let uiView = UIApplication.shared.windows.first { $0.isKeyWindow }?.rootViewController?.view
        return findWKWebView(in: uiView)
    }
    
    private func findWKWebView(in view: UIView?) -> WKWebView? {
        if let wkview = view as? WKWebView {
            return wkview
        }
        for subview in view?.subviews ?? [] {
            if let found = findWKWebView(in: subview) {
                return found
            }
        }
        return nil
    }
}

#if DEBUG
struct YouTubePlayer_Previews: PreviewProvider {
    static var previews: some View {
        YouTubePlayer(videoID: "dQw4w9WgXcQ")
            .frame(height: 200)
    }
}
#endif
