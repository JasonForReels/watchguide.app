//
//  LeavingSoonViews.swift
//  WatchGuide-MovieandTVtracker
//
//  UI for titles about to leave the user's streaming services.
//

import SwiftUI

// MARK: - Row

/// Its own row of watchlist titles leaving soon, soonest first: a Liquid Glass
/// "Leaving Soon" badge over backdrop cards with the title written on them.
struct LeavingSoonRow: View {
    let entries: [LeavingSoonEntry]
    let onItemTap: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                LeavingSoonGlassBadge()
                Text(entries.first?.fromWatchlist == false ? "on your services" : "from your watchlist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            onItemTap(entry.item.toMediaItem())
                        } label: {
                            LeavingSoonBackdropCard(entry: entry, appearanceIndex: index)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Glass Badge

/// The row's "Leaving Soon" logo, set in Liquid Glass.
struct LeavingSoonGlassBadge: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "hourglass.bottomhalf.filled")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
            Text("Leaving Soon")
                .font(.title3.weight(.heavy))
                .tracking(-0.2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(.orange.opacity(0.18)), in: .capsule)
    }
}

// MARK: - Backdrop Card

/// 16:9 backdrop with the title written over it, the service it's leaving, and
/// a glass countdown.
struct LeavingSoonBackdropCard: View {
    let entry: LeavingSoonEntry
    let appearanceIndex: Int
    @State private var isHovered = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isFocused) private var isFocused

    private var cardWidth: CGFloat {
        #if os(tvOS)
        480
        #else
        horizontalSizeClass == .regular ? 320 : 260
        #endif
    }

    var body: some View {
        let cardHeight = cardWidth * 9.0 / 16.0
        let isEngaged = isHovered || isFocused

        ZStack(alignment: .bottomLeading) {
            BackdropImageView(
                backdropPath: entry.item.backdropPath,
                size: .backdropSmall,
                mediaId: entry.item.mediaId,
                mediaType: entry.item.mediaType,
                displayWidth: cardWidth
            )
            .frame(width: cardWidth, height: cardHeight)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: .black.opacity(0.45), location: 0.6),
                    .init(color: .black.opacity(0.9), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("LEAVING \(entry.providerName.uppercased())")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                Text(entry.item.title)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
            }
            .padding(12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .overlay(alignment: .topTrailing) {
            LeavingSoonCountdownPill(entry: entry)
                .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.25), radius: isEngaged ? 12 : 5, y: isEngaged ? 6 : 3)
        .scaleEffect(isEngaged ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEngaged)
        .contentShape(Rectangle())
        .wgStaggeredAppear(index: appearanceIndex)
        #if !os(tvOS)
        .onHover { isHovered = $0 }
        #endif
    }
}

// MARK: - Countdown Pill

struct LeavingSoonCountdownPill: View {
    let entry: LeavingSoonEntry

    private var tint: Color {
        entry.daysLeft <= 3 ? .red : .orange
    }

    var body: some View {
        Text(entry.countdownText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .glassEffect(.regular.tint(tint.opacity(0.55)), in: .capsule)
    }
}

// MARK: - Detail Banner

/// Shown on a title's detail page when it's leaving a service the user has.
struct LeavingSoonBanner: View {
    let providerName: String
    let leavesOn: Date

    private var daysLeft: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.startOfDay(for: leavesOn)
        return max(0, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.title3)
                .foregroundStyle(daysLeft <= 3 ? .red : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Leaving \(providerName)")
                    .font(.subheadline.weight(.semibold))
                Text("Available until \(leavesOn.formatted(.dateTime.weekday(.wide).month(.wide).day()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
