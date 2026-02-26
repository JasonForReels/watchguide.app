//
//  WatchProvidersView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if canImport(SafariServices)
import SafariServices
#endif

// MARK: - Provider Deep Link Mapping
private struct ProviderDeepLink {
    /// Returns the URL scheme for a known provider, if the app is installed.
    /// Falls back to nil so we open the JustWatch link in-app browser instead.
    static func appScheme(for providerId: Int) -> String? {
        switch providerId {
        // Netflix
        case 8: return "nflx://"
        // Disney+
        case 337: return "disneyplus://"
        // Max / HBO Max
        case 384, 1899: return "hbomax://"
        // Hulu
        case 15: return "hulu://"
        // Paramount+
        case 531, 582: return "paramountplus://"
        // Peacock
        case 386, 387: return "peacocktv://"
        // Apple TV+
        case 350, 2: return "appletv://"
        // Crunchyroll
        case 283: return "crunchyroll://"
        // Discovery+
        case 510, 584: return "discoveryplus://"
        // MUBI
        case 11: return "mubi://"
        // Showmax
        case 55: return "showmax://"
        // BritBox
        case 380, 151: return "britbox://"
        // Tubi
        case 73: return "tubi://"
        // Pluto TV
        case 300: return "plutotv://"
        // Vudu / Fandango at Home
        case 7: return "vudu://"
        // Shudder
        case 99: return "shudder://"
        // Starz
        case 43: return "starz://"
        default: return nil
        }
    }
    
    /// Checks if the provider's native app is installed.
    static func isAppInstalled(for providerId: Int) -> Bool {
        guard let scheme = appScheme(for: providerId),
              let url = URL(string: scheme) else { return false }
        return PlatformURLHandler.canOpenURL(url)
    }
}

struct WatchProvidersView: View {
    let providers: WatchProviderRegion?
    let link: String?
    
    @State private var safariURL: URL?
    @State private var showSafari = false
    
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
        let filtered = providers.filter { !excludedProviderIds.contains($0.providerId) }
        #if os(tvOS)
        return filtered.filter { ProviderDeepLink.isAppInstalled(for: $0.providerId) }
        #else
        return filtered
        #endif
    }
    
    private func handleProviderTap(_ provider: WatchProvider) {
        #if os(tvOS)
        if ProviderDeepLink.isAppInstalled(for: provider.providerId),
           let scheme = ProviderDeepLink.appScheme(for: provider.providerId),
           let appURL = URL(string: scheme) {
            PlatformURLHandler.openURL(appURL)
        }
        #else
        // If the provider's native app is installed, open it
        if ProviderDeepLink.isAppInstalled(for: provider.providerId),
           let scheme = ProviderDeepLink.appScheme(for: provider.providerId),
           let appURL = URL(string: scheme) {
            PlatformURLHandler.openURL(appURL)
            return
        }
        
        // Otherwise, open the JustWatch link in-app browser
        if let link = link, let url = URL(string: link) {
            safariURL = url
            showSafari = true
        }
        #endif
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Streaming
            if let flatrate = providers?.flatrate, !filterProviders(flatrate).isEmpty {
                ProviderSection(title: "Stream", providers: filterProviders(flatrate), onTap: handleProviderTap)
            }
            
            // Free with ads
            if let ads = providers?.ads, !filterProviders(ads).isEmpty {
                ProviderSection(title: "Free with Ads", providers: filterProviders(ads), onTap: handleProviderTap)
            }
            
            // Free
            if let free = providers?.free, !filterProviders(free).isEmpty {
                ProviderSection(title: "Free", providers: filterProviders(free), onTap: handleProviderTap)
            }
            
            // Rent
            if let rent = providers?.rent, !filterProviders(rent).isEmpty {
                ProviderSection(title: "Rent", providers: filterProviders(rent), onTap: handleProviderTap)
            }
            
            // Buy
            if let buy = providers?.buy, !filterProviders(buy).isEmpty {
                ProviderSection(title: "Buy", providers: filterProviders(buy), onTap: handleProviderTap)
            }
            
            // Link to JustWatch
            #if os(iOS)
            if let link = link, let url = URL(string: link) {
                Button {
                    safariURL = url
                    showSafari = true
                } label: {
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
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showSafari) {
            if let url = safariURL {
                WatchProviderSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        #endif
    }
}

// MARK: - In-App Safari for Watch Providers
#if os(iOS)
private struct WatchProviderSafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = .systemBlue
        return controller
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif

struct ProviderSection: View {
    let title: String
    let providers: [WatchProvider]
    var onTap: ((WatchProvider) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(providers.prefix(10)) { provider in
                        ProviderLogo(provider: provider, onTap: onTap)
                    }
                }
            }
        }
    }
}

struct ProviderLogo: View {
    let provider: WatchProvider
    var onTap: ((WatchProvider) -> Void)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        let logoSize = ResponsiveSizing.providerLogoSize(horizontalSizeClass: horizontalSizeClass)
        Button {
            onTap?(provider)
        } label: {
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
                .frame(width: logoSize, height: logoSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text(provider.providerName)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: logoSize)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WatchProvidersView(providers: nil, link: nil)
}
