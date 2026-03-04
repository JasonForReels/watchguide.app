//
//  PostSignInSyncView.swift
//  WatchGuide-MovieandTVtracker
//
//  Shown after sign-in/sign-up to sync data or create a profile
//

import SwiftUI

struct PostSignInSyncView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var profileService = ProfileService.shared
    @ObservedObject private var storage = StorageService.shared
    @Environment(\.dismiss) private var dismiss
    
    enum SyncState: Equatable {
        case checking        // Checking cloud for existing data
        case existingUser    // Found cloud data — offer to sync
        case newUser         // No cloud data — prompt to create profile
        case syncing         // Currently downloading data
        case done            // Finished — will dismiss
    }
    
    @State private var syncState: SyncState = .checking
    @State private var foundProfileCount = 0
    @State private var didCloudCheckFail = false
    @State private var didFindNoCloudProfiles = false
    @State private var animateIn = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 28) {
                            switch syncState {
                            case .checking:
                                checkingContent
                            case .existingUser:
                                existingUserContent
                            case .newUser:
                                newUserContent
                            case .syncing:
                                syncingContent
                            case .done:
                                doneContent
                            }
                        }
                        .padding(24)
                        .padding(.top, 20)
                    }
                    
                    // Bottom actions
                    if syncState == .existingUser || syncState == .newUser {
                        bottomActions
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // No cancel — user must complete this flow
            }
            .interactiveDismissDisabled(true)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                    animateIn = true
                }
                Task {
                    await checkForExistingData()
                }
            }
        }
    }
    
    // MARK: - Checking State
    private var checkingContent: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)
            
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 90, height: 90)
                
                Image(systemName: "cloud.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                    .symbolEffect(.pulse, options: .repeating)
            }
            
            VStack(spacing: 8) {
                Text("Checking for Existing Data")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("Looking for your profiles and saved data in the cloud...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            ProgressView()
                .scaleEffect(1.1)
                .padding(.top, 8)
        }
        .opacity(animateIn ? 1 : 0)
    }
    
    // MARK: - Existing User (found cloud data)
    private var existingUserContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 90, height: 90)
                
                Image(systemName: "checkmark.cloud.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 8) {
                Text("Welcome Back!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text(existingUserMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Summary card
            VStack(spacing: 14) {
                if foundProfileCount > 0 {
                    dataSummaryRow(
                        icon: "person.2.fill",
                        color: .accentColor,
                        title: "\(foundProfileCount) Profile\(foundProfileCount == 1 ? "" : "s")",
                        subtitle: "Your profiles will be restored"
                    )
                }
                if didCloudCheckFail {
                    dataSummaryRow(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        title: "Cloud Check Unavailable",
                        subtitle: "Network or API issue while checking your account"
                    )
                }
                if didFindNoCloudProfiles {
                    dataSummaryRow(
                        icon: "questionmark.circle.fill",
                        color: .secondary,
                        title: "No Cloud Profiles Found",
                        subtitle: "You can still continue and create one on this device"
                    )
                }
                
                dataSummaryRow(
                    icon: "list.bullet.rectangle",
                    color: .orange,
                    title: "Lists & Watchlist",
                    subtitle: "Your watchlist, watched, and liked items"
                )
                
                dataSummaryRow(
                    icon: "gearshape.fill",
                    color: .purple,
                    title: "Settings & Preferences",
                    subtitle: "Region, display options, and more"
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemGray6))
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    // MARK: - New User (no cloud data)
    private var newUserContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 90, height: 90)
                
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 8) {
                Text("Welcome to WatchGuide!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Let's create your first profile to personalize recommendations and settings.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Features teaser
            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "person.2.fill", color: .accentColor, title: "Personal Profiles", subtitle: "Each person gets their own experience")
                featureRow(icon: "cloud.fill", color: .green, title: "Cloud Sync", subtitle: "Your data syncs across all your devices")
                featureRow(icon: "sparkles", color: .purple, title: "Scout AI", subtitle: "Get personalized recommendations")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemGray6))
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    // MARK: - Syncing State
    private var syncingContent: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)
            
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 90, height: 90)
                
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                    .symbolEffect(.pulse, options: .repeating)
            }
            
            VStack(spacing: 8) {
                Text("Syncing Your Data")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("Downloading your profiles, lists, and settings from the cloud...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            ProgressView()
                .scaleEffect(1.1)
                .padding(.top, 8)
        }
    }
    
    // MARK: - Done State
    private var doneContent: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)
            
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 90, height: 90)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }
            
            Text("All Set!")
                .font(.title3)
                .fontWeight(.bold)
        }
    }
    
    // MARK: - Bottom Actions
    private var bottomActions: some View {
        VStack(spacing: 12) {
            if syncState == .existingUser {
                Button {
                    Task { await syncAndContinue() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Sync to This Device")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                
                Button {
                    skipAndContinue()
                } label: {
                    Text("Skip for Now")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            } else if syncState == .newUser {
                Button {
                    continueToProfileSetup()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Create Profile")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func dataSummaryRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Logic
    
    private var existingUserMessage: String {
        if didCloudCheckFail {
            return "We couldn't verify your cloud data right now. You can sync now or skip and try again later."
        }
        if didFindNoCloudProfiles {
            return "We couldn't find cloud profiles for this account yet. Try syncing now, or skip and create a profile."
        }
        return "We found your existing data in the cloud. Would you like to sync it to this device?"
    }

    private func checkForExistingData() async {
        // Give a brief pause for visual feedback
        try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s

        // New account flow: always create first profile after sign-up.
        if authService.lastAuthFlow == .signUp {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) {
                    syncState = .newUser
                }
            }
            return
        }
        
        // Try to download profiles from cloud to check if data exists
        await profileService.downloadProfilesFromCloud()
        
        await MainActor.run {
            if profileService.hasProfiles {
                foundProfileCount = profileService.profiles.count
                didCloudCheckFail = false
                didFindNoCloudProfiles = false
                withAnimation(.easeInOut(duration: 0.35)) {
                    syncState = .existingUser
                }
            } else if profileService.didLastCloudProfileDownloadFail {
                foundProfileCount = 0
                didCloudCheckFail = true
                didFindNoCloudProfiles = false
                withAnimation(.easeInOut(duration: 0.35)) {
                    syncState = .existingUser
                }
            } else {
                foundProfileCount = 0
                didCloudCheckFail = false
                didFindNoCloudProfiles = true
                withAnimation(.easeInOut(duration: 0.35)) {
                    // For sign-in, keep the user in sync flow even when cloud profiles are not found.
                    syncState = .existingUser
                }
            }
        }
    }
    
    private func syncAndContinue() async {
        withAnimation(.easeInOut(duration: 0.3)) {
            syncState = .syncing
        }

        // Prioritize profiles so the user can continue quickly.
        // Heavy data (lists/settings/custom hubs) is pulled in the background.
        await profileService.downloadProfilesFromCloud()
        
        // Mark sync decision complete
        authService.completePostSignInSyncDecision()
        
        // Trigger profile selection if multiple profiles exist
        if profileService.hasProfiles && !profileService.hasActiveProfile {
            profileService.requestProfileSelection()
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            syncState = .done
        }

        // Continue app flow quickly, then finish full sync in background.
        if storage.isCloudConfigured {
            Task { @MainActor in
                await storage.downloadFromCloud()
            }
        }

        try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
        dismiss()
    }
    
    private func skipAndContinue() {
        // Complete the sync decision without downloading data
        authService.completePostSignInSyncDecision()
        
        if profileService.hasProfiles && !profileService.hasActiveProfile {
            profileService.requestProfileSelection()
        }
        
        dismiss()
    }
    
    private func continueToProfileSetup() {
        // Complete the sync decision and route to first profile setup in ContentView.
        authService.completePostSignInSyncDecision()
        profileService.markInitialSyncComplete()
        dismiss()
    }
}
