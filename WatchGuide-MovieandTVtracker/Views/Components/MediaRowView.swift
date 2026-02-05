//
//  MediaRowView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct MediaRowView: View {
    let title: String
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    let onSeeAll: (() -> Void)?
    
    @State private var scrollOffset: CGFloat = 0
    
    init(title: String, items: [MediaItem], onItemTap: @escaping (MediaItem) -> Void, onSeeAll: (() -> Void)? = nil) {
        self.title = title
        self.items = items
        self.onItemTap = onItemTap
        self.onSeeAll = onSeeAll
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                if let onSeeAll = onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 4) {
                            Text("See All")
                                .font(.subheadline)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(.horizontal)
            
            // Scrolling content
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        MediaPosterCard(item: item)
                            .onTapGesture {
                                onItemTap(item)
                            }
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - Media Poster Card
struct MediaPosterCard: View {
    let item: MediaItem
    @State private var isHovered = false
    
    var body: some View {
        PosterImageView(posterPath: item.posterPath, size: .medium, mediaId: item.id, mediaType: item.resolvedMediaType)
            .frame(width: 130, height: 195)
            .clipped()
            .shadow(color: .black.opacity(0.2), radius: isHovered ? 12 : 4, y: isHovered ? 8 : 2)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Saved Media Row
struct SavedMediaRowView: View {
    let title: String
    let items: [SavedMediaItem]
    let onItemTap: (SavedMediaItem) -> Void
    let onSeeAll: (() -> Void)?
    
    init(title: String, items: [SavedMediaItem], onItemTap: @escaping (SavedMediaItem) -> Void, onSeeAll: (() -> Void)? = nil) {
        self.title = title
        self.items = items
        self.onItemTap = onItemTap
        self.onSeeAll = onSeeAll
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                if let onSeeAll = onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 4) {
                            Text("See All")
                                .font(.subheadline)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(.horizontal)
            
            // Scrolling content
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        SavedMediaPosterCard(item: item)
                            .onTapGesture {
                                onItemTap(item)
                            }
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - Saved Media Poster Card
struct SavedMediaPosterCard: View {
    let item: SavedMediaItem
    @State private var isHovered = false
    
    var body: some View {
        PosterImageView(posterPath: item.posterPath, size: .medium, mediaId: item.mediaId, mediaType: item.mediaType)
            .frame(width: 130, height: 195)
            .clipped()
            .shadow(color: .black.opacity(0.2), radius: isHovered ? 12 : 4, y: isHovered ? 8 : 2)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

#Preview {
    MediaRowView(
        title: "Trending Movies",
        items: [],
        onItemTap: { _ in }
    )
}
