//
//  WatchGuide_MovieandTVtrackerApp.swift
//  WatchGuide-MovieandTVtracker
//
//  Created by Neel Makhecha on 9/5/25.
//

import SwiftUI

@main
struct WatchGuide_MovieandTVtrackerApp: App {
    @StateObject private var scoutSubscription = ScoutSubscriptionService.shared
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .task {
                    await scoutSubscription.prepare()
                }
        }
    }
}
