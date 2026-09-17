import Foundation
import StoreKit

@MainActor
final class ScoutSubscriptionService: ObservableObject {
    static let shared = ScoutSubscriptionService()

    // MARK: - Product IDs
    //
    // WatchGuide Pro replaced the old WG Plus / WG Unlimited pair. Purchasable IDs and
    // entitlement IDs are deliberately separate lists: retiring a product from sale must
    // never revoke access for someone who already bought it.

    /// WatchGuide Pro, monthly. Same subscription group as the retired products.
    static let proMonthlyProductIDs = [
        "com.JasonSmith.WatchGuide-MovieandTVtracker.pro.monthly"
    ]
    /// WatchGuide Pro, annual. Carries the 7-day free trial as an introductory offer.
    static let proAnnualProductIDs = [
        "com.JasonSmith.WatchGuide-MovieandTVtracker.pro.annual"
    ]
    /// WatchGuide Pro, lifetime. A non-consumable, so it sits outside the subscription group.
    static let proLifetimeProductIDs = [
        "com.JasonSmith.WatchGuide-MovieandTVtracker.pro.lifetime"
    ]

    /// Retired from sale but still honored — **never remove an ID from this list.**
    /// Anyone holding one of these keeps full Pro access for as long as it stays valid.
    /// WG Plus is included deliberately: that tier no longer exists, so its subscribers
    /// are grandfathered *up* to full Pro rather than losing the features they paid for.
    static let legacyEntitlementProductIDs = [
        // WG Unlimited — monthly
        "scout_unlimited_monthly",
        "com.JasonSmith.WatchGuideMovieandTVtracker.scout_unlimited_monthly",
        "com.JasonSmith.WatchGuide-MovieandTVtracker.scout.unlimited.monthly",
        // WG Unlimited — lifetime
        "scout_unlimited_lifetime",
        "com.JasonSmith.WatchGuideMovieandTVtracker.scout_unlimited_lifetime",
        "com.JasonSmith.WatchGuide-MovieandTVtracker.scout.unlimited.lifetime",
        // WG Plus — grandfathered up to Pro
        "com.JasonSmith.WatchGuideMovieandTVtracker.wg_plus_monthly"
    ]

    /// Everything a new customer can buy today.
    static let purchasableProductIDs = proMonthlyProductIDs + proAnnualProductIDs + proLifetimeProductIDs

    /// Everything that grants Pro access, current or retired.
    static let proEntitlementProductIDs = purchasableProductIDs + legacyEntitlementProductIDs

    // MARK: - Keys & Notifications

    // Storage keys are unchanged so existing installs keep their entitlement across the rename.
    static let entitlementActiveKey = "scout_unlimited_entitlement_active"
    static let plusEntitlementActiveKey = "scout_plus_entitlement_active"
    /// Developer/admin override that simulates an active Pro entitlement for testing.
    static let adminUnlimitedOverrideKey = "wg_admin_unlimited_override"
    static let statusDidChangeNotification = Notification.Name("ScoutSubscriptionStatusDidChange")

    // MARK: - Published State

    /// True when WatchGuide Pro is active, from any current or legacy product.
    @Published private(set) var isUnlimitedActive: Bool
    /// Retained for the many call sites that only ask "is this a paying user?".
    /// Pro is now the only paid tier, so this always matches `isUnlimitedActive`.
    @Published private(set) var isPlusActive: Bool
    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var annualProduct: Product?
    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var isPurchasing = false
    @Published private(set) var isLoadingProduct = false
    /// False once the user has consumed an introductory offer anywhere in this
    /// subscription group. Gate all "7 days free" copy on this — offering a trial
    /// the App Store will not grant is the fastest way to earn a refund request.
    @Published private(set) var isEligibleForIntroOffer = false
    /// When true, Pro is treated as active regardless of real StoreKit entitlements.
    /// Intended for internal testing only.
    @Published private(set) var isAdminUnlimitedOverride: Bool

    /// Preferred name for new code.
    var isProActive: Bool { isUnlimitedActive }

    /// Annual saving versus paying monthly for twelve months, e.g. `50` for "Save 50%".
    /// Returns nil until both products load, so the UI can omit the badge rather than guess.
    var annualSavingsPercent: Int? {
        guard let monthlyProduct, let annualProduct else { return nil }
        let twelveMonths = monthlyProduct.price * 12
        guard twelveMonths > 0, annualProduct.price < twelveMonths else { return nil }
        let saved = (twelveMonths - annualProduct.price) / twelveMonths * 100
        return Int(NSDecimalNumber(decimal: saved).doubleValue.rounded())
    }

    private var updatesTask: Task<Void, Never>?
    
    enum PurchaseOutcome {
        case success
        case cancelled
        case pending
        case productNotFound
        case notVerified
        case failed(String)
        
        var message: String {
            switch self {
            case .success:
                return "Subscription activated."
            case .cancelled:
                return "Purchase cancelled."
            case .pending:
                return "Purchase is pending approval."
            case .productNotFound:
                return "Product not found in App Store Connect. Verify Product ID and status."
            case .notVerified:
                return "Transaction could not be verified."
            case .failed(let reason):
                return "Purchase failed: \(reason)"
            }
        }
    }

    private init() {
        #if DEBUG
        // Developer builds default to WatchGuide Pro so the dev gets every benefit
        // without purchasing. Only seeded once — if the dev later toggles the
        // admin switch off in Settings, that explicit choice is respected.
        if UserDefaults.standard.object(forKey: Self.adminUnlimitedOverrideKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.adminUnlimitedOverrideKey)
        }
        #endif

        let adminOverride = UserDefaults.standard.bool(forKey: Self.adminUnlimitedOverrideKey)
        // A previous install may have stored only the Plus flag. Treat that as Pro so
        // grandfathered subscribers keep access on the very first launch after updating,
        // before the async refreshEntitlements() confirms it against StoreKit.
        let pro = UserDefaults.standard.bool(forKey: Self.entitlementActiveKey)
            || UserDefaults.standard.bool(forKey: Self.plusEntitlementActiveKey)
            || adminOverride
        self.isAdminUnlimitedOverride = adminOverride
        self.isUnlimitedActive = pro
        self.isPlusActive = pro

        // Persist the effective state synchronously so UserDefaults-based gates
        // (e.g. AIMessageQuota) see Pro immediately on launch.
        UserDefaults.standard.set(pro, forKey: Self.entitlementActiveKey)
        UserDefaults.standard.set(pro, forKey: Self.plusEntitlementActiveKey)

        updatesTask = Task { [weak self] in
            guard let self else { return }
            await self.observeTransactionUpdates()
        }

        Task {
            await prepare()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func prepare() async {
        await loadProducts()
        await refreshEntitlements()
    }

    private func forceReloadProducts() async {
        await fetchProducts(force: true)
    }

    func loadProducts() async {
        await fetchProducts(force: false)
    }

    /// Only the three purchasable products are fetched. Retired products are intentionally
    /// absent — they still grant entitlement via `Transaction.currentEntitlements`, but
    /// `Product.products(for:)` no longer returns them once they leave sale.
    private func fetchProducts(force: Bool) async {
        if !force, monthlyProduct != nil, annualProduct != nil, lifetimeProduct != nil { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            let products = try await Product.products(for: Self.purchasableProductIDs)
            print("Pro IAP: fetched \(products.count) products: \(products.map(\.id))")
            monthlyProduct = products.first { Self.proMonthlyProductIDs.contains($0.id) }
            annualProduct = products.first { Self.proAnnualProductIDs.contains($0.id) }
            lifetimeProduct = products.first { Self.proLifetimeProductIDs.contains($0.id) }

            if monthlyProduct == nil {
                print("Pro IAP WARNING: no monthly product. IDs tried: \(Self.proMonthlyProductIDs)")
            }
            if annualProduct == nil {
                print("Pro IAP WARNING: no annual product. IDs tried: \(Self.proAnnualProductIDs)")
            }
            if lifetimeProduct == nil {
                print("Pro IAP WARNING: no lifetime product. IDs tried: \(Self.proLifetimeProductIDs)")
            }

            await refreshIntroOfferEligibility()
        } catch {
            print("Pro IAP load error: \(error)")
        }
    }

    private func refreshIntroOfferEligibility() async {
        guard let subscription = annualProduct?.subscription else {
            isEligibleForIntroOffer = false
            return
        }
        isEligibleForIntroOffer = await subscription.isEligibleForIntroOffer
    }

    // MARK: - Purchase

    func purchaseProMonthly() async -> PurchaseOutcome {
        if monthlyProduct == nil { await forceReloadProducts() }
        guard let monthlyProduct else { return .productNotFound }
        return await purchase(product: monthlyProduct)
    }

    func purchaseProAnnual() async -> PurchaseOutcome {
        if annualProduct == nil { await forceReloadProducts() }
        guard let annualProduct else { return .productNotFound }
        return await purchase(product: annualProduct)
    }

    func purchaseProLifetime() async -> PurchaseOutcome {
        if lifetimeProduct == nil { await forceReloadProducts() }
        guard let lifetimeProduct else { return .productNotFound }
        return await purchase(product: lifetimeProduct)
    }

    private func purchase(product: Product) async -> PurchaseOutcome {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            #if os(visionOS)
            // visionOS requires PurchaseAction (SwiftUI) or purchase(confirmIn:options:).
            return .failed("Purchases are not available from this flow on visionOS yet.")
            #else
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    let nowPro = isUnlimitedActive || Self.proEntitlementProductIDs.contains(transaction.productID)
                    updateEntitlementState(isProActive: nowPro)
                    await refreshEntitlements()
                    return .success
                case .unverified:
                    return .notVerified
                }
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed("Unknown App Store purchase state.")
            }
            #endif
        } catch {
            print("Scout IAP purchase error: \(error)")
            return .failed(error.localizedDescription)
        }
    }

    func restorePurchases() async -> PurchaseOutcome {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
        } catch {
            // AppStore.sync() commonly throws in sandbox (auth prompt, network, etc.).
            // Always fall through and check currentEntitlements regardless.
            print("Scout IAP restore sync error: \(error)")
        }
        await refreshEntitlements()
        if isUnlimitedActive || isPlusActive { return .success }
        return .failed("No active subscription found.")
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var hasPro = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate != nil { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= Date() { continue }

            // A single list covers current and retired products, so a legacy WG Plus or
            // WG Unlimited receipt resolves to full Pro without any special-casing.
            if Self.proEntitlementProductIDs.contains(transaction.productID) {
                hasPro = true
            }
        }

        updateEntitlementState(isProActive: hasPro)
        await refreshIntroOfferEligibility()
    }

    private func observeTransactionUpdates() async {
        for await _ in Transaction.updates {
            await refreshEntitlements()
        }
    }

    private func updateEntitlementState(isProActive newPro: Bool) {
        // The admin override forces Pro on regardless of real entitlements so the paid
        // tier can be tested without an actual purchase.
        let effectivePro = newPro || isAdminUnlimitedOverride

        let changed = isUnlimitedActive != effectivePro || isPlusActive != effectivePro

        isUnlimitedActive = effectivePro
        // Persist the EFFECTIVE state (real OR admin override) so UserDefaults-based
        // consumers like AIMessageQuota also treat the user as Pro. Toggling the override
        // off triggers refreshEntitlements(), which recomputes this from real entitlements.
        UserDefaults.standard.set(effectivePro, forKey: Self.entitlementActiveKey)

        // Pro is the only paid tier now, so both flags move together. The second key is
        // still written because older gates and the widget extension read it directly.
        isPlusActive = effectivePro
        UserDefaults.standard.set(effectivePro, forKey: Self.plusEntitlementActiveKey)

        if changed {
            NotificationCenter.default.post(name: Self.statusDidChangeNotification, object: nil)
        }
    }

    // MARK: - Admin / Testing

    /// Enables or disables a developer override that simulates an active WatchGuide Pro
    /// subscription. When disabled, the real StoreKit entitlement state is restored.
    func setAdminUnlimitedOverride(_ enabled: Bool) {
        isAdminUnlimitedOverride = enabled
        UserDefaults.standard.set(enabled, forKey: Self.adminUnlimitedOverrideKey)

        if enabled {
            updateEntitlementState(isProActive: true)
        } else {
            // Re-evaluate against the real entitlements now that the override is off.
            Task { await refreshEntitlements() }
        }
    }
}
