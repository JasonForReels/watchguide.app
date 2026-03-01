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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var scrollOffset: CGFloat = 0

    init(title: String, items: [MediaItem], onItemTap: @escaping (MediaItem) -> Void, onSeeAll: (() -> Void)? = nil) {
        self.title = title
        self.items = items
        self.onItemTap = onItemTap
        self.onSeeAll = onSeeAll
    }

    var body: some View {
        let isRegular = horizontalSizeClass == .regular
        let isRankedTrendingRow = [
            "trending movies",
            "trending tv shows",
            "trending tv"
        ].contains(title.lowercased())
        VStack(alignment: .leading, spacing: isRegular ? 16 : 12) {
            // Header
            HStack {
                Text(title)
                    .font(isRegular ? .title2 : .title3)
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
            .padding(.horizontal, isRegular ? 20 : 16)

            // Scrolling content
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: isRegular ? 16 : 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        MediaPosterCard(
                            item: item,
                            rank: isRankedTrendingRow ? index + 1 : nil
                        )
                            .onTapGesture {
                                onItemTap(item)
                            }
                    }
                }
                .padding(.horizontal, isRegular ? 20 : 16)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - Media Poster Card
struct MediaPosterCard: View {
    let item: MediaItem
    let rank: Int?
    @State private var isHovered = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(item: MediaItem, rank: Int? = nil) {
        self.item = item
        self.rank = rank
    }

    var body: some View {
        let posterSize = ResponsiveSizing.posterSize(horizontalSizeClass: horizontalSizeClass)
        let rankVisible = rank != nil

        ZStack(alignment: .leading) {
            if let rank {
                Text("\(rank)")
                    .font(.system(size: posterSize.height * 0.55, weight: .black, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.22))
                    .offset(x: -6, y: posterSize.height * 0.17)
                    .zIndex(0)
            }

            PosterImageView(posterPath: item.posterPath, size: .medium, mediaId: item.id, mediaType: item.resolvedMediaType)
                .frame(width: posterSize.width, height: posterSize.height)
                .clipped()
                .shadow(color: .black.opacity(0.2), radius: isHovered ? 12 : 4, y: isHovered ? 8 : 2)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                .padding(.leading, rankVisible ? 20 : 0)
                .zIndex(1)
        }
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(title: String, items: [SavedMediaItem], onItemTap: @escaping (SavedMediaItem) -> Void, onSeeAll: (() -> Void)? = nil) {
        self.title = title
        self.items = items
        self.onItemTap = onItemTap
        self.onSeeAll = onSeeAll
    }

    var body: some View {
        let isRegular = horizontalSizeClass == .regular
        VStack(alignment: .leading, spacing: isRegular ? 16 : 12) {
            // Header
            HStack {
                Text(title)
                    .font(isRegular ? .title2 : .title3)
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
            .padding(.horizontal, isRegular ? 20 : 16)

            // Scrolling content
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: isRegular ? 16 : 12) {
                    ForEach(items) { item in
                        SavedMediaPosterCard(item: item)
                            .onTapGesture {
                                onItemTap(item)
                            }
                    }
                }
                .padding(.horizontal, isRegular ? 20 : 16)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - Saved Media Poster Card
struct SavedMediaPosterCard: View {
    let item: SavedMediaItem
    @State private var isHovered = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let posterSize = ResponsiveSizing.posterSize(horizontalSizeClass: horizontalSizeClass)
        PosterImageView(posterPath: item.posterPath, size: .medium, mediaId: item.mediaId, mediaType: item.mediaType)
            .frame(width: posterSize.width, height: posterSize.height)
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
