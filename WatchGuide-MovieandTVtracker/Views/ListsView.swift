//
//  ListsView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct ListsView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var selectedItem: MediaItem?
    @State private var showCreateList = false
    @State private var showImportMDBList = false
    @State private var newListName = ""
    @State private var selectedTab: ListTab = .wantToWatch
    
    enum ListTab: String, CaseIterable {
        case wantToWatch = "Watchlist"
        case watched = "Watched"
        case liked = "Liked"
        case custom = "Custom"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ListTab.allCases, id: \.rawValue) { tab in
                            TabButton(
                                title: tab.rawValue,
                                count: countForTab(tab),
                                isSelected: selectedTab == tab
                            ) {
                                selectedTab = tab
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                
                Divider()
                
                // Content
                Group {
                    switch selectedTab {
                    case .wantToWatch:
                        listContent(items: storage.wantToWatch, emptyTitle: "Your Watchlist is Empty", emptySubtitle: "Add movies and shows you want to watch")
                    case .watched:
                        listContent(items: storage.watched, emptyTitle: "No Watched Items", emptySubtitle: "Mark titles as watched to track what you've seen")
                    case .liked:
                        listContent(items: storage.liked, emptyTitle: "No Liked Items", emptySubtitle: "Like your favorite movies and shows")
                    case .custom:
                        customListsContent
                    }
                }
            }
            .navigationTitle("My Lists")
            .toolbar {
                if selectedTab == .custom {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                showCreateList = true
                            } label: {
                                Label("Create List", systemImage: "folder.badge.plus")
                            }
                            
                            Button {
                                showImportMDBList = true
                            } label: {
                                Label("Import from PublicMetaDB", systemImage: "arrow.down.circle")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .alert("Create New List", isPresented: $showCreateList) {
                TextField("List Name", text: $newListName)
                Button("Cancel", role: .cancel) {
                    newListName = ""
                }
                Button("Create") {
                    if !newListName.isEmpty {
                        storage.createCustomList(name: newListName)
                        newListName = ""
                    }
                }
            }
            .sheet(isPresented: $showImportMDBList) {
                ImportMDBListSheet()
            }
        }
    }
    
    private func countForTab(_ tab: ListTab) -> Int {
        switch tab {
        case .wantToWatch: return storage.wantToWatch.count
        case .watched: return storage.watched.count
        case .liked: return storage.liked.count
        case .custom: return storage.customLists.count
        }
    }
    
    @ViewBuilder
    private func listContent(items: [SavedMediaItem], emptyTitle: String, emptySubtitle: String) -> some View {
        if items.isEmpty {
            emptyState(title: emptyTitle, subtitle: emptySubtitle)
        } else {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                ], spacing: 20) {
                    ForEach(items) { item in
                        SavedMediaPosterCard(item: item)
                            .onTapGesture {
                                // Convert to MediaItem for detail view
                            }
                    }
                }
                .padding()
            }
        }
    }
    
    @ViewBuilder
    private var customListsContent: some View {
        if storage.customLists.isEmpty && storage.importedLists.isEmpty {
            emptyState(title: "No Custom Lists", subtitle: "Create a list to organize your favorites")
        } else {
            List {
                if !storage.customLists.isEmpty {
                    Section("My Lists") {
                        ForEach(storage.customLists) { list in
                            NavigationLink(destination: CustomListDetailView(list: list)) {
                                HStack {
                                    Image(systemName: list.iconName)
                                        .foregroundColor(.accentColor)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(list.name)
                                            .fontWeight(.medium)
                                        Text("\(list.items.count) items")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                storage.deleteCustomList(id: storage.customLists[index].id)
                            }
                        }
                    }
                }
                
                if !storage.importedLists.isEmpty {
                    Section("Imported Lists") {
                        ForEach(storage.importedLists) { list in
                            NavigationLink(destination: ImportedListDetailView(list: list)) {
                                HStack {
                                    Image(systemName: list.source.iconName)
                                        .foregroundColor(list.source == .mdblist ? .purple : .orange)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(list.name)
                                                .fontWeight(.medium)
                                            Text("(\(list.source.displayName))")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        HStack {
                                            Text("\(list.items.count) items")
                                            if let synced = list.lastSynced {
                                                Text("•")
                                                Text("Synced \(synced.formatted(.relative(presentation: .named)))")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                storage.deleteImportedList(id: storage.importedLists[index].id)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Tab Button
struct TabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.2) : Color(.systemGray4))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

// MARK: - Custom List Detail View
struct CustomListDetailView: View {
    let list: CustomList
    @ObservedObject private var storage = StorageService.shared
    
    var body: some View {
        Group {
            if list.items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("This list is empty")
                        .font(.headline)
                    Text("Add items from movie or TV details")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                    ], spacing: 20) {
                        ForEach(list.items) { item in
                            SavedMediaPosterCard(item: item)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(list.name)
    }
}

// MARK: - Imported List Detail View (PublicMetaDB & MDBList)
struct ImportedListDetailView: View {
    let list: ImportedListItem
    @ObservedObject private var storage = StorageService.shared
    @State private var isSyncing = false
    
    var body: some View {
        Group {
            if list.items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No items yet")
                        .font(.headline)
                    Text("Sync the list to load items")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button {
                        Task {
                            await syncList()
                        }
                    } label: {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSyncing)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                    ], spacing: 20) {
                        ForEach(list.items) { item in
                            SavedMediaPosterCard(item: item)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(list.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await syncList()
                    }
                } label: {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isSyncing)
            }
        }
    }
    
    private func syncList() async {
        isSyncing = true
        
        do {
            var items: [SavedMediaItem] = []
            
            switch list.source {
            case .publicMetaDB:
                items = try await PublicMetaDBService.shared.fetchListItemsAsSavedMedia(listId: list.listId)
            case .mdblist:
                items = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: list.listId)
            }
            
            var updatedList = list
            updatedList.items = items
            updatedList.lastSynced = Date()
            storage.updateImportedList(updatedList)
        } catch {
            print("Failed to sync list: \(error)")
        }
        
        isSyncing = false
    }
}

// MARK: - Import List Sheet (PublicMetaDB & MDBList)
struct ImportMDBListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var storage = StorageService.shared
    @State private var listId = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedSource: ImportedListSource = .publicMetaDB
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source", selection: $selectedSource) {
                        Text("PublicMetaDB").tag(ImportedListSource.publicMetaDB)
                        Text("MDBList").tag(ImportedListSource.mdblist)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section {
                    TextField(selectedSource == .publicMetaDB ? "PublicMetaDB ID or URL" : "MDBList ID or URL", text: $listId)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                } header: {
                    Text("List ID")
                } footer: {
                    if selectedSource == .publicMetaDB {
                        Text("Enter the PublicMetaDB list ID or paste the full URL")
                    } else {
                        Text("Enter the MDBList ID (e.g., username/listname) or paste the full URL")
                    }
                }
                
                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Import List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        Task {
                            await importList()
                        }
                    }
                    .disabled(listId.isEmpty || isLoading)
                }
            }
        }
    }
    
    private func importList() async {
        isLoading = true
        error = nil
        
        switch selectedSource {
        case .publicMetaDB:
            await importFromPublicMetaDB()
        case .mdblist:
            await importFromMDBList()
        }
        
        isLoading = false
        dismiss()
    }
    
    private func importFromPublicMetaDB() async {
        // Extract list ID from URL if needed
        var extractedId = listId
        if listId.contains("publicmetadb.com") {
            extractedId = listId.components(separatedBy: "/").last ?? listId
        }
        
        var newList = ImportedListItem(name: "Imported List", listId: extractedId, source: .publicMetaDB)
        
        // Try to fetch list info and items
        do {
            let info = try await PublicMetaDBService.shared.getListInfo(listId: extractedId)
            newList = ImportedListItem(name: info.name, listId: extractedId, source: .publicMetaDB)
            newList.items = try await PublicMetaDBService.shared.fetchListItemsAsSavedMedia(listId: extractedId)
            newList.lastSynced = Date()
        } catch {
            print("Failed to fetch list: \(error)")
            self.error = "Failed to import list. Please check the ID."
            return
        }
        
        storage.addImportedList(newList)
    }
    
    private func importFromMDBList() async {
        let extractedId = MDBListService.shared.parseListId(from: listId)
        
        // Try to extract list name from URL
        var listName = "MDBList"
        if extractedId.contains("/") {
            let components = extractedId.split(separator: "/")
            if components.count >= 2 {
                listName = String(components.last ?? "MDBList")
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized
            }
        }
        
        var newList = ImportedListItem(name: listName, listId: extractedId, source: .mdblist)
        
        // Try to fetch list items
        do {
            newList.items = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: extractedId)
            newList.lastSynced = Date()
        } catch {
            print("Failed to fetch list: \(error)")
            self.error = "Failed to import list. Please check the ID."
            return
        }
        
        storage.addImportedList(newList)
    }
}

// MARK: - MDBListExploreView
struct MDBListExploreView: View {
    @ObservedObject private var storage = StorageService.shared
    
    private let comedyListId = "dualipafan01/comedy-movies"
    private let comedyListName = "Comedy"
    private let trendingListId = "dualipafan01/trending-titles"
    private let trendingListName = "Trending"
    
    @State private var comedyItems: [SavedMediaItem] = []
    @State private var comedyLoading = true
    @State private var comedyError: String?
    
    @State private var trendingItems: [SavedMediaItem] = []
    @State private var trendingLoading = true
    @State private var trendingError: String?
    
    var body: some View {
        List {
            Section {
                Text("Explore popular curated lists from MDBList.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Section("Comedy") {
                if comedyLoading {
                    ProgressView()
                } else if let error = comedyError {
                    Text(error)
                        .foregroundColor(.red)
                } else if comedyItems.isEmpty {
                    Text("No items found.")
                        .foregroundColor(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(comedyItems.prefix(10), id: \.self.id) { item in
                                VStack(spacing: 4) {
                                    SavedMediaPosterCard(item: item)
                                        .frame(width: 100)
                                    Text(item.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .frame(width: 100)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            Section("Trending") {
                if trendingLoading {
                    ProgressView()
                } else if let error = trendingError {
                    Text(error)
                        .foregroundColor(.red)
                } else if trendingItems.isEmpty {
                    Text("No items found.")
                        .foregroundColor(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(trendingItems.prefix(10), id: \.self.id) { item in
                                VStack(spacing: 4) {
                                    SavedMediaPosterCard(item: item)
                                        .frame(width: 100)
                                    Text(item.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .frame(width: 100)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("MDBList Extensions")
        .task {
            await loadComedyList()
            await loadTrendingList()
        }
    }
    
    private func loadComedyList() async {
        comedyLoading = true
        comedyError = nil
        do {
            comedyItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: comedyListId)
        } catch {
            comedyError = "Failed to load comedy list. Please try again."
            print("MDBList comedy error: \(error)")
        }
        comedyLoading = false
    }
    
    private func loadTrendingList() async {
        trendingLoading = true
        trendingError = nil
        do {
            trendingItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: trendingListId)
        } catch {
            trendingError = "Failed to load trending list. Please try again."
            print("MDBList trending error: \(error)")
        }
        trendingLoading = false
    }
}

#Preview {
    ListsView()
}

