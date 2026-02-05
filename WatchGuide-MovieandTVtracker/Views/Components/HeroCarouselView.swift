//
//  HeroCarouselView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct HeroCarouselView: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void
    
    @State private var currentIndex = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background blur of current slide
                if let currentItem = items[safe: currentIndex] {
                    BackdropImageView(backdropPath: currentItem.backdropPath)
                        .frame(width: geometry.size.width, height: geometry.size.width * 9.0 / 16.0)
                        .blur(radius: 30)
                        .opacity(0.5)
                }
                
                // Main carousel
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ZStack(alignment: .bottomLeading) {
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
                            .frame(width: geometry.size.width, height: geometry.size.width * 9.0 / 16.0)
                            .clipped()
                            
                            // Gradient overlay
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.7), .black.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .allowsHitTesting(false)
                            
                            // Simple content
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
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onItemTap(item) }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Page indicators (up to 10)
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
            .frame(width: geometry.size.width, height: geometry.size.width * 9.0 / 16.0)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                // Thin fading border line
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .aspectRatio(16.0/9.0, contentMode: .fit)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
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

