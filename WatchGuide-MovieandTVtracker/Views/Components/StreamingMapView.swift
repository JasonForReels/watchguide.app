//
//  StreamingMapView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if canImport(MapKit)
import MapKit
#endif

// MARK: - Country Coordinate Data

/// Represents a country with streaming availability that can be placed on the map.
struct StreamingCountry: Identifiable {
    let id: String // ISO 3166-1 alpha-2 code
    let name: String
    let coordinate: CLLocationCoordinate2D
    let flag: String
    let continent: Continent
    let providers: WatchProviderRegion
}

// MARK: - Continent Definitions

enum Continent: String, CaseIterable, Identifiable {
    case northAmerica = "North America"
    case southAmerica = "South America"
    case europe = "Europe"
    case africa = "Africa"
    case middleEast = "Middle East"
    case asia = "Asia"
    case oceania = "Oceania"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .northAmerica: return "🌎"
        case .southAmerica: return "🌎"
        case .europe: return "🌍"
        case .africa: return "🌍"
        case .middleEast: return "🌍"
        case .asia: return "🌏"
        case .oceania: return "🌏"
        }
    }

    var centerCoordinate: CLLocationCoordinate2D {
        switch self {
        case .northAmerica: return CLLocationCoordinate2D(latitude: 40.0, longitude: -100.0)
        case .southAmerica: return CLLocationCoordinate2D(latitude: -15.0, longitude: -60.0)
        case .europe: return CLLocationCoordinate2D(latitude: 50.0, longitude: 15.0)
        case .africa: return CLLocationCoordinate2D(latitude: 5.0, longitude: 20.0)
        case .middleEast: return CLLocationCoordinate2D(latitude: 28.0, longitude: 45.0)
        case .asia: return CLLocationCoordinate2D(latitude: 30.0, longitude: 105.0)
        case .oceania: return CLLocationCoordinate2D(latitude: -25.0, longitude: 145.0)
        }
    }

    /// The zoom span used when drilling into a continent.
    var regionSpan: MKCoordinateSpan {
        switch self {
        case .northAmerica: return MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 60)
        case .southAmerica: return MKCoordinateSpan(latitudeDelta: 55, longitudeDelta: 45)
        case .europe: return MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 45)
        case .africa: return MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 50)
        case .middleEast: return MKCoordinateSpan(latitudeDelta: 25, longitudeDelta: 35)
        case .asia: return MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 60)
        case .oceania: return MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 50)
        }
    }
}

/// A cluster representing a continent on the map.
struct ContinentCluster: Identifiable {
    let id: String
    let continent: Continent
    let countries: [StreamingCountry]
    var coordinate: CLLocationCoordinate2D { continent.centerCoordinate }
    var count: Int { countries.count }
}

/// Lookup table for country codes to coordinates, names, flag emojis, and continent.
private enum CountryDirectory {
    struct CountryInfo {
        let name: String
        let latitude: Double
        let longitude: Double
        let flag: String
        let continent: Continent
    }

    // Hard-coded continent assignments so geography-based clustering is correct
    // (e.g. Iceland -> North America grouping, Turkey -> Middle East, etc.)
    static let countries: [String: CountryInfo] = [
        // --- North America & Caribbean ---
        "AG": CountryInfo(name: "Antigua and Barbuda", latitude: 17.0608, longitude: -61.7964, flag: "🇦🇬", continent: .northAmerica),
        "BB": CountryInfo(name: "Barbados", latitude: 13.1939, longitude: -59.5432, flag: "🇧🇧", continent: .northAmerica),
        "BM": CountryInfo(name: "Bermuda", latitude: 32.3078, longitude: -64.7505, flag: "🇧🇲", continent: .northAmerica),
        "BS": CountryInfo(name: "Bahamas", latitude: 25.0343, longitude: -77.3963, flag: "🇧🇸", continent: .northAmerica),
        "BZ": CountryInfo(name: "Belize", latitude: 17.1899, longitude: -88.4976, flag: "🇧🇿", continent: .northAmerica),
        "CA": CountryInfo(name: "Canada", latitude: 56.1304, longitude: -106.3468, flag: "🇨🇦", continent: .northAmerica),
        "CR": CountryInfo(name: "Costa Rica", latitude: 9.7489, longitude: -83.7534, flag: "🇨🇷", continent: .northAmerica),
        "CU": CountryInfo(name: "Cuba", latitude: 21.5218, longitude: -77.7812, flag: "🇨🇺", continent: .northAmerica),
        "DO": CountryInfo(name: "Dominican Republic", latitude: 18.7357, longitude: -70.1627, flag: "🇩🇴", continent: .northAmerica),
        "GT": CountryInfo(name: "Guatemala", latitude: 15.7835, longitude: -90.2308, flag: "🇬🇹", continent: .northAmerica),
        "HN": CountryInfo(name: "Honduras", latitude: 15.1990, longitude: -86.2419, flag: "🇭🇳", continent: .northAmerica),
        "IS": CountryInfo(name: "Iceland", latitude: 64.9631, longitude: -19.0208, flag: "🇮🇸", continent: .northAmerica),
        "JM": CountryInfo(name: "Jamaica", latitude: 18.1096, longitude: -77.2975, flag: "🇯🇲", continent: .northAmerica),
        "LC": CountryInfo(name: "Saint Lucia", latitude: 13.9094, longitude: -60.9789, flag: "🇱🇨", continent: .northAmerica),
        "MX": CountryInfo(name: "Mexico", latitude: 23.6345, longitude: -102.5528, flag: "🇲🇽", continent: .northAmerica),
        "NI": CountryInfo(name: "Nicaragua", latitude: 12.8654, longitude: -85.2072, flag: "🇳🇮", continent: .northAmerica),
        "PA": CountryInfo(name: "Panama", latitude: 8.5380, longitude: -80.7821, flag: "🇵🇦", continent: .northAmerica),
        "SV": CountryInfo(name: "El Salvador", latitude: 13.7942, longitude: -88.8965, flag: "🇸🇻", continent: .northAmerica),
        "TC": CountryInfo(name: "Turks and Caicos", latitude: 21.6940, longitude: -71.7979, flag: "🇹🇨", continent: .northAmerica),
        "TT": CountryInfo(name: "Trinidad and Tobago", latitude: 10.6918, longitude: -61.2225, flag: "🇹🇹", continent: .northAmerica),
        "US": CountryInfo(name: "United States", latitude: 37.0902, longitude: -95.7129, flag: "🇺🇸", continent: .northAmerica),

        // --- South America ---
        "AR": CountryInfo(name: "Argentina", latitude: -38.4161, longitude: -63.6167, flag: "🇦🇷", continent: .southAmerica),
        "BO": CountryInfo(name: "Bolivia", latitude: -16.2902, longitude: -63.5887, flag: "🇧🇴", continent: .southAmerica),
        "BR": CountryInfo(name: "Brazil", latitude: -14.2350, longitude: -51.9253, flag: "🇧🇷", continent: .southAmerica),
        "CL": CountryInfo(name: "Chile", latitude: -35.6751, longitude: -71.5430, flag: "🇨🇱", continent: .southAmerica),
        "CO": CountryInfo(name: "Colombia", latitude: 4.5709, longitude: -74.2973, flag: "🇨🇴", continent: .southAmerica),
        "EC": CountryInfo(name: "Ecuador", latitude: -1.8312, longitude: -78.1834, flag: "🇪🇨", continent: .southAmerica),
        "GF": CountryInfo(name: "French Guiana", latitude: 3.9339, longitude: -53.1258, flag: "🇬🇫", continent: .southAmerica),
        "GY": CountryInfo(name: "Guyana", latitude: 4.8604, longitude: -58.9302, flag: "🇬🇾", continent: .southAmerica),
        "PE": CountryInfo(name: "Peru", latitude: -9.1900, longitude: -75.0152, flag: "🇵🇪", continent: .southAmerica),
        "PY": CountryInfo(name: "Paraguay", latitude: -23.4425, longitude: -58.4438, flag: "🇵🇾", continent: .southAmerica),
        "UY": CountryInfo(name: "Uruguay", latitude: -32.5228, longitude: -55.7658, flag: "🇺🇾", continent: .southAmerica),
        "VE": CountryInfo(name: "Venezuela", latitude: 6.4238, longitude: -66.5897, flag: "🇻🇪", continent: .southAmerica),

        // --- Europe ---
        "AD": CountryInfo(name: "Andorra", latitude: 42.5063, longitude: 1.5218, flag: "🇦🇩", continent: .europe),
        "AL": CountryInfo(name: "Albania", latitude: 41.1533, longitude: 20.1683, flag: "🇦🇱", continent: .europe),
        "AT": CountryInfo(name: "Austria", latitude: 47.5162, longitude: 14.5501, flag: "🇦🇹", continent: .europe),
        "BA": CountryInfo(name: "Bosnia and Herzegovina", latitude: 43.9159, longitude: 17.6791, flag: "🇧🇦", continent: .europe),
        "BE": CountryInfo(name: "Belgium", latitude: 50.5039, longitude: 4.4699, flag: "🇧🇪", continent: .europe),
        "BG": CountryInfo(name: "Bulgaria", latitude: 42.7339, longitude: 25.4858, flag: "🇧🇬", continent: .europe),
        "BY": CountryInfo(name: "Belarus", latitude: 53.7098, longitude: 27.9534, flag: "🇧🇾", continent: .europe),
        "CH": CountryInfo(name: "Switzerland", latitude: 46.8182, longitude: 8.2275, flag: "🇨🇭", continent: .europe),
        "CZ": CountryInfo(name: "Czech Republic", latitude: 49.8175, longitude: 15.4730, flag: "🇨🇿", continent: .europe),
        "DE": CountryInfo(name: "Germany", latitude: 51.1657, longitude: 10.4515, flag: "🇩🇪", continent: .europe),
        "DK": CountryInfo(name: "Denmark", latitude: 56.2639, longitude: 9.5018, flag: "🇩🇰", continent: .europe),
        "EE": CountryInfo(name: "Estonia", latitude: 58.5953, longitude: 25.0136, flag: "🇪🇪", continent: .europe),
        "ES": CountryInfo(name: "Spain", latitude: 40.4637, longitude: -3.7492, flag: "🇪🇸", continent: .europe),
        "FI": CountryInfo(name: "Finland", latitude: 61.9241, longitude: 25.7482, flag: "🇫🇮", continent: .europe),
        "FR": CountryInfo(name: "France", latitude: 46.2276, longitude: 2.2137, flag: "🇫🇷", continent: .europe),
        "GB": CountryInfo(name: "United Kingdom", latitude: 55.3781, longitude: -3.4360, flag: "🇬🇧", continent: .europe),
        "GI": CountryInfo(name: "Gibraltar", latitude: 36.1408, longitude: -5.3536, flag: "🇬🇮", continent: .europe),
        "GR": CountryInfo(name: "Greece", latitude: 39.0742, longitude: 21.8243, flag: "🇬🇷", continent: .europe),
        "HR": CountryInfo(name: "Croatia", latitude: 45.1000, longitude: 15.2000, flag: "🇭🇷", continent: .europe),
        "HU": CountryInfo(name: "Hungary", latitude: 47.1625, longitude: 19.5033, flag: "🇭🇺", continent: .europe),
        "IE": CountryInfo(name: "Ireland", latitude: 53.1424, longitude: -7.6921, flag: "🇮🇪", continent: .europe),
        "IT": CountryInfo(name: "Italy", latitude: 41.8719, longitude: 12.5674, flag: "🇮🇹", continent: .europe),
        "LI": CountryInfo(name: "Liechtenstein", latitude: 47.1660, longitude: 9.5554, flag: "🇱🇮", continent: .europe),
        "LT": CountryInfo(name: "Lithuania", latitude: 55.1694, longitude: 23.8813, flag: "🇱🇹", continent: .europe),
        "LV": CountryInfo(name: "Latvia", latitude: 56.8796, longitude: 24.6032, flag: "🇱🇻", continent: .europe),
        "MC": CountryInfo(name: "Monaco", latitude: 43.7384, longitude: 7.4246, flag: "🇲🇨", continent: .europe),
        "MD": CountryInfo(name: "Moldova", latitude: 47.4116, longitude: 28.3699, flag: "🇲🇩", continent: .europe),
        "ME": CountryInfo(name: "Montenegro", latitude: 42.7087, longitude: 19.3744, flag: "🇲🇪", continent: .europe),
        "MK": CountryInfo(name: "North Macedonia", latitude: 41.5124, longitude: 21.7453, flag: "🇲🇰", continent: .europe),
        "MT": CountryInfo(name: "Malta", latitude: 35.9375, longitude: 14.3754, flag: "🇲🇹", continent: .europe),
        "NL": CountryInfo(name: "Netherlands", latitude: 52.1326, longitude: 5.2913, flag: "🇳🇱", continent: .europe),
        "NO": CountryInfo(name: "Norway", latitude: 60.4720, longitude: 8.4689, flag: "🇳🇴", continent: .europe),
        "PL": CountryInfo(name: "Poland", latitude: 51.9194, longitude: 19.1451, flag: "🇵🇱", continent: .europe),
        "PT": CountryInfo(name: "Portugal", latitude: 39.3999, longitude: -8.2245, flag: "🇵🇹", continent: .europe),
        "RO": CountryInfo(name: "Romania", latitude: 45.9432, longitude: 24.9668, flag: "🇷🇴", continent: .europe),
        "RS": CountryInfo(name: "Serbia", latitude: 44.0165, longitude: 21.0059, flag: "🇷🇸", continent: .europe),
        "RU": CountryInfo(name: "Russia", latitude: 61.5240, longitude: 105.3188, flag: "🇷🇺", continent: .europe),
        "SE": CountryInfo(name: "Sweden", latitude: 60.1282, longitude: 18.6435, flag: "🇸🇪", continent: .europe),
        "SI": CountryInfo(name: "Slovenia", latitude: 46.1512, longitude: 14.9955, flag: "🇸🇮", continent: .europe),
        "SK": CountryInfo(name: "Slovakia", latitude: 48.6690, longitude: 19.6990, flag: "🇸🇰", continent: .europe),
        "SM": CountryInfo(name: "San Marino", latitude: 43.9424, longitude: 12.4578, flag: "🇸🇲", continent: .europe),
        "UA": CountryInfo(name: "Ukraine", latitude: 48.3794, longitude: 31.1656, flag: "🇺🇦", continent: .europe),
        "XK": CountryInfo(name: "Kosovo", latitude: 42.6026, longitude: 20.9030, flag: "🇽🇰", continent: .europe),

        // --- Africa ---
        "AO": CountryInfo(name: "Angola", latitude: -11.2027, longitude: 17.8739, flag: "🇦🇴", continent: .africa),
        "CI": CountryInfo(name: "Ivory Coast", latitude: 7.5400, longitude: -5.5471, flag: "🇨🇮", continent: .africa),
        "CM": CountryInfo(name: "Cameroon", latitude: 7.3697, longitude: 12.3547, flag: "🇨🇲", continent: .africa),
        "CV": CountryInfo(name: "Cape Verde", latitude: 16.5388, longitude: -23.0418, flag: "🇨🇻", continent: .africa),
        "DZ": CountryInfo(name: "Algeria", latitude: 28.0339, longitude: 1.6596, flag: "🇩🇿", continent: .africa),
        "GH": CountryInfo(name: "Ghana", latitude: 7.9465, longitude: -1.0232, flag: "🇬🇭", continent: .africa),
        "GQ": CountryInfo(name: "Equatorial Guinea", latitude: 1.6508, longitude: 10.2679, flag: "🇬🇶", continent: .africa),
        "KE": CountryInfo(name: "Kenya", latitude: -0.0236, longitude: 37.9062, flag: "🇰🇪", continent: .africa),
        "LY": CountryInfo(name: "Libya", latitude: 26.3351, longitude: 17.2283, flag: "🇱🇾", continent: .africa),
        "MA": CountryInfo(name: "Morocco", latitude: 31.7917, longitude: -7.0926, flag: "🇲🇦", continent: .africa),
        "MU": CountryInfo(name: "Mauritius", latitude: -20.3484, longitude: 57.5522, flag: "🇲🇺", continent: .africa),
        "MW": CountryInfo(name: "Malawi", latitude: -13.2543, longitude: 34.3015, flag: "🇲🇼", continent: .africa),
        "MZ": CountryInfo(name: "Mozambique", latitude: -18.6657, longitude: 35.5296, flag: "🇲🇿", continent: .africa),
        "NE": CountryInfo(name: "Niger", latitude: 17.6078, longitude: 8.0817, flag: "🇳🇪", continent: .africa),
        "NG": CountryInfo(name: "Nigeria", latitude: 9.0820, longitude: 8.6753, flag: "🇳🇬", continent: .africa),
        "SC": CountryInfo(name: "Seychelles", latitude: -4.6796, longitude: 55.4920, flag: "🇸🇨", continent: .africa),
        "SN": CountryInfo(name: "Senegal", latitude: 14.4974, longitude: -14.4524, flag: "🇸🇳", continent: .africa),
        "TD": CountryInfo(name: "Chad", latitude: 15.4542, longitude: 18.7322, flag: "🇹🇩", continent: .africa),
        "TN": CountryInfo(name: "Tunisia", latitude: 33.8869, longitude: 9.5375, flag: "🇹🇳", continent: .africa),
        "TZ": CountryInfo(name: "Tanzania", latitude: -6.3690, longitude: 34.8888, flag: "🇹🇿", continent: .africa),
        "UG": CountryInfo(name: "Uganda", latitude: 1.3733, longitude: 32.2903, flag: "🇺🇬", continent: .africa),
        "ZA": CountryInfo(name: "South Africa", latitude: -30.5595, longitude: 22.9375, flag: "🇿🇦", continent: .africa),
        "ZM": CountryInfo(name: "Zambia", latitude: -13.1339, longitude: 27.8493, flag: "🇿🇲", continent: .africa),
        "ZW": CountryInfo(name: "Zimbabwe", latitude: -19.0154, longitude: 29.1549, flag: "🇿🇼", continent: .africa),

        // --- Middle East ---
        "AE": CountryInfo(name: "United Arab Emirates", latitude: 23.4241, longitude: 53.8478, flag: "🇦🇪", continent: .middleEast),
        "BH": CountryInfo(name: "Bahrain", latitude: 25.9304, longitude: 50.6378, flag: "🇧🇭", continent: .middleEast),
        "CY": CountryInfo(name: "Cyprus", latitude: 35.1264, longitude: 33.4299, flag: "🇨🇾", continent: .middleEast),
        "EG": CountryInfo(name: "Egypt", latitude: 26.8206, longitude: 30.8025, flag: "🇪🇬", continent: .middleEast),
        "IL": CountryInfo(name: "Israel", latitude: 31.0461, longitude: 34.8516, flag: "🇮🇱", continent: .middleEast),
        "IQ": CountryInfo(name: "Iraq", latitude: 33.2232, longitude: 43.6793, flag: "🇮🇶", continent: .middleEast),
        "JO": CountryInfo(name: "Jordan", latitude: 30.5852, longitude: 36.2384, flag: "🇯🇴", continent: .middleEast),
        "KW": CountryInfo(name: "Kuwait", latitude: 29.3117, longitude: 47.4818, flag: "🇰🇼", continent: .middleEast),
        "LB": CountryInfo(name: "Lebanon", latitude: 33.8547, longitude: 35.8623, flag: "🇱🇧", continent: .middleEast),
        "OM": CountryInfo(name: "Oman", latitude: 21.4735, longitude: 55.9754, flag: "🇴🇲", continent: .middleEast),
        "PS": CountryInfo(name: "Palestine", latitude: 31.9522, longitude: 35.2332, flag: "🇵🇸", continent: .middleEast),
        "QA": CountryInfo(name: "Qatar", latitude: 25.3548, longitude: 51.1839, flag: "🇶🇦", continent: .middleEast),
        "SA": CountryInfo(name: "Saudi Arabia", latitude: 23.8859, longitude: 45.0792, flag: "🇸🇦", continent: .middleEast),
        "TR": CountryInfo(name: "Turkey", latitude: 38.9637, longitude: 35.2433, flag: "🇹🇷", continent: .middleEast),
        "YE": CountryInfo(name: "Yemen", latitude: 15.5527, longitude: 48.5164, flag: "🇾🇪", continent: .middleEast),

        // --- Asia ---
        "HK": CountryInfo(name: "Hong Kong", latitude: 22.3193, longitude: 114.1694, flag: "🇭🇰", continent: .asia),
        "ID": CountryInfo(name: "Indonesia", latitude: -0.7893, longitude: 113.9213, flag: "🇮🇩", continent: .asia),
        "IN": CountryInfo(name: "India", latitude: 20.5937, longitude: 78.9629, flag: "🇮🇳", continent: .asia),
        "JP": CountryInfo(name: "Japan", latitude: 36.2048, longitude: 138.2529, flag: "🇯🇵", continent: .asia),
        "KR": CountryInfo(name: "South Korea", latitude: 35.9078, longitude: 127.7669, flag: "🇰🇷", continent: .asia),
        "MY": CountryInfo(name: "Malaysia", latitude: 4.2105, longitude: 101.9758, flag: "🇲🇾", continent: .asia),
        "PH": CountryInfo(name: "Philippines", latitude: 12.8797, longitude: 121.7740, flag: "🇵🇭", continent: .asia),
        "PK": CountryInfo(name: "Pakistan", latitude: 30.3753, longitude: 69.3451, flag: "🇵🇰", continent: .asia),
        "SG": CountryInfo(name: "Singapore", latitude: 1.3521, longitude: 103.8198, flag: "🇸🇬", continent: .asia),
        "TH": CountryInfo(name: "Thailand", latitude: 15.8700, longitude: 100.9925, flag: "🇹🇭", continent: .asia),
        "TW": CountryInfo(name: "Taiwan", latitude: 23.6978, longitude: 120.9605, flag: "🇹🇼", continent: .asia),

        // --- Oceania ---
        "AU": CountryInfo(name: "Australia", latitude: -25.2744, longitude: 133.7751, flag: "🇦🇺", continent: .oceania),
        "FJ": CountryInfo(name: "Fiji", latitude: -17.7134, longitude: 178.0650, flag: "🇫🇯", continent: .oceania),
        "NZ": CountryInfo(name: "New Zealand", latitude: -40.9006, longitude: 174.8860, flag: "🇳🇿", continent: .oceania),
        "PG": CountryInfo(name: "Papua New Guinea", latitude: -6.3150, longitude: 143.9555, flag: "🇵🇬", continent: .oceania),
    ]

    static func streamingCountries(from regions: [String: WatchProviderRegion]) -> [StreamingCountry] {
        regions.compactMap { code, region in
            guard let flatrate = region.flatrate, !flatrate.isEmpty else { return nil }
            guard let info = countries[code] else { return nil }
            return StreamingCountry(
                id: code,
                name: info.name,
                coordinate: CLLocationCoordinate2D(latitude: info.latitude, longitude: info.longitude),
                flag: info.flag,
                continent: info.continent,
                providers: region
            )
        }
        .sorted { $0.name < $1.name }
    }

    static func clusters(from countries: [StreamingCountry]) -> [ContinentCluster] {
        let grouped = Dictionary(grouping: countries) { $0.continent }
        return grouped.map { continent, members in
            ContinentCluster(id: continent.rawValue, continent: continent, countries: members)
        }
        .sorted { $0.continent.rawValue < $1.continent.rawValue }
    }
}

// MARK: - Streaming Map View

#if canImport(MapKit) && !os(tvOS)

struct StreamingMapView: View {
    let allRegions: [String: WatchProviderRegion]
    let mediaTitle: String
    let alternateTitle: String?
    let mediaType: MediaType
    let year: String?

    @State private var selectedCountry: StreamingCountry?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var allCountries: [StreamingCountry] = []
    @State private var clusters: [ContinentCluster] = []
    @State private var expandedContinent: Continent?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Map(position: $cameraPosition) {
                if let expanded = expandedContinent {
                    // Show individual country pins for the expanded continent
                    let visible = allCountries.filter { $0.continent == expanded }
                    ForEach(visible) { country in
                        Annotation(country.name, coordinate: country.coordinate) {
                            CountryPinView(country: country) {
                                selectedCountry = country
                            }
                        }
                    }
                } else {
                    // Show continent cluster pins
                    ForEach(clusters) { cluster in
                        Annotation(cluster.continent.rawValue, coordinate: cluster.coordinate) {
                            ClusterPinView(cluster: cluster) {
                                expandedContinent = cluster.continent
                                withAnimation {
                                    cameraPosition = .region(MKCoordinateRegion(
                                        center: cluster.continent.centerCoordinate,
                                        span: cluster.continent.regionSpan
                                    ))
                                }
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .mapControls {
                MapCompass()
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topLeading) {
                if expandedContinent != nil {
                    Button {
                        expandedContinent = nil
                        withAnimation {
                            cameraPosition = .automatic
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                            Text("All")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThickMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
            }
        }
        .onAppear {
            allCountries = CountryDirectory.streamingCountries(from: allRegions)
            clusters = CountryDirectory.clusters(from: allCountries)
        }
        .sheet(item: $selectedCountry) { country in
            CountryStreamingDetailView(
                country: country,
                mediaTitle: mediaTitle,
                alternateTitle: alternateTitle,
                mediaType: mediaType,
                year: year
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Cluster Pin View

/// Shows a continent emoji + country count badge. Tapping zooms into that continent.
private struct ClusterPinView: View {
    let cluster: ContinentCluster
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(cluster.continent.emoji)
                    .font(.system(size: 20))

                Text("\(cluster.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor, in: Capsule())
            }
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThickMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Country Pin View

/// Shows a country flag. Tapping opens the streaming detail sheet.
private struct CountryPinView: View {
    let country: StreamingCountry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Text(country.flag)
                    .font(.system(size: 18))
                    .padding(4)
                    .background {
                        Circle()
                            .fill(.ultraThickMaterial)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    }

                // Pin tail
                Triangle()
                    .fill(.ultraThickMaterial)
                    .frame(width: 10, height: 5)
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A small triangle shape used as the pin tail.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - rect.width / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width / 2, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Country Streaming Detail Sheet

struct CountryStreamingDetailView: View {
    let country: StreamingCountry
    let mediaTitle: String
    let alternateTitle: String?
    let mediaType: MediaType
    let year: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Text(country.flag)
                            .font(.system(size: 48))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(country.name)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(country.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                    }
                    .padding(.bottom, 4)

                    if let flatrate = country.providers.flatrate, !flatrate.isEmpty {
                        StreamingMapProviderSection(title: "Stream", systemImage: "play.circle.fill", providers: flatrate)
                    }

                    if let ads = country.providers.ads, !ads.isEmpty {
                        StreamingMapProviderSection(title: "Free with Ads", systemImage: "megaphone.fill", providers: ads)
                    }

                    if let free = country.providers.free, !free.isEmpty {
                        StreamingMapProviderSection(title: "Free", systemImage: "gift.fill", providers: free)
                    }
                }
                .padding()
            }
            .navigationTitle("Streaming in \(country.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Provider Section

private struct StreamingMapProviderSection: View {
    let title: String
    let systemImage: String
    let providers: [WatchProvider]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 12)], spacing: 12) {
                ForEach(providers) { provider in
                    StreamingMapProviderTile(provider: provider)
                }
            }
        }
    }
}

private struct StreamingMapProviderTile: View {
    let provider: WatchProvider

    var body: some View {
        VStack(spacing: 6) {
            if let logoPath = provider.logoPath {
                AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w92\(logoPath)")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        providerPlaceholder
                    default:
                        ProgressView()
                            .frame(width: 48, height: 48)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                providerPlaceholder
            }

            Text(provider.providerName)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
    }

    private var providerPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 48, height: 48)
            .overlay {
                Text(String(provider.providerName.prefix(2)))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
    }
}

#endif

// MARK: - tvOS Fallback

#if os(tvOS)
struct StreamingMapView: View {
    let allRegions: [String: WatchProviderRegion]
    let mediaTitle: String
    let alternateTitle: String?
    let mediaType: MediaType
    let year: String?

    var body: some View {
        let countries = CountryDirectory.streamingCountries(from: allRegions)

        if countries.isEmpty {
            Text("No streaming availability found.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(countries) { country in
                            VStack(spacing: 4) {
                                Text(country.flag)
                                    .font(.system(size: 32))
                                Text(country.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .frame(width: 80)
                        }
                    }
                }
            }
        }
    }
}
#endif
