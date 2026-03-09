//
//  AsyncImageView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if canImport(UIKit)
import UIKit
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

struct AsyncImageView: View {
    let url: URL?
    let contentMode: ContentMode
    let cornerRadius: CGFloat
    
    init(url: URL?, contentMode: ContentMode = .fill, cornerRadius: CGFloat = 8) {
        self.url = url
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ZStack {
                    sharedGray5Color
                    ProgressView()
                        .tint(.secondary)
                }
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Poster Image with FanArt.tv Primary, TMDB Fallback
struct PosterImageView: View {
    let posterPath: String?
    let backdropPath: String?
    let size: TMDBService.ImageSize
    var mediaId: Int?
    var mediaType: MediaType?
    
    /// FanArt.tv poster URL (primary source)
    @State private var fanartURL: URL?
    /// Whether we've attempted to load from FanArt.tv
    @State private var fanartAttempted = false
    /// Whether FanArt.tv image failed to render
    @State private var fanartImageFailed = false
    /// Whether TMDB image failed to render
    @State private var useBackdropFallback = false
    
    init(
        posterPath: String?,
        backdropPath: String? = nil,
        size: TMDBService.ImageSize = .medium,
        mediaId: Int? = nil,
        mediaType: MediaType? = nil
    ) {
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.size = size
        self.mediaId = mediaId
        self.mediaType = mediaType
    }
    
    var body: some View {
        Group {
            if let fanartURL = fanartURL, !fanartImageFailed {
                // Primary: FanArt.tv poster
                AsyncImage(url: fanartURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        // FanArt image failed to load — fall back to TMDB
                        tmdbPosterView
                            .onAppear { fanartImageFailed = true }
                    case .empty:
                        ZStack {
                            sharedGray5Color
                            ProgressView().tint(.secondary)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    @unknown default:
                        tmdbPosterView
                    }
                }
            } else if fanartAttempted {
                // FanArt unavailable — use TMDB
                tmdbPosterView
            } else {
                // Still loading from FanArt — show TMDB while we wait
                tmdbPosterView
                    .onAppear { loadFanArtPoster() }
            }
        }
    }
    
    /// TMDB poster (fallback)
    private var tmdbPosterView: some View {
        let currentURL = useBackdropFallback ? backdropImageURL : posterImageURL
        return Group {
            if let url = currentURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            sharedGray5Color
                            ProgressView().tint(.secondary)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        if !useBackdropFallback, backdropImageURL != nil {
                            placeholderView
                                .onAppear { useBackdropFallback = true }
                        } else {
                            placeholderView
                        }
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
    }
    
    private var posterImageURL: URL? {
        resolvedImageURL(from: posterPath, size: size)
    }

    private var backdropImageURL: URL? {
        resolvedImageURL(from: backdropPath, size: .backdrop)
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func loadFanArtPoster() {
        guard let mediaId = mediaId, let mediaType = mediaType else {
            fanartAttempted = true
            return
        }
        Task {
            let url = await FanArtService.shared.getBestPosterURL(tmdbId: mediaId, mediaType: mediaType)
            await MainActor.run {
                self.fanartURL = url
                self.fanartAttempted = true
            }
        }
    }
}

// MARK: - Backdrop Image with FanArt.tv Primary, TMDB Fallback
struct BackdropImageView: View {
    let backdropPath: String?
    let size: TMDBService.ImageSize
    var mediaId: Int?
    var mediaType: MediaType?
    
    @State private var fanartURL: URL?
    @State private var fanartAttempted = false
    @State private var fanartImageFailed = false
    
    init(backdropPath: String?, size: TMDBService.ImageSize = .backdrop, mediaId: Int? = nil, mediaType: MediaType? = nil) {
        self.backdropPath = backdropPath
        self.size = size
        self.mediaId = mediaId
        self.mediaType = mediaType
    }
    
    var body: some View {
        Group {
            if let fanartURL = fanartURL, !fanartImageFailed {
                AsyncImage(url: fanartURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        tmdbBackdropView
                            .onAppear { fanartImageFailed = true }
                    case .empty:
                        ZStack {
                            sharedGray5Color
                            ProgressView().tint(.secondary)
                        }
                    @unknown default:
                        tmdbBackdropView
                    }
                }
            } else if fanartAttempted {
                tmdbBackdropView
            } else {
                tmdbBackdropView
                    .onAppear { loadFanArtBackdrop() }
            }
        }
    }
    
    private var tmdbBackdropView: some View {
        AsyncImageView(
            url: TMDBService.shared.imageURL(path: backdropPath, size: size),
            cornerRadius: 0
        )
    }
    
    private func loadFanArtBackdrop() {
        guard let mediaId = mediaId, let mediaType = mediaType else {
            fanartAttempted = true
            return
        }
        Task {
            let url = await FanArtService.shared.getBestBackdropURL(tmdbId: mediaId, mediaType: mediaType)
            await MainActor.run {
                self.fanartURL = url
                self.fanartAttempted = true
            }
        }
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
        AsyncImage(url: TMDBService.shared.imageURL(path: profilePath, size: .profile)) { phase in
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
