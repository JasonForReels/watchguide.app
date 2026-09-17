//
//  ListsView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if os(tvOS)
import CoreImage.CIFilterBuiltins
import UIKit
#endif

struct ListsView: View {
    @ObservedObject private var storage = StorageService.shared
    @ObservedObject private var traktService = TraktService.shared
    @State private var selectedItem: MediaItem?
    @State private var showCreateList = false
    @State private var showListLimitPaywall = false
    @State private var newListName = ""
    @State private var selectedTab: ListTab = .wantToWatch
    @State private var traktStatusMessage: String?
    @State private var isSmartCategorizing = false
    @State private var showSmartCategorizationAlert = false
    @State private var smartCategorizationAlertMessage = ""
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    enum ListTab: String, CaseIterable {
        case continueWatching = "Continue Watching"
        case wantToWatch = "Watchlist"
        case watched = "Watched"
        case liked = "Liked"
        case custom = "Custom"
        
        var iconName: String {
            switch self {
            case .continueWatching: return "play.circle.fill"
            case .wantToWatch: return "bookmark.fill"
            case .watched: return "checkmark.circle.fill"
            case .liked: return "heart.fill"
            case .custom: return "folder.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
                // Tab selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ListTab.allCases, id: \.rawValue) { tab in
                            TabButton(
                                title: tab.rawValue,
                                count: countForTab(tab),
                                isSelected: selectedTab == tab,
                                iconName: tab.iconName
                            ) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedTab = tab
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                #if os(tvOS)
                .focusSection()
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
                #else
                .padding(.vertical, 12)
                #endif
                
                #if !os(tvOS)
                Divider()
                #endif
                
                // Content
                Group {
                    switch selectedTab {
                    case .continueWatching:
                        continueWatchingContent
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
                
                #if !os(tvOS)
                RemoteBannerView(placement: .lists)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                #endif
            }
            #if os(tvOS)
            .background(TVOSAmbientBackdrop())
            #endif
            .navigationTitle("My Lists")
            .mediaDetailPresentation(item: $selectedItem)
            .toolbar {
                if selectedTab == .continueWatching {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await refreshContinueWatching() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(traktService.isBusy)
                    }
                } else if selectedTab == .custom {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if traktService.isConnected && (!storage.watched.isEmpty || !storage.liked.isEmpty) {
                            Button {
                                Task { await runSmartCategorization() }
                            } label: {
                                if isSmartCategorizing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "wand.and.sparkles")
                                }
                            }
                            .disabled(isSmartCategorizing)
                            .help("Smart Categorize with AI")
                        }
                        Button {
                            if AIMessageQuota.canCreateCustomList(currentCount: storage.customLists.count) {
                                showCreateList = true
                            } else {
                                showListLimitPaywall = true
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
            .sheet(isPresented: $showListLimitPaywall) {
                WGSubscriptionPaywallView(context: .plus)
            }
            .alert("Smart Lists", isPresented: $showSmartCategorizationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(smartCategorizationAlertMessage)
            }
    }
    
    private func countForTab(_ tab: ListTab) -> Int {
        switch tab {
        case .continueWatching: return 0
        case .wantToWatch: return storage.wantToWatch.count
        case .watched: return storage.watched.count
        case .liked: return storage.liked.count
        case .custom: return storage.customLists.count
        }
    }

    private var inProgressItems: [ContinueWatchingItem] {
        storage.continueWatching.filter { $0.status == .inProgress }
    }

    @ViewBuilder
    private var continueWatchingContent: some View {
        if inProgressItems.isEmpty {
            emptyState(
                title: "Nothing to Continue",
                subtitle: "Tap a streaming link on any title to start tracking what you're watching."
            )
            .task {
                await refreshContinueWatchingIfNeeded()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(inProgressItems) { item in
                        #if os(tvOS)
                        FocusableActionSurface(action: {
                            selectedItem = item.show.toMediaItem()
                        }) {
                            ContinueWatchingCard(item: item)
                        }
                        .contextMenu {
                            Button {
                                Task { await ContinueWatchingService.shared.markAsWatched(item) }
                            } label: {
                                Label("Mark as Watched", systemImage: "checkmark.circle")
                            }
                            Button(role: .destructive) {
                                ContinueWatchingService.shared.removeItem(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        #else
                        Button {
                            selectedItem = item.show.toMediaItem()
                        } label: {
                            ContinueWatchingCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                Task { await ContinueWatchingService.shared.markAsWatched(item) }
                            } label: {
                                Label("Mark as Watched", systemImage: "checkmark.circle")
                            }
                            Button(role: .destructive) {
                                ContinueWatchingService.shared.removeItem(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        #endif
                    }
                }
                .padding()
            }
            .task {
                await refreshContinueWatchingIfNeeded()
            }
        }
    }

    private func refreshContinueWatchingIfNeeded() async {
        guard storage.continueWatching.isEmpty else { return }
        await refreshContinueWatching()
    }

    private func refreshContinueWatching() async {
        guard traktService.isConnected else { return }
        do {
            _ = try await traktService.syncContinueWatching()
        } catch {
            print("Continue watching sync failed: \(error)")
        }
    }

    private func runSmartCategorization() async {
        guard !isSmartCategorizing else { return }
        isSmartCategorizing = true
        defer { isSmartCategorizing = false }

        do {
            let count = try await TraktSmartCategorizationService.shared.generateSmartLists()
            if count > 0 {
                smartCategorizationAlertMessage = "Created \(count) smart list\(count == 1 ? "" : "s") based on your Trakt history."
            } else {
                smartCategorizationAlertMessage = "No new lists were created. You may already have smart lists, or try adding more to your watched history."
            }
        } catch {
            smartCategorizationAlertMessage = "Couldn't generate smart lists: \(error.localizedDescription)"
        }

        showSmartCategorizationAlert = true
    }

    // MARK: - Demo / Sample-data path

    @ViewBuilder
    private var smartCategorizationDemoButton: some View {
        VStack(spacing: 12) {
            Divider().padding(.horizontal, 32)
            VStack(spacing: 6) {
                Label("Try Smart Categorize", systemImage: "wand.and.sparkles")
                    .font(.headline)
                Text("Load 15 sample titles and let on-device AI build your first smart lists.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                Task { await runSmartCategorizationDemo() }
            } label: {
                if isSmartCategorizing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Generating…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Generate from Sample Data")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSmartCategorizing)
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 32)
    }

    private func runSmartCategorizationDemo() async {
        guard !isSmartCategorizing else { return }
        isSmartCategorizing = true
        defer { isSmartCategorizing = false }

        // Seed a diverse set of titles so the model has clear patterns to find
        let demoTitles: [(id: Int, title: String, type: MediaType, year: String)] = [
            // High-adrenaline action
            (1001, "John Wick",                     .movie, "2014"),
            (1002, "Mad Max: Fury Road",             .movie, "2015"),
            (1003, "Mission: Impossible – Fallout",  .movie, "2018"),
            (1004, "Top Gun: Maverick",              .movie, "2022"),
            // Cozy comfort TV
            (2001, "The Office",                     .tv,    "2005"),
            (2002, "Parks and Recreation",           .tv,    "2009"),
            (2003, "Schitt's Creek",                 .tv,    "2015"),
            (2004, "Ted Lasso",                      .tv,    "2020"),
            // Mind-bending sci-fi
            (1005, "Interstellar",                   .movie, "2014"),
            (1006, "Arrival",                        .movie, "2016"),
            (2005, "Black Mirror",                   .tv,    "2011"),
            (2006, "Severance",                      .tv,    "2022"),
            // Prestige drama & thrillers
            (2007, "Succession",                     .tv,    "2018"),
            (1008, "Get Out",                        .movie, "2017"),
            (1009, "Knives Out",                     .movie, "2019"),
        ]

        for entry in demoTitles {
            let item = SavedMediaItem(
                id: "\(entry.type.rawValue)-\(entry.id)",
                mediaId: entry.id,
                mediaType: entry.type,
                title: entry.title,
                posterPath: nil,
                backdropPath: nil,
                year: entry.year,
                releaseDate: nil,
                voteAverage: 7.8,
                overview: nil,
                addedAt: Date()
            )
            if !storage.isInWatched(entry.id, mediaType: entry.type) {
                storage.addToWatched(item)
            }
        }

        do {
            let count = try await TraktSmartCategorizationService.shared.generateSmartLists()
            if count > 0 {
                smartCategorizationAlertMessage = "Created \(count) smart list\(count == 1 ? "" : "s") from sample data. Switch to the Watched tab to see the seeded titles."
            } else {
                smartCategorizationAlertMessage = "Smart lists already exist for these titles. Delete them and try again."
            }
        } catch {
            smartCategorizationAlertMessage = "Couldn't generate lists: \(error.localizedDescription)"
        }

        showSmartCategorizationAlert = true
    }
    
    @ViewBuilder
    private func listContent(items: [SavedMediaItem], emptyTitle: String, emptySubtitle: String) -> some View {
        if items.isEmpty {
            emptyState(title: emptyTitle, subtitle: emptySubtitle)
        } else {
            let posterWidth = ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass)
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: posterWidth, maximum: posterWidth), spacing: 16)
                ], spacing: 20) {
                    ForEach(items) { item in
                        #if os(tvOS)
                        FocusableActionSurface(action: {
                            selectedItem = item.toMediaItem()
                        }) {
                            SavedMediaPosterCard(item: item, allowsExpansion: false, widthOverride: posterWidth)
                                .contentShape(Rectangle())
                        }
                        #else
                        Button {
                            selectedItem = item.toMediaItem()
                        } label: {
                            SavedMediaPosterCard(item: item, allowsExpansion: false, widthOverride: posterWidth)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding()
            }
        }
    }
    
    @ViewBuilder
    private var customListsContent: some View {
        if storage.customLists.isEmpty && storage.importedLists.isEmpty {
            VStack(spacing: 0) {
                emptyState(title: "No Custom Lists", subtitle: "Create a list to organize your favorites")
                #if !os(tvOS)
                smartCategorizationDemoButton
                #endif
            }
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
                                        .foregroundColor(.accentColor)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(list.displayName)
                                            .fontWeight(.medium)
                                        Text("\(list.items.count) items")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Text(list.source.displayName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
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

#if os(tvOS)
private struct ListsTraktTVActivationView: View {
    let activation: TraktTVActivation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let qrImage = qrCodeImage(for: activation.verificationURL.absoluteString) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Scan with your phone or go to:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(activation.verificationURL.absoluteString)
                    .font(.caption.monospaced())

                Text("Enter code: \(activation.userCode)")
                    .font(.headline.monospaced())

                Text("This code expires at \(activation.expiresAt.formatted(date: .omitted, time: .shortened)).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func qrCodeImage(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaledImage = outputImage.transformed(by: transform)
        let context = CIContext()

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
#endif

// MARK: - Tab Button
struct TabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    var iconName: String? = nil
    let action: () -> Void

    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #endif

    var body: some View {
        #if os(tvOS)
        HStack(spacing: 8) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.system(size: isSelected ? 18 : 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }

            if isSelected {
                Text(title)
                    .fontWeight(.semibold)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.8, anchor: .leading)),
                        removal: .opacity.combined(with: .scale(scale: 0.8, anchor: .leading))
                    ))

                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
        }
        .padding(.horizontal, isSelected ? 22 : 16)
        .padding(.vertical, 14)
        .foregroundColor(isSelected ? .white : (isFocused ? .white : Color.white.opacity(0.5)))
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(isFocused ? 0.12 : 0.06))
        )
        .focusable(true)
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused {
                action()
            }
        }
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .shadow(color: .white.opacity(isFocused ? 0.08 : 0), radius: isFocused ? 10 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSelected)
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: isFocused)
        #else
        Button {
            action()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)

                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.2) : Color.gray.opacity(0.35))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.12))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
        #endif
    }
}

// MARK: - Custom List Detail View
struct CustomListDetailView: View {
    let list: CustomList
    @ObservedObject private var storage = StorageService.shared
    @State private var selectedItem: MediaItem?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
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
                let posterWidth = ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass)
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: posterWidth, maximum: posterWidth), spacing: 16)
                    ], spacing: 20) {
                        ForEach(list.items) { item in
                            #if os(tvOS)
                            FocusableActionSurface(action: {
                                selectedItem = item.toMediaItem()
                            }) {
                                SavedMediaPosterCard(item: item, allowsExpansion: false, widthOverride: posterWidth)
                                    .contentShape(Rectangle())
                            }
                            #else
                            Button {
                                selectedItem = item.toMediaItem()
                            } label: {
                                SavedMediaPosterCard(item: item, allowsExpansion: false, widthOverride: posterWidth)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            #endif
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(list.name)
        .mediaDetailPresentation(item: $selectedItem)
    }
}

struct ImportedListDetailView: View {
    let list: ImportedListItem
    @State private var selectedItem: MediaItem?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if list.items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: list.source.iconName)
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("This imported list is empty")
                        .font(.headline)
                    Text("Sync or import it again from Settings.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                let posterWidth = ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass)
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: posterWidth, maximum: posterWidth), spacing: 16)
                    ], spacing: 20) {
                        ForEach(list.items) { item in
                            #if os(tvOS)
                            FocusableActionSurface(action: {
                                selectedItem = item.toMediaItem()
                            }) {
                                SavedMediaPosterCard(item: item, allowsExpansion: false, widthOverride: posterWidth)
                                    .contentShape(Rectangle())
                            }
                            #else
                            Button {
                                selectedItem = item.toMediaItem()
                            } label: {
                                SavedMediaPosterCard(item: item, allowsExpansion: false, widthOverride: posterWidth)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            #endif
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(list.displayName)
        .mediaDetailPresentation(item: $selectedItem)
    }
}

struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isFocused) private var isFocused

    private var progressLabel: String {
        "\(Int((item.progress * 100).rounded()))% watched"
    }

    private var providerLogos: [WatchProvider] {
        let providers = item.providers
        return Array(
            (providers?.flatrate ?? [])
                + (providers?.free ?? [])
                + (providers?.ads ?? [])
        )
        .uniqued(by: \.providerId)
        .prefix(4)
        .map { $0 }
    }

    var body: some View {
        let posterWidth = min(ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass) * 0.82, 122)

        HStack(alignment: .top, spacing: 14) {
            SavedMediaPosterCard(item: item.show, allowsExpansion: false, widthOverride: posterWidth)
                .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 10) {
                Text(item.show.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    if let lastEpisode = item.lastEpisode {
                        Label("Up to \(lastEpisode.code)", systemImage: "play.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let title = lastEpisode.title, !title.isEmpty {
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    if item.progress >= 0 {
                        ProgressView(value: item.progress)
                            .tint(.accentColor)

                        Text(progressLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("In Progress", systemImage: "play.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                if let nextEpisode = item.nextEpisode {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next to watch")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(nextEpisode.code) \(nextEpisode.title ?? "Next Episode")")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let upcomingEpisode = item.upcomingEpisode, let airDate = upcomingEpisode.airDate {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coming up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(upcomingEpisode.code) airs \(formattedDate(airDate))")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !providerLogos.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Where to watch next")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(providerLogos) { provider in
                                ResilientAsyncImage(url: TMDBService.shared.imageURL(path: provider.logoPath, size: .logo)) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.secondary.opacity(0.15))
                                            .overlay {
                                                Text(String(provider.providerName.prefix(2)))
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.secondary)
                                            }
                                    }
                                }
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.9 : 0.14), lineWidth: isFocused ? 1.0 : 0.75)
        }
        #if os(tvOS)
        .shadow(color: .black.opacity(isFocused ? 0.28 : 0.12), radius: isFocused ? 24 : 12, y: isFocused ? 14 : 8)
        #endif
    }

    private func formattedDate(_ value: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")

        guard let date = parser.date(from: value) else {
            return value
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private extension Array {
    func uniqued<Value: Hashable>(by keyPath: KeyPath<Element, Value>) -> [Element] {
        var seen = Set<Value>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

#Preview {
    ListsView()
}
