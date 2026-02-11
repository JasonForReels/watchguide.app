//
//  InlineTrailerPlayerView.swift
//  WatchGuide-MovieandTVtracker
//
//  Inline YouTube trailer player for the hero carousel.
//  Uses a YouTube embed iframe for reliable muted autoplay.
//

import SwiftUI
import WebKit

struct InlineTrailerPlayerView: UIViewRepresentable {
    let videoKey: String
    @Binding var isMuted: Bool
    @Binding var isPlaying: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "ytState")
        
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // Allow YouTube embed to work properly
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        // Allow interaction so YouTube iframe can initialize properly
        webView.isUserInteractionEnabled = false
        
        // Transparent background
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = .clear
        }
        
        context.coordinator.webView = webView
        
        let html = Self.buildEmbedHTML(videoKey: videoKey)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let currentMuted = isMuted
        if currentMuted != context.coordinator.lastMuteState {
            context.coordinator.lastMuteState = currentMuted
            let js = currentMuted ? "mutePlayer();" : "unmutePlayer();"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeAllScriptMessageHandlers()
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
        coordinator.webView = nil
    }
    
    // MARK: - YouTube Embed HTML
    
    private static func buildEmbedHTML(videoKey: String) -> String {
        // Use the YouTube IFrame Player API with a proper embed.
        // The oversized container + negative margins ensure the video fills
        // the viewport edge-to-edge (hiding YouTube chrome / black bars).
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>
        *{margin:0;padding:0;box-sizing:border-box;}
        html,body{width:100%;height:100%;overflow:hidden;background:#000;}
        .wrap{position:absolute;top:50%;left:50%;width:300vw;height:300vh;transform:translate(-50%,-50%);}
        .wrap iframe{width:100%;height:100%;border:none;}
        </style>
        </head>
        <body>
        <div class="wrap">
          <div id="ytplayer"></div>
        </div>
        <script>
        // Load YouTube IFrame API
        var tag=document.createElement('script');
        tag.src='https://www.youtube.com/iframe_api';
        document.head.appendChild(tag);

        var player;
        var ready=false;

        function onYouTubeIframeAPIReady(){
          player=new YT.Player('ytplayer',{
            videoId:'\(videoKey)',
            playerVars:{
              autoplay:1,
              mute:1,
              controls:0,
              showinfo:0,
              rel:0,
              modestbranding:1,
              playsinline:1,
              iv_load_policy:3,
              disablekb:1,
              fs:0,
              cc_load_policy:0,
              loop:1,
              playlist:'\(videoKey)',
              origin:'https://www.youtube.com'
            },
            events:{
              onReady:function(e){
                ready=true;
                e.target.mute();
                e.target.playVideo();
              },
              onStateChange:function(e){
                var s='';
                switch(e.data){
                  case YT.PlayerState.PLAYING:s='playing';break;
                  case YT.PlayerState.ENDED:s='ended';break;
                  case YT.PlayerState.PAUSED:s='paused';break;
                  case YT.PlayerState.BUFFERING:s='buffering';break;
                  default:return;
                }
                try{window.webkit.messageHandlers.ytState.postMessage(s);}catch(x){}
              },
              onError:function(){
                try{window.webkit.messageHandlers.ytState.postMessage('error');}catch(x){}
              }
            }
          });
        }

        function mutePlayer(){if(ready&&player)player.mute();}
        function unmutePlayer(){if(ready&&player)player.unMute();}
        function pausePlayer(){if(ready&&player)player.pauseVideo();}
        function resumePlayer(){if(ready&&player)player.playVideo();}
        </script>
        </body>
        </html>
        """
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: InlineTrailerPlayerView
        weak var webView: WKWebView?
        var lastMuteState: Bool = true
        
        init(_ parent: InlineTrailerPlayerView) {
            self.parent = parent
            self.lastMuteState = parent.isMuted
            super.init()
        }
        
        // MARK: WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let state = message.body as? String else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch state {
                case "playing":
                    self.parent.isPlaying = true
                case "ended", "paused", "error":
                    self.parent.isPlaying = false
                case "buffering":
                    break
                default:
                    break
                }
            }
        }
        
        // MARK: WKNavigationDelegate
        // Allow YouTube navigation (needed for iframe API script loading)
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("InlineTrailerPlayer nav failed: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("InlineTrailerPlayer provisional nav failed: \(error.localizedDescription)")
        }
    }
}
