//
//  AdService.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import Combine
#if canImport(GoogleMobileAds) && !os(tvOS)
import GoogleMobileAds
#endif

/// Manages Google AdMob ad loading and visibility based on subscription status.
/// Ads are hidden for Scout Unlimited subscribers, Kids profiles, and tvOS.
@MainActor
class AdService: ObservableObject {
    static let shared = AdService()
    
    // MARK: - Test Ad Unit IDs (replace with real IDs once AdMob account is verified)
    static let testBannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"
    
    /// Whether ads should be displayed to the current user
    @Published private(set) var shouldShowAds: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        #if !os(tvOS)
        updateAdVisibility()
        
        // React to subscription status changes
        ScoutSubscriptionService.shared.$isUnlimitedActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateAdVisibility() }
            .store(in: &cancellables)
        
        // React to profile/settings changes (e.g., Kids mode toggled)
        StorageService.shared.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateAdVisibility() }
            .store(in: &cancellables)
        #endif
    }
    
    /// Initialize the Google Mobile Ads SDK. Call once at app launch.
    func configure() {
        #if canImport(GoogleMobileAds) && !os(tvOS)
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        #endif
    }
    
    private func updateAdVisibility() {
        #if os(tvOS)
        shouldShowAds = false
        #else
        let isSubscriber = ScoutSubscriptionService.shared.isUnlimitedActive
        let isKids = StorageService.shared.settings.isKidsProfile
        shouldShowAds = !isSubscriber && !isKids
        #endif
    }
}
