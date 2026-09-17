//
//  TVTimeTrendingCarouselView.swift
//  WatchGuide-MovieandTVtracker
//
//  A carousel view displaying trending shows and movies from TV Time community data.
//  Shows trending rank, momentum indicator, and community reactions.
//

import SwiftUI

struct TVTimeTrendingCarouselView: View {
    let trendingItems: [TVTimeTrendingItem]
    let onItemTap: (TVTimeTrendingItem) -> Void
    
    private let accent = Color(hex: "FF375F")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Trending Now", systemImage: "chart.line.uptrend.xyaxis.circle.fill")
                .font(.title3.weight(.bold))
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(trendingItems.prefix(10)) { item in
                        TrendingItemCard(item: item, accent: accent, onTap: onItemTap)
                    }
                }
                .padding(.horizontal, -16)
                .padding(.horizontal, 16)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Trending Item Card

struct TrendingItemCard: View {
    let item: TVTimeTrendingItem
    let accent: Color
    let onTap: (TVTimeTrendingItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Rank badge + momentum
            HStack(spacing: 8) {
                ZStack(alignment: .center) {
                    Circle()
                        .fill(accent)
                    Text("#\(item.trendingRank)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    Label("Trending", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                    Text("Momentum: \(item.momentum)/10")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            
            // Poster image
            ResilientAsyncImage(url: TMDBService.shared.imageURL(path: item.posterPath, size: .medium)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.3))
                        .overlay(Image(systemName: "film").foregroundStyle(.secondary))
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: sharedPosterCornerRadius, style: .continuous))
            
            // Title
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            
            // Reactions
            ReactionBubbles(reactions: item.reactions)
        }
        .frame(width: 140)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap(item)
        }
    }
}

// MARK: - Reaction Bubbles

struct ReactionBubbles: View {
    let reactions: TrendingReactions
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach([
                ("❤️", reactions.love),
                ("😮", reactions.wow),
                ("😂", reactions.laugh)
            ], id: \.0) { emoji, count in
                if count > 0 {
                    HStack(spacing: 2) {
                        Text(emoji)
                            .font(.caption)
                        Text("\(count < 1000 ? String(count) : String(count / 1000) + "k")")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(Color.gray.opacity(0.1), in: Capsule())
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack {
        TVTimeTrendingCarouselView(
            trendingItems: [
                TVTimeTrendingItem(
                    id: "1",
                    mediaId: 1,
                    mediaType: .tv,
                    title: "Breaking Bad",
                    posterPath: nil,
                    trendingRank: 1,
                    trendingFor: "this_week",
                    momentum: 9,
                    reactions: TrendingReactions(love: 50000, wow: 20000, laugh: 5000, cry: 3000, angry: 1000),
                    lastUpdate: Date()
                )
            ],
            onItemTap: { _ in }
        )
        Spacer()
    }
}
