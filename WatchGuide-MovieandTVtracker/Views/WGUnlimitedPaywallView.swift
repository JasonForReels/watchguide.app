//
//  WGUnlimitedPaywallView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if os(iOS)
import RevenueCat
import RevenueCatUI
#endif

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

/// The paywall every upgrade entry point presents. Once the current RevenueCat offering
/// has a paywall published in the dashboard it is shown, so copy, layout and pricing can
/// change without an app update. Until then (and on platforms RevenueCatUI does not
/// cover) the built-in paywall is used.
struct WGSubscriptionPaywallView: View {
    var context: PaywallContext = .unlimited
    @ObservedObject private var subscription = ScoutSubscriptionService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS)
        if let offering = subscription.currentOffering, offering.hasPaywall, !subscription.isProActive {
            PaywallView(offering: offering, displayCloseButton: true)
                .onPurchaseCompleted { _ in dismiss() }
                .onRestoreCompleted { info in
                    if info.entitlements[ScoutSubscriptionService.proEntitlementID]?.isActive == true {
                        dismiss()
                    }
                }
        } else {
            WGBuiltInPaywallView(context: context)
        }
        #else
        WGBuiltInPaywallView(context: context)
        #endif
    }
}

// MARK: - Built-in Paywall

private struct WGBuiltInPaywallView: View {
    var context: PaywallContext = .unlimited
    @ObservedObject private var subscription = ScoutSubscriptionService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: ProPlan = .annual
    @State private var purchaseMessage: String?

    // MARK: - Fallback Prices
    //
    // Shown only until StoreKit returns real localized prices. Keep these in step with
    // App Store Connect, and never present one as final — the live App Store price always wins.

    private func fallback(_ usd: String, _ zar: String, _ gbp: String, _ eur: String) -> String {
        switch Locale.current.currency?.identifier {
        case "ZAR": return zar
        case "GBP": return gbp
        case "EUR": return eur
        default:    return usd
        }
    }

    private var monthlyPrice: String {
        subscription.monthlyProduct?.localizedPriceString ?? fallback("$4.99", "R44.99", "£4.49", "€4.99")
    }

    private var annualPrice: String {
        subscription.annualProduct?.localizedPriceString ?? fallback("$29.99", "R249", "£26.99", "€29.99")
    }

    private var lifetimePrice: String {
        subscription.lifetimeProduct?.localizedPriceString ?? fallback("$79.99", "R699", "£69.99", "€79.99")
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
                detail: "Jump straight into the right app")
    ]

    // MARK: - Body

    @State private var snapshot = PaywallLibrarySnapshot(
        posterURLs: [], trackedCount: 0, watchedCount: 0, hoursWatched: 0,
        tonightPick: nil, tonightPickDaysWaiting: 0
    )
    @State private var trendingPosterURLs: [URL] = []
    @State private var showsWelcome = false

    /// The user's own posters where there are enough to fill the wall, topped up
    /// with what's trending so a brand-new library still gets a full wall.
    private var wallURLs: [URL] {
        let own = snapshot.posterURLs
        guard own.count < 16 else { return own }
        let ownSet = Set(own)
        return own + trendingPosterURLs.filter { !ownSet.contains($0) }
    }

    /// Length of the annual plan's free trial, read from the App Store offer.
    private var trialDays: Int {
        #if os(iOS)
        if let period = subscription.annualProduct?.introductoryDiscount?.subscriptionPeriod {
            switch period.unit {
            case .day:   return period.value
            case .week:  return period.value * 7
            case .month: return period.value * 30
            case .year:  return period.value * 365
            @unknown default: break
            }
        }
        #endif
        return 7
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PaywallPosterWall(urls: wallURLs)
                .opacity(wallURLs.isEmpty ? 0 : 0.6)
                .animation(.easeIn(duration: 0.8), value: wallURLs.isEmpty)
                .ignoresSafeArea()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.15), location: 0),
                    .init(color: .black.opacity(0.55), location: 0.28),
                    .init(color: .black.opacity(0.92), location: 0.5),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    header
                        .padding(.top, 150)
                    if snapshot.isPersonal {
                        statsRow.wgStaggeredAppear(index: 1)
                    }
                    PaywallAtlasPreview(snapshot: snapshot)
                        .wgStaggeredAppear(index: 2)
                    benefitGrid
                    if !subscription.isProActive {
                        planPicker
                        if showsTrial && selectedPlan == .annual {
                            PaywallTrialTimeline(trialDays: trialDays, renewalPrice: annualPrice)
                                .padding(18)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    } else {
                        Label("WatchGuide Pro is active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.weight(.semibold))
                    }
                    if let purchaseMessage {
                        Text(purchaseMessage)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    legal
                }
                .padding(.horizontal, 20)
                .animation(WGMotion.smooth, value: selectedPlan)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                if !subscription.isProActive { purchaseDock }
            }

            if showsWelcome {
                PaywallWelcomeView(posterURLs: wallURLs) { dismiss() }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !showsWelcome {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(.trailing, 16)
                .padding(.top, 8)
                .accessibilityLabel("Close")
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: selectedPlan)
        #endif
        .task {
            snapshot = PaywallLibrarySnapshot.current()
            await subscription.loadProducts()
        }
        .task { await loadTrendingPosters() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "play.tv.fill")
                Text("WATCHGUIDE PRO")
            }
            .font(.caption.weight(.heavy))
            .tracking(2.4)
            .foregroundStyle(LinearGradient(colors: [.yellow, .orange],
                                            startPoint: .leading, endPoint: .trailing))

            Text(snapshot.isPersonal ? "Your taste,\nsupercharged." : "Never wonder\nwhat's next.")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 16)

            Text(snapshot.isPersonal
                 ? "You've built a library worth bragging about. Pro gives it superpowers."
                 : "Ask anything, plan every cinema trip, and see your watching like never before.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            if showsTrial && !subscription.isProActive {
                Text("\(trialDays) days free")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.orange.gradient, in: Capsule())
                    .padding(.top, 2)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            PaywallStat(value: snapshot.trackedCount, label: "Tracked")
            PaywallStat(value: snapshot.watchedCount, label: "Watched")
            if snapshot.hoursWatched > 0 {
                PaywallStat(value: snapshot.hoursWatched, label: "Hours")
            }
        }
        .padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Atlas has its own preview card above, so the grid starts after it.
    private var benefitGrid: some View {
        let cards = Array(benefits.dropFirst())
        let rows = stride(from: 0, to: cards.count, by: 2).map { Array(cards[$0..<min($0 + 2, cards.count)]) }
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.element.id) { column, benefit in
                        benefitCard(benefit)
                            .wgStaggeredAppear(index: rowIndex * 2 + column + 3)
                    }
                }
            }
        }
    }

    private func benefitCard(_ benefit: Benefit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: benefit.icon)
                .font(.title3)
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 3) {
                Text(benefit.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(benefit.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            planRow(.annual,
                    title: "Annual",
                    price: annualPrice,
                    period: subscription.annualProduct?.localizedPricePerMonth.map { "Just \($0)/month, billed yearly" }
                        ?? "per year",
                    badge: subscription.annualSavingsPercent.map { "SAVE \($0)%" })
            planRow(.monthly,
                    title: "Monthly",
                    price: monthlyPrice,
                    period: "per month",
                    badge: nil)
            if subscription.lifetimeProduct != nil {
                planRow(.lifetime,
                        title: "Lifetime",
                        price: lifetimePrice,
                        period: "one-time payment",
                        badge: nil)
            }
        }
    }

    private func planRow(_ plan: ProPlan, title: String, price: String, period: String, badge: String?) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.orange : Color.white.opacity(0.35))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.green.gradient, in: Capsule())
                                .foregroundStyle(.black)
                        }
                    }
                    Text(period)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Text(price)
                    .font(.headline)
                    .monospacedDigit()
            }
            .padding(16)
            .background(isSelected ? Color.orange.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? Color.orange : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            )
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .scaleEffect(isSelected ? 1 : 0.98)
            .contentShape(Rectangle())
        }
        .buttonStyle(.wgPress)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// The purchase button stays pinned above the home indicator, so the offer is
    /// always one tap away however far the user scrolls.
    private var purchaseDock: some View {
        VStack(spacing: 8) {
            Button {
                Task { await buy() }
            } label: {
                HStack(spacing: 8) {
                    if subscription.isPurchasing {
                        ProgressView().tint(.white)
                    }
                    Text(callToAction)
                        .font(.headline)
                        .contentTransition(.interpolate)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.1), .orange,
                                                     Color(red: 0.95, green: 0.35, blue: 0.1)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .modifier(PaywallSheen())
                .clipShape(Capsule())
                .shadow(color: .orange.opacity(0.45), radius: 18, y: 6)
                .foregroundStyle(.white)
            }
            .buttonStyle(.wgPress)
            .disabled(subscription.isPurchasing)
            .animation(WGMotion.snappy, value: selectedPlan)

            Text(priceCaption)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)

            restoreButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .background {
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0),
                                   .init(color: .black.opacity(0.94), location: 0.3),
                                   .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .padding(.top, -28)
                .ignoresSafeArea()
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
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.7))
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
            .tint(.white)
            .padding(.top, 4)
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.5))
        .multilineTextAlignment(.center)
        .padding(.bottom, 24)
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
        if case .success = outcome {
            withAnimation(.easeInOut(duration: 0.5)) { showsWelcome = true }
        } else {
            purchaseMessage = outcome.message
        }
    }

    /// Fills out the poster wall for libraries too small to cover it alone.
    private func loadTrendingPosters() async {
        guard trendingPosterURLs.isEmpty else { return }
        async let movies = try? TMDBService.shared.getTrending(mediaType: .movie)
        async let shows = try? TMDBService.shared.getTrending(mediaType: .tv)
        let items = (await movies?.results ?? []) + (await shows?.results ?? [])
        trendingPosterURLs = items.compactMap {
            TMDBService.shared.imageURL(path: $0.posterPath, size: .small)
        }
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
