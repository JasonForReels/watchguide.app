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
        case lists = 1
        case ai = 2
        case settings = 3
        
        var id: Int { rawValue }
        
        var label: String {
            switch self {
            case .browse: return "Home"
            case .lists: return "Lists"
            case .ai: return "AI"
            case .settings: return "Settings"
            }
        }
        
        var iconName: String {
            switch self {
            case .browse: return "house.fill"
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
            Tab.browse.tab {
                BrowseView(selectedItem: $selectedMediaItem)
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
