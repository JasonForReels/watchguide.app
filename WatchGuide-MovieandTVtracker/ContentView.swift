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
    
    enum Tab: Int, CaseIterable, Identifiable {
        case browse = 0
        case search = 1
        case lists = 2
        case ai = 3
        case settings = 4
        
        var id: Int { rawValue }
        
        var label: String {
            switch self {
            case .browse: return "Home"
            case .search: return "Search"
            case .lists: return "Library"
            case .ai: return "AI"
            case .settings: return "Settings"
            }
        }
        
        var iconName: String {
            switch self {
            case .browse: return "house.fill"
            case .search: return "magnifyingglass"
            case .lists: return "list.bullet.below.rectangle"
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
            Tab.browse.tab {
                BrowseView(selectedItem: $selectedMediaItem)
            }
            
            Tab.search.tab {
                NavigationStack {
                    SearchView(selectedItem: $selectedMediaItem)
                        .navigationTitle("Search")
                }
            }
            
            Tab.lists.tab {
                ListsView()
            }
            
            Tab.ai.tab {
                AIRecommendView()
            }
            
            Tab.settings.tab {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("Settings")
                }
            }
        }
        .tint(.accentColor)
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
