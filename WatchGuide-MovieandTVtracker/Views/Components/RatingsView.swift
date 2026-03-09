//
//  RatingsView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct RatingsView: View {
    let ratings: RatingsSummary?
    let tmdbRating: Double?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // TMDB Rating
                if let rating = tmdbRating, rating > 0 {
                    LogoRatingBadge(
                        logoImage: Image("E0B6FD45-4C57-46E0-9A00-CB64F05895BA_Tmdb-312x276-logo"),
                        value: String(format: "%.1f", rating),
                        label: "TMDB"
                    )
                }
                
                // IMDb Rating
                if let imdb = ratings?.imdbRating, imdb != "N/A" {
                    LogoRatingBadge(
                        logoImage: Image("F154F6CE-7602-4A20-8AC1-94F19395B5FC_IMDb_Logo_Rectangle_svg"),
                        value: imdb,
                        label: "IMDb"
                    )
                }
                
                // Rotten Tomatoes (Dropdown with Critics + Audience)
                if ratings?.rottenTomatoesScore != nil || ratings?.rottenTomatoesAudienceScore != nil {
                    RTDropdownBadge(
                        criticsScore: ratings?.rottenTomatoesScore,
                        audienceScore: ratings?.rottenTomatoesAudienceScore
                    )
                }
                
                // Metacritic
                if let meta = ratings?.metacriticScore {
                    let score = metaScore(meta)
                    MetacriticBadge(value: meta, score: score)
                }
            }
        }
    }
    
    private func metaScore(_ value: String) -> Int {
        let numericString = value.components(separatedBy: "/").first ?? "0"
        return Int(numericString) ?? 0
    }
}

// MARK: - Logo Rating Badge (TMDB, IMDb)
struct LogoRatingBadge: View {
    let logoImage: Image
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 5) {
            logoImage
                .resizable()
                .scaledToFit()
                .frame(height: 18)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(10)
    }
}

// MARK: - Rotten Tomatoes Dropdown Badge
struct RTDropdownBadge: View {
    let criticsScore: String?
    let audienceScore: String?
    
    @State private var isExpanded = false
    
    /// The primary score to display on the collapsed badge
    private var primaryScore: String {
        criticsScore ?? audienceScore ?? ""
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main badge (tappable)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                VStack(spacing: 5) {
                    Image("435410DD-5B01-4D39-90BC-ED4EEDA10E06_rt-tomato-logo_20c3bdbc97b")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 18)
                    
                    HStack(spacing: 3) {
                        Text(primaryScore)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            // Expanded dropdown
            if isExpanded {
                VStack(spacing: 0) {
                    // Critics score
                    if let critics = criticsScore {
                        HStack(spacing: 8) {
                            Image("F209AC62-E462-4675-B076-F6764418CC33_Fresh_Tomato_logo_svg")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Critics")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(critics)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    
                    // Divider between critics & audience if both exist
                    if criticsScore != nil && audienceScore != nil {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                    
                    // Audience score
                    if let audience = audienceScore {
                        HStack(spacing: 8) {
                            Image("B07B3FD9-0C00-485E-BB1D-142B7A766C33_Rotten_Tomatoes_positive_audience")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Audience")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(audience)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .background(Color.gray.opacity(0.12))
                .cornerRadius(10)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }
}

// MARK: - Metacritic Badge
struct MetacriticBadge: View {
    let value: String
    let score: Int
    
    private var scoreColor: Color {
        if score >= 61 {
            return .green
        } else if score >= 40 {
            return .yellow
        } else {
            return .red
        }
    }
    
    var body: some View {
        VStack(spacing: 5) {
            Image("9D5D80F6-DBE2-472F-87A9-002863F60594_Metacritic_logo_Roundel_svg")
                .resizable()
                .scaledToFit()
                .frame(height: 18)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(scoreColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(10)
    }
}

#Preview {
    RatingsView(
        ratings: RatingsSummary(
            imdbRating: "8.4",
            rottenTomatoesScore: "79%",
            rottenTomatoesAudienceScore: "96%",
            metacriticScore: "66/100"
        ),
        tmdbRating: 8.5
    )
}
