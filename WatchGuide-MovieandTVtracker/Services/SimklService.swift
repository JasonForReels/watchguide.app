//
//  SimklService.swift
//  WatchGuide-MovieandTVtracker
//
//  Simkl sync over AUTH V2 (OAuth 2.0 with PKCE; device code on tvOS).
//  Mirrors WatchGuide's lists to Simkl as the user changes them, imports the
//  Simkl library on request, and can check in when the user opens a title in
//  a streaming app. Simkl's rules this follows (api.simkl.org/api-rules):
//  one call per user action, batched writes at most one POST a second,
//  library reads gated on /sync/activities, and no client secret on device.
//

import Foundation
import AuthenticationServices
import CryptoKit
import Security
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class SimklService: NSObject, ObservableObject {
    static let shared = SimklService()

    @Published private(set) var isConnected = false
    @Published private(set) var isBusy = false
    @Published private(set) var username: String?
    @Published private(set) var tvActivation: SimklTVActivation?

    /// Check in on Simkl when the user opens a title in a streaming app. Off by
    /// default: Simkl marks a check-in watched once the runtime has passed.
    @Published var checkInEnabled: Bool {
        didSet { UserDefaults.standard.set(checkInEnabled, forKey: Self.checkInKey) }
    }

    private static let checkInKey = "simkl_checkin_enabled"
    private static let activitiesKey = "simkl_last_activity"
    private let sessionKey = "SIMKL_SESSION"
    private let redirectURI = "watchguide://simkl/callback"
    private let authorizeURL = URL(string: "https://simkl.com/oauth2/authorize")!
    private let apiBaseURL = URL(string: "https://api.simkl.com")!
    private let appName = "watchguide"

    private var authSession: ASWebAuthenticationSession?
    private var session: SimklSession?
    private var refreshTask: Task<Void, Error>?
    private var lastPost = Date.distantPast

    /// AUTH V2 client id (Mobile, desktop & browser apps). Not a secret: on its
    /// own it reaches only public catalog data. `SIMKL_CLIENT_ID` overrides it.
    private let bundledClientID = "c1374253946313ab935715d2aaea592cd99fda4b1dbe10b21cce3e017b5cdbde"

    private var clientID: String {
        let configured = ApiKeyManager.shared.get(key: "SIMKL_CLIENT_ID")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured.isEmpty ? bundledClientID : configured
    }

    var isConfigured: Bool { !clientID.isEmpty }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    override private init() {
        checkInEnabled = UserDefaults.standard.bool(forKey: Self.checkInKey)
        super.init()
        restoreSession()
    }

    // MARK: - Connection

    func prepare() async {
        guard session != nil, username == nil else { return }
        do {
            try await refreshProfile()
        } catch SimklError.notConnected {
            clearSession()
        } catch {
            // Offline or Simkl is down — keep the session and try again later.
        }
    }

    func connect() async throws {
        guard isConfigured else { throw SimklError.missingConfiguration }
        isBusy = true
        tvActivation = nil
        defer {
            isBusy = false
            tvActivation = nil
        }

        #if os(tvOS)
        let token = try await connectWithDeviceCode()
        #else
        let verifier = Self.makeCodeVerifier()
        let code = try await authorize(challenge: Self.codeChallenge(for: verifier))
        let token = try await tokenRequest([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier
        ])
        #endif
        session = SimklSession(token: token, username: nil)
        persistSession()
        try await refreshProfile()
        UserDefaults.standard.removeObject(forKey: Self.activitiesKey)
    }

    func disconnect() {
        #if !os(tvOS)
        authSession?.cancel()
        #endif
        authSession = nil
        if let refreshToken = session?.refreshToken {
            let body = ["client_id": clientID, "token": refreshToken]
            Task { try? await self.formPost(path: "/oauth2/revoke", body: body) }
        }
        clearSession()
    }

    // MARK: - Live sync (called from StorageService on each user change)

    func addToWatchlist(_ item: SavedMediaItem) async {
        await send("/sync/add-to-list", body: listBody(for: [item], status: "plantowatch"))
    }

    func removeFromWatchlist(_ item: SavedMediaItem) async {
        // Moving to Watched also removes from Want to Watch; Simkl keeps one
        // status per title, so only un-track it when it isn't watched either.
        guard !StorageService.shared.isInWatched(item.mediaId, mediaType: item.mediaType) else { return }
        await send("/sync/history/remove", body: idsBody(for: [item]))
    }

    func markWatched(_ item: SavedMediaItem) async {
        if item.mediaType == .movie {
            await send("/sync/history", body: idsBody(for: [item], extra: ["watched_at": Self.isoNow()]))
        } else {
            // Set the status only; /sync/history would mark every episode watched.
            await send("/sync/add-to-list", body: listBody(for: [item], status: "completed"))
        }
    }

    func unmarkWatched(_ item: SavedMediaItem) async {
        if StorageService.shared.isInWantToWatch(item.mediaId, mediaType: item.mediaType) {
            await send("/sync/add-to-list", body: listBody(for: [item], status: "plantowatch"))
        } else {
            await send("/sync/history/remove", body: idsBody(for: [item]))
        }
    }

    func addLike(_ item: SavedMediaItem) async {
        await send("/sync/ratings", body: idsBody(for: [item], extra: ["rating": 10]))
    }

    func removeLike(_ item: SavedMediaItem) async {
        await send("/sync/ratings/remove", body: idsBody(for: [item]))
    }

    /// Records one episode as watched, e.g. from Continue Watching's "Mark as watched".
    func markEpisodeWatched(show: SavedMediaItem, season: Int, episode: Int) async {
        guard show.mediaType == .tv else { return }
        var entry = mediaEntry(for: show)
        entry["seasons"] = [["number": season, "episodes": [["number": episode, "watched_at": Self.isoNow()]]]]
        await send("/sync/history", body: ["shows": [entry]])
    }

    /// Checks in when the user opens a title in a streaming app, if they turned it on.
    func checkIn(_ item: SavedMediaItem, season: Int? = nil, episode: Int? = nil) async {
        guard checkInEnabled else { return }
        var body: [String: Any]
        switch item.mediaType {
        case .movie:
            body = ["movie": mediaEntry(for: item)]
        case .tv:
            guard let season, let episode else { return }
            body = ["show": mediaEntry(for: item), "episode": ["season": season, "number": episode]]
        case .person:
            return
        }
        body["progress"] = 0
        // 409 means a check-in for this title is already running; nothing to do.
        await send("/scrobble/checkin", body: body, ignoring: [409])
    }

    // MARK: - Full sync (from Settings)

    /// Pulls the Simkl library into WatchGuide. Skips the download when Simkl
    /// reports no changes since the last import.
    func importLibrary() async throws -> SimklSyncSummary {
        isBusy = true
        defer { isBusy = false }

        let activities: SimklActivities = try await get("/sync/activities")
        if let last = UserDefaults.standard.string(forKey: Self.activitiesKey), last == activities.all {
            return SimklSyncSummary(watchlistCount: 0, watchedCount: 0, likedCount: 0, unchanged: true)
        }

        let movies: SimklAllItems = try await get("/sync/all-items/movies")
        let shows: SimklAllItems = try await get("/sync/all-items/shows")
        let entries = (movies.movies ?? []).map { ($0, MediaType.movie) } + (shows.shows ?? []).map { ($0, MediaType.tv) }

        var watchlist: [(Int, MediaType)] = []
        var watched: [(Int, MediaType)] = []
        var liked: [(Int, MediaType)] = []
        for (entry, type) in entries {
            guard let tmdbId = entry.media?.ids.tmdbId else { continue }
            switch entry.status {
            case "plantowatch", "watching", "hold": watchlist.append((tmdbId, type))
            case "completed": watched.append((tmdbId, type))
            default: break
            }
            if let rating = entry.userRating, rating >= 8 { liked.append((tmdbId, type)) }
        }

        let watchlistItems = try await resolve(watchlist)
        let watchedItems = try await resolve(watched)
        let likedItems = try await resolve(liked)

        let storage = StorageService.shared
        storage.mergeTraktWatchlist(watchlistItems)
        storage.mergeTraktWatched(watchedItems)
        storage.mergeTraktLiked(likedItems)
        UserDefaults.standard.set(activities.all, forKey: Self.activitiesKey)

        return SimklSyncSummary(
            watchlistCount: watchlistItems.count,
            watchedCount: watchedItems.count,
            likedCount: likedItems.count,
            unchanged: false
        )
    }

    /// Sends WatchGuide's lists to Simkl in batches.
    func exportLibrary() async throws -> SimklSyncSummary {
        isBusy = true
        defer { isBusy = false }

        let storage = StorageService.shared
        let watchedMovies = storage.watched.filter { $0.mediaType == .movie }
        let watchedShows = storage.watched.filter { $0.mediaType == .tv }
        let wantToWatch = storage.wantToWatch.filter { !storage.isInWatched($0.mediaId, mediaType: $0.mediaType) }

        for chunk in wantToWatch.chunked(into: 100) {
            try await post("/sync/add-to-list", body: listBody(for: chunk, status: "plantowatch"))
        }
        for chunk in watchedMovies.chunked(into: 100) {
            try await post("/sync/history", body: idsBody(for: chunk))
        }
        for chunk in watchedShows.chunked(into: 100) {
            try await post("/sync/add-to-list", body: listBody(for: chunk, status: "completed"))
        }
        for chunk in storage.liked.chunked(into: 100) {
            try await post("/sync/ratings", body: idsBody(for: chunk, extra: ["rating": 10]))
        }

        return SimklSyncSummary(
            watchlistCount: wantToWatch.count,
            watchedCount: watchedMovies.count + watchedShows.count,
            likedCount: storage.liked.count,
            unchanged: false
        )
    }

    // MARK: - Sign-in

    #if !os(tvOS)
    private func authorize(challenge: String) async throws -> String {
        let state = UUID().uuidString
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "media:read media:write"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components?.url else { throw SimklError.invalidResponse }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "watchguide") { [weak self] callbackURL, error in
                Task { @MainActor in self?.authSession = nil }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let items = callbackURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
                guard items.first(where: { $0.name == "state" })?.value == state,
                      let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                    continuation.resume(throwing: SimklError.missingAuthorizationCode)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = SimklPresentationContextProvider.shared
            authSession = session
            if !session.start() {
                authSession = nil
                continuation.resume(throwing: SimklError.unableToStartAuthentication)
            }
        }
    }
    #endif

    #if os(tvOS)
    private func connectWithDeviceCode() async throws -> SimklTokenPayload {
        let data = try await formPost(path: "/oauth2/device", body: [
            "client_id": clientID,
            "scope": "media:read media:write"
        ])
        let device = try JSONDecoder().decode(SimklDeviceCodePayload.self, from: data)
        let activation = SimklTVActivation(
            userCode: device.userCode,
            verificationURL: URL(string: device.verificationURIComplete ?? device.verificationURI) ?? URL(string: "https://simkl.com/pin")!,
            expiresAt: Date().addingTimeInterval(TimeInterval(device.expiresIn))
        )
        tvActivation = activation

        var interval = max(device.interval, 5)
        while Date() < activation.expiresAt {
            try await Task.sleep(for: .seconds(Double(interval)))
            do {
                return try await tokenRequest([
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    "client_id": clientID,
                    "device_code": device.deviceCode
                ])
            } catch SimklError.oauth(let code) {
                switch code {
                case "authorization_pending": continue
                case "slow_down": interval += 5
                case "access_denied": throw SimklError.deviceCodeDenied
                case "expired_token": throw SimklError.deviceCodeExpired
                default: throw SimklError.oauth(code)
                }
            }
        }
        throw SimklError.deviceCodeExpired
    }
    #endif

    private func tokenRequest(_ body: [String: String]) async throws -> SimklTokenPayload {
        let data = try await formPost(path: "/oauth2/token", body: body)
        return try JSONDecoder().decode(SimklTokenPayload.self, from: data)
    }

    /// Refreshes once at a time, so two requests never refresh the same grant
    /// and cut each other off.
    private func refreshAccessToken() async throws {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = session?.refreshToken else { throw SimklError.notConnected }
        let task = Task { @MainActor in
            let token = try await self.tokenRequest([
                "grant_type": "refresh_token",
                "client_id": self.clientID,
                "refresh_token": refreshToken
            ])
            self.session = SimklSession(token: token, username: self.session?.username)
            self.persistSession()
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            try await task.value
        } catch SimklError.oauth {
            // invalid_grant: the user revoked access or the refresh token lapsed.
            clearSession()
            throw SimklError.notConnected
        }
    }

    private func refreshProfile() async throws {
        let settings: SimklUserSettings = try await get("/users/settings")
        username = settings.user?.name
        session?.username = username
        isConnected = true
        persistSession()
    }

    // MARK: - Requests

    private func send(_ path: String, body: [String: Any], ignoring: Set<Int> = []) async {
        guard isConnected, !body.isEmpty else { return }
        do {
            try await post(path, body: body, ignoring: ignoring)
        } catch {
            print("Simkl \(path) failed: \(error.localizedDescription)")
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await authorized(path: path, method: "GET", body: nil)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post(_ path: String, body: [String: Any], ignoring: Set<Int> = []) async throws {
        // Simkl allows one POST a second per user, and a burst gets the token throttled.
        let wait = 1.1 - Date().timeIntervalSince(lastPost)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        lastPost = Date()
        do {
            _ = try await authorized(path: path, method: "POST", body: try JSONSerialization.data(withJSONObject: body))
        } catch SimklError.http(let status, _) where ignoring.contains(status) {
            return
        }
    }

    /// Sends a request with the access token, refreshing it first when it is
    /// close to expiry, and once more on a 401.
    private func authorized(path: String, method: String, body: Data?, retried: Bool = false) async throws -> Data {
        guard let current = session else { throw SimklError.notConnected }
        if current.expiresAt < Date().addingTimeInterval(86400) {
            try await refreshAccessToken()
        }

        var request = URLRequest(url: makeURL(path: path))
        request.httpMethod = method
        request.setValue("WatchGuide/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(session?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 401, !retried {
            try await refreshAccessToken()
            return try await authorized(path: path, method: method, body: body, retried: true)
        }
        if status == 401 {
            clearSession()
            throw SimklError.notConnected
        }
        guard (200...299).contains(status) else {
            throw SimklError.http(status, Self.errorMessage(from: data))
        }
        return data
    }

    @discardableResult
    private func formPost(path: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: makeURL(path: path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("WatchGuide/\(appVersion)", forHTTPHeaderField: "User-Agent")
        var form = URLComponents()
        form.queryItems = body.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" alone, which a form decoder reads as a space.
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            if let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String {
                throw SimklError.oauth(error)
            }
            throw SimklError.http(status, Self.errorMessage(from: data))
        }
        return data
    }

    /// Adds the three parameters Simkl wants on every request.
    private func makeURL(path: String) -> URL {
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "app-name", value: appName),
            URLQueryItem(name: "app-version", value: appVersion)
        ]
        return components.url!
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["message"] as? String) ?? (object["error_description"] as? String) ?? (object["error"] as? String)
    }

    // MARK: - Request bodies

    /// title + year + TMDB id; Simkl resolves the rest server-side.
    private func mediaEntry(for item: SavedMediaItem) -> [String: Any] {
        var entry: [String: Any] = ["title": item.title, "ids": ["tmdb": String(item.mediaId)]]
        if let year = item.year.flatMap({ Int($0.prefix(4)) }) { entry["year"] = year }
        return entry
    }

    private func idsBody(for items: [SavedMediaItem], extra: [String: Any] = [:]) -> [String: Any] {
        var movies: [[String: Any]] = []
        var shows: [[String: Any]] = []
        for item in items {
            let entry = mediaEntry(for: item).merging(extra) { _, new in new }
            switch item.mediaType {
            case .movie: movies.append(entry)
            case .tv: shows.append(entry)
            case .person: break
            }
        }
        var body: [String: Any] = [:]
        if !movies.isEmpty { body["movies"] = movies }
        if !shows.isEmpty { body["shows"] = shows }
        return body
    }

    private func listBody(for items: [SavedMediaItem], status: String) -> [String: Any] {
        idsBody(for: items, extra: ["to": status])
    }

    // MARK: - Import helpers

    private func resolve(_ ids: [(Int, MediaType)]) async throws -> [SavedMediaItem] {
        try await withThrowingTaskGroup(of: (Int, SavedMediaItem?).self) { group in
            for (index, (tmdbId, type)) in ids.enumerated() {
                group.addTask {
                    // A title TMDB can't find is skipped rather than failing the import.
                    if type == .movie {
                        guard let details = try? await TMDBService.shared.getMovieDetails(id: tmdbId) else { return (index, nil) }
                        return (index, SavedMediaItem(from: details))
                    }
                    guard let details = try? await TMDBService.shared.getTVShowDetails(id: tmdbId) else { return (index, nil) }
                    return (index, SavedMediaItem(from: details))
                }
            }
            var collected: [(Int, SavedMediaItem)] = []
            for try await (index, item) in group {
                if let item { collected.append((index, item)) }
            }
            var seen = Set<String>()
            return collected.sorted { $0.0 < $1.0 }.map(\.1).filter { seen.insert($0.id).inserted }
        }
    }

    // MARK: - Session storage (Keychain)

    private func restoreSession() {
        guard let json = ApiKeyManager.shared.get(key: sessionKey), !json.isEmpty,
              let stored = try? JSONDecoder().decode(SimklSession.self, from: Data(json.utf8)) else { return }
        session = stored
        username = stored.username
        isConnected = true
    }

    private func persistSession() {
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        _ = ApiKeyManager.shared.set(key: sessionKey, value: String(decoding: data, as: UTF8.self))
    }

    private func clearSession() {
        session = nil
        username = nil
        isConnected = false
        tvActivation = nil
        _ = ApiKeyManager.shared.set(key: sessionKey, value: "")
        UserDefaults.standard.removeObject(forKey: Self.activitiesKey)
    }

    // MARK: - PKCE

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Could not generate a secure PKCE verifier")
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

#if !os(tvOS)
private final class SimklPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = SimklPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first {
            return window
        }
        #endif
        return ASPresentationAnchor()
    }
}
#endif

// MARK: - Models

struct SimklTVActivation: Equatable {
    let userCode: String
    /// Opens Simkl's approval page with the code already filled in.
    let verificationURL: URL
    let expiresAt: Date
}

struct SimklSyncSummary {
    let watchlistCount: Int
    let watchedCount: Int
    let likedCount: Int
    /// Simkl reported no changes since the last import, so nothing was downloaded.
    let unchanged: Bool
}

private struct SimklSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    var username: String?

    init(token: SimklTokenPayload, username: String?) {
        accessToken = token.accessToken
        refreshToken = token.refreshToken
        expiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        self.username = username
    }
}

private struct SimklTokenPayload: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct SimklDeviceCodePayload: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let verificationURIComplete: String?
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct SimklUserSettings: Decodable {
    struct User: Decodable { let name: String? }
    let user: User?
}

private struct SimklActivities: Decodable {
    let all: String?
}

private struct SimklAllItems: Decodable {
    let movies: [SimklLibraryEntry]?
    let shows: [SimklLibraryEntry]?
}

private struct SimklLibraryEntry: Decodable {
    let status: String?
    let userRating: Int?
    let movie: SimklMedia?
    let show: SimklMedia?

    var media: SimklMedia? { movie ?? show }

    enum CodingKeys: String, CodingKey {
        case status, movie, show
        case userRating = "user_rating"
    }
}

private struct SimklMedia: Decodable {
    let ids: SimklIDs
}

private struct SimklIDs: Decodable {
    /// Simkl sends TMDB ids as strings; accept numbers too.
    let tmdbId: Int?

    enum CodingKeys: String, CodingKey { case tmdb }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? container.decode(String.self, forKey: .tmdb) {
            tmdbId = Int(string)
        } else {
            tmdbId = try? container.decode(Int.self, forKey: .tmdb)
        }
    }
}

enum SimklError: LocalizedError {
    case missingConfiguration
    case missingAuthorizationCode
    case unableToStartAuthentication
    case deviceCodeExpired
    case deviceCodeDenied
    case notConnected
    case invalidResponse
    case oauth(String)
    case http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "Simkl is not configured."
        case .missingAuthorizationCode: return "Simkl sign-in did not return an authorization code."
        case .unableToStartAuthentication: return "Could not open the Simkl sign-in page."
        case .deviceCodeExpired: return "The Simkl code expired. Start the connection again."
        case .deviceCodeDenied: return "The Simkl sign-in was declined."
        case .notConnected: return "Your Simkl session has ended. Please reconnect."
        case .invalidResponse: return "Simkl returned an invalid response."
        case .oauth(let code): return "Simkl sign-in failed (\(code.replacingOccurrences(of: "_", with: " ")))."
        case .http(let status, let message): return message ?? "Simkl request failed (\(status))."
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
