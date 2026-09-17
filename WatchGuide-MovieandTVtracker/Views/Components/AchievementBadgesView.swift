//
//  AchievementBadgesView.swift
//  WatchGuide-MovieandTVtracker
//
//  Displays user achievements earned through watching activity and milestones.
//  Shows locked and unlocked achievements with earned dates and descriptions.
//

import SwiftUI

struct AchievementBadgesView: View {
    let achievements: [TVTimeAchievement]
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    private let accent = Color(hex: "FF375F")
    
    var unlockedCount: Int {
        achievements.filter { $0.unlockedAt != nil }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Achievements", systemImage: "trophy.fill")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(unlockedCount)/\(achievements.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(achievements) { achievement in
                    AchievementBadge(achievement: achievement, accent: accent)
                }
            }
        }
    }
}

// MARK: - Achievement Badge

struct AchievementBadge: View {
    let achievement: TVTimeAchievement
    let accent: Color
    
    @State private var showDetails = false
    
    var isUnlocked: Bool {
        achievement.unlockedAt != nil
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Badge
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    Text(achievement.icon)
                        .font(.system(size: 32))
                    Text(achievement.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isUnlocked ? Color.yellow.opacity(0.2) : Color.gray.opacity(0.1))
                        .strokeBorder(isUnlocked ? Color.yellow : Color.gray.opacity(0.3), lineWidth: 1.5)
                )
                
                if isUnlocked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accent)
                        .padding(6)
                        .background(Color.white, in: Circle())
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showDetails = true
            }
            
            // Unlock date or "Locked"
            if let date = achievement.unlockedAt {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Locked")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showDetails) {
            AchievementDetailsView(achievement: achievement)
        }
    }
}

// MARK: - Achievement Details Sheet

struct AchievementDetailsView: View {
    let achievement: TVTimeAchievement
    @Environment(\.dismiss) var dismiss
    
    var isUnlocked: Bool {
        achievement.unlockedAt != nil
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .center) {
                    Circle()
                        .fill(isUnlocked ? Color.yellow.opacity(0.3) : Color.gray.opacity(0.15))
                    Text(achievement.icon)
                        .font(.system(size: 64))
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(achievement.title)
                        .font(.title2.weight(.bold))
                    
                    Text(achievement.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    if let date = achievement.unlockedAt {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                            Text("Unlocked \(date.formatted(date: .abbreviated, time: .omitted))")
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "FF375F"))
                        .padding(.top, 8)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                            Text("Keep watching to unlock")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Achievement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    AchievementBadgesView(
        achievements: [
            TVTimeAchievement(
                id: "first_movie",
                title: "First Film",
                description: "Watched your first movie",
                icon: "🎬",
                unlockedAt: Date()
            ),
            TVTimeAchievement(
                id: "first_episode",
                title: "Series Starter",
                description: "Watched your first TV episode",
                icon: "📺",
                unlockedAt: nil
            )
        ]
    )
}
