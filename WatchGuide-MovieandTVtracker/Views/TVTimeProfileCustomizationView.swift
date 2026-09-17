//
//  TVTimeProfileCustomizationView.swift
//  WatchGuide-MovieandTVtracker
//
//  Allows users to customize their TV Time profile, privacy settings,
//  and preference display options.
//

import SwiftUI

struct TVTimeProfileCustomizationView: View {
    @ObservedObject private var tvTimeService = TVTimeService.shared
    @State private var username: String = ""
    @State private var displayStats = true
    @State private var allowComparisons = true
    @State private var showAchievements = true
    @State private var showStreaks = true
    @State private var allowFriendRequests = true
    @State private var profileVisibility: ProfileVisibility = .publicProfile
    @State private var showSaveConfirmation = false
    
    private let accent = Color(hex: "FF375F")
    
    var body: some View {
        NavigationStack {
            Form {
                // Profile Section
                Section(header: Label("Profile", systemImage: "person.fill")) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(accent)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Username", text: $username)
                            Text(username.isEmpty ? "Enter display name" : "Visible to community")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    
                    Picker("Profile Visibility", selection: $profileVisibility) {
                        ForEach(ProfileVisibility.allCases, id: \.self) { visibility in
                            Text(visibility.label).tag(visibility)
                        }
                    }
                }
                
                // Stats Display Section
                Section(header: Label("Public Stats", systemImage: "chart.bar.fill")) {
                    Toggle("Display Watch Statistics", isOn: $displayStats)
                    Toggle("Show Achievements", isOn: $showAchievements)
                    Toggle("Show Current Streak", isOn: $showStreaks)
                    Toggle("Allow Comparisons", isOn: $allowComparisons)
                }
                .footerText("Choose which stats are visible on your profile")
                
                // Social Section
                Section(header: Label("Social", systemImage: "person.2.fill")) {
                    Toggle("Allow Friend Requests", isOn: $allowFriendRequests)
                    
                    HStack {
                        Label("Share Achievements", systemImage: "square.and.arrow.up")
                        Spacer()
                        NavigationLink(destination: TVTimeSocialSharingView(
                            userStats: WatchGuideTrackingService.shared.stats,
                            userProfile: tvTimeService.userProfile
                        )) {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Label("Leaderboard", systemImage: "podium.fill")
                        Spacer()
                        NavigationLink(destination: TVTimeLeaderboardView()) {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Data & Privacy Section
                Section(header: Label("Data & Privacy", systemImage: "lock.fill")) {
                    NavigationLink(destination: DataPrivacyView()) {
                        Label("Privacy Policy", systemImage: "doc.text")
                    }
                    
                    Button(role: .destructive) {
                        // Clear history action
                    } label: {
                        Label("Clear Watch History", systemImage: "trash.fill")
                    }
                    
                    Button(role: .destructive) {
                        tvTimeService.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "arrowthrough.sign")
                    }
                }
                
                // Save Section
                Section {
                    Button(action: saveProfile) {
                        Text("Save Changes")
                            .frame(maxWidth: .infinity)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .listRowBackground(accent)
                }
            }
            .navigationTitle("TV Time Profile")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Saved", isPresented: $showSaveConfirmation) {
                Button("OK") { }
            } message: {
                Text("Your profile has been updated successfully.")
            }
            .onAppear {
                username = tvTimeService.userProfile?.username ?? ""
            }
        }
    }
    
    private func saveProfile() {
        // Save profile changes
        showSaveConfirmation = true
    }
}

// MARK: - Profile Visibility

enum ProfileVisibility: String, CaseIterable {
    case publicProfile
    case friendsOnly
    case privateProfile
    
    var label: String {
        switch self {
        case .publicProfile: return "Public - Anyone can see"
        case .friendsOnly: return "Friends Only"
        case .privateProfile: return "Private - Only you"
        }
    }
}

// MARK: - Data Privacy View

struct DataPrivacyView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title2.weight(.bold))
                    .padding()
                
                PrivacySection(
                    title: "Data Collection",
                    icon: "doc.text.fill",
                    content: "WatchGuide collects your viewing data to provide personalized recommendations and community insights. Your data is encrypted and stored securely."
                )
                
                PrivacySection(
                    title: "Data Usage",
                    icon: "chart.bar.fill",
                    content: "Your watch history is used to calculate personal statistics, power recommendations, and generate community-wide insights. You control what's shared."
                )
                
                PrivacySection(
                    title: "Community Insights",
                    icon: "globe.europe.africa.fill",
                    content: "Anonymized aggregated data helps power trending lists and community statistics. Individual viewing data is never shared without your consent."
                )
                
                PrivacySection(
                    title: "Data Deletion",
                    icon: "trash.fill",
                    content: "You can delete your watch history and account data at any time. This action is permanent and cannot be undone."
                )
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacySection: View {
    let title: String
    let icon: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(hex: "FF375F"))
            
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Form Section Footer Extension

extension View {
    func footerText(_ text: String) -> some View {
        #if os(iOS)
        return self.listRowSeparator(.hidden)
        #else
        return self
        #endif
    }
}

#Preview {
    TVTimeProfileCustomizationView()
}
