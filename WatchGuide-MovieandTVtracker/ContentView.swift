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
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var profileService = ProfileService.shared
    @ObservedObject private var aiGuideManager = AppleIntelligenceGuideManager.shared
    
    // Track which tabs have been visited so we only create their views once
    @State private var visitedTabs: Set<Tab> = [.browse]
    
    @State private var showProfileSwitcherPage = false
    @State private var lastContentTab: Tab = .browse
    
    enum Tab: Int, CaseIterable, Identifiable {
        case browse = 0
        case search = 1
        case ai = 2
        case lists = 3
        case me = 4
        
        var id: Int { rawValue }
        
        var label: String {
            switch self {
            case .browse: return "Browse"
            case .search: return "Search"
            case .ai: return "Scout"
            case .lists: return "Lists"
            case .me: return "Me"
            }
        }
        
        var iconName: String {
            switch self {
            case .browse: return "popcorn.fill"
            case .search: return "magnifyingglass"
            case .ai: return "sparkles"
            case .lists: return "list.bullet.below.rectangle"
            case .me: return "person.crop.circle"
            }
        }
    }
    
    @State private var showPostSignInSync = false
    
    #if os(macOS) || targetEnvironment(macCatalyst)
    private var isMacLike: Bool { true }
    #else
    private var isMacLike: Bool { false }
    #endif
    
    var body: some View {
        if requiresOnboarding {
            OnboardingFlowView()
        } else if requiresFirstProfileSetup {
            FirstProfileSetupView {
                profileService.markInitialSyncComplete()
            }
        } else if requiresProfilePicker {
            ProfilePickerView(dismissOnSelection: false)
        } else if authService.isAuthenticated && authService.requiresPostSignInSyncDecision {
            // Just signed in/up — show sync decision popup over a loading state
            platformBackgroundColor
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
                #if os(macOS) || targetEnvironment(macCatalyst)
                if isMacLike {
                    macLayout
                } else {
                    iPhoneLayout
                }
                #else
                iPhoneLayout
                #endif
            }
            .sheet(item: $selectedMediaItem) { item in
                MediaDetailView(item: item)
            }
            .sheet(isPresented: $aiGuideManager.isGuidePresented) {
                AppleIntelligenceGuideView()
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
            .onReceive(NotificationCenter.default.publisher(for: .appleIntelligenceGuideOpenDestination)) { notification in
                guard let destination = notification.object as? AppleIntelligenceGuideDestination else { return }
                switch destination {
                case .search:
                    selectedTab = .search
                    visitedTabs.insert(.search)
                case .scout:
                    let target: Tab = visibleTabs.contains(.ai) ? .ai : .browse
                    selectedTab = target
                    visitedTabs.insert(target)
                case .browse:
                    selectedTab = .browse
                    visitedTabs.insert(.browse)
                }
            }
            .task {
                await handlePendingVisualRouteIfNeeded()
                aiGuideManager.presentIfNeededAfterUpdate()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await handlePendingVisualRouteIfNeeded()
                }
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

    private var firstAvailableContentTab: Tab {
        visibleTabs.first(where: { $0 != .me }) ?? .browse
    }

    // MARK: - iPhone Layout
    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            ForEach(visibleTabs) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Image(systemName: tab.iconName)
                        Text(tab.label)
                    }
                    .tag(tab)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .me {
                showProfileSwitcherPage = true
                let fallbackTab = visibleTabs.contains(lastContentTab) ? lastContentTab : firstAvailableContentTab
                if selectedTab != fallbackTab {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        selectedTab = fallbackTab
                    }
                }
            } else {
                lastContentTab = newTab
                visitedTabs.insert(newTab)
            }
        }
        .onAppear {
            if selectedTab == .me {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selectedTab = firstAvailableContentTab
                }
            }
        }
        .sheet(isPresented: $showProfileSwitcherPage) {
            ProfilePickerView()
        }
        .ignoresSafeArea(.keyboard)
    }
    
    // MARK: - Mac Layout
    #if os(macOS) || targetEnvironment(macCatalyst)
    private var macLayout: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(visibleTabs.filter { $0 != .me }) { tab in
                    Label(tab.label, systemImage: tab.iconName)
                        .tag(tab)
                }
            }
            .navigationTitle("WatchGuide")
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    Button {
                        showProfileSwitcherPage = true
                    } label: {
                        Label("Profiles", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        } detail: {
            tabContent(for: activeMacTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showProfileSwitcherPage) {
            ProfilePickerView()
        }
        .onAppear {
            if !visibleTabs.contains(selectedTab) || selectedTab == .me {
                selectedTab = firstAvailableContentTab
            }
            visitedTabs.insert(selectedTab)
        }
        .onChange(of: selectedTab) { _, newTab in
            if !visibleTabs.contains(newTab) || newTab == .me {
                selectedTab = firstAvailableContentTab
            }
            visitedTabs.insert(selectedTab)
        }
        .frame(minWidth: 1100, minHeight: 740)
    }
    
    private var activeMacTab: Tab {
        let candidate = selectedTab == .me ? firstAvailableContentTab : selectedTab
        return visibleTabs.contains(candidate) ? candidate : firstAvailableContentTab
    }
    #endif

    private var platformBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color.black
        #endif
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
        case .me:
            Color.clear
        }
    }

    @MainActor
    private func handlePendingVisualRouteIfNeeded() async {
        guard let route = await VisualIntentRouteCenter.shared.consume() else { return }
        guard let mediaItem = await fetchMediaItem(for: route) else { return }

        if route.action == .addToWatchlist {
            StorageService.shared.addToWantToWatch(SavedMediaItem(from: mediaItem))
        }

        selectedTab = .browse
        selectedMediaItem = mediaItem
    }

    private func fetchMediaItem(for route: VisualIntentRoute) async -> MediaItem? {
        do {
            switch route.mediaType {
            case .movie:
                let details = try await TMDBService.shared.getMovieDetails(id: route.mediaId)
                return MediaItem(
                    id: details.id,
                    title: details.title,
                    name: nil,
                    originalTitle: details.originalTitle,
                    originalName: nil,
                    overview: details.overview,
                    posterPath: details.posterPath,
                    backdropPath: details.backdropPath,
                    releaseDate: details.releaseDate,
                    firstAirDate: nil,
                    voteAverage: details.voteAverage,
                    voteCount: details.voteCount,
                    popularity: nil,
                    genreIds: details.genres?.map { $0.id },
                    mediaType: MediaType.movie.rawValue,
                    adult: details.adult,
                    originalLanguage: nil
                )
            case .tv:
                let details = try await TMDBService.shared.getTVShowDetails(id: route.mediaId)
                return MediaItem(
                    id: details.id,
                    title: nil,
                    name: details.name,
                    originalTitle: nil,
                    originalName: details.originalName,
                    overview: details.overview,
                    posterPath: details.posterPath,
                    backdropPath: details.backdropPath,
                    releaseDate: nil,
                    firstAirDate: details.firstAirDate,
                    voteAverage: details.voteAverage,
                    voteCount: details.voteCount,
                    popularity: nil,
                    genreIds: details.genres?.map { $0.id },
                    mediaType: MediaType.tv.rawValue,
                    adult: nil,
                    originalLanguage: nil
                )
            case .person:
                return nil
            }
        } catch {
            return nil
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
                                                            .fill(.clear)
                                                            .glassEffect(.regular, in: .circle)
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
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

// MARK: - Liquid Glass Background Components (iOS 26 SDK)

/// A capsule-shaped Liquid Glass background using the native .glassEffect() modifier.
/// Kept as a ViewModifier wrapper for backward compatibility with existing call sites.
struct LiquidGlassCapsuleBackground: View {
    var body: some View {
        Capsule()
            .fill(.clear)
            .glassEffect(.regular, in: .capsule)
    }
}

/// A circle-shaped Liquid Glass background using the native .glassEffect() modifier.
struct LiquidGlassCircleBackground: View {
    let size: CGFloat
    
    var body: some View {
        Circle()
            .fill(.clear)
            .frame(width: size, height: size)
            .glassEffect(.regular, in: .circle)
    }
}

/// A rounded-rectangle Liquid Glass background using the native .glassEffect() modifier.
struct LiquidGlassRoundedBackground: View {
    let cornerRadius: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

#Preview {
    ContentView()
}
