//
//  WGUnlimitedPaywallView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

// MARK: - Paywall Context

/// Retained so existing call sites keep compiling. WatchGuide Pro is the only paid
/// tier now, so the context no longer changes what the paywall offers.
enum PaywallContext {
    case plus
    case unlimited
}

// MARK: - Plan

private enum ProPlan: Hashable {
    case annual
    case monthly
    case lifetime
}

// MARK: - Paywall

struct WGSubscriptionPaywallView: View {
    var context: PaywallContext = .unlimited
    @ObservedObject private var subscription = ScoutSubscriptionService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: ProPlan = .annual
    @State private var purchaseMessage: String?

    // MARK: - Fallback Prices
    //
    // Shown only until StoreKit returns real localized prices. Keep these in step with
    // App Store Connect, and never present one as final — `displayPrice` always wins.

    private func fallback(_ usd: String, _ zar: String, _ gbp: String, _ eur: String) -> String {
        switch Locale.current.currency?.identifier {
        case "ZAR": return zar
        case "GBP": return gbp
        case "EUR": return eur
        default:    return usd
        }
    }

    private var monthlyPrice: String {
        subscription.monthlyProduct?.displayPrice ?? fallback("$4.99", "R44.99", "£4.49", "€4.99")
    }

    private var annualPrice: String {
        subscription.annualProduct?.displayPrice ?? fallback("$29.99", "R249", "£26.99", "€29.99")
    }

    private var lifetimePrice: String {
        subscription.lifetimeProduct?.displayPrice ?? fallback("$79.99", "R699", "£69.99", "€79.99")
    }

    private var showsTrial: Bool {
        subscription.isEligibleForIntroOffer
    }

    // MARK: - Benefits

    private struct Benefit: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private let benefits: [Benefit] = [
        Benefit(icon: "bubble.left.and.bubble.right.fill",
                title: "Ask Atlas anything",
                detail: "Unlimited questions about any film or show"),
        Benefit(icon: "film.fill",
                title: "Post-credits checks",
                detail: "Know before you leave your seat"),
        Benefit(icon: "map.fill",
                title: "Cinema trip planning",
                detail: "Live traffic tells you when to leave"),
        Benefit(icon: "folder.fill",
                title: "Unlimited lists",
                detail: "Organize everything, no cap"),
        Benefit(icon: "sparkles.rectangle.stack",
                title: "AI playlists & share cards",
                detail: "Curated picks worth sharing"),
        Benefit(icon: "chart.bar.fill",
                title: "Stats & insights",
                detail: "Your watching, properly measured"),
        Benefit(icon: "link",
                title: "Instant deep links",
                detail: "Jump straight into the right app"),
        Benefit(icon: "rectangle.slash",
                title: "No ads",
                detail: "Nothing between you and what's next")
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefitList
                    if !subscription.isProActive {
                        planPicker
                        purchaseButton
                    }
                    restoreButton
                    if subscription.isProActive {
                        Label("WatchGuide Pro is active", systemImage: "checkmark.seal.fill")
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
                    legal
                }
            }
            .background(Color.groupedBackground)
            .navigationTitle("WatchGuide Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await subscription.loadProducts() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow, .orange)

            Text("WatchGuide Pro")
                .font(.title.bold())

            Text(showsTrial
                 ? "Try everything free for 7 days"
                 : "Everything WatchGuide can do")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private var benefitList: some View {
        VStack(spacing: 0) {
            ForEach(Array(benefits.enumerated()), id: \.element.id) { index, benefit in
                if index > 0 { Divider().padding(.leading, 48) }
                HStack(spacing: 12) {
                    Image(systemName: benefit.icon)
                        .font(.body)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(benefit.title)
                            .font(.subheadline.weight(.semibold))
                        Text(benefit.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(Color.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            planRow(.annual,
                    title: "Annual",
                    price: annualPrice,
                    period: "per year",
                    badge: subscription.annualSavingsPercent.map { "SAVE \($0)%" })
            planRow(.monthly,
                    title: "Monthly",
                    price: monthlyPrice,
                    period: "per month",
                    badge: nil)
            planRow(.lifetime,
                    title: "Lifetime",
                    price: lifetimePrice,
                    period: "one-time payment",
                    badge: nil)
        }
        .padding(.horizontal, 16)
    }

    private func planRow(_ plan: ProPlan, title: String, price: String, period: String, badge: String?) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                        }
                    }
                    Text(period)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                Text(price)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .padding(14)
            .background(Color.secondaryGroupedBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var purchaseButton: some View {
        VStack(spacing: 6) {
            Button {
                Task { await buy() }
            } label: {
                HStack {
                    if subscription.isPurchasing {
                        ProgressView().tint(.white)
                    }
                    Text(callToAction)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(subscription.isPurchasing)

            Text(priceCaption)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
    }

    private var callToAction: String {
        switch selectedPlan {
        case .lifetime: return "Buy Lifetime — \(lifetimePrice)"
        case .annual:   return showsTrial ? "Start 7-Day Free Trial" : "Continue — \(annualPrice)/year"
        case .monthly:  return "Continue — \(monthlyPrice)/month"
        }
    }

    private var priceCaption: String {
        switch selectedPlan {
        case .lifetime:
            return "One payment. Yours permanently."
        case .annual:
            return showsTrial
                ? "7 days free, then \(annualPrice)/year. Cancel anytime."
                : "\(annualPrice)/year. Cancel anytime."
        case .monthly:
            return "\(monthlyPrice)/month. Cancel anytime."
        }
    }

    private var restoreButton: some View {
        Button {
            Task {
                let outcome = await subscription.restorePurchases()
                switch outcome {
                case .success:
                    purchaseMessage = "WatchGuide Pro restored."
                default:
                    purchaseMessage = outcome.message
                }
            }
        } label: {
            HStack(spacing: 6) {
                if subscription.isPurchasing {
                    ProgressView().controlSize(.mini)
                }
                Text("Restore Purchases")
            }
        }
        .font(.subheadline)
        .disabled(subscription.isPurchasing)
    }

    private var legal: some View {
        VStack(spacing: 4) {
            Text(legalText)
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

    private var legalText: String {
        if selectedPlan == .lifetime {
            return "One-time purchase. Payment is charged to your Apple Account at confirmation. Not a subscription — nothing renews."
        }
        let trialSentence = showsTrial
            ? " Your free trial converts to a paid subscription unless canceled at least 24 hours before it ends."
            : ""
        return "Auto-renewable subscription. Payment is charged to your Apple Account at confirmation. Renews automatically unless canceled at least 24 hours before the end of the current period.\(trialSentence) Manage or cancel in Settings > Apple Account > Subscriptions."
    }

    // MARK: - Actions

    private func buy() async {
        let outcome: ScoutSubscriptionService.PurchaseOutcome
        switch selectedPlan {
        case .annual:   outcome = await subscription.purchaseProAnnual()
        case .monthly:  outcome = await subscription.purchaseProMonthly()
        case .lifetime: outcome = await subscription.purchaseProLifetime()
        }
        purchaseMessage = outcome.message
    }
}

/// Backward-compatible typealias so existing call sites still compile.
typealias WGUnlimitedPaywallView = WGSubscriptionPaywallView

// MARK: - Upgrade Lock Button

/// A small lock icon that presents the paywall when tapped. Free users only.
struct WGUnlimitedLockButton: View {
    @ObservedObject private var subscription = ScoutSubscriptionService.shared
    var context: PaywallContext = .plus
    @State private var showPaywall = false

    var body: some View {
        if !subscription.isProActive {
            Button {
                showPaywall = true
            } label: {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPaywall) {
                WGSubscriptionPaywallView(context: context)
            }
        }
    }
}

// MARK: - Inline Locked Feature Card

/// Compact inline card shown in place of a Pro-gated feature for free users.
struct WGPlusLockedFeatureCard: View {
    let featureName: String
    let iconName: String
    var context: PaywallContext = .plus
    @State private var showPaywall = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(featureName)
                    .font(.caption.weight(.semibold))
                Text("Available with WatchGuide Pro")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Upgrade") { showPaywall = true }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
        }
        .padding(10)
        .background(Color.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $showPaywall) {
            WGSubscriptionPaywallView(context: context)
        }
    }
}

// MARK: - Upgrade Sheet Modifier

/// A modifier that shows the upgrade paywall as a sheet.
struct WGUnlimitedUpgradeModifier: ViewModifier {
    @Binding var isPresented: Bool
    var context: PaywallContext = .unlimited

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            WGSubscriptionPaywallView(context: context)
        }
    }
}

extension View {
    func wgUnlimitedUpgradeSheet(isPresented: Binding<Bool>, context: PaywallContext = .unlimited) -> some View {
        modifier(WGUnlimitedUpgradeModifier(isPresented: isPresented, context: context))
    }
}
