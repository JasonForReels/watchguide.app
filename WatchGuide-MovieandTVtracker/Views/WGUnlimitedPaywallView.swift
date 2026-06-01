//
//  WGUnlimitedPaywallView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct WGUnlimitedPaywallView: View {
    @ObservedObject private var subscription = ScoutSubscriptionService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var purchaseMessage: String?

    private let features: [(icon: String, title: String, description: String)] = [
        ("bubble.left.and.bubble.right.fill", "Unlimited Scout AI Messages", "Ask Scout anything — no daily message cap."),
        ("film.fill", "Unlimited Post-Credits Checks", "Find out if a movie has a post-credits scene, every time."),
        ("map.fill", "Unlimited Cinema Trip Plans", "Plan as many cinema trips as you want each month."),
        ("link", "Deep Link Cache Warm-Up", "Streaming deep links load instantly for your whole library."),
        ("nosign", "Ad-Free Experience", "No banner ads or affiliate promotions.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.yellow, .orange)

                        Text("WG Unlimited")
                            .font(.title.bold())

                        Text("Unlock the full WatchGuide experience")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    // Feature List
                    VStack(spacing: 0) {
                        ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: feature.icon)
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 30, alignment: .center)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(feature.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)

                            if index < features.count - 1 {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)

                    // Free Plan Comparison
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Free plan includes:")
                            .font(.subheadline.weight(.semibold))
                        VStack(alignment: .leading, spacing: 4) {
                            Label("5 Scout AI messages per day", systemImage: "bubble.left")
                            Label("1 cinema trip plan per month", systemImage: "map")
                            Label("4 post-credits checks per month", systemImage: "film")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)

                    // Purchase Buttons
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                let outcome = await subscription.purchaseScoutUnlimited()
                                purchaseMessage = outcome.message
                            }
                        } label: {
                            HStack {
                                if subscription.isPurchasing {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("Subscribe — \(subscription.subscriptionProduct?.displayPrice ?? "$3.99")/month")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(subscription.isUnlimitedActive || subscription.isPurchasing)

                        if subscription.lifetimeProduct != nil {
                            Button {
                                Task {
                                    let outcome = await subscription.purchaseScoutUnlimitedLifetime()
                                    purchaseMessage = outcome.message
                                }
                            } label: {
                                Text("Buy Lifetime — \(subscription.lifetimeProduct?.displayPrice ?? "")")
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .disabled(subscription.isUnlimitedActive || subscription.isPurchasing)
                        }

                        Button("Restore Purchases") {
                            Task {
                                await subscription.restorePurchases()
                                purchaseMessage = subscription.isUnlimitedActive
                                    ? "Subscription restored."
                                    : "No active WG Unlimited subscription found."
                            }
                        }
                        .font(.subheadline)
                        .disabled(subscription.isPurchasing)
                    }
                    .padding(.horizontal, 16)

                    if subscription.isUnlimitedActive {
                        Label("WG Unlimited is active", systemImage: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.subheadline.weight(.semibold))
                    }

                    if let purchaseMessage {
                        Text(purchaseMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    // Legal
                    VStack(spacing: 4) {
                        Text("Auto-renewable monthly subscription. Payment is charged to your Apple Account at confirmation. Subscription renews automatically unless canceled at least 24 hours before the end of the current period. Manage or cancel in Settings > Apple Account > Subscriptions.")
                        HStack(spacing: 16) {
                            if let url = URL(string: "https://www.watchguide.app/#/privacy") {
                                Link("Privacy Policy", destination: url)
                            }
                            if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                                Link("Terms of Use", destination: url)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("WG Unlimited")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Upgrade Lock Button

/// A small lock icon that presents the WG Unlimited paywall when tapped.
/// Use this next to features that are gated behind WG Unlimited.
struct WGUnlimitedLockButton: View {
    @ObservedObject private var subscription = ScoutSubscriptionService.shared
    @State private var showPaywall = false

    var body: some View {
        if !subscription.isUnlimitedActive {
            Button {
                showPaywall = true
            } label: {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPaywall) {
                WGUnlimitedPaywallView()
            }
        }
    }
}

/// A modifier that shows the upgrade paywall as a sheet.
struct WGUnlimitedUpgradeModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            WGUnlimitedPaywallView()
        }
    }
}

extension View {
    func wgUnlimitedUpgradeSheet(isPresented: Binding<Bool>) -> some View {
        modifier(WGUnlimitedUpgradeModifier(isPresented: isPresented))
    }
}
