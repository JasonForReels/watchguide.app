//
//  AdService.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import Combine
#if canImport(UnityAds) && !os(tvOS)
import UnityAds
#endif

/// Manages Unity Ads loading and visibility based on subscription status.
/// Ads are hidden for WatchGuide Pro subscribers, Kids profiles, and tvOS.
@MainActor
class AdService: NSObject, ObservableObject {
    static let shared = AdService()
    
    // MARK: - Unity Ads Configuration
    /// Replace with your Unity Ads Game ID from the Unity Dashboard
    static let gameID = "6111856"
    /// Replace with your Unity Ads banner placement ID
    static let bannerPlacementID = "iOS_Banner_1"
    /// Set to false for production
    static let testMode = true
    
    /// Whether Unity Ads should be displayed to the current user
    @Published private(set) var shouldShowAds: Bool = false
    
    /// Whether affiliate banners (NordVPN etc.) should be displayed.
    /// Unlike shouldShowAds, this works on all platforms including tvOS.
    @Published private(set) var shouldShowAffiliateBanners: Bool = false
    
    /// Whether the Unity Ads SDK has been initialized successfully
    @Published private(set) var isSDKInitialized: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private override init() {
        super.init()
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
    }
    
    /// Initialize the Unity Ads SDK. Call once at app launch.
    func configure() {
        #if canImport(UnityAds) && !os(tvOS)
        guard !UnityServices.isInitialized() else { return }
        UnityServices.initialize(Self.gameID, testMode: Self.testMode, initializationDelegate: self)
        #endif
    }
    
    private func updateAdVisibility() {
        let isSubscriber = ScoutSubscriptionService.shared.isUnlimitedActive
        let isKids = StorageService.shared.settings.isKidsProfile
        
        // Affiliate banners work on all platforms
        shouldShowAffiliateBanners = !isSubscriber && !isKids
        
        // Unity Ads only on non-tvOS
        #if os(tvOS)
        shouldShowAds = false
        #else
        shouldShowAds = !isSubscriber && !isKids
        #endif
    }
}

#if canImport(UnityAds) && !os(tvOS)
extension AdService: UnityAdsInitializationDelegate {
    nonisolated func initializationComplete() {
        print("[AdService] Unity Ads initialized successfully")
        Task { @MainActor in
            self.isSDKInitialized = true
        }
    }
    
    nonisolated func initializationFailed(_ error: UnityAdsInitializationError, withMessage message: String) {
        print("[AdService] Unity Ads initialization failed: \(message)")
    }
}
#endif
