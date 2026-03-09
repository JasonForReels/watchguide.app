import Foundation
import StoreKit

@MainActor
final class ScoutSubscriptionService: ObservableObject {
    static let shared = ScoutSubscriptionService()

    static let scoutUnlimitedSubscriptionProductIDs = [
        "scout_unlimited_monthly",
        "com.JasonSmith.WatchGuideMovieandTVtracker.scout_unlimited_monthly",
        "com.JasonSmith.WatchGuide-MovieandTVtracker.scout.unlimited.monthly"
    ]
    static let scoutUnlimitedLifetimeProductIDs = [
        "scout_unlimited_lifetime",
        "com.JasonSmith.WatchGuideMovieandTVtracker.scout_unlimited_lifetime",
        "com.JasonSmith.WatchGuide-MovieandTVtracker.scout.unlimited.lifetime"
    ]
    static let scoutUnlimitedEntitlementProductIDs = scoutUnlimitedSubscriptionProductIDs + scoutUnlimitedLifetimeProductIDs
    static let entitlementActiveKey = "scout_unlimited_entitlement_active"
    static let statusDidChangeNotification = Notification.Name("ScoutSubscriptionStatusDidChange")

    @Published private(set) var isUnlimitedActive: Bool
    @Published private(set) var subscriptionProduct: Product?
    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var isPurchasing = false
    @Published private(set) var isLoadingProduct = false

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
                return "Scout Unlimited activated."
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
        self.isUnlimitedActive = UserDefaults.standard.bool(forKey: Self.entitlementActiveKey)

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

    func loadProducts() async {
        if subscriptionProduct != nil || lifetimeProduct != nil { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            let products = try await Product.products(for: Self.scoutUnlimitedEntitlementProductIDs)
            subscriptionProduct = products.first { Self.scoutUnlimitedSubscriptionProductIDs.contains($0.id) }
            lifetimeProduct = products.first { Self.scoutUnlimitedLifetimeProductIDs.contains($0.id) }
        } catch {
            print("Scout IAP load error: \(error)")
        }
    }

    func purchaseScoutUnlimited() async -> PurchaseOutcome {
        if subscriptionProduct == nil {
            await loadProducts()
        }
        guard let subscriptionProduct else { return .productNotFound }
        return await purchase(product: subscriptionProduct)
    }

    func purchaseScoutUnlimitedLifetime() async -> PurchaseOutcome {
        if lifetimeProduct == nil {
            await loadProducts()
        }
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
                    await refreshEntitlements()
                    return isUnlimitedActive ? .success : .failed("Entitlement not active after purchase.")
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

    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            print("Scout IAP restore error: \(error)")
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var hasActiveEntitlement = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.scoutUnlimitedEntitlementProductIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate != nil { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= Date() { continue }
            hasActiveEntitlement = true
            break
        }

        updateEntitlementState(isActive: hasActiveEntitlement)
    }

    private func observeTransactionUpdates() async {
        for await _ in Transaction.updates {
            await refreshEntitlements()
        }
    }

    private func updateEntitlementState(isActive: Bool) {
        guard isUnlimitedActive != isActive else {
            UserDefaults.standard.set(isActive, forKey: Self.entitlementActiveKey)
            return
        }

        isUnlimitedActive = isActive
        UserDefaults.standard.set(isActive, forKey: Self.entitlementActiveKey)
        NotificationCenter.default.post(name: Self.statusDidChangeNotification, object: nil)
    }
}
