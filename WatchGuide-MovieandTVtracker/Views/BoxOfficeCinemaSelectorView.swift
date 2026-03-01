import SwiftUI
import CoreLocation
import MapKit

private struct CinemaRouteInfo: Equatable {
    let cinema: CinemaLocation
    let distanceMeters: CLLocationDistance
    let expectedTravelTime: TimeInterval?

    var distanceText: String {
        let km = distanceMeters / 1_000
        return String(format: "%.1f km", km)
    }

    var etaText: String {
        guard let expectedTravelTime else { return "" }
        let minutes = Int((expectedTravelTime / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours)h \(remainder)m"
    }

    static func == (lhs: CinemaRouteInfo, rhs: CinemaRouteInfo) -> Bool {
        lhs.cinema.id == rhs.cinema.id
    }
}

@MainActor
private final class BoxOfficeLocationViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var city: String?
    @Published var suburb: String?
    @Published var nearest: CinemaRouteInfo?
    @Published var nearby: [CinemaRouteInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedCinema: CinemaLocation?
    @Published var showSafari = false
    @Published var safariURL: URL?

    /// Map camera position — starts centered on South Africa
    @Published var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -28.5, longitude: 25.5),
            span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
        )
    )

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    let allCinemas = SouthAfricaCinemaDirectory.sterKinekor

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestLocation() {
        errorMessage = nil
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            errorMessage = "Location access is off. Enable it in Settings to find cinemas near you."
        @unknown default:
            errorMessage = "Location access is unavailable right now."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        Task { await updateNearbyCinemas(from: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Could not get your location."
    }

    private func updateNearbyCinemas(from location: CLLocation) async {
        isLoading = true
        defer { isLoading = false }

        await reverseGeocode(location)

        let withDistance = allCinemas.map { cinema -> (CinemaLocation, CLLocationDistance) in
            let destination = CLLocation(latitude: cinema.coordinate.latitude, longitude: cinema.coordinate.longitude)
            return (cinema, location.distance(from: destination))
        }
        .sorted { $0.1 < $1.1 }

        var routeInfos: [CinemaRouteInfo] = []
        await withTaskGroup(of: CinemaRouteInfo?.self) { group in
            for (cinema, straightDistance) in withDistance.prefix(8) {
                group.addTask {
                    let eta = await self.fetchETA(from: location.coordinate, to: cinema.coordinate)
                    return CinemaRouteInfo(cinema: cinema, distanceMeters: straightDistance, expectedTravelTime: eta)
                }
            }
            for await info in group {
                if let info { routeInfos.append(info) }
            }
        }

        let sorted = routeInfos.sorted { $0.distanceMeters < $1.distanceMeters }
        nearby = sorted
        nearest = sorted.first

        // Zoom the map to show the user and the nearest cinema
        if let nearestCinema = sorted.first {
            let midLat = (location.coordinate.latitude + nearestCinema.cinema.coordinate.latitude) / 2
            let midLon = (location.coordinate.longitude + nearestCinema.cinema.coordinate.longitude) / 2
            let latDelta = abs(location.coordinate.latitude - nearestCinema.cinema.coordinate.latitude) * 1.8
            let lonDelta = abs(location.coordinate.longitude - nearestCinema.cinema.coordinate.longitude) * 1.8
            withAnimation(.easeInOut(duration: 0.6)) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
                        span: MKCoordinateSpan(
                            latitudeDelta: max(latDelta, 0.05),
                            longitudeDelta: max(lonDelta, 0.05)
                        )
                    )
                )
            }
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            let first = placemarks.first
            suburb = first?.subLocality ?? first?.locality
            city = first?.locality ?? first?.administrativeArea
        } catch {
            suburb = nil
            city = nil
        }
    }

    private func fetchETA(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            return response.routes.first?.expectedTravelTime
        } catch {
            return nil
        }
    }

    func openDirections(to cinema: CinemaLocation) {
        guard let currentLocation else { return }
        let source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate))
        source.name = "My Location"
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: cinema.coordinate))
        destination.name = cinema.name
        MKMapItem.openMaps(
            with: [source, destination],
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        )
    }

    func openWebsite(for cinema: CinemaLocation) {
        guard let url = cinema.websiteURL else { return }
        safariURL = url
        showSafari = true
    }

    func focusCinema(_ cinema: CinemaLocation) {
        withAnimation(.easeInOut(duration: 0.5)) {
            selectedCinema = cinema
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: cinema.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
        }
    }

    func routeInfo(for cinema: CinemaLocation) -> CinemaRouteInfo? {
        nearby.first(where: { $0.cinema.id == cinema.id })
    }
}

// MARK: - Main View

struct BoxOfficeCinemaSelectorView: View {
    @StateObject private var viewModel = BoxOfficeLocationViewModel()
    @State private var showList = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen interactive map
            Map(position: $viewModel.cameraPosition, selection: Binding(
                get: { viewModel.selectedCinema?.id },
                set: { newId in
                    viewModel.selectedCinema = viewModel.allCinemas.first(where: { $0.id == newId })
                }
            )) {
                // User location
                UserAnnotation()

                // Cinema pins
                ForEach(viewModel.allCinemas) { cinema in
                    Annotation(cinema.name, coordinate: cinema.coordinate, anchor: .bottom) {
                        CinemaMapPin(
                            isSelected: viewModel.selectedCinema?.id == cinema.id,
                            isNearest: viewModel.nearest?.cinema.id == cinema.id
                        )
                        .onTapGesture {
                            viewModel.focusCinema(cinema)
                        }
                    }
                    .tag(cinema.id)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .including([.movieTheater])))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .top)

            // Bottom card overlay
            VStack(spacing: 0) {
                if let selected = viewModel.selectedCinema {
                    // Selected cinema detail card
                    CinemaDetailCard(
                        cinema: selected,
                        routeInfo: viewModel.routeInfo(for: selected),
                        onShowtimes: { viewModel.openWebsite(for: selected) },
                        onDirections: { viewModel.openDirections(to: selected) },
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewModel.selectedCinema = nil
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let nearest = viewModel.nearest {
                    // Nearest cinema quick card
                    NearestCinemaCard(
                        info: nearest,
                        onTap: { viewModel.focusCinema(nearest.cinema) },
                        onShowAll: { showList = true }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Location prompt card
                    LocationPromptCard(
                        isLoading: viewModel.isLoading,
                        error: viewModel.errorMessage,
                        onLocate: { viewModel.requestLocation() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.selectedCinema?.id)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.nearest?.cinema.id)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle("Box Office")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.requestLocation()
        }
        .sheet(isPresented: $showList) {
            CinemaListSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showSafari) {
            if let url = viewModel.safariURL {
                InAppSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Map Pin

private struct CinemaMapPin: View {
    let isSelected: Bool
    let isNearest: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(pinColor.opacity(0.2))
                .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)

            Circle()
                .fill(pinColor)
                .frame(width: isSelected ? 30 : 22, height: isSelected ? 30 : 22)
                .shadow(color: pinColor.opacity(0.4), radius: isSelected ? 6 : 3, y: 2)

            Image(systemName: "film.fill")
                .font(.system(size: isSelected ? 14 : 10, weight: .bold))
                .foregroundColor(.white)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private var pinColor: Color {
        if isSelected { return .accentColor }
        if isNearest { return .red }
        return Color(.systemGray)
    }
}

// MARK: - Location Prompt Card

private struct LocationPromptCard: View {
    let isLoading: Bool
    let error: String?
    let onLocate: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding cinemas near you...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find Nearby Cinemas")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if let error {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("Tap to use your location")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: onLocate) {
                        Image(systemName: "location.circle.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        )
    }
}

// MARK: - Nearest Cinema Card

private struct NearestCinemaCard: View {
    let info: CinemaRouteInfo
    let onTap: () -> Void
    let onShowAll: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nearest Cinema")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(info.cinema.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        HStack(spacing: 6) {
                            Text(info.distanceText)
                            if !info.etaText.isEmpty {
                                Text("·")
                                Text(info.etaText)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            Button(action: onShowAll) {
                Text("View All Cinemas")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        )
    }
}

// MARK: - Cinema Detail Card (selected cinema)

private struct CinemaDetailCard: View {
    let cinema: CinemaLocation
    let routeInfo: CinemaRouteInfo?
    let onShowtimes: () -> Void
    let onDirections: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // Header with dismiss
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cinema.name)
                        .font(.headline)
                    Text("\(cinema.suburb), \(cinema.city)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let info = routeInfo {
                        HStack(spacing: 6) {
                            Image(systemName: "car.fill")
                                .font(.caption2)
                            Text(info.distanceText)
                            if !info.etaText.isEmpty {
                                Text("·")
                                Text(info.etaText)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onShowtimes) {
                    HStack(spacing: 6) {
                        Image(systemName: "ticket.fill")
                        Text("View Showtimes")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor)
                    )
                }

                Button(action: onDirections) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        Text("Directions")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.systemGray5))
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        )
    }
}

// MARK: - Cinema List Sheet

private struct CinemaListSheet: View {
    @ObservedObject var viewModel: BoxOfficeLocationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.nearby.isEmpty {
                    Section("Sorted by Distance") {
                        ForEach(viewModel.nearby, id: \.cinema.id) { info in
                            CinemaListRow(info: info) {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    viewModel.focusCinema(info.cinema)
                                }
                            } onShowtimes: {
                                viewModel.openWebsite(for: info.cinema)
                            }
                        }
                    }
                }

                let remainingIds = Set(viewModel.nearby.map(\.cinema.id))
                let remaining = viewModel.allCinemas.filter { !remainingIds.contains($0.id) }
                if !remaining.isEmpty {
                    Section("Other Cinemas") {
                        ForEach(remaining) { cinema in
                            CinemaListRow(cinema: cinema) {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    viewModel.focusCinema(cinema)
                                }
                            } onShowtimes: {
                                viewModel.openWebsite(for: cinema)
                            }
                        }
                    }
                }
            }
            .navigationTitle("All Cinemas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct CinemaListRow: View {
    let cinema: CinemaLocation
    let info: CinemaRouteInfo?
    let onLocate: () -> Void
    let onShowtimes: () -> Void

    init(info: CinemaRouteInfo, onLocate: @escaping () -> Void, onShowtimes: @escaping () -> Void) {
        self.cinema = info.cinema
        self.info = info
        self.onLocate = onLocate
        self.onShowtimes = onShowtimes
    }

    init(cinema: CinemaLocation, onLocate: @escaping () -> Void, onShowtimes: @escaping () -> Void) {
        self.cinema = cinema
        self.info = nil
        self.onLocate = onLocate
        self.onShowtimes = onShowtimes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cinema.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(cinema.suburb), \(cinema.city)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let info {
                        HStack(spacing: 4) {
                            Text(info.distanceText)
                            if !info.etaText.isEmpty {
                                Text("·")
                                Text(info.etaText)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button(action: onShowtimes) {
                    HStack(spacing: 4) {
                        Image(systemName: "ticket.fill")
                            .font(.caption2)
                        Text("Showtimes")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.accentColor)
                }

                Button(action: onLocate) {
                    HStack(spacing: 4) {
                        Image(systemName: "map.fill")
                            .font(.caption2)
                        Text("Show on Map")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        BoxOfficeCinemaSelectorView()
    }
}
