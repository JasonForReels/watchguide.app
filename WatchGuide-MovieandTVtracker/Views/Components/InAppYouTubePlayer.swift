//
//  InAppYouTubePlayer.swift
//  WatchGuide-MovieandTVtracker
//
//  Embedded trailer player powered by AVPlayer.
//  Note: AVPlayer can only play direct media URLs (mp4/mov/m3u8), not YouTube page IDs.
//

import SwiftUI
import AVKit
#if canImport(WebKit)
import WebKit
#endif

private extension Color {
    static var trailerFallbackGray: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGray5)
        #elseif canImport(AppKit)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color.gray.opacity(0.2)
        #endif
    }
}

// MARK: - Embedded Trailer Player View
struct EmbeddedTrailerPlayer: View {
    let videoKey: String
    let title: String
    var compact: Bool = false
    var autoPlay: Bool = true

    @State private var player: AVPlayer?
    @State private var isMuted: Bool
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var hasPlayableSource = false
    @State private var embeddedYouTubeID: String?

    init(videoKey: String, title: String, compact: Bool = false, autoPlay: Bool = true) {
        self.videoKey = videoKey
        self.title = title
        self.compact = compact
        self.autoPlay = autoPlay
        _isMuted = State(initialValue: StorageService.shared.settings.autoPlayTrailersMuted)
    }

    var body: some View {
        ZStack {
            Color.black

            if let player, hasPlayableSource {
                VideoPlayer(player: player)
                    .onAppear {
                        player.isMuted = isMuted
                        if autoPlay {
                            player.play()
                        }
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else if let youtubeID = embeddedYouTubeID {
                #if canImport(WebKit) && !os(tvOS)
                YouTubeNoChromeWebPlayer(videoID: youtubeID, autoplay: autoPlay, muted: isMuted)
                    .allowsHitTesting(false)
                #else
                TrailerErrorFallback(videoKey: youtubeID, title: title, compact: compact)
                #endif
            } else {
                TrailerErrorFallback(videoKey: videoKey, title: title, compact: compact)
            }

            if hasPlayableSource || embeddedYouTubeID != nil {
                controlsOverlay
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14))
        .onAppear {
            configurePlayerIfPossible()
            scheduleControlsHide()
        }
        .onDisappear {
            controlsTimer?.invalidate()
        }
    }

    private var controlsOverlay: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                    if showControls {
                        scheduleControlsHide()
                    }
                }

            if showControls {
                VStack {
                    Spacer()

                    HStack {
                        Button {
                            isMuted.toggle()
                            player?.isMuted = isMuted
                            scheduleControlsHide()
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, compact ? 8 : 12)
                    .padding(.bottom, compact ? 8 : 10)
                    .padding(.top, 20)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .transition(.opacity)
            }
        }
    }

    private func scheduleControlsHide() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.25)) {
                    showControls = false
                }
            }
        }
    }

    private func configurePlayerIfPossible() {
        guard player == nil else { return }
        embeddedYouTubeID = nil
        guard let url = Self.resolveDirectMediaURL(from: videoKey) else {
            hasPlayableSource = false
            embeddedYouTubeID = Self.resolveYouTubeID(from: videoKey)
            return
        }

        let avPlayer = AVPlayer(url: url)
        avPlayer.isMuted = isMuted
        player = avPlayer
        hasPlayableSource = true
    }

    private static func resolveDirectMediaURL(from value: String) -> URL? {
        // Accept direct network media links.
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            let ext = url.pathExtension.lowercased()
            if ["mp4", "mov", "m4v", "m3u8"].contains(ext) {
                return url
            }
        }

        // Accept bundled media by filename key.
        let candidates = ["mp4", "mov", "m4v", "m3u8"]
        for ext in candidates {
            if let bundled = Bundle.main.url(forResource: value, withExtension: ext) {
                return bundled
            }
        }

        return nil
    }

    private static func resolveYouTubeID(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Raw YouTube ID
        if trimmed.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil {
            return trimmed
        }
        // Full URL
        guard let url = URL(string: trimmed) else { return nil }
        if url.host?.contains("youtu.be") == true {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        }
        if url.host?.contains("youtube.com") == true {
            if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               let v = queryItems.first(where: { $0.name == "v" })?.value,
               !v.isEmpty {
                return v
            }
            let comps = url.pathComponents
            if let idx = comps.firstIndex(of: "embed"), comps.indices.contains(idx + 1) {
                let id = comps[idx + 1]
                return id.isEmpty ? nil : id
            }
        }
        return nil
    }
}

#if canImport(WebKit) && (os(iOS) || targetEnvironment(macCatalyst))
private struct YouTubeNoChromeWebPlayer: UIViewRepresentable {
    let videoID: String
    let autoplay: Bool
    let muted: Bool

    class Coordinator {
        var lastSource: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = false
        load(into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        load(into: uiView, coordinator: context.coordinator)
    }

    private func load(into webView: WKWebView, coordinator: Coordinator) {
        let autoplayValue = autoplay ? "1" : "0"
        let mutedValue = muted ? "1" : "0"
        let src = "https://www.youtube-nocookie.com/embed/\(videoID)?autoplay=\(autoplayValue)&mute=\(mutedValue)&playsinline=1&controls=0&modestbranding=1&rel=0&iv_load_policy=3&fs=0&disablekb=1&loop=1&playlist=\(videoID)"
        guard coordinator.lastSource != src else { return }
        coordinator.lastSource = src
        let html = """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
            <style>
              html, body { margin: 0; padding: 0; background: #000; overflow: hidden; }
              iframe { position: fixed; inset: 0; width: 100vw; height: 100vh; border: 0; pointer-events: none; }
            </style>
          </head>
          <body>
            <iframe
              src="\(src)"
              title="Trailer"
              allow="autoplay; encrypted-media; picture-in-picture"
              allowfullscreen>
            </iframe>
          </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }
}
#endif

#if canImport(WebKit) && os(macOS)
private struct YouTubeNoChromeWebPlayer: NSViewRepresentable {
    let videoID: String
    let autoplay: Bool
    let muted: Bool

    class Coordinator {
        var lastSource: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        load(into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        load(into: nsView, coordinator: context.coordinator)
    }

    private func load(into webView: WKWebView, coordinator: Coordinator) {
        let autoplayValue = autoplay ? "1" : "0"
        let mutedValue = muted ? "1" : "0"
        let src = "https://www.youtube-nocookie.com/embed/\(videoID)?autoplay=\(autoplayValue)&mute=\(mutedValue)&playsinline=1&controls=0&modestbranding=1&rel=0&iv_load_policy=3&fs=0&disablekb=1&loop=1&playlist=\(videoID)"
        guard coordinator.lastSource != src else { return }
        coordinator.lastSource = src
        let html = """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
            <style>
              html, body { margin: 0; padding: 0; background: #000; overflow: hidden; }
              iframe { position: fixed; inset: 0; width: 100vw; height: 100vh; border: 0; pointer-events: none; }
            </style>
          </head>
          <body>
            <iframe
              src="\(src)"
              title="Trailer"
              allow="autoplay; encrypted-media; picture-in-picture"
              allowfullscreen>
            </iframe>
          </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }
}
#endif

// MARK: - Error Fallback
struct TrailerErrorFallback: View {
    let videoKey: String
    let title: String
    var compact: Bool = false

    var body: some View {
        ZStack {
            AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoKey)/maxresdefault.jpg")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(16.0 / 9.0, contentMode: .fill)
                default:
                    Color.trailerFallbackGray
                }
            }

            Color.black.opacity(0.35)

            Button {
                if let externalURL = resolvedExternalURL {
                    PlatformURLHandler.openURL(externalURL)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.5))
                        .frame(width: compact ? 40 : 56, height: compact ? 40 : 56)

                    Image(systemName: "play.fill")
                        .font(compact ? .body : .title3)
                        .foregroundColor(.white)
                        .offset(x: 2)
                }
            }
        }
    }

    private var resolvedExternalURL: URL? {
        if let directURL = URL(string: videoKey), directURL.scheme != nil {
            return directURL
        }
        return URL(string: "https://www.youtube.com/watch?v=\(videoKey)")
    }
}

// MARK: - Full Screen Trailer Sheet
struct YouTubePlayerSheet: View {
    let videoKey: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack {
                    Spacer()
                    EmbeddedTrailerPlayer(videoKey: videoKey, title: title)
                        .padding(.horizontal)
                    Spacer()
                }
            }
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.white.opacity(0.25))
                    }
                }
            }
            #if !os(macOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
        }
    }
}

// MARK: - Legacy API compatibility
struct InAppYouTubePlayer: View {
    let videoKey: String
    var autoplay: Bool = true

    var body: some View {
        EmbeddedTrailerPlayer(videoKey: videoKey, title: "Trailer", compact: false, autoPlay: autoplay)
    }
}
