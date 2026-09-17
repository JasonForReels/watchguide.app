import SwiftUI
@preconcurrency import CoreLocation
import MapKit

private struct CinemaRouteInfo: Equatable {
    let cinema: CinemaLocation
    let distanceMeters: CLLocationDistance
    let expectedTravelTime: TimeInterval?
    let route: MKRoute?

    var distanceText: String {
        let km = distanceMeters / 1_000
        return String(format: "%.1f km", km)
    }

    var drivingDistanceText: String? {
        guard let route else { return nil }
        let km = route.distance / 1_000
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
    @Published var activeRoute: MKRoute?
    @Published var showingRouteForCinema: CinemaLocation?

    /// Map camera position — starts centered on South Africa
    @Published var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -28.5, longitude: 25.5),
            span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
        )
    )

    let resolver = CinemaLocationResolver()

    var allCinemas: [CinemaLocation] { resolver.resolvedCinemas }

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    /// Kick off Apple Maps search to refine all cinema pin locations
    func resolveLocations() async {
        await resolver.resolveAll()
        // If we already have user location, recalculate distances with refined coords
        if let loc = currentLocation {
            await updateNearbyCinemas(from: loc)
        }
    }

    func requestLocation() {
        errorMessage = nil
        switch authorizationStatus {
        case _ where isAuthorized(authorizationStatus):
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            errorMessage = "Location access is off. Enable it in Settings to find cinemas near you."
        @unknown default:
            errorMessage = "Location access is unavailable right now."
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if isAuthorized(authorizationStatus) {
                manager.requestLocation()
            }
        }
    }

    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(macOS)
        return status == .authorized || status == .authorizedAlways
        #else
        return status == .authorizedWhenInUse || status == .authorizedAlways
        #endif
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location
            await updateNearbyCinemas(from: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = "Could not get your location."
        }
    }

    private func updateNearbyCinemas(from location: CLLocation) async {
        isLoading = true
        defer { isLoading = false }

        await reverseGeocode(location)

        let cinemas = allCinemas
        let withDistance = cinemas.map { cinema -> (CinemaLocation, CLLocationDistance) in
            let destination = CLLocation(latitude: cinema.coordinate.latitude, longitude: cinema.coordinate.longitude)
            return (cinema, location.distance(from: destination))
        }
        .sorted { $0.1 < $1.1 }

        var routeInfos: [CinemaRouteInfo] = []
        await withTaskGroup(of: CinemaRouteInfo?.self) { group in
            for (cinema, straightDistance) in withDistance.prefix(8) {
                group.addTask {
                    let route = await self.fetchRoute(from: location.coordinate, to: cinema.coordinate)
                    return CinemaRouteInfo(
                        cinema: cinema,
                        distanceMeters: straightDistance,
                        expectedTravelTime: route?.expectedTravelTime,
                        route: route
                    )
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

    private func fetchRoute(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            return response.routes.first
        } catch {
            return nil
        }
    }

    /// Show driving route on the map without leaving the app
    func showRoute(to cinema: CinemaLocation) {
        guard let info = routeInfo(for: cinema), let route = info.route else {
            // No cached route, fetch one
            Task {
                guard let loc = currentLocation else { return }
                if let route = await fetchRoute(from: loc.coordinate, to: cinema.coordinate) {
                    activeRoute = route
                    showingRouteForCinema = cinema
                    zoomToRoute(route, cinema: cinema)
                }
            }
            return
        }
        activeRoute = route
        showingRouteForCinema = cinema
        zoomToRoute(route, cinema: cinema)
    }

    func clearRoute() {
        withAnimation(.easeInOut(duration: 0.3)) {
            activeRoute = nil
            showingRouteForCinema = nil
        }
    }

    private func zoomToRoute(_ route: MKRoute, cinema: CinemaLocation) {
        let rect = route.polyline.boundingMapRect
        let padding = rect.size.width * 0.3
        let padded = rect.insetBy(dx: -padding, dy: -padding)
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .rect(padded)
        }
    }

    /// Open Apple Maps with business name search for accurate navigation
    func openInAppleMaps(cinema: CinemaLocation) {
        #if os(tvOS)
        _ = cinema
        return
        #else
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: cinema.coordinate))
        destination.name = cinema.mapSearchName
        destination.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
        #endif
    }

    func openWebsite(for cinema: CinemaLocation) {
        guard let url = cinema.websiteURL else { return }
        safariURL = url
        showSafari = true
    }

    func focusCinema(_ cinema: CinemaLocation) {
        clearRoute()
        withAnimation(.easeInOut(duration: 0.5)) {
            selectedCinema = cinema
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: cinema.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
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
    #if !os(tvOS)
    @State private var showTripPlanner = false
    #endif

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

                // Cinema pins — use resolver's live-updated list
                ForEach(viewModel.allCinemas) { cinema in
                    Annotation(cinema.name, coordinate: cinema.coordinate, anchor: .bottom) {
                        CinemaMapPin(
                            isSelected: viewModel.selectedCinema?.id == cinema.id,
                            isNearest: viewModel.nearest?.cinema.id == cinema.id,
                            hasIMAX: cinema.hasIMAX
                        )
                        .onTapGesture {
                            viewModel.focusCinema(cinema)
                        }
                    }
                    .tag(cinema.id)
                }

                // Driving route overlay
                if let route = viewModel.activeRoute {
                    MapPolyline(route.polyline)
                        .stroke(.blue, lineWidth: 5)
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
                // Route info banner when showing directions
                if let routeCinema = viewModel.showingRouteForCinema, let route = viewModel.activeRoute {
                    RouteInfoBanner(
                        cinema: routeCinema,
                        route: route,
                        onOpenMaps: { viewModel.openInAppleMaps(cinema: routeCinema) },
                        onDismiss: { viewModel.clearRoute() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
                }

                if let selected = viewModel.selectedCinema, viewModel.showingRouteForCinema == nil {
                    // Selected cinema detail card
                    CinemaDetailCard(
                        cinema: selected,
                        routeInfo: viewModel.routeInfo(for: selected),
                        onShowtimes: { viewModel.openWebsite(for: selected) },
                        onDirections: { viewModel.showRoute(to: selected) },
                        onOpenMaps: { viewModel.openInAppleMaps(cinema: selected) },
                        onPlanTrip: {
                            #if !os(tvOS)
                            showTripPlanner = true
                            #endif
                        },
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewModel.selectedCinema = nil
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if viewModel.showingRouteForCinema == nil {
                    if let nearest = viewModel.nearest {
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
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.selectedCinema?.id)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.nearest?.cinema.id)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.showingRouteForCinema?.id)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle("Box Office")
        #if !os(macOS) && !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if !os(tvOS)
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: CinemaTripPlannerView()) {
                    Image(systemName: "car.circle.fill")
                        .font(.title3)
                }
            }
            #endif
        }
        .task {
            // First resolve accurate locations from Apple Maps, then request user location
            await viewModel.resolveLocations()
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
        #if !os(tvOS)
        .sheet(isPresented: $showTripPlanner) {
            NavigationStack {
                CinemaTripPlannerView()
            }
        }
        #endif
    }
}

// MARK: - Map Pin

private struct CinemaMapPin: View {
    let isSelected: Bool
    let isNearest: Bool
    let hasIMAX: Bool

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
        .overlay(alignment: .topTrailing) {
            if hasIMAX {
                Text("IMAX")
                    .font(.system(size: 5, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.blue))
                    .offset(x: 6, y: -4)
            }
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
                        HStack(spacing: 6) {
                            Text(info.cinema.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            if info.cinema.hasIMAX {
                                Text("IMAX")
                                    .font(.system(size: 7, weight: .heavy))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.blue))
                            }
                        }
                        HStack(spacing: 6) {
                            if let drivingDist = info.drivingDistanceText {
                                Text(drivingDist)
                            } else {
                                Text(info.distanceText)
                            }
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
    let onOpenMaps: () -> Void
    let onPlanTrip: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // Header with dismiss
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(cinema.name)
                            .font(.headline)
                        if cinema.hasIMAX {
                            Text("IMAX")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue))
                        }
                    }
                    Text("\(cinema.suburb), \(cinema.city)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let info = routeInfo {
                        HStack(spacing: 6) {
                            Image(systemName: "car.fill")
                                .font(.caption2)
                            if let drivingDist = info.drivingDistanceText {
                                Text(drivingDist)
                            } else {
                                Text(info.distanceText)
                            }
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

            // Action buttons row 1
            HStack(spacing: 10) {
                Button(action: onShowtimes) {
                    HStack(spacing: 6) {
                        Image(systemName: "ticket.fill")
                        Text("Showtimes")
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
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                        Text("Route")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.gray.opacity(0.18))
                    )
                }

                #if !os(tvOS)
                Button(action: onOpenMaps) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.gray.opacity(0.18))
                        )
                }
                #endif
            }

            #if !os(tvOS)
            Button(action: onPlanTrip) {
                HStack(spacing: 6) {
                    Image(systemName: "car.circle.fill")
                    Text("Plan Trip")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.green.opacity(0.12))
                )
            }
            #endif
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        )
    }
}

// MARK: - Route Info Banner

private struct RouteInfoBanner: View {
    let cinema: CinemaLocation
    let route: MKRoute
    let onOpenMaps: () -> Void
    let onDismiss: () -> Void

    private var drivingDistance: String {
        let km = route.distance / 1_000
        return String(format: "%.1f km", km)
    }

    private var etaText: String {
        let minutes = Int((route.expectedTravelTime / 60).rounded())
        if minutes < 60 { return "\(minutes) min drive" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr drive" : "\(hours)h \(remainder)m drive"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Directions to \(cinema.name)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    HStack(spacing: 8) {
                        Label(drivingDistance, systemImage: "car.fill")
                        Text("·")
                        Text(etaText)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            #if !os(tvOS)
            Button(action: onOpenMaps) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    Text("Open in Apple Maps")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.blue)
                )
            }
            #endif
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
            #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
