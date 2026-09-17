//
//  TVTimeCommunityStatsView.swift
//  WatchGuide-MovieandTVtracker
//
//  Displays user's viewing statistics compared to the TV Time community.
//  Shows percentile ranking, user rank title, and comparison metrics.
//

import SwiftUI

struct TVTimeCommunityStatsView: View {
    let userProfile: TVTimeUserProfile?
    let comparisonStats: (userHours: Int, globalAverage: Double, percentile: Double, userRank: String)
    
    private let accent = Color(hex: "FF375F")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Label("Community Insights", systemImage: "globe.europe.africa.fill")
                .font(.title3.weight(.bold))
            
            // Rank card
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Rank")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(comparisonStats.userRank)
                            .font(.title2.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    
                    Spacer(minLength: 0)
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Percentile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(String(format: "%.0f", comparisonStats.percentile) + "%")
                                .font(.title2.weight(.bold))
                            Image(systemName: "arrowup.forward")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(accent)
                        }
                    }
                }
                
                // Percentile bar
                PercentileBar(percentile: comparisonStats.percentile, accent: accent)
            }
            .padding()
            .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            
            // Stats grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                TVTimeStatCard(
                    title: "Your Watch Time",
                    value: String(format: "%dh", comparisonStats.userHours),
                    subtitle: "hours watched",
                    icon: "clock.fill",
                    accent: accent
                )
                
                TVTimeStatCard(
                    title: "Global Average",
                    value: String(format: "%.0fh", comparisonStats.globalAverage),
                    subtitle: "hours watched",
                    icon: "globe",
                    accent: accent
                )
                
                if let profile = userProfile {
                    TVTimeStatCard(
                        title: "Current Streak",
                        value: "\(profile.currentStreak)d",
                        subtitle: "days",
                        icon: "flame.fill",
                        accent: accent
                    )
                    
                    TVTimeStatCard(
                        title: "Titles Watched",
                        value: "\(profile.totalShowsTracked + profile.totalMoviesWatched)",
                        subtitle: "total",
                        icon: "film.stack.fill",
                        accent: accent
                    )
                }
            }
        }
    }
}

// MARK: - Percentile Bar

struct PercentileBar: View {
    let percentile: Double
    let accent: Color
    
    var clippedPercentile: Double {
        min(100, max(0, percentile))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("New Explorer")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Top 1%")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(width: nil)
                    .scaleEffect(x: clippedPercentile / 100, anchor: .leading)
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Stat Card

struct TVTimeStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let accent: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    TVTimeCommunityStatsView(
        userProfile: TVTimeUserProfile(
            id: "user_1",
            username: "MovieFan",
            joinedAt: Date(),
            totalHoursWatched: 250,
            totalShowsTracked: 45,
            totalMoviesWatched: 120,
            currentStreak: 7,
            longestStreak: 30,
            userRank: 75,
            userPercentile: 75,
            mostWatchedGenre: "Thriller",
            profilePicture: nil
        ),
        comparisonStats: (userHours: 250, globalAverage: 200.0, percentile: 75.0, userRank: "True Enthusiast")
    )
}
