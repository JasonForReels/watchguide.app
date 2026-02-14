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
        }
    }
    
    private var requiresOnboarding: Bool {
        if !onboardingComplete { return true }
        return false
    }
    
    // MARK: - iPhone Layout (TabView)
    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            Tab.browse.tab {
                BrowseView(selectedItem: $selectedMediaItem)
            }
            
            Tab.search.tab {
                LazyTabContent(tab: .search, visitedTabs: $visitedTabs) {
                    NavigationStack {
                        SearchView(selectedItem: $selectedMediaItem)
                            .navigationTitle("Search")
                    }
                }
            }
            
            Tab.ai.tab {
                LazyTabContent(tab: .ai, visitedTabs: $visitedTabs) {
                    AIAssistantView()
                }
            }
            
            Tab.lists.tab {
                LazyTabContent(tab: .lists, visitedTabs: $visitedTabs) {
                    ListsView()
                }
            }
            
            Tab.settings.tab {
                LazyTabContent(tab: .settings, visitedTabs: $visitedTabs) {
                    NavigationStack {
                        SettingsView()
                            .navigationTitle("Settings")
                    }
                }
            }
        }
        .tint(.accentColor)
        .onChange(of: selectedTab) { _, newTab in
            visitedTabs.insert(newTab)
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

// MARK: - Tab Extension for building tab items
extension ContentView.Tab {
    @ViewBuilder
    func tab<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .tabItem {
                Label(self.label, systemImage: self.iconName)
            }
            .tag(self)
    }
}

// MARK: - Shared Scout Promo Banner
struct ScoutPromoBanner: View {
    @EnvironmentObject private var bannerManager: ScoutBannerManager
    
    var body: some View {
        if bannerManager.isBannerVisible {
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
