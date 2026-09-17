//
//  TVTimeLeaderboardView.swift
//  WatchGuide-MovieandTVtracker
//
//  Displays community leaderboards showing top watchers and their stats.
//  Includes daily, weekly, monthly, and all-time rankings.
//

import SwiftUI

struct TVTimeLeaderboardView: View {
    @State private var selectedPeriod: LeaderboardPeriod = .allTime
    @State private var selectedCategory: LeaderboardCategory = .mostWatched
    
    private let accent = Color(hex: "FF375F")
    
    // Mock data - in production, would be fetched from backend
    private let mockLeaderboard: [LeaderboardEntry] = [
        LeaderboardEntry(rank: 1, displayName: "CinephileKing", value: 1250, userRank: "Cinephile Elite"),
        LeaderboardEntry(rank: 2, displayName: "BingeWatcher92", value: 1100, userRank: "True Enthusiast"),
        LeaderboardEntry(rank: 3, displayName: "MovieLover", value: 980, userRank: "True Enthusiast"),
        LeaderboardEntry(rank: 4, displayName: "ShowAddicted", value: 850, userRank: "Dedicated Watcher"),
        LeaderboardEntry(rank: 5, displayName: "StreamingFanatic", value: 750, userRank: "Dedicated Watcher"),
        LeaderboardEntry(rank: 6, displayName: "EntertainmentGeek", value: 680, userRank: "Regular Viewer"),
        LeaderboardEntry(rank: 7, displayName: "FilmBuff", value: 620, userRank: "Regular Viewer"),
        LeaderboardEntry(rank: 8, displayName: "TVJunkie", value: 550, userRank: "Regular Viewer"),
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Image(systemName: "podium.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(accent)
                            Text("Leaderboard")
                                .font(.title2.weight(.bold))
                        }
                        Text("See how you rank against other watchers")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    
                    // Period Selector
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(LeaderboardPeriod.allCases, id: \.self) { period in
                            Text(period.label).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    // Category Selector
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(LeaderboardCategory.allCases, id: \.self) { category in
                            Text(category.label).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    // Your Rank Card (Mock)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your Position", systemImage: "star.fill")
                            .font(.headline)
                            .foregroundStyle(accent)
                        
                        HStack(alignment: .center, spacing: 12) {
                            Text("#42")
                                .font(.title.weight(.bold))
                                .foregroundStyle(accent)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("You")
                                    .font(.subheadline.weight(.semibold))
                                Text("750 hours • True Enthusiast")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrowup.forward")
                                    Text("↑ 5 spots")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.green)
                                
                                Text("This week")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding()
                    
                    // Leaderboard List
                    VStack(spacing: 0) {
                        ForEach(Array(mockLeaderboard.enumerated()), id: \.element) { index, entry in
                            LeaderboardRow(entry: entry, isHighlighted: false, accent: accent)
                                .padding(.horizontal)
                            
                            if index < mockLeaderboard.count - 1 {
                                Divider()
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding()
                }
            }
            .background(Color.groupedBackground.ignoresSafeArea())
            .navigationTitle("TV Time")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Leaderboard Row

struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let isHighlighted: Bool
    let accent: Color
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Rank badge
            ZStack(alignment: .center) {
                if entry.rank <= 3 {
                    Image(systemName: entry.rankIcon)
                        .font(.title3)
                        .foregroundStyle(entry.rankColor)
                } else {
                    Text("\(entry.rank)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 36)
            
            // User info
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    Text(entry.userRank)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer(minLength: 0)
            
            // Value
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(entry.value)h")
                    .font(.subheadline.weight(.bold))
                Text("watched")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .background(isHighlighted ? accent.opacity(0.05) : Color.clear)
    }
}

// MARK: - Models

enum LeaderboardPeriod: String, CaseIterable {
    case today
    case thisWeek
    case thisMonth
    case allTime
    
    var label: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .allTime: return "All Time"
        }
    }
}

enum LeaderboardCategory: String, CaseIterable {
    case mostWatched
    case longestStreak
    case mostTitles
    case topRated
    
    var label: String {
        switch self {
        case .mostWatched: return "Most Watched"
        case .longestStreak: return "Streaks"
        case .mostTitles: return "Most Titles"
        case .topRated: return "Top Rated"
        }
    }
}

struct LeaderboardEntry: Hashable {
    let rank: Int
    let displayName: String
    let value: Int
    let userRank: String
    
    var rankIcon: String {
        switch rank {
        case 1: return "crown.fill"
        case 2: return "medal.fill"
        case 3: return "medal"
        default: return ""
        }
    }
    
    var rankColor: Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.843, blue: 0.0) // Gold
        case 2: return Color(red: 0.753, green: 0.753, blue: 0.753) // Silver
        case 3: return Color(red: 0.804, green: 0.498, blue: 0.196) // Bronze
        default: return .secondary
        }
    }
}

#Preview {
    TVTimeLeaderboardView()
}
