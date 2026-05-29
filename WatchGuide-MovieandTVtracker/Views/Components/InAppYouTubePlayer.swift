//
//  InAppYouTubePlayer.swift
//  WatchGuide-MovieandTVtracker
//
//  Embedded YouTube player using YouTubePlayerKit (SPM).
//  Uses the official YouTube IFrame Player API bridge — handles
//  Referer headers, embed restrictions, and Error 153 automatically.
//  Falls back to AVPlayer for direct media URLs (mp4/mov/m3u8).
//

import SwiftUI
import AVKit
import YouTubePlayerKit

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
    var showsControls: Bool = true
    var loops: Bool = false
    var aspectRatio: CGFloat = 16.0 / 9.0
    var contentMode: ContentMode = .fit
    var cornerRadius: CGFloat? = nil
    var zoomScale: CGFloat = 1.0
    var alternateVideoKeys: [String] = []
    var onPlaybackEnded: (() -> Void)?
    var onProgress: ((TimeInterval) -> Void)?
    var volume: Double = 1.0
    var pauseOffscreen: Bool = true

    // YouTube player (primary path for YouTube IDs)
    @StateObject private var ytPlayer: YouTubePlayer

    // AVPlayer (secondary path for direct media URLs)
    @State private var avPlayer: AVPlayer?
    @State private var usingAVPlayer = false

    @State private var isMuted: Bool
    @State private var showControlsOverlay = true
    @State private var controlsTimer: Timer?
    @State private var isReady = false
    @State private var hasError = false
    @State private var progressObserver: Any?
    @State private var wasPlayingBeforeHidden = false

    init(
        videoKey: String,
        title: String,
        compact: Bool = false,
        autoPlay: Bool = true,
        showsControls: Bool = true,
        loops: Bool = false,
        aspectRatio: CGFloat = 16.0 / 9.0,
        contentMode: ContentMode = .fit,
        cornerRadius: CGFloat? = nil,
        zoomScale: CGFloat = 1.0,
        alternateVideoKeys: [String] = [],
        onPlaybackEnded: (() -> Void)? = nil,
        onProgress: ((TimeInterval) -> Void)? = nil,
        pauseOffscreen: Bool = true
    ) {
        self.videoKey = videoKey
        self.title = title
        self.compact = compact
        self.autoPlay = autoPlay
        self.showsControls = showsControls
        self.loops = loops
        self.aspectRatio = aspectRatio
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.zoomScale = zoomScale
        self.alternateVideoKeys = alternateVideoKeys
        self.onPlaybackEnded = onPlaybackEnded
        self.onProgress = onProgress
        self.pauseOffscreen = pauseOffscreen

        let startMuted = StorageService.shared.settings.autoPlayTrailersMuted
        _isMuted = State(initialValue: startMuted)

        // Resolve which key to use for YouTube
        let resolvedYTID = Self.resolveYouTubeID(from: videoKey)
            ?? alternateVideoKeys.lazy.compactMap({ Self.resolveYouTubeID(from: $0) }).first

        _ytPlayer = StateObject(wrappedValue: YouTubePlayer(
            source: resolvedYTID.map { .video(id: $0) } ?? .video(id: videoKey),
            parameters: .init(
                autoPlay: autoPlay,
                loopEnabled: loops,
                showControls: false,
                showFullscreenButton: false,
                keyboardControlsDisabled: true,
                restrictRelatedVideosToSameChannel: true
            ),
            configuration: .init(
                allowsInlineMediaPlayback: true,
                openURLAction: .init { _, _ in
                    // Block all navigation to prevent Safari from opening
                }
            )
        ))
    }

    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? (compact ? 10 : 14)
    }

    var body: some View {
        ZStack {
            Color.black

            if usingAVPlayer, let avPlayer {
                // Direct media (mp4/mov/m3u8) via AVPlayer
                VideoPlayer(player: avPlayer)
                    .scaleEffect(zoomScale)
                    .onAppear {
                        avPlayer.isMuted = isMuted
                        avPlayer.volume = Float(volume)
                        if autoPlay {
                            avPlayer.play()
                        }
                        setupAVProgressObserver(for: avPlayer)
                        setupAVEndObserver(for: avPlayer)
                    }
                    .onDisappear {
                        avPlayer.pause()
                        removeAVProgressObserver(from: avPlayer)
                    }
                    .onChange(of: volume) { _, newValue in
                        avPlayer.volume = Float(newValue)
                    }
            } else if !hasError {
                // YouTube player (primary path)
                YouTubePlayerKit.YouTubePlayerView(ytPlayer)
                    .scaleEffect(zoomScale)
                    .opacity(isReady ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: isReady)
            }

            // Loading state (YouTube path)
            if !usingAVPlayer && !isReady && !hasError {
                loadingOverlay
            }

            // Error fallback
            if hasError {
                TrailerErrorFallback(videoKey: videoKey, title: title, compact: compact)
            }

            // Custom controls overlay
            if showsControls && (isReady || usingAVPlayer) && !hasError {
                controlsOverlayView
            }
        }
        .aspectRatio(aspectRatio, contentMode: contentMode)
        .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius))
        .modifier(ScrollVisibilityPauseModifier(enabled: pauseOffscreen, onVisibilityChanged: { visible in
            handleVisibilityChange(visible)
        }))
        .onAppear {
            tryDirectMediaFirst()
            if showsControls {
                scheduleControlsHide()
            }
        }
        .onDisappear {
            controlsTimer?.invalidate()
        }
        .onReceive(ytPlayer.statePublisher) { state in
            guard !usingAVPlayer else { return }
            switch state {
            case .ready:
                isReady = true
                hasError = false
                let shouldMute = StorageService.shared.settings.autoPlayTrailersMuted
                Task {
                    // Always mute first to satisfy iOS autoplay policy
                    try? await ytPlayer.mute()
                    // Explicitly start playback
                    try? await ytPlayer.play()
                    // Then apply the user's actual mute preference
                    if !shouldMute {
                        try? await ytPlayer.unmute()
                    }
                }
            case .error:
                hasError = true
            default:
                break
            }
        }
    }

    // MARK: - Direct media URL check

    /// Try all keys for a direct media URL first (TrailerAddonService / bundled video).
    /// If found, use AVPlayer. Otherwise, YouTubePlayerKit handles it.
    private func tryDirectMediaFirst() {
        let keysToTry = [videoKey] + alternateVideoKeys
        for key in keysToTry {
            if let url = Self.resolveDirectMediaURL(from: key) {
                let player = AVPlayer(url: url)
                player.isMuted = isMuted
                player.volume = Float(volume)
                avPlayer = player
                usingAVPlayer = true
                isReady = true
                return
            }
        }
        // Otherwise YouTubePlayerKit is already configured in init
    }

    // MARK: - Loading overlay

    private var loadingOverlay: some View {
        ZStack {
            AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoKey)/maxresdefault.jpg")) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .aspectRatio(16.0 / 9.0, contentMode: .fill)
                }
            }
            Color.black.opacity(0.4)
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
        }
    }

    // MARK: - Controls overlay

    private var controlsOverlayView: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControlsOverlay.toggle()
                    }
                    if showControlsOverlay {
                        scheduleControlsHide()
                    }
                }

            if showControlsOverlay {
                VStack {
                    Spacer()

                    HStack(spacing: 12) {
                        Button {
                            isMuted.toggle()
                            if usingAVPlayer {
                                avPlayer?.isMuted = isMuted
                            } else {
                                Task {
                                    if isMuted {
                                        try? await ytPlayer.mute()
                                    } else {
                                        try? await ytPlayer.unmute()
                                    }
                                }
                            }
                            scheduleControlsHide()
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }

                        if !compact {
                            Text(title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                        }

                        Spacer()

                        Text("TRAILER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.ultraThinMaterial))
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

    // MARK: - Visibility handling

    private func handleVisibilityChange(_ visible: Bool) {
        if usingAVPlayer {
            if visible {
                if wasPlayingBeforeHidden, let avPlayer {
                    avPlayer.play()
                    wasPlayingBeforeHidden = false
                }
            } else {
                if let avPlayer, avPlayer.rate > 0 {
                    wasPlayingBeforeHidden = true
                    avPlayer.pause()
                } else {
                    wasPlayingBeforeHidden = false
                }
            }
        } else {
            if visible {
                if wasPlayingBeforeHidden {
                    Task { try? await ytPlayer.play() }
                    wasPlayingBeforeHidden = false
                }
            } else {
                wasPlayingBeforeHidden = true
                Task { try? await ytPlayer.pause() }
            }
        }
    }

    // MARK: - Timer

    private func scheduleControlsHide() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.25)) {
                    showControlsOverlay = false
                }
            }
        }
    }

    // MARK: - AVPlayer observers (for direct media only)

    private func setupAVProgressObserver(for player: AVPlayer) {
        guard onProgress != nil else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        progressObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            onProgress?(time.seconds)
        }
    }

    private func removeAVProgressObserver(from player: AVPlayer) {
        if let observer = progressObserver {
            player.removeTimeObserver(observer)
            progressObserver = nil
        }
    }

    private func setupAVEndObserver(for player: AVPlayer) {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            if loops {
                player.seek(to: .zero)
                player.play()
            } else {
                onPlaybackEnded?()
            }
        }
    }

    // MARK: - URL resolution helpers

    private static func resolveDirectMediaURL(from value: String) -> URL? {
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            let ext = url.pathExtension.lowercased()
            if ["mp4", "mov", "m4v", "m3u8"].contains(ext) {
                return url
            }
        }
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
        if trimmed.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil {
            return trimmed
        }
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

// MARK: - Scroll Visibility Pause

/// Conditionally applies `onScrollVisibilityChange` to pause/resume content when scrolled offscreen.
private struct ScrollVisibilityPauseModifier: ViewModifier {
    let enabled: Bool
    let onVisibilityChanged: (Bool) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .onScrollVisibilityChange(threshold: 0.3) { visible in
                    onVisibilityChanged(visible)
                }
        } else {
            content
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
