//
//  SpotlightCardView.swift
//  WatchGuide-MovieandTVtracker
//
//  A full-width cinematic card that breaks the monotony of horizontal
//  poster rows in the Browse feed.
//

import SwiftUI

struct SpotlightCardView: View {
    let item: MediaItem
    let onTap: () -> Void

    @State private var isHovered = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let isRegular = horizontalSizeClass == .regular

        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Backdrop image — cinematic full-bleed
                BackdropImageView(
                    backdropPath: item.backdropPath,
                    size: .backdrop,
                    mediaId: item.id,
                    mediaType: item.resolvedMediaType
                )
                .aspectRatio(2.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()

                // Deep cinematic gradient overlay
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.15),
                        .init(color: .black.opacity(0.2), location: 0.35),
                        .init(color: .black.opacity(0.55), location: 0.55),
                        .init(color: .black.opacity(0.85), location: 0.80),
                        .init(color: .black.opacity(0.95), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Content overlay
                VStack(alignment: .leading, spacing: 8) {
                    // Glass badge
                    Text(item.resolvedMediaType == .tv ? "SERIES" : "MOVIE")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())

                    Text(item.displayTitle)
                        .font(isRegular ? .title : .title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(isRegular ? .subheadline : .caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                    }

                    HStack(spacing: 12) {
                        if let year = item.year {
                            Text(year)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        if let rating = item.voteAverage, rating > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                }
                .padding(isRegular ? 24 : 16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: isHovered ? 16 : 8, y: isHovered ? 8 : 4)
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isRegular ? 20 : 16)
        #if !os(tvOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }
}

// MARK: - Section Divider

/// A subtle visual break between groups of rows in the Browse feed.
struct BrowseSectionDivider: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let isRegular = horizontalSizeClass == .regular
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.gray.opacity(0.2), Color.gray.opacity(0.2), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1.5)
            .padding(.horizontal, isRegular ? 40 : 32)
    }
}
