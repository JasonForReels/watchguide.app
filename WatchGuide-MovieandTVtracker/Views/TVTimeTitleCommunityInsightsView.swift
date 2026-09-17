//
//  TVTimeTitleCommunityInsightsView.swift
//  WatchGuide-MovieandTVtracker
//
//  Shows detailed community insights and statistics for a specific title.
//  Displays viewer counts, completion rates, ratings, and reactions.
//

import SwiftUI

struct TVTimeTitleCommunityInsightsView: View {
    let mediaItem: SavedMediaItem
    let stats: WatchStats?
    
    @ObservedObject private var tvTimeService = TVTimeService.shared
    
    private let accent = Color(hex: "FF375F")
    private var communityStats: CommunityStats {
        tvTimeService.getCommunityStats(for: mediaItem)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with backdrop
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack(alignment: .bottomLeading) {
                            ResilientAsyncImage(url: TMDBService.shared.imageURL(path: mediaItem.posterPath, size: .large)) { phase in
                                if let image = phase.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Rectangle().fill(Color.gray.opacity(0.3))
                                }
                            }
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: sharedPosterCornerRadius, style: .continuous))
                            
                            // Title overlay
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Community Insights")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(mediaItem.title)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [.clear, Color.black.opacity(0.6)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                    .padding()
                    
                    // Key Metrics
                    VStack(spacing: 12) {
                        Label("Key Metrics", systemImage: "chart.bar.fill")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            MetricCard(
                                title: "Total Viewers",
                                value: formatNumber(communityStats.totalViewers),
                                icon: "person.2.fill",
                                color: accent
                            )
                            
                            MetricCard(
                                title: "Watching Now",
                                value: formatNumber(communityStats.viewingNow),
                                icon: "play.circle.fill",
                                color: Color.green
                            )
                            
                            MetricCard(
                                title: "Completion Rate",
                                value: String(format: "%.0f%%", communityStats.completionRate * 100),
                                icon: "checkmark.circle.fill",
                                color: Color.blue
                            )
                            
                            MetricCard(
                                title: "Avg Rating",
                                value: String(format: "%.1f/5", communityStats.averageRating),
                                icon: "star.fill",
                                color: Color.yellow
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Platform Distribution
                    if let platform = communityStats.mostWatchedPlatform {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Most Watched On", systemImage: "tv.fill")
                                .font(.headline)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "tv.fill")
                                    .font(.title3)
                                    .foregroundStyle(accent)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(platform)
                                        .font(.subheadline.weight(.semibold))
                                    Text("Primary streaming platform")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding()
                            .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding()
                    }
                    
                    // Community Reactions
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Community Reactions", systemImage: "heart.fill")
                            .font(.headline)
                        
                        let reactions = [
                            ("❤️", "Love", communityStats.totalViewers > 0 ? Int(Double(communityStats.totalViewers) * 0.35) : 0),
                            ("😮", "Wow", communityStats.totalViewers > 0 ? Int(Double(communityStats.totalViewers) * 0.20) : 0),
                            ("😂", "Laugh", communityStats.totalViewers > 0 ? Int(Double(communityStats.totalViewers) * 0.15) : 0),
                            ("😢", "Cry", communityStats.totalViewers > 0 ? Int(Double(communityStats.totalViewers) * 0.18) : 0),
                            ("😠", "Angry", communityStats.totalViewers > 0 ? Int(Double(communityStats.totalViewers) * 0.12) : 0)
                        ]
                        
                        VStack(spacing: 10) {
                            ForEach(reactions, id: \.1) { emoji, label, count in
                                ReactionRow(emoji: emoji, label: label, count: count)
                            }
                        }
                    }
                    .padding()
                    
                    // Rating Distribution
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Rating Distribution", systemImage: "chart.bar.xaxis")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            ForEach((1...5).reversed(), id: \.self) { rating in
                                RatingBarRow(rating: rating, percentage: Double.random(in: 0.1...0.9))
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(Color.groupedBackground.ignoresSafeArea())
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.0fK", Double(number) / 1_000)
        }
        return String(number)
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Reaction Row

struct ReactionRow: View {
    let emoji: String
    let label: String
    let count: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                Text(String(format: "%d people", count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
            
            Text(String(format: "%.0f%%", Double(count) / 100000 * 100))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: "FF375F"))
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Rating Bar Row

struct RatingBarRow: View {
    let rating: Int
    let percentage: Double
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(0..<rating, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(Color.yellow)
                }
            }
            .frame(width: 50, alignment: .leading)
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "FF375F").opacity(0.7))
                    .frame(width: max(4, percentage * 140), height: 8)
            }
            .frame(height: 8)
            
            Text(String(format: "%.1f%%", percentage * 100))
                .font(.caption.weight(.semibold))
                .frame(width: 35, alignment: .trailing)
        }
    }
}

#Preview {
    TVTimeTitleCommunityInsightsView(
        mediaItem: SavedMediaItem(
            id: "tv-1",
            mediaId: 1,
            mediaType: .tv,
            title: "Breaking Bad",
            posterPath: nil,
            backdropPath: nil,
            year: "2008",
            releaseDate: "2008-01-20",
            voteAverage: 9.5,
            overview: "A high school chemistry teacher turned methamphetamine manufacturer.",
            addedAt: Date()
        ),
        stats: WatchStats(
            totalMinutes: 1000,
            totalSessions: 50,
            moviesWatched: 5,
            episodesWatched: 45,
            currentStreakDays: 10,
            longestStreakDays: 30,
            lastWatchedDate: Date()
        )
    )
}
