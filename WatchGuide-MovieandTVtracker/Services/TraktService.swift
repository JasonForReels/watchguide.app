//
//  TraktService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class TraktService: NSObject, ObservableObject {
    static let shared = TraktService()

    @Published private(set) var isConnected = false
    @Published private(set) var isBusy = false
    @Published private(set) var username: String?

    private let sessionKey = "trakt_session"
    private let redirectURI = "watchguide://trakt-callback"
    private let authorizeURL = URL(string: "https://trakt.tv/oauth/authorize")!
    private let apiBaseURL = URL(string: "https://api.trakt.tv")!

    private var authSession: ASWebAuthenticationSession?
    private var session: TraktSession?

    private var clientID: String {
        ApiKeyManager.shared.get(key: "TRAKT_CLIENT_ID")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var clientSecret: String {
        ApiKeyManager.shared.get(key: "TRAKT_CLIENT_SECRET")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var isConfigured: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty
    }

    override private init() {
        super.init()
        restoreCachedSession()
    }

    func prepare() async {
        guard session != nil else { return }
        do {
            try await refreshProfile()
        } catch {
            disconnect()
        }
    }

    func connect() async throws {
        guard isConfigured else {
            throw TraktError.missingConfiguration
        }

        isBusy = true
        defer { isBusy = false }

        let code = try await authorize()
        let token = try await exchangeCodeForToken(code)
        session = token.session
        persistSession()
        try await refreshProfile()
    }

    func disconnect() {
        authSession?.cancel()
        authSession = nil
        session = nil
        username = nil
        isConnected = false
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    func importWatchlist() async throws -> Int {
        isBusy = true
        defer { isBusy = false }

        let movies: [TraktMovieListItem] = try await request(path: "/sync/watchlist/movies")
        let shows: [TraktShowListItem] = try await request(path: "/sync/watchlist/shows")
        let items = try await resolveSavedItems(movies: movies, shows: shows)
        upsertImportedList(name: "Trakt Watchlist", listId: "trakt-watchlist", items: items)
        return items.count
    }

    func importWatched() async throws -> Int {
        isBusy = true
        defer { isBusy = false }

        let movies: [TraktMovieListItem] = try await request(path: "/sync/watched/movies")
        let shows: [TraktShowListItem] = try await request(path: "/sync/watched/shows")
        let items = try await resolveSavedItems(movies: movies, shows: shows)
        upsertImportedList(name: "Trakt Watched", listId: "trakt-watched", items: items)
        return items.count
    }

    private func authorize() async throws -> String {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]

        guard let url = components?.url else {
            throw TraktError.invalidAuthorizeURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: URL(string: redirectURI)?.scheme
            ) { [weak self] callbackURL, error in
                self?.authSession = nil

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard
                    let callbackURL,
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                    let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                    !code.isEmpty
                else {
                    continuation.resume(throwing: TraktError.missingAuthorizationCode)
                    return
                }

                continuation.resume(returning: code)
            }

            session.presentationContextProvider = TraktPresentationContextProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            authSession = session

            if !session.start() {
                authSession = nil
                continuation.resume(throwing: TraktError.unableToStartAuthentication)
            }
        }
    }

    private func exchangeCodeForToken(_ code: String) async throws -> TraktTokenResponse {
        try await tokenRequest(body: [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ])
    }

    private func refreshAccessTokenIfNeeded() async throws {
        guard let session else {
            throw TraktError.notConnected
        }

        if session.expiresAt > Date().addingTimeInterval(60) {
            return
        }

        let refreshed = try await tokenRequest(body: [
            "refresh_token": session.refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "refresh_token"
        ])

        self.session = refreshed.session
        persistSession()
    }

    private func tokenRequest(body: [String: String]) async throws -> TraktTokenResponse {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let payload = try JSONDecoder().decode(TraktTokenPayload.self, from: data)
        return TraktTokenResponse(payload: payload)
    }

    private func refreshProfile() async throws {
        let response: TraktUserSettings = try await request(path: "/users/settings")
        username = response.user.username
        isConnected = true
        session?.username = response.user.username
        persistSession()
    }

    private func request<T: Decodable>(path: String) async throws -> T {
        try await refreshAccessTokenIfNeeded()

        guard let session else {
            throw TraktError.notConnected
        }

        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: apiBaseURL.appendingPathComponent(trimmedPath))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TraktError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw TraktError.notConnected
            }

            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TraktError.server(message?.isEmpty == false ? message! : "Trakt request failed with status \(http.statusCode).")
        }
    }

    private func resolveSavedItems(
        movies: [TraktMovieListItem],
        shows: [TraktShowListItem]
    ) async throws -> [SavedMediaItem] {
        async let resolvedMovies = resolveMovieItems(movies)
        async let resolvedShows = resolveShowItems(shows)

        let merged = try await resolvedMovies + resolvedShows
        var seen = Set<String>()
        return merged.filter { seen.insert($0.id).inserted }
    }

    private func resolveMovieItems(_ items: [TraktMovieListItem]) async throws -> [SavedMediaItem] {
        try await withThrowingTaskGroup(of: (Int, SavedMediaItem?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    guard let tmdbID = item.movie.ids.tmdb else {
                        return (index, nil)
                    }
                    let details = try await TMDBService.shared.getMovieDetails(id: tmdbID)
                    return (index, SavedMediaItem(from: details))
                }
            }

            var collected: [(Int, SavedMediaItem)] = []
            for try await result in group {
                if let item = result.1 {
                    collected.append((result.0, item))
                }
            }

            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func resolveShowItems(_ items: [TraktShowListItem]) async throws -> [SavedMediaItem] {
        try await withThrowingTaskGroup(of: (Int, SavedMediaItem?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    guard let tmdbID = item.show.ids.tmdb else {
                        return (index, nil)
                    }
                    let details = try await TMDBService.shared.getTVShowDetails(id: tmdbID)
                    return (index, SavedMediaItem(from: details))
                }
            }

            var collected: [(Int, SavedMediaItem)] = []
            for try await result in group {
                if let item = result.1 {
                    collected.append((result.0, item))
                }
            }

            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func upsertImportedList(name: String, listId: String, items: [SavedMediaItem]) {
        let storage = StorageService.shared

        if var existing = storage.importedLists.first(where: { $0.source == .trakt && $0.listId == listId }) {
            existing.name = name
            existing.items = items
            existing.lastSynced = Date()
            existing.showOnHome = true
            storage.updateImportedList(existing)

            if !storage.customHomeRows.contains(where: { $0.importedListId == existing.id }) {
                let row = CustomHomeRow.importedListRow(
                    name: existing.displayName,
                    listId: existing.id,
                    sortOrder: storage.customHomeRows.count
                )
                storage.addCustomHomeRow(row)
            }
            return
        }

        var newList = ImportedListItem(
            name: name,
            listId: listId,
            showOnHome: true,
            source: .trakt
        )
        newList.items = items
        newList.lastSynced = Date()
        storage.addImportedList(newList)

        let row = CustomHomeRow.importedListRow(
            name: newList.displayName,
            listId: newList.id,
            sortOrder: storage.customHomeRows.count
        )
        storage.addCustomHomeRow(row)
    }

    private func restoreCachedSession() {
        guard
            let data = UserDefaults.standard.data(forKey: sessionKey),
            let stored = try? JSONDecoder().decode(TraktSession.self, from: data)
        else {
            return
        }

        session = stored
        username = stored.username
        isConnected = true
    }

    private func persistSession() {
        guard let session else { return }
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }
}

private final class TraktPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = TraktPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first {
            return window
        }
        return ASPresentationAnchor()
        #elseif canImport(AppKit)
        return NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

private struct TraktTokenResponse {
    let session: TraktSession

    init(payload: TraktTokenPayload) {
        let createdAt = Date(timeIntervalSince1970: TimeInterval(payload.createdAt))
        session = TraktSession(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: createdAt.addingTimeInterval(TimeInterval(payload.expiresIn)),
            username: nil
        )
    }
}

private struct TraktTokenPayload: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case createdAt = "created_at"
    }
}

private struct TraktSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    var username: String?
}

private struct TraktUserSettings: Decodable {
    let user: TraktUserProfile
}

private struct TraktUserProfile: Decodable {
    let username: String
}

private struct TraktMovieListItem: Decodable {
    let movie: TraktMovieSummary
}

private struct TraktShowListItem: Decodable {
    let show: TraktShowSummary
}

private struct TraktMovieSummary: Decodable {
    let ids: TraktMediaIDs
}

private struct TraktShowSummary: Decodable {
    let ids: TraktMediaIDs
}

private struct TraktMediaIDs: Decodable {
    let tmdb: Int?
}

enum TraktError: LocalizedError {
    case missingConfiguration
    case invalidAuthorizeURL
    case missingAuthorizationCode
    case unableToStartAuthentication
    case notConnected
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Trakt is not configured."
        case .invalidAuthorizeURL:
            return "Could not start Trakt sign-in."
        case .missingAuthorizationCode:
            return "Trakt sign-in did not return an authorization code."
        case .unableToStartAuthentication:
            return "Could not open the Trakt sign-in flow."
        case .notConnected:
            return "Your Trakt session is no longer valid. Please reconnect."
        case .invalidResponse:
            return "Trakt returned an invalid response."
        case .server(let message):
            return message
        }
    }
}
