import Foundation
import CoreLocation

struct CinemaLocation: Identifiable {
    let id: String
    let name: String
    let suburb: String
    let city: String
    let coordinate: CLLocationCoordinate2D
    let mapQuery: String
    /// The slug used on sterkinekor.com/program?location=<slug>
    let websiteSlug: String

    /// Full Ster-Kinekor program URL for this location
    var websiteURL: URL? {
        URL(string: "https://www.sterkinekor.com/program?location=\(websiteSlug)")
    }
}

enum SouthAfricaCinemaDirectory {
    static let sterKinekor: [CinemaLocation] = [
        CinemaLocation(
            id: "sterkinekor-sandton",
            name: "Ster-Kinekor Sandton",
            suburb: "Sandton",
            city: "Johannesburg",
            coordinate: CLLocationCoordinate2D(latitude: -26.1076, longitude: 28.0567),
            mapQuery: "Ster-Kinekor Sandton",
            websiteSlug: "sandtoncity"
        ),
        CinemaLocation(
            id: "sterkinekor-eastgate",
            name: "Ster-Kinekor Eastgate",
            suburb: "Bedfordview",
            city: "Johannesburg",
            coordinate: CLLocationCoordinate2D(latitude: -26.1814, longitude: 28.1372),
            mapQuery: "Ster-Kinekor Eastgate",
            websiteSlug: "eastgate"
        ),
        CinemaLocation(
            id: "sterkinekor-rosebank",
            name: "Ster-Kinekor Rosebank",
            suburb: "Rosebank",
            city: "Johannesburg",
            coordinate: CLLocationCoordinate2D(latitude: -26.1457, longitude: 28.0424),
            mapQuery: "Ster-Kinekor Rosebank",
            websiteSlug: "rosebank"
        ),
        CinemaLocation(
            id: "sterkinekor-tyger",
            name: "Ster-Kinekor Tyger Valley",
            suburb: "Bellville",
            city: "Cape Town",
            coordinate: CLLocationCoordinate2D(latitude: -33.8758, longitude: 18.6350),
            mapQuery: "Ster-Kinekor Tyger Valley",
            websiteSlug: "tygervalley"
        ),
        CinemaLocation(
            id: "sterkinekor-cavendish",
            name: "Ster-Kinekor Cavendish",
            suburb: "Claremont",
            city: "Cape Town",
            coordinate: CLLocationCoordinate2D(latitude: -33.9792, longitude: 18.4632),
            mapQuery: "Ster-Kinekor Cavendish",
            websiteSlug: "cavendish"
        ),
        CinemaLocation(
            id: "sterkinekor-vanda",
            name: "Ster-Kinekor V&A Waterfront",
            suburb: "V&A Waterfront",
            city: "Cape Town",
            coordinate: CLLocationCoordinate2D(latitude: -33.9032, longitude: 18.4207),
            mapQuery: "Ster-Kinekor V&A Waterfront",
            websiteSlug: "v-a-waterfront"
        ),
        CinemaLocation(
            id: "sterkinekor-pavilion",
            name: "Ster-Kinekor The Pavilion",
            suburb: "Westville",
            city: "Durban",
            coordinate: CLLocationCoordinate2D(latitude: -29.8466, longitude: 30.9351),
            mapQuery: "Ster-Kinekor Pavilion",
            websiteSlug: "pavilion"
        ),
        CinemaLocation(
            id: "sterkinekor-gateway",
            name: "Ster-Kinekor Gateway",
            suburb: "Umhlanga",
            city: "Durban",
            coordinate: CLLocationCoordinate2D(latitude: -29.7272, longitude: 31.0667),
            mapQuery: "Ster-Kinekor Gateway",
            websiteSlug: "gateway"
        ),
        CinemaLocation(
            id: "sterkinekor-brooklyn",
            name: "Ster-Kinekor Brooklyn",
            suburb: "Brooklyn",
            city: "Pretoria",
            coordinate: CLLocationCoordinate2D(latitude: -25.7690, longitude: 28.2334),
            mapQuery: "Ster-Kinekor Brooklyn",
            websiteSlug: "brooklyncommercia"
        ),
        CinemaLocation(
            id: "sterkinekor-centurion",
            name: "Ster-Kinekor Centurion",
            suburb: "Centurion",
            city: "Pretoria",
            coordinate: CLLocationCoordinate2D(latitude: -25.8592, longitude: 28.1881),
            mapQuery: "Ster-Kinekor Centurion",
            websiteSlug: "centurion"
        )
    ]
}
