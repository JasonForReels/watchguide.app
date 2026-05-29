//
//  MoreHubView.swift
//  WatchGuide-MovieandTVtracker
//
//  A hub view for the "More" tab, featuring buttons for Lists, Friends, Settings, etc.
//  Styled like the Discovery page.
//

import SwiftUI

struct MoreHubView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var storage = StorageService.shared
    
    // MARK: - Platform-Aware Layout Values
    
    private var sectionSpacing: CGFloat {
        #if os(tvOS)
        48
        #else
        28
        #endif
    }
    
    private var cardSpacing: CGFloat {
        #if os(tvOS)
        28
        #else
        14
        #endif
    }
    
    private var horizontalInset: CGFloat {
        #if os(tvOS)
        80
        #else
        16
        #endif
    }
    
    private var topPadding: CGFloat {
        #if os(tvOS)
        24
        #else
        8
        #endif
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: sectionSpacing) {
                featureCards
                
                quickStatsRow
                
                appInfo
                
                Spacer(minLength: 40)
            }
            .padding(.top, topPadding)
        }
        .navigationTitle("More")
    }

    @ViewBuilder
    private var featureCards: some View {
        VStack(spacing: cardSpacing) {
            // Friends / Social - Hero card
            NavigationLink {
                FriendsActivityView()
            } label: {
                MoreFeatureCard(
                    title: "Friends & Social",
                    subtitle: "Follow friends, see activity, and host parties",
                    iconName: "person.2.fill",
                    accentColor: .blue,
                    isLarge: true
                )
            }
            .buttonStyle(.plain)
            
            HStack(spacing: cardSpacing) {
                // Lists
                NavigationLink {
                    ListsView()
                } label: {
                    MoreFeatureCard(
                        title: "My Lists",
                        subtitle: "\(storage.watched.count + storage.wantToWatch.count + storage.liked.count) items",
                        iconName: "list.bullet.below.rectangle",
                        accentColor: .green,
                        isLarge: false
                    )
                }
                .buttonStyle(.plain)
                
                // Watch Parties
                NavigationLink {
                    WatchPartyView()
                } label: {
                    MoreFeatureCard(
                        title: "Watch Parties",
                        subtitle: "Watch together",
                        iconName: "popcorn.fill",
                        accentColor: .orange,
                        isLarge: false
                    )
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: cardSpacing) {
                // Settings
                NavigationLink {
                    SettingsView()
                } label: {
                    MoreFeatureCard(
                        title: "Settings",
                        subtitle: "App & sync options",
                        iconName: "gearshape.fill",
                        accentColor: .gray,
                        isLarge: false
                    )
                }
                .buttonStyle(.plain)
                
                // Account / Profile
                NavigationLink {
                    accountDestination
                } label: {
                    MoreFeatureCard(
                        title: authService.isAuthenticated ? "Account" : "Sign In",
                        subtitle: authService.isAuthenticated ? (authService.currentUser?.email ?? "Profile") : "Sync your data",
                        iconName: "person.crop.circle.fill",
                        accentColor: .purple,
                        isLarge: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, horizontalInset)
    }

    @ViewBuilder
    private var appInfo: some View {
        VStack(spacing: 8) {
            Text("WatchGuide")
                #if os(tvOS)
                .font(.title3)
                #else
                .font(.headline)
                #endif
                .foregroundColor(.secondary)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                #if os(tvOS)
                .font(.callout)
                #else
                .font(.caption2)
                #endif
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 20)
    }
    
    @ViewBuilder
    private var accountDestination: some View {
        if authService.isAuthenticated {
            SettingsView(displayMode: .accountOnly)
        } else {
            AuthView()
        }
    }
    
    // MARK: - Quick Stats Row
    private var quickStatsRow: some View {
        VStack(alignment: .leading, spacing: statsHeaderSpacing) {
            Text("Your Pulse")
                .font(statsSectionTitleFont)
                .fontWeight(.bold)
                .padding(.horizontal, horizontalInset)
            
            #if os(tvOS)
            HStack(spacing: cardSpacing) {
                MoreStatPill(
                    label: "Watched",
                    value: "\(storage.watched.count)",
                    iconName: "checkmark.circle.fill",
                    color: .green
                )
                
                MoreStatPill(
                    label: "Watchlist",
                    value: "\(storage.wantToWatch.count)",
                    iconName: "bookmark.fill",
                    color: .blue
                )
                
                MoreStatPill(
                    label: "Liked",
                    value: "\(storage.liked.count)",
                    iconName: "heart.fill",
                    color: .red
                )
            }
            .padding(.horizontal, horizontalInset)
            #else
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    MoreStatPill(
                        label: "Watched",
                        value: "\(storage.watched.count)",
                        iconName: "checkmark.circle.fill",
                        color: .green
                    )
                    
                    MoreStatPill(
                        label: "Watchlist",
                        value: "\(storage.wantToWatch.count)",
                        iconName: "bookmark.fill",
                        color: .blue
                    )
                    
                    MoreStatPill(
                        label: "Liked",
                        value: "\(storage.liked.count)",
                        iconName: "heart.fill",
                        color: .red
                    )
                }
                .padding(.horizontal)
            }
            #endif
        }
    }
    
    private var statsSectionTitleFont: Font {
        #if os(tvOS)
        .title2
        #else
        .title3
        #endif
    }
    
    private var statsHeaderSpacing: CGFloat {
        #if os(tvOS)
        20
        #else
        12
        #endif
    }
}

// MARK: - Feature Card
struct MoreFeatureCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let accentColor: Color
    let isLarge: Bool
    @Environment(\.isFocused) private var isFocused
    
    private var iconFont: Font {
        #if os(tvOS)
        isLarge ? .largeTitle : .title
        #else
        isLarge ? .title : .title3
        #endif
    }
    
    private var titleFont: Font {
        #if os(tvOS)
        isLarge ? .title2 : .title3
        #else
        isLarge ? .title3 : .subheadline
        #endif
    }
    
    private var subtitleFont: Font {
        #if os(tvOS)
        .callout
        #else
        .caption
        #endif
    }
    
    private var iconPadding: CGFloat {
        #if os(tvOS)
        isLarge ? 18 : 14
        #else
        10
        #endif
    }
    
    private var cardPadding: CGFloat {
        #if os(tvOS)
        isLarge ? 36 : 28
        #else
        isLarge ? 20 : 16
        #endif
    }
    
    private var innerSpacing: CGFloat {
        #if os(tvOS)
        isLarge ? 18 : 14
        #else
        isLarge ? 12 : 8
        #endif
    }
    
    private var cardCornerRadius: CGFloat {
        #if os(tvOS)
        24
        #else
        18
        #endif
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: innerSpacing) {
            Image(systemName: iconName)
                .font(iconFont)
                .foregroundStyle(accentColor.gradient)
                .padding(iconPadding)
                .background(.clear)
                .glassEffect(.regular, in: .circle)
                .shadow(color: accentColor.opacity(0.3), radius: 5, y: 2)
            
            Text(title)
                .font(titleFont)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            
            Text(subtitle)
                .font(subtitleFont)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(tvOS)
        .frame(minHeight: isLarge ? 180 : 140)
        #endif
        .padding(cardPadding)
        .contentShape(Rectangle())
        #if os(tvOS)
        .tvOSPanelStyle(
            cornerRadius: cardCornerRadius,
            fillOpacity: isFocused ? 0.12 : 0.08,
            strokeOpacity: isFocused ? 0.24 : 0.12
        )
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        #else
        .modifier(LiquidGlassRoundedRect(cornerRadius: cardCornerRadius))
        #endif
    }
}

// MARK: - Stat Pill
struct MoreStatPill: View {
    let label: String
    let value: String
    let iconName: String
    let color: Color
    
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #endif
    
    var body: some View {
        #if os(tvOS)
        VStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            
            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .tvOSPanelStyle(
            cornerRadius: 20,
            fillOpacity: isFocused ? 0.12 : 0.08,
            strokeOpacity: isFocused ? 0.20 : 0.10
        )
        .scaleEffect(isFocused ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        #else
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
        #endif
    }
}

#Preview {
    MoreHubView()
}
