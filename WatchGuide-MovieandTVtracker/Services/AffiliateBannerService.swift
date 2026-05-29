//
//  AffiliateBannerService.swift
//  WatchGuide-MovieandTVtracker
//
//  Fetches, caches, and filters affiliate banners from a remote JSON config.
//

import Foundation

actor AffiliateBannerService {
    static let shared = AffiliateBannerService()

    // MARK: - Configuration

    /// Replace with the raw GitHub URL where banners.json is hosted
    private static let configURL = "https://raw.githubusercontent.com/YOUR_OWNER/YOUR_REPO/main/banners.json"
    private static let cacheTTL: TimeInterval = 30 * 60 // 30 minutes

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    private var cachedConfig: AffiliateBannerConfig?
    private var cacheTimestamp: Date?
    private var fetchTask: Task<AffiliateBannerConfig, Error>?

    private init() {}

    // MARK: - Public API

    /// Returns banners matching the given placement, filtered by country, platform, and date.
    func banners(for placement: BannerPlacement) async -> [AffiliateBanner] {
        let config = await fetchConfig()
        return filterBanners(config.banners, for: placement)
    }

    // MARK: - Fetch with Cache & Deduplication

    private func fetchConfig() async -> AffiliateBannerConfig {
        // Return cache if still fresh
        if let cached = cachedConfig,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < Self.cacheTTL {
            return cached
        }

        // Deduplicate concurrent fetches
        if let existing = fetchTask {
            do {
                return try await existing.value
            } catch {
                // Stale cache or fallback
                return cachedConfig ?? fallbackConfig()
            }
        }

        let task = Task<AffiliateBannerConfig, Error> {
            guard let url = URL(string: Self.configURL) else {
                throw URLError(.badURL)
            }
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return try JSONDecoder().decode(AffiliateBannerConfig.self, from: data)
        }

        fetchTask = task

        do {
            let config = try await task.value
            cachedConfig = config
            cacheTimestamp = Date()
            fetchTask = nil
            return config
        } catch {
            fetchTask = nil
            // Stale cache if available, otherwise hardcoded fallback
            return cachedConfig ?? fallbackConfig()
        }
    }

    // MARK: - Filtering

    private func filterBanners(_ banners: [AffiliateBanner], for placement: BannerPlacement) -> [AffiliateBanner] {
        let currentCountry = deviceCountryCode()
        let currentPlatform = devicePlatform()
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()

        return banners
            .filter { banner in
                guard banner.active else { return false }
                guard banner.placements.contains(placement.rawValue) else { return false }

                // Country filter: empty = global
                if !banner.countries.isEmpty {
                    guard banner.countries.contains(where: { $0.caseInsensitiveCompare(currentCountry) == .orderedSame }) else { return false }
                }

                // Platform filter: empty = all
                if !banner.platforms.isEmpty {
                    guard banner.platforms.contains(currentPlatform) else { return false }
                }

                // Date window
                if let startStr = banner.startDate, let start = isoFormatter.date(from: startStr) {
                    guard now >= start else { return false }
                }
                if let endStr = banner.endDate, let end = isoFormatter.date(from: endStr) {
                    guard now <= end else { return false }
                }

                return true
            }
            .sorted { $0.priority > $1.priority }
    }

    // MARK: - Device Info

    private func deviceCountryCode() -> String {
        if #available(iOS 16, tvOS 16, macOS 13, *) {
            return Locale.current.region?.identifier ?? "US"
        } else {
            return Locale.current.regionCode ?? "US"
        }
    }

    private func devicePlatform() -> String {
        #if os(tvOS)
        return "tvos"
        #elseif os(macOS)
        return "macos"
        #else
        return "ios"
        #endif
    }

    // MARK: - Hardcoded Fallback

    /// Returns the current NordVPN banners as a fallback when the remote JSON is unavailable.
    private func fallbackConfig() -> AffiliateBannerConfig {
        let labelBanner = AffiliateBanner(
            id: "fallback-nordvpn-label",
            active: true,
            priority: 10,
            partnerName: "NordVPN",
            title: "In Partnership with",
            subtitle: "",
            affiliateUrl: "https://go.nordvpn.net/aff_c?offer_id=15&aff_id=147783&url_id=902",
            imageUrl: "",
            logoUrl: "",
            style: BannerStyle.label.rawValue,
            placements: [BannerPlacement.browseHeader.rawValue],
            countries: [],
            platforms: [],
            startDate: nil,
            endDate: nil
        )

        let imageBanner = AffiliateBanner(
            id: "fallback-nordvpn-banner",
            active: true,
            priority: 10,
            partnerName: "NordVPN",
            title: "",
            subtitle: "",
            affiliateUrl: "https://go.nordvpn.net/aff_c?offer_id=15&aff_id=147783&url_id=902",
            imageUrl: "",
            logoUrl: "",
            style: BannerStyle.fullImage.rawValue,
            placements: [
                BannerPlacement.browseFooter.rawValue,
                BannerPlacement.discover.rawValue,
                BannerPlacement.search.rawValue,
                BannerPlacement.detail.rawValue,
                BannerPlacement.settings.rawValue
            ],
            countries: [],
            platforms: [],
            startDate: nil,
            endDate: nil
        )

        return AffiliateBannerConfig(version: 0, banners: [labelBanner, imageBanner])
    }
}
