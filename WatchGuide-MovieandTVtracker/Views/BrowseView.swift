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
    @State private var selectedCompanyHub: CompanyHub?
    @State private var activeStudioSheet: StudioSheet?
    @State private var showCustomizeSheet = false
    @State private var selectedPerson: Person?
    @State private var showProfileSwitcher = false
    @State private var selectedJSONHub: CustomJSONHub?
    @State private var dailyPickCache: DailyPickCache?
    @State private var isDailyPickHidden = false
    @State private var selectedMiniGame: MiniGame?
    @State private var miniGameCandidates: [MediaItem] = []
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var profileService = ProfileService.shared
    
    enum StudioSheet: String, Identifiable {
        case twentiethCentury, warnerBros, dreamWorks, dcStudios, universalPictures, sonyPictures
        var id: String { rawValue }
    }
    
    private var isKidsProfile: Bool {
        StorageService.shared.settings.isKidsProfile
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

    enum MiniGame: String, Identifiable, CaseIterable {
        case guessThePoster
        case thisOrThat

        var id: String { rawValue }

        var title: String {
            switch self {
            case .guessThePoster:
                return "Guess the Poster"
            case .thisOrThat:
                return "This or That"
            }
        }
        
        var subtitle: String {
            switch self {
            case .guessThePoster:
                return "Blurred poster challenge"
            case .thisOrThat:
                return "Pick your vibe"
            }
        }
        
        var iconName: String {
            switch self {
            case .guessThePoster:
                return "sparkles"
            case .thisOrThat:
                return "arrow.left.arrow.right.circle.fill"
            }
        }
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

    private let productionCompanies: [ProductionCompanyEntry] = [
        ProductionCompanyEntry(
            name: "Paramount Pictures",
            logoURL: "https://cdn.brandfetch.io/idrAEeTLeo/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1757576972155"
        ),
        ProductionCompanyEntry(
            name: "Walt Disney Pictures",
            logoURL: "https://cdn.brandfetch.io/idxASqzkm_/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1675929043591"
        ),
        ProductionCompanyEntry(
            name: "20th Century Studios",
            logoURL: "https://cdn.brandfetch.io/id80eyhRc1/w/820/h/683/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1667562091650"
        ),
        ProductionCompanyEntry(
            name: "Searchlight Pictures",
            logoURL: nil
        ),
        ProductionCompanyEntry(
            name: "Warner Bros.",
            logoURL: "https://cdn.brandfetch.io/idxBWIwtz0/w/405/h/396/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1768344714851"
        ),
        ProductionCompanyEntry(
            name: "Pixar",
            logoURL: "https://cdn.brandfetch.io/idYVybSjsA/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1764458646138"
        ),
        ProductionCompanyEntry(
            name: "Universal Pictures",
            logoURL: "https://cdn.brandfetch.io/id4AnmmNSk/theme/light/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1767628904850"
        ),
        ProductionCompanyEntry(
            name: "Sony Pictures",
            logoURL: "https://cdn.brandfetch.io/idIBgcvFOi/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1766845823465"
        ),
        ProductionCompanyEntry(
            name: "Metro-Goldwyn-Mayer",
            logoURL: "https://cdn.brandfetch.io/idLI5gJfl8/w/161/h/86/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1667810266726"
        ),
        ProductionCompanyEntry(
            name: "Lionsgate Films",
            logoURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/9/95/Lionsgate_2025.svg/500px-Lionsgate_2025.svg.png"
        ),
        ProductionCompanyEntry(
            name: "A24",
            logoURL: "https://cdn.brandfetch.io/idHlMmIC6s/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1748302432792"
        ),
        ProductionCompanyEntry(
            name: "DreamWorks",
            logoURL: "https://cdn.brandfetch.io/idj7QnEvUG/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1764869429974"
        ),
        ProductionCompanyEntry(
            name: "Blumhouse Productions",
            logoURL: "https://cdn.brandfetch.io/idMdr695hi/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1767230760280"
        ),
        ProductionCompanyEntry(
            name: "Happy Madison Productions",
            logoURL: "https://upload.wikimedia.org/wikipedia/commons/4/4f/Happy-Madison-Productions-logo.png"
        ),
        ProductionCompanyEntry(
            name: "Amblin Entertainment",
            logoURL: "https://upload.wikimedia.org/wikipedia/en/1/16/Amblin_Entertainment_%28Print%29.svg"
        )
    ]
    
    var body: some View {
        NavigationStack {
            PopcornRefreshableScrollView {
                await viewModel.refresh()
                await forYouVM.refresh()
            } content: {
                browseScrollContent
            }
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
            .sheet(item: $selectedNetworkHub) { hub in
                NetworkHubSheet(hub: hub, selectedItem: $selectedItem)
            }
            .sheet(item: $activeStudioSheet) { studio in
                studioSheetContent(for: studio)
            }
            .sheet(item: $selectedCompanyHub) { hub in
                CompanyHubSheet(companyHub: hub, selectedItem: $selectedItem)
            }
            .sheet(item: $selectedJSONHub) { hub in
                CustomJSONHubSheet(hub: hub, selectedItem: $selectedItem)
            }
            .sheet(item: $selectedMiniGame) { game in
                MiniGameSheet(game: game, candidates: miniGameCandidates)
            }
            #if os(iOS)
            .sheet(isPresented: $showCustomizeSheet) {
                HomeCustomizationView()
            }
            #endif
            .sheet(isPresented: $showProfileSwitcher) {
                ProfileSwitcherSheet()
            }
            .onChange(of: StorageService.shared.settings.heroCarouselSource) { _, _ in
                Task { await viewModel.refresh() }
            }
            .onChange(of: authService.isAuthenticated) { _, _ in
                Task { await viewModel.refresh() }
            }
            .onChange(of: StorageService.shared.settings.isKidsProfile) { _, _ in
                Task { await viewModel.refresh() }
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
        }
    }
    
    // MARK: - Extracted Sub-Views
    
    private var browseScrollContent: some View {
        LazyVStack(spacing: 24) {
            if let cache = dailyPickCache, !isDailyPickHidden {
                DailyPickCard(
                    item: cache.item,
                    reason: dailyPickReason(for: cache.source),
                    onTap: { selectedItem = cache.item },
                    onDismiss: dismissDailyPickForToday
                )
            }
            if !viewModel.heroItems.isEmpty {
                ResizableHeroCarousel(
                    items: viewModel.heroItems,
                    onItemTap: { item in
                        selectedItem = item
                    }
                )
            }
            
            ForEach(orderedSections) { section in
                browseSectionView(for: section)
            }

            ProductionCompaniesSection(
                companies: productionCompanies,
                onCompanyTap: { company in
                    if let hub = company.toCompanyHub() {
                        selectedCompanyHub = hub
                    }
                }
            )
        }
        .padding(.vertical)
    }
    
    @ViewBuilder
    private func browseSectionView(for section: BrowseSectionItem) -> some View {
        switch section.sectionType {
        case .networks:
            if !isKidsProfile, !viewModel.networkHubs.isEmpty {
                NetworkHubsRow(hubs: viewModel.networkHubs) { hub in
                    selectedNetworkHub = hub
                }
            }
        case .rows:
            browseRowsSection
        case .studios:
            if !isKidsProfile {
                StudiosHubRow(
                    onTwentiethCenturyTap: { activeStudioSheet = .twentiethCentury },
                    onWarnerBrosTap: { activeStudioSheet = .warnerBros },
                    onDreamWorksTap: { activeStudioSheet = .dreamWorks },
                    onDCStudiosTap: { activeStudioSheet = .dcStudios },
                    onUniversalPicturesTap: { activeStudioSheet = .universalPictures },
                    onSonyPicturesTap: { activeStudioSheet = .sonyPictures }
                )
            }
        case .customHubs:
            customHubsSection
        case .forYou:
            if authService.isAuthenticated, isAdultProfile {
                ForYouRow(viewModel: forYouVM) { item in
                    selectedItem = item
                }
            }
        case .discover:
            if isAdultProfile {
                BrowseDiscoverSection()
            }
        }
    }
    
    private var browseRowsSection: some View {
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
                if row.title == "Now Playing", !isKidsProfile {
                    MiniGamesSection { game in
                        Task {
                            let candidates = await loadMiniGameCandidates()
                            await MainActor.run {
                                miniGameCandidates = candidates
                                selectedMiniGame = game
                            }
                        }
                    }
                }
            } else {
                EmptyView()
            }
        }
    }

    private func buildMiniGameCandidates() -> [MediaItem] {
        var pool = viewModel.heroItems
        for row in viewModel.rows {
            pool.append(contentsOf: row.items)
        }
        let filtered = pool.filter { item in
            guard item.resolvedMediaType != .person else { return false }
            if isKidsProfile, item.adult == true { return false }
            return item.posterPath != nil
        }
        var seen = Set<Int>()
        let unique = filtered.filter { item in
            if seen.contains(item.id) { return false }
            seen.insert(item.id)
            return true
        }
        return Array(unique.prefix(40))
    }

    private func loadMiniGameCandidates() async -> [MediaItem] {
        var base = buildMiniGameCandidates()
        if base.count >= 8 { return base }

        let listId = isKidsProfile ? "dualipafan01/family-friendly-list" : "dualipafan01/new-content-list"
        do {
            let items = try await MDBListService.shared.fetchListItemsAsMediaItems(listId: listId, limit: 40)
            base.append(contentsOf: items)
        } catch {
            print("Mini game list error: \(error)")
        }

        var filtered = base.filter { item in
            guard item.resolvedMediaType != .person else { return false }
            if isKidsProfile, item.adult == true { return false }
            return item.posterPath != nil
        }
        var seen = Set<Int>()
        let unique = filtered.filter { item in
            if seen.contains(item.id) { return false }
            seen.insert(item.id)
            return true
        }
        if unique.count >= 4 {
            return Array(unique.prefix(40))
        }

        do {
            let movieResults = try await TMDBService.shared.getTrending(mediaType: .movie, timeWindow: "day").results
            let tvResults = try await TMDBService.shared.getTrending(mediaType: .tv, timeWindow: "day").results
            filtered.append(contentsOf: movieResults)
            filtered.append(contentsOf: tvResults)
        } catch {
            print("Mini game TMDB fallback error: \(error)")
        }

        seen.removeAll()
        let fallbackUnique = filtered.filter { item in
            guard item.resolvedMediaType != .person else { return false }
            if isKidsProfile, item.adult == true { return false }
            guard item.posterPath != nil else { return false }
            if seen.contains(item.id) { return false }
            seen.insert(item.id)
            return true
        }
        return Array(fallbackUnique.prefix(40))
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
        ToolbarItem(placement: .topBarLeading) {
            if authService.isAuthenticated && profileService.hasProfiles {
                Button {
                    showProfileSwitcher = true
                } label: {
                    if let profile = profileService.activeProfile {
                        Image(systemName: profile.avatar.rawValue)
                            .foregroundColor(profile.color.color)
                    } else {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
        }
        
        #if os(iOS)
        ToolbarItem(placement: .primaryAction) {
            Button {
                showCustomizeSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
        #endif
    }
    
    @ViewBuilder
    private func studioSheetContent(for studio: StudioSheet) -> some View {
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

            Button(action: onTap) {
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
                        .fill(Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
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
                    .fill(Color(.systemGray5))
                    .overlay { ProgressView() }
            default:
                Rectangle()
                    .fill(Color(.systemGray5))
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

private struct MiniGamesSection: View {
    let onTap: (BrowseView.MiniGame) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mini Games")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(BrowseView.MiniGame.allCases) { game in
                        Button {
                            onTap(game)
                        } label: {
                            MiniGameCard(game: game)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct MiniGameCard: View {
    let game: BrowseView.MiniGame

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: game.iconName)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(game.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(game.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color.secondary.opacity(0.6))
        }
        .padding(12)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
        )
    }
}

private struct MiniGameSheet: View {
    let game: BrowseView.MiniGame
    let candidates: [MediaItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            switch game {
            case .thisOrThat:
                ThisOrThatGameView(candidates: candidates)
            case .guessThePoster:
                GuessThePosterGameView(candidates: candidates)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }
}

private struct ThisOrThatGameView: View {
    let candidates: [MediaItem]
    @State private var leftItem: MediaItem?
    @State private var rightItem: MediaItem?
    @State private var round = 1
    @State private var totalRounds = 5
    @State private var isComplete = false
    @State private var localCandidates: [MediaItem] = []

    var body: some View {
        VStack(spacing: 16) {
            Text("This or That")
                .font(.title2)
                .fontWeight(.bold)

            Text("Round \(round) of \(totalRounds)")
                .font(.caption)
                .foregroundColor(.secondary)

            if let leftItem, let rightItem {
                HStack(spacing: 12) {
                    MiniGamePosterCard(item: leftItem) {
                        advanceRound()
                    }
                    MiniGamePosterCard(item: rightItem) {
                        advanceRound()
                    }
                }
                .padding(.horizontal)
            } else {
                Text("Not enough titles to play yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.top, 16)
        .onAppear {
            localCandidates = uniqueCandidates(from: candidates)
            startRound()
        }
        .task {
            guard localCandidates.count < 2 else { return }
            let fallback = await fetchFallbackCandidates(minimum: 2)
            let merged = uniqueCandidates(from: localCandidates + fallback)
            if merged.count >= 2 {
                localCandidates = merged
                startRound()
            }
        }
        .alert("All done!", isPresented: $isComplete) {
            Button("Play again") {
                round = 1
                isComplete = false
                startRound()
            }
        } message: {
            Text("Nice picks. Want another quick round?")
        }
    }

    private func startRound() {
        guard localCandidates.count >= 2 else {
            leftItem = nil
            rightItem = nil
            return
        }
        let shuffled = localCandidates.shuffled()
        leftItem = shuffled.first
        rightItem = shuffled.dropFirst().first
    }

    private func advanceRound() {
        if round >= totalRounds {
            isComplete = true
            return
        }
        round += 1
        startRound()
    }

    private func fetchFallbackCandidates(minimum: Int) async -> [MediaItem] {
        do {
            let movieResults = try await TMDBService.shared.getTrending(mediaType: .movie, timeWindow: "day").results
            let tvResults = try await TMDBService.shared.getTrending(mediaType: .tv, timeWindow: "day").results
            let combined = (movieResults + tvResults).filter { $0.posterPath != nil }
            return Array(combined.prefix(max(minimum, 8)))
        } catch {
            print("Mini game fallback error: \(error)")
            return []
        }
    }

    private func uniqueCandidates(from items: [MediaItem]) -> [MediaItem] {
        var seen = Set<Int>()
        return items.filter { item in
            guard item.posterPath != nil else { return false }
            if seen.contains(item.id) { return false }
            seen.insert(item.id)
            return true
        }
    }
}

private struct GuessThePosterGameView: View {
    let candidates: [MediaItem]
    @State private var localCandidates: [MediaItem] = []
    @State private var correctItem: MediaItem?
    @State private var options: [MediaItem] = []
    @State private var round = 1
    @State private var totalRounds = 5
    @State private var feedback: String?
    @State private var score = 0
    @State private var isComplete = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Guess the Poster")
                .font(.title2)
                .fontWeight(.bold)

            Text("Round \(round) of \(totalRounds) • Score \(score)")
                .font(.caption)
                .foregroundColor(.secondary)

            if let correctItem {
                BlurredPosterView(item: correctItem)
                    .padding(.top, 4)

                VStack(spacing: 10) {
                    ForEach(options, id: \.id) { option in
                        Button {
                            handleGuess(option)
                        } label: {
                            Text(option.displayTitle)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(.systemGray6))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            } else {
                Text("Not enough titles to play yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.top, 16)
        .onAppear {
            localCandidates = uniqueCandidates(from: candidates)
            startRound()
        }
        .task {
            guard localCandidates.count < 4 else { return }
            let fallback = await fetchFallbackCandidates(minimum: 4)
            let merged = uniqueCandidates(from: localCandidates + fallback)
            if merged.count >= 4 {
                localCandidates = merged
                startRound()
            }
        }
        .alert("Nice!", isPresented: $isComplete) {
            Button("Play again") {
                round = 1
                score = 0
                isComplete = false
                startRound()
            }
        } message: {
            Text("Your final score: \(score)/\(totalRounds)")
        }
    }

    private func startRound() {
        guard localCandidates.count >= 4 else {
            correctItem = nil
            options = []
            return
        }
        let shuffled = localCandidates.shuffled()
        correctItem = shuffled.first
        options = Array(shuffled.prefix(4)).shuffled()
        feedback = nil
    }

    private func handleGuess(_ option: MediaItem) {
        guard let correctItem else { return }
        if option.id == correctItem.id {
            score += 1
            feedback = "Correct!"
        } else {
            feedback = "Not quite — it was \(correctItem.displayTitle)."
        }
        if round >= totalRounds {
            isComplete = true
        } else {
            round += 1
            startRound()
        }
    }

    private func fetchFallbackCandidates(minimum: Int) async -> [MediaItem] {
        do {
            let movieResults = try await TMDBService.shared.getTrending(mediaType: .movie, timeWindow: "day").results
            let tvResults = try await TMDBService.shared.getTrending(mediaType: .tv, timeWindow: "day").results
            let combined = (movieResults + tvResults).filter { $0.posterPath != nil }
            return Array(combined.prefix(max(minimum, 8)))
        } catch {
            print("Guess the Poster fallback error: \(error)")
            return []
        }
    }

    private func uniqueCandidates(from items: [MediaItem]) -> [MediaItem] {
        var seen = Set<Int>()
        return items.filter { item in
            guard item.posterPath != nil else { return false }
            if seen.contains(item.id) { return false }
            seen.insert(item.id)
            return true
        }
    }
}

private struct MiniGamePosterCard: View {
    let item: MediaItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                MiniGamePosterImage(item: item)
                Text(item.displayTitle)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MiniGamePosterImage: View {
    let item: MediaItem

    var body: some View {
        let posterURL = TMDBService.shared.imageURL(path: item.posterPath, size: .medium)
        AsyncImage(url: posterURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "film")
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(width: 110, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct BlurredPosterView: View {
    let item: MediaItem

    var body: some View {
        let posterURL = TMDBService.shared.imageURL(path: item.posterPath, size: .medium)
        AsyncImage(url: posterURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 10)
            default:
                Rectangle()
                    .fill(Color(.systemGray5))
            }
        }
        .frame(width: 180, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Resizable Hero Carousel (Per-Profile)
struct ResizableHeroCarousel: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    
    @ObservedObject private var profileService = ProfileService.shared
    
    private let minimumRatio: Double = 0.45
    private let maximumRatio: Double = 1.0
    
    var body: some View {
        let layout = resolvedLayout()
        let aspect = layout.aspect
        let availableWidth = max(UIScreen.main.bounds.width - 24, 1)
        let clampedRatio = max(minimumRatio, min(maximumRatio, layout.widthRatio))
        let width = availableWidth * clampedRatio
        
        HeroCarouselView(
            items: items,
            onItemTap: onItemTap,
            aspectRatio: aspect.aspectRatio,
            isPortrait: aspect == .portrait
        )
        .frame(width: width)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    private func resolvedLayout() -> (widthRatio: Double, aspect: HeroCarouselAspect) {
        let profile = profileService.activeProfile
        let ratio = profile?.heroCarouselWidthRatio ?? 1.0
        let aspect = profile?.heroCarouselAspect ?? .landscape
        return (max(minimumRatio, min(maximumRatio, ratio)), aspect)
    }
}

// MARK: - Production Companies Section
struct ProductionCompanyEntry: Identifiable {
    let id = UUID().uuidString
    let name: String
    let logoURL: String?

    func toCompanyHub() -> CompanyHub? {
        guard let companyId = ProductionCompanyEntry.companyId(for: name) else { return nil }
        return CompanyHub(name: name, companyIds: [companyId], networkIds: [])
    }

    private static func companyId(for name: String) -> Int? {
        switch name {
        case "Paramount Pictures": return 4
        case "Walt Disney Pictures": return 2
        case "20th Century Studios": return 127928
        case "Searchlight Pictures": return 127929
        case "Warner Bros.": return 174
        case "Pixar": return 3
        case "Universal Pictures": return 33
        case "Sony Pictures": return 34
        case "Metro-Goldwyn-Mayer": return 21
        case "Lionsgate Films": return 1632
        case "A24": return 41077
        case "DreamWorks": return 521
        case "Blumhouse Productions": return 3172
        case "Happy Madison Productions": return 878
        case "Amblin Entertainment": return 56
        default: return nil
        }
    }
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
        }
        .padding(.top, 8)
    }
}

struct ProductionCompanyCard: View {
    let company: ProductionCompanyEntry
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var isSearchlight: Bool { company.name == "Searchlight Pictures" }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                            radius: 6,
                            x: 0,
                            y: 3
                        )

                    if isSearchlight {
                        Image("SearchlightLogo")
                            .resizable()
                            .scaledToFit()
                            .padding(16)
                    } else if let urlString = company.logoURL, let url = URL(string: urlString) {
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
                .frame(width: 160, height: 92)

                Text(company.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
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
                        innerGradient
                        
                        // Content
                        AsyncImage(url: URL(string: imageURL)) { phase in
                            imageContent(for: phase)
                        }
                        
                        // Top specular highlight
                        topHighlight
                        
                        // Border ring
                        borderRing
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
    
    private var innerGradient: some View {
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
    }
    
    private var topHighlight: some View {
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
    }
    
    private var borderRing: some View {
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
                HStack(spacing: 14) {
                    NavigationLink(destination: TimelinesView()) {
                        DiscoverFeatureCard(
                            title: "Timelines",
                            subtitle: "Follow story arcs in order",
                            iconName: "list.bullet.rectangle",
                            accentColor: .indigo,
                            isLarge: false
                        )
                    }
                    .buttonStyle(.plain)
                    
                    NavigationLink(destination: MoodDiscoveryView()) {
                        DiscoverFeatureCard(
                            title: "Mood Discovery",
                            subtitle: "Pick your vibe, get curated results",
                            iconName: "sparkles",
                            accentColor: .purple,
                            isLarge: false
                        )
                    }
                    .buttonStyle(.plain)
                }
                
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
                
                HStack(spacing: 14) {
                    NavigationLink(destination: AIRecommendView()) {
                        DiscoverFeatureCard(
                            title: "AI Recommendations",
                            subtitle: "Get personalized picks from AI assistants",
                            iconName: "brain.head.profile.fill",
                            accentColor: Color(.systemGray),
                            isLarge: false
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: BoxOfficeCinemaSelectorView()) {
                        DiscoverFeatureCard(
                            title: "Box Office",
                            subtitle: "Find your nearest cinema",
                            iconName: "ticket.fill",
                            accentColor: .red,
                            isLarge: false
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 14) {
                    NavigationLink(destination: CinemaTripPlannerView()) {
                        DiscoverFeatureCard(
                            title: "Trip Planner",
                            subtitle: "Know when to leave for the movies",
                            iconName: "car.circle.fill",
                            accentColor: .mint,
                            isLarge: false
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            
            // Quick Stats Row — only observes storage here
            BrowseQuickStatsRow()
            
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
    
    /// Filters a list of MediaItems to only those that have at least one YouTube trailer/teaser.
    /// Checks videos concurrently and preserves original order.
    private func filterItemsWithTrailers(_ items: [MediaItem]) async -> [MediaItem] {
        guard !items.isEmpty else { return [] }
        
        let results = await withTaskGroup(of: (Int, MediaItem, Bool).self, returning: [(Int, MediaItem)].self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    do {
                        let videos: VideosResponse
                        if item.resolvedMediaType == .movie {
                            videos = try await TMDBService.shared.getMovieVideos(id: item.id)
                        } else {
                            videos = try await TMDBService.shared.getTVShowVideos(id: item.id)
                        }
                        let hasTrailer = videos.results.contains { v in
                            v.site.lowercased() == "youtube" &&
                            (v.type.lowercased() == "trailer" || v.type.lowercased() == "teaser")
                        }
                        return (index, item, hasTrailer)
                    } catch {
                        return (index, item, false)
                    }
                }
            }
            
            var matched: [(Int, MediaItem)] = []
            for await (index, item, hasTrailer) in group {
                if hasTrailer {
                    matched.append((index, item))
                }
            }
            return matched.sorted { $0.0 < $1.0 }
        }
        
        let filtered = results.map { $0.1 }
        if filtered.isEmpty {
            return items
        }
        return filtered
    }
    
    private func loadHeroItems() async {
        let source = StorageService.shared.settings.heroCarouselSource
        let isAuthenticated = await MainActor.run { AuthService.shared.isAuthenticated }
        let isKids = await MainActor.run { StorageService.shared.settings.isKidsProfile }
        
        // Kids profile: load only family-friendly content for the hero carousel
        if isKids {
            await loadKidsHeroItems()
            return
        }
        
        // Default behavior: use MDBList lists based on auth state
        // Only override if user has explicitly changed from the default
        if source == .trendingMovies {
            // Default source — use MDBList based on auth
            do {
                let listId = isAuthenticated
                    ? "dualipafan01/new-content-list"
                    : "dualipafan01/family-friendly-list"
                let items = try await MDBListService.shared.fetchListItemsAsMediaItems(listId: listId)
                if !items.isEmpty {
                    // Fetch more candidates to ensure we have enough after trailer filtering
                    let candidates = Array(items.prefix(20))
                    let withTrailers = await filterItemsWithTrailers(candidates)
                    if !withTrailers.isEmpty {
                        heroItems = Array(withTrailers.prefix(10))
                        ImagePrefetchService.shared.prefetchBackdrops(for: heroItems, size: .backdrop)
                        return
                    }
                    // If no trailers found, fall through to TMDB trending fallback
                }
            } catch {
                print("Error loading MDBList hero items: \(error)")
            }
            // Fallback to TMDB trending if MDBList fails or no trailers found
            do {
                let items = try await TMDBService.shared.getTrending(mediaType: .movie, timeWindow: "day").results
                let candidates = Array(items.prefix(20))
                let withTrailers = await filterItemsWithTrailers(candidates)
                heroItems = Array(withTrailers.prefix(10))
                ImagePrefetchService.shared.prefetchBackdrops(for: heroItems, size: .backdrop)
            } catch {
                print("Error loading fallback hero: \(error)")
            }
            return
        }
        
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
            case .customLists:
                await loadCustomListHeroItems()
                return
            case .mdblistPair:
                await loadMDBListPairHeroItems()
                return
            }
            // Filter to only items with trailers
            let candidates = Array(items.prefix(20))
            let withTrailers = await filterItemsWithTrailers(candidates)
            heroItems = Array(withTrailers.prefix(10))
            
            // Prefetch hero backdrop images
            ImagePrefetchService.shared.prefetchBackdrops(for: heroItems, size: .backdrop)
        } catch {
            print("Error loading hero: \(error)")
        }
    }

    private func loadCustomListHeroItems() async {
        let storage = StorageService.shared
        let lists = storage.customLists
        if lists.isEmpty {
            heroItems = []
            return
        }

        let movieList = lists.first(where: { $0.id == storage.settings.heroCarouselCustomMovieListId })
            ?? lists.first(where: { $0.items.contains(where: { $0.mediaType == .movie }) })
        let showList = lists.first(where: { $0.id == storage.settings.heroCarouselCustomShowListId })
            ?? lists.first(where: { $0.items.contains(where: { $0.mediaType == .tv }) })

        let movies = movieList?.items.filter { $0.mediaType == .movie }.map { $0.toMediaItem() } ?? []
        let shows = showList?.items.filter { $0.mediaType == .tv }.map { $0.toMediaItem() } ?? []

        let combined = await buildHeroPair(movies: movies, shows: shows)
        let withTrailers = await filterItemsWithTrailers(combined)
        heroItems = Array(withTrailers.prefix(10))
        ImagePrefetchService.shared.prefetchBackdrops(for: heroItems, size: .backdrop)
    }

    private func loadMDBListPairHeroItems() async {
        let storage = StorageService.shared
        var movies: [MediaItem] = []
        var shows: [MediaItem] = []

        await withTaskGroup(of: (Bool, [MediaItem]).self) { group in
            if let movieListId = storage.settings.heroCarouselMDBListMovieId, !movieListId.isEmpty {
                group.addTask {
                    do {
                        let items = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: movieListId)
                        let filtered = items.filter { $0.mediaType == .movie }.map { $0.toMediaItem() }
                        return (true, filtered)
                    } catch {
                        print("Error loading MDBList movies: \(error)")
                        return (true, [])
                    }
                }
            }

            if let showListId = storage.settings.heroCarouselMDBListShowId, !showListId.isEmpty {
                group.addTask {
                    do {
                        let items = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: showListId)
                        let filtered = items.filter { $0.mediaType == .tv }.map { $0.toMediaItem() }
                        return (false, filtered)
                    } catch {
                        print("Error loading MDBList shows: \(error)")
                        return (false, [])
                    }
                }
            }

            for await result in group {
                if result.0 {
                    movies = result.1
                } else {
                    shows = result.1
                }
            }
        }

        let combined = await buildHeroPair(movies: movies, shows: shows)
        let withTrailers = await filterItemsWithTrailers(combined)
        heroItems = Array(withTrailers.prefix(10))
        ImagePrefetchService.shared.prefetchBackdrops(for: heroItems, size: .backdrop)
    }

    private func buildHeroPair(movies: [MediaItem], shows: [MediaItem]) async -> [MediaItem] {
        var selectedMovies = Array(movies.prefix(5))
        var selectedShows = Array(shows.prefix(5))

        if selectedMovies.count < 5 {
            let needed = 5 - selectedMovies.count
            if let fallback = try? await TMDBService.shared.getTrending(mediaType: .movie, timeWindow: "day").results {
                appendUniqueItems(from: fallback, to: &selectedMovies, limit: 5, count: needed)
            }
        }

        if selectedShows.count < 5 {
            let needed = 5 - selectedShows.count
            if let fallback = try? await TMDBService.shared.getTrending(mediaType: .tv, timeWindow: "day").results {
                appendUniqueItems(from: fallback, to: &selectedShows, limit: 5, count: needed)
            }
        }

        return selectedMovies + selectedShows
    }

    private func appendUniqueItems(from items: [MediaItem], to target: inout [MediaItem], limit: Int, count: Int) {
        guard count > 0 else { return }
        for item in items {
            if target.count >= limit { break }
            let isDuplicate = target.contains { $0.id == item.id && $0.resolvedMediaType == item.resolvedMediaType }
            if !isDuplicate {
                target.append(item)
            }
        }
    }
    
    /// Loads hero carousel items specifically for kids profiles.
    /// Mixes popular family/kids movies and TV shows, sorted by popularity.
    private func loadKidsHeroItems() async {
        do {
            // Fetch kids movies and TV shows concurrently
            async let kidsMoviesTask = TMDBService.shared.discoverKidsMovies()
            async let kidsTVTask = TMDBService.shared.discoverKidsTV()
            
            let kidsMovies = try await kidsMoviesTask.results
            let kidsTV = try await kidsTVTask.results
            
            // Tag TV items with media_type so resolvedMediaType works correctly
            let taggedTV = kidsTV.map { item -> MediaItem in
                if item.mediaType == nil {
                    return MediaItem(
                        id: item.id,
                        title: item.title,
                        name: item.name,
                        originalTitle: item.originalTitle,
                        originalName: item.originalName,
                        overview: item.overview,
                        posterPath: item.posterPath,
                        backdropPath: item.backdropPath,
                        releaseDate: item.releaseDate,
                        firstAirDate: item.firstAirDate,
                        voteAverage: item.voteAverage,
                        voteCount: item.voteCount,
                        popularity: item.popularity,
                        genreIds: item.genreIds,
                        mediaType: "tv",
                        adult: item.adult,
                        originalLanguage: item.originalLanguage
                    )
                }
                return item
            }
            
            let taggedMovies = kidsMovies.map { item -> MediaItem in
                if item.mediaType == nil {
                    return MediaItem(
                        id: item.id,
                        title: item.title,
                        name: item.name,
                        originalTitle: item.originalTitle,
                        originalName: item.originalName,
                        overview: item.overview,
                        posterPath: item.posterPath,
                        backdropPath: item.backdropPath,
                        releaseDate: item.releaseDate,
                        firstAirDate: item.firstAirDate,
                        voteAverage: item.voteAverage,
                        voteCount: item.voteCount,
                        popularity: item.popularity,
                        genreIds: item.genreIds,
                        mediaType: "movie",
                        adult: item.adult,
                        originalLanguage: item.originalLanguage
                    )
                }
                return item
            }
            
            // Interleave: take top movies and TV, sort by popularity, pick top 10
            var combined = Array(taggedMovies.prefix(10)) + Array(taggedTV.prefix(10))
            combined.sort { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            
            // Deduplicate by ID
            var seen = Set<Int>()
            let unique = combined.filter { item in
                if seen.contains(item.id) { return false }
                seen.insert(item.id)
                return true
            }
            
            // Filter to only items with trailers
            let withTrailers = await filterItemsWithTrailers(Array(unique.prefix(20)))
            heroItems = Array(withTrailers.prefix(10))
            ImagePrefetchService.shared.prefetchBackdrops(for: heroItems, size: .backdrop)
        } catch {
            print("Error loading kids hero items: \(error)")
            // Fallback: try the family-friendly MDBList
            do {
                let items = try await MDBListService.shared.fetchListItemsAsMediaItems(listId: "dualipafan01/family-friendly-list")
                let withTrailers = await filterItemsWithTrailers(Array(items.prefix(20)))
                heroItems = Array(withTrailers.prefix(10))
                ImagePrefetchService.shared.prefetchBackdrops(for: heroItems, size: .backdrop)
            } catch {
                print("Kids hero fallback also failed: \(error)")
            }
        }
    }
    
    func refresh() async {
        // Wait for any in-flight load to finish to avoid clearing data mid-load
        while isLoading {
            try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s
        }

        // Keep current data visible while loading fresh data
        // Only clear if we successfully get new data in loadContent()
        await loadContent()
    }
    
    private func loadBrowseRows() async {
        let isKids = await MainActor.run { StorageService.shared.settings.isKidsProfile }
        
        // Kids profile: use dedicated kids-friendly rows instead of the user's config
        if isKids {
            await loadKidsBrowseRows()
            return
        }
        
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
    
    /// Loads browse rows with only kids-friendly content.
    /// Replaces all standard rows with curated kids categories.
    private func loadKidsBrowseRows() async {
        // Kids genre IDs: Animation = 16, Family = 10751 (movies & TV), Kids = 10762 (TV only)
        var loadedRows: [(Int, MediaRow)] = []
        
        await withTaskGroup(of: (Int, MediaRow?).self) { group in
            // Row 0: Kids Movies (popular family/animation movies, G/PG)
            group.addTask {
                do {
                    let response = try await TMDBService.shared.discoverKidsMovies()
                    let items = response.results
                    if !items.isEmpty {
                        ImagePrefetchService.shared.prefetchPosters(for: items)
                        return (0, MediaRow(title: "Kids Movies", items: items, people: []))
                    }
                } catch {
                    print("Error loading kids movies: \(error)")
                }
                return (0, nil)
            }
            
            // Row 1: Kids TV Shows (popular family/animation/kids TV)
            group.addTask {
                do {
                    let response = try await TMDBService.shared.discoverKidsTV()
                    let items = response.results
                    if !items.isEmpty {
                        ImagePrefetchService.shared.prefetchPosters(for: items)
                        return (1, MediaRow(title: "Kids TV Shows", items: items, people: []))
                    }
                } catch {
                    print("Error loading kids TV: \(error)")
                }
                return (1, nil)
            }
            
            // Row 2: Top Rated Family Movies
            group.addTask {
                do {
                    let region = await MainActor.run { StorageService.shared.settings.region }
                    let certRegion = ["US", "CA", "GB", "AU", "NZ", "DE", "FR"].contains(region) ? region : "US"
                    let response: TMDBResponse<MediaItem> = try await TMDBService.shared.discoverMovies(
                        genres: [10751],
                        sortBy: "vote_average.desc"
                    )
                    // Filter to only include items with decent vote count to avoid obscure titles
                    let items = response.results.filter { ($0.voteCount ?? 0) >= 100 }
                    if !items.isEmpty {
                        ImagePrefetchService.shared.prefetchPosters(for: items)
                        return (2, MediaRow(title: "Top Rated Family Movies", items: items, people: []))
                    }
                } catch {
                    print("Error loading top rated family movies: \(error)")
                }
                return (2, nil)
            }
            
            // Row 3: Animated TV Shows
            group.addTask {
                do {
                    let response = try await TMDBService.shared.discoverTV(genres: [16], sortBy: "popularity.desc")
                    // Filter to keep only clearly kids-friendly shows (exclude adult animation)
                    let kidsGenreIds: Set<Int> = [16, 10751, 10762]
                    let items = response.results.filter { item in
                        guard let genres = item.genreIds else { return true }
                        // Exclude if the show has genres commonly associated with adult animation
                        // (Crime=80, War=10768/10752, Drama=18 without Family/Kids)
                        let adultGenres: Set<Int> = [80, 10752, 10768]
                        let hasAdultGenre = !genres.filter { adultGenres.contains($0) }.isEmpty
                        let hasFamilyGenre = !genres.filter { kidsGenreIds.contains($0) }.isEmpty
                        if hasAdultGenre && !hasFamilyGenre { return false }
                        return true
                    }
                    if !items.isEmpty {
                        ImagePrefetchService.shared.prefetchPosters(for: items)
                        return (3, MediaRow(title: "Animated Shows", items: items, people: []))
                    }
                } catch {
                    print("Error loading animated TV: \(error)")
                }
                return (3, nil)
            }
            
            // Row 4: New Family Movies (recent releases)
            group.addTask {
                do {
                    let region = await MainActor.run { StorageService.shared.settings.region }
                    let certRegion = ["US", "CA", "GB", "AU", "NZ", "DE", "FR"].contains(region) ? region : "US"
                    let response = try await TMDBService.shared.discoverKidsMovies(page: 2)
                    let items = response.results
                    if !items.isEmpty {
                        ImagePrefetchService.shared.prefetchPosters(for: items)
                        return (4, MediaRow(title: "More Kids Movies", items: items, people: []))
                    }
                } catch {
                    print("Error loading new family movies: \(error)")
                }
                return (4, nil)
            }
            
            for await result in group {
                if let row = result.1 {
                    loadedRows.append((result.0, row))
                }
            }
        }
        
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var movies: [MediaItem] = []
    @State private var tvShows: [MediaItem] = []
    @State private var heroCarouselItems: [MediaItem] = []
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
                                .frame(height: ResponsiveSizing.hubLogoHeight(horizontalSizeClass: horizontalSizeClass))
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Tab picker
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("TV Shows").tag(1)
                }
                .pickerStyle(.segmented)
                .controlSize(horizontalSizeClass == .regular ? .small : .regular)
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 12)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if hub.name != "Disney+" && !heroCarouselItems.isEmpty {
                                ResizableHeroCarousel(items: heroCarouselItems) { item in
                                    selectedItem = item
                                    dismiss()
                                }
                            }

                            LazyVGrid(columns: [
                                GridItem(
                                    .adaptive(
                                        minimum: ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass),
                                        maximum: ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass) + 30
                                    ),
                                    spacing: 16
                                )
                            ], spacing: 16) {
                                let items = selectedTab == 0 ? movies : tvShows
                                ForEach(items) { item in
                                    MediaPosterCard(item: item)
                                        .onTapGesture {
                                            selectedItem = item
                                            dismiss()
                                        }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 12)
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
                self.heroCarouselItems = []
                self.isLoading = false
            }
            return
        }

        await MainActor.run { heroCarouselItems = [] }

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

// MARK: - Custom JSON Hubs Row (Network-style with image thumbnails)
struct CustomJSONHubsRow: View {
    let hubs: [CustomJSONHub]
    let onHubTap: (CustomJSONHub) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Hubs")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(hubs) { hub in
                        CustomJSONHubCard(hub: hub)
                            .onTapGesture {
                                onHubTap(hub)
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Custom JSON Hub Card (Network-style with image thumbnail)
struct CustomJSONHubCard: View {
    let hub: CustomJSONHub
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var resolvedColor: Color {
        if let hex = hub.brandColor, !hex.isEmpty {
            return Color(hex: hex)
        }
        return Color.orange
    }
    
    private var hasImage: Bool {
        if let imageURL = hub.imageURL, !imageURL.isEmpty { return true }
        return false
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background circle with brand color
                Circle()
                    .fill(resolvedColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
                    .frame(width: 68, height: 68)
                
                if hasImage, let imageURL = hub.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 58, height: 58)
                                .clipShape(Circle())
                        case .failure:
                            hubFallbackIcon
                        default:
                            ProgressView()
                                .frame(width: 58, height: 58)
                        }
                    }
                } else {
                    hubFallbackIcon
                }
                
                // Subtle border ring
                Circle()
                    .stroke(
                        resolvedColor.opacity(colorScheme == .dark ? 0.3 : 0.2),
                        lineWidth: 1.5
                    )
                    .frame(width: 68, height: 68)
            }
            .shadow(color: resolvedColor.opacity(0.25), radius: isPressed ? 2 : 5, y: isPressed ? 1 : 3)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            
            Text(hub.displayRowName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 72)
        }
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
    
    private var hubFallbackIcon: some View {
        ZStack {
            Circle()
                .fill(resolvedColor)
                .frame(width: 58, height: 58)
            
            Image(systemName: hub.source == .mdblist ? "list.star" : "doc.text.fill")
                .font(.title3)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        
        var rgb: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&rgb)
        
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Custom JSON Hub Sheet
struct CustomJSONHubSheet: View {
    let hub: CustomJSONHub
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var allItems: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    
    private var movies: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .movie }
    }
    
    private var tvShows: [SavedMediaItem] {
        allItems.filter { $0.mediaType == .tv }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header image or name
                if let imageURL = hub.imageURL, !imageURL.isEmpty, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 60)
                        default:
                            Text(hub.name)
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                    }
                    .padding(.vertical, 12)
                } else {
                    Text(hub.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.vertical, 12)
                }
                
                // Tab picker (only show if both types exist)
                if !movies.isEmpty && !tvShows.isEmpty {
                    Picker("Content Type", selection: $selectedTab) {
                        Text("Movies").tag(0)
                        Text("TV").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                
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
                    let items: [SavedMediaItem] = {
                        if movies.isEmpty && !tvShows.isEmpty { return tvShows }
                        if tvShows.isEmpty && !movies.isEmpty { return movies }
                        return selectedTab == 0 ? movies : tvShows
                    }()
                    
                    if items.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "film.stack")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No items found")
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
        
        // If items are already cached locally, use them
        if !hub.items.isEmpty {
            allItems = hub.items
            isLoading = false
            return
        }
        
        // Use the new resolvedMDBListIds which handles single/multi/legacy sources
        let listIds = hub.resolvedMDBListIds
        
        // Re-fetch from source
        do {
            if hub.source == .mdblist || !listIds.isEmpty {
                // MDBList source — fetch from all list IDs and merge
                if !listIds.isEmpty {
                    let items = try await MDBListService.shared.fetchMultipleListsAsSavedMedia(inputs: listIds)
                    allItems = items
                    await MainActor.run {
                        var updatedHub = hub
                        updatedHub.items = items
                        updatedHub.lastSynced = Date()
                        StorageService.shared.updateCustomJSONHub(updatedHub)
                    }
                } else {
                    error = "No MDBList ID found for this hub."
                }
            } else if !hub.jsonURL.isEmpty {
                // JSON URL source
                let result = try await JSONHubService.shared.fetchAndResolve(from: hub.jsonURL)
                allItems = result.items
                await MainActor.run {
                    var updatedHub = hub
                    updatedHub.items = result.items
                    updatedHub.lastSynced = Date()
                    StorageService.shared.updateCustomJSONHub(updatedHub)
                }
            } else {
                error = "No valid source URL found for this hub."
            }
            
            if allItems.isEmpty && error == nil {
                error = "No content found in this list."
            }
        } catch {
            self.error = "Failed to load content. Please try again."
            print("Custom hub load error for '\(hub.name)': \(error)")
        }
        
        isLoading = false
    }
}

#Preview {
    BrowseView(selectedItem: .constant(nil))
}
