//
//  AuthService.swift
//  WatchGuide-MovieandTVtracker
//
//  User authentication service supporting Supabase Auth
//

import Foundation
import Combine

@MainActor
class AuthService: ObservableObject {
    enum AuthFlow {
        case unknown
        case signIn
        case signUp
    }

    static let shared = AuthService()
    
    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = false
    @Published var requiresPostSignInSyncDecision = false
    @Published private(set) var lastAuthFlow: AuthFlow = .unknown
    @Published var errorMessage: String?
    
    private var supabaseURL: String {
        ApiKeyManager.shared.get(key: "SUPABASE_URL") ?? ""
    }
    
    private var supabaseAnonKey: String {
        ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY") ?? ""
    }

    private var deleteAccountFunctionName: String {
        let configured = ApiKeyManager.shared.get(key: "DELETE_ACCOUNT_FUNCTION_NAME")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }
        return "super-endpoint"
    }
    
    private let sessionKey = "supabase_session"
    private let icloudSessionKey = "icloud_auth_session"
    private let backendKey = "auth_backend"
    private let lastUserIdKey = "last_user_id"

    private enum AuthBackend: String {
        case supabase
        case apple
    }

    private var authBackend: AuthBackend? {
        get {
            guard let value = UserDefaults.standard.string(forKey: backendKey) else { return nil }
            return AuthBackend(rawValue: value)
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: backendKey)
        }
    }
    
    var isConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
    
    /// Whether Supabase is available for auth
    var isSupabaseAvailable: Bool {
        isConfigured
    }
    
    // Current access token for authenticated requests
    var accessToken: String? {
        currentUser?.accessToken
    }
    
    // User ID for database queries (replaces device_id when logged in)
    var userId: String? {
        currentUser?.id
    }

    var isAppleAuthActive: Bool {
        isAuthenticated && authBackend == .apple
    }
    
    private init() {
        loadSession()
    }
    
    // MARK: - Session Management
    
    private func loadSession() {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            loadAppleSession()
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
        UserDefaults.standard.removeObject(forKey: icloudSessionKey)
        authBackend = .supabase
        
        let previousUserId = UserDefaults.standard.string(forKey: lastUserIdKey)
        if let previousUserId = previousUserId, previousUserId != session.user.id {
            StorageService.shared.clearAllData()
        }
        UserDefaults.standard.set(session.user.id, forKey: lastUserIdKey)
    }
    
    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
        UserDefaults.standard.removeObject(forKey: icloudSessionKey)
        UserDefaults.standard.removeObject(forKey: backendKey)
        UserDefaults.standard.removeObject(forKey: lastUserIdKey)
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
                    lastAuthFlow = .signUp
                    requiresPostSignInSyncDecision = true
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
                    lastAuthFlow = .signIn
                    requiresPostSignInSyncDecision = true
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
        await signInWithApple(idToken: idToken, nonce: nonce, appleUserID: nil, email: nil)
    }

    func signInWithApple(idToken: String, nonce: String?, appleUserID: String?, email: String?) async -> Bool {
        if !isConfigured {
            let userId = appleUserID?.isEmpty == false ? appleUserID! : "apple-\(UUID().uuidString)"
            let user = AuthUser(
                id: userId,
                email: email,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                accessToken: nil
            )
            saveAppleSession(user)
            currentUser = user
            isAuthenticated = true
            lastAuthFlow = .signIn
            requiresPostSignInSyncDecision = true
            errorMessage = nil
            return true
        }

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
                    lastAuthFlow = .signIn
                    authBackend = .supabase
                    requiresPostSignInSyncDecision = true
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

    // MARK: - Sign Out
    
    func signOut() async {
        guard isConfigured, let token = accessToken else {
            StorageService.shared.clearAllData()
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
        
        StorageService.shared.clearAllData()
        clearSession()
        resetProfileState()
        requiresPostSignInSyncDecision = false
        
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
        guard currentUser?.id != nil else {
            errorMessage = "Not signed in."
            return false
        }
        
        isLoading = true
        errorMessage = nil
        
        // Supabase backend
        guard isConfigured, let token = accessToken else {
            if authBackend == .apple {
                StorageService.shared.clearAllData()
                clearSession()
                resetProfileState()
                isLoading = false
                return true
            } else {
                errorMessage = "Supabase not configured."
                isLoading = false
                return false
            }
        }
        
        // Hard-delete account via Edge Function (must delete auth user, not just local data).
        do {
            let validToken = await ensureFreshAccessToken(preferredToken: token)
            try await callDeleteAccountEdgeFunction(accessToken: validToken)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }

        StorageService.shared.clearAllData()
        clearSession()
        resetProfileState()

        var settings = StorageService.shared.settings
        settings.isKidsProfile = false
        StorageService.shared.updateSettings(settings)

        isLoading = false
        return true
    }

    private func callDeleteAccountEdgeFunction(accessToken: String) async throws {
        guard let url = URL(string: "\(supabaseURL)/functions/v1/\(deleteAccountFunctionName)") else {
            throw AuthError.invalidURL
        }

        let (data, httpResponse) = try await performDeleteAccountRequest(url: url, accessToken: accessToken)
        if httpResponse.statusCode == 401, let refreshToken = storedRefreshToken {
            // Session may be stale; refresh once and retry.
            await refreshSession(refreshToken: refreshToken)
            guard let retriedToken = self.accessToken else {
                throw AuthError.apiError("Session expired. Please sign in again and retry account deletion.")
            }
            let (retryData, retryResponse) = try await performDeleteAccountRequest(url: url, accessToken: retriedToken)
            guard (200...299).contains(retryResponse.statusCode) else {
                let message = String(data: retryData, encoding: .utf8) ?? "Unauthorized"
                throw AuthError.apiError("Delete account failed (\(retryResponse.statusCode)): \(message)")
            }
            return
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw AuthError.apiError("Delete account failed (\(httpResponse.statusCode)): \(message)")
        }
    }

    private func performDeleteAccountRequest(url: URL, accessToken: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        return (data, httpResponse)
    }

    private var storedRefreshToken: String? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            return nil
        }
        return session.refreshToken
    }

    private func ensureFreshAccessToken(preferredToken: String) async -> String {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            return preferredToken
        }

        // Refresh if this token is near expiry (or expired) before sensitive operations.
        if session.expiresAt <= Date().addingTimeInterval(60) {
            await refreshSession(refreshToken: session.refreshToken)
            return accessToken ?? preferredToken
        }

        return preferredToken
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

    private func loadAppleSession() {
        guard let data = UserDefaults.standard.data(forKey: icloudSessionKey),
              let session = try? JSONDecoder().decode(AppleAuthSession.self, from: data) else {
            return
        }

        currentUser = AuthUser(
            id: session.userId,
            email: session.email,
            createdAt: session.createdAt,
            accessToken: nil
        )
        isAuthenticated = true
        requiresPostSignInSyncDecision = false
        authBackend = .apple
    }

    private func saveAppleSession(_ user: AuthUser) {
        let session = AppleAuthSession(
            userId: user.id,
            email: user.email,
            createdAt: user.createdAt ?? ISO8601DateFormatter().string(from: Date())
        )
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: icloudSessionKey)
        }
        UserDefaults.standard.removeObject(forKey: sessionKey)
        authBackend = .apple
        UserDefaults.standard.set(user.id, forKey: lastUserIdKey)
    }

    func completePostSignInSyncDecision() {
        requiresPostSignInSyncDecision = false
        lastAuthFlow = .unknown
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

struct AppleAuthSession: Codable {
    let userId: String
    let email: String?
    let createdAt: String
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notConfigured
    case invalidResponse
    case invalidURL
    case noSession
    case invalidCredentials
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Authentication not configured"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidURL:
            return "Invalid request URL"
        case .noSession:
            return "No session returned"
        case .invalidCredentials:
            return "Invalid email or password"
        case .apiError(let message):
            return message
        }
    }
}
