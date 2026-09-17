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
import AVFoundation
#if canImport(YouTubePlayerKit)
import YouTubePlayerKit
#endif

private extension Color {
    static var trailerFallbackGray: Color {
        #if os(tvOS)
        return Color.gray.opacity(0.2)
        #elseif canImport(UIKit)
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

    #if canImport(YouTubePlayerKit)
    // YouTube player (primary path for YouTube IDs)
    @StateObject private var ytPlayer: YouTubePlayer
    #endif

    // AVPlayer (secondary path for direct media URLs)
    @State private var avSession: TrailerPlaybackSession?
    @State private var avPlayer: AVPlayer?
    @State private var usingAVPlayer = false

    @State private var isMuted: Bool
    @State private var showControlsOverlay = true
    @State private var controlsTimer: Timer?
    @State private var isReady = false
    @State private var hasError = false
    @State private var progressObserver: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var wasPlayingBeforeHidden = false
    /// Separate from `wasPlayingBeforeHidden` on purpose: scroll visibility and a
    /// voice session can suppress playback at the same time, and one restoring
    /// must not resume a trailer the other still wants silent.
    @State private var wasPlayingBeforeVoice = false
    @ObservedObject private var playbackGate = HeroCarouselMuteManager.shared

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

        #if canImport(YouTubePlayerKit)
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
        #endif
    }

    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? (compact ? 10 : 14)
    }

    var body: some View {
        ZStack {
            Color.black

            if usingAVPlayer, !hasError, let avPlayer {
                // Direct media (mp4/mov/m3u8) via AVPlayer
                VideoPlayer(player: avPlayer)
                    .scaleEffect(zoomScale)
                    .onAppear {
                        avPlayer.isMuted = isMuted
                        avPlayer.volume = Float(volume)
                        setupAVProgressObserver(for: avPlayer)
                        setupAVEndObserver(for: avPlayer)
                    }
                    .onDisappear {
                        avSession?.pause()
                        removeAVProgressObserver(from: avPlayer)
                    }
                    .onChange(of: volume) { _, newValue in
                        avPlayer.volume = Float(newValue)
                    }
            } else if !hasError {
                #if canImport(YouTubePlayerKit)
                // YouTube player (primary path)
                YouTubePlayerKit.YouTubePlayerView(ytPlayer)
                    .scaleEffect(zoomScale)
                    .opacity(isReady ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: isReady)
                #else
                // No YouTube player available on this platform — show fallback
                TrailerErrorFallback(videoKey: videoKey, title: title, compact: compact)
                #endif
            }

            #if canImport(YouTubePlayerKit)
            // Loading state (YouTube path)
            if !usingAVPlayer && !isReady && !hasError {
                loadingOverlay
            }
            #endif

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
        .onChange(of: playbackGate.isVoiceModeActive) { _, active in
            handleVoiceModeChange(active)
        }
        .onDisappear {
            controlsTimer?.invalidate()
            removeAVEndObserver()
            // Ordered teardown before the player reference goes away, so CoreMedia
            // isn't left with a reporting session for an item that no longer exists.
            avSession?.invalidate()
            avSession = nil
            avPlayer = nil
        }
        #if canImport(YouTubePlayerKit)
        .onReceive(ytPlayer.statePublisher) { state in
            guard !usingAVPlayer else { return }
            switch state {
            case .ready:
                isReady = true
                hasError = false
                guard autoPlay else { break }
                // Atlas is listening — starting here would both talk over the
                // session and reconfigure the shared audio session away from
                // `.voiceChat`. Playback resumes when the call ends.
                guard !HeroCarouselMuteManager.shared.isVoiceModeActive else {
                    wasPlayingBeforeVoice = true
                    break
                }
                let shouldMute = StorageService.shared.settings.autoPlayTrailersMuted
                Task {
                    // Configure audio session for playback
                    #if !os(macOS)
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                    try? AVAudioSession.sharedInstance().setActive(true)
                    #endif
                    // Small delay to let the WebView fully settle on real devices
                    try? await Task.sleep(for: .milliseconds(150))
                    // Always mute first to satisfy iOS autoplay policy
                    try? await ytPlayer.mute()
                    // Explicitly start playback (autoPlay param alone is unreliable on real devices)
                    try? await ytPlayer.play()
                    // Then apply the user's actual mute preference
                    if !shouldMute {
                        // Wait for playback to actually begin before unmuting
                        try? await Task.sleep(for: .milliseconds(300))
                        try? await ytPlayer.unmute()
                    }
                }
            case .error:
                hasError = true
            default:
                break
            }
        }
        .onReceive(ytPlayer.playbackStatePublisher) { playbackState in
            guard !usingAVPlayer else { return }
            if playbackState == .ended {
                if loops {
                    Task { try? await ytPlayer.play() }
                } else {
                    onPlaybackEnded?()
                }
            }
        }
        #endif
    }

    // MARK: - Direct media URL check

    /// Try all keys for a direct media URL first (TrailerAddonService / bundled video).
    /// If found, use AVPlayer. Otherwise, YouTubePlayerKit handles it.
    private func tryDirectMediaFirst() {
        let keysToTry = [videoKey] + alternateVideoKeys
        for key in keysToTry {
            if let url = Self.resolveDirectMediaURL(from: key) {
                // Configure audio session for media playback so audio isn't silenced
                #if !os(macOS)
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try? AVAudioSession.sharedInstance().setActive(true)
                #endif
                let session = TrailerPlaybackSession(url: url, muted: isMuted, volume: Float(volume))
                // Playback is held until the item has buffered enough to play through,
                // rather than starting into an empty buffer the moment the view appears.
                session.onReadyToPlay = {
                    isReady = true
                    if autoPlay { session.play() }
                }
                // A dead URL, or one the connection can't carry, drops to the poster
                // fallback instead of looping through stall after stall.
                session.onFailure = {
                    hasError = true
                }
                avSession = session
                avPlayer = session.player
                usingAVPlayer = true
                return
            }
        }
        #if !canImport(YouTubePlayerKit)
        // No YouTube player on this platform — show error fallback for YouTube IDs
        hasError = true
        #endif
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
                                #if canImport(YouTubePlayerKit)
                                Task {
                                    if isMuted {
                                        try? await ytPlayer.mute()
                                    } else {
                                        try? await ytPlayer.unmute()
                                    }
                                }
                                #endif
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

    /// Pauses for the duration of an Atlas voice session and restores afterwards,
    /// but only what was actually playing when the session began.
    private func handleVoiceModeChange(_ active: Bool) {
        if active {
            if usingAVPlayer {
                guard let avPlayer, avPlayer.rate > 0 else { return }
                wasPlayingBeforeVoice = true
                avSession?.pause()
            } else {
                #if canImport(YouTubePlayerKit)
                guard isReady else { return }
                wasPlayingBeforeVoice = true
                Task { try? await ytPlayer.pause() }
                #endif
            }
        } else if wasPlayingBeforeVoice {
            wasPlayingBeforeVoice = false
            if usingAVPlayer {
                avSession?.play()
            } else {
                #if canImport(YouTubePlayerKit)
                Task { try? await ytPlayer.play() }
                #endif
            }
        }
    }

    private func handleVisibilityChange(_ visible: Bool) {
        // Scrolling back into view must not undo a voice-mode pause.
        let visible = visible && !playbackGate.isVoiceModeActive
        if usingAVPlayer {
            if visible {
                if wasPlayingBeforeHidden {
                    avSession?.play()
                    wasPlayingBeforeHidden = false
                }
            } else {
                if let avPlayer, avPlayer.rate > 0 {
                    wasPlayingBeforeHidden = true
                    avSession?.pause()
                } else {
                    wasPlayingBeforeHidden = false
                }
            }
        } else {
            #if canImport(YouTubePlayerKit)
            // Don't interfere with playback until the player is actually ready
            guard isReady else { return }
            if visible {
                if wasPlayingBeforeHidden {
                    Task { try? await ytPlayer.play() }
                    wasPlayingBeforeHidden = false
                }
            } else {
                wasPlayingBeforeHidden = true
                Task { try? await ytPlayer.pause() }
            }
            #endif
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
        // Re-registering on every appearance used to stack observers on the same item,
        // so a looping trailer fired several seek+play pairs per lap and thrashed the
        // buffer it had just filled.
        removeAVEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            if loops {
                player.seek(to: .zero)
                // The session is still armed from the initial start, so stall recovery
                // continues to cover the next lap.
                player.play()
            } else {
                onPlaybackEnded?()
            }
        }
    }

    private func removeAVEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    // MARK: - URL resolution helpers

    private static func resolveDirectMediaURL(from value: String) -> URL? {
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            let ext = url.pathExtension.lowercased()
            if ["mp4", "mov", "m4v", "m3u8", "ts"].contains(ext) {
                return url
            }
            // Some CDN/HLS URLs embed the format in the path without a clean extension
            let path = url.path.lowercased()
            if path.contains(".m3u8") || path.contains("/playlist") || path.contains("/master") {
                return url
            }
            // Treat any non-YouTube HTTP URL as direct media (addon URLs are already validated)
            let host = url.host?.lowercased() ?? ""
            if !host.contains("youtube.com") && !host.contains("youtu.be") && !host.contains("youtube-nocookie.com") {
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
            #if !os(macOS) && !os(tvOS)
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
