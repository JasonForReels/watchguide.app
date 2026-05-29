//
//  ComingSoonRowView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct ComingSoonRowView: View {
    let title: String
    let items: [CountdownItem]
    let onItemTap: (MediaItem) -> Void
    let onSeeAll: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let isRegular = horizontalSizeClass == .regular
        VStack(alignment: .leading, spacing: isRegular ? 16 : 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(isRegular ? .title2 : .title3)
                        .fontWeight(.bold)

                    Text("Movies, new series, and the next episode worth waiting for.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let onSeeAll {
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

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: isRegular ? 18 : 14) {
                    ForEach(items) { item in
                        Button {
                            onItemTap(item.mediaItem)
                        } label: {
                            ComingSoonPosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, isRegular ? 20 : 16)
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }
}

struct ComingSoonPosterCard: View {
    let item: CountdownItem

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    var body: some View {
        let baseSize = ResponsiveSizing.posterSize(horizontalSizeClass: horizontalSizeClass)
        let posterWidth = baseSize.width
        let posterHeight = baseSize.height
        let scale: CGFloat = 1.08
        let isEngaged = isHovered || isFocused

        ZStack {
            PosterImageView(
                posterPath: item.mediaItem.posterPath,
                backdropPath: item.mediaItem.backdropPath,
                size: .medium,
                mediaId: item.mediaItem.id,
                mediaType: item.mediaType
            )
            .frame(width: posterWidth, height: posterHeight)
            .clipped()
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Image(systemName: item.mediaType == .movie ? "film.stack.fill" : "sparkles.tv.fill")
                        .font(.caption2.weight(.semibold))
                    Text(item.mediaType == .movie ? "Movie" : "Series")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.34), in: Capsule())
                .padding(10)
            }
            .overlay(alignment: .bottom) {
                comingSoonFooter(width: posterWidth)
                    .padding(10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(isEngaged ? 0.28 : 0.16), radius: isEngaged ? 14 : 6, y: isEngaged ? 10 : 4)
            .scaleEffect(isEngaged ? scale : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isEngaged)
        }
        .frame(width: posterWidth * scale, height: posterHeight * scale)
        .contentShape(Rectangle())
        #if !os(tvOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }

    @ViewBuilder
    private func comingSoonFooter(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Image(systemName: "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.urgencyColor)

                Text(item.countdownText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(item.releaseDateFormatted)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: width - 20, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
