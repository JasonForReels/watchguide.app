//
//  RandomPickView.swift
//  WatchGuide-MovieandTVtracker
//
//  "Can't Decide?" — animated random picker from your lists or categories
//

import SwiftUI

struct RandomPickView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var source: PickSource = .watchlist
    @State private var isSpinning = false
    @State private var spinItems: [SavedMediaItem] = []
    @State private var displayIndex: Int = 0
    @State private var pickedItem: SavedMediaItem?
    @State private var showResult = false
    @State private var selectedItem: MediaItem?
    @State private var spinTimer: Timer?
    @State private var rotationDegrees: Double = 0
    
    enum PickSource: String, CaseIterable {
        case watchlist = "Watchlist"
        case watched = "Watched"
        case liked = "Liked"
        case all = "Everything"
        
        var iconName: String {
            switch self {
            case .watchlist: return "bookmark.fill"
            case .watched: return "checkmark.circle.fill"
            case .liked: return "heart.fill"
            case .all: return "tray.full.fill"
            }
        }
    }
    
    private var sourceItems: [SavedMediaItem] {
        switch source {
        case .watchlist: return storage.wantToWatch
        case .watched: return storage.watched
        case .liked: return storage.liked
        case .all:
            var seen = Set<String>()
            var items: [SavedMediaItem] = []
            for item in storage.wantToWatch + storage.watched + storage.liked {
                if !seen.contains(item.id) {
                    seen.insert(item.id)
                    items.append(item)
                }
            }
            return items
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "dice.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)
                        .rotationEffect(.degrees(rotationDegrees))
                    
                    Text("Can't Decide?")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Let us pick something for you")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // Source Picker
                VStack(spacing: 12) {
                    Text("Pick from")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(PickSource.allCases, id: \.rawValue) { src in
                            SourceChip(
                                title: src.rawValue,
                                iconName: src.iconName,
                                count: countFor(src),
                                isSelected: source == src
                            ) {
                                source = src
                                showResult = false
                                pickedItem = nil
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Spinning Display
                if isSpinning {
                    spinningView
                } else if showResult, let item = pickedItem {
                    resultView(item: item)
                } else {
                    emptyStateView
                }
                
                // Spin Button
                Button {
                    startSpin()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isSpinning ? "stop.fill" : "shuffle")
                            .font(.headline)
                        Text(isSpinning ? "Picking..." : (showResult ? "Pick Again" : "Pick for Me"))
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(sourceItems.isEmpty ? Color(.systemGray4) : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                .disabled(isSpinning || sourceItems.isEmpty)
                .padding(.horizontal)
                
                if sourceItems.isEmpty {
                    Text("Add items to your \(source.rawValue.lowercased()) to use this feature")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer(minLength: 40)
            }
        }
        .navigationTitle("Random Pick")
        .sheet(item: $selectedItem) { item in
            MediaDetailView(item: item)
        }
    }
    
    // MARK: - Spinning View
    private var spinningView: some View {
        VStack(spacing: 16) {
            if !spinItems.isEmpty && displayIndex < spinItems.count {
                let currentItem = spinItems[displayIndex]
                
                PosterImageView(posterPath: currentItem.posterPath, size: .large, mediaId: currentItem.mediaId, mediaType: currentItem.mediaType)
                    .frame(width: 180, height: 270)
                    .id(displayIndex) // Force view recreation for animation
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 1.1).combined(with: .opacity)
                    ))
                
                Text(currentItem.title)
                    .font(.headline)
                    .lineLimit(1)
                    .id("title-\(displayIndex)")
            }
        }
        .animation(.easeInOut(duration: 0.15), value: displayIndex)
    }
    
    // MARK: - Result View
    private func resultView(item: SavedMediaItem) -> some View {
        VStack(spacing: 16) {
            Text("Your Pick!")
                .font(.caption)
                .fontWeight(.bold)
                .textCase(.uppercase)
                .foregroundColor(.accentColor)
                .tracking(2)
            
            PosterImageView(posterPath: item.posterPath, size: .large, mediaId: item.mediaId, mediaType: item.mediaType)
                .frame(width: 200, height: 300)
                .shadow(color: .accentColor.opacity(0.3), radius: 20, y: 8)
            
            VStack(spacing: 6) {
                Text(item.title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 12) {
                    if let year = item.year {
                        Text(year)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(item.mediaType == .movie ? "Movie" : "TV Show")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(6)
                    
                    if let rating = item.voteAverage, rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                            Text(String(format: "%.1f", rating))
                        }
                    }
                }
                .font(.subheadline)
            }
            
            // View Details button
            Button {
                selectedItem = item.toMediaItem()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("View Details")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.4))
            
            Text("Tap the button below to randomly pick\nsomething from your \(source.rawValue.lowercased())")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Actions
    private func startSpin() {
        guard !sourceItems.isEmpty else { return }
        
        showResult = false
        pickedItem = nil
        isSpinning = true
        
        // Build shuffled items for the spin animation
        spinItems = sourceItems.shuffled()
        displayIndex = 0
        
        // Animate dice
        withAnimation(.easeInOut(duration: 1.5)) {
            rotationDegrees += 720
        }
        
        // Rapid cycling animation
        var tick = 0
        let totalTicks = 20
        let finalIndex = Int.random(in: 0..<spinItems.count)
        
        spinTimer?.invalidate()
        spinTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            tick += 1
            
            // Slow down near the end
            if tick < totalTicks {
                displayIndex = tick % spinItems.count
            } else {
                displayIndex = finalIndex
                timer.invalidate()
                
                // Show result
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        pickedItem = spinItems[finalIndex]
                        showResult = true
                        isSpinning = false
                    }
                }
            }
        }
    }
    
    private func countFor(_ src: PickSource) -> Int {
        switch src {
        case .watchlist: return storage.wantToWatch.count
        case .watched: return storage.watched.count
        case .liked: return storage.liked.count
        case .all:
            var seen = Set<String>()
            for item in storage.wantToWatch + storage.watched + storage.liked {
                seen.insert(item.id)
            }
            return seen.count
        }
    }
}

// MARK: - Source Chip
struct SourceChip: View {
    let title: String
    let iconName: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.subheadline)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                Text("\(count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        RandomPickView()
    }
}
