//
//  BrowseView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Hub Sheet Enums

enum StudioSheet: String, Identifiable {
    case marvel, pixar, dc, waltDisney
    case warnerBros, universal, sonyPictures, columbia
    case paramountPictures, dreamworks, illumination
    case searchlight, skydance, happyMadison
    var id: String { rawValue }
}

enum StreamingSheet: String, Identifiable {
    case netflix, disneyPlus, hboMax, paramountPlus, appleTVPlus, peacock
    var id: String { rawValue }
}

struct BrowseView: View {
    @StateObject private var viewModel = BrowseViewModel()
    @StateObject private var forYouVM = ForYouViewModel()
    @Binding var selectedItem: MediaItem?
    @State private var selectedNetworkHub: NetworkHub?
    @State private var selectedCompanyHub: CompanyHub?
    @State private var activeStudioSheet: StudioSheet?
    @State private var activeStreamingSheet: StreamingSheet?
    @State private var showCustomizeSheet = false
    @State private var showSettingsSheet = false
    @State private var showSettingsPage = false
    @State private var selectedPerson: Person?
    @State private var selectedJSONHub: CustomJSONHub?
    @State private var seeAllRow: BrowseContentRow?
    @State private var dailyPickCache: DailyPickCache?
    @State private var isDailyPickHidden = false
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var profileService = ProfileService.shared
    @ObservedObject private var watchHour = WatchHourService.shared
    @ObservedObject private var storage = StorageService.shared
    
    private var isKidsProfile: Bool {
        StorageService.shared.settings.isKidsProfile
    }

    /// Inset above the hero on a phone.
    ///
    /// The cinematic stage ignores the top safe area so it can bleed behind the
    /// navigation bar, which on a phone started the artwork hard against the
    /// Dynamic Island and left the whole page — hero, partnership line and every
    /// row below — sitting too high. Restoring roughly the status bar's height
    /// drops the page back down without giving up the bleed: the artwork still
    /// runs under the bar, it just no longer begins at the very top pixel.
    ///
    /// Compact widths only; on iPad and Mac the stage is wide enough that the
    /// flush top edge reads the way it was designed to.
    private var heroTopInset: CGFloat {
        #if os(iOS)
        guard heroBleedsUnderNavigationBar else { return 16 }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let window, window.bounds.width < 520 else { return 0 }
        return max(window.safeAreaInsets.top, 20)
        #else
        return heroBleedsUnderNavigationBar ? 0 : 16
        #endif
    }

    /// Whether the hero should run all the way up behind the navigation bar to
    /// the top of the window.
    ///
    /// Only the cinematic style: it is edge-to-edge and fades out along its top
    /// edge, so it has something to blend into the bar with. The classic style is
    /// a framed card and would simply be clipped by the bar instead.
    private var heroBleedsUnderNavigationBar: Bool {
        !viewModel.heroItems.isEmpty
            && (profileService.activeProfile?.heroCarouselStyle ?? .cinematic) == .cinematic
    }

    @Environment(\.horizontalSizeClass) private var browseSizeClass
    private var horizontalSizeClassIsCompact: Bool { browseSizeClass != .regular }

    /// Posters for the Tonight invitation: the first few trending picks that
    /// aren't already in the hero, so the card doesn't repeat what's above it.
    private var tonightInvitePosters: [MediaItem] {
        let heroIDs = Set(viewModel.heroItems.map(\.id))
        return viewModel.rows.flatMap(\.items)
            .filter { $0.posterPath != nil && !heroIDs.contains($0.id) }
            .prefix(3)
            .map { $0 }
    }

    /// True only for adult (18+) profiles — Scout AI and related features require this
    private var isAdultProfile: Bool {
        !ScoutAgeGateManager.shared.isScoutHidden
    }

    private enum DailyPickSource: String, Codable {
        case forYou
        case hero
        case row
        case unknown
    }

    private struct DailyPickCache: Codable {
        let item: MediaItem
        let source: DailyPickSource
    }

    private let dailyPickDateKey = "daily_pick_date"
    private let dailyPickItemKey = "daily_pick_item"
    private let dailyPickHiddenDateKey = "daily_pick_hidden_date"
    
    /// Ordered sections from StorageService
    private var orderedSections: [BrowseSectionItem] {
        StorageService.shared.getOrderedEnabledSections()
    }

    private var productionCompanies: [ProductionCompanyEntry] {
        StorageService.shared.getEnabledCompanyHubs().map { hub in
            ProductionCompanyEntry(
                hub: hub,
                logoURL: hub.logoPath ?? Self.defaultStudioLogosByName[hub.name]
            )
        }
    }

    private static let defaultStudioLogosByName: [String: String] = [
        "Paramount Pictures": "https://cdn.brandfetch.io/idrAEeTLeo/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1757576972155",
        "Walt Disney Pictures": "https://cdn.brandfetch.io/idxASqzkm_/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1675929043591",
        "20th Century Studios": "https://cdn.brandfetch.io/id80eyhRc1/w/820/h/683/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1667562091650",
        "Warner Bros.": "https://cdn.brandfetch.io/idxBWIwtz0/w/405/h/396/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1768344714851",
        "Pixar": "https://cdn.brandfetch.io/idYVybSjsA/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1764458646138",
        "Universal Pictures": "https://cdn.brandfetch.io/id4AnmmNSk/theme/light/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1767628904850",
        "Sony Pictures": "https://cdn.brandfetch.io/idIBgcvFOi/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1766845823465",
        "Metro-Goldwyn-Mayer": "https://cdn.brandfetch.io/idLI5gJfl8/w/161/h/86/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1667810266726",
        "Lionsgate Films": "https://upload.wikimedia.org/wikipedia/commons/thumb/9/95/Lionsgate_2025.svg/500px-Lionsgate_2025.svg.png",
        "A24": "https://cdn.brandfetch.io/idHlMmIC6s/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1748302432792",
        "DreamWorks": "https://cdn.brandfetch.io/idj7QnEvUG/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1764869429974",
        "Blumhouse Productions": "https://cdn.brandfetch.io/idMdr695hi/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1767230760280",
        "Happy Madison Productions": "https://upload.wikimedia.org/wikipedia/commons/4/4f/Happy-Madison-Productions-logo.png",
        "Amblin Entertainment": "https://upload.wikimedia.org/wikipedia/en/1/16/Amblin_Entertainment_%28Print%29.svg"
    ]
    
    var body: some View {
        #if os(tvOS)
        // tvOS: no inner NavigationStack — ContentView already provides one.
        // Clean StreamQ-style layout: hero + rows + studios.
        tvOSBrowseBody
        #else
        NavigationStack {
            browseBody
        }
        #endif
    }

    // MARK: - tvOS Browse Body (StreamQ-style)
    #if os(tvOS)
    private var tvOSBrowseBody: some View {
        NavigationStack {
            tvOSScrollContent
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $activeStudioSheet) { studio in
                    studioSheetContent(for: studio)
                        .toolbar(.hidden, for: .tabBar)
                }
                .navigationDestination(item: $activeStreamingSheet) { service in
                    streamingSheetContent(for: service)
                        .toolbar(.hidden, for: .tabBar)
                }
        }
    }

    private var tvOSScrollContent: some View {
        ScrollView {
            VStack(spacing: 40) {
                if viewModel.heroItems.isEmpty && viewModel.rows.isEmpty {
                    ProgressView()
                        .padding(.top, 40)
                } else {
                    // Hero carousel
                    if !viewModel.heroItems.isEmpty {
                        ResizableHeroCarousel(
                            items: viewModel.heroItems,
                            onItemTap: { item in
                                selectedItem = item
                            },
                            tabID: "0"
                        )
                        .focusSection()
                    }

                    // Partnership banner
                    HStack(spacing: 8) {
                        Text("In Partnership with")
                            .font(.footnote)
                            .foregroundStyle(.primary)

                        Image("NordVPNLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal)

                    // Content rows (media rows from BrowseViewModel)
                    ForEach(Array(viewModel.rows.enumerated()), id: \.element.title) { _, row in
                        if !row.people.isEmpty {
                            PeopleRowView(
                                title: row.title,
                                people: row.people,
                                onPersonTap: { person in
                                    selectedPerson = person
                                }, onSeeAll: nil
                            )
                        } else if !row.items.isEmpty {
                            MediaRowView(
                                title: row.title,
                                items: row.items,
                                onItemTap: { item in
                                    selectedItem = item
                                },
                                onSeeAll: { seeAllRow = row }
                            )
                        }
                    }

                    // Studios row
                    StudiosHubRow(onStudioTap: { activeStudioSheet = $0 })

                    // Streaming services row
                    StreamingServicesRow(onServiceTap: { activeStreamingSheet = $0 })
                }
            }
            // A strip of page above the content for the tab bar to occupy —
            // needed only when the hero isn't there to run up behind the bar
            // itself.
            .padding(.top, heroBleedsUnderNavigationBar ? 0 : 40)
            .padding(.bottom)
        }
        // Let the cinematic hero run up behind the tab bar to the top edge of
        // the screen, the way a hero on a television is supposed to: the bar
        // floats on the artwork rather than sitting on a black shelf above it.
        // The stage's own top scrim is what keeps the bar's labels legible. An
        // empty edge set is a no-op, so this stays a value change rather than a
        // branch in view identity.
        .ignoresSafeArea(.container, edges: heroBleedsUnderNavigationBar ? .top : [])
        .task {
            await viewModel.loadContent()
        }
        .onAppear {
            if viewModel.heroItems.isEmpty {
                Task { await viewModel.refresh() }
            }
        }
        .sheet(item: $selectedCompanyHub) { hub in
            CompanyHubSheet(companyHub: hub, selectedItem: $selectedItem)
        }
        .sheet(item: $selectedPerson) { person in
            PersonDetailView(
                personId: person.id,
                personName: person.name,
                profilePath: person.profilePath
            )
        }
        .sheet(item: $seeAllRow) { row in
            SeeAllView(title: row.title, items: row.items)
        }
        .onChange(of: StorageService.shared.settings.heroCarouselSource) { _, _ in
            viewModel.scheduleRefresh()
        }
        .onChange(of: authService.isAuthenticated) { _, _ in
            viewModel.scheduleRefresh()
        }
        .onChange(of: StorageService.shared.settings.isKidsProfile) { _, _ in
            viewModel.scheduleRefresh()
        }
    }
    #endif

    // MARK: - Non-tvOS Browse Body
    #if !os(tvOS)
    private var browseBody: some View {
        PopcornRefreshableScrollView {
            await viewModel.refresh()
            await forYouVM.refresh()
        } content: {
            browseScrollContent
        }
        // Let the scroll content start at the true top of the window rather than
        // below the navigation bar, and drop the bar's own background so the
        // hero artwork is what shows through it. An empty edge set is a no-op,
        // which keeps this a value change rather than a branch in view identity.
        .ignoresSafeArea(.container, edges: heroBleedsUnderNavigationBar ? .top : [])
        .background(alignment: .top) {
            TopArtworkGlow(path: viewModel.heroItems.first?.posterPath)
        }
        .toolbarBackgroundVisibility(
            heroBleedsUnderNavigationBar ? .hidden : .automatic,
            for: .navigationBar
        )
        .task {
            await viewModel.loadContent()
            await forYouVM.loadIfNeeded()
            updateDailyPickIfNeeded()
        }
        .onAppear {
            if viewModel.heroItems.isEmpty {
                Task { await viewModel.refresh() }
            }
        }
        .toolbar { browseToolbarContent }
        #if os(macOS)
        .navigationDestination(isPresented: $showSettingsPage) {
            SettingsView()
        }
        #endif
        .sheet(item: $selectedNetworkHub) { hub in
            NetworkHubSheet(hub: hub, selectedItem: $selectedItem)
        }
        .navigationDestination(item: $activeStudioSheet) { studio in
            studioSheetContent(for: studio)
                #if !os(macOS)
                .toolbar(.hidden, for: .tabBar)
                #endif
        }
        .navigationDestination(item: $activeStreamingSheet) { service in
            streamingSheetContent(for: service)
                #if !os(macOS)
                .toolbar(.hidden, for: .tabBar)
                #endif
        }
        .sheet(item: $selectedCompanyHub) { hub in
            CompanyHubSheet(companyHub: hub, selectedItem: $selectedItem)
        }
        .sheet(item: $selectedJSONHub) { hub in
            CustomJSONHubSheet(hub: hub, selectedItem: $selectedItem)
        }
        .sheet(isPresented: $showCustomizeSheet) {
            HomeCustomizationView()
        }
        #if os(iOS)
        .sheet(isPresented: $showSettingsSheet) {
            NavigationStack {
                SettingsView()
            }
        }
        #endif
        .onChange(of: StorageService.shared.settings.heroCarouselSource) { _, _ in
            viewModel.scheduleRefresh()
        }
        .onChange(of: authService.isAuthenticated) { _, _ in
            viewModel.scheduleRefresh()
        }
        .onChange(of: StorageService.shared.settings.isKidsProfile) { _, _ in
            viewModel.scheduleRefresh()
        }
        .onChange(of: viewModel.heroItems) { _, _ in
            updateDailyPickIfNeeded()
        }
        .onChange(of: forYouVM.items) { _, _ in
            updateDailyPickIfNeeded()
        }
        .sheet(item: $selectedPerson) { person in
            PersonDetailView(
                personId: person.id,
                personName: person.name,
                profilePath: person.profilePath
            )
        }
        .sheet(item: $seeAllRow) { row in
            SeeAllView(title: row.title, items: row.items)
        }
    }
    #endif

    // MARK: - Extracted Sub-Views
    
    private var browseContentSpacing: CGFloat {
        #if os(tvOS)
        40
        #else
        24
        #endif
    }

    private var browseScrollContent: some View {
        LazyVStack(spacing: browseContentSpacing) {
            if viewModel.heroItems.isEmpty && viewModel.rows.isEmpty {
                // Loading state matching StreamQ
                ProgressView()
                    .padding(.top, 40)
            } else {
                if !viewModel.heroItems.isEmpty {
                    ResizableHeroCarousel(
                        items: viewModel.heroItems,
                        onItemTap: { item in
                            selectedItem = item
                        },
                        tabID: "0"
                    )
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
                
                // Partnership banner
                #if os(iOS)
                Link(destination: URL(string: "https://go.nordvpn.net/aff_c?offer_id=15&aff_id=147783&url_id=902")!) {
                    HStack(spacing: 8) {
                        Text("In Partnership with")
                            .font(.footnote)
                            .foregroundColor(Color(.label))
                        
                        Image("NordVPNLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .padding(.horizontal)
                #else
                HStack(spacing: 8) {
                    Text("In Partnership with")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                    
                    Image("NordVPNLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 20)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal)
                #endif

                // For You sits directly under the partnership banner.
                if authService.isAuthenticated, isAdultProfile {
                    ForYouRow(viewModel: forYouVM) { item in
                        selectedItem = item
                    }
                }
                
                #if os(iOS)
                if horizontalSizeClassIsCompact, !isKidsProfile {
                    TonightInviteCard(posters: tonightInvitePosters)
                        .padding(.horizontal)
                }
                RecentStubsRow()
                #endif

                ForEach(orderedSections) { section in
                    browseSectionView(for: section)
                }
            }
        }
        // See `heroTopInset`: flush with the top of the window everywhere the
        // stage is wide, and dropped by the status bar's height on a phone.
        .padding(.top, heroTopInset)
        .padding(.bottom)
    }
    
    @ViewBuilder
    private func browseSectionView(for section: BrowseSectionItem) -> some View {
        switch section.sectionType {
        case .networks:
            EmptyView()
        case .rows:
            browseRowsSection
        case .studios:
            StudiosHubRow(onStudioTap: { activeStudioSheet = $0 })
        case .customHubs:
            customHubsSection
        case .forYou:
            // Rendered directly below the hero carousel instead.
            EmptyView()
        case .discover:
            if isAdultProfile {
                BrowseDiscoverSection()
            } else {
                EmptyView()
            }
        case .continueWatching:
            // Continue Watching is now rendered inline with rows (between Trending Movies and Trending TV Shows)
            EmptyView()
        case .streaming:
            StreamingServicesRow(onServiceTap: { activeStreamingSheet = $0 })
        }
    }

    @ViewBuilder
    private var browseContinueWatchingSection: some View {
        let inProgress = storage.continueWatching.filter { $0.status == .inProgress }
        let activeSessions = watchHour.activeSessions
        let heldSessions = watchHour.onHoldSessions

        if !activeSessions.isEmpty || !heldSessions.isEmpty || !inProgress.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                // Watching Now
                if !activeSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Watching Now", systemImage: "play.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Color(hex: "FF375F"))
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(activeSessions) { session in
                                    ActiveSessionCard(session: session, accent: Color(hex: "FF375F"))
                                        .frame(width: 300)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                // On Hold
                if !heldSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("On Hold", systemImage: "pause.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(heldSessions) { session in
                                    HeldSessionCard(session: session, accent: Color(hex: "FF375F"))
                                        .frame(width: 260)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                // Continue Watching - Apple TV style
                if !inProgress.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Continue Watching")
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(inProgress) { item in
                                    #if os(tvOS)
                                    FocusableActionSurface(action: {
                                        selectedItem = item.show.toMediaItem()
                                    }) {
                                        AppleTVContinueWatchingCard(item: item)
                                            .frame(width: 240, height: 135)
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
                                        AppleTVContinueWatchingCard(item: item)
                                            .frame(width: 240, height: 135)
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
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        } else {
            EmptyView()
        }
    }
    
    /// Endpoints that use the cinematic featured backdrop style (Disney+ inspired)
    private static let featuredEndpoints: Set<BrowseRowConfig.BrowseEndpoint> = [
        .nowPlayingMovies, .airingTodayTV
    ]

     private var browseRowsSection: some View {
         ForEach(Array(viewModel.rows.enumerated()), id: \.element.title) { index, row in
             if !row.people.isEmpty {
                 PeopleRowView(
                     title: row.title,
                     people: row.people,
                     onPersonTap: { person in
                         selectedPerson = person
                     }, onSeeAll: nil
                 )
             } else if !row.items.isEmpty {
                 let useFeatured = row.endpoint.map { Self.featuredEndpoints.contains($0) } ?? false
                 MediaRowView(
                     title: row.title,
                     items: row.items,
                     onItemTap: { item in
                         selectedItem = item
                     },
                     onSeeAll: { seeAllRow = row },
                     rowStyle: useFeatured ? .featured : .standard
                 )
             } else {
                 EmptyView()
             }
             
             // Insert Continue Watching between Trending Movies and Trending TV Shows
             if row.title.lowercased().contains("trending") && row.title.lowercased().contains("movie") {
                 browseContinueWatchingSection
             }
         }
     }

    @ViewBuilder
    private var customHubsSection: some View {
        if !isKidsProfile {
            let enabledHubs = StorageService.shared.getEnabledCustomJSONHubs()
            if !enabledHubs.isEmpty {
                CustomJSONHubsRow(hubs: enabledHubs) { hub in
                    selectedJSONHub = hub
                }
            }
        }
    }
    
    @ToolbarContentBuilder
    private var browseToolbarContent: some ToolbarContent {
        #if os(tvOS)
        // tvOS: no toolbar buttons — clean layout like StreamQ
        ToolbarItem(placement: .primaryAction) {
            EmptyView()
        }
        #elseif os(iOS)
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 12) {
                Button {
                    showCustomizeSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }

                Button {
                    showSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
            }
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 12) {
                Button {
                    showCustomizeSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                
                Button {
                    showSettingsPage = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
            }
        }
        #endif
    }
    
    @ViewBuilder
    private func studioSheetContent(for studio: StudioSheet) -> some View {
        switch studio {
        case .marvel: MarvelHubView()
        case .pixar: PixarHubView()
        case .dc: DCHubView()
        case .waltDisney: WaltDisneyHubView()
        case .warnerBros: WarnerBrosHubView()
        case .universal: UniversalHubView()
        case .sonyPictures: SonyPicturesHubView()
        case .columbia: ColumbiaHubView()
        case .paramountPictures: ParamountPicturesHubView()
        case .dreamworks: DreamWorksHubView()
        case .illumination: IlluminationHubView()
        case .searchlight: SearchlightHubView()
        case .skydance: SkydanceHubView()
        case .happyMadison: HappyMadisonHubView()
        }
    }
    
    @ViewBuilder
    private func streamingSheetContent(for service: StreamingSheet) -> some View {
        switch service {
        case .netflix: NetflixHubView()
        case .disneyPlus: DisneyPlusHubView()
        case .hboMax: HBOMaxHubView()
        case .paramountPlus: ParamountPlusHubView()
        case .appleTVPlus: AppleTVPlusHubView()
        case .peacock: PeacockHubView()
        }
    }

    private func updateDailyPickIfNeeded() {
        let today = dayString(Date())
        let hiddenDate = UserDefaults.standard.string(forKey: dailyPickHiddenDateKey)
        isDailyPickHidden = hiddenDate == today

        guard !isDailyPickHidden else {
            dailyPickCache = nil
            return
        }

        if let cachedDate = UserDefaults.standard.string(forKey: dailyPickDateKey),
           cachedDate == today,
           let data = UserDefaults.standard.data(forKey: dailyPickItemKey),
           let cached = try? JSONDecoder().decode(DailyPickCache.self, from: data) {
            dailyPickCache = cached
            return
        }

        if let picked = pickDailyCandidate() {
            dailyPickCache = picked
            if let data = try? JSONEncoder().encode(picked) {
                UserDefaults.standard.set(today, forKey: dailyPickDateKey)
                UserDefaults.standard.set(data, forKey: dailyPickItemKey)
            }
        } else {
            dailyPickCache = nil
        }
    }

    private func pickDailyCandidate() -> DailyPickCache? {
        if let item = firstEligibleItem(from: forYouVM.items) {
            return DailyPickCache(item: item, source: .forYou)
        }
        if let item = firstEligibleItem(from: viewModel.heroItems) {
            return DailyPickCache(item: item, source: .hero)
        }
        for row in viewModel.rows {
            if let item = firstEligibleItem(from: row.items) {
                return DailyPickCache(item: item, source: .row)
            }
        }
        return nil
    }

    private func firstEligibleItem(from items: [MediaItem]) -> MediaItem? {
        items.first(where: { item in
            guard item.resolvedMediaType != .person else { return false }
            if isKidsProfile, item.adult == true { return false }
            return true
        })
    }

    private func dailyPickReason(for source: DailyPickSource) -> String {
        switch source {
        case .forYou:
            return "Based on what you've liked"
        case .hero:
            return "Trending right now"
        case .row:
            return "Popular on your home feed"
        case .unknown:
            return "A quick pick for today"
        }
    }

    private func dismissDailyPickForToday() {
        let today = dayString(Date())
        UserDefaults.standard.set(today, forKey: dailyPickHiddenDateKey)
        isDailyPickHidden = true
        dailyPickCache = nil
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Daily Pick Card
private struct DailyPickCard: View {
    let item: MediaItem
    let reason: String
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Pick")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Not today") {
                    onDismiss()
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
            }

            Button {
                onTap()
            } label: {
                HStack(spacing: 10) {
                    DailyPickPoster(item: item)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayTitle)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let year = item.year {
                            Text(year)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("Open")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Color.secondary.opacity(0.6))
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.gray.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.gray.opacity(0.35).opacity(0.3), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 2)
    }
}

private struct DailyPickPoster: View {
    let item: MediaItem

    var body: some View {
        let posterURL = TMDBService.shared.imageURL(path: item.posterPath, size: .medium)
        AsyncImage(url: posterURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty:
                Rectangle()
                    .fill(Color.gray.opacity(0.18))
                    .overlay { ProgressView() }
            default:
                Rectangle()
                    .fill(Color.gray.opacity(0.18))
                    .overlay {
                        Image(systemName: "film")
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(width: 64, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Resizable Hero Carousel (Per-Profile)
struct ResizableHeroCarousel: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    var tabID: String? = nil
    
    @ObservedObject private var profileService = ProfileService.shared
    
    private let minimumRatio: Double = 0.45
    private let maximumRatio: Double = 1.0
    
    var body: some View {
        #if os(tvOS)
        if resolvedStyle() == .cinematic {
            CinematicHeroCarouselView(
                items: items,
                onItemTap: onItemTap,
                stageAspect: 2.0,
                tabID: tabID
            )
            .frame(maxWidth: .infinity)
        } else {
            // tvOS: full-width edge-to-edge hero carousel, deliberately wider
            // than 16:9 so it stays shorter than the screen (see
            // `HeroCarouselLayout.tvMinimumAspectRatio` — a full-height hero
            // makes the tab bar unreachable).
            // Use an explicit aspectRatio + frame at this level so the inner
            // GeometryReader gets a concrete size proposal instead of unbounded
            // height from ScrollView, which breaks tvOS focus navigation.
            HeroCarouselView(
                items: items,
                onItemTap: onItemTap,
                aspectRatio: HeroCarouselLayout.tvMinimumAspectRatio,
                isPortrait: false,
                isEdgeToEdge: false,
                externalVisibilityOverride: false,
                isImmersiveStyle: false,
                tabID: tabID
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(HeroCarouselLayout.tvMinimumAspectRatio, contentMode: .fit)
        }
        #else
        if resolvedStyle() == .cinematic {
            cinematicCarousel
        } else {
            classicCarousel
        }
        #endif
    }

    #if !os(tvOS)
    /// The cinematic stage derives its own height from the stage aspect, so it
    /// needs no outer sizing. It also ignores the width slider and takes no
    /// horizontal inset — the style runs to the screen edges by design and
    /// dissolves into the page along its bottom edge.
    private var cinematicCarousel: some View {
        CinematicHeroCarouselView(
            items: items,
            onItemTap: onItemTap,
            stageAspect: cinematicStageAspect,
            tabID: tabID
        )
        #if os(iOS)
        .onScrollVisibilityChange(threshold: 0.1) { isVisible in
            HeroCarouselMuteManager.shared.isScrolledOffScreen = !isVisible
        }
        #endif
    }

    /// A 2:1 anamorphic crop is too shallow to hold the title block on a phone, so
    /// compact widths get a taller 3:2 stage instead.
    private var cinematicStageAspect: CGFloat {
        #if os(macOS)
        let containerWidth = NSScreen.main?.visibleFrame.width ?? 1200
        #elseif canImport(UIKit)
        let containerWidth: CGFloat = {
            let windowWidth = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .bounds.width ?? 0
            return windowWidth > 0 ? windowWidth : 390
        }()
        #else
        let containerWidth: CGFloat = 390
        #endif
        return containerWidth < 520 ? 1.5 : 2.0
    }

    @ViewBuilder
    private var classicCarousel: some View {
        let layout = resolvedLayout()
        let aspect = layout.aspect
        let clampedRatio = max(minimumRatio, min(maximumRatio, layout.widthRatio))

        // GeometryReader measures the actual available width after any parent
        // padding, eliminating the need for UIKit window-width lookups that
        // don't account for content margins.
        GeometryReader { geo in
            let carouselWidth = geo.size.width * clampedRatio
            HeroCarouselView(
                items: items,
                onItemTap: onItemTap,
                aspectRatio: aspect.aspectRatio,
                isPortrait: aspect == .portrait,
                tabID: tabID
            )
            .frame(width: carouselWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        // Height is derived from the carousel's aspect ratio relative to the
        // container width so the GeometryReader gets a finite height in ScrollView.
        .aspectRatio(aspect.aspectRatio / clampedRatio, contentMode: .fit)
        .padding(.horizontal, 16)
        #if os(iOS)
        .onScrollVisibilityChange(threshold: 0.1) { isVisible in
            HeroCarouselMuteManager.shared.isScrolledOffScreen = !isVisible
        }
        #endif
    }
    #endif

    private func resolvedLayout() -> (widthRatio: Double, aspect: HeroCarouselAspect) {
        let profile = profileService.activeProfile
        let ratio = profile?.heroCarouselWidthRatio ?? 1.0
        let aspect = profile?.heroCarouselAspect ?? .landscape
        return (max(minimumRatio, min(maximumRatio, ratio)), aspect)
    }

    private func resolvedStyle() -> HeroCarouselStyle {
        profileService.activeProfile?.heroCarouselStyle ?? .cinematic
    }
}

// MARK: - Production Companies Section
struct ProductionCompanyEntry: Identifiable {
    let hub: CompanyHub
    let logoURL: String?

    var id: String { hub.id }
    var name: String { hub.name }
}

struct ProductionCompaniesSection: View {
    let companies: [ProductionCompanyEntry]
    let onCompanyTap: (ProductionCompanyEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Production Companies")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(companies) { company in
                        ProductionCompanyCard(company: company) {
                            onCompanyTap(company)
                        }
                    }
                }
                .padding(.horizontal)
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .padding(.top, 8)
    }
}

struct ProductionCompanyCard: View {
    let company: ProductionCompanyEntry
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var isSearchlight: Bool { company.name == "Searchlight Pictures" }
    private var style: CompanyHub.BackgroundStyle { company.hub.backgroundStyle ?? .solid }
    private var shape: CompanyHub.ButtonShape { company.hub.buttonShape ?? .roundedRectangle }
    private var cardWidth: CGFloat { shape == .circle ? 108 : 160 }
    private var cardHeight: CGFloat { shape == .circle ? 108 : 92 }
    private var resolvedLogoURL: URL? {
        guard let raw = company.logoURL, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "https://raw.githubusercontent.com/WatchGuide-app/Studios-hubs/refs/heads/main/\(trimmed)")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    backgroundShapeView

                    if isSearchlight {
                        Image("SearchlightLogo")
                            .resizable()
                            .scaledToFit()
                            .padding(16)
                    } else if let url = resolvedLogoURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                            case .empty:
                                ProgressView()
                            default:
                                Image(systemName: "film")
                                    .font(.title2.weight(.semibold))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(16)
                    } else {
                        Image(systemName: "film")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: cardWidth, height: cardHeight)

                Text(company.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var backgroundShapeView: some View {
        let shadowColor = Color.black.opacity(colorScheme == .dark ? 0.35 : 0.1)
        switch shape {
        case .roundedRectangle:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundFill)
                .overlay(borderOverlay(for: RoundedRectangle(cornerRadius: 18, style: .continuous)))
                .shadow(color: shadowColor, radius: 6, x: 0, y: 3)
        case .capsule:
            Capsule()
                .fill(backgroundFill)
                .overlay(borderOverlay(for: Capsule()))
                .shadow(color: shadowColor, radius: 6, x: 0, y: 3)
        case .circle:
            Circle()
                .fill(backgroundFill)
                .overlay(borderOverlay(for: Circle()))
                .shadow(color: shadowColor, radius: 6, x: 0, y: 3)
        }
    }

    private var backgroundFill: some ShapeStyle {
        switch style {
        case .solid:
            return AnyShapeStyle(Color.white)
        case .glass:
            return AnyShapeStyle(.ultraThinMaterial)
        case .outline:
            #if canImport(UIKit) && !os(tvOS)
            return AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            #else
            return AnyShapeStyle(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.85))
            #endif
        case .gradient:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .dark:
            return AnyShapeStyle(Color.black.opacity(colorScheme == .dark ? 0.55 : 0.75))
        }
    }

    @ViewBuilder
    private func borderOverlay<S: Shape>(for shape: S) -> some View {
        if style == .outline || style == .glass {
            shape
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.35 : 0.6), lineWidth: 1.0)
        } else {
            EmptyView()
        }
    }
}

struct CompanyHubSheet: View {
    let companyHub: CompanyHub
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @State private var movieItems: [MediaItem] = []
    @State private var tvItems: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(companyHub.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 12)

                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 16)

                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let errorMessage = errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                    Spacer()
                } else {
                    let items = selectedTab == 0 ? movieItems : tvItems
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
                                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 32)
                            ], spacing: 32) {
                                ForEach(items) { item in
                                    MediaPosterCard(item: item)
                                        .onTapGesture {
                                            selectedItem = item
                                            dismiss()
                                        }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                        }
                    }
                }
            }
            .inlineNavTitleIfSupported()
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
        guard !companyHub.companyIds.isEmpty else {
            isLoading = false
            errorMessage = "No company IDs configured."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            async let movies = TMDBService.shared.discoverMoviesByCompany(companyIds: companyHub.companyIds)
            async let tvShows = TMDBService.shared.discoverTVByCompany(companyIds: companyHub.companyIds)
            let movieResponse = try await movies
            let tvResponse = try await tvShows
            movieItems = movieResponse.results
            tvItems = tvResponse.results
        } catch {
            errorMessage = "Failed to load content. Please try again."
            print("CompanyHubSheet error: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Liquid Glass Hub Button (Shared Component — iOS 26 SDK)
struct LiquidGlassHubButton: View {
    let imageURL: String
    let label: String
    let fallbackText: String
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) {
                ZStack {
                    // Content
                    AsyncImage(url: URL(string: imageURL)) { phase in
                        imageContent(for: phase)
                    }
                }
                .frame(width: 62, height: 62)
                .modifier(LiquidGlassCircle())
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
    
    @ViewBuilder
    private func imageContent(for phase: AsyncImagePhase) -> some View {
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
}

// MARK: - Studios Hub Row
struct StudiosHubRow: View {
    let onStudioTap: (StudioSheet) -> Void

    /// Width of the row itself — the buttons size themselves off the window, not the device.
    @State private var containerWidth: CGFloat = 0

    private let studios: [(sheet: StudioSheet, assetName: String, label: String)] = [
        (.marvel, "Marvel Studios", "Marvel"),
        (.pixar, "Pixar", "Pixar"),
        (.dc, "DC Comics", "DC"),
        (.waltDisney, "Walt Disney Pictures", "Disney"),
        (.warnerBros, "Warner Bros Pictures", "Warner Bros"),
        (.universal, "Universal Pictures", "Universal"),
        (.paramountPictures, "Paramount Pictures", "Paramount"),
        (.sonyPictures, "Sony Pictures", "Sony"),
        (.columbia, "Columbia Pictures", "Columbia"),
        (.dreamworks, "Dreamworks", "DreamWorks"),
        (.illumination, "Illumination", "Illumination"),
        (.searchlight, "Searchlight Pictures", "Searchlight"),
        (.skydance, "Skydance", "Skydance"),
        (.happyMadison, "Happy Madison", "Happy Madison"),
    ]

    private var titleFont: Font {
        #if os(tvOS)
        .title2
        #else
        .title3
        #endif
    }

    private var buttonSize: CGFloat {
        ResponsiveSizing.hubCircleButtonSize(containerWidth: containerWidth)
    }

    private var rowSpacing: CGFloat {
        ResponsiveSizing.hubCircleButtonSpacing(containerWidth: containerWidth)
    }

    private var horizontalInset: CGFloat {
        #if os(tvOS)
        60
        #else
        16
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Studios")
                .font(titleFont)
                .fontWeight(.bold)
                .padding(.horizontal, horizontalInset)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: rowSpacing) {
                    ForEach(studios, id: \.sheet) { studio in
                        StudioCircleButton(
                            assetName: studio.assetName,
                            label: studio.label,
                            size: buttonSize
                        ) {
                            onStudioTap(studio.sheet)
                        }
                    }
                }
                .padding(.horizontal, horizontalInset)
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .padding(.vertical, 8)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            containerWidth = width
        }
    }
}

// MARK: - Streaming Services Row
struct StreamingServicesRow: View {
    let onServiceTap: (StreamingSheet) -> Void

    /// Width of the row itself — the buttons size themselves off the window, not the device.
    @State private var containerWidth: CGFloat = 0

    private let services: [(sheet: StreamingSheet, assetName: String, label: String, useSFSymbol: Bool)] = [
        (.netflix, "Netflix_Logomark", "Netflix", false),
        (.disneyPlus, "Disney+_2024", "Disney+", false),
        (.hboMax, "HBO_Max_(2025)", "Max", false),
        (.paramountPlus, "Paramount+_logo", "Paramount+", false),
        (.appleTVPlus, "Apple_TV_logo", "Apple TV", false),
        (.peacock, "NBCUniversal_Peacock_Logo_(2026;_icon)", "Peacock", false),
    ]

    private var titleFont: Font {
        #if os(tvOS)
        .title2
        #else
        .title3
        #endif
    }

    private var buttonSize: CGFloat {
        ResponsiveSizing.hubCircleButtonSize(containerWidth: containerWidth)
    }

    private var rowSpacing: CGFloat {
        ResponsiveSizing.hubCircleButtonSpacing(containerWidth: containerWidth)
    }

    private var horizontalInset: CGFloat {
        #if os(tvOS)
        60
        #else
        16
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Streaming Services")
                .font(titleFont)
                .fontWeight(.bold)
                .padding(.horizontal, horizontalInset)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: rowSpacing) {
                    ForEach(services, id: \.sheet) { service in
                        StreamingCircleButton(
                            assetName: service.assetName,
                            label: service.label,
                            useSFSymbol: service.useSFSymbol,
                            size: buttonSize
                        ) {
                            onServiceTap(service.sheet)
                        }
                    }
                }
                .padding(.horizontal, horizontalInset)
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .padding(.vertical, 8)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            containerWidth = width
        }
    }
}

// MARK: - Studio Circle Button
struct StudioCircleButton: View {
    let assetName: String
    let label: String
    /// Diameter supplied by the row so every button tracks the window width.
    var size: CGFloat = 62
    let action: () -> Void
    @State private var isPressed = false

    private var buttonSize: CGFloat { size }

    private var logoPadding: CGFloat {
        size * 0.19
    }

    private var labelFont: Font {
        #if os(tvOS)
        .callout
        #else
        size >= 88 ? .footnote : .caption2
        #endif
    }

    var body: some View {
        VStack(spacing: tvSpacing) {
            Button(action: action) {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .padding(logoPadding)
                    .frame(width: buttonSize, height: buttonSize)
                    .modifier(LiquidGlassCircle())
                    .scaleEffect(isPressed ? 0.90 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            }
            #if os(tvOS)
            .buttonStyle(TVOSTransparentButtonStyle(cornerRadius: buttonSize / 2))
            #else
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            #endif

            Text(label)
                .font(labelFont)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var tvSpacing: CGFloat {
        #if os(tvOS)
        14
        #else
        max(size * 0.16, 8)
        #endif
    }
}

// MARK: - Streaming Circle Button
struct StreamingCircleButton: View {
    let assetName: String
    let label: String
    let useSFSymbol: Bool
    /// Diameter supplied by the row so every button tracks the window width.
    var size: CGFloat = 62
    let action: () -> Void
    @State private var isPressed = false

    private var buttonSize: CGFloat { size }

    private var logoPadding: CGFloat {
        size * 0.19
    }

    private var labelFont: Font {
        #if os(tvOS)
        .callout
        #else
        size >= 88 ? .footnote : .caption2
        #endif
    }

    private var sfSymbolSize: CGFloat {
        size * 0.39
    }

    private var peacockTextSize: CGFloat {
        size * 0.45
    }

    var body: some View {
        VStack(spacing: tvSpacing) {
            Button(action: action) {
                Group {
                    if useSFSymbol {
                        Image(systemName: "appletv.fill")
                            .font(.system(size: sfSymbolSize))
                            .foregroundStyle(.white)
                            .frame(width: buttonSize, height: buttonSize)
                    } else if assetName.isEmpty {
                        // Peacock — text fallback
                        Text("P")
                            .font(.system(size: peacockTextSize, weight: .black))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.0, green: 0.65, blue: 0.45),
                                        Color(red: 0.0, green: 0.35, blue: 0.7),
                                        .purple
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: buttonSize, height: buttonSize)
                    } else {
                        Image(assetName)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .padding(assetName.contains("Peacock") ? logoPadding * 1.67 : logoPadding)
                            .frame(width: buttonSize, height: buttonSize)
                    }
                }
                .modifier(LiquidGlassCircle())
                .scaleEffect(isPressed ? 0.90 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            }
            #if os(tvOS)
            .buttonStyle(TVOSTransparentButtonStyle(cornerRadius: buttonSize / 2))
            #else
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            #endif

            Text(label)
                .font(labelFont)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var tvSpacing: CGFloat {
        #if os(tvOS)
        14
        #else
        max(size * 0.16, 8)
        #endif
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
                            isIPad
                            ? AnyView(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.clear)
                                    .modifier(LiquidGlassRoundedRect(cornerRadius: 8))
                            )
                            : AnyView(Color.clear)
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
                            isIPad
                            ? AnyView(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.clear)
                                    .modifier(LiquidGlassRoundedRect(cornerRadius: 8))
                            )
                            : AnyView(Color.clear)
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
            #if !os(tvOS)
            .scrollContentBackground(isIPad ? .hidden : .automatic)
            #endif
            .background {
                if isIPad {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: 0))
                        .ignoresSafeArea()
                }
            }
            .navigationTitle("Customize Browse")
            .inlineNavTitleIfSupported()
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
                
                #if !os(tvOS)
                ToolbarItem(placement: .primaryAction) {
                    #if !os(macOS)
                    EditButton()
                    #endif
                }
                #endif
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

// MARK: - Browse Compatibility Layer
struct BrowseContentRow: Identifiable {
    let id = UUID()
    let title: String
    let items: [MediaItem]
    let people: [Person]
    let endpoint: BrowseRowConfig.BrowseEndpoint?

    init(title: String, items: [MediaItem], people: [Person], endpoint: BrowseRowConfig.BrowseEndpoint? = nil) {
        self.title = title
        self.items = items
        self.people = people
        self.endpoint = endpoint
    }
}

@MainActor
final class BrowseViewModel: ObservableObject {
    @Published var heroItems: [MediaItem] = []
    @Published var rows: [BrowseContentRow] = []

    private var hasLoaded = false
    private var pendingRefreshTask: Task<Void, Never>?
    /// The in-flight refresh, so overlapping triggers (`.task` + `.onAppear`)
    /// join the same work instead of each starting a full duplicate load.
    private var activeRefreshTask: Task<Void, Never>?

    func loadContent() async {
        guard !hasLoaded else {
            await activeRefreshTask?.value
            return
        }
        hasLoaded = true
        await refresh()
    }

    func refresh() async {
        if let activeRefreshTask {
            await activeRefreshTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            // Hero and rows are independent; running them together removes a
            // full round-trip from the time-to-first-content.
            async let hero: Void = self.loadHeroItems()
            async let rows: Void = self.loadRows()
            _ = await (hero, rows)
        }
        activeRefreshTask = task
        await task.value
        activeRefreshTask = nil
    }

    /// Debounces rapid-fire calls (e.g. multiple onChange events at startup) into a single refresh.
    func scheduleRefresh() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func loadHeroItems() async {
        let storage = StorageService.shared
        let settings = storage.settings
        let source = settings.heroCarouselSource

        do {
            switch source {
            case .trendingMovies:
                heroItems = try await TMDBService.shared.getTrending(mediaType: .movie).results
            case .trendingTV:
                heroItems = try await TMDBService.shared.getTrending(mediaType: .tv).results
            case .popularMovies:
                heroItems = try await TMDBService.shared.getPopularMovies().results
            case .popularTV:
                heroItems = try await TMDBService.shared.getPopularTV().results
            case .nowPlayingMovies:
                heroItems = try await TMDBService.shared.getNowPlayingMovies().results
            case .topRatedMovies:
                heroItems = try await TMDBService.shared.getTopRatedMovies().results
            case .upcomingMovies:
                heroItems = try await TMDBService.shared.getUpcomingMovies().results
            case .mdblistTrending:
                heroItems = try await MDBListService.shared.fetchListItemsAsMediaItems(
                    listId: "dualipafan01/new-content-list",
                    limit: 25
                )
            case .customLists:
                var merged: [MediaItem] = []
                if let movieList = settings.heroCarouselCustomMovieListId, !movieList.isEmpty {
                    merged += try await MDBListService.shared.fetchListItemsAsMediaItems(listId: movieList, limit: 20)
                }
                if let showList = settings.heroCarouselCustomShowListId, !showList.isEmpty {
                    merged += try await MDBListService.shared.fetchListItemsAsMediaItems(listId: showList, limit: 20)
                }
                heroItems = deduplicated(merged)
            case .mdblistPair:
                var merged: [MediaItem] = []
                if let movieList = settings.heroCarouselMDBListMovieId, !movieList.isEmpty {
                    merged += try await MDBListService.shared.fetchListItemsAsMediaItems(listId: movieList, limit: 20)
                }
                if let showList = settings.heroCarouselMDBListShowId, !showList.isEmpty {
                    merged += try await MDBListService.shared.fetchListItemsAsMediaItems(listId: showList, limit: 20)
                }
                heroItems = deduplicated(merged)
            case .featured:
                let movies = try await TMDBService.shared.getTrending(mediaType: .movie).results
                let shows = try await TMDBService.shared.getTrending(mediaType: .tv).results
                // Interleave movies and shows for variety
                var merged: [MediaItem] = []
                let maxCount = max(movies.count, shows.count)
                for i in 0..<maxCount {
                    if i < movies.count { merged.append(movies[i]) }
                    if i < shows.count { merged.append(shows[i]) }
                }
                heroItems = deduplicated(merged)
            }
        } catch {
            print("BrowseViewModel hero load error: \(error)")
            heroItems = []
        }

        if storage.settings.isKidsProfile {
            heroItems = heroItems.filter { $0.adult != true }
        }
        heroItems = Array(heroItems.prefix(25))

        // The first few hero slides are what the user sees first — warm them
        // before anything else competes for the connection pool.
        let heroURLs = heroItems
            .prefix(4)
            .compactMap { TMDBService.shared.imageURL(path: $0.backdropPath, size: .backdropSmall) }
        ImageDownloader.shared.prefetch(Array(heroURLs))
    }

    /// Loads every configured row concurrently and publishes each one the moment
    /// it arrives, in its configured order.
    ///
    /// This used to run one row at a time and assign `rows` only after the last
    /// one finished, so a single slow endpoint left the whole screen empty —
    /// which is why only the static Studios/Streaming rows appeared on launch.
    private func loadRows() async {
        let storage = StorageService.shared
        let configuredRows = storage.browseRows
            .filter(\.isEnabled)
            .sorted { $0.sortOrder < $1.sortOrder }

        guard !configuredRows.isEmpty else {
            rows = []
            return
        }

        // Slots preserve configured order while results land out of order.
        var slots = [BrowseContentRow?](repeating: nil, count: configuredRows.count)
        var isFirstResult = true

        await withTaskGroup(of: (Int, BrowseContentRow?).self) { group in
            for (index, rowConfig) in configuredRows.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (index, nil) }
                    do {
                        return (index, try await self.loadRow(rowConfig))
                    } catch {
                        print("BrowseViewModel row load error (\(rowConfig.title)): \(error)")
                        return (index, nil)
                    }
                }
            }

            for await (index, row) in group {
                slots[index] = row

                // Replace the previous (possibly stale) rows only once real
                // content exists, so a refresh never blanks the screen.
                if isFirstResult {
                    rows = []
                    isFirstResult = false
                }
                rows = slots.compactMap { $0 }

                if let row {
                    Self.prefetchArtwork(for: row)
                }
            }
        }

        rows = slots.compactMap { $0 }
    }

    /// Warms the image cache for a row's posters so they are already decoded by
    /// the time the user scrolls them into view.
    private static func prefetchArtwork(for row: BrowseContentRow) {
        let urls = row.items
            .prefix(10)
            .compactMap { TMDBService.shared.imageURL(path: $0.posterPath, size: .medium) }
        ImageDownloader.shared.prefetch(Array(urls))
    }

    private func loadRow(_ rowConfig: BrowseRowConfig) async throws -> BrowseContentRow {
        let ep = rowConfig.endpoint
        switch ep {
        case .trendingMovies:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getTrending(mediaType: .movie).results, people: [], endpoint: ep)
        case .trendingTV:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getTrending(mediaType: .tv).results, people: [], endpoint: ep)
        case .trendingPeople:
            return BrowseContentRow(title: rowConfig.title, items: [], people: try await TMDBService.shared.getTrendingPeople().results, endpoint: ep)
        case .popularMovies:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getPopularMovies().results, people: [], endpoint: ep)
        case .popularTV:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getPopularTV().results, people: [], endpoint: ep)
        case .topRatedMovies:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getTopRatedMovies().results, people: [], endpoint: ep)
        case .topRatedTV:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getTopRatedTV().results, people: [], endpoint: ep)
        case .nowPlayingMovies:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getNowPlayingMovies().results, people: [], endpoint: ep)
        case .airingTodayTV:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getAiringTodayTV().results, people: [], endpoint: ep)
        case .upcomingMovies:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getUpcomingMovies().results, people: [], endpoint: ep)
        case .onTheAirTV:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getOnTheAirTV().results, people: [], endpoint: ep)
        case .latestCertifiedFresh:
            // "Latest Movies & Shows Rated 6/10+" — interleave both media types.
            async let movies = TMDBService.shared.getLatestHighRatedMovies().results
            async let shows = TMDBService.shared.getLatestHighRatedTV().results
            let (movieItems, showItems) = try await (movies, shows)
            var merged: [MediaItem] = []
            for index in 0..<max(movieItems.count, showItems.count) {
                if index < movieItems.count { merged.append(movieItems[index]) }
                if index < showItems.count { merged.append(showItems[index]) }
            }
            return BrowseContentRow(title: rowConfig.title, items: deduplicated(merged), people: [], endpoint: ep)
        }
    }

    private func deduplicated(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<Int>()
        return items.filter {
            guard !seen.contains($0.id) else { return false }
            seen.insert($0.id)
            return true
        }
    }
}

@MainActor
final class ForYouViewModel: ObservableObject {
    @Published var items: [MediaItem] = []
    private var didLoad = false

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        await refresh()
    }

    func refresh() async {
        guard TasteRecommender.shared.hasTaste else {
            await loadFallback()
            return
        }
        // GPT-5 Nano reads Liked + Watched and every pick is resolved on TMDB.
        let picks = await TasteRecommender.shared.recommendations(kind: .any, count: 20, refresh: didLoad && !items.isEmpty)
        if picks.isEmpty {
            await loadFallback()
        } else {
            items = Array(picks.prefix(20))
        }
    }

    private func loadFallback() async {
        do {
            async let trendingMovies = TMDBService.shared.getTrending(mediaType: .movie, timeWindow: "day").results
            async let trendingTV = TMDBService.shared.getTrending(mediaType: .tv, timeWindow: "day").results
            let merged = try await trendingMovies + trendingTV
            items = Array(deduplicated(merged).prefix(20))
        } catch {
            print("ForYouViewModel fallback error: \(error)")
            items = []
        }
    }

    private func deduplicated(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<Int>()
        return items.filter {
            guard !seen.contains($0.id) else { return false }
            seen.insert($0.id)
            return true
        }
    }
}

struct ForYouRow: View {
    @ObservedObject var viewModel: ForYouViewModel
    let onItemTap: (MediaItem) -> Void

    var body: some View {
        Group {
            if !viewModel.items.isEmpty {
                MediaRowView(title: "For You", items: viewModel.items, onItemTap: onItemTap)
            }
        }
        .task { await viewModel.loadIfNeeded() }
    }
}

struct BrowseDiscoverSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discover")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)

            NavigationLink(destination: DiscoverView()) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text("Open Discovery Hub")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.gray.opacity(0.12))
                )
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
        }
    }
}

struct CustomJSONHubsRow: View {
    let hubs: [CustomJSONHub]
    let onTap: (CustomJSONHub) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(hubs) { hub in
                    Button {
                        onTap(hub)
                    } label: {
                        Text(hub.displayRowName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.gray.opacity(0.16))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

struct NetworkHubSheet: View {
    let hub: NetworkHub
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(items) { item in
                                Button {
                                    selectedItem = item
                                    dismiss()
                                } label: {
                                    Text(item.displayTitle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(hub.name)
            .inlineNavTitleIfSupported()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            await loadContent()
        }
    }

    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            var loaded: [MediaItem] = []

            if !hub.networkIds.isEmpty {
                let tv = try await TMDBService.shared.discoverTVByNetwork(networkIds: hub.networkIds)
                loaded += tv.results
            }

            if !hub.providerIds.isEmpty {
                let region = StorageService.shared.settings.region.isEmpty ? "US" : StorageService.shared.settings.region
                async let providerMovies = TMDBService.shared.discoverMoviesWithProvider(providerIds: hub.providerIds, region: region)
                async let providerTV = TMDBService.shared.discoverTVWithProvider(providerIds: hub.providerIds, region: region)
                loaded += (try await providerMovies).results
                loaded += (try await providerTV).results
            }

            items = deduplicated(loaded)
            if items.isEmpty {
                errorMessage = "No titles found."
            }
        } catch {
            print("NetworkHubSheet error: \(error)")
            errorMessage = "Failed to load content."
        }
    }

    private func deduplicated(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<Int>()
        return items.filter {
            guard !seen.contains($0.id) else { return false }
            seen.insert($0.id)
            return true
        }
    }
}

struct CustomJSONHubSheet: View {
    let hub: CustomJSONHub
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(hub.items) { item in
                        Button {
                            selectedItem = item.asMediaItem()
                            dismiss()
                        } label: {
                            Text(item.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(hub.name)
            .inlineNavTitleIfSupported()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// Old studio sheets (WarnerBros, DreamWorks, etc.) removed — now using DisneyHubSheet

// MARK: - Availability-safe Liquid Glass helpers
struct LiquidGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content
                .background(
                    Circle().fill(.ultraThinMaterial)
                )
        }
    }
}

struct LiquidGlassRoundedRect: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        }
    }
}

// MARK: - See All View

struct SeeAllView: View {
    let title: String
    let items: [MediaItem]
    @State private var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            selectedItem = item
                        } label: {
                            MediaPosterCard(item: item, appearanceIndex: index)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .mediaDetailPresentation(item: $selectedItem)
    }

    private var gridColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 5 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }
}

// MARK: - Apple TV Continue Watching Card
/// Apple TV-inspired Continue Watching card with backdrop image and progress overlay
struct AppleTVContinueWatchingCard: View {
    let item: ContinueWatchingItem
    @Environment(\.isFocused) private var isFocused
    
    private var progressPercentage: Double {
        max(0, min(1, item.progress))
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image
            if let backdropPath = item.show.backdropPath {
                let url = TMDBService.shared.imageURL(path: backdropPath, size: .backdropSmall)
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .clipped()
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.25))
                            .overlay { ProgressView() }
                    default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.25))
                            .overlay {
                                Image(systemName: "tv.fill")
                                    .foregroundColor(.secondary)
                            }
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .overlay {
                        Image(systemName: "tv.fill")
                            .foregroundColor(.secondary)
                    }
            }
            
            // Dark overlay at bottom for text readability
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: .black.opacity(0.4), location: 0.6),
                    .init(color: .black.opacity(0.7), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Content overlay
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.show.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    if let lastEpisode = item.lastEpisode {
                        Text("Up to \(lastEpisode.code)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                
                // Progress bar
                if item.progress >= 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.white.opacity(0.25))
                            
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * progressPercentage)
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.8 : 0.2), lineWidth: isFocused ? 2 : 0)
        }
        .shadow(color: .black.opacity(isFocused ? 0.4 : 0.2), radius: isFocused ? 12 : 6, y: isFocused ? 6 : 3)
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isFocused)
    }
}

// #Preview omitted for brevity
#Preview {
    BrowseView(selectedItem: .constant(nil))
}

