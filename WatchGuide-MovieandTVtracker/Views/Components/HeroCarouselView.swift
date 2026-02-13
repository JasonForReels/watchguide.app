//
//  HeroCarouselView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import Combine
import YouTubePlayerKit

struct HeroCarouselView: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    
    @State private var currentIndex = 0
    @State private var autoScrollTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    @StateObject private var trailerLoader = HeroTrailerLoader()
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main carousel — edge-to-edge
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    GeometryReader { geometry in
                        HeroCarouselSlide(
                            item: item,
                            isActive: index == currentIndex,
                            trailerKey: trailerLoader.trailerKeys[item.id],
                            onTap: { onItemTap(item) },
                            geometry: geometry,
                            colorScheme: colorScheme
                        )
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Bottom fade overlay that blends into the page background
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: Color(UIColor.systemBackground).opacity(0), location: 0),
                        .init(color: Color(UIColor.systemBackground).opacity(0.4), location: 0.3),
                        .init(color: Color(UIColor.systemBackground).opacity(0.75), location: 0.55),
                        .init(color: Color(UIColor.systemBackground).opacity(0.92), location: 0.75),
                        .init(color: Color(UIColor.systemBackground), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .allowsHitTesting(false)
            }
            
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<min(items.count, 10), id: \.self) { index in
                    Capsule()
                        .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                        .frame(width: index == currentIndex ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentIndex)
                }
            }
            .padding(.bottom, 16)
        }
        .aspectRatio(16.0/10.0, contentMode: .fit)
        .onReceive(autoScrollTimer) { _ in
            guard items.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.9)) {
                currentIndex = (currentIndex + 1) % items.count
            }
        }
        .onChange(of: items.count) { _, newCount in
            if newCount == 0 { currentIndex = 0 }
            else if currentIndex >= newCount { currentIndex = 0 }
        }
        .task {
            await trailerLoader.loadTrailers(for: items)
        }
    }
}

// MARK: - Trailer Loader
@MainActor
class HeroTrailerLoader: ObservableObject {
    @Published var trailerKeys: [Int: String] = [:]
    
    func loadTrailers(for items: [MediaItem]) async {
        await withTaskGroup(of: (Int, String?).self) { group in
            for item in items.prefix(10) {
                group.addTask {
                    do {
                        let videos: VideosResponse
                        if item.resolvedMediaType == .movie {
                            videos = try await TMDBService.shared.getMovieVideos(id: item.id)
                        } else {
                            videos = try await TMDBService.shared.getTVShowVideos(id: item.id)
                        }
                        let key = HeroTrailerLoader.pickTrailerKey(from: videos.results)
                        return (item.id, key)
                    } catch {
                        return (item.id, nil)
                    }
                }
            }
            for await (id, key) in group {
                if let key = key {
                    trailerKeys[id] = key
                }
            }
        }
    }
    
    nonisolated static func pickTrailerKey(from videos: [Video]) -> String? {
        let yt = videos.filter { $0.site.lowercased() == "youtube" }
        let trailers = yt.filter { v in
            let type = v.type.lowercased()
            let name = v.name.lowercased()
            let isTrailer = type == "trailer" || type == "teaser"
            let isFinal = name.contains("final trailer") || name.contains("final teaser") || name.contains("final")
            return isTrailer && !isFinal
        }
        if let official = trailers.first(where: { $0.type.lowercased() == "trailer" && $0.official == true }) {
            return official.key
        }
        if let officialTeaser = trailers.first(where: { $0.type.lowercased() == "teaser" && $0.official == true }) {
            return officialTeaser.key
        }
        return trailers.first?.key
    }
}

// MARK: - Hero Carousel Slide
struct HeroCarouselSlide: View {
    let item: MediaItem
    let isActive: Bool
    let trailerKey: String?
    let onTap: () -> Void
    let geometry: GeometryProxy
    let colorScheme: ColorScheme
    
    @State private var showTrailer = false
    @StateObject private var playerVM = HeroPlayerViewModel()
    
    private var slideWidth: CGFloat { geometry.size.width }
    private var slideHeight: CGFloat { geometry.size.height }
    
    /// True when the YouTube player is loaded and ready — backdrop should hide
    private var trailerIsVisible: Bool {
        showTrailer && playerVM.isReady
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Layer 0: Black base so there's no flash when backdrop fades
            Color.black
            
            // Layer 1: Backdrop image — fades out once the trailer is ready
            backdropImage
                .opacity(trailerIsVisible ? 0 : 1)
                .animation(.easeInOut(duration: 0.6), value: trailerIsVisible)
            
            // Layer 2: Trailer video (sits behind the backdrop until backdrop fades)
            if showTrailer, let player = playerVM.player {
                YouTubePlayerKit.YouTubePlayerView(player)
                    .frame(width: slideWidth, height: slideHeight)
                    .allowsHitTesting(false)
            }
            
            // Layer 2b: Re-draw backdrop on top while trailer loads (crossfade)
            if showTrailer && !playerVM.isReady {
                backdropImage
                    .allowsHitTesting(false)
            }
            
            // Layer 3: Bottom vignette / scrim for text legibility
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.25), location: 0.25),
                        .init(color: .black.opacity(0.6), location: 0.55),
                        .init(color: .black.opacity(0.85), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: slideHeight * 0.6)
            }
            .allowsHitTesting(false)
            
            // Layer 4: Content overlay — title, meta, controls
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                
                Text(item.displayTitle)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                
                HStack(spacing: 12) {
                    if let year = item.year {
                        Text(year)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    if let rating = item.voteAverage, rating > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", rating))
                                .foregroundColor(.white)
                        }
                    }
                    
                    if trailerIsVisible {
                        Text("TRAILER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 50)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Layer 5: Mute button (top-right when trailer is playing)
            if trailerIsVisible {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            playerVM.toggleMute()
                        } label: {
                            Image(systemName: playerVM.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(.black.opacity(0.5)))
                        }
                        .padding(.top, 52)
                        .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .frame(width: slideWidth, height: slideHeight)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onChange(of: isActive) { _, active in
            if active {
                startTrailerIfNeeded()
            } else {
                stopTrailer()
            }
        }
        .onAppear {
            if isActive {
                startTrailerIfNeeded()
            }
        }
        .onDisappear {
            stopTrailer()
        }
    }
    
    private var backdropImage: some View {
        AsyncImage(url: TMDBService.shared.imageURL(path: item.backdropPath, size: .backdrop)) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay { ProgressView() }
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
            @unknown default:
                Rectangle().fill(Color(.systemGray5))
            }
        }
        .frame(width: slideWidth, height: slideHeight)
        .clipped()
    }
    
    private func startTrailerIfNeeded() {
        guard let key = trailerKey else { return }
        showTrailer = true
        playerVM.setup(videoKey: key)
    }
    
    private func stopTrailer() {
        showTrailer = false
        playerVM.teardown()
    }
}

// MARK: - Hero Player ViewModel
class HeroPlayerViewModel: ObservableObject {
    @Published var player: YouTubePlayer?
    @Published var isReady = false
    @Published var isMuted = true
    
    private var cancellable: AnyCancellable?
    
    @MainActor
    func setup(videoKey: String) {
        guard player == nil else { return }
        
        let startMuted = StorageService.shared.settings.autoPlayTrailersMuted
        isMuted = startMuted
        
        let ytPlayer = YouTubePlayer(
            source: .video(id: videoKey),
            parameters: .init(
                autoPlay: true,
                loopEnabled: true,
                showControls: false,
                showFullscreenButton: false,
                keyboardControlsDisabled: true,
                restrictRelatedVideosToSameChannel: true
            ),
            configuration: .init(
                allowsInlineMediaPlayback: true
            )
        )
        
        player = ytPlayer
        
        cancellable = ytPlayer.statePublisher.sink { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isReady = true
                    Task {
                        if self.isMuted {
                            try? await ytPlayer.mute()
                        } else {
                            try? await ytPlayer.unmute()
                        }
                    }
                default:
                    break
                }
            }
        }
    }
    
    func teardown() {
        Task { @MainActor in
            if let p = player {
                try? await p.pause()
            }
            player = nil
            isReady = false
            cancellable = nil
        }
    }
    
    func toggleMute() {
        isMuted.toggle()
        guard let p = player else { return }
        Task {
            if isMuted {
                try? await p.mute()
            } else {
                try? await p.unmute()
            }
        }
    }
}

// MARK: - Array Extension
extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

#Preview {
    HeroCarouselView(items: [], onItemTap: { _ in })
}
