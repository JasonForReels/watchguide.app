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
            .sheet(item: $selectedMediaItem) { item in
                MediaDetailView(item: item)
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

#Preview {
    ContentView()
}
