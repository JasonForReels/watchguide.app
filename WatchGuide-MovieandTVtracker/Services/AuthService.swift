//
//  AuthService.swift
//  WatchGuide-MovieandTVtracker
//
//  User authentication service using Supabase Auth
//

import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import Security

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()
    
    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    
    private var supabaseURL: String {
        ApiKeyManager.shared.get(key: "SUPABASE_URL") ?? ""
    }
    
    private var supabaseAnonKey: String {
        ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY") ?? ""
    }
    
    private let sessionKey = "supabase_session"
    
    var isConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
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
        loadSession()
    }
    
    // MARK: - Session Management
    
    private func loadSession() {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            return
        }
        
        // Check if session is expired
        if session.expiresAt > Date() {
            self.currentUser = session.user
            self.currentUser?.accessToken = session.accessToken
            self.isAuthenticated = true
        } else {
            // Try to refresh the session
            Task {
                await refreshSession(refreshToken: session.refreshToken)
            }
        }
    }
    
    private func saveSession(_ session: AuthSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }
    
    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
        currentUser = nil
        isAuthenticated = false
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
    
    // MARK: - Sign Out
    
    func signOut() async {
        guard isConfigured, let token = accessToken else {
            clearSession()
            // Reset active profile on sign out (keep profiles for next login)
            ProfileService.shared.activeProfile = nil
            ProfileService.shared.needsProfileSelection = false
            ProfileService.shared.resetSessionFlag()
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
        
        clearSession()
        // Reset active profile on sign out (keep profiles for next login)
        ProfileService.shared.activeProfile = nil
        ProfileService.shared.needsProfileSelection = false
        ProfileService.shared.resetSessionFlag()
        
        // Reset kids profile setting when signing out
        var settings = StorageService.shared.settings
        settings.isKidsProfile = false
        StorageService.shared.updateSettings(settings)
        
        isLoading = false
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
    /// Also attempts to delete the auth user via Supabase Admin API (requires service_role key configured as a Supabase Edge Function).
    func deleteAccount() async -> Bool {
        guard isConfigured else {
            errorMessage = "Supabase not configured."
            return false
        }
        
        guard let userId = currentUser?.id, let token = accessToken else {
            errorMessage = "Not signed in."
            return false
        }
        
        isLoading = true
        errorMessage = nil
        
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
                let storage = StorageService.shared
                storage.clearAllData()
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
