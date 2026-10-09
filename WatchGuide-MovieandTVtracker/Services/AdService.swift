//
//  AdService.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import Combine

/// Decides whether affiliate banners are shown. There is no ad SDK in the app:
/// the only monetisation surface is the remote-configured affiliate banners.
/// Hidden for WatchGuide Pro subscribers and Kids profiles; works on all platforms.
@MainActor
class AdService: NSObject, ObservableObject {
    static let shared = AdService()

    /// Whether affiliate banners (NordVPN etc.) should be displayed.
    @Published private(set) var shouldShowAffiliateBanners: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        updateVisibility()

        // React to subscription status changes
        ScoutSubscriptionService.shared.$isUnlimitedActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateVisibility() }
            .store(in: &cancellables)

        // React to profile/settings changes (e.g., Kids mode toggled)
        StorageService.shared.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateVisibility() }
            .store(in: &cancellables)
    }

    private func updateVisibility() {
        let isSubscriber = ScoutSubscriptionService.shared.isUnlimitedActive
        let isKids = StorageService.shared.settings.isKidsProfile
        shouldShowAffiliateBanners = !isSubscriber && !isKids
    }
}
