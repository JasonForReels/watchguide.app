import Foundation
import RevenueCat

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
        "com.JasonSmith.WatchGuideMovieandTVtracker.pro.monthly"
    ]
    /// WatchGuide Pro, annual. Carries the 7-day free trial as an introductory offer.
    static let proAnnualProductIDs = [
        "com.JasonSmith.WatchGuideMovieandTVtracker.pro.annual"
    ]
    /// WatchGuide Pro, lifetime. A non-consumable, so it sits outside the subscription group.
    static let proLifetimeProductIDs = [
        "com.JasonSmith.WatchGuideMovieandTVtracker.pro.lifetime"
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

    /// Lifetime is not on sale yet. Flip this once the product exists in App Store Connect;
    /// the paywall and Settings show the lifetime option whenever its product loads.
    static let isLifetimeOnSale = false

    /// Everything a new customer can buy today.
    static let purchasableProductIDs = proMonthlyProductIDs + proAnnualProductIDs
        + (isLifetimeOnSale ? proLifetimeProductIDs : [])

    /// Everything that grants Pro access, current or retired.
    static let proEntitlementProductIDs = proMonthlyProductIDs + proAnnualProductIDs
        + proLifetimeProductIDs + legacyEntitlementProductIDs

    // MARK: - RevenueCat

    /// Public SDK key for the App Store app in the WatchGuide RevenueCat project.
    private static let appStoreAPIKey = "appl_tzYinluItTHNUuHHWiiGtVfVLIS"
    /// RevenueCat Test Store key: simulated purchases, no App Store account needed.
    /// Debug only — the SDK deliberately crashes a Release build configured with it.
    private static let testStoreAPIKey = "test_XJMNFMOVgDFjelJsNOtHKBpLuLn"
    private static var revenueCatAPIKey: String {
        #if DEBUG
        return testStoreAPIKey
        #else
        return appStoreAPIKey
        #endif
    }
    /// The entitlement every Pro product, current or retired, is attached to in RevenueCat.
    static let proEntitlementID = "watchguide_pro"
    /// Set once the pre-RevenueCat App Store purchases have been sent to RevenueCat.
    private static let didSyncLegacyPurchasesKey = "wg_revenuecat_legacy_purchases_synced"

    /// Safe to call from anywhere that is about to touch `Purchases.shared`.
    static func configureRevenueCatIfNeeded() {
        guard !Purchases.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: revenueCatAPIKey)
    }

    // MARK: - Keys & Notifications

    // Storage keys are unchanged so existing installs keep their entitlement across the rename.
    static let entitlementActiveKey = "scout_unlimited_entitlement_active"
    static let plusEntitlementActiveKey = "scout_plus_entitlement_active"
    /// Developer/admin override that simulates an active Pro entitlement for testing.
    nonisolated static let adminUnlimitedOverrideKey = "wg_admin_unlimited_override"
    /// Thread-safe read of the admin override, for gating admin-only features off the main actor.
    nonisolated static var isAdminOverrideEnabled: Bool {
        UserDefaults.standard.bool(forKey: adminUnlimitedOverrideKey)
    }
    /// Trailer add-ons (Trailerio) are internal-only: Debug builds with the admin override on.
    nonisolated static var areTrailerAddonsAvailable: Bool {
        #if DEBUG
        return isAdminOverrideEnabled
        #else
        return false
        #endif
    }
    static let statusDidChangeNotification = Notification.Name("ScoutSubscriptionStatusDidChange")

    // MARK: - Published State

    /// True when WatchGuide Pro is active, from any current or legacy product.
    @Published private(set) var isUnlimitedActive: Bool
    /// Retained for the many call sites that only ask "is this a paying user?".
    /// Pro is now the only paid tier, so this always matches `isUnlimitedActive`.
    @Published private(set) var isPlusActive: Bool
    @Published private(set) var monthlyProduct: StoreProduct?
    @Published private(set) var annualProduct: StoreProduct?
    @Published private(set) var lifetimeProduct: StoreProduct?
    @Published private(set) var isPurchasing = false
    @Published private(set) var isLoadingProduct = false
    /// False once the user has consumed an introductory offer anywhere in this
    /// subscription group. Gate all "7 days free" copy on this — offering a trial
    /// the App Store will not grant is the fastest way to earn a refund request.
    @Published private(set) var isEligibleForIntroOffer = false
    /// When true, Pro is treated as active regardless of real App Store entitlements.
    /// Intended for internal testing only.
    @Published private(set) var isAdminUnlimitedOverride: Bool
    /// The current RevenueCat offering. When it carries a paywall built in the dashboard,
    /// `WGSubscriptionPaywallView` shows that instead of the built-in one.
    @Published private(set) var currentOffering: Offering?

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
    /// Packages from the current offering, keyed by product ID. Purchasing through the
    /// package (rather than the bare product) keeps offering attribution in RevenueCat.
    private var packagesByProductID: [String: Package] = [:]


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
        // before the async refreshEntitlements() confirms it against RevenueCat.
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

        Self.configureRevenueCatIfNeeded()

        updatesTask = Task { [weak self] in
            guard let self else { return }
            await self.observeCustomerInfoUpdates()
        }

        Task {
            await prepare()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func prepare() async {
        await syncLegacyPurchasesIfNeeded()
        await loadProducts()
        await refreshEntitlements()
    }

    private func forceReloadProducts() async {
        await fetchProducts(force: true)
    }

    func loadProducts() async {
        await fetchProducts(force: false)
    }

    /// Prefers the current RevenueCat offering so the line-up can be changed remotely,
    /// and falls back to the hard-coded product IDs if the offering is missing a package.
    /// The offering's packages are taken as they come, whatever their product IDs: under
    /// the Test Store key they resolve to the simulated `monthly` / `yearly` products.
    /// Retired products are intentionally absent — they still grant the entitlement,
    /// but are no longer for sale.
    private func fetchProducts(force: Bool) async {
        if !force, monthlyProduct != nil, annualProduct != nil,
           lifetimeProduct != nil || !Self.isLifetimeOnSale { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        var monthly: StoreProduct?
        var annual: StoreProduct?
        var lifetime: StoreProduct?
        do {
            if let offering = try await Purchases.shared.offerings().current {
                currentOffering = offering
                let packages = [offering.monthly, offering.annual,
                                Self.isLifetimeOnSale ? offering.lifetime : nil].compactMap { $0 }
                packagesByProductID = Dictionary(
                    packages.map { ($0.storeProduct.productIdentifier, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                monthly = offering.monthly?.storeProduct
                annual = offering.annual?.storeProduct
                lifetime = Self.isLifetimeOnSale ? offering.lifetime?.storeProduct : nil
            }
        } catch {
            print("Pro IAP offerings error: \(error)")
        }

        let missing = (monthly == nil ? Self.proMonthlyProductIDs : [])
            + (annual == nil ? Self.proAnnualProductIDs : [])
            + (lifetime == nil && Self.isLifetimeOnSale ? Self.proLifetimeProductIDs : [])
        if !missing.isEmpty {
            let products = await Purchases.shared.products(missing)
            monthly = monthly ?? products.first { Self.proMonthlyProductIDs.contains($0.productIdentifier) }
            annual = annual ?? products.first { Self.proAnnualProductIDs.contains($0.productIdentifier) }
            lifetime = lifetime ?? products.first { Self.proLifetimeProductIDs.contains($0.productIdentifier) }
        }

        monthlyProduct = monthly
        annualProduct = annual
        lifetimeProduct = lifetime
        let loaded = [monthly, annual, lifetime].compactMap { $0?.productIdentifier }
        print("Pro IAP: fetched \(loaded.count) products: \(loaded)")

        if monthlyProduct == nil {
            print("Pro IAP WARNING: no monthly product. IDs tried: \(Self.proMonthlyProductIDs)")
        }
        if annualProduct == nil {
            print("Pro IAP WARNING: no annual product. IDs tried: \(Self.proAnnualProductIDs)")
        }
        if lifetimeProduct == nil, Self.isLifetimeOnSale {
            print("Pro IAP WARNING: no lifetime product. IDs tried: \(Self.proLifetimeProductIDs)")
        }

        await refreshIntroOfferEligibility()
    }

    private func refreshIntroOfferEligibility() async {
        guard let annualProduct else {
            isEligibleForIntroOffer = false
            return
        }
        let status = await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: annualProduct)
        isEligibleForIntroOffer = status == .eligible
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

    private func purchase(product: StoreProduct) async -> PurchaseOutcome {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result: PurchaseResultData
            if let package = packagesByProductID[product.productIdentifier] {
                result = try await Purchases.shared.purchase(package: package)
            } else {
                result = try await Purchases.shared.purchase(product: product)
            }
            if result.userCancelled { return .cancelled }
            apply(result.customerInfo)
            return .success
        } catch {
            return Self.outcome(for: error)
        }
    }

    /// Maps a RevenueCat purchase error onto the outcome the UI reports.
    static func outcome(for error: Error) -> PurchaseOutcome {
        switch error as? ErrorCode {
        case .purchaseCancelledError:
            return .cancelled
        case .paymentPendingError:
            return .pending
        case .productNotAvailableForPurchaseError:
            return .productNotFound
        case .invalidReceiptError, .missingReceiptFileError:
            return .notVerified
        default:
            print("IAP purchase error: \(error)")
            return .failed(error.localizedDescription)
        }
    }

    func restorePurchases() async -> PurchaseOutcome {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            apply(try await Purchases.shared.restorePurchases())
        } catch {
            // Restore commonly throws in sandbox (auth prompt, network, etc.).
            // Always fall through and re-check the cached entitlements regardless.
            print("Scout IAP restore error: \(error)")
            await refreshEntitlements()
        }
        if isUnlimitedActive || isPlusActive { return .success }
        return .failed("No active subscription found.")
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        do {
            apply(try await Purchases.shared.customerInfo())
        } catch {
            // Offline or RevenueCat unreachable with nothing cached: keep the last known
            // state rather than revoking Pro from someone who paid for it.
            print("Pro entitlement refresh error: \(error)")
        }
        await refreshIntroOfferEligibility()
    }

    private func apply(_ info: CustomerInfo) {
        updateEntitlementState(isProActive: Self.hasPro(in: info))
    }

    /// The RevenueCat entitlement is the source of truth. The product-ID check behind it
    /// covers current and retired products alike, so a legacy WG Plus or WG Unlimited
    /// purchase still resolves to full Pro even if a product is detached in the dashboard.
    private static func hasPro(in info: CustomerInfo) -> Bool {
        if info.entitlements[proEntitlementID]?.isActive == true { return true }
        let ids = Set(proEntitlementProductIDs)
        return !info.activeSubscriptions.isDisjoint(with: ids)
            || info.nonSubscriptions.contains { ids.contains($0.productIdentifier) }
    }

    private func observeCustomerInfoUpdates() async {
        for await info in Purchases.shared.customerInfoStream {
            apply(info)
        }
    }

    /// Purchases made before the move to RevenueCat live only in the App Store receipt.
    /// Send them across once so existing subscribers keep Pro without tapping Restore.
    private func syncLegacyPurchasesIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.didSyncLegacyPurchasesKey) else { return }
        do {
            apply(try await Purchases.shared.syncPurchases())
            UserDefaults.standard.set(true, forKey: Self.didSyncLegacyPurchasesKey)
        } catch {
            print("Pro legacy purchase sync error: \(error)")
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

    /// Observable counterpart of `areTrailerAddonsAvailable` for SwiftUI views.
    var isTrailerAddonsAvailable: Bool {
        #if DEBUG
        return isAdminUnlimitedOverride
        #else
        return false
        #endif
    }

    /// Enables or disables a developer override that simulates an active WatchGuide Pro
    /// subscription. When disabled, the real RevenueCat entitlement state is restored.
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
