import SwiftUI
import CoreLocation
import MapKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Trip Planner View (Plan a Cinema Trip)

struct CinemaTripPlannerView: View {
    @StateObject private var plannerService = CinemaTripPlannerService.shared
    @State private var showNewTripSheet = false

    var body: some View {
        List {
            if !plannerService.upcomingTrips.isEmpty {
                Section {
                    ForEach(plannerService.upcomingTrips) { trip in
                        CinemaTripCard(trip: trip)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                    .onDelete { offsets in
                        let upcoming = plannerService.upcomingTrips
                        for offset in offsets {
                            plannerService.removeTrip(id: upcoming[offset].id)
                        }
                    }
                } header: {
                    Text("Upcoming")
                }
            }

            if !plannerService.pastTrips.isEmpty {
                Section {
                    ForEach(plannerService.pastTrips.prefix(5)) { trip in
                        CinemaTripCard(trip: trip, isPast: true)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                    .onDelete { offsets in
                        let past = Array(plannerService.pastTrips.prefix(5))
                        for offset in offsets {
                            plannerService.removeTrip(id: past[offset].id)
                        }
                    }
                } header: {
                    Text("Past")
                }
            }

            if plannerService.trips.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "car.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.accentColor.opacity(0.5))
                        Text("No trips planned yet")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Plan a cinema trip and Watch Guide will tell you exactly when to leave, with real-time ETA and reminders.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowSeparator(.hidden)
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle("Trip Planner")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewTripSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showNewTripSheet) {
            NewCinemaTripSheet()
        }
        .onAppear {
            plannerService.cleanupOldTrips()
        }
    }
}

// MARK: - Trip Card

private struct CinemaTripCard: View {
    let trip: CinemaTrip
    var isPast: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Movie + Cinema
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isPast ? Color.gray.opacity(0.18) : Color.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: isPast ? "checkmark.circle.fill" : "film.fill")
                        .font(.title3)
                        .foregroundColor(isPast ? .secondary : .accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.movieTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    Text(trip.cinemaName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Date badge
                VStack(spacing: 2) {
                    Text(trip.showtimeDateText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(trip.showtimeTimeText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                }
            }

            if !isPast {
                Divider()

                // ETA Row
                HStack(spacing: 16) {
                    // Travel time
                    HStack(spacing: 6) {
                        Image(systemName: "car.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text(trip.travelTimeText)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }

                    if !trip.distanceText.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(trip.distanceText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Leave-by banner
                if let leaveBy = trip.leaveByDate {
                    HStack(spacing: 8) {
                        Image(systemName: leaveBy > Date() ? "bell.badge.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(leaveBy > Date() ? .green : .orange)

                        if leaveBy > Date() {
                            Text("Leave by **\(trip.leaveByText)**")
                                .font(.caption)
                                .foregroundColor(.primary)

                            Spacer()

                            Text(timeUntilLeave(leaveBy))
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.green.opacity(0.12))
                                )
                        } else {
                            Text("You should have left already!")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Spacer()
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.gray.opacity(0.12))
                    )
                }

                // Prep time info
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Includes \(trip.prepMinutes) min for parking, popcorn & settling in")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.gray.opacity(0.08))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.gray.opacity(0.18), lineWidth: 0.5)
        )
        .opacity(isPast ? 0.7 : 1.0)
    }

    private func timeUntilLeave(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        let totalMinutes = Int(interval / 60)
        if totalMinutes < 60 {
            return "in \(max(1, totalMinutes)) min"
        }
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if mins == 0 { return "in \(hours)h" }
        return "in \(hours)h \(mins)m"
    }
}

// MARK: - New Trip Sheet

private struct NewCinemaTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationVM = TripLocationViewModel()
    @StateObject private var plannerService = CinemaTripPlannerService.shared

    @State private var movieTitle = ""
    @State private var selectedCinema: CinemaLocation?
    @State private var selectedDate = Date()
    @State private var selectedTime = Date()
    @State private var prepMinutes = 15
    @State private var showCinemaPicker = false
    @State private var isSaving = false
    @State private var isScoutCalculating = false
    @State private var scoutResultText: String?
    @State private var scoutTravelSeconds: TimeInterval?
    @State private var scoutDistanceMeters: Double?
    @State private var scoutLeaveByDate: Date?
    @State private var scoutErrorText: String?
    @State private var showLocationPermissionAlert = false

    private let prepOptions = [10, 15, 20, 25, 30]

    private var isFormValid: Bool {
        !movieTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCinema != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "film.fill")
                            .foregroundColor(.accentColor)
                            .frame(width: 24)
                        TextField("Movie title", text: $movieTitle)
                    }
                } header: {
                    Text("Movie")
                }

                Section {
                    Button {
                        showCinemaPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.red)
                                .frame(width: 24)
                            if let cinema = selectedCinema {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cinema.name)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Text("\(cinema.suburb), \(cinema.city)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Select cinema")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Cinema")
                }

                Section {
                    DatePicker("Date", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                    DatePicker("Showtime", selection: $selectedTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Date & Time")
                }

                Section {
                    Picker("Buffer time", selection: $prepMinutes) {
                        ForEach(prepOptions, id: \.self) { mins in
                            Text("\(mins) minutes").tag(mins)
                        }
                    }
                } header: {
                    Text("Prep Time")
                } footer: {
                    Text("Extra time for parking, buying popcorn, finding your seat, and settling in before the movie starts.")
                }
                
                Section {
                    Button {
                        Task { await runScoutLeaveCalculation() }
                    } label: {
                        HStack(spacing: 10) {
                            if isScoutCalculating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.accentColor)
                            }
                            Text(isScoutCalculating ? "Scout is calculating..." : "Calculate Leave Time with Scout")
                        }
                    }
                    .disabled(!isFormValid || isScoutCalculating || isSaving)
                    
                    if let scoutResultText {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                                .padding(.top, 2)
                            Text(scoutResultText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let scoutErrorText {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                                .padding(.top, 2)
                            Text(scoutErrorText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Scout")
                } footer: {
                    Text("Scout uses live Maps traffic to estimate drive time and tell you when to leave.")
                }
            }
            .navigationTitle("Plan Trip")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTrip()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isFormValid || isSaving)
                }
            }
            .sheet(isPresented: $showCinemaPicker) {
                CinemaPickerSheet(selectedCinema: $selectedCinema)
            }
            .onChange(of: selectedCinema?.id) { _, _ in clearScoutResult() }
            .onChange(of: selectedDate) { _, _ in clearScoutResult() }
            .onChange(of: selectedTime) { _, _ in clearScoutResult() }
            .onChange(of: prepMinutes) { _, _ in clearScoutResult() }
            .alert("Location Access Needed", isPresented: $showLocationPermissionAlert) {
                Button("Not Now", role: .cancel) {}
                #if canImport(UIKit)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                #endif
            } message: {
                Text("Scout needs your location to calculate when you should leave. Please allow location access for Watch Guide.")
            }
        }
    }

    private func saveTrip() {
        guard let cinema = selectedCinema else { return }
        guard AIMessageQuota.canCreateTripPlanThisMonth() else {
            scoutErrorText = "Free plan allows 1 new trip plan per month. Upgrade to Scout Unlimited for unlimited trip planning."
            return
        }
        isSaving = true

        let showtimeDate = combinedShowtimeDate

        var trip = CinemaTrip(
            movieTitle: movieTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            cinemaId: cinema.id,
            cinemaName: cinema.name,
            showtimeDate: showtimeDate,
            prepMinutes: prepMinutes
        )
        
        if let scoutTravelSeconds, let scoutDistanceMeters, let scoutLeaveByDate {
            trip.estimatedTravelSeconds = scoutTravelSeconds
            trip.estimatedDistanceMeters = scoutDistanceMeters
            trip.leaveByDate = scoutLeaveByDate
        }

        plannerService.addTrip(trip)
        AIMessageQuota.consumeTripPlan()

        // If Scout already calculated, just schedule notifications; otherwise calculate in background.
        if trip.leaveByDate != nil {
            Task { await plannerService.scheduleLeaveNotification(for: trip) }
        } else {
            Task {
                locationVM.requestLocation()
                // Wait briefly for location
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if let userLoc = locationVM.currentLocation {
                    await plannerService.calculateRoute(
                        for: trip.id,
                        from: userLoc,
                        to: cinema.coordinate
                    )
                }
            }
        }

        dismiss()
    }
    
    private var combinedShowtimeDate: Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        return calendar.date(from: combined) ?? selectedDate
    }
    
    private func clearScoutResult() {
        scoutResultText = nil
        scoutTravelSeconds = nil
        scoutDistanceMeters = nil
        scoutLeaveByDate = nil
        scoutErrorText = nil
    }
    
    private func runScoutLeaveCalculation() async {
        guard let cinema = selectedCinema else { return }
        isScoutCalculating = true
        scoutErrorText = nil
        scoutResultText = nil
        
        defer { isScoutCalculating = false }
        
        locationVM.requestLocation()
        guard let userLocation = await waitForCurrentLocation(timeoutSeconds: 30) else {
            if locationVM.authorizationStatus == .denied || locationVM.authorizationStatus == .restricted {
                showLocationPermissionAlert = true
            }
            scoutErrorText = "Scout couldn't get your location. Enable location access and try again."
            return
        }
        
        guard let result = await plannerService.scoutCalculateLeaveTime(
            showtimeDate: combinedShowtimeDate,
            prepMinutes: prepMinutes,
            from: userLocation,
            to: cinema.coordinate
        ) else {
            scoutErrorText = "Scout couldn't calculate this route right now. Please try again."
            return
        }
        
        scoutTravelSeconds = result.travelSeconds
        scoutDistanceMeters = result.distanceMeters
        scoutLeaveByDate = result.leaveByDate
        
        let minutes = Int((result.travelSeconds / 60).rounded())
        let km = result.distanceMeters / 1_000
        scoutResultText = "Scout says leave by \(formattedTime(result.leaveByDate)) (\(minutes) min drive, \(String(format: "%.1f", km)) km + \(prepMinutes) min prep)."
    }
    
    private func waitForCurrentLocation(timeoutSeconds: Int) async -> CLLocationCoordinate2D? {
        for _ in 0..<(timeoutSeconds * 5) {
            if let location = locationVM.currentLocation {
                return location
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return locationVM.currentLocation
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Cinema Picker Sheet

private struct CinemaPickerSheet: View {
    @Binding var selectedCinema: CinemaLocation?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let cinemas = SouthAfricaCinemaDirectory.sterKinekor

    private var filteredCinemas: [CinemaLocation] {
        if searchText.isEmpty { return cinemas }
        let query = searchText.lowercased()
        return cinemas.filter {
            $0.name.lowercased().contains(query) ||
            $0.suburb.lowercased().contains(query) ||
            $0.city.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredCinemas) { cinema in
                    Button {
                        selectedCinema = cinema
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "film.fill")
                                .foregroundColor(selectedCinema?.id == cinema.id ? .accentColor : .secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(cinema.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    if cinema.hasIMAX {
                                        Text("IMAX")
                                            .font(.system(size: 7, weight: .heavy))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1.5)
                                            .background(Capsule().fill(Color.blue))
                                    }
                                }
                                Text("\(cinema.suburb), \(cinema.city)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if selectedCinema?.id == cinema.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Search cinemas")
            .navigationTitle("Select Cinema")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Trip Location Helper

@MainActor
private final class TripLocationViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        let status = manager.authorizationStatus
        authorizationStatus = status
        if isAuthorized(status) {
            manager.requestLocation()
        } else if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized(authorizationStatus) {
            manager.requestLocation()
        }
    }

    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(macOS)
        return status == .authorized || status == .authorizedAlways
        #else
        return status == .authorizedWhenInUse || status == .authorizedAlways
        #endif
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("TripLocation error: \(error)")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CinemaTripPlannerView()
    }
}
