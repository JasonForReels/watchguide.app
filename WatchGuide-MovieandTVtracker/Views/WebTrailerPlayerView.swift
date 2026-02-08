import SwiftUI
import WebKit

struct WebTrailerPlayerView: UIViewRepresentable {
    let videoKey: String
    var autoplay: Bool
    var muted: Bool

    // Use a consistent origin that matches the baseURL we load HTML from.
    // youtube-nocookie.com is more permissive for embeds and avoids error 150/152.
    private static let embedOrigin = "https://www.youtube-nocookie.com"

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = false

        // Register message handler BEFORE loading content so it's available immediately
        configuration.userContentController.add(context.coordinator, name: "playerReady")
        configuration.userContentController.add(context.coordinator, name: "playerError")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false

        context.coordinator.currentVideoKey = videoKey
        context.coordinator.currentMuted = muted
        context.coordinator.currentAutoplay = autoplay

        let html = Self.buildHTML(videoKey: videoKey, autoplay: autoplay, muted: muted)
        webView.loadHTMLString(html, baseURL: URL(string: Self.embedOrigin))

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let coord = context.coordinator

        guard coord.currentVideoKey == videoKey else {
            coord.currentVideoKey = videoKey
            coord.currentMuted = muted
            coord.currentAutoplay = autoplay
            coord.playerReady = false
            let html = Self.buildHTML(videoKey: videoKey, autoplay: autoplay, muted: muted)
            uiView.loadHTMLString(html, baseURL: URL(string: Self.embedOrigin))
            return
        }

        if coord.playerReady && coord.currentMuted != muted {
            coord.currentMuted = muted
            let js = muted
                ? "try { player.mute(); } catch(e) {}"
                : "try { player.unMute(); } catch(e) {}"
            uiView.evaluateJavaScript(js, completionHandler: nil)
        }

        if coord.playerReady && coord.currentAutoplay != autoplay {
            coord.currentAutoplay = autoplay
            let js = autoplay
                ? "try { player.playVideo(); } catch(e) {}"
                : "try { player.pauseVideo(); } catch(e) {}"
            uiView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - HTML Builder

    static func buildHTML(videoKey: String, autoplay: Bool, muted: Bool) -> String {
        // Real iOS devices require mute for autoplay
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
          html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
          .vc { position: relative; width: 100%; height: 0; padding-bottom: 56.25%; overflow: hidden; }
          #yt-player, iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
        </style>
        </head>
        <body>
          <div class="vc"><div id="yt-player"></div></div>
          <script>
            var tag = document.createElement('script');
            tag.src = "https://www.youtube.com/iframe_api";
            document.head.appendChild(tag);

            var player;
            var retryCount = 0;

            function onYouTubeIframeAPIReady() {
              player = new YT.Player('yt-player', {
                host: '\(embedOrigin)',
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
                  'origin': '\(embedOrigin)',
                  'widget_referrer': '\(embedOrigin)',
                  'fs': 0,
                  'iv_load_policy': 3,
                  'disablekb': 1
                },
                events: {
                  'onReady': onReady,
                  'onStateChange': onState,
                  'onError': onErr
                }
              });
            }

            function onReady(e) {
              e.target.mute();
              e.target.playVideo();
              try { window.webkit.messageHandlers.playerReady.postMessage('ready'); } catch(x) {}
            }

            function onState(e) {
              if (!player) return;
              if (e.data === YT.PlayerState.ENDED) {
                player.seekTo(0);
                player.playVideo();
              }
              if (e.data === YT.PlayerState.PAUSED && \(autoplay ? "true" : "false") && retryCount < 3) {
                retryCount++;
                setTimeout(function() {
                  if (player && player.getPlayerState && player.getPlayerState() === YT.PlayerState.PAUSED) {
                    player.mute();
                    player.playVideo();
                  }
                }, 500);
              }
            }

            function onErr(e) {
              var code = e.data;
              // Error 150 or 101 = embed restricted. Try falling back to direct embed URL.
              if ((code === 150 || code === 101) && retryCount < 1) {
                retryCount = 99;
                var container = document.querySelector('.vc');
                container.innerHTML = '<iframe src="\(embedOrigin)/embed/\(videoKey)?autoplay=\(autoplayInt)&mute=\(muteInt)&playsinline=1&controls=0&modestbranding=1&rel=0&loop=1&playlist=\(videoKey)" frameborder="0" allow="autoplay; encrypted-media" allowfullscreen></iframe>';
              }
              try { window.webkit.messageHandlers.playerError.postMessage(String(code)); } catch(x) {}
            }
          </script>
        </body>
        </html>
        """
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: WebTrailerPlayerView
        var currentVideoKey: String = ""
        var currentMuted: Bool = true
        var currentAutoplay: Bool = false
        var playerReady: Bool = false

        init(_ parent: WebTrailerPlayerView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "playerReady":
                playerReady = true
            case "playerError":
                if let code = message.body as? String {
                    print("WebTrailerPlayer error code: \(code)")
                }
            default:
                break
            }
        }
    }
}
