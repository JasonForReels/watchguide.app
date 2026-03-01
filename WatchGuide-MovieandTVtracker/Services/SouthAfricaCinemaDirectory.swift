import Foundation
import CoreLocation
import MapKit

struct CinemaLocation: Identifiable, Equatable {
    let id: String
    let name: String
    let suburb: String
    let city: String
    /// Fallback coordinate (shopping centre GPS); replaced at runtime by MKLocalSearch
    let coordinate: CLLocationCoordinate2D
    /// Search query used with MKLocalSearch to find the real pin
    let mapSearchQuery: String
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

    /// Return a copy with updated coordinate
    func withCoordinate(_ coord: CLLocationCoordinate2D) -> CinemaLocation {
        CinemaLocation(
            id: id,
            name: name,
            suburb: suburb,
            city: city,
            coordinate: coord,
            mapSearchQuery: mapSearchQuery,
            mapSearchName: mapSearchName,
            websiteSlug: websiteSlug,
            hasIMAX: hasIMAX
        )
    }
}

/// Resolves cinema locations to accurate map pins via Apple Maps search
@MainActor
final class CinemaLocationResolver: ObservableObject {
    @Published var resolvedCinemas: [CinemaLocation] = SouthAfricaCinemaDirectory.sterKinekor
    @Published var isResolving = false
    private var hasResolved = false

    func resolveAll() async {
        guard !hasResolved else { return }
        hasResolved = true
        isResolving = true
        defer { isResolving = false }

        var updated = resolvedCinemas
        await withTaskGroup(of: (Int, CLLocationCoordinate2D?).self) { group in
            for (index, cinema) in resolvedCinemas.enumerated() {
                group.addTask {
                    let coord = await self.searchLocation(for: cinema)
                    return (index, coord)
                }
            }
            for await (index, coord) in group {
                if let coord {
                    updated[index] = updated[index].withCoordinate(coord)
                }
            }
        }
        resolvedCinemas = updated
    }

    private func searchLocation(for cinema: CinemaLocation) async -> CLLocationCoordinate2D? {
        // Search near the fallback coordinate so results are regionally relevant
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = cinema.mapSearchQuery
        request.region = MKCoordinateRegion(
            center: cinema.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
        request.resultTypes = .pointOfInterest

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            // Pick the closest match to our fallback
            let fallback = CLLocation(latitude: cinema.coordinate.latitude, longitude: cinema.coordinate.longitude)
            let best = response.mapItems
                .sorted { a, b in
                    let dA = CLLocation(latitude: a.placemark.coordinate.latitude, longitude: a.placemark.coordinate.longitude).distance(from: fallback)
                    let dB = CLLocation(latitude: b.placemark.coordinate.latitude, longitude: b.placemark.coordinate.longitude).distance(from: fallback)
                    return dA < dB
                }
                .first
            return best?.placemark.coordinate
        } catch {
            return nil // keep fallback
        }
    }
}

enum SouthAfricaCinemaDirectory {
    /// Fallback coordinates point to the shopping centre/mall entrance for each location.
    /// At runtime, CinemaLocationResolver refines these via Apple Maps search.
    static let sterKinekor: [CinemaLocation] = [
        CinemaLocation(
            id: "sterkinekor-sandton",
            name: "Ster-Kinekor Sandton City",
            suburb: "Sandton",
            city: "Johannesburg",
            coordinate: CLLocationCoordinate2D(latitude: -26.1050, longitude: 28.0525),
            mapSearchQuery: "Sandton City Shopping Centre Sandton",
            mapSearchName: "Ster-Kinekor Sandton City",
            websiteSlug: "sandtoncity",
            hasIMAX: false
        ),
        CinemaLocation(
            id: "sterkinekor-eastgate",
            name: "Ster-Kinekor Eastgate & IMAX",
            suburb: "Bedfordview",
            city: "Johannesburg",
            coordinate: CLLocationCoordinate2D(latitude: -26.1797, longitude: 28.1164),
            mapSearchQuery: "Eastgate Shopping Centre Bedfordview",
            mapSearchName: "Ster-Kinekor Eastgate",
            websiteSlug: "eastgate",
            hasIMAX: true
        ),
        CinemaLocation(
            id: "sterkinekor-rosebank",
            name: "Ster-Kinekor Nouveau Rosebank",
            suburb: "Rosebank",
            city: "Johannesburg",
            coordinate: CLLocationCoordinate2D(latitude: -26.1466, longitude: 28.0417),
            mapSearchQuery: "Rosebank Mall Johannesburg",
            mapSearchName: "Ster-Kinekor Rosebank",
            websiteSlug: "rosebank",
            hasIMAX: false
        ),
        CinemaLocation(
            id: "sterkinekor-tyger",
            name: "Ster-Kinekor Tyger Valley",
            suburb: "Bellville",
            city: "Cape Town",
            coordinate: CLLocationCoordinate2D(latitude: -33.8697, longitude: 18.6336),
            mapSearchQuery: "Tyger Valley Shopping Centre Bellville",
            mapSearchName: "Ster-Kinekor Tyger Valley",
            websiteSlug: "tygervalley",
            hasIMAX: false
        ),
        CinemaLocation(
            id: "sterkinekor-cavendish",
            name: "Ster-Kinekor Cavendish",
            suburb: "Claremont",
            city: "Cape Town",
            coordinate: CLLocationCoordinate2D(latitude: -33.9792, longitude: 18.4617),
            mapSearchQuery: "Cavendish Square Shopping Centre Claremont",
            mapSearchName: "Ster-Kinekor Cavendish",
            websiteSlug: "cavendish",
            hasIMAX: false
        ),
        CinemaLocation(
            id: "sterkinekor-vanda",
            name: "Ster-Kinekor V&A Waterfront & IMAX",
            suburb: "V&A Waterfront",
            city: "Cape Town",
            coordinate: CLLocationCoordinate2D(latitude: -33.9036, longitude: 18.4205),
            mapSearchQuery: "V&A Waterfront Shopping Centre Cape Town",
            mapSearchName: "Ster-Kinekor V&A Waterfront",
            websiteSlug: "v-a-waterfront",
            hasIMAX: true
        ),
        CinemaLocation(
            id: "sterkinekor-pavilion",
            name: "Ster-Kinekor The Pavilion",
            suburb: "Westville",
            city: "Durban",
            coordinate: CLLocationCoordinate2D(latitude: -29.8494, longitude: 30.9276),
            mapSearchQuery: "The Pavilion Shopping Centre Westville Durban",
            mapSearchName: "Ster-Kinekor Pavilion Westville",
            websiteSlug: "pavilion",
            hasIMAX: false
        ),
        CinemaLocation(
            id: "sterkinekor-gateway",
            name: "Ster-Kinekor Gateway & IMAX",
            suburb: "Umhlanga",
            city: "Durban",
            coordinate: CLLocationCoordinate2D(latitude: -29.7350, longitude: 31.0428),
            mapSearchQuery: "Gateway Theatre of Shopping Umhlanga",
            mapSearchName: "Ster-Kinekor Gateway",
            websiteSlug: "gateway",
            hasIMAX: true
        ),
        CinemaLocation(
            id: "sterkinekor-brooklyn",
            name: "Ster-Kinekor Brooklyn",
            suburb: "Brooklyn",
            city: "Pretoria",
            coordinate: CLLocationCoordinate2D(latitude: -25.7723, longitude: 28.2365),
            mapSearchQuery: "Brooklyn Mall Pretoria",
            mapSearchName: "Ster-Kinekor Brooklyn",
            websiteSlug: "brooklyncommercia",
            hasIMAX: false
        ),
        CinemaLocation(
            id: "sterkinekor-centurion",
            name: "Ster-Kinekor Centurion Mall",
            suburb: "Centurion",
            city: "Pretoria",
            coordinate: CLLocationCoordinate2D(latitude: -25.8603, longitude: 28.1892),
            mapSearchQuery: "Centurion Mall Pretoria",
            mapSearchName: "Ster-Kinekor Centurion",
            websiteSlug: "centurion",
            hasIMAX: false
        )
    ]
}
