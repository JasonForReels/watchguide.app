//
//  StreamingLogoBadge.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

// MARK: - Streaming Badge Cache

/// Fetches and caches the primary streaming provider ID for each media item.
actor StreamingBadgeCache {
    static let shared = StreamingBadgeCache()

    /// Provider IDs we track badges for (only the big 5 with local logo assets).
    static let trackedProviderIds: Set<Int> = [
        8,          // Netflix
        337,        // Disney+
        384, 1899,  // Max / HBO Max
        15,         // Hulu
        531, 582    // Paramount+
    ]

    private var cache: [String: Int?] = [:]
    private var inFlight: [String: Task<Int?, Never>] = [:]

    /// Returns the first tracked streaming provider ID for the given title, or `nil`.
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
                guard let region = response.results?[regionCode] ?? response.results?["US"] else {
                    return nil
                }

                // Look through flatrate (streaming) providers for the first tracked one
                let flatrate = region.flatrate ?? []
                return flatrate.first(where: { Self.trackedProviderIds.contains($0.providerId) })?.providerId
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

/// A small badge showing the streaming service logo, placed in the top-right corner of a poster.
struct StreamingLogoBadge: View {
    let mediaId: Int
    let mediaType: MediaType

    @State private var assetName: String?

    /// Maps TMDB provider IDs to local asset names in "Streaming logos".
    private static func assetName(for providerId: Int) -> String? {
        switch providerId {
        case 8:              return "Netflix_Logomark"
        case 337:            return "Disney+_2024"
        case 384, 1899:      return "HBO_Max_(2025)"
        case 15:             return "Hulu_logo_(2018)"
        case 531, 582:       return "Paramount+_logo"
        default:             return nil
        }
    }

    var body: some View {
        Group {
            if let assetName {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .padding(4)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            }
        }
        .task(id: mediaId) {
            guard let providerId = await StreamingBadgeCache.shared.primaryProviderId(
                mediaId: mediaId,
                mediaType: mediaType
            ) else { return }
            assetName = Self.assetName(for: providerId)
        }
    }
}
