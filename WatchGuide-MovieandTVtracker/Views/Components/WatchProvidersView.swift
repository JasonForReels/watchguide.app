//
//  WatchProvidersView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if canImport(SafariServices)
import SafariServices
#endif

// MARK: - Provider Deep Link Mapping
struct ProviderLaunchContext {
    let title: String
    let alternateTitle: String?
    let year: String?
    let mediaType: MediaType

    var searchQuery: String {
        let normalizedAlternateTitle = alternateTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalizedAlternateTitle, !normalizedAlternateTitle.isEmpty, normalizedAlternateTitle.caseInsensitiveCompare(baseTitle) != .orderedSame {
            return "\(baseTitle) \(normalizedAlternateTitle)"
        }

        return baseTitle
    }
}

struct ProviderLaunchDestination {
    let appScheme: String?
    let appStoreName: String
    let contentURLBuilder: (ProviderLaunchContext) -> URL?

    var appStoreURL: URL? {
        var components = URLComponents()
        #if os(iOS) || os(tvOS)
        components.scheme = "itms-apps"
        components.host = "itunes.apple.com"
        components.path = "/search"
        #else
        components.scheme = "https"
        components.host = "apps.apple.com"
        components.path = "/us/search"
        #endif
        components.queryItems = [
            URLQueryItem(name: "term", value: appStoreName),
            URLQueryItem(name: "entity", value: "software")
        ]
        return components.url
    }
}

struct ProviderDeepLink {
    static func destination(for providerId: Int) -> ProviderLaunchDestination? {
        switch providerId {
        // Netflix
        case 8:
            return ProviderLaunchDestination(appScheme: "nflx://", appStoreName: "Netflix") { context in
                searchURL(host: "www.netflix.com", path: "/search", queryItem: "q", value: context.searchQuery)
            }
        // Disney+
        case 337:
            return ProviderLaunchDestination(appScheme: "disneyplus://", appStoreName: "Disney+") { context in
                searchURL(host: "www.disneyplus.com", path: "/search", queryItem: "q", value: context.searchQuery)
            }
        // Max / HBO Max
        case 384, 1899:
            return ProviderLaunchDestination(appScheme: "hbomax://", appStoreName: "Max") { context in
                searchURL(host: "play.max.com", path: "/search", queryItem: "q", value: context.searchQuery)
            }
        // Hulu
        case 15:
            return ProviderLaunchDestination(appScheme: "hulu://", appStoreName: "Hulu") { context in
                searchURL(host: "www.hulu.com", path: "/search", queryItem: "q", value: context.searchQuery)
            }
        // Paramount+
        case 531, 582:
            return ProviderLaunchDestination(appScheme: "paramountplus://", appStoreName: "Paramount+") { context in
                searchURL(host: "www.paramountplus.com", path: "/search", queryItem: "q", value: context.searchQuery)
            }
        // Peacock
        case 386, 387:
            return ProviderLaunchDestination(appScheme: "peacocktv://", appStoreName: "Peacock TV") { context in
                searchURL(host: "www.peacocktv.com", path: "/search", queryItem: "q", value: context.searchQuery)
            }
        // Avoid auto-switching into the Apple TV app.
        case 350, 2:
            return nil
        // Crunchyroll
        case 283:
            return ProviderLaunchDestination(appScheme: "crunchyroll://", appStoreName: "Crunchyroll") { context in
                searchURL(host: "www.crunchyroll.com", path: "/search", queryItem: "q", value: context.searchQuery)
            }
        // Discovery+
        case 510, 584:
            return ProviderLaunchDestination(appScheme: "discoveryplus://", appStoreName: "discovery+") { context in
                searchURL(host: "www.discoveryplus.com", path: "/search", queryItem: "q", value: context.searchQuery)
            }
        // MUBI
        case 11:
            return ProviderLaunchDestination(appScheme: "mubi://", appStoreName: "MUBI") { context in
                searchURL(host: "mubi.com", path: "/search", queryItem: "query", value: context.searchQuery)
            }
        // Showmax
        case 55:
            return ProviderLaunchDestination(appScheme: "showmax://", appStoreName: "Showmax") { context in
                searchURL(host: "www.showmax.com", path: "/eng/search", queryItem: "q", value: context.searchQuery)
            }
        // BritBox
        case 380, 151:
            return ProviderLaunchDestination(appScheme: "britbox://", appStoreName: "BritBox") { context in
                searchURL(host: "www.britbox.com", path: "/search", queryItem: "q", value: context.searchQuery)
            }
        // Tubi
        case 73:
            return ProviderLaunchDestination(appScheme: "tubi://", appStoreName: "Tubi") { context in
                searchURL(host: "tubitv.com", path: "/search/\(pathComponent(from: context.searchQuery))", queryItem: nil, value: nil)
            }
        // Pluto TV
        case 300:
            return ProviderLaunchDestination(appScheme: "plutotv://", appStoreName: "Pluto TV") { context in
                searchURL(host: "pluto.tv", path: "/search/details", queryItem: "q", value: context.searchQuery)
            }
        // Vudu / Fandango at Home
        case 7:
            return ProviderLaunchDestination(appScheme: "vudu://", appStoreName: "Fandango at Home") { context in
                searchURL(host: "www.vudu.com", path: "/content/movies/search", queryItem: "searchString", value: context.searchQuery)
            }
        // Shudder
        case 99:
            return ProviderLaunchDestination(appScheme: "shudder://", appStoreName: "Shudder") { context in
                searchURL(host: "www.shudder.com", path: "/search", queryItem: "q", value: context.searchQuery)
            }
        // Starz
        case 43:
            return ProviderLaunchDestination(appScheme: "starz://", appStoreName: "STARZ") { context in
                searchURL(host: "www.starz.com", path: "/us/en/search", queryItem: "query", value: context.searchQuery)
            }
        default:
            return nil
        }
    }

    static func appScheme(for providerId: Int) -> String? {
        destination(for: providerId)?.appScheme
    }

    static func isAppInstalled(for providerId: Int) -> Bool {
        guard let scheme = appScheme(for: providerId),
              let url = URL(string: scheme) else { return false }
        return PlatformURLHandler.canOpenURL(url)
    }

    static func contentURL(for providerId: Int, context: ProviderLaunchContext) -> URL? {
        destination(for: providerId)?.contentURLBuilder(context)
    }

    static func appStoreURL(for providerId: Int) -> URL? {
        destination(for: providerId)?.appStoreURL
    }

    private static func searchURL(host: String, path: String, queryItem: String?, value: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        if let queryItem, let value {
            components.queryItems = [URLQueryItem(name: queryItem, value: value)]
        }
        return components.url
    }

    private static func pathComponent(from value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private actor StreamingContentLinkResolver {
    static let shared = StreamingContentLinkResolver()

    private var disneyURLCache: [String: URL] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    func disneyPlusURL(for context: ProviderLaunchContext) async -> URL? {
        let cacheKey = "\(context.mediaType.rawValue)|\(context.title.lowercased())|\(context.year ?? "")"
        if let cached = disneyURLCache[cacheKey] {
            return cached
        }

        let titleQuery = context.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleQuery.isEmpty else {
            return nil
        }

        let sitePath = context.mediaType == .movie ? "movies" : "series"
        var query = "site:disneyplus.com/\(sitePath) \"\(titleQuery)\""
        if let year = context.year, !year.isEmpty {
            query += " \(year)"
        }

        var components = URLComponents(string: "https://duckduckgo.com/html/")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let searchURL = components.url else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: searchURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }

            if let exactURL = extractDisneyPlusURL(from: html, mediaType: context.mediaType) {
                disneyURLCache[cacheKey] = exactURL
                return exactURL
            }
        } catch {
            return nil
        }

        return nil
    }

    private func extractDisneyPlusURL(from html: String, mediaType: MediaType) -> URL? {
        let ranges = candidateRanges(in: html)

        for range in ranges {
            let candidate = String(html[range])
            if let normalized = normalizedDisneyURL(from: candidate, mediaType: mediaType) {
                return normalized
            }
        }

        return nil
    }

    private func candidateRanges(in html: String) -> [Range<String.Index>] {
        let patterns = [
            #"https://www\.disneyplus\.com[^"' <\\]+"#,
            #"uddg=https%3A%2F%2Fwww\.disneyplus\.com[^"' <\\]+"#
        ]

        return patterns.compactMap { pattern -> [Range<String.Index>]? in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }

            let nsRange = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, options: [], range: nsRange)
            return matches.compactMap { match in
                Range(match.range, in: html)
            }
        }
        .flatMap { $0 }
    }

    private func normalizedDisneyURL(from candidate: String, mediaType: MediaType) -> URL? {
        let decodedCandidate = decodeHTMLAndPercentEncoding(candidate)

        guard let urlStartRange = decodedCandidate.range(of: "https://www.disneyplus.com") else {
            return nil
        }

        let trimmed = String(decodedCandidate[urlStartRange.lowerBound...])
        guard let url = URL(string: trimmed) else {
            return nil
        }

        let path = url.path.lowercased()
        switch mediaType {
        case .movie:
            guard path.contains("/movies/") || path.contains("/browse/entity-") else { return nil }
        case .tv:
            guard path.contains("/series/") || path.contains("/browse/entity-") else { return nil }
        case .person:
            return nil
        }

        return url
    }

    private func decodeHTMLAndPercentEncoding(_ value: String) -> String {
        let htmlDecoded = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")

        return htmlDecoded.removingPercentEncoding ?? htmlDecoded
    }
}

struct WatchProvidersView: View {
    let providers: WatchProviderRegion?
    let link: String?
    let mediaTitle: String
    let alternateTitle: String?
    let mediaType: MediaType
    let year: String?
    var deepLinks: [StreamingDeepLink] = []
    var countryCode: String? = nil

    // Continue Watching tracking context (optional)
    var savedMediaItem: SavedMediaItem?
    var episodeContext: ContinueWatchingEpisode?
    
    @ObservedObject private var subscription = ScoutSubscriptionService.shared
    @State private var safariURL: URL?
    @State private var showSafari = false
    @State private var showProviderSheet = false
    @State private var selectedProvider: WatchProvider?
    @State private var resolvedDeepLinkURL: URL?
    @State private var resolvedAppName: String?
    @State private var resolvedAppInstalled = false
    @State private var showUpgradePaywall = false
    
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
    
    // Hulu is now part of Disney+, so tapping Hulu should also try Disney+.
    private static let huluProviderId = 15
    private static let disneyPlusProviderId = 337

    private func handleProviderTap(_ provider: WatchProvider) {
        let launchContext = ProviderLaunchContext(
            title: mediaTitle,
            alternateTitle: alternateTitle,
            year: year,
            mediaType: mediaType
        )

        Task {
            // Resolve the best URL and app name for this provider
            let providerIdsToTry: [Int] = provider.providerId == Self.huluProviderId
                ? [Self.disneyPlusProviderId, provider.providerId]
                : [provider.providerId]

            var bestURL: URL?
            var appName: String = provider.providerName
            var appInstalled = false

            // Priority 1: MOTN deep link
            if let motnURL = await StreamingDeepLinkService.shared.deepLink(
                forTMDBProviderId: provider.providerId,
                from: deepLinks
            ) {
                bestURL = motnURL
                if let dest = ProviderDeepLink.destination(for: provider.providerId) {
                    appName = dest.appStoreName
                    appInstalled = ProviderDeepLink.isAppInstalled(for: provider.providerId)
                }
            }

            // Priority 2: Provider-specific deep link
            if bestURL == nil {
                for pid in providerIdsToTry {
                    if let dest = ProviderDeepLink.destination(for: pid) {
                        appName = dest.appStoreName
                        appInstalled = ProviderDeepLink.isAppInstalled(for: pid)

                        if appInstalled {
                            if let contentURL = dest.contentURLBuilder(launchContext) {
                                bestURL = contentURL
                                break
                            }
                            if let scheme = dest.appScheme, let appURL = URL(string: scheme) {
                                bestURL = appURL
                                break
                            }
                        } else {
                            // App not installed — use App Store URL
                            bestURL = dest.appStoreURL
                            break
                        }
                    }
                }
            }

            // Priority 3: JustWatch fallback
            if bestURL == nil, let link = link, let url = URL(string: link) {
                bestURL = url
            }

            guard let finalURL = bestURL else { return }

            await MainActor.run {
                selectedProvider = provider
                resolvedDeepLinkURL = finalURL
                resolvedAppName = appName
                resolvedAppInstalled = appInstalled
                showProviderSheet = true
            }
        }
    }

    private func openResolvedDeepLink() {
        guard let url = resolvedDeepLinkURL, selectedProvider != nil else { return }

        Task {
            #if os(iOS) && !targetEnvironment(macCatalyst)
            // For non-app URLs (JustWatch), open in Safari sheet
            if !resolvedAppInstalled && url.scheme == "itms-apps" {
                PlatformURLHandler.openURL(url)
            } else if !resolvedAppInstalled && url.host?.contains("justwatch") == true {
                safariURL = url
                showSafari = true
            } else {
                PlatformURLHandler.openURL(url)
            }
            #else
            PlatformURLHandler.openURL(url)
            #endif

            await recordContinueWatching(openedURL: url)
        }
    }

    private func recordContinueWatching(openedURL: URL?) async {
        guard let savedItem = savedMediaItem else { return }

        if savedItem.mediaType == .tv, let episode = episodeContext {
            await ContinueWatchingService.shared.recordTVEpisodeDeepLinkTap(
                show: savedItem,
                episode: episode,
                providers: providers,
                providersLink: link,
                deepLinkURL: openedURL
            )
        } else if savedItem.mediaType == .movie {
            await ContinueWatchingService.shared.recordMovieDeepLinkTap(
                movie: savedItem,
                providers: providers,
                providersLink: link,
                deepLinkURL: openedURL
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Streaming
            if let flatrate = providers?.flatrate, !filterProviders(flatrate).isEmpty {
                ProviderSection(title: "Stream", providers: filterProviders(flatrate), countryCode: countryCode, onTap: handleProviderTap)
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
            if let link = link, let url = URL(string: link) {
                Button {
                    #if os(iOS) && !targetEnvironment(macCatalyst)
                    safariURL = url
                    showSafari = true
                    #else
                    PlatformURLHandler.openURL(url)
                    #endif
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
        }
        #if os(iOS) && !targetEnvironment(macCatalyst)
        .sheet(isPresented: $showSafari) {
            if let url = safariURL {
                WatchProviderSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        #endif
        .confirmationDialog(
            resolvedAppName ?? "Streaming",
            isPresented: $showProviderSheet,
            titleVisibility: .visible
        ) {
            if resolvedAppInstalled {
                Button("Open in \(resolvedAppName ?? "App")") {
                    openResolvedDeepLink()
                }
            } else {
                Button("Get \(resolvedAppName ?? "App") on the App Store") {
                    openResolvedDeepLink()
                }
            }

            if !subscription.isUnlimitedActive {
                Button("Upgrade to watch straight away") {
                    showUpgradePaywall = true
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            if resolvedAppInstalled {
                Text("Open \(mediaTitle) in \(resolvedAppName ?? "the app").")
            } else {
                Text("\(resolvedAppName ?? "This app") isn't installed. Get it or upgrade to WatchGuide Pro for instant deep links.")
            }
        }
        .wgUnlimitedUpgradeSheet(isPresented: $showUpgradePaywall, context: .unlimited)
    }
}

// MARK: - In-App Safari for Watch Providers
#if os(iOS) && !targetEnvironment(macCatalyst)
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
    var countryCode: String? = nil
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
                        ProviderLogo(provider: provider, countryCode: countryCode, onTap: onTap)
                    }
                }
            }
        }
    }
}

struct ProviderLogo: View {
    let provider: WatchProvider
    var countryCode: String? = nil
    var onTap: ((WatchProvider) -> Void)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isFocused) private var isFocused

    private var providerTileSize: CGFloat {
        #if os(tvOS)
        return max(ResponsiveSizing.providerLogoSize(horizontalSizeClass: horizontalSizeClass) * 1.55, 120)
        #else
        return ResponsiveSizing.providerLogoSize(horizontalSizeClass: horizontalSizeClass)
        #endif
    }

    private var providerTileCornerRadius: CGFloat {
        #if os(tvOS)
        return 20
        #else
        return 8
        #endif
    }
    
    var body: some View {
        Button {
            onTap?(provider)
        } label: {
            VStack(spacing: 4) {
                ResilientAsyncImage(url: TMDBService.shared.imageURL(path: provider.logoPath, size: .logo)) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: providerTileCornerRadius, style: .continuous)
                            .fill(Color.gray.opacity(0.18))
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(.horizontal, logoInnerPadding)
                            .padding(.vertical, logoInnerPadding)
                    case .failure:
                        RoundedRectangle(cornerRadius: providerTileCornerRadius, style: .continuous)
                            .fill(Color.gray.opacity(0.18))
                            .overlay {
                                Text(String(provider.providerName.prefix(2)))
                                    .font(providerFallbackFont)
                                    .fontWeight(.bold)
                            }
                    @unknown default:
                        RoundedRectangle(cornerRadius: providerTileCornerRadius, style: .continuous)
                            .fill(Color.gray.opacity(0.18))
                    }
                }
                .frame(width: providerTileSize, height: providerTileSize)
                .background(providerTileBackground)
                .overlay(providerTileBorder)
                .clipShape(RoundedRectangle(cornerRadius: providerTileCornerRadius, style: .continuous))
                .shadow(color: providerTileShadowColor, radius: isFocused ? 18 : 8, x: 0, y: isFocused ? 10 : 4)
                
                if let price = priceText {
                    Text(price)
                        .font(priceFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            #if os(tvOS)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .animation(.easeOut(duration: 0.18), value: isFocused)
            #endif
        }
        #if os(tvOS)
        .buttonStyle(TVOSTransparentButtonStyle(cornerRadius: providerTileCornerRadius))
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var providerTileBackground: some View {
        RoundedRectangle(cornerRadius: providerTileCornerRadius, style: .continuous)
            .fill(providerTileBackgroundColor)
    }

    private var providerTileBorder: some View {
        RoundedRectangle(cornerRadius: providerTileCornerRadius, style: .continuous)
            .stroke(providerTileBorderColor, lineWidth: providerTileBorderWidth)
    }

    private var providerTileBackgroundColor: Color {
        return Color.clear
    }

    private var providerTileBorderColor: Color {
        #if os(tvOS)
        return Color.white.opacity(isFocused ? 0.96 : 0.18)
        #else
        return Color.clear
        #endif
    }

    private var providerTileBorderWidth: CGFloat {
        #if os(tvOS)
        return isFocused ? 2.4 : 0.8
        #else
        return 0
        #endif
    }

    private var providerTileShadowColor: Color {
        #if os(tvOS)
        return Color.black.opacity(isFocused ? 0.45 : 0.18)
        #else
        return Color.clear
        #endif
    }

    private var providerNameFont: Font {
        #if os(tvOS)
        return .caption.weight(.semibold)
        #else
        return .caption2
        #endif
    }

    private var providerFallbackFont: Font {
        #if os(tvOS)
        return .title3
        #else
        return .caption
        #endif
    }

    private var providerNameWidthPadding: CGFloat {
        #if os(tvOS)
        return 20
        #else
        return 0
        #endif
    }

    private var logoInnerPadding: CGFloat {
        #if os(tvOS)
        return 16
        #else
        return 0
        #endif
    }

    private var priceText: String? {
        guard let code = countryCode else { return nil }
        return ProviderPricingService.monthlyPrice(forProviderId: provider.providerId, countryCode: code)
    }

    private var priceFont: Font {
        #if os(tvOS)
        return .caption2.weight(.medium)
        #else
        return .system(size: 9, weight: .medium)
        #endif
    }
}

#Preview {
    WatchProvidersView(
        providers: nil,
        link: nil,
        mediaTitle: "Severance",
        alternateTitle: nil,
        mediaType: .tv,
        year: "2022"
    )
}
