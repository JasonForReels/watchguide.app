//
//  AuthService.swift
//  WatchGuide-MovieandTVtracker
//
//  User authentication service supporting Supabase Auth and local Sign in with Apple (iCloud)
//

import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import Security

// MARK: - Auth Backend

/// Which authentication backend is in use
enum AuthBackend: String, Codable {
    case supabase = "supabase"
    case icloud = "icloud"
}

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()
    
    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var authBackend: AuthBackend = .supabase
    
    private var supabaseURL: String {
        ApiKeyManager.shared.get(key: "SUPABASE_URL") ?? ""
    }
    
    private var supabaseAnonKey: String {
        ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY") ?? ""
    }
    
    private let sessionKey = "supabase_session"
    private let icloudSessionKey = "icloud_auth_session"
    private let backendKey = "auth_backend"
    
    var isConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
    
    /// Whether Supabase is available for auth
    var isSupabaseAvailable: Bool {
        isConfigured
    }
    
    /// Whether the current session uses iCloud (local Sign in with Apple)
    var isICloudSession: Bool {
        authBackend == .icloud
    }
    
    // Current access token for authenticated requests
    var accessToken: String? {
        currentUser?.accessToken
    }
    
    // User ID for database queries (replaces device_id when logged in)
    var userId: String? {
        currentUser?.id
    }
    
    private init() {
        // Load stored backend preference
        if let raw = UserDefaults.standard.string(forKey: backendKey),
           let backend = AuthBackend(rawValue: raw) {
            authBackend = backend
        }
        loadSession()
    }
    
    // MARK: - Session Management
    
    private func loadSession() {
        // Try iCloud session first
        if authBackend == .icloud {
            loadICloudSession()
            if isAuthenticated { return }
        }
        
        // Fall back to Supabase session
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            // Also try iCloud if backend wasn't explicitly set
            loadICloudSession()
            return
        }
        
        // Check if session is expired
        if session.expiresAt > Date() {
            self.currentUser = session.user
            self.currentUser?.accessToken = session.accessToken
            self.isAuthenticated = true
            self.authBackend = .supabase
        } else {
            // Try to refresh the session
            Task {
                await refreshSession(refreshToken: session.refreshToken)
            }
        }
    }
    
    private func loadICloudSession() {
        guard let data = UserDefaults.standard.data(forKey: icloudSessionKey),
              let user = try? JSONDecoder().decode(AuthUser.self, from: data) else {
            return
        }
        self.currentUser = user
        self.isAuthenticated = true
        self.authBackend = .icloud
    }
    
    private func saveSession(_ session: AuthSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
        authBackend = .supabase
        UserDefaults.standard.set(authBackend.rawValue, forKey: backendKey)
    }
    
    private func saveICloudSession(_ user: AuthUser) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: icloudSessionKey)
        }
        authBackend = .icloud
        UserDefaults.standard.set(authBackend.rawValue, forKey: backendKey)
    }
    
    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
        UserDefaults.standard.removeObject(forKey: icloudSessionKey)
        UserDefaults.standard.removeObject(forKey: backendKey)
        currentUser = nil
        isAuthenticated = false
        authBackend = .supabase
    }
    
    // MARK: - Sign Up
    
    func signUp(email: String, password: String) async -> Bool {
        guard isConfigured else {
            errorMessage = "Supabase not configured. Please link a Supabase project first."
            return false
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "\(supabaseURL)/auth/v1/signup")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let body: [String: Any] = [
                "email": email,
                "password": password
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
                
                if let session = authResponse.toSession() {
                    saveSession(session)
                    currentUser = session.user
                    currentUser?.accessToken = session.accessToken
                    isAuthenticated = true
                    isLoading = false
                    return true
                } else {
                    // Email confirmation required
                    errorMessage = "Please check your email to confirm your account."
                    isLoading = false
                    return false
                }
            } else {
                let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
                errorMessage = errorResponse?.message ?? errorResponse?.msg ?? "Sign up failed"
                isLoading = false
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    // MARK: - Sign In
    
    func signIn(email: String, password: String) async -> Bool {
        guard isConfigured else {
            errorMessage = "Supabase not configured. Please link a Supabase project first."
            return false
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let body: [String: Any] = [
                "email": email,
                "password": password
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
                
                if let session = authResponse.toSession() {
                    saveSession(session)
                    currentUser = session.user
                    currentUser?.accessToken = session.accessToken
                    isAuthenticated = true
                    isLoading = false
                    return true
                }
                throw AuthError.noSession
            } else {
                let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
                errorMessage = errorResponse?.message ?? errorResponse?.msg ?? "Invalid email or password"
                isLoading = false
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    // MARK: - Sign In with Apple

    func signInWithApple(idToken: String, nonce: String?) async -> Bool {
        guard isConfigured else {
            errorMessage = "Supabase not configured. Please link a Supabase project first."
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=id_token")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

            var body: [String: Any] = [
                "provider": "apple",
                "id_token": idToken
            ]
            if let nonce = nonce {
                body["nonce"] = nonce
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            if (200...299).contains(httpResponse.statusCode) {
                let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)

                if let session = authResponse.toSession() {
                    saveSession(session)
                    currentUser = session.user
                    currentUser?.accessToken = session.accessToken
                    isAuthenticated = true
                    isLoading = false
                    return true
                }
                throw AuthError.noSession
            } else {
                let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
                errorMessage = errorResponse?.message ?? errorResponse?.msg ?? "Sign in with Apple failed"
                isLoading = false
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if status != errSecSuccess { return 0 }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Local Sign in with Apple (iCloud backend)
    
    /// Sign in with Apple using local auth only (for iCloud/CloudKit sync, no Supabase required)
    func signInWithAppleLocal(userIdentifier: String, fullName: PersonNameComponents?, email: String?) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        // Build a local user from Apple ID credentials
        let displayEmail = email ?? "\(userIdentifier.prefix(8))@apple.id"
        
        let user = AuthUser(
            id: userIdentifier,
            email: displayEmail,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        
        // Persist full name if provided (Apple only sends it on first sign-in)
        if let givenName = fullName?.givenName {
            UserDefaults.standard.set(givenName, forKey: "apple_user_given_name")
        }
        if let familyName = fullName?.familyName {
            UserDefaults.standard.set(familyName, forKey: "apple_user_family_name")
        }
        
        saveICloudSession(user)
        currentUser = user
        isAuthenticated = true
        authBackend = .icloud
        isLoading = false
        return true
    }
    
    // MARK: - Sign Out
    
    func signOut() async {
        let wasICloud = authBackend == .icloud
        
        if !wasICloud {
            guard isConfigured, let token = accessToken else {
                clearSession()
                resetProfileState()
                return
            }
            
            isLoading = true
            
            do {
                let url = URL(string: "\(supabaseURL)/auth/v1/logout")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                _ = try? await URLSession.shared.data(for: request)
            }
        } else {
            isLoading = true
        }
        
        clearSession()
        resetProfileState()
        
        // Reset kids profile setting when signing out
        var settings = StorageService.shared.settings
        settings.isKidsProfile = false
        StorageService.shared.updateSettings(settings)
        
        isLoading = false
    }
    
    private func resetProfileState() {
        ProfileService.shared.activeProfile = nil
        ProfileService.shared.needsProfileSelection = false
        ProfileService.shared.resetSessionFlag()
    }
    
    // MARK: - Refresh Session
    
    private func refreshSession(refreshToken: String) async {
        guard isConfigured else { return }
        
        do {
            let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=refresh_token")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let body: [String: Any] = [
                "refresh_token": refreshToken
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                clearSession()
                return
            }
            
            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            
            if let session = authResponse.toSession() {
                saveSession(session)
                currentUser = session.user
                currentUser?.accessToken = session.accessToken
                isAuthenticated = true
            } else {
                clearSession()
            }
        } catch {
            clearSession()
        }
    }
    
    // MARK: - Delete Account
    
    /// Deletes the user's cloud data, clears local data, and signs out.
    func deleteAccount() async -> Bool {
        guard let userId = currentUser?.id else {
            errorMessage = "Not signed in."
            return false
        }
        
        isLoading = true
        errorMessage = nil
        
        if authBackend == .icloud {
            // iCloud backend: just clear local data and session
            await MainActor.run {
                StorageService.shared.clearAllData()
            }
            clearSession()
            isLoading = false
            return true
        }
        
        // Supabase backend
        guard isConfigured, let token = accessToken else {
            errorMessage = "Supabase not configured."
            isLoading = false
            return false
        }
        
        do {
            // Step 1: Delete all user data from cloud (media_items table)
            let deleteURL = URL(string: "\(supabaseURL)/rest/v1/media_items?device_id=eq.\(userId)")!
            var deleteRequest = URLRequest(url: deleteURL)
            deleteRequest.httpMethod = "DELETE"
            deleteRequest.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            deleteRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            deleteRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
            _ = try? await URLSession.shared.data(for: deleteRequest)
            
            // Step 2: Clear all local data
            await MainActor.run {
                StorageService.shared.clearAllData()
            }
            
            // Step 3: Sign out from Supabase Auth
            let logoutURL = URL(string: "\(supabaseURL)/auth/v1/logout")!
            var logoutRequest = URLRequest(url: logoutURL)
            logoutRequest.httpMethod = "POST"
            logoutRequest.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            logoutRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: logoutRequest)
            
            // Step 4: Clear local session
            clearSession()
            
            isLoading = false
            return true
        }
    }
    
    // MARK: - Password Reset
    
    func sendPasswordReset(email: String) async -> Bool {
        guard isConfigured else {
            errorMessage = "Supabase not configured."
            return false
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "\(supabaseURL)/auth/v1/recover")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let body: [String: Any] = [
                "email": email
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            isLoading = false
            
            if (200...299).contains(httpResponse.statusCode) {
                return true
            } else {
                errorMessage = "Failed to send password reset email"
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
}

// MARK: - Auth Models

struct AuthUser: Codable, Identifiable {
    let id: String
    let email: String?
    let createdAt: String?
    var accessToken: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case createdAt = "created_at"
    }
}

struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case user
    }
}

struct AuthResponse: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: AuthUser?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
    
    func toSession() -> AuthSession? {
        guard let accessToken = accessToken,
              let refreshToken = refreshToken,
              let expiresIn = expiresIn,
              let user = user else {
            return nil
        }
        
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        var sessionUser = user
        sessionUser.accessToken = accessToken
        
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            user: sessionUser
        )
    }
}

struct AuthErrorResponse: Codable {
    let error: String?
    let message: String?
    let msg: String?
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case message
        case msg
        case errorDescription = "error_description"
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notConfigured
    case invalidResponse
    case noSession
    case invalidCredentials
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Authentication not configured"
        case .invalidResponse:
            return "Invalid response from server"
        case .noSession:
            return "No session returned"
        case .invalidCredentials:
            return "Invalid email or password"
        }
    }
}
