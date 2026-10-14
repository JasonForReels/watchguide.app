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
    @State private var showShareCard = false
    @State private var showShareCardPaywall = false
    
    var body: some View {
        #if os(tvOS)
        legacyRow
        #else
        WGWatchActions(
            mediaId: mediaId,
            mediaType: mediaType,
            savedItem: savedItem,
            showAddToList: $showAddToList,
            onShareCard: openShareCard
        )
        .modifier(sheets)
        #endif
    }

    private func openShareCard() {
        if AIMessageQuota.isPlusOrAbove() {
            showShareCard = true
        } else {
            showShareCardPaywall = true
        }
    }

    private var sheets: ListActionSheets {
        ListActionSheets(savedItem: savedItem, mediaType: mediaType,
                         showAddToList: $showAddToList, showShareCard: $showShareCard,
                         showShareCardPaywall: $showShareCardPaywall)
    }

    private var legacyRow: some View {
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
            
            // Share Card (Plus+ gated)
            ActionButton(
                title: "Share Card",
                iconName: "rectangle.and.pencil.and.ellipsis",
                isActive: false,
                action: openShareCard
            )
        }
        .modifier(sheets)
    }
}

private struct ListActionSheets: ViewModifier {
    let savedItem: SavedMediaItem
    let mediaType: MediaType
    @Binding var showAddToList: Bool
    @Binding var showShareCard: Bool
    @Binding var showShareCardPaywall: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showAddToList) {
                AddToListSheet(item: savedItem)
            }
            .sheet(isPresented: $showShareCard) {
                ShareCardView(
                    title: savedItem.title,
                    posterPath: savedItem.posterPath,
                    mediaType: mediaType,
                    rating: nil,
                    comment: nil,
                    userName: nil
                )
            }
            .sheet(isPresented: $showShareCardPaywall) {
                WGSubscriptionPaywallView(context: .plus)
            }
    }
}

#if !os(tvOS)
// MARK: - Watch Actions (iOS)

/// The title page's actions: one confident glass capsule for the thing people
/// come here to do — mark it watched — with Watchlist beside it, and the
/// occasional actions in a quieter row of glass circles beneath.
///
/// Marking watched gets a proper beat: the check draws itself in, the capsule
/// fills, a ring ripples out and the phone confirms with a success tap.
/// Underneath, the count of titles watched this year ticks over — a real
/// number from the user's library, never a made-up one.
private struct WGWatchActions: View {
    let mediaId: Int
    let mediaType: MediaType
    let savedItem: SavedMediaItem
    @Binding var showAddToList: Bool
    let onShareCard: () -> Void

    @ObservedObject private var storage = StorageService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rippleCount = 0

    private var isWatched: Bool { storage.isInWatched(mediaId, mediaType: mediaType) }
    private var isOnWatchlist: Bool { storage.isInWantToWatch(mediaId, mediaType: mediaType) }
    private var isLiked: Bool { storage.isInLiked(mediaId, mediaType: mediaType) }

    private var watchedThisYear: Int {
        storage.watched.filter { Calendar.current.isDate($0.addedAt, equalTo: Date(), toGranularity: .year) }.count
    }

    private var watchedThisYearCaption: String {
        let n = watchedThisYear
        guard n > 1 else { return "Your first this year." }
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "Your \(n.formatted(.number))\(suffix) this year."
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                watchedCapsule
                circleButton(icon: isOnWatchlist ? "bookmark.fill" : "bookmark",
                             label: isOnWatchlist ? "On Watchlist" : "Add to Watchlist",
                             isOn: isOnWatchlist) {
                    storage.toggleWantToWatch(savedItem)
                }
                .frame(width: 54, height: 54)
            }

            if isWatched {
                Text(watchedThisYearCaption)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .transition(.wgBadgeArrival)
            }

            HStack(spacing: 28) {
                secondary(icon: isLiked ? "heart.fill" : "heart", title: "Like",
                          tint: isLiked ? .red : nil) { storage.toggleLiked(savedItem) }
                secondary(icon: "text.badge.plus", title: "Lists") { showAddToList = true }
                secondary(icon: "square.and.arrow.up", title: "Share Card", action: onShareCard)
            }
        }
        .animation(WGMotion.resolved(WGMotion.bouncy, reduceMotion: reduceMotion), value: isWatched)
    }

    private var watchedCapsule: some View {
        Button {
            let marking = !isWatched
            storage.toggleWatched(savedItem)
            if marking && !reduceMotion { rippleCount += 1 }
        } label: {
            HStack(spacing: 8) {
                if isWatched {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .transition(.symbolEffect(.drawOn))
                }
                Text(isWatched ? "Watched" : "Mark as Watched")
                    .font(.headline)
                    .contentTransition(.interpolate)
            }
            .foregroundStyle(isWatched ? Color(.systemBackground) : .primary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                if isWatched {
                    Capsule().fill(.primary)
                }
            }
            .overlay {
                // A single ring that travels outward each time the title is marked.
                Capsule()
                    .strokeBorder(.primary.opacity(0.55), lineWidth: 2)
                    .keyframeAnimator(initialValue: 1.0, trigger: rippleCount) { ring, progress in
                        ring
                            .scaleEffect(x: 1 + 0.12 * progress, y: 1 + 0.6 * progress)
                            .opacity(1 - progress)
                    } keyframes: { _ in
                        LinearKeyframe(0.0, duration: 0)
                        CubicKeyframe(1.0, duration: 0.7)
                    }
                    .allowsHitTesting(false)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.wgPress)
        .glassEffect(.regular.interactive(), in: Capsule())
        .scaleEffect(isWatched ? 1.02 : 1)
        .sensoryFeedback(.success, trigger: isWatched) { _, now in now }
        .accessibilityLabel(isWatched ? "Watched" : "Mark as Watched")
        .accessibilityAddTraits(isWatched ? .isSelected : [])
    }

    private func circleButton(icon: String, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Circle())
        }
        .buttonStyle(.wgPressDeep)
        .glassEffect(.regular.interactive(), in: Circle())
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(label)
    }

    private func secondary(icon: String, title: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(tint ?? .primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 46, height: 46)
                    .glassEffect(.regular.interactive(), in: Circle())
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.wgPressDeep)
    }
}
#endif

struct ActionButton: View {
    let title: String
    let iconName: String
    let isActive: Bool
    var activeColor: Color = .accentColor
    let action: () -> Void
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #endif

    private var isCompact: Bool {
        #if os(tvOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
    private var compactMinHeight: CGFloat { isCompact ? 40 : 76 }
    private var compactVerticalPad: CGFloat { isCompact ? 4 : 10 }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: isCompact ? 4 : 6) {
                Image(systemName: iconName)
                    .font(isCompact ? .body : .title2)
                    .foregroundColor(isActive ? activeColor : .primary)
                    // The outline and filled glyphs are one symbol in two
                    // states, so morph between them rather than swapping the
                    // image out — and let the symbol itself react to being
                    // switched on. This is the whole animation; the old
                    // delayed 1.3x pop was standing in for it.
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .symbolEffect(.bounce, options: .speed(1.4), value: isActive)
                
                Text(title)
                    .font(.caption2)
                    .foregroundColor(labelColor)
            }
            .frame(maxWidth: .infinity, minHeight: compactMinHeight)
            .padding(.vertical, compactVerticalPad)
            .padding(.horizontal, isCompact ? 6 : 10)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 12 : 16, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: isCompact ? 12 : 16, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
            .scaleEffect(scaleEffect)
            .animation(WGMotion.snappy, value: isActive)
        }
        #if os(tvOS)
        .buttonStyle(TVOSTransparentButtonStyle(cornerRadius: isCompact ? 12 : 16))
        .focused($isFocused)
        #else
        .buttonStyle(.wgPressDeep)
        .sensoryFeedback(.success, trigger: isActive) { _, active in active }
        #endif
    }

    private var labelColor: Color {
        isActive ? activeColor : .secondary
    }

    private var backgroundFill: Color {
        #if os(tvOS)
        if isActive {
            return activeColor.opacity(0.22)
        }
        return Color.white.opacity(0.10)
        #else
        if isActive {
            return activeColor.opacity(0.22)
        }

        return Color.secondary.opacity(0.12)
        #endif
    }

    private var borderColor: Color {
        if isActive {
            #if os(tvOS)
            return activeColor.opacity(isFocused ? 0.95 : 0.72)
            #else
            return activeColor.opacity(0.7)
            #endif
        }

        #if os(tvOS)
        return Color.white.opacity(isFocused ? 0.96 : 0.18)
        #else
        return Color.primary.opacity(0.12)
        #endif
    }

    private var borderWidth: CGFloat {
        #if os(tvOS)
        return isFocused ? 2.6 : (isActive ? 1.6 : 1.1)
        #else
        return isActive ? 1.4 : 1
        #endif
    }

    private var shadowColor: Color {
        #if os(tvOS)
        return Color.black.opacity(isFocused ? 0.4 : 0.16)
        #else
        return Color.clear
        #endif
    }

    private var shadowRadius: CGFloat {
        #if os(tvOS)
        return isFocused ? 18 : 6
        #else
        return 0
        #endif
    }

    private var shadowYOffset: CGFloat {
        #if os(tvOS)
        return isFocused ? 10 : 3
        #else
        return 0
        #endif
    }

    private var scaleEffect: CGFloat {
        #if os(tvOS)
        return isFocused ? 1.08 : 1
        #else
        return 1
        #endif
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
            #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
