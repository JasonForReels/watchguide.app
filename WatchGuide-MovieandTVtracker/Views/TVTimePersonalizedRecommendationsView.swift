//
//  TVTimePersonalizedRecommendationsView.swift
//  WatchGuide-MovieandTVtracker
//
//  Shows personalized trending recommendations filtered by the user's
//  watch history preferences and viewing patterns.
//

import SwiftUI

struct TVTimePersonalizedRecommendationsView: View {
    @ObservedObject private var tvTimeService = TVTimeService.shared
    @State private var selectedItem: TVTimeTrendingItem?
    @State private var filterGenre: String = "All"
    
    private let accent = Color(hex: "FF375F")
    private var personalizedTrending: [TVTimeTrendingItem] {
        tvTimeService.getTrendingByUserPreferences()
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(accent)
                        Text("For You")
                            .font(.title2.weight(.bold))
                    }
                    Text("Trending based on your taste")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
                // Genre filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["All", "Shows", "Movies", "Action", "Drama", "Comedy"], id: \.self) { genre in
                            GenreFilterChip(
                                title: genre,
                                isSelected: filterGenre == genre,
                                accent: accent
                            ) {
                                filterGenre = genre
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Personalized grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(personalizedTrending.prefix(8)) { item in
                            PersonalizedRecommendationCard(item: item, accent: accent) {
                                selectedItem = item
                            }
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
            .background(Color.groupedBackground.ignoresSafeArea())
            .navigationTitle("Recommendations")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Genre Filter Chip

struct GenreFilterChip: View {
    let title: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isSelected ? accent : Color.secondaryGroupedBackground)
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}

// MARK: - Personalized Recommendation Card

struct PersonalizedRecommendationCard: View {
    let item: TVTimeTrendingItem
    let accent: Color
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image with badge
            ZStack(alignment: .topTrailing) {
                ResilientAsyncImage(url: TMDBService.shared.imageURL(path: item.posterPath, size: .medium)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: sharedPosterCornerRadius, style: .continuous))
                
                // Trending badge
                Image(systemName: "chart.line.uptrend")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .padding(8)
                    .background(Color.white.opacity(0.9), in: Circle())
                    .padding(8)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                
                // Type and rank
                HStack(spacing: 6) {
                    Text(item.mediaType.rawValue.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: "dot.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text("#\(item.trendingRank)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                }
                
                // Momentum
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(accent)
                    Text("Trending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer(minLength: 0)
                    
                    Text(item.reactions.topReaction)
                        .font(.caption)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondaryGroupedBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

#Preview {
    TVTimePersonalizedRecommendationsView()
}
