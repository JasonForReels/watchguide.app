//
//  AsyncImageView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Shared Gray5 Color Helper
/// A cross-platform gray color that works on iOS and tvOS.
private let sharedGray5Color: Color = {
    #if os(tvOS)
    return Color.gray.opacity(0.3)
    #elseif canImport(UIKit)
    return Color(UIColor.systemGray5)
    #else
    return Color.gray.opacity(0.3)
    #endif
}()

let sharedPosterCornerRadius: CGFloat = 14

/// Bridges a decoded `PlatformImage` into SwiftUI.
private func swiftUIImage(_ image: PlatformImage) -> Image {
    #if canImport(UIKit)
    return Image(uiImage: image)
    #else
    return Image(nsImage: image)
    #endif
}

@MainActor
private final class ResilientImageLoader: ObservableObject {
    @Published private(set) var phase: AsyncImagePhase = .empty

    private var currentURL: URL?
    private var loadTask: Task<Void, Never>?

    func load(url: URL?, maxPixelSize: CGFloat?, transaction: Transaction = .init()) {
        guard currentURL != url || phase.image == nil else {
            return
        }

        currentURL = url
        loadTask?.cancel()

        guard let url else {
            phase = .empty
            return
        }

        // A cached image resolves synchronously — no `.empty` frame, no flicker
        // when a cell scrolls back into view.
        if let cached = ImageMemoryCache.shared.image(for: url, maxPixelSize: maxPixelSize) {
            phase = .success(swiftUIImage(cached))
            return
        }

        phase = .empty
        loadTask = Task { [weak self] in
            do {
                let image = try await ImageDownloader.shared.image(for: url, maxPixelSize: maxPixelSize)
                guard let self, !Task.isCancelled, self.currentURL == url else { return }
                withTransaction(transaction) {
                    self.phase = .success(swiftUIImage(image))
                }
            } catch {
                guard let self, !Task.isCancelled, self.currentURL == url else { return }
                withTransaction(transaction) {
                    self.phase = .failure(error)
                }
            }
        }
    }
}

struct ResilientAsyncImage<Content: View>: View {
    let url: URL?
    /// Longest edge, in pixels, the image will be drawn at. Supplying it lets the
    /// decoder downsample, which cuts both decode time and memory substantially.
    let maxPixelSize: CGFloat?
    let transaction: Transaction
    let content: (AsyncImagePhase) -> Content

    @StateObject private var loader = ResilientImageLoader()

    init(
        url: URL?,
        maxPixelSize: CGFloat? = nil,
        transaction: Transaction = .init(),
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.transaction = transaction
        self.content = content
    }

    /// Prefers the loader's phase, falling back to a synchronous cache lookup so
    /// an already-decoded image paints on the first frame this view is evaluated.
    private var resolvedPhase: AsyncImagePhase {
        if loader.phase.image != nil { return loader.phase }
        if let url, let cached = ImageMemoryCache.shared.image(for: url, maxPixelSize: maxPixelSize) {
            return .success(swiftUIImage(cached))
        }
        return loader.phase
    }

    var body: some View {
        content(resolvedPhase)
            .task(id: url) {
                loader.load(url: url, maxPixelSize: maxPixelSize, transaction: transaction)
            }
        // Deliberately no `onDisappear` cancel: LazyHStack/LazyVStack churn cells
        // constantly while scrolling, and tearing down a nearly-finished download
        // only to restart it on re-entry is what made posters feel slow. Finished
        // downloads land in the shared cache and cost nothing on the way back.
    }
}

struct PosterDepthModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .clipShape(shape)
            .overlay(
                shape
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .overlay(
                shape
                    .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.35)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 8)
            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
    }
}

extension View {
    func posterDepth(cornerRadius: CGFloat = sharedPosterCornerRadius) -> some View {
        modifier(PosterDepthModifier(cornerRadius: cornerRadius))
    }
}

struct AsyncImageView: View {
    let url: URL?
    let contentMode: ContentMode
    let cornerRadius: CGFloat
    let maxPixelSize: CGFloat?

    init(
        url: URL?,
        contentMode: ContentMode = .fill,
        cornerRadius: CGFloat = sharedPosterCornerRadius,
        maxPixelSize: CGFloat? = nil
    ) {
        self.url = url
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.maxPixelSize = maxPixelSize
    }

    var body: some View {
        ResilientAsyncImage(url: url, maxPixelSize: maxPixelSize) { phase in
            switch phase {
            case .empty:
                sharedGray5Color
                    .shimmer()
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure:
                ZStack {
                    sharedGray5Color
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            @unknown default:
                sharedGray5Color
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Artwork Source Preference

/// How hard a view should work to find "better" artwork than TMDB's own poster.
enum ArtworkSourcePolicy {
    /// Draw TMDB artwork immediately. FanArt.tv art is still used when it has
    /// already been resolved (it is cached process-wide), but nothing waits on a
    /// lookup. This is what rows, grids and carousels want — the artwork is
    /// on screen in one request instead of three.
    case fast
    /// Resolve FanArt.tv first and wait for it. Appropriate for single-item
    /// screens where one extra request buys noticeably better artwork.
    case enhanced
}

// MARK: - Poster Image
struct PosterImageView: View {
    let posterPath: String?
    let backdropPath: String?
    let size: TMDBService.ImageSize
    var mediaId: Int?
    var mediaType: MediaType?
    var artworkPolicy: ArtworkSourcePolicy = .fast
    /// Longest drawn edge in points; used to downsample the decode.
    var displayWidth: CGFloat?

    /// FanArt.tv poster URL, once resolved.
    @State private var fanartURL: URL?
    /// Whether FanArt.tv's image failed to render, so we fall back to TMDB.
    @State private var fanartImageFailed = false

    init(
        posterPath: String?,
        backdropPath: String? = nil,
        size: TMDBService.ImageSize = .medium,
        mediaId: Int? = nil,
        mediaType: MediaType? = nil,
        artworkPolicy: ArtworkSourcePolicy = .fast,
        displayWidth: CGFloat? = nil
    ) {
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.size = size
        self.mediaId = mediaId
        self.mediaType = mediaType
        self.artworkPolicy = artworkPolicy
        self.displayWidth = displayWidth
    }

    /// The URL to draw. FanArt wins only when it is known *before* the first
    /// paint — swapping the URL mid-flight would throw away a poster that is
    /// already downloading and start a second download for the same cell.
    private var activeURL: URL? {
        if let fanartURL, !fanartImageFailed { return fanartURL }
        return posterImageURL
    }

    var body: some View {
        Group {
            if let url = activeURL {
                ResilientAsyncImage(url: url, maxPixelSize: maxPixelSize) { phase in
                    switch phase {
                    case .empty:
                        sharedGray5Color
                            .shimmer()
                            .posterDepth()
                    case .success(let image):
                        ZStack {
                            sharedGray5Color
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .posterDepth()
                    case .failure:
                        failureView(for: url)
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .task(id: fanArtTaskKey) {
            await resolveFanArtPoster()
        }
    }

    @ViewBuilder
    private func failureView(for url: URL) -> some View {
        if url == fanartURL {
            // FanArt art didn't render — drop back to the TMDB poster.
            placeholderView
                .onAppear { fanartImageFailed = true }
        } else {
            placeholderView
        }
    }

    /// Decode at roughly the drawn size. Falls back to a sensible poster width
    /// when a caller hasn't specified one.
    private var maxPixelSize: CGFloat? {
        let width = displayWidth ?? 200
        #if canImport(UIKit)
        let scale = UITraitCollection.current.displayScale > 0 ? UITraitCollection.current.displayScale : 2
        #else
        let scale: CGFloat = 2
        #endif
        // Posters are 2:3, so the long edge is the height.
        return width * 1.5 * scale
    }

    private var fanArtTaskKey: String {
        guard let mediaId, let mediaType else { return "none" }
        return "\(mediaType.rawValue)-\(mediaId)"
    }

    private var posterImageURL: URL? {
        resolvedImageURL(from: posterPath, size: size)
    }

    private func resolvedImageURL(from path: String?, size: TMDBService.ImageSize) -> URL? {
        guard let rawPath = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return nil
        }

        if rawPath.hasPrefix("http://") || rawPath.hasPrefix("https://") {
            return URL(string: rawPath)
        }

        return TMDBService.shared.imageURL(path: rawPath, size: size)
    }

    private var placeholderView: some View {
        ZStack {
            sharedGray5Color
            Image(systemName: "film")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .posterDepth()
    }

    private func resolveFanArtPoster() async {
        guard let mediaId, let mediaType else { return }

        // Already resolved earlier in this session — free, and no request.
        if let known = FanArtURLCache.shared.posterURL(tmdbId: mediaId, mediaType: mediaType) {
            fanartURL = known
            return
        }

        // In `.fast` mode we never spend a network round-trip just to choose a
        // URL; TMDB's poster is already on screen. `.enhanced` callers opt in —
        // as does anything with no TMDB poster at all, where FanArt is the only
        // way to avoid a permanent placeholder.
        guard artworkPolicy == .enhanced || posterImageURL == nil else { return }

        let url = await FanArtService.shared.getBestPosterURL(tmdbId: mediaId, mediaType: mediaType)
        guard !Task.isCancelled, let url else { return }
        FanArtURLCache.shared.setPosterURL(url, tmdbId: mediaId, mediaType: mediaType)
        fanartURL = url
    }
}

// MARK: - Backdrop Image
struct BackdropImageView: View {
    let backdropPath: String?
    let size: TMDBService.ImageSize
    var mediaId: Int?
    var mediaType: MediaType?
    var artworkPolicy: ArtworkSourcePolicy = .fast
    /// Longest drawn edge in points; used to downsample the decode.
    var displayWidth: CGFloat?

    @State private var fanartURL: URL?
    @State private var fanartImageFailed = false

    init(
        backdropPath: String?,
        size: TMDBService.ImageSize = .backdrop,
        mediaId: Int? = nil,
        mediaType: MediaType? = nil,
        artworkPolicy: ArtworkSourcePolicy = .fast,
        displayWidth: CGFloat? = nil
    ) {
        self.backdropPath = backdropPath
        self.size = size
        self.mediaId = mediaId
        self.mediaType = mediaType
        self.artworkPolicy = artworkPolicy
        self.displayWidth = displayWidth
    }

    private var activeURL: URL? {
        if let fanartURL, !fanartImageFailed { return fanartURL }
        return TMDBService.shared.imageURL(path: backdropPath, size: size)
    }

    private var maxPixelSize: CGFloat? {
        guard let displayWidth else { return nil }
        #if canImport(UIKit)
        let scale = UITraitCollection.current.displayScale > 0 ? UITraitCollection.current.displayScale : 2
        #else
        let scale: CGFloat = 2
        #endif
        return displayWidth * scale
    }

    var body: some View {
        Group {
            if let url = activeURL {
                ResilientAsyncImage(url: url, maxPixelSize: maxPixelSize) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        if url == fanartURL {
                            sharedGray5Color
                                .onAppear { fanartImageFailed = true }
                        } else {
                            sharedGray5Color
                        }
                    case .empty:
                        sharedGray5Color
                            .shimmer()
                    @unknown default:
                        sharedGray5Color
                    }
                }
            } else {
                sharedGray5Color
            }
        }
        .task(id: fanArtTaskKey) {
            await resolveFanArtBackdrop()
        }
    }

    private var fanArtTaskKey: String {
        guard let mediaId, let mediaType else { return "none" }
        return "\(mediaType.rawValue)-\(mediaId)"
    }

    private func resolveFanArtBackdrop() async {
        guard let mediaId, let mediaType else { return }

        if let known = FanArtURLCache.shared.backdropURL(tmdbId: mediaId, mediaType: mediaType) {
            fanartURL = known
            return
        }

        guard artworkPolicy == .enhanced || backdropPath == nil else { return }

        let url = await FanArtService.shared.getBestBackdropURL(tmdbId: mediaId, mediaType: mediaType)
        guard !Task.isCancelled, let url else { return }
        FanArtURLCache.shared.setBackdropURL(url, tmdbId: mediaId, mediaType: mediaType)
        fanartURL = url
    }
}

// MARK: - Profile Image
struct ProfileImageView: View {
    let profilePath: String?
    let size: CGFloat
    
    init(profilePath: String?, size: CGFloat = 60) {
        self.profilePath = profilePath
        self.size = size
    }
    
    var body: some View {
        ResilientAsyncImage(url: TMDBService.shared.imageURL(path: profilePath, size: .profile)) { phase in
            switch phase {
            case .empty:
                ZStack {
                    Circle()
                        .fill(sharedGray5Color)
                    ProgressView()
                        .tint(.secondary)
                }
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                ZStack {
                    Circle()
                        .fill(sharedGray5Color)
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.secondary)
                }
            @unknown default:
                Circle()
                    .fill(sharedGray5Color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

#Preview {
    VStack {
        PosterImageView(posterPath: nil)
            .frame(width: 120, height: 180)
        
        ProfileImageView(profilePath: nil)
    }
}
