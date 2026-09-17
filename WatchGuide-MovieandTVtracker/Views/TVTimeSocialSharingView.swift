//
//  TVTimeSocialSharingView.swift
//  WatchGuide-MovieandTVtracker
//
//  Enables social sharing of watch achievements, milestones, and streaks.
//  Users can share their stats with friends and on social media.
//

import SwiftUI

struct TVTimeSocialSharingView: View {
    let userStats: WatchStats
    let userProfile: TVTimeUserProfile?
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedShareType: ShareType = .achievements
    @State private var showShareSheet = false
    @State private var shareText = ""
    
    private let accent = Color(hex: "FF375F")
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Share type selector
                Picker("What to share", selection: $selectedShareType) {
                    ForEach(ShareType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    Text(generateShareText())
                        .font(.subheadline)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal)
                }
                
                // Share buttons
                VStack(spacing: 12) {
                    ShareOptionButton(
                        icon: "message.fill",
                        title: "Messages",
                        color: Color.blue,
                        action: {
                            shareText = generateShareText()
                            showShareSheet = true
                        }
                    )
                    
                    ShareOptionButton(
                        icon: "paperplane.fill",
                        title: "Airdrop",
                        color: Color(hex: "5AC8FA"),
                        action: {
                            shareText = generateShareText()
                            showShareSheet = true
                        }
                    )
                    
                    #if !os(tvOS)
                    ShareOptionButton(
                        icon: "doc.on.doc.fill",
                        title: "Copy to Clipboard",
                        color: Color.green,
                        action: {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(generateShareText(), forType: .string)
                            #else
                            UIPasteboard.general.string = generateShareText()
                            #endif
                            dismiss()
                        }
                    )
                    #endif
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Share Your Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .shareSheet(isPresented: $showShareSheet, activityItems: [shareText])
        }
    }
    
    private func generateShareText() -> String {
        switch selectedShareType {
        case .achievements:
            let unlockedCount = userProfile?.currentStreak ?? 0
            return """
            🏆 I've unlocked \(unlockedCount) achievements on TV Time!
            
            Join me in WatchGuide and track your entertainment journey.
            #WatchGuide #TVTime #Entertainment
            """
            
        case .streak:
            let streak = userStats.currentStreakDays
            return """
            🔥 I'm on a \(streak)-day viewing streak on WatchGuide!
            
            Keep up with what I'm watching on TV Time.
            #WatchGuide #BingeWatcher #EntertainmentStreak
            """
            
        case .watchTime:
            let hours = userStats.totalMinutes / 60
            let minutes = userStats.totalMinutes % 60
            return """
            ⏱️ I've watched \(hours)h \(minutes)m of content on WatchGuide!
            
            See what I'm watching on TV Time.
            #WatchGuide #ContentAddict #EntertainmentStats
            """
            
        case .milestones:
            let rank = userProfile?.userRank ?? Int.random(in: 1...100)
            let percentile = userProfile?.userPercentile ?? 50.0
            return """
            ⭐ I'm in the top \(Int(percentile))% of watchers on TV Time!
            
            My rank: #\(rank)
            Join WatchGuide to see where you rank.
            #WatchGuide #TVTime #CinephileElite
            """
        }
    }
}

// MARK: - Share Type

enum ShareType: String, CaseIterable {
    case achievements
    case streak
    case watchTime
    case milestones
    
    var label: String {
        switch self {
        case .achievements: return "Achievements"
        case .streak: return "Streak"
        case .watchTime: return "Watch Time"
        case .milestones: return "Milestones"
        }
    }
}

// MARK: - Share Option Button

struct ShareOptionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Share Sheet Modifier

extension View {
    func shareSheet(isPresented: Binding<Bool>, activityItems: [Any]) -> some View {
        self.modifier(ShareSheetModifier(isPresented: isPresented, activityItems: activityItems))
    }
}

struct ShareSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let activityItems: [Any]
    
    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    // UIActivityViewController is unavailable on tvOS, so sharing is a no-op there.
                    #if os(macOS)
                    if let view = NSApp.keyWindow?.contentView {
                        NSSharingServicePicker(items: activityItems)
                            .show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
                    }
                    #elseif !os(tvOS)
                    let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {
                        rootViewController.present(vc, animated: true)
                    }
                    #endif
                    isPresented = false
                }
            }
    }
}

#Preview {
    TVTimeSocialSharingView(
        userStats: WatchStats(
            totalMinutes: 15000,
            totalSessions: 250,
            moviesWatched: 120,
            episodesWatched: 450,
            currentStreakDays: 21,
            longestStreakDays: 45,
            lastWatchedDate: Date()
        ),
        userProfile: TVTimeUserProfile(
            id: "user_1",
            username: "MovieFan",
            joinedAt: Date(),
            totalHoursWatched: 250,
            totalShowsTracked: 45,
            totalMoviesWatched: 120,
            currentStreak: 21,
            longestStreak: 45,
            userRank: 42,
            userPercentile: 75,
            mostWatchedGenre: "Thriller",
            profilePicture: nil
        )
    )
}
