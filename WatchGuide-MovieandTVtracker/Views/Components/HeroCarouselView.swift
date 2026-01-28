//
//  HeroCarouselView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct HeroCarouselView: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    
    @State private var currentIndex = 0
    @State private var timer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background blur
                if let currentItem = items[safe: currentIndex] {
                    BackdropImageView(backdropPath: currentItem.backdropPath)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 30)
                        .opacity(0.5)
                }
                
                // Main carousel
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HeroSlideView(item: item, width: geometry.size.width)
                            .tag(index)
                            .onTapGesture {
                                onItemTap(item)
                            }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<min(items.count, 10), id: \.self) { index in
                        Capsule()
                            .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                            .frame(width: index == currentIndex ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.3), value: currentIndex)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .frame(height: 400)
        .onAppear {
            startAutoScroll()
        }
        .onDisappear {
            stopAutoScroll()
        }
    }
    
    private func startAutoScroll() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            withAnimation {
                currentIndex = (currentIndex + 1) % items.count
            }
        }
    }
    
    private func stopAutoScroll() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Hero Slide View
struct HeroSlideView: View {
    let item: MediaItem
    let width: CGFloat
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image
            AsyncImage(url: TMDBService.shared.imageURL(path: item.backdropPath, size: .backdrop)) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            ProgressView()
                        }
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
                    Rectangle()
                        .fill(Color(.systemGray5))
                }
            }
            .frame(width: width, height: 400)
            .clipped()
            
            // Gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.7), .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Content
            VStack(alignment: .leading, spacing: 12) {
                // Media type badge
                Text(item.resolvedMediaType == .movie ? "Movie" : "TV Show")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                
                // Title
                Text(item.displayTitle)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                // Info row
                HStack(spacing: 12) {
                    if let year = item.year {
                        Text(year)
                            .foregroundColor(.white.opacity(0.8))
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
                
                // Overview
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
