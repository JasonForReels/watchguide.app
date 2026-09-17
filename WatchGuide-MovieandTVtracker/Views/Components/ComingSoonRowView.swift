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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isRegular = horizontalSizeClass == .regular
        let displayedItems = Array(items.prefix(20))
        VStack(alignment: .leading, spacing: isRegular ? 16 : 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(isRegular ? .title2 : .title3)
                        .fontWeight(.bold)

                    Text("Movies, new series, and the next episode worth waiting for.")
                        .font(.caption)
                        .foregroundStyle(subtitleColor)
                }

                Spacer()

                if let onSeeAll {
                    Button(action: onSeeAll) {
                        #if os(tvOS)
                        TVSeeAllButtonLabel()
                        #else
                        Image(systemName: "chevron.right")
                            .font(.headline)
                            .foregroundStyle(colorScheme == .dark ? .white : .gray)
                        #endif
                    }
                    #if os(tvOS)
                    .buttonStyle(.plain)
                    #endif
                }
            }
            .padding(.horizontal, horizontalPadding(isRegular: isRegular))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: isRegular ? 18 : 14) {
                    ForEach(displayedItems) { item in
                        FocusableActionSurface(action: {
                            onItemTap(item.mediaItem)
                        }, outlineShape: .roundedRectangle(cornerRadius: 22)) {
                            ComingSoonPosterCard(item: item)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding(isRegular: isRegular))
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var subtitleColor: Color {
        #if os(tvOS)
        .white.opacity(0.66)
        #else
        .secondary
        #endif
    }

    private func horizontalPadding(isRegular: Bool) -> CGFloat {
        #if os(tvOS)
        60
        #else
        isRegular ? 20 : 16
        #endif
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
            .clipShape(RoundedRectangle(cornerRadius: sharedPosterCornerRadius, style: .continuous))
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
                    .strokeBorder(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 0.75)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(isEngaged ? 0.22 : 0.16), radius: isEngaged ? 8 : 6, y: isEngaged ? 4 : 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isEngaged)
        }
        .frame(width: posterWidth, height: posterHeight)
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

            LiveCountdownClock(releaseDate: item.releaseDate, urgencyColor: item.urgencyColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: width - 20, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Live Countdown Clock
struct LiveCountdownClock: View {
    let releaseDate: Date
    let urgencyColor: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = releaseDate.timeIntervalSince(context.date)

            if remaining <= 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Text("Released")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }
            } else {
                let components = countdownComponents(from: remaining)
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(urgencyColor)
                        .symbolEffect(.pulse, isActive: remaining < 86400)

                    countdownUnit(value: components.days, label: "D")
                    countdownSeparator
                    countdownUnit(value: components.hours, label: "H")
                    countdownSeparator
                    countdownUnit(value: components.minutes, label: "M")
                    countdownSeparator
                    countdownUnit(value: components.seconds, label: "S")
                }
            }
        }
    }

    private func countdownUnit(value: Int, label: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text("\(value)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var countdownSeparator: some View {
        Text(":")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary.opacity(0.6))
    }

    private func countdownComponents(from interval: TimeInterval) -> (days: Int, hours: Int, minutes: Int, seconds: Int) {
        let total = Int(interval)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return (days, hours, minutes, seconds)
    }
}
