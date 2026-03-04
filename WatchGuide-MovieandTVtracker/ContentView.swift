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
    
    // Profile switcher bar state
    @State private var showProfileSwitcherBar = false
    
    enum Tab: Int, CaseIterable, Identifiable {
        case browse = 0
        case search = 1
        case ai = 2
        case lists = 3
        
        var id: Int { rawValue }
        
        var label: String {
            switch self {
            case .browse: return "Browse"
            case .search: return "Search"
            case .ai: return "Scout"
            case .lists: return "Lists"
            }
        }
        
        var iconName: String {
            switch self {
            case .browse: return "popcorn.fill"
            case .search: return "magnifyingglass"
            case .ai: return "sparkles"
            case .lists: return "list.bullet.below.rectangle"
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
                if !isAuth && selectedTab == .lists {
                    selectedTab = .browse
                }
                visitedTabs.insert(selectedTab)
            }
            .onChange(of: StorageService.shared.settings.isKidsProfile) { _, isKids in
                if isKids && selectedTab == .ai {
                    selectedTab = .browse
                }
                visitedTabs.insert(selectedTab)
            }
            .onChange(of: profileService.activeProfile?.ageGroup) { _, newAgeGroup in
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
    
    // Visible tabs (no "Me" — that's the separate button)
    private var visibleTabs: [Tab] {
        var tabs = Tab.allCases
        
        if !authService.isAuthenticated {
            tabs = tabs.filter { $0 != .lists }
        }
        
        let isAdult = profileService.activeProfile?.ageGroup == .adult && profileService.activeProfile?.isKids != true
        let isKids = profileService.activeProfile?.isKids == true || StorageService.shared.settings.isKidsProfile
        if isKids || (profileService.hasActiveProfile && !isAdult) {
            tabs = tabs.filter { $0 != .ai }
        }
        
        return tabs
    }
    
    // MARK: - iPhone Layout
    private var iPhoneLayout: some View {
        ZStack(alignment: .bottom) {
            // Content area — tabs rendered directly (no native TabView tab bar)
            ZStack {
                ForEach(visibleTabs) { tab in
                    tabContent(for: tab)
                        .opacity(selectedTab == tab ? 1 : 0)
                        .zIndex(selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(selectedTab == tab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Leave space for the custom tab bar
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 56)
            }
            
            // Custom Tab Bar + Me button
            VStack(spacing: 0) {
                // Profile Switcher Bar overlay (above the tab bar)
                if showProfileSwitcherBar {
                    ProfileSwitcherBar(
                        profiles: profileService.profiles,
                        activeProfileId: profileService.activeProfile?.id,
                        onSelectProfile: { profile in
                            profileService.switchToProfile(profile)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showProfileSwitcherBar = false
                            }
                        },
                        onDismiss: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showProfileSwitcherBar = false
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                customTabBar
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: selectedTab) { _, newTab in
            visitedTabs.insert(newTab)
            if showProfileSwitcherBar {
                withAnimation(.easeOut(duration: 0.25)) {
                    showProfileSwitcherBar = false
                }
            }
        }
        .id("\(authService.isAuthenticated)-\(profileService.activeProfile?.id ?? "none")")
    }
    
    // MARK: - Custom Tab Bar (Liquid Glass)
    private var customTabBar: some View {
        HStack(spacing: 12) {
            // Main tab bar pill — Liquid Glass style
            HStack(spacing: 0) {
                ForEach(visibleTabs) { tab in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 18, weight: .semibold))
                                .symbolEffect(.bounce.down, value: selectedTab == tab)
                            Text(tab.label)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background {
                LiquidGlassCapsuleBackground()
            }
            
            // Separate "Me" profile button
            meProfileButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .padding(.top, 4)
    }
    
    // MARK: - Me Profile Button (Liquid Glass circle)
    private var meProfileButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            if profileService.hasProfiles, profileService.profiles.count > 1 {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showProfileSwitcherBar.toggle()
                }
            }
        } label: {
            ZStack {
                LiquidGlassCircleBackground(size: 52)
                
                if let profile = profileService.activeProfile {
                    ProfileAvatarImageView(
                        profile: profile,
                        size: 34,
                        showBorder: false
                    )
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                // Active indicator ring
                if showProfileSwitcherBar, let profile = profileService.activeProfile {
                    Circle()
                        .stroke(profile.color.color.opacity(0.8), lineWidth: 2)
                        .frame(width: 52, height: 52)
                }
            }
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
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
        }
    }
}

// MARK: - Profile Switcher Bar (Liquid Glass)
struct ProfileSwitcherBar: View {
    let profiles: [UserProfile]
    let activeProfileId: String?
    let onSelectProfile: (UserProfile) -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            // Header row with title and close button
            HStack {
                Text("Switch Profile")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            
            // Profile avatars row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(profiles) { profile in
                        let isActive = profile.id == activeProfileId
                        
                        Button {
                            onSelectProfile(profile)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    // Liquid glass backing circle
                                    if isActive {
                                        Circle()
                                            .fill(profile.color.color.opacity(0.12))
                                            .frame(width: 58, height: 58)
                                    }
                                    
                                    ProfileAvatarImageView(
                                        profile: profile,
                                        size: 52,
                                        showBorder: false
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                isActive
                                                    ? profile.color.color.opacity(0.8)
                                                    : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.0),
                                                lineWidth: isActive ? 2.5 : 1
                                            )
                                    )
                                    .scaleEffect(isActive ? 1.08 : 1.0)
                                    .shadow(
                                        color: isActive ? profile.color.color.opacity(0.3) : .clear,
                                        radius: 6,
                                        y: 2
                                    )
                                    
                                    if isActive {
                                        VStack {
                                            Spacer()
                                            HStack {
                                                Spacer()
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(profile.color.color)
                                                    .background(
                                                        Circle()
                                                            .fill(.ultraThinMaterial)
                                                            .frame(width: 16, height: 16)
                                                    )
                                            }
                                        }
                                        .frame(width: 52, height: 52)
                                        .offset(x: 2, y: 2)
                                    }
                                }
                                
                                Text(profile.name)
                                    .font(.caption2)
                                    .fontWeight(isActive ? .semibold : .regular)
                                    .foregroundStyle(isActive ? profile.color.color : .secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 14)
        }
        .background {
            LiquidGlassRoundedBackground(cornerRadius: 22)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
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

// MARK: - Liquid Glass Background Components

/// A capsule-shaped Liquid Glass background with specular highlight, depth shadow, and border refraction.
struct LiquidGlassCapsuleBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        ZStack {
            // Depth shadow layer
            Capsule()
                .fill(Color.black.opacity(isDark ? 0.35 : 0.08))
                .blur(radius: 3)
                .offset(y: 2)
            
            // Main frosted glass
            Capsule()
                .fill(.ultraThinMaterial)
            
            // Inner subtle gradient for 3D curvature
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(isDark ? 0.08 : 0.18),
                            .clear,
                            .black.opacity(isDark ? 0.06 : 0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Top specular highlight strip
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(isDark ? 0.12 : 0.22),
                            .white.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .mask {
                    VStack {
                        Rectangle()
                            .frame(height: 18)
                        Spacer()
                    }
                }
            
            // Border ring with refraction gradient
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(isDark ? 0.22 : 0.35),
                            .white.opacity(isDark ? 0.06 : 0.12),
                            .white.opacity(0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        }
        .shadow(color: .black.opacity(isDark ? 0.4 : 0.12), radius: 12, y: 4)
    }
}

/// A circle-shaped Liquid Glass background.
struct LiquidGlassCircleBackground: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        ZStack {
            // Depth shadow
            Circle()
                .fill(Color.black.opacity(isDark ? 0.3 : 0.06))
                .frame(width: size, height: size)
                .blur(radius: 3)
                .offset(y: 2)
            
            // Main frosted glass
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
            
            // Inner curvature gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(isDark ? 0.10 : 0.20),
                            .clear,
                            .black.opacity(isDark ? 0.08 : 0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
            
            // Top specular highlight
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(isDark ? 0.14 : 0.25),
                            .white.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(width: size, height: size)
                .mask {
                    VStack {
                        Ellipse()
                            .frame(width: size * 0.65, height: size * 0.3)
                            .offset(y: size * 0.06)
                        Spacer()
                    }
                    .frame(width: size, height: size)
                }
            
            // Border refraction ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(isDark ? 0.22 : 0.35),
                            .white.opacity(isDark ? 0.05 : 0.1),
                            .white.opacity(0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
                .frame(width: size, height: size)
        }
        .shadow(color: .black.opacity(isDark ? 0.35 : 0.1), radius: 10, y: 3)
    }
}

/// A rounded-rectangle Liquid Glass background.
struct LiquidGlassRoundedBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        ZStack {
            // Depth shadow
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(isDark ? 0.3 : 0.06))
                .blur(radius: 4)
                .offset(y: 3)
            
            // Main frosted glass
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            
            // Inner curvature gradient
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(isDark ? 0.08 : 0.16),
                            .clear,
                            .black.opacity(isDark ? 0.06 : 0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Top specular highlight
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(isDark ? 0.12 : 0.22),
                            .white.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .mask {
                    VStack {
                        Rectangle()
                            .frame(height: 22)
                        Spacer()
                    }
                }
            
            // Border refraction
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(isDark ? 0.20 : 0.30),
                            .white.opacity(isDark ? 0.05 : 0.10),
                            .white.opacity(0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        }
        .shadow(color: .black.opacity(isDark ? 0.35 : 0.1), radius: 14, y: 4)
    }
}

#Preview {
    ContentView()
}
