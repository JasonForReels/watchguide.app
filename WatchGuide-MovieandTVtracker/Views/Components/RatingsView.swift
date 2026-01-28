//
//  RatingsView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct RatingsView: View {
    let ratings: RatingsSummary?
    let tmdbRating: Double?
    
    var body: some View {
        HStack(spacing: 16) {
            // TMDB Rating
            if let rating = tmdbRating, rating > 0 {
                RatingBadge(
                    source: "TMDB",
                    value: String(format: "%.1f", rating),
                    iconName: "star.fill",
                    color: .yellow
                )
            }
            
            // IMDb Rating
            if let imdb = ratings?.imdbRating, imdb != "N/A" {
                RatingBadge(
                    source: "IMDb",
                    value: imdb,
                    iconName: "star.fill",
                    color: .orange
                )
            }
            
            // Rotten Tomatoes
            if let rt = ratings?.rottenTomatoesScore {
                let isFresh = rtIsFresh(rt)
                RatingBadge(
                    source: "RT",
                    value: rt,
                    iconName: isFresh ? "checkmark.seal.fill" : "xmark.seal.fill",
                    color: isFresh ? .red : .gray
                )
            }
            
            // Metacritic
            if let meta = ratings?.metacriticScore {
                let score = metaScore(meta)
                RatingBadge(
                    source: "Meta",
                    value: meta,
                    iconName: "square.fill",
                    color: metaColor(score)
                )
            }
        }
    }
    
    private func rtIsFresh(_ value: String) -> Bool {
        let numericString = value.replacingOccurrences(of: "%", with: "")
        if let percent = Int(numericString) {
            return percent >= 60
        }
        return false
    }
    
    private func metaScore(_ value: String) -> Int {
        let numericString = value.components(separatedBy: "/").first ?? "0"
        return Int(numericString) ?? 0
    }
    
    private func metaColor(_ score: Int) -> Color {
        if score >= 61 {
            return .green
        } else if score >= 40 {
            return .yellow
        } else {
            return .red
        }
    }
}

struct RatingBadge: View {
    let source: String
    let value: String
    let iconName: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Text(source)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    RatingsView(ratings: nil, tmdbRating: 8.5)
}
