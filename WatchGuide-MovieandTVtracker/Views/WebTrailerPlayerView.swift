import SwiftUI
import WebKit

struct WebTrailerPlayerView: UIViewRepresentable {
    let videoKey: String
    var autoplay: Bool
    var muted: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // Critical: allow media to play without user gesture
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Allow inline playback
        configuration.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        // Important: allow inspection and proper JS execution
        webView.scrollView.bounces = false

        // Store current state for coordinator
        context.coordinator.currentVideoKey = videoKey
        context.coordinator.currentMuted = muted
        context.coordinator.currentAutoplay = autoplay

        let html = buildHTML(videoKey: videoKey, autoplay: autoplay, muted: muted)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let coord = context.coordinator
        
        // Only send JS commands if the player has loaded and video key hasn't changed
        guard coord.currentVideoKey == videoKey else {
            // Video key changed, reload entirely
            coord.currentVideoKey = videoKey
            coord.currentMuted = muted
            coord.currentAutoplay = autoplay
            coord.playerReady = false
            let html = buildHTML(videoKey: videoKey, autoplay: autoplay, muted: muted)
            uiView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
            return
        }
        
        // Only update mute state if player is ready and mute changed
        if coord.playerReady && coord.currentMuted != muted {
            coord.currentMuted = muted
            let muteScript = muted
                ? "try { player.mute(); } catch(e) {}"
                : "try { player.unMute(); } catch(e) {}"
            uiView.evaluateJavaScript(muteScript, completionHandler: nil)
        }
        
        // Only update play state if player is ready and autoplay changed
        if coord.playerReady && coord.currentAutoplay != autoplay {
            coord.currentAutoplay = autoplay
            if autoplay {
                uiView.evaluateJavaScript("try { player.playVideo(); } catch(e) {}", completionHandler: nil)
            } else {
                uiView.evaluateJavaScript("try { player.pauseVideo(); } catch(e) {}", completionHandler: nil)
            }
        }
    }

    private func buildHTML(videoKey: String, autoplay: Bool, muted: Bool) -> String {
        // On real devices, autoplay ONLY works when muted.
        // Force mute=1 when autoplay is requested to ensure playback starts.
        let effectiveMuted = autoplay ? true : muted
        let autoplayInt = autoplay ? 1 : 0
        let muteInt = effectiveMuted ? 1 : 0

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"/>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body {
            width: 100%; height: 100%;
            background-color: black;
            overflow: hidden;
          }
          .video-container {
            position: relative;
            width: 100%; height: 0;
            padding-bottom: 56.25%;
            overflow: hidden;
          }
          #yt-player {
            position: absolute;
            top: 0; left: 0;
            width: 100%; height: 100%;
          }
          iframe {
            position: absolute;
            top: 0; left: 0;
            width: 100%; height: 100%;
          }
        </style>
        </head>
        <body>
          <div class="video-container">
            <div id="yt-player"></div>
          </div>
          <script>
            var tag = document.createElement('script');
            tag.src = "https://www.youtube.com/iframe_api";
            var firstScriptTag = document.getElementsByTagName('script')[0];
            firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

            var player;
            var playerReady = false;

            function onYouTubeIframeAPIReady() {
              player = new YT.Player('yt-player', {
                videoId: '\(videoKey)',
                playerVars: {
                  'autoplay': \(autoplayInt),
                  'controls': 0,
                  'modestbranding': 1,
                  'playsinline': 1,
                  'rel': 0,
                  'mute': \(muteInt),
                  'loop': 1,
                  'playlist': '\(videoKey)',
                  'enablejsapi': 1,
                  'origin': 'https://www.youtube.com',
                  'fs': 0,
                  'iv_load_policy': 3,
                  'disablekb': 1
                },
                events: {
                  'onReady': onPlayerReady,
                  'onStateChange': onPlayerStateChange,
                  'onError': onPlayerError
                }
              });
            }

            function onPlayerReady(event) {
              playerReady = true;
              // Always mute first, then play — this is the key for real devices
              event.target.mute();
              event.target.playVideo();
              
              // If user didn't want muted, schedule unmute after playback starts
              // (only if autoplay was not the reason for muting)
              \((!muted && autoplay) ? """
              // User wants unmuted but we had to mute for autoplay.
              // They can unmute via the UI button.
              """ : "")
              
              // Notify native side that player is ready
              try {
                window.webkit.messageHandlers.playerReady.postMessage('ready');
              } catch(e) {}
            }

            function onPlayerStateChange(event) {
              if (!playerReady || !player) return;
              // Loop: restart when ended
              if (event.data === YT.PlayerState.ENDED) {
                player.seekTo(0);
                player.playVideo();
              }
              // If video is paused right after loading (browser blocked autoplay),
              // try playing again
              if (event.data === YT.PlayerState.PAUSED && \(autoplay ? "true" : "false")) {
                setTimeout(function() {
                  if (player && player.getPlayerState && player.getPlayerState() === YT.PlayerState.PAUSED) {
                    player.mute();
                    player.playVideo();
                  }
                }, 300);
              }
            }

            function onPlayerError(event) {
              // Silently handle errors — don't crash the view
              console.log('YT Player Error:', event.data);
            }
          </script>
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebTrailerPlayerView
        var currentVideoKey: String = ""
        var currentMuted: Bool = true
        var currentAutoplay: Bool = false
        var playerReady: Bool = false

        init(_ parent: WebTrailerPlayerView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Add a message handler to know when the player is truly ready
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "playerReady")
            webView.configuration.userContentController.add(self, name: "playerReady")
        }
    }
}

extension WebTrailerPlayerView.Coordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "playerReady" {
            playerReady = true
        }
    }
}
