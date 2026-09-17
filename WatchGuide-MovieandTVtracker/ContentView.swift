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
    @ObservedObject private var quickRouteCenter = WatchGuideQuickRouteCenter.shared
    @State private var selectedMediaItem: MediaItem?
    @State private var showProfilePicker = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var profileService = ProfileService.shared
    @ObservedObject private var aiGuideManager = AppleIntelligenceGuideManager.shared
    @ObservedObject private var scoutAgentRouteCenter = ScoutAgentRouteCenter.shared
    @ObservedObject private var atlasActionCenter = AtlasActionCenter.shared
    #if !os(tvOS)
    @ObservedObject private var atlasDock = AtlasDockState.shared
    #else
    @ObservedObject private var heroFocusState = TVHeroFocusState.shared
    #endif
    
    // Track which tabs have been visited so we only create their views once
    @State private var visitedTabs: Set<Tab> = [.browse]
    
    enum Tab: Int, CaseIterable, Identifiable {
        case browse = 0
        case search = 1
        case lists = 3
        case me = 4
        case settings = 5
        case more = 7
        case myStreaming = 8
        case watchHour = 9
        case tonight = 10

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .browse: return "Browse"
            case .search: return "Search"
            case .lists: return "Lists"
            case .me: return "Me"
            case .settings: return "Settings"
            case .more: return "More"
            case .myStreaming: return "StreamQ"
            case .watchHour: return "WatchHour"
            case .tonight: return "Tonight"
            }
        }

        var iconName: String {
            switch self {
            case .browse: return "popcorn.fill"
            case .search: return "magnifyingglass"
            case .lists: return "list.bullet.below.rectangle"
            case .me: return "person.crop.circle"
            case .settings: return "gearshape.fill"
            case .more: return "ellipsis.circle.fill"
            case .myStreaming: return "play.tv.fill"
            case .watchHour: return "hourglass"
            case .tonight: return "sparkles.rectangle.stack.fill"
            }
        }
    }
    
    @State private var showPostSignInSync = false
    @State private var showAtlasSheet = false

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
                #if os(tvOS)
                tvOSLayout
                #elseif os(macOS) || targetEnvironment(macCatalyst)
                if isMacLike {
                    macLayout
                } else {
                    iPhoneLayout
                }
                #else
                iPhoneLayout
                #endif
            }
            .modifier(TVPrimaryPresentationModifier(
                isGuidePresented: $aiGuideManager.isGuidePresented
            ))
            .mediaDetailPresentation(item: $selectedMediaItem)
            .onChange(of: authService.isAuthenticated) { _, isAuth in
                if !isAuth && selectedTab == .lists {
                    selectedTab = .browse
                }
                visitedTabs.insert(selectedTab)
            }
            .onChange(of: StorageService.shared.settings.isKidsProfile) { _, _ in
                visitedTabs.insert(selectedTab)
            }
            .onChange(of: profileService.activeProfile?.ageGroup) { _, _ in
                visitedTabs.insert(selectedTab)
            }
            .onReceive(NotificationCenter.default.publisher(for: .appleIntelligenceGuideOpenDestination)) { notification in
                guard let destination = notification.object as? AppleIntelligenceGuideDestination else { return }
                switch destination {
                case .search:
                    selectedTab = .search
                    visitedTabs.insert(.search)
                case .scout:
                    #if os(tvOS)
                    showAtlasSheet = true
                    #else
                    AtlasProactiveEngine.shared.markBriefingSeen()
                    AtlasDockState.shared.engage()
                    #endif
                case .browse:
                    selectedTab = .browse
                    visitedTabs.insert(.browse)
                }
            }
            .onChange(of: scoutAgentRouteCenter.pendingRoute?.id) { _, newValue in
                guard newValue != nil else { return }
                selectedMediaItem = nil
                selectedTab = .search
                visitedTabs.insert(.search)
            }
            // Control Center controls land here. `.scanner` is deliberately left
            // in the slot: the scanner sheet belongs to SearchView, so this only
            // gets the user onto the right tab and SearchView consumes it.
            .onChange(of: quickRouteCenter.pending) { _, route in
                guard let route else { return }
                switch route.destination {
                case .atlas, .tonight:
                    #if os(iOS) && !targetEnvironment(macCatalyst)
                    if route.destination == .tonight {
                        selectedTab = .tonight
                        visitedTabs.insert(.tonight)
                        quickRouteCenter.consume()
                        return
                    }
                    #endif
                    #if os(tvOS)
                    showAtlasSheet = true
                    #else
                    AtlasProactiveEngine.shared.markBriefingSeen()
                    AtlasDockState.shared.engage()
                    #endif
                    quickRouteCenter.consume()
                case .search:
                    selectedTab = .search
                    visitedTabs.insert(.search)
                    quickRouteCenter.consume()
                case .watchlist:
                    selectedTab = authService.isAuthenticated ? .lists : .browse
                    visitedTabs.insert(selectedTab)
                    quickRouteCenter.consume()
                case .scanner:
                    selectedTab = .search
                    visitedTabs.insert(.search)
                }
            }
            .task {
                aiGuideManager.presentIfNeededAfterUpdate()
                WidgetDataService.shared.syncAPIKey()
            }
            // tvOS keeps the full page: it has no dock bar, because the bar
            // depends on direct manipulation the remote can't provide.
            #if os(tvOS)
            .sheet(isPresented: $showAtlasSheet) {
                NavigationStack {
                    AIAssistantView()
                }
            }
            .onChange(of: showAtlasSheet) { _, isOpen in
                HeroCarouselMuteManager.shared.isExternallyMuted = isOpen
                if isOpen { AtlasProactiveEngine.shared.markBriefingSeen() }
            }
            #endif
            .onChange(of: atlasActionCenter.pendingNavigation?.id) { _, newValue in
                guard let newValue, let request = atlasActionCenter.pendingNavigation else { return }
                handleAtlasNavigation(request.target)
                atlasActionCenter.consumeNavigation(newValue)
            }
            #if !os(tvOS)
            .atlasHUD()
            #endif
        }
    }
    
    /// Moves the user to the screen Atlas asked for. Atlas states the intent;
    /// the tab switch itself stays in the view layer.
    private func handleAtlasNavigation(_ target: AtlasNavigationTarget) {
        let tab: Tab
        switch target {
        case .browse:      tab = .browse
        case .search:      tab = .search
        case .lists, .watchlist: tab = .lists
        case .myStreaming: tab = .myStreaming
        case .watchHour:   tab = .watchHour
        case .me:          tab = .me
        case .settings:    tab = .settings
        }

        #if os(tvOS)
        showAtlasSheet = false
        #else
        AtlasDockState.shared.dismiss()
        #endif
        selectedTab = tab
        visitedTabs.insert(tab)
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

    private var selectedMediaItemPresentationBinding: Binding<Bool> {
        Binding(
            get: { selectedMediaItem != nil },
            set: { isPresented in
                if !isPresented {
                    selectedMediaItem = nil
                }
            }
        )
    }
    
    private var visibleTabs: [Tab] {
        var tabs: [Tab] = [.browse, .search, .myStreaming, .lists, .me, .settings]

        #if !os(tvOS)
        if !authService.isAuthenticated {
            tabs = tabs.filter { $0 != .lists }
        }
        #endif

        #if os(tvOS)
        return tabs
        #elseif !os(macOS)
        // On iPhone/iPad, we group secondary things into "More"
        var grouped: [Tab] = [.browse]
        if tabs.contains(.search) { grouped.append(.search) }
        if tabs.contains(.myStreaming) { grouped.append(.myStreaming) }
        grouped.append(.tonight)
        grouped.append(.more)
        return grouped
        #else
        return tabs
        #endif
    }

    private var firstAvailableContentTab: Tab {
        visibleTabs.first ?? .browse
    }

    // MARK: - iPhone Layout
    
    /// Tabs that appear directly in the tab bar
    private var primaryTabs: [Tab] {
        visibleTabs.filter { [.browse, .myStreaming].contains($0) }
    }
    
    /// Tabs that go into the "More" section (Lists, Me, Settings)
    private var secondaryTabs: [Tab] {
        visibleTabs.filter { [.lists, .me, .settings].contains($0) }
    }
    
    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            // Primary tabs in the tab bar
            ForEach(primaryTabs) { tab in
                SwiftUI.Tab(tab.label, systemImage: tab.iconName, value: tab) {
                    tabContent(for: tab)
                }
            }

            if visibleTabs.contains(.tonight) {
                SwiftUI.Tab(ContentView.Tab.tonight.label, systemImage: ContentView.Tab.tonight.iconName, value: ContentView.Tab.tonight) {
                    tabContent(for: .tonight)
                }
            }

            // Search tab as a separate circular liquid glass button
            if visibleTabs.contains(.search) {
                SwiftUI.Tab(value: ContentView.Tab.search, role: .search) {
                    tabContent(for: .search)
                }
            }

            // The single "More" tab that leads to the hub
            if visibleTabs.contains(.more) {
                SwiftUI.Tab(value: ContentView.Tab.more) {
                    tabContent(for: .more)
                } label: {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
            }
        }
        .tabViewStyle(.tabBarOnly)
        .onAppear {
            HeroCarouselMuteManager.shared.activeTabID = "\(selectedTab.rawValue)"
        }
        .onChange(of: selectedTab) { _, newTab in
            visitedTabs.insert(newTab)
            HeroCarouselMuteManager.shared.activeTabID = "\(newTab.rawValue)"
        }
        .ignoresSafeArea(.keyboard)
    }

    #if os(tvOS)
    private var tvOSLayout: some View {
        TabView(selection: $selectedTab) {
            ForEach(visibleTabs) { tab in
                tabContent(for: tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tvOSBackground)
                    // The hero carousel is the top-most focusable on a page and
                    // fills the screen, so once it takes focus there is nothing
                    // above it to move to and the bar stays collapsed. Pin the
                    // bar while the hero holds focus so an up-swipe reaches it.
                    .toolbar(heroFocusState.isHeroFocused ? .visible : .automatic, for: .tabBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            if tab != .search && tab != .myStreaming && tab != .browse {
                                Button {
                                    showProfilePicker = true
                                } label: {
                                    Label("Profiles", systemImage: "person.crop.circle")
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .glassEffect(.regular, in: .capsule)
                                }
                            }
                        }
                    }
                .tabItem {
                    Label(tab.label, systemImage: tab.iconName)
                }
                .tag(tab)
            }
        }
        .tabViewStyle(.tabBarOnly)
        .background(tvOSBackground.ignoresSafeArea())
        .fullScreenCover(isPresented: $showProfilePicker) {
            NavigationStack {
                ProfilePickerView(dismissOnSelection: true)
            }
        }
        .onAppear {
            if !visibleTabs.contains(selectedTab) {
                selectedTab = firstAvailableContentTab
            }
            visitedTabs.formUnion(visibleTabs)
            syncVoiceTabContext(selectedTab)
            HeroCarouselMuteManager.shared.activeTabID = "\(selectedTab.rawValue)"
        }
        .onChange(of: selectedTab) { _, newTab in
            visitedTabs.insert(newTab)
            syncVoiceTabContext(newTab)
            HeroCarouselMuteManager.shared.activeTabID = "\(newTab.rawValue)"
        }
    }

    private var tvOSBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.02, blue: 0.05),
                    Color(red: 0.04, green: 0.05, blue: 0.1),
                    Color(red: 0.02, green: 0.03, blue: 0.06),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.32, green: 0.45, blue: 0.92).opacity(0.26),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 880
            )

            RadialGradient(
                colors: [
                    Color(red: 0.98, green: 0.44, blue: 0.22).opacity(0.16),
                    Color.clear
                ],
                center: .trailing,
                startRadius: 90,
                endRadius: 640
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.clear,
                    Color.black.opacity(0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack {
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 520, height: 520)
                    .blur(radius: 120)
                    .offset(x: -140, y: -240)

                Spacer()

                Circle()
                    .fill(Color(red: 0.16, green: 0.22, blue: 0.42).opacity(0.34))
                    .frame(width: 420, height: 420)
                    .blur(radius: 130)
                    .offset(x: 110, y: -90)
            }

            VStack {
                Spacer()
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.34)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 280)
            }
        }
        .overlay {
            Rectangle()
                .fill(.black.opacity(0.18))
                .blendMode(.multiply)
                .ignoresSafeArea()
        }
        .compositingGroup()
        .ignoresSafeArea()
    }
    #endif
    
    // MARK: - Mac Layout
    #if os(macOS) || targetEnvironment(macCatalyst)
    private var macLayout: some View {
        TabView(selection: $selectedTab) {
            ForEach(visibleTabs) { tab in
                SwiftUI.Tab(tab.label, systemImage: tab.iconName, value: tab) {
                    tabContent(for: tab)
                }
            }
        }
        .tabViewStyle(.tabBarOnly)
        .onAppear {
            if !visibleTabs.contains(selectedTab) {
                selectedTab = firstAvailableContentTab
            }
            visitedTabs.insert(selectedTab)
            syncVoiceTabContext(selectedTab)
            HeroCarouselMuteManager.shared.activeTabID = "\(selectedTab.rawValue)"
        }
        .onChange(of: selectedTab) { _, newTab in
            if !visibleTabs.contains(newTab) {
                selectedTab = firstAvailableContentTab
            }
            visitedTabs.insert(selectedTab)
            syncVoiceTabContext(selectedTab)
            HeroCarouselMuteManager.shared.activeTabID = "\(selectedTab.rawValue)"
        }
        .frame(minWidth: 1100, minHeight: 740)
    }
    #endif

    #if os(macOS)
    /// macOS: Atlas lives in its own button beside the tab bar rather than a floating orb.
    private var atlasToolbarButton: some View {
        Button {
            if atlasDock.isEngaged {
                atlasDock.dismiss()
            } else {
                AtlasProactiveEngine.shared.markBriefingSeen()
                atlasDock.engage()
            }
        } label: {
            Label("Atlas", systemImage: "sparkles")
                .labelStyle(.titleAndIcon)
        }
        .help("Ask Atlas")
        .keyboardShortcut("k", modifiers: .command)
    }
    #endif

    private var platformBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(iOS) || targetEnvironment(macCatalyst)
        Color(uiColor: .systemBackground)
        #else
        Color.black
        #endif
    }
    
    @ViewBuilder
    private func tabContent(for tab: Tab) -> some View {
        #if os(tvOS)
        // tvOS: avoid wrapping in NavigationStack so it doesn't interfere
        // with the TabView's tab bar focus management.
        tabContentInner(for: tab)
        #else
        NavigationStack {
            tabContentInner(for: tab)
                // The Atlas dock bar replaces the tab bar rather than stacking
                // on it, so engaging Atlas costs no extra vertical space.
                #if !os(macOS)
                .toolbar(atlasDock.isEngaged ? .hidden : .visible, for: .tabBar)
                #else
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        atlasToolbarButton
                    }
                }
                #endif
        }
        #endif
    }

    @ViewBuilder
    private func tabContentInner(for tab: Tab) -> some View {
        switch tab {
        case .browse:
            BrowseView(selectedItem: $selectedMediaItem)
        case .search:
            LazyTabContent(tab: .search, visitedTabs: $visitedTabs) {
                SearchView(selectedItem: $selectedMediaItem)
            }
        case .myStreaming:
            LazyTabContent(tab: .myStreaming, visitedTabs: $visitedTabs) {
                MyStreamingView()
            }
        case .watchHour:
            LazyTabContent(tab: .watchHour, visitedTabs: $visitedTabs) {
                WatchHourView()
            }
        case .tonight:
            LazyTabContent(tab: .tonight, visitedTabs: $visitedTabs) {
                TonightReelView(selectedItem: $selectedMediaItem)
            }
        case .lists:
            LazyTabContent(tab: .lists, visitedTabs: $visitedTabs) {
                ListsView()
            }
        case .me:
            if authService.isAuthenticated {
                SettingsView(displayMode: .accountOnly)
            } else {
                AuthView()
            }
        case .settings:
            SettingsView()
        case .more:
            MoreHubView()
        }
    }

    private func syncVoiceTabContext(_ tab: Tab) {
        _ = tab
    }

}

private struct TVPrimaryPresentationModifier: ViewModifier {
    @Binding var isGuidePresented: Bool

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isGuidePresented) {
                NavigationStack {
                    AppleIntelligenceGuideView()
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
