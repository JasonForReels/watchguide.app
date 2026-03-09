//
//  DiscoverView.swift
//  WatchGuide-MovieandTVtracker
//
//  Central hub for all discovery features: Mood, Random Pick, Countdown, Decade Explorer, Stats
//

import SwiftUI

struct DiscoverView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var selectedItem: MediaItem?
    
    var body: some View {
        NavigationStack {
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
                    }
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
        }
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

// MARK: - Feature Card (Liquid Glass — iOS 26 SDK)
struct DiscoverFeatureCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let accentColor: Color
    let isLarge: Bool
    
    @State private var isPressed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 12 : 8) {
            Image(systemName: iconName)
                .font(isLarge ? .title : .title3)
                .foregroundColor(accentColor)
            
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
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
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

#Preview {
    DiscoverView()
}
