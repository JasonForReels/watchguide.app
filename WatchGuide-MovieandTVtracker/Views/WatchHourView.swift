//
//  WatchHourView.swift
//  WatchGuide-MovieandTVtracker
//
//  WatchHour — WatchGuide's unified tracking hub. A single place to see the
//  title you're currently watching, manage active sessions, review your
//  viewing history, statistics, streaks, and watch time. Now integrated with
//  TV Time for community insights and global trending data.
//

import SwiftUI

/// WatchHour hub page. Presented as its own tab; the enclosing navigation
/// container (from the TabView) provides the navigation bar.
struct WatchHourView: View {
    @ObservedObject private var storage = StorageService.shared
    @ObservedObject private var watchGuideTracking = WatchGuideTrackingService.shared
    @ObservedObject private var tvTime = TVTimeService.shared

    private let accent = Color(hex: "FF375F")
    @State private var selectedTrendingItem: TVTimeTrendingItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                headerCard
                
                // TV Time Community Insights
                TVTimeCommunityStatsView(
                    userProfile: tvTime.userProfile,
                    comparisonStats: tvTime.getComparisonStats()
                )
                .padding(.horizontal)

                if !watchGuideTracking.activeSessions.isEmpty {
                    section(title: "Watching Now", systemImage: "play.circle.fill") {
                        ForEach(watchGuideTracking.activeSessions) { session in
                            ActiveSessionCard(session: session, accent: accent)
                        }
                    }
                }

                if !watchGuideTracking.onHoldSessions.isEmpty {
                    section(title: "On Hold", systemImage: "pause.circle.fill") {
                        ForEach(watchGuideTracking.onHoldSessions) { session in
                            HeldSessionCard(session: session, accent: accent)
                        }
                    }
                }

                statsSection
                
                // TV Time Achievements
                if !tvTime.achievements.isEmpty {
                    section(title: "Your Achievements", systemImage: "trophy.fill") {
                        AchievementBadgesView(achievements: tvTime.achievements)
                    }
                }
                
                // TV Time Trending Carousel
                let allTrending = tvTime.trendingShows + tvTime.trendingMovies
                if !allTrending.isEmpty {
                    TVTimeTrendingCarouselView(
                        trendingItems: allTrending.sorted { $0.trendingRank < $1.trendingRank }
                    ) { item in
                        selectedTrendingItem = item
                        tvTime.recordTrendingInteraction(item: item, interaction: "view")
                    }
                    .padding(.horizontal)
                }

                if !watchGuideTracking.history.isEmpty {
                    section(title: "History", systemImage: "clock.arrow.circlepath") {
                        ForEach(watchGuideTracking.history.prefix(50)) { entry in
                            HistoryRow(entry: entry, accent: accent)
                        }
                    }
                }

                if watchGuideTracking.activeSessions.isEmpty
                    && watchGuideTracking.onHoldSessions.isEmpty
                    && watchGuideTracking.history.isEmpty
                    && tvTime.achievements.isEmpty {
                    emptyState
                }
            }
            .padding()
        }
        .background(Color.groupedBackground.ignoresSafeArea())
        .navigationTitle("WatchHour")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .onAppear {
            tvTime.syncUserProfileFromTracking()
            Task {
                if tvTime.trendingShows.isEmpty {
                    await tvTime.fetchTrendingShows()
                }
                if tvTime.trendingMovies.isEmpty {
                    await tvTime.fetchTrendingMovies()
                }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(accent)
                Text("Your entertainment journey")
                    .font(.headline)
            }
            Text("WatchHour tracks your viewing, compares you with the community, shows achievements, and brings trending entertainment to your fingertips.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Stats

    private var statsSection: some View {
        let stats = watchGuideTracking.stats
        return section(title: "Statistics", systemImage: "chart.bar.fill") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "Watch Time", value: stats.totalTimeFormatted, systemImage: "clock.fill", accent: accent)
                StatTile(title: "Current Streak", value: streakLabel(stats.currentStreakDays), systemImage: "flame.fill", accent: accent)
                StatTile(title: "Longest Streak", value: streakLabel(stats.longestStreakDays), systemImage: "trophy.fill", accent: accent)
                StatTile(title: "Titles Watched", value: "\(stats.totalSessions)", systemImage: "film.stack.fill", accent: accent)
                StatTile(title: "Movies", value: "\(stats.moviesWatched)", systemImage: "film.fill", accent: accent)
                StatTile(title: "Episodes", value: "\(stats.episodesWatched)", systemImage: "tv.fill", accent: accent)
            }
        }
    }

    private func streakLabel(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(accent)
            Text("No sessions yet")
                .font(.headline)
            Text("Tap Watch or Continue Watching on any title and WatchHour will start tracking here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Section Helper

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.bold))
            content()
        }
    }
}

// MARK: - Poster Thumbnail

struct PosterThumb: View {
    let path: String?
    var width: CGFloat = 60

    var body: some View {
        ResilientAsyncImage(url: TMDBService.shared.imageURL(path: path, size: .medium)) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
                    .overlay(Image(systemName: "film").foregroundStyle(.secondary))
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Active Session Card

struct ActiveSessionCard: View {
    let session: WatchSession
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                PosterThumb(path: session.posterPath)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(2)
                    if let code = session.episodeCode {
                        Text(code + (session.episodeTitle.map { " · \($0)" } ?? ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Label("Ends around \(session.expectedEndTime.formatted(date: .omitted, time: .shortened))",
                          systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(session.deviceName, systemImage: "tv.and.hifispeaker.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await WatchGuideTrackingService.shared.finish(session) }
                } label: {
                    Label("Finished", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)

                Button {
                    Task { await WatchGuideTrackingService.shared.stillWatching(session) }
                } label: {
                    Label("Still Watching", systemImage: "hourglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                WatchGuideTrackingService.shared.putOnHold(session)
            } label: {
                Label("Put on Hold", systemImage: "pause.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Held Session Card

struct HeldSessionCard: View {
    let session: WatchSession
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            PosterThumb(path: session.posterPath, width: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let code = session.episodeCode {
                    Text(code)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)

            Button {
                Task { await WatchGuideTrackingService.shared.resume(session) }
            } label: {
                Text("Resume")
            }
            .buttonStyle(.bordered)
            .tint(accent)

            Button(role: .destructive) {
                WatchGuideTrackingService.shared.dismissSession(session)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Stat Tile

private struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(accent)
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let entry: WatchHistoryEntry
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            PosterThumb(path: entry.posterPath, width: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let code = entry.episodeCode {
                        Text(code)
                    }
                    Text(entry.watchedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                StarRatingView(rating: entry.rating ?? 0, accent: accent) { newValue in
                    WatchGuideTrackingService.shared.rate(entry, rating: newValue)
                }
            }
            Spacer(minLength: 0)

            Text("\(entry.minutesWatched)m")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Star Rating

private struct StarRatingView: View {
    let rating: Int
    let accent: Color
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    onChange(star)
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(star <= rating ? accent : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
