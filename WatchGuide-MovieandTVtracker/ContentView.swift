//
//  ContentView.swift
//  WatchGuide-MovieandTVtracker
//
//  Created by Neel Makhecha on 9/5/25.
//

import SwiftUI

// MARK: - Scout Banner Manager
/// Manages the Scout AI banner visibility across all tabs.
/// Uses in-memory state so it resets every time the app is force-quit.
class ScoutBannerManager: ObservableObject {
    static let shared = ScoutBannerManager()
    @Published var isBannerVisible = true
    
    func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) {
            isBannerVisible = false
        }
    }
}

struct ContentView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var selectedTab: Tab = .browse
    @State private var selectedMediaItem: MediaItem?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var scoutBannerManager = ScoutBannerManager.shared
    @ObservedObject private var authService = AuthService.shared
    
    // Track which tabs have been visited so we only create their views once
    @State private var visitedTabs: Set<Tab> = [.browse]
    
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
            case .settings: return "Settings"
            }
        }
        
        var iconName: String {
            switch self {
            case .browse: return "popcorn.fill"
            case .search: return "magnifyingglass"
            case .ai: return "sparkles"
            case .lists: return "list.bullet.below.rectangle"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    var body: some View {
        if requiresOnboarding {
            OnboardingFlowView()
        } else {
            Group {
                iPhoneLayout
            }
            .environmentObject(scoutBannerManager)
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
                // If kids profile is activated while on Scout tab, redirect to Browse
                if isKids && selectedTab == .ai {
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
    
    // Stable list of visible tabs based on auth state and kids profile
    private var visibleTabs: [Tab] {
        var tabs = Tab.allCases
        
        // Hide Lists tab for non-authenticated users
        if !authService.isAuthenticated {
            tabs = tabs.filter { $0 != .lists }
        }
        
        // Hide Scout AI tab for kids profiles (13 and under)
        if StorageService.shared.settings.isKidsProfile {
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
                        Label(tab.label, systemImage: tab.iconName)
                    }
                    .tag(tab)
            }
        }
        .tint(.accentColor)
        .onChange(of: selectedTab) { _, newTab in
            visitedTabs.insert(newTab)
        }
        .id(authService.isAuthenticated)
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

// MARK: - Shared Scout Promo Banner
struct ScoutPromoBanner: View {
    @EnvironmentObject private var bannerManager: ScoutBannerManager
    
    var body: some View {
        if bannerManager.isBannerVisible && !StorageService.shared.settings.isKidsProfile {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.body)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Scout")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("Get personalized recommendations from our AI assistant")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Button {
                    bannerManager.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
            )
            .padding(.horizontal)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview {
    ContentView()
}
