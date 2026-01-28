//
//  AsyncImageView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

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
                    Color(.systemGray5)
                    ProgressView()
                        .tint(.secondary)
                }
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure:
                ZStack {
                    Color(.systemGray5)
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            @unknown default:
                Color(.systemGray5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Poster Image
struct PosterImageView: View {
    let posterPath: String?
    let size: TMDBService.ImageSize
    
    init(posterPath: String?, size: TMDBService.ImageSize = .medium) {
        self.posterPath = posterPath
        self.size = size
    }
    
    var body: some View {
        AsyncImageView(
            url: TMDBService.shared.imageURL(path: posterPath, size: size),
            cornerRadius: 8
        )
    }
}

// MARK: - Backdrop Image
struct BackdropImageView: View {
    let backdropPath: String?
    let size: TMDBService.ImageSize
    
    init(backdropPath: String?, size: TMDBService.ImageSize = .backdrop) {
        self.backdropPath = backdropPath
        self.size = size
    }
    
    var body: some View {
        AsyncImageView(
            url: TMDBService.shared.imageURL(path: backdropPath, size: size),
            cornerRadius: 0
        )
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
                        .fill(Color(.systemGray5))
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
                        .fill(Color(.systemGray5))
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.secondary)
                }
            @unknown default:
                Circle()
                    .fill(Color(.systemGray5))
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
