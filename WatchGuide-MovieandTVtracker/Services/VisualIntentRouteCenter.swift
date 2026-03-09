import Foundation

enum VisualIntentAction: String, Codable {
    case openDetails
    case openTrailer
    case addToWatchlist
}

struct VisualIntentRoute: Codable {
    let mediaId: Int
    let mediaType: MediaType
    let action: VisualIntentAction
}

actor VisualIntentRouteCenter {
    static let shared = VisualIntentRouteCenter()

    private let routeKey = "watchguide_visual_intent_route"

    func queue(_ route: VisualIntentRoute) {
        guard let data = try? JSONEncoder().encode(route) else { return }
        UserDefaults.standard.set(data, forKey: routeKey)
    }

    func consume() -> VisualIntentRoute? {
        guard let data = UserDefaults.standard.data(forKey: routeKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: routeKey)
        return try? JSONDecoder().decode(VisualIntentRoute.self, from: data)
    }
}
