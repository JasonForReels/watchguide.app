//
//  ContentView.swift
//  WatchGuide-MovieandTVtracker
//
//  Created by Neel Makhecha on 9/5/25.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var selectedTab: Tab = .browse
    @State private var selectedMediaItem: MediaItem?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var profileService = ProfileService.shared
    
    // Track which tabs have been visited so we only create their views once
    @State private var visitedTabs: Set<Tab> = [.browse]
    
    // Cached profile avatar UIImage for tab bar icon
    @State private var profileTabIcon: UIImage?
    
    enum Tab: Int, CaseIterable, Identifiable {
        case browse = 0
        case search = 1
        case ai = 2
        case lists = 3
        case settings = 4
        
        var id: Int { rawValue }
        
        var label: String {
            switch self {
            case .browse: return "Browse"
            case .search: return "Search"
            case .ai: return "Scout"
            case .lists: return "Lists"
            case .settings: return "Me"
            }
        }
        
        var iconName: String {
            switch self {
            case .browse: return "popcorn.fill"
            case .search: return "magnifyingglass"
            case .ai: return "sparkles"
            case .lists: return "list.bullet.below.rectangle"
            case .settings: return "person.crop.circle.fill"
            }
        }
    }
    
    @State private var showPostSignInSync = false
    
    var body: some View {
        if requiresOnboarding {
            OnboardingFlowView()
        } else if requiresFirstProfileSetup {
            FirstProfileSetupView {
                profileService.markInitialSyncComplete()
            }
        } else if requiresProfilePicker {
            ProfilePickerView()
        } else if authService.isAuthenticated && authService.requiresPostSignInSyncDecision {
            // Just signed in/up — show sync decision popup over a loading state
            Color(.systemBackground)
                .ignoresSafeArea()
                .overlay {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Preparing your account...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .onAppear {
                    // Small delay to let the UI settle, then show the popup
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showPostSignInSync = true
                    }
                }
                .sheet(isPresented: $showPostSignInSync) {
                    PostSignInSyncView()
                }
        } else {
            Group {
                iPhoneLayout
            }
            .sheet(item: $selectedMediaItem) { item in
                MediaDetailView(item: item)
            }
            .onChange(of: selectedMediaItem) { _, newValue in
                HeroCarouselMuteManager.shared.isExternallyMuted = (newValue != nil)
            }
            .onChange(of: authService.isAuthenticated) { _, isAuth in
                // If user logs out while on Lists tab, redirect to Browse
                if !isAuth && selectedTab == .lists {
                    selectedTab = .browse
                }
                // Make sure the current tab is marked as visited after auth change
                // since .id() forces a TabView rebuild
                visitedTabs.insert(selectedTab)
            }
            .onChange(of: StorageService.shared.settings.isKidsProfile) { _, isKids in
                // If non-adult profile is activated while on Scout tab, redirect to Browse
                if isKids && selectedTab == .ai {
                    selectedTab = .browse
                }
                visitedTabs.insert(selectedTab)
            }
            .onChange(of: profileService.activeProfile?.ageGroup) { _, newAgeGroup in
                // If a non-adult profile is selected while on Scout tab, redirect to Browse
                if newAgeGroup != .adult && selectedTab == .ai {
                    selectedTab = .browse
                }
                visitedTabs.insert(selectedTab)
            }
        }
    }
    
    private var requiresOnboarding: Bool {
        if !onboardingComplete { return true }
        return false
    }

    private var requiresFirstProfileSetup: Bool {
        authService.isAuthenticated
            && !authService.requiresPostSignInSyncDecision
            && profileService.hasCompletedInitialSync
            && !profileService.hasProfiles
    }

    private var requiresProfilePicker: Bool {
        authService.isAuthenticated
            && !authService.requiresPostSignInSyncDecision
            && profileService.hasProfiles
            && !profileService.hasActiveProfile
    }
    
    // Stable list of visible tabs based on auth state and age profile
    private var visibleTabs: [Tab] {
        var tabs = Tab.allCases
        
        // Hide Lists tab for non-authenticated users
        if !authService.isAuthenticated {
            tabs = tabs.filter { $0 != .lists }
        }
        
        // Hide Scout AI tab for non-adult profiles (only 18+ can access Scout)
        let isAdult = profileService.activeProfile?.ageGroup == .adult && profileService.activeProfile?.isKids != true
        let isKids = profileService.activeProfile?.isKids == true || StorageService.shared.settings.isKidsProfile
        if isKids || (profileService.hasActiveProfile && !isAdult) {
            tabs = tabs.filter { $0 != .ai }
        }
        
        return tabs
    }
    
    // MARK: - iPhone Layout (TabView)
    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            ForEach(visibleTabs) { tab in
                tabContent(for: tab)
                    .tabItem {
                        if tab == .settings, let icon = profileTabIcon {
                            Label {
                                Text(tab.label)
                            } icon: {
                                Image(uiImage: icon)
                                    .renderingMode(.original)
                            }
                        } else {
                            Label(tab.label, systemImage: tab.iconName)
                        }
                    }
                    .tag(tab)
            }
        }
        .tint(.accentColor)
        .onChange(of: selectedTab) { _, newTab in
            visitedTabs.insert(newTab)
        }
        .onChange(of: profileService.activeProfile?.avatarImageURL) { _, _ in
            loadProfileTabIcon()
        }
        .onChange(of: profileService.activeProfile?.id) { _, _ in
            loadProfileTabIcon()
        }
        .task {
            loadProfileTabIcon()
        }
        .id("\(authService.isAuthenticated)-\(profileService.activeProfile?.id ?? "none")")
    }
    
    /// Downloads the active profile's avatar image and creates a circular tab bar icon
    private func loadProfileTabIcon() {
        guard let profile = profileService.activeProfile,
              let urlStr = profile.avatarImageURL,
              !urlStr.isEmpty,
              let url = URL(string: urlStr) else {
            profileTabIcon = nil
            return
        }
        
        Task.detached {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let original = UIImage(data: data) else { return }
                
                let size: CGFloat = 26
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
                let circular = renderer.image { _ in
                    let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
                    UIBezierPath(ovalIn: rect).addClip()
                    original.draw(in: rect)
                }
                
                let finalIcon = circular.withRenderingMode(.alwaysOriginal)
                await MainActor.run {
                    profileTabIcon = finalIcon
                }
            } catch {
                print("Failed to load profile tab icon: \(error)")
            }
        }
    }
    
    @ViewBuilder
    private func tabContent(for tab: Tab) -> some View {
        switch tab {
        case .browse:
            BrowseView(selectedItem: $selectedMediaItem)
        case .search:
            LazyTabContent(tab: .search, visitedTabs: $visitedTabs) {
                NavigationStack {
                    SearchView(selectedItem: $selectedMediaItem)
                        .navigationTitle("Search")
                }
            }
        case .ai:
            LazyTabContent(tab: .ai, visitedTabs: $visitedTabs) {
                AIAssistantView()
            }
        case .lists:
            LazyTabContent(tab: .lists, visitedTabs: $visitedTabs) {
                ListsView()
            }
        case .settings:
            LazyTabContent(tab: .settings, visitedTabs: $visitedTabs) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("Settings")
                }
            }
        }
    }
}

/// Wraps tab content so it is only created on first visit, then kept alive.
struct LazyTabContent<Content: View>: View {
    let tab: ContentView.Tab
    @Binding var visitedTabs: Set<ContentView.Tab>
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        if visitedTabs.contains(tab) {
            content()
        } else {
            Color.clear
        }
    }
}

#Preview {
    ContentView()
}
