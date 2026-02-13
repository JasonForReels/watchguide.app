//
//  BrowseView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct BrowseView: View {
    @StateObject private var viewModel = BrowseViewModel()
    @StateObject private var forYouVM = ForYouViewModel()
    @Binding var selectedItem: MediaItem?
    @State private var selectedNetworkHub: NetworkHub?
    @State private var activeStudioSheet: StudioSheet?
    @State private var showCustomizeSheet = false
    @State private var selectedPerson: Person?
    
    enum StudioSheet: String, Identifiable {
        case twentiethCentury, warnerBros, dreamWorks, dcStudios, universalPictures, sonyPictures
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Scout AI Banner
                    ScoutPromoBanner()
                    
                    // Hero Carousel
                    if !viewModel.heroItems.isEmpty {
                        HeroCarouselView(items: viewModel.heroItems) { item in
                            selectedItem = item
                        }
                    }
                    
                    // Networks Section (Streaming Services)
                    if !viewModel.networkHubs.isEmpty {
                        NetworkHubsRow(hubs: viewModel.networkHubs) { hub in
                            selectedNetworkHub = hub
                        }
                        .padding(.top, 4)
                    }
                    
                    // Browse Rows with Studios buttons + For You row inserted
                    ForEach(Array(viewModel.rows.enumerated()), id: \.element.title) { _, row in
                        if !row.people.isEmpty {
                            PeopleRowView(
                                title: row.title,
                                people: row.people,
                                onPersonTap: { person in
                                    selectedPerson = person
                                }
                            )
                        } else if !row.items.isEmpty {
                            MediaRowView(
                                title: row.title,
                                items: row.items,
                                onItemTap: { item in
                                    selectedItem = item
                                }
                            )
                        }
                        
                        // Insert Studios buttons after Trending TV Shows row
                        if row.title == "Trending TV Shows" {
                            StudiosHubRow(
                                onTwentiethCenturyTap: { activeStudioSheet = .twentiethCentury },
                                onWarnerBrosTap: { activeStudioSheet = .warnerBros },
                                onDreamWorksTap: { activeStudioSheet = .dreamWorks },
                                onDCStudiosTap: { activeStudioSheet = .dcStudios },
                                onUniversalPicturesTap: { activeStudioSheet = .universalPictures },
                                onSonyPicturesTap: { activeStudioSheet = .sonyPictures }
                            )
                            
                            // For You Row (AI-powered, based on likes)
                            ForYouRow(viewModel: forYouVM) { item in
                                selectedItem = item
                            }
                        }
                    }
                    
                    // MARK: - Discover Section
                    BrowseDiscoverSection()
                }
                .padding(.vertical)
            }
            .refreshable {
                await viewModel.refresh()
                await forYouVM.refresh()
            }
            .task {
                await viewModel.loadContent()
                await forYouVM.loadIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCustomizeSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(item: $selectedNetworkHub) { hub in
                NetworkHubSheet(hub: hub, selectedItem: $selectedItem)
            }
            .sheet(item: $activeStudioSheet) { studio in
                switch studio {
                case .twentiethCentury:
                    TwentiethCenturyStudiosSheet(selectedItem: $selectedItem)
                case .warnerBros:
                    WarnerBrosSheet(selectedItem: $selectedItem)
                case .dreamWorks:
                    DreamWorksSheet(selectedItem: $selectedItem)
                case .dcStudios:
                    DCStudiosSheet(selectedItem: $selectedItem)
                case .universalPictures:
                    UniversalPicturesSheet(selectedItem: $selectedItem)
                case .sonyPictures:
                    SonyPicturesSheet(selectedItem: $selectedItem)
                }
            }
            .sheet(isPresented: $showCustomizeSheet) {
                HomeCustomizationView()
            }
            .onChange(of: StorageService.shared.settings.heroCarouselSource) { _, _ in
                Task { await viewModel.refresh() }
            }
            .sheet(item: $selectedPerson) { person in
                PersonDetailView(
                    personId: person.id,
                    personName: person.name,
                    profilePath: person.profilePath
                )
            }
        }
    }
}

// MARK: - Liquid Glass Hub Button (Shared Component)
struct LiquidGlassHubButton: View {
    let imageURL: String
    let label: String
    let fallbackText: String
    let action: () -> Void
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) {
                ZStack {
                    // Outer glow ring
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(colorScheme == .dark ? 0.06 : 0.12),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 28,
                                endRadius: 42
                            )
                        )
                        .frame(width: 72, height: 72)
                    
                    // Main button body with 3D layering
                    ZStack {
                        // Shadow/depth base layer
                        Circle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 62, height: 62)
                            .offset(y: 2)
                            .blur(radius: 3)
                        
                        // Main background
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 62, height: 62)
                        
                        // Inner gradient for 3D curvature
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(colorScheme == .dark ? 0.12 : 0.25),
                                        .clear,
                                        .black.opacity(colorScheme == .dark ? 0.15 : 0.05)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 62, height: 62)
                        
                        // Content
                        AsyncImage(url: URL(string: imageURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 54, height: 54)
                                    .clipShape(Circle())
                            case .failure, .empty:
                                Text(fallbackText)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .frame(width: 54, height: 54)
                            @unknown default:
                                ProgressView()
                                    .frame(width: 54, height: 54)
                            }
                        }
                        
                        // Top specular highlight
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(colorScheme == .dark ? 0.18 : 0.3),
                                        .white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(width: 62, height: 62)
                            .mask(
                                VStack {
                                    Ellipse()
                                        .frame(width: 44, height: 20)
                                        .offset(y: 4)
                                    Spacer()
                                }
                                .frame(width: 62, height: 62)
                            )
                        
                        // Border ring
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(colorScheme == .dark ? 0.25 : 0.4),
                                        .white.opacity(colorScheme == .dark ? 0.05 : 0.1),
                                        .white.opacity(0.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                            .frame(width: 62, height: 62)
                    }
                }
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: isPressed ? 2 : 6, y: isPressed ? 1 : 3)
                .scaleEffect(isPressed ? 0.90 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Studios Hub Row
struct StudiosHubRow: View {
    let onTwentiethCenturyTap: () -> Void
    let onWarnerBrosTap: () -> Void
    let onDreamWorksTap: () -> Void
    let onDCStudiosTap: () -> Void
    let onUniversalPicturesTap: () -> Void
    let onSonyPicturesTap: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                StudioHubButton(
                    label: "20th Century",
                    brandColor: Color(red: 0x66/255, green: 0x66/255, blue: 0x66/255),
                    action: onTwentiethCenturyTap
                )
                StudioHubButton(
                    label: "Warner Bros",
                    brandColor: Color(red: 0x05/255, green: 0x00/255, blue: 0x8C/255),
                    action: onWarnerBrosTap
                )
                StudioHubButton(
                    label: "DreamWorks",
                    brandColor: Color(red: 0x22/255, green: 0x22/255, blue: 0x22/255),
                    action: onDreamWorksTap
                )
                StudioHubButton(
                    label: "DC Studios",
                    brandColor: Color(red: 0x00/255, green: 0x74/255, blue: 0xE8/255),
                    action: onDCStudiosTap
                )
                StudioHubButton(
                    label: "Universal",
                    brandColor: Color(red: 0x37/255, green: 0x5F/255, blue: 0x78/255),
                    action: onUniversalPicturesTap
                )
                StudioHubButton(
                    label: "Sony Pictures",
                    brandColor: Color(red: 0xB5/255, green: 0xB6/255, blue: 0xB7/255),
                    action: onSonyPicturesTap
                )
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

// MARK: - Studio Hub Button
struct StudioHubButton: View {
    let label: String
    let brandColor: Color
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minWidth: 80)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(brandColor)
                )
        }
        .buttonStyle(.plain)
        .shadow(color: brandColor.opacity(0.35), radius: isPressed ? 2 : 5, y: isPressed ? 1 : 3)
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - 20th Century Studios Sheet
struct TwentiethCenturyStudiosSheet: View {
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var allItems: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedTab = 0
    
    private var movies: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .movie }
    }
    
    private var tvShows: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .tv }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                AsyncImage(url: URL(string: "https://i.ibb.co/0VZ8BZdZ/20th-century-studios-seeklogo.png")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60)
                    default:
                        EmptyView()
                    }
                }
                .padding(.vertical, 16)
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    let items = selectedTab == 0 ? movies : tvShows
                    
                    if items.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: selectedTab == 0 ? "film" : "tv")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No \(selectedTab == 0 ? "movies" : "TV shows") found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                            ], spacing: 20) {
                                ForEach(items) { item in
                                    SavedMediaPosterCard(item: item)
                                        .onTapGesture {
                                            // Convert SavedMediaItem to MediaItem
                                            let mediaItem = MediaItem(
                                                id: item.mediaId,
                                                title: item.mediaType == .movie ? item.title : nil,
                                                name: item.mediaType == .tv ? item.title : nil,
                                                originalTitle: nil,
                                                originalName: nil,
                                                overview: item.overview,
                                                posterPath: item.posterPath,
                                                backdropPath: item.backdropPath,
                                                releaseDate: item.year,
                                                firstAirDate: item.year,
                                                voteAverage: item.voteAverage,
                                                voteCount: nil,
                                                popularity: nil,
                                                genreIds: nil,
                                                mediaType: item.mediaType.rawValue,
                                                adult: nil,
                                                originalLanguage: nil
                                            )
                                            selectedItem = mediaItem
                                            dismiss()
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        isLoading = true
        error = nil
        
        do {
            // Fetch from MDBList: dualipafan01/20th-century-studios
            allItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: "dualipafan01/20th-century-studios")
            if allItems.isEmpty {
                error = "No content found in this list."
            }
        } catch {
            self.error = "Failed to load content. Please try again."
            print("20th Century Studios error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Warner Bros Sheet
struct WarnerBrosSheet: View {
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var allItems: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedTab = 0
    
    private var movies: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .movie }
    }
    
    private var tvShows: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .tv }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                AsyncImage(url: URL(string: "https://i.ibb.co/wZ1HR70w/Pik-Png-com-warner-bros-logo-png-1514023.png")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60)
                    default:
                        EmptyView()
                    }
                }
                .padding(.vertical, 16)
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    let items = selectedTab == 0 ? movies : tvShows
                    
                    if items.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: selectedTab == 0 ? "film" : "tv")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No \(selectedTab == 0 ? "movies" : "TV shows") found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                            ], spacing: 20) {
                                ForEach(items) { item in
                                    SavedMediaPosterCard(item: item)
                                        .onTapGesture {
                                            // Convert SavedMediaItem to MediaItem
                                            let mediaItem = MediaItem(
                                                id: item.mediaId,
                                                title: item.mediaType == .movie ? item.title : nil,
                                                name: item.mediaType == .tv ? item.title : nil,
                                                originalTitle: nil,
                                                originalName: nil,
                                                overview: item.overview,
                                                posterPath: item.posterPath,
                                                backdropPath: item.backdropPath,
                                                releaseDate: item.year,
                                                firstAirDate: item.year,
                                                voteAverage: item.voteAverage,
                                                voteCount: nil,
                                                popularity: nil,
                                                genreIds: nil,
                                                mediaType: item.mediaType.rawValue,
                                                adult: nil,
                                                originalLanguage: nil
                                            )
                                            selectedItem = mediaItem
                                            dismiss()
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        isLoading = true
        error = nil
        
        do {
            // Fetch from MDBList: dualipafan01/warner-bros
            allItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: "dualipafan01/warner-bros")
            if allItems.isEmpty {
                error = "No content found in this list."
            }
        } catch {
            self.error = "Failed to load content. Please try again."
            print("Warner Bros error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - DreamWorks Sheet
struct DreamWorksSheet: View {
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var allItems: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedTab = 0
    
    private var movies: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .movie }
    }
    
    private var tvShows: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .tv }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                AsyncImage(url: URL(string: "https://i.ibb.co/ZRKVxnCG/Dream-Works-Animation-2016-Moon-Boy-svg.png")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60)
                    default:
                        EmptyView()
                    }
                }
                .padding(.vertical, 16)
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    let items = selectedTab == 0 ? movies : tvShows
                    
                    if items.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: selectedTab == 0 ? "film" : "tv")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No \(selectedTab == 0 ? "movies" : "TV shows") found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                            ], spacing: 20) {
                                ForEach(items) { item in
                                    SavedMediaPosterCard(item: item)
                                        .onTapGesture {
                                            // Convert SavedMediaItem to MediaItem
                                            let mediaItem = MediaItem(
                                                id: item.mediaId,
                                                title: item.mediaType == .movie ? item.title : nil,
                                                name: item.mediaType == .tv ? item.title : nil,
                                                originalTitle: nil,
                                                originalName: nil,
                                                overview: item.overview,
                                                posterPath: item.posterPath,
                                                backdropPath: item.backdropPath,
                                                releaseDate: item.year,
                                                firstAirDate: item.year,
                                                voteAverage: item.voteAverage,
                                                voteCount: nil,
                                                popularity: nil,
                                                genreIds: nil,
                                                mediaType: item.mediaType.rawValue,
                                                adult: nil,
                                                originalLanguage: nil
                                            )
                                            selectedItem = mediaItem
                                            dismiss()
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        isLoading = true
        error = nil
        
        do {
            // Fetch from MDBList: dualipafan01/dreamworks
            allItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: "dualipafan01/dreamworks")
            if allItems.isEmpty {
                error = "No content found in this list."
            }
        } catch {
            self.error = "Failed to load content. Please try again."
            print("DreamWorks error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - DC Studios Sheet
struct DCStudiosSheet: View {
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var allItems: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedTab = 0
    
    private var movies: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .movie }
    }
    
    private var tvShows: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .tv }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                AsyncImage(url: URL(string: "https://cdn.brandfetch.io/idnLU4lJS1/w/313/h/313/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1722965181273")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60)
                    default:
                        EmptyView()
                    }
                }
                .padding(.vertical, 16)
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    let items = selectedTab == 0 ? movies : tvShows
                    
                    if items.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: selectedTab == 0 ? "film" : "tv")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No \(selectedTab == 0 ? "movies" : "TV shows") found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                            ], spacing: 20) {
                                ForEach(items) { item in
                                    SavedMediaPosterCard(item: item)
                                        .onTapGesture {
                                            // Convert SavedMediaItem to MediaItem
                                            let mediaItem = MediaItem(
                                                id: item.mediaId,
                                                title: item.mediaType == .movie ? item.title : nil,
                                                name: item.mediaType == .tv ? item.title : nil,
                                                originalTitle: nil,
                                                originalName: nil,
                                                overview: item.overview,
                                                posterPath: item.posterPath,
                                                backdropPath: item.backdropPath,
                                                releaseDate: item.year,
                                                firstAirDate: item.year,
                                                voteAverage: item.voteAverage,
                                                voteCount: nil,
                                                popularity: nil,
                                                genreIds: nil,
                                                mediaType: item.mediaType.rawValue,
                                                adult: nil,
                                                originalLanguage: nil
                                            )
                                            selectedItem = mediaItem
                                            dismiss()
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        isLoading = true
        error = nil
        
        do {
            // Fetch from MDBList: dualipafan01/dc-studios
            allItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: "dualipafan01/dc-studios")
            if allItems.isEmpty {
                error = "No content found in this list."
            }
        } catch {
            self.error = "Failed to load content. Please try again."
            print("DC Studios error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Universal Pictures Sheet
struct UniversalPicturesSheet: View {
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var allItems: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedTab = 0
    
    private var movies: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .movie }
    }
    
    private var tvShows: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .tv }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                AsyncImage(url: URL(string: "https://cdn.brandfetch.io/id4AnmmNSk/theme/light/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1767628904850")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60)
                    default:
                        EmptyView()
                    }
                }
                .padding(.vertical, 16)
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    let items = selectedTab == 0 ? movies : tvShows
                    
                    if items.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: selectedTab == 0 ? "film" : "tv")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No \(selectedTab == 0 ? "movies" : "TV shows") found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                            ], spacing: 20) {
                                ForEach(items) { item in
                                    SavedMediaPosterCard(item: item)
                                        .onTapGesture {
                                            // Convert SavedMediaItem to MediaItem
                                            let mediaItem = MediaItem(
                                                id: item.mediaId,
                                                title: item.mediaType == .movie ? item.title : nil,
                                                name: item.mediaType == .tv ? item.title : nil,
                                                originalTitle: nil,
                                                originalName: nil,
                                                overview: item.overview,
                                                posterPath: item.posterPath,
                                                backdropPath: item.backdropPath,
                                                releaseDate: item.year,
                                                firstAirDate: item.year,
                                                voteAverage: item.voteAverage,
                                                voteCount: nil,
                                                popularity: nil,
                                                genreIds: nil,
                                                mediaType: item.mediaType.rawValue,
                                                adult: nil,
                                                originalLanguage: nil
                                            )
                                            selectedItem = mediaItem
                                            dismiss()
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        isLoading = true
        error = nil
        
        do {
            // Fetch from MDBList: dualipafan01/universal-pictures
            allItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: "dualipafan01/universal-pictures")
            if allItems.isEmpty {
                error = "No content found in this list."
            }
        } catch {
            self.error = "Failed to load content. Please try again."
            print("Universal Pictures error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Sony Pictures Sheet
struct SonyPicturesSheet: View {
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var allItems: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedTab = 0
    
    private var movies: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .movie }
    }
    
    private var tvShows: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .tv }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                AsyncImage(url: URL(string: "https://cdn.brandfetch.io/idIBgcvFOi/w/400/h/400/theme/dark/icon.jpeg?c=1bxid64Mup7aczewSAYMX&t=1766845823662")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60)
                    default:
                        EmptyView()
                    }
                }
                .padding(.vertical, 16)
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    let items = selectedTab == 0 ? movies : tvShows
                    
                    if items.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: selectedTab == 0 ? "film" : "tv")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No \(selectedTab == 0 ? "movies" : "TV shows") found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                            ], spacing: 20) {
                                ForEach(items) { item in
                                    SavedMediaPosterCard(item: item)
                                        .onTapGesture {
                                            let mediaItem = MediaItem(
                                                id: item.mediaId,
                                                title: item.mediaType == .movie ? item.title : nil,
                                                name: item.mediaType == .tv ? item.title : nil,
                                                originalTitle: nil,
                                                originalName: nil,
                                                overview: item.overview,
                                                posterPath: item.posterPath,
                                                backdropPath: item.backdropPath,
                                                releaseDate: item.year,
                                                firstAirDate: item.year,
                                                voteAverage: item.voteAverage,
                                                voteCount: nil,
                                                popularity: nil,
                                                genreIds: nil,
                                                mediaType: item.mediaType.rawValue,
                                                adult: nil,
                                                originalLanguage: nil
                                            )
                                            selectedItem = mediaItem
                                            dismiss()
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        isLoading = true
        error = nil
        
        do {
            allItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: "dualipafan01/columbia-pictures")
            if allItems.isEmpty {
                error = "No content found in this list."
            }
        } catch {
            self.error = "Failed to load content. Please try again."
            print("Sony Pictures error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Browse Discover Section
struct BrowseDiscoverSection: View {
    var body: some View {
        VStack(spacing: 20) {
            // Section Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Discover")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Explore, analyze, and find your next watch")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            
            // Feature Cards Grid
            VStack(spacing: 14) {
                // Mood Discovery - Hero card
                NavigationLink(destination: MoodDiscoveryView()) {
                    DiscoverFeatureCard(
                        title: "Mood Discovery",
                        subtitle: "Pick your vibe, get curated results",
                        iconName: "sparkles",
                        accentColor: .purple,
                        isLarge: true
                    )
                }
                .buttonStyle(.plain)
                
                HStack(spacing: 14) {
                    NavigationLink(destination: RandomPickView()) {
                        DiscoverFeatureCard(
                            title: "Random Pick",
                            subtitle: "Can't decide? Let us choose",
                            iconName: "dice.fill",
                            accentColor: .orange,
                            isLarge: false
                        )
                    }
                    .buttonStyle(.plain)
                    
                    NavigationLink(destination: CountdownCalendarView()) {
                        DiscoverFeatureCard(
                            title: "Countdown",
                            subtitle: "Upcoming release dates",
                            iconName: "calendar.badge.clock",
                            accentColor: .green,
                            isLarge: false
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                HStack(spacing: 14) {
                    NavigationLink(destination: DecadeExplorerView()) {
                        DiscoverFeatureCard(
                            title: "Time Machine",
                            subtitle: "Explore cinema by decade",
                            iconName: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                            accentColor: .teal,
                            isLarge: false
                        )
                    }
                    .buttonStyle(.plain)
                    
                    NavigationLink(destination: StatsInsightsView()) {
                        DiscoverFeatureCard(
                            title: "My Stats",
                            subtitle: "Your watching insights",
                            iconName: "chart.bar.fill",
                            accentColor: .blue,
                            isLarge: false
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                NavigationLink(destination: AIRecommendView()) {
                    DiscoverFeatureCard(
                        title: "AI Recommendations",
                        subtitle: "Get personalized picks from AI assistants",
                        iconName: "brain.head.profile.fill",
                        accentColor: Color(.systemGray),
                        isLarge: true
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            
            // Quick Stats Row — only observes storage here
            BrowseQuickStatsRow()
            
            // Collections
            if !PopularTMDBCollection.popular.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Collections")
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(PopularTMDBCollection.popular) { collection in
                                NavigationLink(destination: TMDBCollectionSheet(collection: collection)) {
                                    TMDBCollectionTile(collection: collection)
                                        .frame(width: 180)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            
            Spacer(minLength: 40)
        }
        .padding(.top, 8)
    }
}

// MARK: - Quick Stats Row (isolated storage observation)
struct BrowseQuickStatsRow: View {
    @ObservedObject private var storage = StorageService.shared
    
    var body: some View {
        if storage.watched.count > 0 || storage.liked.count > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Glance")
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        QuickStatPill(
                            label: "Watched",
                            value: "\(storage.watched.count)",
                            iconName: "checkmark.circle.fill",
                            color: .green
                        )
                        
                        QuickStatPill(
                            label: "Watchlist",
                            value: "\(storage.wantToWatch.count)",
                            iconName: "bookmark.fill",
                            color: .blue
                        )
                        
                        QuickStatPill(
                            label: "Liked",
                            value: "\(storage.liked.count)",
                            iconName: "heart.fill",
                            color: .red
                        )
                        
                        if storage.customLists.count > 0 {
                            QuickStatPill(
                                label: "Lists",
                                value: "\(storage.customLists.count)",
                                iconName: "folder.fill",
                                color: .purple
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: - For You View Model
@MainActor
class ForYouViewModel: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var errorMessage: String?
    
    private var lastLikedCount: Int = -1
    private var hasLikedItems: Bool {
        !StorageService.shared.liked.isEmpty
    }
    
    func loadIfNeeded() async {
        let liked = StorageService.shared.liked
        guard !liked.isEmpty else {
            items = []
            errorMessage = nil
            hasLoaded = true
            return
        }
        // Only reload if liked list changed or never loaded
        guard !hasLoaded || liked.count != lastLikedCount else { return }
        await load(liked: liked)
    }
    
    func refresh() async {
        let liked = StorageService.shared.liked
        guard !liked.isEmpty else {
            items = []
            errorMessage = nil
            hasLoaded = true
            return
        }
        hasLoaded = false
        await load(liked: liked)
    }
    
    func retry() {
        Task {
            let liked = StorageService.shared.liked
            guard !liked.isEmpty else { return }
            hasLoaded = false
            await load(liked: liked)
        }
    }
    
    private func load(liked: [SavedMediaItem]) async {
        isLoading = true
        errorMessage = nil
        lastLikedCount = liked.count
        
        // Retry up to 2 times on failure
        for attempt in 0..<2 {
            do {
                if attempt > 0 {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1s backoff
                }
                
                let recs = try await AIService.shared.getForYouRecommendations(likedItems: liked)
                
                guard !recs.isEmpty else {
                    continue
                }
                
                // Resolve each recommendation to a MediaItem via TMDB search
                var resolved: [(order: Int, item: MediaItem)] = []
                let likedIds = Set(liked.map { $0.mediaId })
                
                await withTaskGroup(of: (Int, MediaItem?).self) { group in
                    for (index, rec) in recs.prefix(10).enumerated() {
                        group.addTask {
                            do {
                                let results = try await TMDBService.shared.searchMulti(query: rec.title)
                                // Try to match the correct type
                                let preferred = results.results.first(where: {
                                    let mt = $0.resolvedMediaType
                                    return (rec.mediaType == "movie" && mt == .movie) || (rec.mediaType == "tv" && mt == .tv)
                                }) ?? results.results.first
                                
                                if let item = preferred, !likedIds.contains(item.id) {
                                    return (index, item)
                                }
                                return (index, nil)
                            } catch {
                                return (index, nil)
                            }
                        }
                    }
                    
                    for await (index, item) in group {
                        if let item = item {
                            resolved.append((order: index, item: item))
                        }
                    }
                }
                
                // Sort by original order and deduplicate
                let sortedItems = resolved.sorted { $0.order < $1.order }.map { $0.item }
                var seen = Set<Int>()
                let finalItems = sortedItems.filter { item in
                    if seen.contains(item.id) { return false }
                    seen.insert(item.id)
                    return true
                }
                
                if finalItems.isEmpty {
                    continue
                }
                
                items = finalItems
                isLoading = false
                hasLoaded = true
                return
                
            } catch {
                print("For You attempt \(attempt + 1) error: \(error)")
            }
        }
        
        // Both attempts failed
        if items.isEmpty {
            errorMessage = "Couldn't load recommendations"
        }
        isLoading = false
        hasLoaded = true
    }
}

// MARK: - For You Row
struct ForYouRow: View {
    @ObservedObject var viewModel: ForYouViewModel
    let onItemTap: (MediaItem) -> Void
    
    var body: some View {
        if viewModel.isLoading {
            ForYouLoadingRow()
        } else if !viewModel.items.isEmpty {
            MediaRowView(
                title: "For You",
                items: viewModel.items,
                onItemTap: onItemTap
            )
        } else if let error = viewModel.errorMessage {
            ForYouErrorRow(message: error) {
                viewModel.retry()
            }
        }
    }
}

// MARK: - For You Error / Retry Row
private struct ForYouErrorRow: View {
    let message: String
    let onRetry: () -> Void
    @State private var isPressed = false
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("For You")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.5)) {
                    rotationAngle += 360
                }
                onRetry()
            }) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .rotationEffect(.degrees(rotationAngle))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Couldn't load picks")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("Tap to refresh")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Color.secondary.opacity(0.5))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            .padding(.horizontal)
        }
    }
}

// MARK: - For You Loading Placeholder
private struct ForYouLoadingRow: View {
    @State private var shimmer = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("For You")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                            .frame(width: 130, height: 195)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, Color(.systemGray4).opacity(0.4), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .offset(x: shimmer ? 200 : -200)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
    }
}

// MARK: - Browse View Model
@MainActor
class BrowseViewModel: ObservableObject {
    @Published var heroItems: [MediaItem] = []
    @Published var rows: [MediaRow] = []
    @Published var networkHubs: [NetworkHub] = []
    @Published var isLoading = false
    
    struct MediaRow {
        let title: String
        let items: [MediaItem]
        let people: [Person]
    }
    
    func loadContent() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        
        // Load network hubs (streaming services)
        networkHubs = StorageService.shared.getEnabledNetworkHubs()
        
        // Load hero items based on user's selected source (concurrently)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadHeroItems() }
            group.addTask { await self.loadBrowseRows() }
        }
    }
    
    private func loadHeroItems() async {
        let source = StorageService.shared.settings.heroCarouselSource
        
        do {
            let items: [MediaItem]
            switch source {
            case .trendingMovies, .mdblistTrending:
                items = try await TMDBService.shared.getTrending(mediaType: .movie, timeWindow: "day").results
            case .trendingTV:
                items = try await TMDBService.shared.getTrending(mediaType: .tv, timeWindow: "day").results
            case .popularMovies:
                items = try await TMDBService.shared.getPopularMovies().results
            case .popularTV:
                items = try await TMDBService.shared.getPopularTV().results
            case .nowPlayingMovies:
                items = try await TMDBService.shared.getNowPlayingMovies().results
            case .topRatedMovies:
                items = try await TMDBService.shared.getTopRatedMovies().results
            case .upcomingMovies:
                items = try await TMDBService.shared.getUpcomingMovies().results
            }
            heroItems = Array(items.prefix(10))
            
            // Prefetch hero backdrop images
            ImagePrefetchService.shared.prefetchBackdrops(for: heroItems, size: .backdrop)
        } catch {
            print("Error loading hero: \(error)")
        }
    }
    
    func refresh() async {
        // Wait for any in-flight load to finish to avoid clearing data mid-load
        while isLoading {
            try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s
        }

        rows = []
        heroItems = []
        networkHubs = []
        await loadContent()
    }
    
    private func loadBrowseRows() async {
        var configs = StorageService.shared.browseRows.filter { $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
        
        // If no enabled configs, use defaults
        if configs.isEmpty {
            configs = BrowseRowConfig.defaultRows.filter { $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
        }
        
        var loadedRows: [(Int, MediaRow)] = []
        
        await withTaskGroup(of: (Int, MediaRow?).self) { group in
            for (index, config) in configs.enumerated() {
                group.addTask {
                    do {
                        let row = try await self.fetchRow(config)
                        return (index, row)
                    } catch {
                        print("Error loading \(config.title): \(error)")
                        return (index, nil)
                    }
                }
            }
            
            for await result in group {
                if let row = result.1 {
                    loadedRows.append((result.0, row))
                }
            }
        }
        
        // Sort by original order and extract rows
        rows = loadedRows.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
    }
    
    private func fetchRow(_ config: BrowseRowConfig) async throws -> MediaRow {
        let row: MediaRow
        switch config.endpoint {
        case .trendingMovies:
            let items = try await TMDBService.shared.getTrending(mediaType: .movie, timeWindow: "day").results
            row = MediaRow(title: config.title, items: items, people: [])
        case .trendingTV:
            let items = try await TMDBService.shared.getTrending(mediaType: .tv, timeWindow: "day").results
            row = MediaRow(title: config.title, items: items, people: [])
        case .trendingPeople:
            let people = try await TMDBService.shared.getTrendingPeople(timeWindow: "week").results
            row = MediaRow(title: config.title, items: [], people: people)
        case .popularMovies:
            let items = try await TMDBService.shared.getPopularMovies().results
            row = MediaRow(title: config.title, items: items, people: [])
        case .popularTV:
            let items = try await TMDBService.shared.getPopularTV().results
            row = MediaRow(title: config.title, items: items, people: [])
        case .topRatedMovies:
            let items = try await TMDBService.shared.getTopRatedMovies().results
            row = MediaRow(title: config.title, items: items, people: [])
        case .topRatedTV:
            let items = try await TMDBService.shared.getTopRatedTV().results
            row = MediaRow(title: config.title, items: items, people: [])
        case .nowPlayingMovies:
            let items = try await TMDBService.shared.getNowPlayingMovies().results
            row = MediaRow(title: config.title, items: items, people: [])
        case .airingTodayTV:
            let items = try await TMDBService.shared.getAiringTodayTV().results
            row = MediaRow(title: config.title, items: items, people: [])
        case .upcomingMovies:
            let items = try await TMDBService.shared.getUpcomingMovies().results
            row = MediaRow(title: config.title, items: items, people: [])
        case .onTheAirTV:
            let items = try await TMDBService.shared.getOnTheAirTV().results
            row = MediaRow(title: config.title, items: items, people: [])
        }
        
        // Prefetch poster images for the row
        if !row.items.isEmpty {
            ImagePrefetchService.shared.prefetchPosters(for: row.items)
        }
        
        return row
    }
}

// MARK: - Network Hubs Row (Streaming Services)
struct NetworkHubsRow: View {
    let hubs: [NetworkHub]
    let onHubTap: (NetworkHub) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(hubs) { hub in
                    NetworkHubCard(hub: hub)
                        .onTapGesture {
                            onHubTap(hub)
                        }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct NetworkHubCard: View {
    let hub: NetworkHub
    @State private var isPressed = false
    
    private var brandColor: Color {
        switch hub.name {
        case "Disney+": return Color(red: 0x13/255, green: 0x68/255, blue: 0x78/255)
        case "Netflix": return Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255)
        case "Showmax": return Color(red: 0xDD/255, green: 0x00/255, blue: 0x4F/255)
        case "Max": return Color(red: 0x03/255, green: 0x03/255, blue: 0x28/255)
        case "Peacock": return Color(red: 0x06/255, green: 0x9D/255, blue: 0xE0/255)
        case "Paramount+": return Color(red: 0x00/255, green: 0x59/255, blue: 0xF1/255)
        case "Disney Channel": return Color(red: 0x00/255, green: 0x89/255, blue: 0xE2/255)
        default: return Color(.systemGray3)
        }
    }
    
    var body: some View {
        Text(hub.name)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: 80)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(brandColor)
            )
            .shadow(color: brandColor.opacity(0.35), radius: isPressed ? 2 : 5, y: isPressed ? 1 : 3)
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
    }
}

extension NetworkHub {
    var companyIdsIfKnown: [Int] {
        switch name {
        case "Disney Channel":
            // TMDB company id for Disney Channel
            return [2739]
        default:
            return []
        }
    }
}

// MARK: - Network Hub Sheet
struct NetworkHubSheet: View {
    let hub: NetworkHub
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var movies: [MediaItem] = []
    @State private var tvShows: [MediaItem] = []
    @State private var isLoading = true
    @State private var selectedTab = 0
    
    // In-hub logo URLs (transparent background SVG logos)
    private var inHubLogoURL: String {
        switch hub.name {
        case "Disney+":
            return "https://cdn.brandfetch.io/idhQlYRiX2/theme/light/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1769147818509"
        case "Netflix":
            return "https://cdn.brandfetch.io/ideQwN5lBE/theme/light/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1741362568562"
        case "Showmax":
            return "https://cdn.brandfetch.io/id_ej-GSqX/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1712822097790"
        case "Max":
            return "https://cdn.brandfetch.io/idKKo6p4ks/theme/light/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1719475129913"
        case "Peacock":
            return "https://cdn.brandfetch.io/idIaTUzyS6/theme/light/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1764405218440"
        case "Paramount+":
            return "https://cdn.brandfetch.io/idU9biO3N_/theme/light/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1758268970538"
        case "Disney Channel":
            return "https://cdn.brandfetch.io/idrq2iCmCC/w/300/h/126/theme/light/logo.png?c=1bxid64Mup7aczewSAYMX&t=1769179360009"
        default:
            return hub.logoURL ?? ""
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with logo
                if let url = URL(string: inHubLogoURL), !inHubLogoURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 40)
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV Shows").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)
                        ], spacing: 20) {
                            let items = selectedTab == 0 ? movies : tvShows
                            ForEach(items) { item in
                                MediaPosterCard(item: item)
                                    .onTapGesture {
                                        selectedItem = item
                                        dismiss()
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        await MainActor.run { isLoading = true }
        
        var region = StorageService.shared.settings.region
        
        // Special handling for South Africa Disney+ (mirrors UK content)
        if region == "ZA" && hub.name == "Disney+" {
            region = "GB"
        }
        
        // Skip Disney Channel since it requires MDBList (removed)
        if hub.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "disney channel" {
            await MainActor.run {
                self.movies = []
                self.tvShows = []
                self.isLoading = false
            }
            return
        }
        
        // Load movies: try provider-based first; fallback to empty if no providers
        do {
            if !hub.providerIds.isEmpty {
                let response = try await TMDBService.shared.discoverMoviesWithProvider(
                    providerIds: hub.providerIds,
                    region: region
                )
                await MainActor.run { movies = response.results }
            } else {
                await MainActor.run { movies = [] }
            }
        } catch {
            print("Error loading movies: \(error)")
        }
        
        // Load TV: try provider-based first; fallback to empty if no providers
        do {
            if !hub.providerIds.isEmpty {
                let response = try await TMDBService.shared.discoverTVWithProvider(
                    providerIds: hub.providerIds,
                    region: region
                )
                await MainActor.run { tvShows = response.results }
            } else {
                await MainActor.run { tvShows = [] }
            }
        } catch {
            print("Error loading TV: \(error)")
        }
        
        await MainActor.run { isLoading = false }
    }
}





// MARK: - Browse Customize Sheet (Legacy - kept for backwards compatibility)
struct BrowseCustomizeSheet: View {
    @ObservedObject private var storage = StorageService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var browseRows: [BrowseRowConfig] = []
    @State private var networkHubs: [NetworkHub] = []
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Networks Section - only show available in user's region
                Section {
                    ForEach($networkHubs.filter { storage.settings.region.isEmpty || $0.wrappedValue.regions.contains(storage.settings.region) }) { $hub in
                        HStack {
                            if let logoURL = hub.logoURL, let url = URL(string: logoURL) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .renderingMode(.template)
                                            .foregroundStyle(colorScheme == .light ? .black : .white)
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 50, height: 24)
                                    default:
                                        Text(hub.name)
                                            .fontWeight(.medium)
                                    }
                                }
                            } else {
                                Text(hub.name)
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $hub.isEnabled)
                                .labelsHidden()
                        }
                        .listRowBackground(
                            isIPad ? AnyView(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)) : AnyView(Color.clear)
                        )
                    }
                    .onMove { from, to in
                        networkHubs.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("Networks (Available in \(regionName))")
                } footer: {
                    Text("Drag to reorder, toggle to show/hide. Only services available in your region are shown.")
                }
                
                // Browse Rows Section
                Section {
                    ForEach($browseRows) { $row in
                        HStack {
                            Text(row.title)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Toggle("", isOn: $row.isEnabled)
                                .labelsHidden()
                        }
                        .listRowBackground(
                            isIPad ? AnyView(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)) : AnyView(Color.clear)
                        )
                    }
                    .onMove { from, to in
                        browseRows.move(fromOffsets: from, toOffset: to)
                        updateSortOrder()
                    }
                } header: {
                    Text("Content Rows")
                } footer: {
                    Text("Drag to reorder, toggle to show/hide")
                }
            }
            .scrollContentBackground(isIPad ? .hidden : .automatic)
            .background {
                if isIPad {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                }
            }
            .navigationTitle("Customize Browse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
            .onAppear {
                browseRows = storage.browseRows.sorted { $0.sortOrder < $1.sortOrder }
                networkHubs = storage.networkHubs.sorted { $0.sortOrder < $1.sortOrder }
            }
        }
    }
    
    private var regionName: String {
        let region = storage.settings.region
        let regionNames: [String: String] = [
            "US": "United States",
            "GB": "United Kingdom",
            "CA": "Canada",
            "AU": "Australia",
            "ZA": "South Africa",
            "DE": "Germany",
            "FR": "France",
            "JP": "Japan",
            "KR": "South Korea",
            "IN": "India",
            "BR": "Brazil",
            "NZ": "New Zealand",
            "NG": "Nigeria",
            "KE": "Kenya"
        ]
        return regionNames[region] ?? region
    }
    
    private func updateSortOrder() {
        for (index, _) in browseRows.enumerated() {
            browseRows[index].sortOrder = index
        }
    }
    
    private func saveChanges() {
        // Save browse rows
        var updatedRows = browseRows
        for (index, _) in updatedRows.enumerated() {
            updatedRows[index].sortOrder = index
        }
        storage.updateBrowseRows(updatedRows)
        
        // Save network hubs
        storage.reorderNetworkHubs(networkHubs)
    }
}

#Preview {
    BrowseView(selectedItem: .constant(nil))
}

