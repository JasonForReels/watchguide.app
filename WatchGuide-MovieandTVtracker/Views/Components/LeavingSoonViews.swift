//
//  LeavingSoonViews.swift
//  WatchGuide-MovieandTVtracker
//
//  UI for titles about to leave the user's streaming services.
//

import SwiftUI

// MARK: - Row

/// Horizontal row of watchlist titles leaving soon, soonest first.
struct LeavingSoonRow: View {
    let entries: [LeavingSoonEntry]
    let onItemTap: (MediaItem) -> Void

    private var posterWidth: CGFloat {
        #if os(tvOS)
        200
        #else
        120
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
                Text("Leaving Soon")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("from your watchlist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(entries) { entry in
                        Button {
                            onItemTap(entry.item.toMediaItem())
                        } label: {
                            card(entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    private func card(_ entry: LeavingSoonEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImageView(
                posterPath: entry.item.posterPath,
                mediaId: entry.item.mediaId,
                mediaType: entry.item.mediaType,
                displayWidth: posterWidth
            )
            .frame(width: posterWidth, height: posterWidth * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: sharedPosterCornerRadius, style: .continuous))
            .overlay(alignment: .bottom) {
                LeavingSoonCountdownPill(entry: entry)
                    .padding(6)
            }

            Text(entry.item.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(entry.providerName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: posterWidth)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.9), in: Capsule())
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
