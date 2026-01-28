//
//  WatchGuide_MovieandTVtrackerApp.swift
//  WatchGuide-MovieandTVtracker
//
//  Created by Neel Makhecha on 9/5/25.
//

import SwiftUI

@main
struct WatchGuide_MovieandTVtrackerApp: App {
    @State private var showMDBListAuthSuccess = false
    @State private var mdbListAuthError: String?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .alert("MDBList Connected", isPresented: $showMDBListAuthSuccess) {
                    Button("OK") { }
                } message: {
                    Text("Your MDBList account has been connected successfully!")
                }
                .alert("MDBList Error", isPresented: .init(
                    get: { mdbListAuthError != nil },
                    set: { if !$0 { mdbListAuthError = nil } }
                )) {
                    Button("OK") { mdbListAuthError = nil }
                } message: {
                    Text(mdbListAuthError ?? "")
                }
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "watchguide" else { return }
        
        // Handle MDBList OAuth callback
        if url.host == "mdblist" && url.path == "/callback" {
            handleMDBListCallback(url)
        }
    }
    
    private func handleMDBListCallback(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            mdbListAuthError = "Invalid callback URL"
            return
        }
        
        // Check for error
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            mdbListAuthError = "Authorization failed: \(error)"
            return
        }
        
        // Extract authorization code
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            mdbListAuthError = "No authorization code received"
            return
        }
        
        // Exchange code for token
        Task {
            do {
                try await MDBListService.shared.exchangeCodeForToken(code: code)
                await MainActor.run {
                    showMDBListAuthSuccess = true
                }
            } catch {
                await MainActor.run {
                    mdbListAuthError = "Failed to complete authentication: \(error.localizedDescription)"
                }
            }
        }
    }
}
