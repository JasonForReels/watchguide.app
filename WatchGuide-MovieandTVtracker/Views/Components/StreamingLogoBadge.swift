//
//  StreamingLogoBadge.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Hub Provider Environment Key

/// Environment key that streaming hubs set so poster badges show the correct logo.
private struct HubProviderIdKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// When set, `StreamingLogoBadge` uses this provider ID instead of looking it up.
    var hubProviderId: Int? {
        get { self[HubProviderIdKey.self] }
        set { self[HubProviderIdKey.self] = newValue }
    }
}

// MARK: - Streaming Badge Cache

/// Fetches and caches the primary streaming provider ID for each media item.
actor StreamingBadgeCache {
    static let shared = StreamingBadgeCache()

    /// Provider IDs we track badges for (the major services with local logo assets).
    static let trackedProviderIds: Set<Int> = [
        8,          // Netflix
        337,        // Disney+
        384, 1899,  // Max / HBO Max
        15,         // Hulu
        531, 582,   // Paramount+
        9, 10, 119, // Prime Video
        350,        // Apple TV+
        386         // Peacock
    ]

    /// Prime Video provider IDs — used to detect Amazon Channel add-ons.
    private static let primeVideoIds: Set<Int> = [9, 10, 119]

    /// Maps an Amazon Channel add-on provider to its parent service ID by name.
    /// For example, "HBO Max Amazon Channel" → 1899 (HBO Max).
    /// Returns `nil` if the provider is not a recognized channel variant.
    private static func parentServiceId(for provider: WatchProvider) -> Int? {
        let name = provider.providerName.lowercased()
        // Only remap providers whose name suggests they are add-on channels
        guard name.contains("channel") || name.contains("amazon") || name.contains("prime") else {
            return nil
        }
        // Already a direct tracked ID (not an add-on) — no remapping
        if trackedProviderIds.contains(provider.providerId) { return nil }
        if name.contains("netflix") { return 8 }
        if name.contains("disney") { return 337 }
        if name.contains("hbo") || name.contains("max") { return 1899 }
        if name.contains("hulu") { return 15 }
        if name.contains("paramount") { return 531 }
        if name.contains("apple") { return 350 }
        if name.contains("peacock") { return 386 }
        return nil
    }

    private var cache: [String: Int?] = [:]
    private var inFlight: [String: Task<Int?, Never>] = [:]

    /// Returns the first tracked streaming provider ID for the given title, or `nil`.
    /// When Amazon Channel add-ons are present (e.g. "HBO Max Amazon Channel"),
    /// the parent service is preferred over raw Prime Video.
    func primaryProviderId(mediaId: Int, mediaType: MediaType) async -> Int? {
        let key = "\(mediaType.rawValue)|\(mediaId)"

        if let cached = cache[key] {
            return cached
        }

        // Coalesce duplicate requests for the same item
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<Int?, Never> {
            do {
                let response: WatchProvidersResponse
                switch mediaType {
                case .movie:
                    response = try await TMDBService.shared.getMovieWatchProviders(id: mediaId)
                case .tv:
                    response = try await TMDBService.shared.getTVShowWatchProviders(id: mediaId)
                case .person:
                    return nil
                }

                let regionCode = Locale.current.region?.identifier ?? "US"
                // Check user's region first, then fall back to US
                let regionsToCheck = regionCode == "US" ? ["US"] : [regionCode, "US"]
                for region in regionsToCheck {
                    guard let data = response.results?[region] else { continue }
                    // Look through streaming categories for the first tracked one
                    // Priority: flatrate (subscription) > free > ads
                    let streamingProviders: [WatchProvider] =
                        (data.flatrate ?? []) +
                        (data.free ?? []) +
                        (data.ads ?? [])

                    // Collect any parent service IDs from Amazon Channel add-ons
                    var channelParentIds = Set<Int>()
                    for provider in streamingProviders {
                        if let parentId = Self.parentServiceId(for: provider) {
                            channelParentIds.insert(parentId)
                        }
                    }

                    // Pick the first tracked provider, but skip raw Prime Video
                    // if an Amazon Channel add-on maps to a known parent service.
                    for provider in streamingProviders {
                        let id = provider.providerId
                        guard Self.trackedProviderIds.contains(id) else { continue }
                        // If this is Prime Video but we found a channel add-on
                        // for another service, skip Prime and prefer the parent.
                        if Self.primeVideoIds.contains(id) && !channelParentIds.isEmpty {
                            continue
                        }
                        return id
                    }

                    // Fall back: if only channel add-ons matched, return the first parent
                    if let firstParent = channelParentIds.first {
                        return firstParent
                    }
                }
                return nil
            } catch {
                return nil
            }
        }

        inFlight[key] = task
        let result = await task.value
        cache[key] = result
        inFlight[key] = nil
        return result
    }
}

// MARK: - Studio Badge Cache

/// Resolves and caches the owning studio's local logo asset for each media item,
/// based on its production companies (and TV networks). Only studios that have a
/// local logo asset are tracked.
actor StudioBadgeCache {
    static let shared = StudioBadgeCache()

    /// A studio name match: the parent-company logo plus, when the name is a
    /// recognized sub-label (e.g. Marvel, Pixar), the dedicated sub-label asset.
    struct StudioMatch {
        /// Parent-company logo asset, always present (e.g. "Disney_logo").
        let parentAsset: String
        /// Dedicated sub-label asset (e.g. "Marvel_logo"), or nil for the parent brand itself.
        let specificAsset: String?
    }

    /// Maps a production company / network name to its parent studio logo and,
    /// when applicable, the more specific sub-label logo. The sub-label logo is
    /// only used if its asset actually exists in the catalog (see `studioAssetName(mediaId:)`),
    /// so titles fall back to the parent logo until dedicated artwork is added.
    static func studioMatch(forName rawName: String) -> StudioMatch? {
        let name = rawName.lowercased()

        // Walt Disney Company family — prefer the specific sub-label logo.
        if name.contains("pixar") {
            return StudioMatch(parentAsset: "Disney_logo", specificAsset: "Pixar_logo")
        }
        if name.contains("marvel") {
            return StudioMatch(parentAsset: "Disney_logo", specificAsset: "Marvel_logo")
        }
        if name.contains("lucasfilm") {
            return StudioMatch(parentAsset: "Disney_logo", specificAsset: "Lucasfilm_logo")
        }
        if name.contains("20th century") || name.contains("twentieth century") {
            return StudioMatch(parentAsset: "Disney_logo", specificAsset: "20th_Century_Studios_logo")
        }
        if name.contains("searchlight") {
            return StudioMatch(parentAsset: "Disney_logo", specificAsset: "Searchlight_Pictures_logo")
        }
        if name.contains("disney")
            || name.contains("touchstone")
            || name.contains("blue sky")
            || name.contains("hollywood pictures") {
            return StudioMatch(parentAsset: "Disney_logo", specificAsset: nil)
        }

        // Warner Bros. Discovery family — prefer the specific sub-label logo.
        if name.contains("new line") {
            return StudioMatch(parentAsset: "Warner Bros logo", specificAsset: "New_Line_Cinema_logo")
        }
        if name.contains("dc comics")
            || name.contains("dc entertainment")
            || name.contains("dc studios")
            || name.contains("dc films") {
            return StudioMatch(parentAsset: "Warner Bros logo", specificAsset: "DC_logo")
        }
        if name.contains("warner")
            || name.contains("castle rock")
            || name.contains("hanna-barbera") {
            return StudioMatch(parentAsset: "Warner Bros logo", specificAsset: nil)
        }

        return nil
    }

    /// Whether an image asset with the given name exists in the catalog.
    private static func assetExists(_ name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
        #else
        return true
        #endif
    }

    private var cache: [String: String?] = [:]
    private var inFlight: [String: Task<String?, Never>] = [:]

    /// Returns the local studio logo asset name for the given title, or `nil`.
    func studioAssetName(mediaId: Int, mediaType: MediaType) async -> String? {
        let key = "\(mediaType.rawValue)|\(mediaId)"

        if let cached = cache[key] {
            return cached
        }

        // Coalesce duplicate requests for the same item
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<String?, Never> {
            do {
                // Gather candidate company / network names for this title.
                var names: [String] = []
                switch mediaType {
                case .movie:
                    let details = try await TMDBService.shared.getMovieDetails(id: mediaId)
                    names = (details.productionCompanies ?? []).map(\.name)
                case .tv:
                    let details = try await TMDBService.shared.getTVShowDetails(id: mediaId)
                    names = (details.networks ?? []).map(\.name)
                        + (details.productionCompanies ?? []).map(\.name)
                case .person:
                    return nil
                }

                // Prefer the most specific sub-label logo (e.g. Marvel) whose
                // artwork exists, looking across every company/network name — not
                // just the first match — so a Marvel show on Disney+ shows Marvel
                // rather than the Disney network logo. Fall back to the parent
                // studio logo when no dedicated sub-label asset is available.
                var parentFallback: String?
                for name in names {
                    guard let match = Self.studioMatch(forName: name) else { continue }
                    if let specific = match.specificAsset, Self.assetExists(specific) {
                        return specific
                    }
                    if parentFallback == nil {
                        parentFallback = match.parentAsset
                    }
                }
                return parentFallback
            } catch {
                return nil
            }
        }

        inFlight[key] = task
        let result = await task.value
        cache[key] = result
        inFlight[key] = nil
        return result
    }
}

// MARK: - Streaming Logo Badge View

/// A small badge placed in the top-right corner of a poster. Shows the streaming
/// service logo for titles available on a tracked platform, and — when the owning
/// studio is recognized — appends a vertical divider followed by the studio logo.
struct StreamingLogoBadge: View {
    let mediaId: Int
    let mediaType: MediaType
    /// Multiplier applied to the streaming-logo size (and spacing/divider).
    /// Defaults to 1 (poster size); larger contexts like the hero pass a bigger value.
    var scale: CGFloat = 1
    /// Separate multiplier for the studio logo, which is a wide wordmark and
    /// reads as much larger than the streaming icon at the same scale. Defaults to 1.
    var studioScale: CGFloat = 1
    /// Whether to append the owning studio's logo. Poster badges leave this off —
    /// the wordmark crowds the artwork at poster size.
    var showsStudioLogo: Bool = true

    @Environment(\.hubProviderId) private var hubProviderId
    @State private var providerId: Int?
    @State private var studioAssetName: String?

    /// Maps TMDB provider IDs to local asset catalog names.
    private static func assetName(for providerId: Int) -> String? {
        switch providerId {
        case 8:              return "Netflix_Logomark"
        case 337:            return "Disney+_2024"
        case 384, 1899:      return "HBO_Max_(2025)"
        case 15:             return "Hulu_logo_(2018)"
        case 531, 582:       return "Paramount+_logo"
        case 9, 10, 119:     return "Prime_Video"
        case 350:            return "Apple_TV_logo"
        case 386:            return "NBCUniversal_Peacock_Logo_(2026;_icon)"
        default:             return nil
        }
    }

    var body: some View {
        let streamingAsset = providerId.flatMap { Self.assetName(for: $0) }

        HStack(spacing: badgeSpacing) {
            // Streaming platform logo (shown when on a tracked streaming service)
            if let streamingAsset {
                Image(streamingAsset)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .modifier(BadgeSizeModifier(scale: scale))
            }

            // Vertical divider, only when both a streaming logo and studio logo show
            if streamingAsset != nil, studioAssetName != nil {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(0.6))
                    .frame(width: dividerWidth, height: dividerHeight)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            }

            // Studio logo (shown when the owning studio is recognized)
            if let studioAssetName {
                Image(studioAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .modifier(StudioBadgeSizeModifier(scale: studioScale))
            }
        }
        .task(id: mediaId) {
            // Resolve the streaming provider
            if let hubProviderId {
                providerId = hubProviderId
            } else if let id = await StreamingBadgeCache.shared.primaryProviderId(
                mediaId: mediaId,
                mediaType: mediaType
            ) {
                providerId = id
            }

            // Resolve the owning studio logo (skipped entirely when not shown,
            // so poster rows don't fire per-item detail requests)
            if showsStudioLogo {
                studioAssetName = await StudioBadgeCache.shared.studioAssetName(
                    mediaId: mediaId,
                    mediaType: mediaType
                )
            }
        }
    }

    #if os(tvOS)
    private var badgeSpacing: CGFloat { 12 * scale }
    private var dividerWidth: CGFloat { 2 }
    private var dividerHeight: CGFloat { 30 * scale }
    #else
    private var badgeSpacing: CGFloat { 6 * scale }
    private var dividerWidth: CGFloat { 1 }
    private var dividerHeight: CGFloat { 14 * scale }
    #endif
}

private struct BadgeSizeModifier: ViewModifier {
    var scale: CGFloat = 1
    func body(content: Content) -> some View {
        content
            #if os(tvOS)
            .frame(width: 40 * scale, height: 40 * scale)
            .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
            #else
            .frame(width: 18 * scale, height: 18 * scale)
            .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
            #endif
    }
}

/// Studio logos are constrained by height only, letting wordmark-style logos
/// (e.g. Disney) keep their natural aspect ratio.
private struct StudioBadgeSizeModifier: ViewModifier {
    var scale: CGFloat = 1
    func body(content: Content) -> some View {
        content
            #if os(tvOS)
            .frame(height: 40 * scale)
            .frame(maxWidth: 80 * scale)
            .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
            #else
            .frame(height: 18 * scale)
            .frame(maxWidth: 38 * scale)
            .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
            #endif
    }
}
