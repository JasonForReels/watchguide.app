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

struct BrowseView: View {
    @StateObject private var viewModel = BrowseViewModel()
    @StateObject private var forYouVM = ForYouViewModel()
    @Binding var selectedItem: MediaItem?
    @State private var selectedNetworkHub: NetworkHub?
    @State private var selectedCompanyHub: CompanyHub?
    @State private var activeStudioSheet: StudioSheet?
    @State private var showCustomizeSheet = false
    @State private var showSettingsSheet = false
    @State private var showSettingsPage = false
    @State private var selectedPerson: Person?
    @State private var selectedJSONHub: CustomJSONHub?
    @State private var dailyPickCache: DailyPickCache?
    @State private var isDailyPickHidden = false
    @State private var selectedMiniGame: MiniGame?
    @State private var miniGameCandidates: [MediaItem] = []
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var profileService = ProfileService.shared
    
    enum StudioSheet: String, Identifiable {
        case disney
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
            #if os(macOS)
            .navigationDestination(isPresented: $showSettingsPage) {
                SettingsView()
            }
            #endif
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

        }
        .padding(.vertical)
    }
    
    @ViewBuilder
    private func browseSectionView(for section: BrowseSectionItem) -> some View {
        switch section.sectionType {
        case .networks:
            EmptyView()
        case .rows:
            browseRowsSection
        case .studios:
            StudiosHubRow(
                onDisneyTap: { activeStudioSheet = .disney }
            )
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
        #if os(iOS)
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
        case .disney:
            DisneyHubSheet(selectedItem: $selectedItem)
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
                .fill(Color.gray.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.gray.opacity(0.35).opacity(0.3), lineWidth: 0.5)
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
        .inlineNavTitleIfSupported()
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
                                        .fill(Color.gray.opacity(0.12))
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
                    .fill(Color.gray.opacity(0.12))
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
                    .fill(Color.gray.opacity(0.18))
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
                    .fill(Color.gray.opacity(0.18))
            }
        }
        .frame(width: 180, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.gray.opacity(0.35).opacity(0.3), lineWidth: 0.5)
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
        let measuredWidth = resolvedContainerWidth()
        let availableWidth = max(measuredWidth - 24, 1)
        let clampedRatio = max(minimumRatio, min(maximumRatio, layout.widthRatio))
        let width = availableWidth * clampedRatio
        
        ZStack {
            HeroCarouselView(
                items: items,
                onItemTap: onItemTap,
                aspectRatio: aspect.aspectRatio,
                isPortrait: aspect == .portrait
            )
            .frame(width: width)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    private func resolvedLayout() -> (widthRatio: Double, aspect: HeroCarouselAspect) {
        let profile = profileService.activeProfile
        let ratio = profile?.heroCarouselWidthRatio ?? 1.0
        let aspect = profile?.heroCarouselAspect ?? .landscape
        return (max(minimumRatio, min(maximumRatio, ratio)), aspect)
    }
    
    private func resolvedContainerWidth() -> CGFloat {
        #if canImport(UIKit)
        let windowWidth = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .bounds.width ?? 0
        if windowWidth > 0 {
            return windowWidth
        }
        #endif
        #if canImport(AppKit)
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 0
        if screenWidth > 0 {
            // Keep the hero prominent on Mac without letting it dominate the full viewport.
            return min(max(screenWidth * 0.6, 760), 920)
        }
        #endif
        return 820
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
            #if canImport(UIKit)
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
    let onDisneyTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Studios")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    DisneyStudioHubButton(action: onDisneyTap)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Disney Studio Hub Button (Liquid Glass)
struct DisneyStudioHubButton: View {
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) {
                ZStack {
                    Image("WaltDisneyPictures")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 54, height: 54)
                        .clipShape(Circle())
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
            
            Text("Disney")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Disney Hub Sheet (TMDB Company ID 2 — Walt Disney Pictures)
struct DisneyHubSheet: View {
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
                // Header with local asset logo
                Image("WaltDisneyPictures")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 64)
                    .padding(.vertical, 16)

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
                } else if let errorMessage {
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
                    .padding()
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
        errorMessage = nil

        do {
            async let movies = TMDBService.shared.discoverMoviesByCompany(companyIds: [2])
            async let tvShows = TMDBService.shared.discoverTVByCompany(companyIds: [2])
            movieItems = try await movies.results
            tvItems = try await tvShows.results
        } catch {
            errorMessage = "Failed to load Disney content. Please try again."
            print("DisneyHubSheet error: \(error)")
        }

        isLoading = false
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
            .scrollContentBackground(isIPad ? .hidden : .automatic)
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
                
                ToolbarItem(placement: .primaryAction) {
                    #if !os(macOS)
                    EditButton()
                    #endif
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

// MARK: - Browse Compatibility Layer
struct BrowseContentRow: Identifiable {
    let id = UUID()
    let title: String
    let items: [MediaItem]
    let people: [Person]
}

@MainActor
final class BrowseViewModel: ObservableObject {
    @Published var heroItems: [MediaItem] = []
    @Published var rows: [BrowseContentRow] = []

    private var hasLoaded = false

    func loadContent() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    func refresh() async {
        await loadHeroItems()
        await loadRows()
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
            }
        } catch {
            print("BrowseViewModel hero load error: \(error)")
            heroItems = []
        }

        if storage.settings.isKidsProfile {
            heroItems = heroItems.filter { $0.adult != true }
        }
        heroItems = Array(heroItems.prefix(25))
    }

    private func loadRows() async {
        let storage = StorageService.shared
        let configuredRows = storage.browseRows
            .filter(\.isEnabled)
            .sorted { $0.sortOrder < $1.sortOrder }

        var loadedRows: [BrowseContentRow] = []
        for rowConfig in configuredRows {
            do {
                let row = try await loadRow(rowConfig)
                loadedRows.append(row)
            } catch {
                print("BrowseViewModel row load error (\(rowConfig.title)): \(error)")
            }
        }
        rows = loadedRows
    }

    private func loadRow(_ rowConfig: BrowseRowConfig) async throws -> BrowseContentRow {
        switch rowConfig.endpoint {
        case .trendingMovies:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getTrending(mediaType: .movie).results, people: [])
        case .trendingTV:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getTrending(mediaType: .tv).results, people: [])
        case .trendingPeople:
            return BrowseContentRow(title: rowConfig.title, items: [], people: try await TMDBService.shared.getTrendingPeople().results)
        case .popularMovies:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getPopularMovies().results, people: [])
        case .popularTV:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getPopularTV().results, people: [])
        case .topRatedMovies:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getTopRatedMovies().results, people: [])
        case .topRatedTV:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getTopRatedTV().results, people: [])
        case .nowPlayingMovies:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getNowPlayingMovies().results, people: [])
        case .airingTodayTV:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getAiringTodayTV().results, people: [])
        case .upcomingMovies:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getUpcomingMovies().results, people: [])
        case .onTheAirTV:
            return BrowseContentRow(title: rowConfig.title, items: try await TMDBService.shared.getOnTheAirTV().results, people: [])
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
        let likedItems = StorageService.shared.liked
        guard !likedItems.isEmpty else {
            await loadFallback()
            return
        }

        do {
            let recommendations = try await AIService.shared.getForYouRecommendations(likedItems: likedItems)
            var resolved: [MediaItem] = []

            for recommendation in recommendations.prefix(10) {
                let result: TMDBResponse<MediaItem>
                if recommendation.mediaType.lowercased() == "tv" {
                    result = try await TMDBService.shared.searchTV(query: recommendation.title)
                } else {
                    result = try await TMDBService.shared.searchMovies(query: recommendation.title)
                }
                if let first = result.results.first(where: { $0.resolvedMediaType != .person }) {
                    resolved.append(first)
                }
            }

            let unique = deduplicated(resolved)
            if unique.isEmpty {
                await loadFallback()
            } else {
                items = Array(unique.prefix(20))
            }
        } catch {
            print("ForYouViewModel AI load error: \(error)")
            await loadFallback()
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

private extension View {
    @ViewBuilder
    func inlineNavTitleIfSupported() -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

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

// #Preview omitted for brevity
#Preview {
    BrowseView(selectedItem: .constant(nil))
}
