//
//  HeroCarouselView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct HeroCarouselView: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    
    @State private var currentIndex = 0
    @State private var autoScrollTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    @Environment(\.colorScheme) private var colorScheme
    
    private var fadeColor: Color {
        colorScheme == .dark ? Color(UIColor.systemBackground) : Color(UIColor.systemBackground)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main carousel — edge-to-edge, no clip/round
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    GeometryReader { geometry in
                        HeroCarouselSlide(
                            item: item,
                            onTap: { onItemTap(item) },
                            geometry: geometry,
                            fadeColor: fadeColor
                        )
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Page indicators — overlaid at bottom
            HStack(spacing: 8) {
                ForEach(0..<min(items.count, 10), id: \.self) { index in
                    Capsule()
                        .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                        .frame(width: index == currentIndex ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentIndex)
                }
            }
            .padding(.bottom, 24)
        }
        .aspectRatio(16.0/10.0, contentMode: .fit)
        .onReceive(autoScrollTimer) { _ in
            guard items.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.9)) {
                currentIndex = (currentIndex + 1) % items.count
            }
        }
        .onChange(of: items.count) { _, newCount in
            if newCount == 0 {
                currentIndex = 0
            } else if currentIndex >= newCount {
                currentIndex = 0
            }
        }
    }
}

// MARK: - Hero Carousel Slide
struct HeroCarouselSlide: View {
    let item: MediaItem
    let onTap: () -> Void
    let geometry: GeometryProxy
    let fadeColor: Color
    
    private var slideWidth: CGFloat { geometry.size.width }
    private var slideHeight: CGFloat { geometry.size.height }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image — fills entire slide
            AsyncImage(url: TMDBService.shared.imageURL(path: item.backdropPath, size: .backdrop)) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay { ProgressView() }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "film")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        }
                @unknown default:
                    Rectangle().fill(Color(.systemGray5))
                }
            }
            .frame(width: slideWidth, height: slideHeight)
            .clipped()
            
            // Bottom fade into page background
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.3), location: 0.3),
                        .init(color: .black.opacity(0.65), location: 0.6),
                        .init(color: fadeColor.opacity(0.85), location: 0.85),
                        .init(color: fadeColor, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: slideHeight * 0.55)
            }
            .allowsHitTesting(false)
            
            // Content overlay
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                Text(item.displayTitle)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    if let year = item.year {
                        Text(year)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    if let rating = item.voteAverage, rating > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", rating))
                                .foregroundColor(.white)
                        }
                    }
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: slideWidth, height: slideHeight)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Array Extension
extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

#Preview {
    HeroCarouselView(items: [], onItemTap: { _ in })
}
