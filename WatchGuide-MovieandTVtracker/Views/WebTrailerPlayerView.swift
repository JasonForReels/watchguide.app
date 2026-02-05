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
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator

        let html = buildHTML(videoKey: videoKey, autoplay: autoplay, muted: muted)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let muteScript = "if (typeof player !== 'undefined') { " + (muted ? "player.mute();" : "player.unMute();") + " }"
        uiView.evaluateJavaScript(muteScript, completionHandler: nil)

        if autoplay {
            uiView.evaluateJavaScript("if (typeof player !== 'undefined') { player.playVideo(); }", completionHandler: nil)
        } else {
            uiView.evaluateJavaScript("if (typeof player !== 'undefined') { player.pauseVideo(); }", completionHandler: nil)
        }
    }

    private func buildHTML(videoKey: String, autoplay: Bool, muted: Bool) -> String {
        let autoplayInt = autoplay ? 1 : 0
        let muteInt = muted ? 1 : 0
        let playerDivId = "yt-player"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"/>
        <style>
          * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
          }
          html, body {
            width: 100%;
            height: 100%;
            background-color: black;
            overflow: hidden;
          }
          .video-container {
            position: relative;
            width: 100%;
            height: 0;
            padding-bottom: 56.25%; /* 16:9 aspect ratio */
            overflow: hidden;
          }
          #\(playerDivId) {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
          }
          iframe {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
          }
        </style>
        </head>
        <body>
          <div class="video-container">
            <div id="\(playerDivId)"></div>
          </div>
          <script>
            var tag = document.createElement('script');
            tag.src = "https://www.youtube.com/iframe_api";
            var firstScriptTag = document.getElementsByTagName('script')[0];
            firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

            var player;
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('\(playerDivId)', {
                host: 'https://www.youtube-nocookie.com',
                videoId: '\(videoKey)',
                playerVars: {
                  autoplay: \(autoplayInt),
                  controls: 0,
                  modestbranding: 1,
                  playsinline: 1,
                  rel: 0,
                  mute: \(muteInt),
                  loop: 1,
                  playlist: '\(videoKey)'
                },
                events: {
                  'onReady': onPlayerReady,
                  'onStateChange': onPlayerStateChange
                }
              });
            }

            function onPlayerReady(event) {
              if (typeof player === 'undefined') { return; }
              if (\(muted ? "true" : "false")) {
                player.mute();
              } else {
                player.unMute();
              }
              if (\(autoplay ? "true" : "false")) {
                player.playVideo();
              }
            }

            function onPlayerStateChange(event) {
              if (typeof player === 'undefined') { return; }
              if(event.data === YT.PlayerState.ENDED) {
                player.seekTo(0);
                player.playVideo();
              }
            }

            function setMuted(isMuted) {
              if (isMuted) {
                player.mute();
              } else {
                player.unMute();
              }
            }

            function play() {
              player.playVideo();
            }

            function pause() {
              player.pauseVideo();
            }
          </script>
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebTrailerPlayerView

        init(_ parent: WebTrailerPlayerView) {
            self.parent = parent
        }
    }
}
