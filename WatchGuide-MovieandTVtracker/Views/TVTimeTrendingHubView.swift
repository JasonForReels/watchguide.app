//
//  TVTimeTrendingHubView.swift
//  WatchGuide-MovieandTVtracker
//
//  A dedicated hub showing trending shows, movies, and community insights.
//  Displays community reactions, top trending items, and personalized recommendations.
//

import SwiftUI

struct TVTimeTrendingHubView: View {
    @ObservedObject private var tvTimeService = TVTimeService.shared
    @State private var selectedItem: TVTimeTrendingItem?
    @State private var isRefreshing = false
    
    private let accent = Color(hex: "FF375F")
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(accent)
                            Text("TV Time Trending")
                                .font(.title2.weight(.bold))
                        }
                        Text("What's hot in the community")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    
                    // Shows Section
                    if !tvTimeService.trendingShows.isEmpty {
                        TrendingSection(
                            title: "Trending Shows",
                            icon: "tv.fill",
                            items: tvTimeService.trendingShows,
                            onItemTap: { selectedItem = $0 },
                            accent: accent
                        )
                    }
                    
                    // Movies Section
                    if !tvTimeService.trendingMovies.isEmpty {
                        TrendingSection(
                            title: "Trending Movies",
                            icon: "film.fill",
                            items: tvTimeService.trendingMovies,
                            onItemTap: { selectedItem = $0 },
                            accent: accent
                        )
                    }
                    
                    // Loading state
                    if tvTimeService.isLoadingTrending {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading trending...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                    
                    // Error state
                    if let error = tvTimeService.trendingError {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            Text("Couldn't load trending")
                                .font(.subheadline.weight(.semibold))
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding()
            }
            .background(Color.groupedBackground.ignoresSafeArea())
            .refreshable {
                isRefreshing = true
                await tvTimeService.fetchTrendingShows(forceRefresh: true)
                await tvTimeService.fetchTrendingMovies(forceRefresh: true)
                isRefreshing = false
            }
            .onAppear {
                if tvTimeService.trendingShows.isEmpty {
                    Task {
                        await tvTimeService.fetchTrendingShows()
                        await tvTimeService.fetchTrendingMovies()
                    }
                }
            }
        }
    }
}

// MARK: - Trending Section

struct TrendingSection: View {
    let title: String
    let icon: String
    let items: [TVTimeTrendingItem]
    let onItemTap: (TVTimeTrendingItem) -> Void
    let accent: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.bold))
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items.prefix(10)) { item in
                        TrendingHubCard(item: item, accent: accent, onTap: onItemTap)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Trending Hub Card

struct TrendingHubCard: View {
    let item: TVTimeTrendingItem
    let accent: Color
    let onTap: (TVTimeTrendingItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Poster with rank overlay
            ZStack(alignment: .topLeading) {
                ResilientAsyncImage(url: TMDBService.shared.imageURL(path: item.posterPath, size: .medium)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.3))
                            .overlay(Image(systemName: "film").foregroundStyle(.secondary))
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: sharedPosterCornerRadius, style: .continuous))
                
                // Rank badge
                ZStack(alignment: .center) {
                    Circle()
                        .fill(accent)
                    Text("#\(item.trendingRank)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                .padding(8)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                
                // Momentum
                HStack(spacing: 4) {
                    ForEach(0..<item.momentum, id: \.self) { _ in
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(accent)
                    }
                    Spacer(minLength: 0)
                }
                
                // Top reaction
                HStack(spacing: 4) {
                    Text(item.reactions.topReaction)
                    Text(String(item.reactions.total < 1000 ? item.reactions.total : item.reactions.total / 1000) + (item.reactions.total >= 1000 ? "k" : ""))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondaryGroupedBackground)
        }
        .frame(width: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap(item)
        }
    }
}

#Preview {
    TVTimeTrendingHubView()
}
