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
    
    enum Tab: String, CaseIterable {
        case browse = "Browse"
        case search = "Search"
        case lists = "Lists"
        case chron = "Chron"
        case settings = "Settings"
        
        var iconName: String {
            switch self {
            case .browse: return "rectangle.grid.2x2.fill"
            case .search: return "magnifyingglass"
            case .lists: return "list.bullet"
            case .chron: return "sparkles"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    var body: some View {
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
            
            AIAssistantView()
                .tabItem {
                    Label(Tab.chron.rawValue, systemImage: Tab.chron.iconName)
                }
                .tag(Tab.chron)
            
            SettingsView()
                .tabItem {
                    Label(Tab.settings.rawValue, systemImage: Tab.settings.iconName)
                }
                .tag(Tab.settings)
        }
        .tint(.accentColor)
        .sheet(item: $selectedMediaItem) { item in
            MediaDetailView(item: item)
        }
    }
}

#Preview {
    ContentView()
}
