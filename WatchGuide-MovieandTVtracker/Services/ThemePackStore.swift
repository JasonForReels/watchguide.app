import Foundation
import RevenueCat

/// Ownership, storefront availability and the active theme for Marquee Mode.
/// Every pack is a non-consumable: once bought it is owned forever, even after it
/// leaves the store, so ownership never depends on `isOnSale`.
@MainActor
final class ThemePackStore: ObservableObject {
    static let shared = ThemePackStore()

    static let selectedThemeKey = "wg_selected_theme_id"
    static let followSeasonKey = "wg_theme_follow_season"
    static let previewDuration: TimeInterval = 60

    @Published private(set) var products: [String: StoreProduct] = [:]
    /// Pack IDs owned, bundles expanded into the packs they contain.
    @Published private(set) var ownedPackIDs: Set<String> = ["free"]
    @Published private(set) var isPurchasing = false
    /// A theme being tried before purchase, and when the try-out ends.
    @Published private(set) var previewTheme: WGTheme?
    @Published private(set) var previewEndsAt: Date?

    @Published var selectedThemeID: String {
        didSet { UserDefaults.standard.set(selectedThemeID, forKey: Self.selectedThemeKey) }
    }
    /// When on, the active theme follows the season where the user lives.
    @Published var followsSeason: Bool {
        didSet { UserDefaults.standard.set(followsSeason, forKey: Self.followSeasonKey) }
    }

    /// Server-side switch per pack ID, so a season's art can ship early in a normal
    /// update and be turned on by date. Absent keys fall back to the local calendar.
    var remoteSaleOverrides: [String: Bool] = [:]

    private var updatesTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        selectedThemeID = defaults.string(forKey: Self.selectedThemeKey) ?? ThemeCatalog.defaultThemeID
        followsSeason = defaults.object(forKey: Self.followSeasonKey) as? Bool ?? true
        ScoutSubscriptionService.configureRevenueCatIfNeeded()
        updatesTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream { self?.apply(info) }
        }
        Task { await prepare() }
    }

    deinit { updatesTask?.cancel() }

    func prepare() async {
        await loadProducts()
        await refreshEntitlements()
    }

    // MARK: - Catalogue queries

    func owns(_ pack: ThemePack) -> Bool { ownedPackIDs.contains(pack.id) }

    func owns(themeID: String) -> Bool {
        ThemeCatalog.packs.contains { owns($0) && $0.themeIDs.contains(themeID) }
    }

    var ownedThemes: [WGTheme] { ThemeCatalog.themes.filter { owns(themeID: $0.id) } }

    func isOnSale(_ pack: ThemePack, on date: Date = .now) -> Bool {
        remoteSaleOverrides[pack.id] ?? pack.availability.isOnSale(on: date)
    }

    /// Packs to show a Buy button for: on sale, not owned, and not already covered
    /// by something the user owns. A bundle hides once everything in it is owned.
    var storefrontPacks: [ThemePack] {
        ThemeCatalog.packs.filter { pack in
            guard !pack.productID.isEmpty, isOnSale(pack), !owns(pack) else { return false }
            if pack.isBundle {
                return !ThemeCatalog.expand(pack.id).subtracting([pack.id]).isSubset(of: ownedPackIDs)
            }
            return true
        }
    }

    var ownedPacks: [ThemePack] { ThemeCatalog.packs.filter { owns($0) && !$0.isBundle } }

    func displayPrice(for pack: ThemePack) -> String {
        products[pack.productID]?.localizedPriceString ?? pack.fallbackPrice
    }

    // MARK: - Active theme

    /// The theme to draw right now: a live preview wins, then the season (if the user
    /// owns a matching theme and has Follow Season on), then their manual pick.
    var activeTheme: WGTheme {
        if let previewTheme { return previewTheme }
        if followsSeason, let seasonal = seasonalTheme { return seasonal }
        if owns(themeID: selectedThemeID), let t = ThemeCatalog.theme(id: selectedThemeID) { return t }
        return ThemeCatalog.theme(id: ThemeCatalog.defaultThemeID)!
    }

    private var seasonalTheme: WGTheme? {
        let now = Date()
        let seasonalPackID: String?
        if ThemePack.Availability.isHolidayWindow(now), owns(ThemeCatalog.pack(id: "holidays")!) {
            seasonalPackID = "holidays"
        } else {
            seasonalPackID = Hemisphere.current().season(on: now)?.rawValue
        }
        guard let id = seasonalPackID, let pack = ThemeCatalog.pack(id: id), owns(pack) else { return nil }
        // Keep the user's pick if it already belongs to this pack.
        if pack.themeIDs.contains(selectedThemeID) { return ThemeCatalog.theme(id: selectedThemeID) }
        return pack.themeIDs.first.flatMap(ThemeCatalog.theme(id:))
    }

    func select(_ theme: WGTheme) {
        guard owns(themeID: theme.id) else { return startPreview(theme) }
        endPreview()
        selectedThemeID = theme.id
        followsSeason = false
    }

    // MARK: - Preview

    func startPreview(_ theme: WGTheme) {
        previewTask?.cancel()
        previewTheme = theme
        previewEndsAt = Date().addingTimeInterval(Self.previewDuration)
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.previewDuration))
            guard !Task.isCancelled else { return }
            self?.endPreview()
        }
    }

    func endPreview() {
        previewTask?.cancel()
        previewTheme = nil
        previewEndsAt = nil
    }

    // MARK: - RevenueCat

    func loadProducts() async {
        let loaded = await Purchases.shared.products(ThemeCatalog.productIDs)
        guard !loaded.isEmpty else { return }
        products = Dictionary(loaded.map { ($0.productIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func purchase(_ pack: ThemePack) async -> ScoutSubscriptionService.PurchaseOutcome {
        if products[pack.productID] == nil { await loadProducts() }
        guard let product = products[pack.productID] else { return .productNotFound }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(product: product)
            if result.userCancelled { return .cancelled }
            apply(result.customerInfo)
            if let first = ThemeCatalog.themes(in: pack).first { select(first) }
            return .success
        } catch {
            return ScoutSubscriptionService.outcome(for: error)
        }
    }

    func restore() async {
        do {
            apply(try await Purchases.shared.restorePurchases())
        } catch {
            print("Theme IAP restore error: \(error)")
            await refreshEntitlements()
        }
    }

    func refreshEntitlements() async {
        do {
            apply(try await Purchases.shared.customerInfo())
        } catch {
            // Offline with nothing cached: keep what is already unlocked rather than
            // taking a paid-for theme away.
            print("Theme entitlement refresh error: \(error)")
            setOwned(ownedPackIDs)
        }
    }

    /// Packs are non-consumables, so every theme product the customer has ever bought
    /// (and not had refunded) is owned.
    private func apply(_ info: CustomerInfo) {
        let purchased = info.allPurchasedProductIdentifiers.compactMap(ThemeCatalog.pack(productID:))
        setOwned(purchased.reduce(into: ["free"]) { $0.formUnion(ThemeCatalog.expand($1.id)) })
    }

    private func setOwned(_ packIDs: Set<String>) {
        var owned = packIDs
        // The developer Pro override also unlocks every pack, for testing.
        if ScoutSubscriptionService.shared.isAdminUnlimitedOverride {
            owned.formUnion(ThemeCatalog.packs.map(\.id))
        }
        ownedPackIDs = owned
    }
}
