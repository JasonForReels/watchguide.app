//
//  WatchGuideQuickRouteCenter.swift
//  WatchGuide-MovieandTVtracker
//
//  Where a Control Center control lands when it opens the app.
//
//  Controls can't render a result of their own — a `ControlWidgetButton` runs an
//  intent and that's it — so each control opens the app at a `watchguide://`
//  destination instead. The deep link handler parks the destination here and the
//  views that own the relevant UI pick it up: `ContentView` for anything that is
//  a tab or the Atlas dock, `SearchView` for the scanner sheet it owns privately.
//
//  Single-slot rather than a queue: a control tap is the user saying "go here
//  now", so a second tap should replace a destination that hasn't been consumed,
//  not stack behind it.
//

import Foundation
import Combine

@MainActor
final class WatchGuideQuickRouteCenter: ObservableObject {
    static let shared = WatchGuideQuickRouteCenter()

    enum Destination: String {
        /// Atlas, the in-app assistant.
        case atlas
        /// A pick for tonight: the Tonight tab on iPhone, Atlas elsewhere.
        case tonight
        /// The Search tab.
        case search
        /// The watchlist.
        case watchlist
        /// The in-app visual scanner, which lives inside `SearchView`.
        case scanner
    }

    /// Carries an id so a repeat of the same destination still fires: `onChange`
    /// on the destination alone would ignore tapping the same control twice.
    struct Route: Equatable {
        let id = UUID()
        let destination: Destination
    }

    @Published var pending: Route?

    private init() {}

    func open(_ destination: Destination) {
        pending = Route(destination: destination)
    }

    /// Clears the slot once a view has acted on it.
    func consume() {
        pending = nil
    }
}
