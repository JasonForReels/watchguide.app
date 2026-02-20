//
//  InAppYouTubePlayer.swift
//  WatchGuide-MovieandTVtracker
//
//  Embedded YouTube player using YouTubePlayerKit (SPM).
//  Uses the official YouTube IFrame Player API bridge — handles
//  Referer headers, embed restrictions, and Error 153 automatically.
//

import SwiftUI

#if !os(tvOS)
import YouTubePlayerKit

// MARK: - Embedded Trailer Player View (plays inline with controls overlay)
struct EmbeddedTrailerPlayer: View {
    let videoKey: String
    let title: String
    var compact: Bool = false
    var autoPlay: Bool = true

    @StateObject private var player: YouTubePlayer

    @State private var isMuted: Bool
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var isReady = false
    @State private var hasError = false

    init(videoKey: String, title: String, compact: Bool = false, autoPlay: Bool = true) {
        self.videoKey = videoKey
        self.title = title
        self.compact = compact
        self.autoPlay = autoPlay
        
        let startMuted = StorageService.shared.settings.autoPlayTrailersMuted
        _isMuted = State(initialValue: startMuted)
        
        _player = StateObject(wrappedValue: YouTubePlayer(
            source: .video(id: videoKey),
            parameters: .init(
                autoPlay: autoPlay,
                loopEnabled: true,
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

    var body: some View {
        ZStack {
            Color.black

            // YouTube Player (from YouTubePlayerKit)
            YouTubePlayerKit.YouTubePlayerView(player)
                .opacity(isReady ? 1 : 0)
                .animation(.easeIn(duration: 0.3), value: isReady)

            // Loading state
            if !isReady && !hasError {
                loadingOverlay
            }

            // Error fallback
            if hasError {
                TrailerErrorFallback(videoKey: videoKey, title: title, compact: compact)
            }

            // Custom controls overlay (only when ready)
            if isReady && !hasError {
                controlsOverlay
            }
        }
        .aspectRatio(16.0/9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14))
        .onReceive(player.statePublisher) { state in
            switch state {
            case .ready:
                isReady = true
                hasError = false
                // Apply mute preference then explicitly start playback.
                // On real devices WebKit blocks autoplay unless we mute first
                // and then call play() explicitly after the player is ready.
                let shouldMute = StorageService.shared.settings.autoPlayTrailersMuted
                Task {
                    // Always mute first to satisfy iOS autoplay policy
                    try? await player.mute()
                    // Explicitly start playback (autoPlay param alone is unreliable on real devices)
                    try? await player.play()
                    // Then apply the user's actual mute preference
                    if !shouldMute {
                        try? await player.unmute()
                    }
                }
            case .error:
                hasError = true
            default:
                break
            }
        }
        .onAppear {
            scheduleControlsHide()
        }
        .onDisappear {
            controlsTimer?.invalidate()
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoKey)/maxresdefault.jpg")) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .aspectRatio(16.0/9.0, contentMode: .fill)
                }
            }
            Color.black.opacity(0.4)
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
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

                    HStack(spacing: 12) {
                        Button {
                            isMuted.toggle()
                            Task {
                                if isMuted {
                                    try? await player.mute()
                                } else {
                                    try? await player.unmute()
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
                            colors: [.clear, .black.opacity(0.6)],
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
                withAnimation(.easeOut(duration: 0.3)) {
                    showControls = false
                }
            }
        }
    }
}

// MARK: - Error Fallback (thumbnail with play button, opens YouTube externally)
struct TrailerErrorFallback: View {
    let videoKey: String
    let title: String
    var compact: Bool = false

    var body: some View {
        ZStack {
            AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoKey)/maxresdefault.jpg")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(16.0/9.0, contentMode: .fill)
                default:
                    Color(.systemGray5)
                }
            }

            Color.black.opacity(0.35)

            Button {
                if let url = URL(string: "https://www.youtube.com/watch?v=\(videoKey)") {
                    PlatformURLHandler.openURL(url)
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
}

// MARK: - Full Screen YouTube Player Sheet
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
                    EmbeddedTrailerPlayer(
                        videoKey: videoKey,
                        title: title
                    )
                    .padding(.horizontal)
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Legacy InAppYouTubePlayer (kept for API compat)
struct InAppYouTubePlayer: View {
    let videoKey: String
    var autoplay: Bool = true

    var body: some View {
        EmbeddedTrailerPlayer(videoKey: videoKey, title: "Trailer")
    }
}

#else
// tvOS fallback: no in-app player support.
struct EmbeddedTrailerPlayer: View {
    let videoKey: String
    let title: String
    var compact: Bool = false
    var autoPlay: Bool = true

    var body: some View {
        TrailerErrorFallback(videoKey: videoKey, title: title, compact: compact)
    }
}

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
                    Color(.systemGray5)
                }
            }

            Color.black.opacity(0.35)

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
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14))
    }
}

struct YouTubePlayerSheet: View {
    let videoKey: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                TrailerErrorFallback(videoKey: videoKey, title: title)
                    .padding(.horizontal)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.white.opacity(0.25))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

struct InAppYouTubePlayer: View {
    let videoKey: String
    var autoplay: Bool = true

    var body: some View {
        EmbeddedTrailerPlayer(videoKey: videoKey, title: "Trailer", compact: false, autoPlay: false)
    }
}
#endif
