//
//  HeroCarouselView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct HeroCarouselView: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    
    @State private var currentIndex = 0
    @State private var autoScrollTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    @StateObject private var trailerLoader = HeroTrailerLoader()
    @State private var isMuted = true
    @State private var isTrailerPlaying = false
    @State private var showMuteButton = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background blur of current slide
                if let currentItem = items[safe: currentIndex] {
                    BackdropImageView(backdropPath: currentItem.backdropPath)
                        .frame(width: geometry.size.width, height: geometry.size.width * 9.0 / 16.0)
                        .blur(radius: 30)
                        .opacity(0.5)
                }
                
                // Main carousel
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HeroCarouselSlide(
                            item: item,
                            isActive: index == currentIndex,
                            trailerKey: trailerLoader.trailerKeys[item.id],
                            isMuted: $isMuted,
                            isTrailerPlaying: $isTrailerPlaying,
                            onTap: { onItemTap(item) },
                            geometry: geometry
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Bottom overlay: page indicators + mute button
                HStack {
                    // Page indicators
                    HStack(spacing: 8) {
                        ForEach(0..<min(items.count, 10), id: \.self) { index in
                            Capsule()
                                .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                                .frame(width: index == currentIndex ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentIndex)
                        }
                    }
                    
                    Spacer()
                    
                    // Mute/Unmute button - only visible when trailer is playing
                    if showMuteButton {
                        Button {
                            isMuted.toggle()
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial.opacity(0.8))
                                .clipShape(Circle())
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(width: geometry.size.width, height: geometry.size.width * 9.0 / 16.0)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .aspectRatio(16.0/9.0, contentMode: .fit)
        }
        .onReceive(autoScrollTimer) { _ in
            guard items.count > 1 else { return }
            // Only auto-scroll if trailer is NOT playing
            if !isTrailerPlaying {
                withAnimation(.easeInOut(duration: 0.9)) {
                    currentIndex = (currentIndex + 1) % items.count
                }
            }
        }
        .onChange(of: items.count) { _, newCount in
            if newCount == 0 {
                currentIndex = 0
            } else if currentIndex >= newCount {
                currentIndex = 0
            }
        }
        .onChange(of: isTrailerPlaying) { _, playing in
            withAnimation(.easeInOut(duration: 0.3)) {
                showMuteButton = playing
            }
        }
        .onChange(of: currentIndex) { _, _ in
            // Reset playing state when slide changes
            isTrailerPlaying = false
            showMuteButton = false
            // Reset to muted for new slides
            isMuted = true
        }
        .task {
            await trailerLoader.loadTrailers(for: items)
        }
        .onChange(of: items) { _, newItems in
            Task {
                await trailerLoader.loadTrailers(for: newItems)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }
}

// MARK: - Hero Carousel Slide
struct HeroCarouselSlide: View {
    let item: MediaItem
    let isActive: Bool
    let trailerKey: String?
    @Binding var isMuted: Bool
    @Binding var isTrailerPlaying: Bool
    let onTap: () -> Void
    let geometry: GeometryProxy
    
    @State private var localIsPlaying = false
    @State private var showTrailer = false
    @State private var trailerAppearDelay: Task<Void, Never>?
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Trailer layer (behind backdrop initially, then cross-fades in)
            if isActive, let key = trailerKey, showTrailer {
                InlineTrailerPlayerView(
                    videoKey: key,
                    isMuted: $isMuted,
                    isPlaying: $localIsPlaying
                )
                .frame(width: geometry.size.width, height: geometry.size.width * 9.0 / 16.0)
                .opacity(localIsPlaying ? 1 : 0)
                .animation(.easeInOut(duration: 0.8), value: localIsPlaying)
            }
            
            // Static backdrop image (visible until trailer plays)
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
            .frame(width: geometry.size.width, height: geometry.size.width * 9.0 / 16.0)
            .clipped()
            .opacity(localIsPlaying ? 0 : 1)
            .animation(.easeInOut(duration: 0.8), value: localIsPlaying)
            
            // Gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.7), .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            
            // Content overlay
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                Text(item.displayTitle)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
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
                }
                .font(.subheadline)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onChange(of: isActive) { _, active in
            if active {
                startTrailerDelay()
            } else {
                cancelTrailerDelay()
                showTrailer = false
                localIsPlaying = false
            }
        }
        .onChange(of: localIsPlaying) { _, playing in
            if isActive {
                isTrailerPlaying = playing
            }
        }
        .onAppear {
            if isActive {
                startTrailerDelay()
            }
        }
        .onDisappear {
            cancelTrailerDelay()
            showTrailer = false
            localIsPlaying = false
        }
    }
    
    private func startTrailerDelay() {
        cancelTrailerDelay()
        guard trailerKey != nil else { return }
        // Delay before showing the trailer to let the user see the backdrop first
        trailerAppearDelay = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            guard !Task.isCancelled else { return }
            await MainActor.run {
                showTrailer = true
            }
        }
    }
    
    private func cancelTrailerDelay() {
        trailerAppearDelay?.cancel()
        trailerAppearDelay = nil
    }
}

// MARK: - Hero Trailer Loader
@MainActor
class HeroTrailerLoader: ObservableObject {
    @Published var trailerKeys: [Int: String] = [:] // mediaId -> YouTube key
    private var loadedItemIds = Set<Int>()
    
    func loadTrailers(for items: [MediaItem]) async {
        let newItems = items.filter { !loadedItemIds.contains($0.id) }
        guard !newItems.isEmpty else { return }
        
        // Load trailers concurrently for all hero items
        await withTaskGroup(of: (Int, String?).self) { group in
            for item in newItems.prefix(10) {
                group.addTask {
                    let key = await self.fetchTrailerKey(for: item)
                    return (item.id, key)
                }
            }
            
            for await (id, key) in group {
                loadedItemIds.insert(id)
                if let key = key {
                    trailerKeys[id] = key
                }
            }
        }
    }
    
    private func fetchTrailerKey(for item: MediaItem) async -> String? {
        do {
            let videos: VideosResponse
            if item.resolvedMediaType == .movie {
                videos = try await TMDBService.shared.getMovieVideos(id: item.id)
            } else {
                videos = try await TMDBService.shared.getTVShowVideos(id: item.id)
            }
            
            // Find the best trailer
            let ytVideos = videos.results.filter { $0.site.lowercased() == "youtube" }
            
            // Prefer official trailers, exclude final trailers
            let trailers = ytVideos.filter { video in
                let type = video.type.lowercased()
                let name = video.name.lowercased()
                let isTrailer = type == "trailer" || type == "teaser"
                let isFinal = name.contains("final trailer") || name.contains("final teaser")
                return isTrailer && !isFinal
            }
            
            // Scoring: official > non-official, trailer > teaser
            let scored = trailers.sorted { v1, v2 in
                var s1 = 0, s2 = 0
                if v1.official == true { s1 += 10 }
                if v2.official == true { s2 += 10 }
                if v1.type.lowercased() == "trailer" { s1 += 5 }
                if v2.type.lowercased() == "trailer" { s2 += 5 }
                if v1.name.lowercased().contains("official trailer") { s1 += 3 }
                if v2.name.lowercased().contains("official trailer") { s2 += 3 }
                return s1 > s2
            }
            
            return scored.first?.key
        } catch {
            return nil
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
