//
//  ContentView.swift
//  WatchGuide-MovieandTVtracker
//
//  Created by Neel Makhecha on 9/5/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .browse
    @State private var selectedMediaItem: MediaItem?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    enum Tab: String, CaseIterable, Identifiable {
        case browse = "Browse"
        case search = "Search"
        case lists = "Lists"
        case ai = "AI"
        case settings = "Settings"
        
        var id: String { rawValue }
        
        var iconName: String {
            switch self {
            case .browse: return "rectangle.grid.2x2.fill"
            case .search: return "magnifyingglass"
            case .lists: return "list.bullet"
            case .ai: return "sparkles"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    var body: some View {
        Group {
            iPhoneLayout
        }
        .sheet(item: $selectedMediaItem) { item in
            MediaDetailView(item: item)
        }
    }
    
    // MARK: - iPhone Layout (TabView)
    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            BrowseView(selectedItem: $selectedMediaItem)
                .tabItem {
                    Label(Tab.browse.rawValue, systemImage: Tab.browse.iconName)
                }
                .tag(Tab.browse)
            
            SearchView(selectedItem: $selectedMediaItem)
                .tabItem {
                    Label(Tab.search.rawValue, systemImage: Tab.search.iconName)
                }
                .tag(Tab.search)
            
            ListsView()
                .tabItem {
                    Label(Tab.lists.rawValue, systemImage: Tab.lists.iconName)
                }
                .tag(Tab.lists)
            
            AIRecommendView()
                .tabItem {
                    Label(Tab.ai.rawValue, systemImage: Tab.ai.iconName)
                }
                .tag(Tab.ai)
            
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label(Tab.settings.rawValue, systemImage: Tab.settings.iconName)
            }
            .tag(Tab.settings)
        }
        .tint(.accentColor)
    }
}

#Preview {
    ContentView()
}
