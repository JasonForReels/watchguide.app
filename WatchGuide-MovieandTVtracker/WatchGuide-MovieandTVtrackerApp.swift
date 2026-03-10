//
//  WatchGuide_MovieandTVtrackerApp.swift
//  WatchGuide-MovieandTVtracker
//
//  Created by Neel Makhecha on 9/5/25.
//

import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif

@main
struct WatchGuide_MovieandTVtrackerApp: App {
    @StateObject private var scoutSubscription = ScoutSubscriptionService.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .task {
                    await scoutSubscription.prepare()
                    registerAppShortcutsIfAvailable()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await scoutSubscription.prepare()
                        registerAppShortcutsIfAvailable()
                    }
                }
        }
    }

    private func registerAppShortcutsIfAvailable() {
        guard PlatformCompatibility.supportsVisualIntelligence else { return }
#if canImport(AppIntents) && os(iOS) && !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
        // Keep app launch resilient if AppShortcuts provider source is not compiled into this target.
        // Visual intelligence features continue to work without this registration call.
        if #available(iOS 18.0, *) {}
#endif
    }
}
