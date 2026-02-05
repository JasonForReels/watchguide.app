//
//  WatchProvidersView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct WatchProvidersView: View {
    let providers: WatchProviderRegion?
    let link: String?
    
    // Provider IDs to exclude (Amazon and Google Play)
    private let excludedProviderIds: Set<Int> = [
        10,   // Amazon Video
        119,  // Amazon Prime Video
        9,    // Amazon Prime Video (alternate)
        3,    // Google Play Movies
        192,  // Google Play Movies (alternate)
        350,  // Apple TV Plus (keeping for reference, not excluded)
    ]
    
    private func filterProviders(_ providers: [WatchProvider]?) -> [WatchProvider] {
        guard let providers = providers else { return [] }
        return providers.filter { !excludedProviderIds.contains($0.providerId) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Streaming
            if let flatrate = providers?.flatrate, !filterProviders(flatrate).isEmpty {
                ProviderSection(title: "Stream", providers: filterProviders(flatrate))
            }
            
            // Free with ads
            if let ads = providers?.ads, !filterProviders(ads).isEmpty {
                ProviderSection(title: "Free with Ads", providers: filterProviders(ads))
            }
            
            // Free
            if let free = providers?.free, !filterProviders(free).isEmpty {
                ProviderSection(title: "Free", providers: filterProviders(free))
            }
            
            // Rent
            if let rent = providers?.rent, !filterProviders(rent).isEmpty {
                ProviderSection(title: "Rent", providers: filterProviders(rent))
            }
            
            // Buy
            if let buy = providers?.buy, !filterProviders(buy).isEmpty {
                ProviderSection(title: "Buy", providers: filterProviders(buy))
            }
            
            // Link to JustWatch
            if let link = link, let url = URL(string: link) {
                Link(destination: url) {
                    HStack {
                        Text("More options on JustWatch")
                            .font(.caption)
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                    }
                    .foregroundColor(.accentColor)
                }
                .padding(.top, 4)
            }
        }
    }
}

struct ProviderSection: View {
    let title: String
    let providers: [WatchProvider]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(providers.prefix(10)) { provider in
                        ProviderLogo(provider: provider)
                    }
                }
            }
        }
    }
}

struct ProviderLogo: View {
    let provider: WatchProvider
    
    var body: some View {
        VStack(spacing: 4) {
            AsyncImage(url: TMDBService.shared.imageURL(path: provider.logoPath, size: .logo)) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .overlay {
                            Text(String(provider.providerName.prefix(2)))
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                @unknown default:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text(provider.providerName)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 48)
        }
    }
}

#Preview {
    WatchProvidersView(providers: nil, link: nil)
}