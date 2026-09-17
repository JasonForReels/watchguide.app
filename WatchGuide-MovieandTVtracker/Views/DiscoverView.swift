//
//  DiscoverView.swift
//  WatchGuide-MovieandTVtracker
//
//  Central hub for all discovery features: Mood, Random Pick, Countdown, Decade Explorer, Stats
//

import SwiftUI

struct DiscoverView: View {
    @ObservedObject private var storage = StorageService.shared
    @ObservedObject private var subscription = ScoutSubscriptionService.shared
    @State private var selectedItem: MediaItem?
    @State private var showStatsPaywall = false
    
    var body: some View {
        ScrollView {
                VStack(spacing: 28) {
                    // Feature Cards
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
                        .buttonStyle(DiscoverFeatureButtonStyle())
                        
                        // Did You Know? – Franchise Trivia
                        NavigationLink(destination: DidYouKnowView()) {
                            DiscoverFeatureCard(
                                title: "Did You Know?",
                                subtitle: "Legends & lore from the MCU and more",
                                iconName: "sparkles.tv.fill",
                                accentColor: .yellow,
                                isLarge: true
                            )
                        }
                        .buttonStyle(DiscoverFeatureButtonStyle())
                        
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
                            .buttonStyle(DiscoverFeatureButtonStyle())
                            
                            NavigationLink(destination: CountdownCalendarView()) {
                                DiscoverFeatureCard(
                                    title: "Countdown",
                                    subtitle: "Upcoming release dates",
                                    iconName: "calendar.badge.clock",
                                    accentColor: .green,
                                    isLarge: false
                                )
                            }
                            .buttonStyle(DiscoverFeatureButtonStyle())
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
                            .buttonStyle(DiscoverFeatureButtonStyle())
                            
                            if subscription.isPlusActive {
                                NavigationLink(destination: StatsInsightsView()) {
                                    DiscoverFeatureCard(
                                        title: "My Stats",
                                        subtitle: "Your watching insights",
                                        iconName: "chart.bar.fill",
                                        accentColor: .blue,
                                        isLarge: false
                                    )
                                }
                                .buttonStyle(DiscoverFeatureButtonStyle())
                            } else {
                                Button {
                                    showStatsPaywall = true
                                } label: {
                                    DiscoverFeatureCard(
                                        title: "My Stats",
                                        subtitle: "Pro",
                                        iconName: "chart.bar.fill",
                                        accentColor: .blue.opacity(0.5),
                                        isLarge: false
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: "lock.fill")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(8)
                                    }
                                }
                                .buttonStyle(DiscoverFeatureButtonStyle())
                                .sheet(isPresented: $showStatsPaywall) {
                                    WGSubscriptionPaywallView(context: .plus)
                                }
                            }
                        }
                        
                        HStack(spacing: 14) {
                            #if !os(tvOS)
                            NavigationLink(destination: AIRecommendView()) {
                                DiscoverFeatureCard(
                                    title: "AI Recommendations",
                                    subtitle: "Get personalized picks from AI assistants",
                                    iconName: "brain.head.profile.fill",
                                    accentColor: Color(.systemGray),
                                    isLarge: false
                                )
                            }
                            .buttonStyle(DiscoverFeatureButtonStyle())
                            #endif

                            NavigationLink(destination: BoxOfficeCinemaSelectorView()) {
                                DiscoverFeatureCard(
                                    title: "Box Office",
                                    subtitle: "Find your nearest cinema",
                                    iconName: "ticket.fill",
                                    accentColor: .red,
                                    isLarge: false
                                )
                            }
                            .buttonStyle(DiscoverFeatureButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    
                    // Affiliate banner
                    RemoteBannerView(placement: .discover)
                        .padding(.horizontal)
                    
                    // Quick Stats Row
                    if storage.watched.count > 0 || storage.liked.count > 0 {
                        quickStatsRow
                    }
                    
                    // Collections
                    if !PopularTMDBCollection.popular.isEmpty {
                        collectionsSection
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Discover")
            .mediaDetailPresentation(item: $selectedItem)
        }
    
    // MARK: - Quick Stats Row
    private var quickStatsRow: some View {
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
    
    // MARK: - Collections Section
    private var collectionsSection: some View {
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
}

// MARK: - Feature Card Button Style
struct DiscoverFeatureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Feature Card (Liquid Glass — iOS 26 SDK)
struct DiscoverFeatureCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let accentColor: Color
    let isLarge: Bool
    
    @State private var appeared = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 12 : 8) {
            Image(systemName: iconName)
                .font(isLarge ? .title : .title3)
                .foregroundColor(accentColor)
                .symbolEffect(.bounce, value: appeared)
            
            Text(title)
                .font(isLarge ? .title3 : .subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isLarge ? 20 : 16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appeared = true
            }
        }
    }
}

// MARK: - Quick Stat Pill (Liquid Glass — iOS 26 SDK)
struct QuickStatPill: View {
    let label: String
    let value: String
    let iconName: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.subheadline)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}

private struct DiscoverTrailerCountdownEntry: Identifiable {
    let id: String
    let item: CountdownItem
    let trailer: Video?
}

private struct DiscoverRaceBarEntry: Identifiable {
    let id: String
    let entry: DiscoverTrailerCountdownEntry
    let score: Double
    let rank: Int
}

private struct DiscoverRaceSnapshot: Identifiable {
    let id: Int
    let date: Date
    let bars: [DiscoverRaceBarEntry]
    let maxScore: Double

    var leader: DiscoverRaceBarEntry? {
        bars.first
    }
}

@MainActor
private final class DiscoverTrailerCountdownViewModel: ObservableObject {
    @Published private(set) var entries: [DiscoverTrailerCountdownEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var snapshots: [DiscoverRaceSnapshot] = []
    @Published var currentFrameIndex = 0

    let autoAdvanceDuration: TimeInterval = 0.95

    private var autoAdvanceTask: Task<Void, Never>?

    deinit {
        autoAdvanceTask?.cancel()
    }

    func loadIfNeeded() async {
        guard entries.isEmpty, !isLoading else {
            resumeAutoAdvance()
            return
        }

        isLoading = true
        let upcoming = await CountdownDataLoader.loadUpcomingItems()
        let rankedItems = Array(
            upcoming
                .sorted { lhs, rhs in
                    let lhsPopularity = lhs.mediaItem.popularity ?? 0
                    let rhsPopularity = rhs.mediaItem.popularity ?? 0
                    if lhsPopularity == rhsPopularity {
                        return lhs.releaseDate < rhs.releaseDate
                    }
                    return lhsPopularity > rhsPopularity
                }
                .prefix(10)
        )

        let loadedEntries = await withTaskGroup(of: (Int, DiscoverTrailerCountdownEntry).self, returning: [DiscoverTrailerCountdownEntry].self) { group in
            for (index, item) in rankedItems.enumerated() {
                group.addTask {
                    let trailer = await Self.loadPreferredTrailer(for: item)
                    return (index, DiscoverTrailerCountdownEntry(id: item.id, item: item, trailer: trailer))
                }
            }

            var ordered: [(Int, DiscoverTrailerCountdownEntry)] = []
            for await result in group {
                ordered.append(result)
            }
            return ordered
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }

        entries = loadedEntries
        snapshots = Self.buildSnapshots(from: loadedEntries)
        currentFrameIndex = 0
        isLoading = false
        resumeAutoAdvance()
    }

    func select(frame index: Int) {
        guard snapshots.indices.contains(index) else { return }
        currentFrameIndex = index
        resumeAutoAdvance()
    }

    func resumeAutoAdvance() {
        autoAdvanceTask?.cancel()
        guard snapshots.count > 1 else { return }

        autoAdvanceTask = Task { [weak self] in
            while !Task.isCancelled {
                let durationSeconds = self?.autoAdvanceDuration ?? 8
                try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.advance()
                }
            }
        }
    }

    func pauseAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
    }

    private func advance() {
        guard !snapshots.isEmpty else { return }
        currentFrameIndex = (currentFrameIndex + 1) % snapshots.count
    }

    private static func loadPreferredTrailer(for item: CountdownItem) async -> Video? {
        do {
            let response: VideosResponse
            switch item.mediaType {
            case .movie:
                response = try await TMDBService.shared.getMovieVideos(id: item.mediaItem.id)
            case .tv:
                response = try await TMDBService.shared.getTVShowVideos(id: item.mediaItem.id)
            case .person:
                return nil
            }
            return selectPreferredTrailer(from: response.results)
        } catch {
            return nil
        }
    }

    private static func selectPreferredTrailer(from videos: [Video]) -> Video? {
        if let directTrailer = videos.first(where: {
            $0.site.lowercased() == "direct"
                && ($0.type.lowercased() == "trailer" || $0.type.lowercased() == "teaser")
        }) {
            return directTrailer
        }

        let youtubeTrailers = videos.filter {
            let type = $0.type.lowercased()
            return $0.site.lowercased() == "youtube" && (type == "trailer" || type == "teaser")
        }

        let officialTrailer = youtubeTrailers.first {
            $0.type.lowercased() == "trailer" && ($0.official == true)
        }
        if let officialTrailer {
            return officialTrailer
        }

        let officialTeaser = youtubeTrailers.first {
            $0.type.lowercased() == "teaser" && ($0.official == true)
        }
        if let officialTeaser {
            return officialTeaser
        }

        return youtubeTrailers.first
    }

    private static func buildSnapshots(from entries: [DiscoverTrailerCountdownEntry]) -> [DiscoverRaceSnapshot] {
        guard !entries.isEmpty else { return [] }

        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let furthestDate = entries.map(\.item.releaseDate).max() ?? startDate
        let totalDays = max(calendar.dateComponents([.day], from: startDate, to: furthestDate).day ?? 0, 1)
        let frameCount = min(max(totalDays + 1, 20), 44)
        let maxPopularity = max(entries.map { $0.item.mediaItem.popularity ?? 1 }.max() ?? 1, 1)

        return (0..<frameCount).map { frameIndex in
            let progress = frameCount == 1 ? 1 : Double(frameIndex) / Double(frameCount - 1)
            let currentDate = startDate.addingTimeInterval(TimeInterval(totalDays) * 86_400 * progress)

            let rankedBars = entries
                .map { entry -> DiscoverRaceBarEntry in
                    let score = score(for: entry, at: currentDate, startDate: startDate)
                    return DiscoverRaceBarEntry(id: entry.id, entry: entry, score: score, rank: 0)
                }
                .sorted { lhs, rhs in
                    if lhs.score == rhs.score {
                        return lhs.entry.item.releaseDate < rhs.entry.item.releaseDate
                    }
                    return lhs.score > rhs.score
                }
                .enumerated()
                .map { offset, bar in
                    DiscoverRaceBarEntry(
                        id: bar.id,
                        entry: bar.entry,
                        score: bar.score,
                        rank: offset + 1
                    )
                }

            return DiscoverRaceSnapshot(
                id: frameIndex,
                date: currentDate,
                bars: rankedBars,
                maxScore: maxPopularity
            )
        }
    }

    private static func score(
        for entry: DiscoverTrailerCountdownEntry,
        at currentDate: Date,
        startDate: Date
    ) -> Double {
        let rawPopularity = max(entry.item.mediaItem.popularity ?? 1, 1)
        let total = max(entry.item.releaseDate.timeIntervalSince(startDate), 86_400)
        let elapsed = min(max(currentDate.timeIntervalSince(startDate), 0), total)
        let progress = elapsed / total
        let eased = pow(progress, 0.72)
        return rawPopularity * eased
    }
}

private struct DiscoverTrailerCountdownSection: View {
    let onItemTap: (MediaItem) -> Void

    @StateObject private var viewModel = DiscoverTrailerCountdownViewModel()
    @Environment(\.scenePhase) private var scenePhase

    private var currentSnapshot: DiscoverRaceSnapshot? {
        guard viewModel.snapshots.indices.contains(viewModel.currentFrameIndex) else { return nil }
        return viewModel.snapshots[viewModel.currentFrameIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Now Trending in Theaters and Streaming")
                        .font(.title3.weight(.black))

                    Text("An animated release race with live trailers, shifting ranks, and a rolling timeline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink(destination: CountdownCalendarView()) {
                    Label("See All", systemImage: "calendar.badge.clock")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            Group {
                if viewModel.isLoading {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay {
                            ProgressView("Loading trailers...")
                                .foregroundStyle(.secondary)
                        }
                } else if let snapshot = currentSnapshot {
                    Button {
                        if let leader = snapshot.leader {
                            onItemTap(leader.entry.item.mediaItem)
                        }
                    } label: {
                        DiscoverTrailerRaceCard(
                            snapshot: snapshot,
                            timelineProgress: timelineProgress,
                            onBarTap: { item in
                                onItemTap(item)
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !viewModel.snapshots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(viewModel.snapshots.enumerated()), id: \.element.id) { index, snapshot in
                            Button {
                                viewModel.select(frame: index)
                            } label: {
                                Text(snapshot.date.discoverRaceAxisLabel)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(index == viewModel.currentFrameIndex ? .white : .secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(index == viewModel.currentFrameIndex ? Color.white.opacity(0.28) : Color.white.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onAppear {
            viewModel.resumeAutoAdvance()
        }
        .onDisappear {
            viewModel.pauseAutoAdvance()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.resumeAutoAdvance()
            } else {
                viewModel.pauseAutoAdvance()
            }
        }
    }

    private var timelineProgress: Double {
        guard viewModel.snapshots.count > 1 else { return 1 }
        return Double(viewModel.currentFrameIndex) / Double(viewModel.snapshots.count - 1)
    }
}

private struct DiscoverTrailerRaceCard: View {
    let snapshot: DiscoverRaceSnapshot
    let timelineProgress: Double
    let onBarTap: (MediaItem) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            mediaBackdrop

            LinearGradient(
                colors: [
                    .black.opacity(0.28),
                    .black.opacity(0.48),
                    .black.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CINEMATIC RACE")
                            .font(.caption2.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.72))

                        Text("Moving chart, live trailer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Spacer()

                    Text(snapshot.date.discoverRaceHeadline)
                        .font(.title3.weight(.black))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    if snapshot.leader?.entry.trailer != nil {
                        Label("Trailer Live", systemImage: "play.rectangle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.35), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }

                if let leader = snapshot.leader {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(leader.entry.item.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: 10) {
                            Label(leader.entry.item.countdownText, systemImage: "timer")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)

                            Text(leader.entry.item.releaseDateFormatted)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))

                            Text("Score \(Int(leader.score.rounded()))")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .monospacedDigit()
                        }
                    }
                }

                VStack(spacing: 10) {
                    ForEach(snapshot.bars) { bar in
                        DiscoverRaceBarRow(
                            bar: bar,
                            maxScore: snapshot.maxScore,
                            isLeader: bar.rank == 1,
                            onTap: {
                                onBarTap(bar.entry.item.mediaItem)
                            }
                        )
                    }
                }
                .padding(16)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                DiscoverRaceTimelineAxis(progress: timelineProgress, currentLabel: snapshot.date.discoverRaceAxisLabel)
            }
            .padding(22)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 10)
        .animation(.snappy(duration: 0.45), value: snapshot.id)
    }

    @ViewBuilder
    private var mediaBackdrop: some View {
        if let trailer = snapshot.leader?.entry.trailer {
            EmbeddedTrailerPlayer(
                videoKey: trailer.key,
                title: snapshot.leader?.entry.item.title ?? "Trailer",
                compact: false,
                autoPlay: true,
                showsControls: false,
                loops: true,
                aspectRatio: 16.0 / 9.0,
                contentMode: .fill,
                cornerRadius: 24
            )
            .allowsHitTesting(false)
        } else {
            ResilientAsyncImage(url: TMDBService.shared.imageURL(path: snapshot.leader?.entry.item.mediaItem.backdropPath, size: .backdrop)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.55),
                            Color.black.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private struct DiscoverRaceBarRow: View {
    let bar: DiscoverRaceBarEntry
    let maxScore: Double
    let isLeader: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text("#\(bar.rank)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(isLeader ? 1 : 0.7))
                    .frame(width: 28, alignment: .leading)

                PosterImageView(
                    posterPath: bar.entry.item.mediaItem.posterPath,
                    backdropPath: bar.entry.item.mediaItem.backdropPath,
                    size: .small,
                    mediaId: bar.entry.item.mediaItem.id,
                    mediaType: bar.entry.item.mediaType
                )
                .frame(width: 26, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(bar.entry.item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: isLeader
                                        ? [Color.orange, Color.yellow]
                                        : [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.45)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * barWidthRatio)
                    }
                }
                .frame(height: 18)

                Text("\(Int(bar.score.rounded()))")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 44, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var barWidthRatio: CGFloat {
        guard maxScore > 0 else { return 0 }
        return CGFloat(bar.score / maxScore)
    }
}

private struct DiscoverRaceTimelineAxis: View {
    let progress: Double
    let currentLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Text(currentLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))

                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: geometry.size.width * CGFloat(progress))
                }
            }
            .frame(height: 4)
        }
    }
}

private extension Date {
    var discoverRaceHeadline: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: self)
    }

    var discoverRaceAxisLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: self)
    }
}

#Preview {
    DiscoverView()
}
