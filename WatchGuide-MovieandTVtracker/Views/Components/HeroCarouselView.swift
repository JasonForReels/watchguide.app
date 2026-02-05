//
//  HeroCarouselView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import WebKit
import UIKit

struct HeroCarouselView: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    
    @State private var currentIndex = 0
    @State private var timer: Timer?
    @State private var trailers: [Int: Video] = [:] // mediaId -> trailer
    @State private var trailerCandidates: [Int: [Video]] = [:] // mediaId -> fallback trailers
    @State private var preloadedStreamURLs: [String: String] = [:] // videoKey -> streamURL
    @State private var isPlayingTrailer = false
    @State private var borderRotation: Angle = .degrees(0)
    @State private var borderAnimating: Bool = true
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    private var autoPlayEnabled: Bool {
        StorageService.shared.settings.autoPlayTrailers
    }
    
    // Adaptive height based on orientation
    private var carouselHeight: CGFloat {
        verticalSizeClass == .compact ? 280 : 400
    }
    
    private var animatedBorderGradient: AngularGradient {
        let base = UIColor(ambientColor)
        // Generate complementary and analogous colors for a pleasing gradient
        let components = base.cgColor.components ?? [0.2, 0.2, 0.2, 1]
        let r = components[0], g = components[1], b = components[2]
        let lighten = Color(red: min(r + 0.2, 1), green: min(g + 0.2, 1), blue: min(b + 0.2, 1))
        let darken = Color(red: max(r - 0.2, 0), green: max(g - 0.2, 0), blue: max(b - 0.2, 0))
        let colors: [Color] = [Color(ambientColor), lighten, Color(ambientColor), darken]
        return AngularGradient(gradient: Gradient(colors: colors), center: .center, angle: borderRotation)
    }
    
    @State private var ambientColor: Color = .black
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background blur
                if let currentItem = items[safe: currentIndex] {
                    BackdropImageView(backdropPath: currentItem.backdropPath)
                        .frame(width: geometry.size.width, height: geometry.size.width * 9.0 / 16.0)
                        .blur(radius: 30)
                        .opacity(0.5)
                }
                
                // Main carousel
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HeroSlideView(
                            item: item,
                            width: geometry.size.width,
                            height: geometry.size.width * 9.0 / 16.0,
                            trailer: trailers[item.id],
                            trailerCandidates: trailerCandidates[item.id] ?? [],
                            preloadedStreamURL: preloadedStreamURLs[trailers[item.id]?.key ?? ""],
                            isCurrentSlide: index == currentIndex,
                            autoPlayEnabled: autoPlayEnabled,
                            isPlayingTrailer: $isPlayingTrailer,
                            onTrailerEnded: {
                                // Advance to next item when trailer ends
                                advanceToNextItem()
                            },
                            onTrailerFailed: { error in
                                print("All trailers failed for \(item.displayTitle): \(error)")
                            }
                        )
                        .tag(index)
                        .onTapGesture {
                            onItemTap(item)
                        }
                        .onAppear {
                            // Update ambient color when this slide appears
                            if let path = item.backdropPath, let url = TMDBService.shared.imageURL(path: path, size: .backdrop) {
                                Task {
                                    if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                                        updateAmbientColor(from: ui)
                                    }
                                }
                            }
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
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
            .frame(width: geometry.size.width, height: geometry.size.width * 9.0 / 16.0)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(animatedBorderGradient, lineWidth: 2)
                    .allowsHitTesting(false)
            )
            .aspectRatio(16.0/9.0, contentMode: .fit)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .onAppear {
            startAutoScroll()
            loadTrailers()
            // After a short delay, attempt to start trailer for first item if available
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                attemptStartTrailerForFirstItem()
            }
            startBorderAnimation()
        }
        .onDisappear {
            stopAutoScroll()
            stopBorderAnimation()
        }
        .onChange(of: currentIndex) { _, _ in
            // Reset trailer state when switching slides
            isPlayingTrailer = false
            // Restart auto-scroll timer after manual swipe
            restartAutoScroll()
            // Notify other views about index change
            NotificationCenter.default.post(name: Notification.Name("HeroCarouselIndexChanged"), object: NSNumber(value: currentIndex))
        }
        .preferredColorScheme(StorageService.shared.settings.ambientModeEnabled ? .dark : nil)
    }
    
    private func advanceToNextItem() {
        withAnimation(.easeInOut(duration: 0.5)) {
            currentIndex = (currentIndex + 1) % max(items.count, 1)
        }
        isPlayingTrailer = false
        restartAutoScroll()
    }
    
    private func startAutoScroll() {
        guard !isPlayingTrailer else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { _ in
            if !isPlayingTrailer {
                withAnimation {
                    currentIndex = (currentIndex + 1) % max(items.count, 1)
                }
            }
        }
    }
    
    private func restartAutoScroll() {
        stopAutoScroll()
        startAutoScroll()
    }
    
    private func stopAutoScroll() {
        timer?.invalidate()
        timer = nil
    }
    
    private func loadTrailers() {
        Task {
            // Prioritize fetching the first item's trailer immediately so it can play
            if let first = items.first {
                do {
                    let videos: VideosResponse
                    if first.resolvedMediaType == .movie {
                        videos = try await TMDBService.shared.getMovieVideos(id: first.id)
                    } else {
                        videos = try await TMDBService.shared.getTVShowVideos(id: first.id)
                    }
                    let candidates = selectTrailerCandidates(from: videos.results, limit: 3)
                    if let best = candidates.first {
                        await MainActor.run {
                            trailers[first.id] = best
                            trailerCandidates[first.id] = candidates
                        }
                        // Preload stream URL for faster playback
                        if let streamURL = await preloadStreamURL(for: best.key) {
                            await MainActor.run {
                                preloadedStreamURLs[best.key] = streamURL
                            }
                        }
                    }
                } catch {
                    print("Error loading trailer for first item: \(error)")
                }
            }
            
            // Load remaining trailers concurrently for faster loading
            await withTaskGroup(of: (Int, [Video]).self) { group in
                for item in items.prefix(10).dropFirst() {
                    group.addTask {
                        do {
                            let videos: VideosResponse
                            if item.resolvedMediaType == .movie {
                                videos = try await TMDBService.shared.getMovieVideos(id: item.id)
                            } else {
                                videos = try await TMDBService.shared.getTVShowVideos(id: item.id)
                            }
                            let candidates = self.selectTrailerCandidates(from: videos.results, limit: 3)
                            return (item.id, candidates)
                        } catch {
                            print("Error loading trailer for \(item.displayTitle): \(error)")
                            return (item.id, [])
                        }
                    }
                }
                
                for await (itemId, candidates) in group {
                    if let first = candidates.first {
                        await MainActor.run {
                            trailers[itemId] = first
                            trailerCandidates[itemId] = candidates
                        }
                        // Preload stream URLs for next few items
                        if let streamURL = await preloadStreamURL(for: first.key) {
                            await MainActor.run {
                                preloadedStreamURLs[first.key] = streamURL
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Preload stream URL from Invidious for faster playback
    private func preloadStreamURL(for videoKey: String) async -> String? {
        let instances = [
            "https://inv.nadeko.net",
            "https://invidious.nerdvpn.de",
            "https://invidious.privacyredirect.com"
        ]
        
        for instance in instances {
            let apiURL = "\(instance)/api/v1/videos/\(videoKey)"
            guard let url = URL(string: apiURL) else { continue }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    continue
                }
                
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                
                // Get format streams (combined audio+video, faster to load)
                if let formatStreams = json["formatStreams"] as? [[String: Any]] {
                    let sorted = formatStreams.sorted { a, b in
                        let qualityA = (a["qualityLabel"] as? String) ?? ""
                        let qualityB = (b["qualityLabel"] as? String) ?? ""
                        return qualityPriority(qualityA) > qualityPriority(qualityB)
                    }
                    
                    if let best = sorted.first, let streamUrl = best["url"] as? String {
                        return streamUrl
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
    
    private func qualityPriority(_ quality: String) -> Int {
        if quality.contains("720") { return 100 }
        if quality.contains("480") { return 90 }
        if quality.contains("360") { return 80 }
        if quality.contains("1080") { return 70 }
        return 0
    }
    
    private func ensureCurrentHasTrailerOrAdvance() {
        guard autoPlayEnabled, !items.isEmpty else { return }
        let currentItem = items[currentIndex]
        if trailers[currentItem.id] != nil { return }
        if let nextIndex = items.prefix(10).firstIndex(where: { trailers[$0.id] != nil }) {
            withAnimation { currentIndex = nextIndex }
        }
    }
    
    private nonisolated func selectBestOfficialTrailer(from videos: [Video]) -> Video? {
        // Filter to only YouTube trailers (excluding teasers)
        let trailers = videos.filter {
            $0.site.lowercased() == "youtube" &&
            $0.type == "Trailer"
        }
        
        guard !trailers.isEmpty else { return nil }
        
        // Keywords that indicate this is NOT a standard "Official Trailer"
        let excludeKeywords = ["final", "teaser", "tv spot", "featurette", "clip", "behind", "making of", "interview", "red band"]
        
        // Keywords that indicate this IS an official trailer we want
        let preferKeywords = ["official trailer", "theatrical trailer", "main trailer"]
        
        // Score and sort trailers
        let scored = trailers.map { video -> (video: Video, score: Int) in
            var score = 0
            let nameLower = video.name.lowercased()
            
            // Strong preference for official trailers (these are less likely to have embed restrictions)
            if video.official == true {
                score += 100
            }
            
            // Boost for preferred keywords
            for keyword in preferKeywords {
                if nameLower.contains(keyword) {
                    score += 50
                    break
                }
            }
            
            // Penalize excluded keywords (final trailer, teaser, etc.)
            for keyword in excludeKeywords {
                if nameLower.contains(keyword) {
                    score -= 200
                    break
                }
            }
            
            // Simple "trailer" in name is good
            if nameLower.contains("trailer") && !nameLower.contains("teaser") {
                score += 20
            }
            
            // Numbered trailers (Trailer 2, Trailer 3) get lower priority
            if nameLower.contains("trailer 2") || nameLower.contains("trailer 3") || nameLower.contains("trailer #2") || nameLower.contains("trailer #3") {
                score -= 30
            }
            
            return (video, score)
        }
        
        // Sort by score descending
        let sorted = scored.sorted { $0.score > $1.score }
        
        // Return multiple candidates so we can try alternatives if first fails
        return sorted.first?.video
    }
    
    /// Returns sorted list of trailer candidates for fallback support
    private nonisolated func selectTrailerCandidates(from videos: [Video], limit: Int = 3) -> [Video] {
        let trailers = videos.filter {
            $0.site.lowercased() == "youtube" &&
            ($0.type == "Trailer" || $0.type == "Teaser")
        }
        
        guard !trailers.isEmpty else { return [] }
        
        let excludeKeywords = ["tv spot", "featurette", "clip", "behind", "making of", "interview"]
        let preferKeywords = ["official trailer", "theatrical trailer", "main trailer"]
        
        let scored = trailers.map { video -> (video: Video, score: Int) in
            var score = 0
            let nameLower = video.name.lowercased()
            
            if video.official == true { score += 100 }
            
            for keyword in preferKeywords {
                if nameLower.contains(keyword) { score += 50; break }
            }
            
            for keyword in excludeKeywords {
                if nameLower.contains(keyword) { score -= 200; break }
            }
            
            if nameLower.contains("trailer") && !nameLower.contains("teaser") { score += 20 }
            if video.type == "Teaser" { score -= 10 }
            
            return (video, score)
        }
        
        return scored.sorted { $0.score > $1.score }.prefix(limit).map { $0.video }
    }
    
    private func startBorderAnimation() {
        borderAnimating = true
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            borderRotation = .degrees(360)
        }
    }
    
    private func stopBorderAnimation() {
        borderAnimating = false
        borderRotation = .degrees(0)
    }
    
    private func updateAmbientColor(from uiImage: UIImage) {
        if let avg = uiImage.averageColor() {
            ambientColor = Color(avg)
        } else {
            ambientColor = .black
        }
    }
    
    private func attemptStartTrailerForFirstItem() {
        guard autoPlayEnabled, !items.isEmpty else { return }
        
        currentIndex = 0
        let firstItemId = items[0].id
        
        if trailers[firstItemId] != nil {
            // Post notification and try to start trailer soon
            NotificationCenter.default.post(name: Notification.Name("HeroCarouselIndexChanged"), object: NSNumber(value: currentIndex))
            isPlayingTrailer = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isPlayingTrailer = true
            }
            return
        }
        
        var attempts = 0
        func pollForTrailer() {
            attempts += 1
            if trailers[firstItemId] != nil {
                NotificationCenter.default.post(name: Notification.Name("HeroCarouselIndexChanged"), object: NSNumber(value: currentIndex))
                isPlayingTrailer = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isPlayingTrailer = true
                }
            } else if attempts < 15 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    pollForTrailer()
                }
            }
            // If no trailer found after polling, do nothing (do not advance)
        }
        pollForTrailer()
    }
}

// MARK: - Hero Slide View
struct HeroSlideView: View {
    let item: MediaItem
    let width: CGFloat
    var height: CGFloat = 400
    let trailer: Video?
    let trailerCandidates: [Video]
    let preloadedStreamURL: String?
    let isCurrentSlide: Bool
    let autoPlayEnabled: Bool
    @Binding var isPlayingTrailer: Bool
    var onTrailerEnded: (() -> Void)?
    var onTrailerFailed: ((String) -> Void)?
    
    @State private var showTrailer = false
    @State private var trailerReady = false
    @State private var trailerFailed = false
    @State private var trailerKey: String = ""
    @State private var streamURL: String = ""
    @State private var currentTrailerIndex: Int = 0
    @State private var isMuted: Bool = StorageService.shared.settings.autoPlayTrailersMuted
    @State private var ambientColor: Color = .black
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }
    
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    
    // Show the video player element when trailer should be loading
    private var shouldShowTrailerPlayer: Bool {
        showTrailer && !trailerFailed && trailer != nil && autoPlayEnabled && isCurrentSlide && !trailerKey.isEmpty
    }
    
    // Only hide backdrop once trailer is actually ready and playing
    private var shouldHideBackdrop: Bool {
        shouldShowTrailerPlayer && trailerReady
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if StorageService.shared.settings.ambientModeEnabled {
                AmbientBackground(color: ambientColor)
            }
            
            // Show backdrop until trailer is ready and playing - with smooth fade out
            backdropView
                .frame(width: width, height: height)
                .clipped()
                .opacity(shouldHideBackdrop ? 0 : 1)
                .animation(.easeInOut(duration: 0.5), value: shouldHideBackdrop)
                .zIndex(0)
            
            // Video overlay (loads immediately, but backdrop stays until ready)
            if shouldShowTrailerPlayer {
                InvidiousPlayerView(
                    videoKey: trailerKey,
                    preloadedStreamURL: streamURL.isEmpty ? nil : streamURL,
                    autoPlay: true,
                    isMuted: isMuted,
                    onReady: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            trailerReady = true
                        }
                    },
                    onError: { error in
                        print("Trailer error: \(error)")
                        DispatchQueue.main.async {
                            // Try next candidate trailer if available
                            tryNextTrailerCandidate(afterError: error)
                        }
                    },
                    onEnded: {
                        // Trailer finished playing: hide overlay and restore backdrop/title immediately
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showTrailer = false
                            }
                            isPlayingTrailer = false
                            trailerKey = ""
                            streamURL = ""
                            onTrailerEnded?()
                        }
                    }
                )
                .frame(width: width, height: height)
                .clipped()
                .opacity(trailerReady ? 1 : 0) // Hide video player until ready
                .transition(.opacity)
                .zIndex(1)
            }
            
            // Gradient overlay (lighter when video is playing)
            LinearGradient(
                colors: [.clear, .black.opacity(shouldHideBackdrop ? 0.5 : 0.7), .black.opacity(shouldHideBackdrop ? 0.7 : 0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            .zIndex(2)
            
            // Content - adaptive layout for landscape
            VStack(alignment: .leading, spacing: isCompactHeight ? 6 : 12) {
                HStack {
                    // Media type badge
                    Text(item.resolvedMediaType == .movie ? "Movie" : "TV Show")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    
                    Spacer()
                    
                    // Trailer play button (hide if already playing or failed)
                    if trailer != nil && autoPlayEnabled && !trailerFailed && !shouldShowTrailerPlayer {
                        Button {
                            startTrailer()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                Text("Trailer")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .foregroundColor(.white)
                    }
                }
                
                Spacer()
                
                if !(isPhone && shouldHideBackdrop) {
                    Text(item.displayTitle)
                        .font(isCompactHeight ? .title2 : .title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(isCompactHeight ? 1 : 2)
                }
                
                // Info row
                HStack(spacing: 12) {
                    if let year = item.year {
                        Text(year)
                            .foregroundColor(.white.opacity(0.8))
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
                
                // Overview (hide when trailer is playing or in compact height)
                if !shouldHideBackdrop && !isCompactHeight, let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            .padding(isCompactHeight ? 16 : 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zIndex(3)
        }
        .aspectRatio(16.0/9.0, contentMode: .fill)
        .preferredColorScheme(StorageService.shared.settings.ambientModeEnabled ? .dark : nil)
        .onTapGesture {
            if shouldHideBackdrop && isMuted {
                isMuted = false
            }
        }
        .onChange(of: isCurrentSlide) { _, newValue in
            if !newValue {
                // Stop trailer when sliding away
                stopTrailer()
            } else if autoPlayEnabled && !trailerFailed {
                attemptAutoStartWithWait()
            }
        }
        .onChange(of: showTrailer) { oldValue, newValue in
            // Fallback: if trailer just stopped displaying while this is the current slide, advance immediately
            if oldValue == true && newValue == false && autoPlayEnabled {
                onTrailerEnded?()
            }
        }
        .onAppear {
            // Reset states when appearing
            trailerFailed = false
            trailerReady = false
            trailerKey = ""
            currentTrailerIndex = 0
            // Removed resetting isMuted to true here to preserve initial setting from StorageService
            // isMuted = true
            
            // Start trailer if this is the current slide and autoplay is enabled (wait if trailer not loaded yet)
            if isCurrentSlide && autoPlayEnabled {
                attemptAutoStartWithWait()
            }
        }
        .onDisappear {
            stopTrailer()
        }
    }
    
    // MARK: - Backdrop View
    @ViewBuilder
    private var backdropView: some View {
        AsyncImage(url: TMDBService.shared.imageURL(path: item.backdropPath, size: .backdrop)) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        ProgressView()
                    }
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .onAppear {
                        Task {
                            if let path = item.backdropPath, let url = TMDBService.shared.imageURL(path: path, size: .backdrop) {
                                if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                                    updateAmbientColor(from: ui)
                                }
                            }
                        }
                    }
            case .failure:
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
            @unknown default:
                Rectangle()
                    .fill(Color(.systemGray5))
            }
        }
    }
    
    // MARK: - Helper Methods
    private func startTrailer() {
        // Start with the first candidate (index 0)
        guard !trailerCandidates.isEmpty else {
            // Fall back to single trailer if no candidates
            guard let trailer = trailer, !trailer.key.isEmpty else {
                trailerFailed = true
                return
            }
            trailerKey = trailer.key
            streamURL = preloadedStreamURL ?? ""
            showTrailer = true
            isPlayingTrailer = true
            return
        }
        
        currentTrailerIndex = 0
        let candidate = trailerCandidates[currentTrailerIndex]
        
        trailerKey = candidate.key
        // Use preloaded stream URL if available for first trailer
        if currentTrailerIndex == 0 {
            streamURL = preloadedStreamURL ?? ""
        } else {
            streamURL = ""
        }
        showTrailer = true
        isPlayingTrailer = true
    }
    
    private func tryNextTrailerCandidate(afterError error: String) {
        // If we have more candidates to try, use the next one
        let nextIndex = currentTrailerIndex + 1
        
        if nextIndex < trailerCandidates.count {
            print("Trying fallback trailer \(nextIndex + 1) of \(trailerCandidates.count)")
            currentTrailerIndex = nextIndex
            let nextCandidate = trailerCandidates[nextIndex]
            
            // Reset state and try next
            trailerReady = false
            trailerKey = nextCandidate.key
            // Keep showTrailer true to load the next candidate
        } else {
            // No more candidates - mark as failed and hide
            print("All trailer candidates failed, showing backdrop")
            trailerFailed = true
            showTrailer = false
            isPlayingTrailer = false
            trailerKey = ""
            onTrailerFailed?(error)
        }
    }
    
    private func stopTrailer() {
        showTrailer = false
        trailerReady = false
        trailerKey = ""
        streamURL = ""
        currentTrailerIndex = 0
    }
    
    private func updateAmbientColor(from uiImage: UIImage) {
        if let avg = uiImage.averageColor() {
            ambientColor = Color(avg)
        } else {
            ambientColor = .black
        }
    }
    
    private func attemptAutoStartWithWait() {
        guard autoPlayEnabled && isCurrentSlide && !trailerFailed else { return }
        // If we already have a trailer, start shortly
        if trailer != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if isCurrentSlide && !trailerFailed {
                    startTrailer()
                }
            }
            return
        }
        // Otherwise, poll briefly for trailer availability (up to ~2 seconds)
        var attempts = 0
        func poll() {
            attempts += 1
            if trailer != nil && isCurrentSlide && !trailerFailed {
                startTrailer()
            } else if attempts < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    poll()
                }
            }
        }
        poll()
    }
}

// MARK: - Ambient Background View
struct AmbientBackground: View {
    let color: Color
    var body: some View {
        ZStack {
            color.opacity(0.6)
            RadialGradient(colors: [color.opacity(0.7), color.opacity(0.2), .black.opacity(0.8)], center: .center, startRadius: 0, endRadius: 800)
                .blendMode(.plusLighter)
        }
        .blur(radius: 60)
        .ignoresSafeArea()
    }
}

// MARK: - Invidious Proxy Player View for reliable trailer playback
struct InvidiousPlayerView: UIViewRepresentable {
    let videoKey: String
    var preloadedStreamURL: String?
    var autoPlay: Bool = false
    var isMuted: Bool = false
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?
    var onEnded: (() -> Void)?
    
    // Invidious instances sorted by reliability/speed
    private static let invidiousInstances = [
        "https://inv.nadeko.net",
        "https://invidious.nerdvpn.de",
        "https://invidious.privacyredirect.com",
        "https://iv.ggtyler.dev",
        "https://invidious.protokolla.fi"
    ]
    
    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "playerReady")
        contentController.add(context.coordinator, name: "playerError")
        contentController.add(context.coordinator, name: "playerEnded")
        contentController.add(context.coordinator, name: "playerPlaying")
        
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences = preferences
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard !videoKey.isEmpty else {
            DispatchQueue.main.async {
                self.onError?("Invalid video key")
            }
            return
        }
        
        if context.coordinator.currentVideoKey == videoKey && context.coordinator.lastMuteValue == isMuted {
            return
        }
        context.coordinator.currentVideoKey = videoKey
        context.coordinator.lastMuteValue = isMuted
        context.coordinator.hasErrored = false
        context.coordinator.currentInstanceIndex = 0
        
        // If we have a preloaded stream URL, use it directly for faster playback
        if let preloaded = preloadedStreamURL, !preloaded.isEmpty {
            context.coordinator.loadHTMLPlayer(webView: webView, streamURL: preloaded, autoPlay: autoPlay, isMuted: isMuted)
        } else {
            // Start fetching video stream URL from Invidious
            Task {
                await context.coordinator.loadVideoStream(
                    videoKey: videoKey,
                    webView: webView,
                    autoPlay: autoPlay,
                    isMuted: isMuted
                )
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            instances: Self.invidiousInstances,
            onReady: onReady,
            onError: onError,
            onEnded: onEnded
        )
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var currentVideoKey: String?
        var lastMuteValue: Bool? = nil
        var hasErrored: Bool = false
        var currentInstanceIndex: Int = 0
        let instances: [String]
        var onReady: (() -> Void)?
        var onError: ((String) -> Void)?
        var onEnded: (() -> Void)?
        
        init(instances: [String], onReady: (() -> Void)?, onError: ((String) -> Void)?, onEnded: (() -> Void)?) {
            self.instances = instances
            self.onReady = onReady
            self.onError = onError
            self.onEnded = onEnded
        }
        
        @MainActor
        func loadVideoStream(videoKey: String, webView: WKWebView, autoPlay: Bool, isMuted: Bool) async {
            // Try each Invidious instance until one works
            for (index, instance) in instances.enumerated() {
                currentInstanceIndex = index
                
                if let streamURL = await fetchStreamURL(from: instance, videoKey: videoKey) {
                    loadHTMLPlayer(webView: webView, streamURL: streamURL, autoPlay: autoPlay, isMuted: isMuted)
                    return
                }
            }
            
            // All instances failed
            hasErrored = true
            onError?("All proxy instances failed")
        }
        
        private func fetchStreamURL(from instance: String, videoKey: String) async -> String? {
            let apiURL = "\(instance)/api/v1/videos/\(videoKey)"
            
            guard let url = URL(string: apiURL) else { return nil }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 4 // Short timeout for faster fallback
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    return nil
                }
                
                // Parse JSON response
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }
                
                // Prefer format streams (combined audio+video) for faster loading
                if let formatStreams = json["formatStreams"] as? [[String: Any]] {
                    let sorted = formatStreams.sorted { a, b in
                        let qualityA = (a["qualityLabel"] as? String) ?? ""
                        let qualityB = (b["qualityLabel"] as? String) ?? ""
                        return qualityPriority(qualityA) > qualityPriority(qualityB)
                    }
                    
                    if let best = sorted.first, let streamUrl = best["url"] as? String {
                        return streamUrl
                    }
                }
                
                // Fallback to adaptive formats
                if let adaptiveFormats = json["adaptiveFormats"] as? [[String: Any]] {
                    let videoFormats = adaptiveFormats.filter { format in
                        guard let type = format["type"] as? String else { return false }
                        return type.contains("video/mp4")
                    }
                    
                    let sorted = videoFormats.sorted { a, b in
                        let qualityA = (a["qualityLabel"] as? String) ?? ""
                        let qualityB = (b["qualityLabel"] as? String) ?? ""
                        return qualityPriority(qualityA) > qualityPriority(qualityB)
                    }
                    
                    if let best = sorted.first, let streamUrl = best["url"] as? String {
                        return streamUrl
                    }
                }
                
                return nil
            } catch {
                print("Invidious fetch error from \(instance): \(error)")
                return nil
            }
        }
        
        private func qualityPriority(_ quality: String) -> Int {
            if quality.contains("720") { return 100 }
            if quality.contains("480") { return 90 }
            if quality.contains("360") { return 80 }
            if quality.contains("1080") { return 70 }
            if quality.contains("240") { return 60 }
            return 0
        }
        
        @MainActor
        func loadHTMLPlayer(webView: WKWebView, streamURL: String, autoPlay: Bool, isMuted: Bool) {
            let autoPlayAttr = autoPlay ? "autoplay" : ""
            let mutedAttr = isMuted ? "muted" : ""
            
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                <style>
                    * { margin: 0; padding: 0; box-sizing: border-box; }
                    html, body { 
                        width: 100%; 
                        height: 100%; 
                        overflow: hidden; 
                        background: #000;
                    }
                    #video-container {
                        position: absolute;
                        top: 50%;
                        left: 50%;
                        width: 177.78vh;
                        height: 100vh;
                        min-width: 100%;
                        min-height: 56.25vw;
                        transform: translate(-50%, -50%);
                    }
                    video {
                        position: absolute;
                        top: 0;
                        left: 0;
                        width: 100%;
                        height: 100%;
                        object-fit: cover;
                        background: #000;
                    }
                </style>
            </head>
            <body>
                <div id="video-container">
                    <video id="player" playsinline \(autoPlayAttr) \(mutedAttr)>
                        <source src="\(streamURL)" type="video/mp4">
                    </video>
                </div>
                
                <script>
                    var video = document.getElementById('player');
                    var hasNotifiedReady = false;
                    var hasNotifiedError = false;
                    var hasNotifiedEnded = false;
                    
                    function notifyReady() {
                        if (!hasNotifiedReady) {
                            hasNotifiedReady = true;
                            try { window.webkit.messageHandlers.playerReady.postMessage('ready'); } catch(e) {}
                        }
                    }
                    
                    function notifyPlaying() {
                        try { window.webkit.messageHandlers.playerPlaying.postMessage('playing'); } catch(e) {}
                    }
                    
                    function notifyError(msg) {
                        if (!hasNotifiedError) {
                            hasNotifiedError = true;
                            try { window.webkit.messageHandlers.playerError.postMessage(msg); } catch(e) {}
                        }
                    }
                    
                    function notifyEnded() {
                        if (!hasNotifiedEnded) {
                            hasNotifiedEnded = true;
                            try { window.webkit.messageHandlers.playerEnded.postMessage('ended'); } catch(e) {}
                        }
                    }
                    
                    // Notify ready when video starts playing
                    video.addEventListener('playing', function() {
                        notifyReady();
                        notifyPlaying();
                    });
                    
                    video.addEventListener('ended', notifyEnded);
                    
                    video.addEventListener('error', function(e) {
                        var msg = 'Video error';
                        if (video.error) {
                            msg = 'Error code: ' + video.error.code;
                        }
                        notifyError(msg);
                    });
                    
                    // Stall detection - if video stalls for too long, report error
                    video.addEventListener('stalled', function() {
                        setTimeout(function() {
                            if (!hasNotifiedReady && !hasNotifiedError && video.readyState < 3) {
                                notifyError('Video stalled');
                            }
                        }, 5000);
                    });
                    
                    // Timeout fallback - if nothing happens in 6 seconds, report error
                    setTimeout(function() {
                        if (!hasNotifiedReady && !hasNotifiedError) {
                            notifyError('Timeout loading video');
                        }
                    }, 6000);
                    
                    // Auto-end after 3 minutes (typical trailer length)
                    setTimeout(function() {
                        if (!hasNotifiedEnded) {
                            notifyEnded();
                        }
                    }, 180000);
                </script>
            </body>
            </html>
            """
            
            webView.loadHTMLString(html, baseURL: nil)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "playerReady":
                DispatchQueue.main.async {
                    self.onReady?()
                }
            case "playerPlaying":
                break
            case "playerError":
                guard !hasErrored else { return }
                hasErrored = true
                let errorMsg = message.body as? String ?? "Unknown error"
                DispatchQueue.main.async {
                    self.onError?(errorMsg)
                }
            case "playerEnded":
                DispatchQueue.main.async {
                    self.onEnded?()
                }
            default:
                break
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !hasErrored else { return }
            hasErrored = true
            DispatchQueue.main.async {
                self.onError?("Navigation failed: \(error.localizedDescription)")
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !hasErrored else { return }
            hasErrored = true
            DispatchQueue.main.async {
                self.onError?("Failed to load: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - YouTube Player View (for AI Assistant and other uses)
struct YouTubePlayerView: UIViewRepresentable {
    let videoKey: String
    var autoPlay: Bool = false
    var isMuted: Bool = false
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?
    var onEnded: (() -> Void)?
    
    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "playerReady")
        contentController.add(context.coordinator, name: "playerError")
        contentController.add(context.coordinator, name: "playerEnded")
        
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences = preferences
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard !videoKey.isEmpty else { return }
        
        if context.coordinator.currentVideoKey == videoKey {
            return
        }
        context.coordinator.currentVideoKey = videoKey
        
        let autoPlayValue = autoPlay ? 1 : 0
        let muteValue = isMuted ? 1 : 0
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; }
                html, body { width: 100%; height: 100%; background: #000; }
                iframe { width: 100%; height: 100%; border: none; }
            </style>
        </head>
        <body>
            <iframe src="https://www.youtube-nocookie.com/embed/\(videoKey)?autoplay=\(autoPlayValue)&mute=\(muteValue)&controls=1&modestbranding=1&rel=0&playsinline=1" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>
            <script>
                setTimeout(function() {
                    try { window.webkit.messageHandlers.playerReady.postMessage('ready'); } catch(e) {}
                }, 1000);
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onError: onError, onEnded: onEnded)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var currentVideoKey: String?
        var onReady: (() -> Void)?
        var onError: ((String) -> Void)?
        var onEnded: (() -> Void)?
        
        init(onReady: (() -> Void)?, onError: ((String) -> Void)?, onEnded: (() -> Void)?) {
            self.onReady = onReady
            self.onError = onError
            self.onEnded = onEnded
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "playerReady":
                DispatchQueue.main.async { self.onReady?() }
            case "playerError":
                DispatchQueue.main.async { self.onError?(message.body as? String ?? "Error") }
            case "playerEnded":
                DispatchQueue.main.async { self.onEnded?() }
            default:
                break
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.onError?(error.localizedDescription) }
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

// MARK: - UIImage Average Color Extension
extension UIImage {
    func averageColor() -> UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: CIVector(cgRect: extent)])
        guard let outputImage = filter?.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(bitmap[0]) / 255.0, green: CGFloat(bitmap[1]) / 255.0, blue: CGFloat(bitmap[2]) / 255.0, alpha: 1)
    }
}

#Preview {
    HeroCarouselView(items: [], onItemTap: { _ in })
}

