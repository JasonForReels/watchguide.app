//
//  ListActionsView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct ListActionsView: View {
    let mediaId: Int
    let mediaType: MediaType
    let savedItem: SavedMediaItem
    
    @ObservedObject private var storage = StorageService.shared
    @State private var showAddToList = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Want to Watch
            ActionButton(
                title: "Watchlist",
                iconName: storage.isInWantToWatch(mediaId, mediaType: mediaType) ? "bookmark.fill" : "bookmark",
                isActive: storage.isInWantToWatch(mediaId, mediaType: mediaType),
                action: {
                    storage.toggleWantToWatch(savedItem)
                }
            )
            
            // Watched
            ActionButton(
                title: "Watched",
                iconName: storage.isInWatched(mediaId, mediaType: mediaType) ? "checkmark.circle.fill" : "checkmark.circle",
                isActive: storage.isInWatched(mediaId, mediaType: mediaType),
                action: {
                    storage.toggleWatched(savedItem)
                }
            )
            
            // Liked
            ActionButton(
                title: "Liked",
                iconName: storage.isInLiked(mediaId, mediaType: mediaType) ? "heart.fill" : "heart",
                isActive: storage.isInLiked(mediaId, mediaType: mediaType),
                activeColor: .red,
                action: {
                    storage.toggleLiked(savedItem)
                }
            )
            
            // Add to list
            ActionButton(
                title: "Add to List",
                iconName: "plus.rectangle.on.folder",
                isActive: false,
                action: {
                    showAddToList = true
                }
            )
        }
        .sheet(isPresented: $showAddToList) {
            AddToListSheet(item: savedItem)
        }
    }
}

struct ActionButton: View {
    let title: String
    let iconName: String
    let isActive: Bool
    var activeColor: Color = .accentColor
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                action()
            }
        }) {
            VStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(isActive ? activeColor : .primary)
                    .scaleEffect(isPressed ? 1.3 : 1.0)
                
                Text(title)
                    .font(.caption2)
                    .foregroundColor(isActive ? activeColor : .secondary)
            }
            .frame(minWidth: 60)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? activeColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add to List Sheet
struct AddToListSheet: View {
    let item: SavedMediaItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var storage = StorageService.shared
    @State private var showCreateList = false
    @State private var newListName = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section("Default Lists") {
                    ListRow(
                        name: "Want to Watch",
                        iconName: "bookmark.fill",
                        isInList: storage.isInWantToWatch(item.mediaId, mediaType: item.mediaType),
                        action: {
                            storage.toggleWantToWatch(item)
                        }
                    )
                    
                    ListRow(
                        name: "Watched",
                        iconName: "checkmark.circle.fill",
                        isInList: storage.isInWatched(item.mediaId, mediaType: item.mediaType),
                        action: {
                            storage.toggleWatched(item)
                        }
                    )
                    
                    ListRow(
                        name: "Liked",
                        iconName: "heart.fill",
                        isInList: storage.isInLiked(item.mediaId, mediaType: item.mediaType),
                        action: {
                            storage.toggleLiked(item)
                        }
                    )
                }
                
                if !storage.customLists.isEmpty {
                    Section("Custom Lists") {
                        ForEach(storage.customLists) { list in
                            ListRow(
                                name: list.name,
                                iconName: list.iconName,
                                isInList: storage.isInCustomList(listId: list.id, mediaId: item.mediaId, mediaType: item.mediaType),
                                action: {
                                    if storage.isInCustomList(listId: list.id, mediaId: item.mediaId, mediaType: item.mediaType) {
                                        storage.removeFromCustomList(listId: list.id, item: item)
                                    } else {
                                        storage.addToCustomList(listId: list.id, item: item)
                                    }
                                }
                            )
                        }
                    }
                }
                
                Section {
                    Button {
                        showCreateList = true
                    } label: {
                        Label("Create New List", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Add to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
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
                        if let newList = storage.customLists.last {
                            storage.addToCustomList(listId: newList.id, item: item)
                        }
                        newListName = ""
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ListRow: View {
    let name: String
    let iconName: String
    let isInList: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(isInList ? .accentColor : .secondary)
                    .frame(width: 24)
                
                Text(name)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isInList {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}

#Preview {
    ListActionsView(
        mediaId: 550,
        mediaType: .movie,
        savedItem: SavedMediaItem(from: MediaItem(
            id: 550,
            title: "Fight Club",
            name: nil,
            originalTitle: nil,
            originalName: nil,
            overview: nil,
            posterPath: nil,
            backdropPath: nil,
            releaseDate: nil,
            firstAirDate: nil,
            voteAverage: nil,
            voteCount: nil,
            popularity: nil,
            genreIds: nil,
            mediaType: "movie",
            adult: nil,
            originalLanguage: nil
        ))
    )
}
