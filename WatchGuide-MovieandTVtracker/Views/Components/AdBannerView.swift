//
//  AdBannerView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if canImport(UnityAds) && !os(tvOS)
import UnityAds
#endif

/// A SwiftUI view that displays a Unity Ads banner ad.
/// Only renders content when Unity Ads SDK is available and not on tvOS.
struct AdBannerView: View {
    @ObservedObject private var adService = AdService.shared
    
    var body: some View {
        #if os(tvOS)
        EmptyView()
        #elseif canImport(UnityAds)
        if adService.shouldShowAds && adService.isSDKInitialized {
            UnityBannerRepresentable()
                .frame(height: 50)
                .frame(maxWidth: .infinity)
        }
        #else
        EmptyView()
        #endif
    }
}

#if canImport(UnityAds) && !os(tvOS)

/// UIViewRepresentable for UADSBannerView with automatic retry on failure
private struct UnityBannerRepresentable: UIViewRepresentable {
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        
        context.coordinator.container = container
        context.coordinator.loadNewBanner(in: container)
        
        return container
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // No-op: banner lifecycle managed by coordinator
    }
    
    class Coordinator: NSObject, UADSBannerViewDelegate {
        weak var container: UIView?
        private var retryCount = 0
        private let maxRetries = 5
        private var currentBanner: UADSBannerView?
        
        func loadNewBanner(in container: UIView) {
            currentBanner?.removeFromSuperview()
            
            let banner = UADSBannerView(placementId: AdService.bannerPlacementID, size: CGSize(width: 320, height: 50))
            banner.delegate = self
            banner.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(banner)
            
            NSLayoutConstraint.activate([
                banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                banner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                banner.widthAnchor.constraint(equalToConstant: 320),
                banner.heightAnchor.constraint(equalToConstant: 50)
            ])
            
            currentBanner = banner
            banner.load()
        }
        
        func bannerViewDidLoad(_ bannerView: UADSBannerView) {
            retryCount = 0
        }
        
        func bannerViewDidShow(_ bannerView: UADSBannerView) { }
        
        func bannerViewDidClick(_ bannerView: UADSBannerView) { }
        
        func bannerViewDidLeaveApplication(_ bannerView: UADSBannerView) { }
        
        func bannerViewDidError(_ bannerView: UADSBannerView, error: UADSBannerError) {
            guard retryCount < maxRetries, let container = container else { return }
            retryCount += 1
            
            let delay = TimeInterval(5 * (1 << (retryCount - 1)))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.loadNewBanner(in: container)
            }
        }
    }
}
#endif
