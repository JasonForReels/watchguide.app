//
//  ThemePack.swift
//  WatchGuide-MovieandTVtracker
//
//  Marquee Mode theme packs. A theme is data, not a screen: a handful of colour
//  tokens, a corner radius, a frame style and asset names. New packs can be
//  added here (or later decoded from hosted JSON — every type is Codable)
//  without touching any view code.
//

import SwiftUI

// MARK: - Theme

struct WGTheme: Identifiable, Codable, Hashable {
    enum FrameStyle: String, Codable {
        case none, hairline, marquee, filmStrip, glow
    }

    struct Palette: Codable, Hashable {
        var background: String
        var surface: String
        var accent: String
        var secondary: String
        var text: String
    }

    let id: String
    let name: String
    let mood: String
    var light: Palette
    var dark: Palette
    var cornerRadius: CGFloat = 14
    var frameStyle: FrameStyle = .hairline
    /// Alternate app icon set name (Assets.xcassets). Nil until the art ships.
    var alternateIconName: String? = nil
    /// Hosted or bundled background image for Apple TV / Marquee Mode.
    var backgroundImage: String? = nil

    func palette(for scheme: ColorScheme) -> Palette { scheme == .dark ? dark : light }
}

// MARK: - Pack

struct ThemePack: Identifiable, Codable, Hashable {
    enum Availability: Codable, Hashable {
        /// Always in the store.
        case always
        /// Only while it's this season where the user lives.
        case season(WGSeason)
        /// Roughly October to early January, everywhere.
        case holidays
    }

    let id: String
    let name: String
    let tagline: String
    let productID: String
    let availability: Availability
    let themeIDs: [String]
    /// For bundles: the packs a purchase unlocks. Empty for single packs.
    var includesPackIDs: [String] = []
    /// Price shown before StoreKit loads. The App Store price always wins.
    var fallbackPrice: String
    var symbol: String

    var isBundle: Bool { !includesPackIDs.isEmpty }
}

enum WGSeason: String, Codable, CaseIterable {
    case spring, summer, autumn, winter
}

// MARK: - Catalogue

enum ThemeCatalog {
    private static let productPrefix = "com.JasonSmith.WatchGuideMovieandTVtracker.themes."

    static let defaultThemeID = "marquee"

    static let packs: [ThemePack] = [
        ThemePack(id: "free", name: "Marquee Mode", tagline: "The classic Coming Soon marquee.",
                  productID: "", availability: .always, themeIDs: ["marquee"],
                  fallbackPrice: "Free", symbol: "sparkles.tv"),
        ThemePack(id: "cinema", name: "Cinema Pack",
                  tagline: "Now-playing sync, scheduling, Marathon mode and five core themes.",
                  productID: productPrefix + "cinema", availability: .always,
                  themeIDs: ["drive-in", "noir", "golden-age", "scifi-terminal", "art-house"],
                  fallbackPrice: "$9.99", symbol: "film.stack"),
        ThemePack(id: "holidays", name: "Holidays", tagline: "Festive looks that work in both hemispheres.",
                  productID: productPrefix + "holidays", availability: .holidays,
                  themeIDs: ["creature-feature", "festive-feature", "premiere-night"],
                  fallbackPrice: "$5.99", symbol: "gift"),
        ThemePack(id: "spring", name: "Spring", tagline: "Fresh and hopeful.",
                  productID: productPrefix + "spring", availability: .season(.spring),
                  themeIDs: ["bloom"], fallbackPrice: "$5.99", symbol: "leaf"),
        ThemePack(id: "summer", name: "Summer", tagline: "Big, bright evenings at the movies.",
                  productID: productPrefix + "summer", availability: .season(.summer),
                  themeIDs: ["summer-spectacular"], fallbackPrice: "$5.99", symbol: "sun.max"),
        ThemePack(id: "autumn", name: "Autumn", tagline: "Cozy lamp-lit afternoons.",
                  productID: productPrefix + "autumn", availability: .season(.autumn),
                  themeIDs: ["harvest-matinee"], fallbackPrice: "$5.99", symbol: "wind"),
        ThemePack(id: "winter", name: "Winter", tagline: "Long nights in with a film.",
                  productID: productPrefix + "winter", availability: .season(.winter),
                  themeIDs: ["fireside"], fallbackPrice: "$5.99", symbol: "flame"),
        ThemePack(id: "seasons", name: "Seasons Collection", tagline: "All four season packs.",
                  productID: productPrefix + "seasons", availability: .always, themeIDs: [],
                  includesPackIDs: ["spring", "summer", "autumn", "winter"],
                  fallbackPrice: "$14.99", symbol: "circle.hexagongrid"),
        ThemePack(id: "everything", name: "Everything",
                  tagline: "Cinema Pack, every season and Holidays — as they exist today.",
                  productID: productPrefix + "everything", availability: .always, themeIDs: [],
                  includesPackIDs: ["cinema", "seasons", "holidays"],
                  fallbackPrice: "$24.99", symbol: "star.square.on.square"),
    ]

    static let themes: [WGTheme] = [
        theme("marquee", "Marquee", "House lights down, posters up.",
              ["F6F1E9", "FFFFFF", "FF9E33", "8A6A4A", "1C1714"],
              ["121014", "1E1A1F", "FF9E33", "C9A77C", "F4EEE6"], radius: 14, frame: .marquee),

        // Cinema Pack
        theme("drive-in", "Drive-In", "Retro summer night at an outdoor cinema.",
              ["F3F0FA", "FFFFFF", "D6249F", "1BA8C4", "1B1640"],
              ["120E33", "1E1850", "FF3EC8", "2EE6FF", "FFF8F0"], radius: 20, frame: .glow),
        theme("noir", "Noir", "Rain-soaked, late-night detective film.",
              ["EDEDED", "FFFFFF", "B7791F", "5E5E5E", "111111"],
              ["0A0A0A", "1C1C1C", "E0A040", "A8A8A8", "E8E8E8"], radius: 4, frame: .hairline),
        theme("golden-age", "Golden Age", "Lavish classic-Hollywood colour.",
              ["FFF9EC", "FFFFFF", "B3122E", "007A8A", "2A1A10"],
              ["1F0A0E", "2E1216", "E8334F", "2EC4D6", "FFF6E0"], radius: 10, frame: .marquee),
        theme("scifi-terminal", "Sci-Fi Terminal", "A computer terminal on a starship.",
              ["EEF6F2", "FFFFFF", "0F8F4A", "0A8FB0", "0C1A14"],
              ["05080A", "0D1418", "39FF88", "2EE6FF", "C8F5DC"], radius: 2, frame: .glow),
        theme("art-house", "Art House", "Quiet, minimal gallery cinema.",
              ["FAF6EE", "FFFFFF", "A8432E", "6B6B6B", "262626"],
              ["1E1D1B", "2A2826", "D9694F", "A3A09A", "F5F0E6"], radius: 0, frame: .none),

        // Holidays
        theme("creature-feature", "Creature Feature", "Midnight monster-movie marathon.",
              ["F4F0F7", "FFFFFF", "D9531E", "3E9E3E", "1A1024"],
              ["120A1A", "20142C", "FF6A2B", "7CFF6B", "F2EDE4"], radius: 12, frame: .filmStrip),
        theme("festive-feature", "Festive Feature", "Warm, sparkly, no snow required.",
              ["FFF8EC", "FFFFFF", "A3122A", "1F5C3A", "2A1810"],
              ["14201A", "1E2E25", "E0B04A", "E0485C", "FFF5E1"], radius: 16, frame: .glow),
        theme("premiere-night", "Premiere Night", "Midnight countdown, red carpet.",
              ["FBF6EA", "FFFFFF", "9C7A1E", "8E1B2B", "151515"],
              ["0B0B0B", "1A1714", "E6C35C", "D0344A", "F7E9C8"], radius: 8, frame: .marquee),

        // Seasons
        theme("bloom", "Bloom", "A soft morning after rain.",
              ["FFF7F4", "FFFFFF", "D9537A", "4E9E5A", "2B2226"],
              ["1E1A1D", "2A2428", "FF8FAE", "8FD98F", "FBF1EC"], radius: 22, frame: .hairline),
        theme("summer-spectacular", "Summer Spectacular", "A warm evening at the movies.",
              ["FFF6EC", "FFFFFF", "E4571B", "0B7A7A", "241410"],
              ["0E2426", "15343A", "FF8A3D", "FFD24A", "FFF3E6"], radius: 18, frame: .glow),
        theme("harvest-matinee", "Harvest Matinee", "A cozy lamp-lit afternoon.",
              ["FBF3E6", "FFFFFF", "B8501E", "8A5A2B", "2A1C12"],
              ["1E140E", "2C1E15", "E8773A", "D9A83A", "F7EBDD"], radius: 14, frame: .filmStrip),
        theme("fireside", "Fireside", "A long night in with a film.",
              ["F2F3F6", "FFFFFF", "C2571E", "5A6272", "141A2A"],
              ["0D1222", "171E33", "FF8A3D", "8C94A6", "F4ECDF"], radius: 16, frame: .marquee),
    ]

    static func theme(id: String) -> WGTheme? { themes.first { $0.id == id } }
    static func pack(id: String) -> ThemePack? { packs.first { $0.id == id } }
    static func pack(productID: String) -> ThemePack? { packs.first { $0.productID == productID } }

    /// Every purchasable product, for `Purchases.shared.products(_:)`.
    static var productIDs: [String] { packs.map(\.productID).filter { !$0.isEmpty } }

    /// Expands bundles recursively into the single packs they unlock (bundle included).
    static func expand(_ packID: String) -> Set<String> {
        guard let pack = pack(id: packID) else { return [] }
        return pack.includesPackIDs.reduce(into: [packID]) { $0.formUnion(expand($1)) }
    }

    /// Themes a pack gives you, including those from packs inside a bundle.
    static func themes(in pack: ThemePack) -> [WGTheme] {
        expand(pack.id).compactMap { Self.pack(id: $0) }
            .sorted { packs.firstIndex(of: $0)! < packs.firstIndex(of: $1)! }
            .flatMap(\.themeIDs).compactMap(theme(id:))
    }

    private static func theme(_ id: String, _ name: String, _ mood: String,
                              _ light: [String], _ dark: [String],
                              radius: CGFloat, frame: WGTheme.FrameStyle) -> WGTheme {
        func palette(_ c: [String]) -> WGTheme.Palette {
            .init(background: c[0], surface: c[1], accent: c[2], secondary: c[3], text: c[4])
        }
        return WGTheme(id: id, name: name, mood: mood, light: palette(light), dark: palette(dark),
                       cornerRadius: radius, frameStyle: frame)
    }
}

// MARK: - Seasons & hemispheres

enum Hemisphere {
    case northern, southern, equatorial

    /// Timezones near enough to the equator that seasons don't mean much.
    private static let equatorialZones: Set<String> = [
        "Asia/Singapore", "Asia/Kuala_Lumpur", "Asia/Jakarta", "Asia/Pontianak", "Asia/Makassar",
        "Asia/Jayapura", "Asia/Brunei", "Asia/Colombo", "Indian/Maldives",
        "Africa/Nairobi", "Africa/Kampala", "Africa/Kigali", "Africa/Lagos", "Africa/Accra",
        "Africa/Abidjan", "Africa/Douala", "Africa/Libreville", "Africa/Kinshasa", "Africa/Mogadishu",
        "Africa/Addis_Ababa", "Africa/Dar_es_Salaam",
        "America/Bogota", "America/Guayaquil", "America/Caracas", "America/Panama",
        "America/Manaus", "America/Belem", "America/Paramaribo", "America/Cayenne", "America/Guyana",
        "Pacific/Galapagos", "Pacific/Nauru", "Pacific/Tarawa", "Pacific/Majuro",
    ]

    private static let southernZones: Set<String> = [
        "Africa/Johannesburg", "Africa/Maputo", "Africa/Harare", "Africa/Lusaka", "Africa/Windhoek",
        "Africa/Gaborone", "Africa/Maseru", "Africa/Mbabane", "Africa/Luanda", "Africa/Blantyre",
        "Indian/Mauritius", "Indian/Reunion", "Indian/Antananarivo",
        "America/Sao_Paulo", "America/Argentina/Buenos_Aires", "America/Buenos_Aires",
        "America/Santiago", "America/Montevideo", "America/Asuncion", "America/La_Paz", "America/Lima",
        "Pacific/Auckland", "Pacific/Chatham", "Pacific/Fiji", "Pacific/Tongatapu", "Pacific/Apia",
        "Pacific/Noumea", "Pacific/Port_Moresby", "Pacific/Tahiti", "Pacific/Efate",
    ]

    static func current(timeZone: TimeZone = .current) -> Hemisphere {
        let id = timeZone.identifier
        if equatorialZones.contains(id) { return .equatorial }
        if southernZones.contains(id)
            || id.hasPrefix("Australia/") || id.hasPrefix("Antarctica/")
            || id.hasPrefix("America/Argentina/") {
            return .southern
        }
        return .northern
    }

    /// Meteorological seasons. Nil at the equator.
    func season(on date: Date = .now, calendar: Calendar = .current) -> WGSeason? {
        let month = calendar.component(.month, from: date)
        let northern: WGSeason = switch month {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
        switch self {
        case .equatorial: return nil
        case .northern: return northern
        case .southern:
            return ([.spring: .autumn, .summer: .winter, .autumn: .spring, .winter: .summer] as [WGSeason: WGSeason])[northern]
        }
    }
}

extension ThemePack.Availability {
    /// Holidays run from 1 October to 7 January, everywhere.
    static func isHolidayWindow(_ date: Date = .now, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.month, .day], from: date)
        guard let month = c.month, let day = c.day else { return false }
        return month >= 10 || (month == 1 && day <= 7)
    }

    func isOnSale(on date: Date = .now, hemisphere: Hemisphere = .current()) -> Bool {
        switch self {
        case .always: return true
        case .holidays: return Self.isHolidayWindow(date)
        case .season(let season): return hemisphere.season(on: date) == season
        }
    }
}

// MARK: - SwiftUI tokens

struct ResolvedTheme {
    let theme: WGTheme
    let scheme: ColorScheme

    private var p: WGTheme.Palette { theme.palette(for: scheme) }
    var background: Color { Color(hex: p.background) }
    var surface: Color { Color(hex: p.surface) }
    var accent: Color { Color(hex: p.accent) }
    var secondary: Color { Color(hex: p.secondary) }
    var text: Color { Color(hex: p.text) }
    var cornerRadius: CGFloat { theme.cornerRadius }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: WGTheme = ThemeCatalog.theme(id: ThemeCatalog.defaultThemeID)!
}

extension EnvironmentValues {
    var wgTheme: WGTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Poster-card styling for the current theme.
struct ThemedPosterFrame: ViewModifier {
    @Environment(\.wgTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let t = ResolvedTheme(theme: theme, scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: t.cornerRadius, style: .continuous)
        content
            .clipShape(shape)
            .overlay {
                switch theme.frameStyle {
                case .none: EmptyView()
                case .hairline: shape.strokeBorder(t.secondary.opacity(0.5), lineWidth: 1)
                case .marquee: shape.strokeBorder(t.accent, lineWidth: 3)
                case .filmStrip:
                    shape.strokeBorder(t.text.opacity(0.8),
                                       style: StrokeStyle(lineWidth: 4, dash: [6, 5]))
                case .glow: shape.strokeBorder(t.accent, lineWidth: 2)
                }
            }
            .shadow(color: theme.frameStyle == .glow ? t.accent.opacity(0.6) : .clear, radius: 10)
    }
}

extension View {
    func themedPosterFrame() -> some View { modifier(ThemedPosterFrame()) }
}
