import Foundation
import CoreLocation
import MapKit
import UserNotifications

// MARK: - Cinema Trip Model

struct CinemaTrip: Identifiable, Codable, Equatable {
    let id: String
    let movieTitle: String
    let cinemaId: String
    let cinemaName: String
    let showtimeDate: Date          // The date & time the movie starts
    let prepMinutes: Int            // Extra prep time (popcorn, parking, etc.)
    var estimatedTravelSeconds: TimeInterval?
    var estimatedDistanceMeters: Double?
    var leaveByDate: Date?          // Computed: showtime - travel - prep
    var notificationScheduled: Bool
    let createdAt: Date

    init(
        movieTitle: String,
        cinemaId: String,
        cinemaName: String,
        showtimeDate: Date,
        prepMinutes: Int = 15
    ) {
        self.id = UUID().uuidString
        self.movieTitle = movieTitle
        self.cinemaId = cinemaId
        self.cinemaName = cinemaName
        self.showtimeDate = showtimeDate
        self.prepMinutes = prepMinutes
        self.estimatedTravelSeconds = nil
        self.estimatedDistanceMeters = nil
        self.leaveByDate = nil
        self.notificationScheduled = false
        self.createdAt = Date()
    }

    var isPast: Bool {
        showtimeDate < Date()
    }

    var travelTimeText: String {
        guard let secs = estimatedTravelSeconds else { return "Calculating..." }
        let minutes = Int((secs / 60).rounded())
        if minutes < 60 { return "\(minutes) min drive" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr drive" : "\(hours)h \(remainder)m drive"
    }

    var distanceText: String {
        guard let meters = estimatedDistanceMeters else { return "" }
        let km = meters / 1_000
        return String(format: "%.1f km", km)
    }

    var leaveByText: String {
        guard let leave = leaveByDate else { return "—" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: leave)
    }

    var showtimeDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM"
        return formatter.string(from: showtimeDate)
    }

    var showtimeTimeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: showtimeDate)
    }

    static func == (lhs: CinemaTrip, rhs: CinemaTrip) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Trip Planner Service

@MainActor
final class CinemaTripPlannerService: ObservableObject {
    static let shared = CinemaTripPlannerService()
    
    @Published var trips: [CinemaTrip] = []
    
    private let storageKey = "cinema_trips_v1"
    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {
        loadTrips()
    }

    // MARK: - CRUD

    func addTrip(_ trip: CinemaTrip) {
        trips.append(trip)
        saveTrips()
    }

    func removeTrip(id: String) {
        // Remove notification
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [
            "cinema_leave_\(id)",
            "cinema_reminder_\(id)"
        ])
        trips.removeAll { $0.id == id }
        saveTrips()
    }

    func updateTrip(_ trip: CinemaTrip) {
        if let idx = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[idx] = trip
            saveTrips()
        }
    }

    var upcomingTrips: [CinemaTrip] {
        trips.filter { !$0.isPast }.sorted { $0.showtimeDate < $1.showtimeDate }
    }

    var pastTrips: [CinemaTrip] {
        trips.filter { $0.isPast }.sorted { $0.showtimeDate > $1.showtimeDate }
    }

    // MARK: - Route Calculation
    
    struct ScoutLeaveCalculation {
        let travelSeconds: TimeInterval
        let distanceMeters: Double
        let leaveByDate: Date
    }
    
    /// Scout-backed leave-time calculation using live Apple Maps routing.
    func scoutCalculateLeaveTime(
        showtimeDate: Date,
        prepMinutes: Int,
        from userLocation: CLLocationCoordinate2D,
        to cinemaCoordinate: CLLocationCoordinate2D
    ) async -> ScoutLeaveCalculation? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: cinemaCoordinate))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        request.departureDate = Date()
        
        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else { return nil }
            let travelSeconds = route.expectedTravelTime
            let totalLeadSeconds = travelSeconds + Double(prepMinutes * 60)
            let leaveByDate = showtimeDate.addingTimeInterval(-totalLeadSeconds)
            return ScoutLeaveCalculation(
                travelSeconds: travelSeconds,
                distanceMeters: route.distance,
                leaveByDate: leaveByDate
            )
        } catch {
            print("Scout leave-time calculation error: \(error)")
            return nil
        }
    }

    /// Calculates driving ETA from user's current location to the cinema and updates the trip.
    func calculateRoute(for tripId: String, from userLocation: CLLocationCoordinate2D, to cinemaCoordinate: CLLocationCoordinate2D) async {
        guard let existingTrip = trips.first(where: { $0.id == tripId }) else { return }
        guard let calculation = await scoutCalculateLeaveTime(
            showtimeDate: existingTrip.showtimeDate,
            prepMinutes: existingTrip.prepMinutes,
            from: userLocation,
            to: cinemaCoordinate
        ) else { return }
        
        var trip = existingTrip
        trip.estimatedTravelSeconds = calculation.travelSeconds
        trip.estimatedDistanceMeters = calculation.distanceMeters
        trip.leaveByDate = calculation.leaveByDate
        updateTrip(trip)
        await scheduleLeaveNotification(for: trip)
    }

    // MARK: - Notifications

    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    func scheduleLeaveNotification(for trip: CinemaTrip) async {
        guard let leaveBy = trip.leaveByDate, leaveBy > Date() else { return }

        let granted = await requestNotificationPermission()
        guard granted else { return }

        // Remove existing notifications for this trip
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [
            "cinema_leave_\(trip.id)",
            "cinema_reminder_\(trip.id)"
        ])

        // "Leave now" notification at the exact leave-by time
        let leaveContent = UNMutableNotificationContent()
        leaveContent.title = "Time to leave!"
        leaveContent.body = "Head out now for \(trip.movieTitle) at \(trip.cinemaName). Your movie starts at \(trip.showtimeTimeText)."
        leaveContent.sound = .default
        leaveContent.categoryIdentifier = "CINEMA_TRIP"

        let leaveComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: leaveBy)
        let leaveTrigger = UNCalendarNotificationTrigger(dateMatching: leaveComponents, repeats: false)
        let leaveRequest = UNNotificationRequest(
            identifier: "cinema_leave_\(trip.id)",
            content: leaveContent,
            trigger: leaveTrigger
        )

        // 15 min heads-up reminder before leave time
        let reminderDate = leaveBy.addingTimeInterval(-15 * 60)
        if reminderDate > Date() {
            let reminderContent = UNMutableNotificationContent()
            reminderContent.title = "Get ready"
            reminderContent.body = "You should leave in about 15 minutes for \(trip.movieTitle) at \(trip.cinemaName)."
            reminderContent.sound = .default
            reminderContent.categoryIdentifier = "CINEMA_TRIP"

            let reminderComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
            let reminderTrigger = UNCalendarNotificationTrigger(dateMatching: reminderComponents, repeats: false)
            let reminderRequest = UNNotificationRequest(
                identifier: "cinema_reminder_\(trip.id)",
                content: reminderContent,
                trigger: reminderTrigger
            )
            try? await notificationCenter.add(reminderRequest)
        }

        try? await notificationCenter.add(leaveRequest)

        // Mark as scheduled
        if var updated = trips.first(where: { $0.id == trip.id }) {
            updated.notificationScheduled = true
            updateTrip(updated)
        }
    }

    // MARK: - Persistence

    private func saveTrips() {
        if let data = try? JSONEncoder().encode(trips) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadTrips() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([CinemaTrip].self, from: data) else {
            return
        }
        trips = loaded
    }

    /// Cleans up trips older than 7 days
    func cleanupOldTrips() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        trips.removeAll { $0.showtimeDate < cutoff }
        saveTrips()
    }
}
