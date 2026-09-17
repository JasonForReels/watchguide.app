//
//  ProviderPricingService.swift
//  WatchGuide-MovieandTVtracker
//
//  Static subscription pricing data for streaming providers,
//  keyed by TMDB provider ID and ISO 3166-1 country code.
//  Prices represent the cheapest available tier (with ads where applicable).
//  Last updated: 2026-05
//

import Foundation

enum ProviderPricingService {

    /// Returns a pre-formatted monthly price string for a given provider
    /// in a given country, or `nil` if no data is available.
    static func monthlyPrice(forProviderId providerId: Int, countryCode: String) -> String? {
        pricingData[PricingKey(providerId: providerId, countryCode: countryCode.uppercased())]
    }

    // MARK: - Internal Types

    private struct PricingKey: Hashable {
        let providerId: Int
        let countryCode: String
    }

    // MARK: - Pricing Data

    private static let pricingData: [PricingKey: String] = {
        var d = [PricingKey: String]()

        func add(_ pid: Int, _ cc: String, _ price: String) {
            d[PricingKey(providerId: pid, countryCode: cc)] = price
        }

        // Convenience to add the same price for multiple provider IDs
        func addAll(_ pids: [Int], _ cc: String, _ price: String) {
            for pid in pids { add(pid, cc, price) }
        }

        // ────────────────────────────────────────────
        // Netflix (8)
        // ────────────────────────────────────────────
        add(8, "US", "$7.99/mo")
        add(8, "CA", "CA$7.99/mo")
        add(8, "GB", "£4.99/mo")
        add(8, "AU", "A$7.99/mo")
        add(8, "DE", "€4.99/Mo.")
        add(8, "FR", "€5.99/mois")
        add(8, "ES", "€5.49/mes")
        add(8, "IT", "€6.99/mese")
        add(8, "NL", "€7.99/mnd")
        add(8, "SE", "79 kr/mån")
        add(8, "NO", "79 kr/mnd")
        add(8, "DK", "79 kr/md")
        add(8, "BR", "R$20.90/mês")
        add(8, "MX", "MX$129/mes")
        add(8, "AR", "ARS$3,599/mes")
        add(8, "CO", "COP$16,900/mes")
        add(8, "JP", "¥890/月")
        add(8, "KR", "₩5,500/월")
        add(8, "IN", "₹149/mo")
        add(8, "ZA", "R49/mo")
        add(8, "PH", "₱149/mo")
        add(8, "TH", "฿99/mo")
        add(8, "MY", "RM19.90/mo")
        add(8, "SG", "S$6.98/mo")
        add(8, "ID", "Rp54,000/bln")
        add(8, "PL", "29 zł/mies.")
        add(8, "TR", "₺99.99/ay")
        add(8, "IL", "₪32.90/mo")
        add(8, "EG", "E£70/mo")
        add(8, "NG", "₦2,200/mo")
        add(8, "KE", "KSh300/mo")

        // ────────────────────────────────────────────
        // Disney+ (337)
        // ────────────────────────────────────────────
        add(337, "US", "$9.99/mo")
        add(337, "CA", "CA$9.99/mo")
        add(337, "GB", "£4.99/mo")
        add(337, "AU", "A$13.99/mo")
        add(337, "DE", "€5.99/Mo.")
        add(337, "FR", "€5.99/mois")
        add(337, "ES", "€5.99/mes")
        add(337, "IT", "€5.99/mese")
        add(337, "NL", "€5.99/mnd")
        add(337, "SE", "69 kr/mån")
        add(337, "NO", "69 kr/mnd")
        add(337, "DK", "59 kr/md")
        add(337, "BR", "R$33.90/mês")
        add(337, "MX", "MX$159/mes")
        add(337, "AR", "ARS$3,699/mes")
        add(337, "CO", "COP$15,900/mes")
        add(337, "JP", "¥990/月")
        add(337, "KR", "₩9,900/월")
        add(337, "IN", "₹299/mo")
        add(337, "ZA", "R49/mo")
        add(337, "SG", "S$9.98/mo")
        add(337, "ID", "Rp39,000/bln")
        add(337, "PH", "₱159/mo")
        add(337, "TH", "฿289/mo")
        add(337, "MY", "RM19.90/mo")
        add(337, "PL", "29.99 zł/mies.")
        add(337, "TR", "₺134.99/ay")

        // ────────────────────────────────────────────
        // Max / HBO Max (384, 1899)
        // ────────────────────────────────────────────
        addAll([384, 1899], "US", "$9.99/mo")
        addAll([384, 1899], "BR", "R$34.90/mês")
        addAll([384, 1899], "MX", "MX$99/mes")
        addAll([384, 1899], "AR", "ARS$2,999/mes")
        addAll([384, 1899], "CO", "COP$14,900/mes")
        addAll([384, 1899], "ES", "€5.99/mes")
        addAll([384, 1899], "SE", "89 kr/mån")
        addAll([384, 1899], "NO", "89 kr/mnd")
        addAll([384, 1899], "DK", "69 kr/md")
        addAll([384, 1899], "FI", "€5.99/kk")
        addAll([384, 1899], "PL", "24.99 zł/mies.")
        addAll([384, 1899], "PT", "€5.99/mês")
        addAll([384, 1899], "NL", "€5.99/mnd")
        addAll([384, 1899], "HR", "€5.99/mj.")

        // ────────────────────────────────────────────
        // Hulu (15)
        // ────────────────────────────────────────────
        add(15, "US", "$9.99/mo")
        add(15, "JP", "¥1,026/月")

        // ────────────────────────────────────────────
        // Paramount+ (531, 582)
        // ────────────────────────────────────────────
        addAll([531, 582], "US", "$7.99/mo")
        addAll([531, 582], "CA", "CA$7.99/mo")
        addAll([531, 582], "GB", "£4.99/mo")
        addAll([531, 582], "AU", "A$8.99/mo")
        addAll([531, 582], "DE", "€7.99/Mo.")
        addAll([531, 582], "FR", "€7.99/mois")
        addAll([531, 582], "IT", "€7.99/mese")
        addAll([531, 582], "BR", "R$19.90/mês")
        addAll([531, 582], "MX", "MX$79/mes")
        addAll([531, 582], "AR", "ARS$1,699/mes")
        addAll([531, 582], "KR", "₩7,900/월")
        addAll([531, 582], "SE", "69 kr/mån")
        addAll([531, 582], "NO", "69 kr/mnd")
        addAll([531, 582], "DK", "59 kr/md")

        // ────────────────────────────────────────────
        // Peacock (386, 387)
        // ────────────────────────────────────────────
        addAll([386, 387], "US", "$7.99/mo")
        addAll([386, 387], "GB", "£4.99/mo")
        addAll([386, 387], "DE", "€4.99/Mo.")
        addAll([386, 387], "IT", "€4.99/mese")
        addAll([386, 387], "IE", "€4.99/mo")
        addAll([386, 387], "AT", "€4.99/Mo.")
        addAll([386, 387], "CH", "CHF 4.99/Mt.")

        // ────────────────────────────────────────────
        // Apple TV+ (350, 2)
        // ────────────────────────────────────────────
        addAll([350, 2], "US", "$9.99/mo")
        addAll([350, 2], "CA", "CA$12.99/mo")
        addAll([350, 2], "GB", "£8.99/mo")
        addAll([350, 2], "AU", "A$12.99/mo")
        addAll([350, 2], "DE", "€9.99/Mo.")
        addAll([350, 2], "FR", "€9.99/mois")
        addAll([350, 2], "ES", "€9.99/mes")
        addAll([350, 2], "IT", "€9.99/mese")
        addAll([350, 2], "NL", "€9.99/mnd")
        addAll([350, 2], "JP", "¥900/月")
        addAll([350, 2], "KR", "₩9,900/월")
        addAll([350, 2], "IN", "₹99/mo")
        addAll([350, 2], "BR", "R$21.90/mês")
        addAll([350, 2], "MX", "MX$99/mes")
        addAll([350, 2], "ZA", "R89.99/mo")
        addAll([350, 2], "SE", "99 kr/mån")
        addAll([350, 2], "NO", "99 kr/mnd")
        addAll([350, 2], "DK", "79 kr/md")
        addAll([350, 2], "TR", "₺64.99/ay")
        addAll([350, 2], "ID", "Rp49,000/bln")
        addAll([350, 2], "SG", "S$8.98/mo")
        addAll([350, 2], "PL", "34.99 zł/mies.")

        // ────────────────────────────────────────────
        // Crunchyroll (283)
        // ────────────────────────────────────────────
        add(283, "US", "$7.99/mo")
        add(283, "CA", "CA$9.99/mo")
        add(283, "GB", "£4.99/mo")
        add(283, "AU", "A$7.99/mo")
        add(283, "DE", "€6.99/Mo.")
        add(283, "FR", "€6.99/mois")
        add(283, "BR", "R$32/mês")
        add(283, "MX", "MX$99/mes")
        add(283, "IN", "₹79/mo")

        // ────────────────────────────────────────────
        // Discovery+ (510, 584)
        // ────────────────────────────────────────────
        addAll([510, 584], "US", "$4.99/mo")
        addAll([510, 584], "GB", "£3.99/mo")
        addAll([510, 584], "SE", "49 kr/mån")
        addAll([510, 584], "NO", "49 kr/mnd")
        addAll([510, 584], "DK", "39 kr/md")
        addAll([510, 584], "IT", "€3.99/mese")
        addAll([510, 584], "NL", "€3.99/mnd")
        addAll([510, 584], "BR", "R$22.90/mês")
        addAll([510, 584], "IN", "₹299/mo")

        // ────────────────────────────────────────────
        // MUBI (11)
        // ────────────────────────────────────────────
        add(11, "US", "$14.99/mo")
        add(11, "GB", "£11.99/mo")
        add(11, "DE", "€13.99/Mo.")
        add(11, "FR", "€11.99/mois")
        add(11, "BR", "R$37.90/mês")
        add(11, "IN", "₹499/mo")
        add(11, "TR", "₺79.90/ay")
        add(11, "JP", "¥1,500/月")

        // ────────────────────────────────────────────
        // Showmax (55)
        // ────────────────────────────────────────────
        add(55, "ZA", "R99/mo")
        add(55, "NG", "₦2,900/mo")
        add(55, "KE", "KSh300/mo")
        add(55, "GH", "GH₵25/mo")

        // ────────────────────────────────────────────
        // BritBox (380, 151)
        // ────────────────────────────────────────────
        addAll([380, 151], "US", "$8.99/mo")
        addAll([380, 151], "CA", "CA$8.99/mo")
        addAll([380, 151], "GB", "£5.99/mo")
        addAll([380, 151], "AU", "A$8.99/mo")
        addAll([380, 151], "ZA", "R99.99/mo")

        // ────────────────────────────────────────────
        // Shudder (99)
        // ────────────────────────────────────────────
        add(99, "US", "$6.99/mo")
        add(99, "CA", "CA$6.99/mo")
        add(99, "GB", "£4.99/mo")
        add(99, "AU", "A$6.99/mo")

        // ────────────────────────────────────────────
        // Starz (43)
        // ────────────────────────────────────────────
        add(43, "US", "$9.99/mo")
        add(43, "CA", "CA$8.99/mo")

        // ────────────────────────────────────────────
        // Tubi (73) — Free service, no price shown
        // Pluto TV (300) — Free service, no price shown
        // Vudu / Fandango at Home (7) — Transactional, no sub price
        // ────────────────────────────────────────────

        return d
    }()
}
