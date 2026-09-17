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
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.15),
                                Color.purple.opacity(0.10),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let imageURL = URL(string: banner.imageUrl), !banner.imageUrl.isEmpty {
                    ResilientAsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 500, maxHeight: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        case .failure:
                            localBannerFallback
                        case .empty:
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .frame(maxWidth: 500, minHeight: 50, maxHeight: 60)
                                .overlay {
                                    ProgressView()
                                        .tint(.white.opacity(0.5))
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    localBannerFallback
                }
            }
        }
        .buttonStyle(BannerPressButtonStyle())
        .frame(maxWidth: .infinity, alignment: .center)
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
    }

    // MARK: - Label Style

    private func labelBanner(_ banner: AffiliateBanner) -> some View {
        Button {
            openAffiliateURL(banner.affiliateUrl)
        } label: {
            HStack(spacing: 10) {
                if !banner.title.isEmpty {
                    Text(banner.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.88))
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

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(BannerPressButtonStyle())
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Card Style

    private func cardBanner(_ banner: AffiliateBanner) -> some View {
        Button {
            openAffiliateURL(banner.affiliateUrl)
        } label: {
            HStack(spacing: 14) {
                if let logoURL = URL(string: banner.logoUrl), !banner.logoUrl.isEmpty {
                    ResilientAsyncImage(url: logoURL) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 28)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    if !banner.title.isEmpty {
                        Text(banner.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    if !banner.subtitle.isEmpty {
                        Text(banner.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(BannerPressButtonStyle())
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
    }

    // MARK: - Local Fallbacks

    private var localBannerFallback: some View {
        Image("NordVPNBanner")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 500, maxHeight: 60)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

// MARK: - Press Animation Button Style

private struct BannerPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
