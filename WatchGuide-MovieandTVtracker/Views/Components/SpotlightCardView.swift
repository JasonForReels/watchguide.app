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
                // Backdrop image
                BackdropImageView(
                    backdropPath: item.backdropPath,
                    size: .backdrop,
                    mediaId: item.id,
                    mediaType: item.resolvedMediaType
                )
                .aspectRatio(16.0 / 9.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()

                // Gradient overlay
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: .black.opacity(0.55), location: 0.65),
                        .init(color: .black.opacity(0.88), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Text content
                VStack(alignment: .leading, spacing: 6) {
                    // Media type badge
                    Text(item.resolvedMediaType == .tv ? "TV SERIES" : "MOVIE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.7))

                    Text(item.displayTitle)
                        .font(isRegular ? .title : .title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(isRegular ? .subheadline : .caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }

                    HStack(spacing: 12) {
                        if let year = item.year {
                            Text(year)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        if let rating = item.voteAverage, rating > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                }
                .padding(isRegular ? 24 : 16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
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
