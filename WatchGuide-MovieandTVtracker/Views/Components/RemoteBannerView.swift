//
//  RemoteBannerView.swift
//  WatchGuide-MovieandTVtracker
//
//  Drop-in SwiftUI component for remote-configurable affiliate banners.
//  Fetches banners from AffiliateBannerService, filtered by placement and geo.
//

import SwiftUI

struct RemoteBannerView: View {
    let placement: BannerPlacement

    @ObservedObject private var adService = AdService.shared
    @State private var banners: [AffiliateBanner] = []
    @State private var hasLoaded = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        if adService.shouldShowAffiliateBanners {
            if !banners.isEmpty {
                ForEach(banners) { banner in
                    bannerContent(for: banner)
                }
            } else if !hasLoaded {
                Color.clear
                    .frame(height: 0)
                    .task { await loadBanners() }
            }
        }
    }

    // MARK: - Style Router

    @ViewBuilder
    private func bannerContent(for banner: AffiliateBanner) -> some View {
        switch BannerStyle(rawValue: banner.style) ?? .fullImage {
        case .fullImage:
            fullImageBanner(banner)
        case .label:
            labelBanner(banner)
        case .card:
            cardBanner(banner)
        }
    }

    // MARK: - Full Image Style

    private func fullImageBanner(_ banner: AffiliateBanner) -> some View {
        Button {
            openAffiliateURL(banner.affiliateUrl)
        } label: {
            if let imageURL = URL(string: banner.imageUrl), !banner.imageUrl.isEmpty {
                ResilientAsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    case .failure:
                        localBannerFallback
                    case .empty:
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.clear)
                            .frame(maxWidth: 300, minHeight: 50)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                localBannerFallback
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Label Style

    private func labelBanner(_ banner: AffiliateBanner) -> some View {
        HStack(spacing: 8) {
            if !banner.title.isEmpty {
                Text(banner.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.75))
            }

            if let logoURL = URL(string: banner.logoUrl), !banner.logoUrl.isEmpty {
                ResilientAsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 22)
                    case .failure:
                        localLogoFallback
                    case .empty:
                        Color.clear.frame(width: 60, height: 22)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                localLogoFallback
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
        .focusable(false)
        .onTapGesture {
            openAffiliateURL(banner.affiliateUrl)
        }
    }

    // MARK: - Card Style

    private func cardBanner(_ banner: AffiliateBanner) -> some View {
        Button {
            openAffiliateURL(banner.affiliateUrl)
        } label: {
            HStack(spacing: 10) {
                if let logoURL = URL(string: banner.logoUrl), !banner.logoUrl.isEmpty {
                    ResilientAsyncImage(url: logoURL) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 24)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    if !banner.title.isEmpty {
                        Text(banner.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    if !banner.subtitle.isEmpty {
                        Text(banner.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Local Fallbacks

    private var localBannerFallback: some View {
        Image("NordVPNBanner")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 300)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var localLogoFallback: some View {
        Image("NordVPNLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 22)
    }

    // MARK: - Helpers

    private func openAffiliateURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }

    private func loadBanners() async {
        let fetched = await AffiliateBannerService.shared.banners(for: placement)
        banners = fetched
        hasLoaded = true
    }
}
