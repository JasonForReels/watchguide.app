import Foundation
import CoreLocation

struct CinemaLocation: Identifiable, Equatable {
    let id: String
    let name: String
    let suburb: String
    let city: String
    let coordinate: CLLocationCoordinate2D
    /// The exact business name as it appears on Apple Maps for reliable search
    let mapSearchName: String
    /// The slug used on sterkinekor.com/program?location=<slug>
    let websiteSlug: String
    /// Whether this location has IMAX
    let hasIMAX: Bool

    /// Full Ster-Kinekor program URL for this location
    var websiteURL: URL? {
        URL(string: "https://www.sterkinekor.com/program?location=\(websiteSlug)")
    }

    static func == (lhs: CinemaLocation, rhs: CinemaLocation) -> Bool {
        lhs.id == rhs.id
    }
}

enum SouthAfricaCinemaDirectory {
    static let sterKinekor: [CinemaLocation] = [
        CinemaLocation(
            id: "sterkinekor-sandton",
            name: "Ster-Kinekor Sandton City",
            suburb: "Sandton",
            city: "Johannesburg",
            coordinate: CLLocationCoordinate2D(latitude: -26.1076, longitude: 28.0567),
            mapSearchName: "Ster-Kinekor Sandton City",
            websiteSlug: "sandtoncity",
            hasIMAX: false
        ),
        CinemaLocation(
            id: "sterkinekor-eastgate",
            name: "Ster-Kinekor Eastgate & IMAX",
            suburb: "Bedfordview",
            city: "Johannesburg",
            coordinate: CLLocationCoordinate2D(latitude: -26.1814, longitude: 28.1372),
            mapSearchName: "Ster-Kinekor Eastgate & IMAX",
            websiteSlug: "eastgate",
            hasIMAX: true
        ),
        CinemaLocation(
            id: "sterkinekor-rosebank",
            name: "Ster-Kinekor Nouveau Rosebank",
            suburb: "Rosebank",
            city: "Johannesburg",
            coordinate: CLLocationCoordinate2D(latitude: -26.1457, longitude: 28.0424),
            mapSearchName: "Ster-Kinekor Rosebank",
            websiteSlug: "rosebank",
            hasIMAX: false
        ),
        CinemaLocation(
            id: "sterkinekor-tyger",
            name: "Ster-Kinekor Tyger Valley",
            suburb: "Bellville",
            city: "Cape Town",
            coordinate: CLLocationCoordinate2D(latitude: -33.8758, longitude: 18.6350),
            mapSearchName: "Ster-Kinekor Tyger Valley",
            websiteSlug: "tygervalley",
            hasIMAX: false
        ),
        CinemaLocation(
            id: "sterkinekor-cavendish",
            name: "Ster-Kinekor Cavendish",
            suburb: "Claremont",
            city: "Cape Town",
            coordinate: CLLocationCoordinate2D(latitude: -33.9792, longitude: 18.4632),
            mapSearchName: "Ster-Kinekor Cavendish",
            websiteSlug: "cavendish",
            hasIMAX: false
        ),
        CinemaLocation(
            id: "sterkinekor-vanda",
            name: "Ster-Kinekor V&A Waterfront & IMAX",
            suburb: "V&A Waterfront",
            city: "Cape Town",
            coordinate: CLLocationCoordinate2D(latitude: -33.9032, longitude: 18.4207),
            mapSearchName: "Ster-Kinekor V&A Waterfront",
            websiteSlug: "v-a-waterfront",
            hasIMAX: true
        ),
        CinemaLocation(
            id: "sterkinekor-pavilion",
            name: "Ster-Kinekor The Pavilion",
            suburb: "Westville",
            city: "Durban",
            coordinate: CLLocationCoordinate2D(latitude: -29.8466, longitude: 30.9351),
            mapSearchName: "Ster-Kinekor Pavilion Westville",
            websiteSlug: "pavilion",
            hasIMAX: false
        ),
        CinemaLocation(
            id: "sterkinekor-gateway",
            name: "Ster-Kinekor Gateway & IMAX",
            suburb: "Umhlanga",
            city: "Durban",
            coordinate: CLLocationCoordinate2D(latitude: -29.7272, longitude: 31.0667),
            mapSearchName: "Ster-Kinekor Gateway",
            websiteSlug: "gateway",
            hasIMAX: true
        ),
        CinemaLocation(
            id: "sterkinekor-brooklyn",
            name: "Ster-Kinekor Brooklyn",
            suburb: "Brooklyn",
            city: "Pretoria",
            coordinate: CLLocationCoordinate2D(latitude: -25.7690, longitude: 28.2334),
            mapSearchName: "Ster-Kinekor Brooklyn",
            websiteSlug: "brooklyncommercia",
            hasIMAX: false
        ),
        CinemaLocation(
            id: "sterkinekor-centurion",
            name: "Ster-Kinekor Centurion Mall",
            suburb: "Centurion",
            city: "Pretoria",
            coordinate: CLLocationCoordinate2D(latitude: -25.8592, longitude: 28.1881),
            mapSearchName: "Ster-Kinekor Centurion",
            websiteSlug: "centurion",
            hasIMAX: false
        )
    ]
}
