//
//  BrowseTonightComponents.swift
//  WatchGuide-MovieandTVtracker
//
//  Browse pieces that tie the home feed to Tonight and Ticket Stubs: an
//  invitation into Tonight, a row of recent stubs, and the soft poster glow
//  behind the top of the page.
//

import SwiftUI

// MARK: - Tonight invitation

/// "Can't decide?" card with a small fan of posters. Tapping it opens Tonight.
struct TonightInviteCard: View {
    let posters: [MediaItem]

    var body: some View {
        Button {
            WatchGuideQuickRouteCenter.shared.open(.tonight)
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Can't Decide?")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Text("Tonight shows you one pick at a time. Swipe until something clicks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Open Tonight", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Reel.accent)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
                fan
            }
            .padding(18)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(WGPressButtonStyle())
        .accessibilityLabel("Can't decide? Open Tonight")
    }

    private var fan: some View {
        ZStack {
            ForEach(Array(posters.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                AsyncImageView(url: TMDBService.shared.imageURL(path: item.posterPath, size: .small), cornerRadius: 10)
                    .frame(width: 62, height: 93)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    .rotationEffect(.degrees(Double(index - 1) * 9), anchor: .bottom)
                    .offset(x: CGFloat(index - 1) * 18)
            }
        }
        .frame(width: 110, height: 104)
        .accessibilityHidden(true)
    }
}

// MARK: - Recent stubs row

struct RecentStubsRow: View {
    @ObservedObject private var store = TicketStubStore.shared
    @State private var showStubBox = false

    var body: some View {
        if !store.stubs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button { showStubBox = true } label: {
                    RowHeaderLabel(title: "Your Ticket Stubs")
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(store.stubs.prefix(10)) { stub in
                            StubCard(stub: stub)
                                .frame(width: 300)
                        }
                    }
                    .padding(.horizontal)
                }
                .scrollClipDisabled()
            }
            .sheet(isPresented: $showStubBox) {
                NavigationStack { StubBoxView() }
            }
        }
    }
}

/// The App Store / Apple TV style section header: a bold title with an inline
/// chevron that signals the whole title is tappable.
struct RowHeaderLabel: View {
    let title: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Top glow

/// A blurred wash of the featured artwork behind the top of a scrolling page,
/// fading into the system background.
struct TopArtworkGlow: View {
    let path: String?
    var height: CGFloat = 520
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AsyncImageView(url: TMDBService.shared.imageURL(path: path, size: .small), cornerRadius: 0)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .blur(radius: 70)
            .saturation(1.3)
            .opacity(colorScheme == .dark ? 0.5 : 0.3)
            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(.easeInOut(duration: 0.6), value: path)
    }
}
