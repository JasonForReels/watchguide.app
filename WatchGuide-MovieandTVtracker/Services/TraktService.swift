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

    private let bundledClientID = "7a21622de3781573c3b182c40d2e5365ac78adf0fcf28aebf8e0b0a95cf172cd"
    private let bundledClientSecret = "b5f110f77316e6c2ad889b19be55939bc369bee255b9d158dbadc78b555ca65e"

    @Published private(set) var isConnected = false
    @Published private(set) var isBusy = false
    @Published private(set) var username: String?
    @Published private(set) var tvActivation: TraktTVActivation?

    private let sessionKey = "trakt_session"
    private let redirectURI = "watchguide://oauth/callback"
    private let authorizeURL = URL(string: "https://trakt.tv/oauth/authorize")!
    private let apiBaseURL = URL(string: "https://api.trakt.tv")!

    private var authSession: ASWebAuthenticationSession?
    private var session: TraktSession?

    private var clientID: String {
        let configured = ApiKeyManager.shared.get(key: "TRAKT_CLIENT_ID")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured.isEmpty ? bundledClientID : configured
    }

    private var clientSecret: String {
        let configured = ApiKeyManager.shared.get(key: "TRAKT_CLIENT_SECRET")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured.isEmpty ? bundledClientSecret : configured
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
        tvActivation = nil
        defer {
            isBusy = false
            if !isConnected {
                tvActivation = nil
            }
        }

        #if os(tvOS)
        let token = try await connectWithDeviceCode()
        #else
        let code = try await authorize()
        let token = try await exchangeCodeForToken(code)
        #endif
        session = token.session
        persistSession()
        try await refreshProfile()
        tvActivation = nil
    }

    func disconnect() {
        #if !os(tvOS)
        authSession?.cancel()
        #endif
        authSession = nil
        tvActivation = nil
        session = nil
        username = nil
        isConnected = false
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    func importWatchlist() async throws -> Int {
        isBusy = true
        defer { isBusy = false }

        let movies: [TraktMovieListItem] = try await requestArray(path: "/sync/watchlist/movies")
        let shows: [TraktShowListItem] = try await requestArray(path: "/sync/watchlist/shows")
        let items = try await resolveSavedItems(movies: movies, shows: shows)
        upsertImportedList(name: "Trakt Watchlist", listId: "trakt-watchlist", items: items)
        return items.count
    }

    func importWatched() async throws -> Int {
        isBusy = true
        defer { isBusy = false }

        let movies: [TraktMovieListItem] = try await requestArray(path: "/sync/watched/movies")
        let shows: [TraktShowListItem] = try await requestArray(path: "/sync/watched/shows")
        let items = try await resolveSavedItems(movies: movies, shows: shows)
        upsertImportedList(name: "Trakt Watched", listId: "trakt-watched", items: items)
        return items.count
    }

    func importLiked() async throws -> Int {
        isBusy = true
        defer { isBusy = false }

        let movies: [TraktMovieListItem] = try await requestArray(path: "/sync/ratings/movies")
        let shows: [TraktShowListItem] = try await requestArray(path: "/sync/ratings/shows")
        let items = try await resolveSavedItems(movies: movies, shows: shows)
        upsertImportedList(name: "Trakt Likes", listId: "trakt-likes", items: items)
        return items.count
    }

    func syncContinueWatching() async throws -> Int {
        isBusy = true
        defer { isBusy = false }

        let playbackItems: [TraktPlaybackEpisodeItem] = try await requestArray(path: "/sync/playback/episodes")
        let historyItems: [TraktHistoryEpisodeItem] = try await requestArray(path: "/sync/history/episodes?limit=100")
        let resolvedItems = try await resolveContinueWatchingItems(historyItems: historyItems, playbackItems: playbackItems)
        // Merge Trakt items with existing deep-link-sourced items
        let deepLinkItems = StorageService.shared.continueWatching.filter { $0.source == .deepLink }
        let traktIds = Set(resolvedItems.map { $0.id })
        let nonOverlapping = deepLinkItems.filter { !traktIds.contains($0.id) }
        StorageService.shared.updateContinueWatching(resolvedItems + nonOverlapping)
        return resolvedItems.count
    }

    func syncFromTraktToWatchGuide() async throws -> TraktSyncSummary {
        isBusy = true
        defer { isBusy = false }

        let watchlistMovies: [TraktMovieListItem] = try await requestArray(path: "/sync/watchlist/movies")
        let watchlistShows: [TraktShowListItem] = try await requestArray(path: "/sync/watchlist/shows")
        let watchedMovies: [TraktMovieListItem] = try await requestArray(path: "/sync/watched/movies")
        let watchedShows: [TraktShowListItem] = try await requestArray(path: "/sync/watched/shows")
        let likedMovies: [TraktMovieListItem] = try await requestArray(path: "/sync/ratings/movies")
        let likedShows: [TraktShowListItem] = try await requestArray(path: "/sync/ratings/shows")

        let watchlistItems = try await resolveSavedItems(movies: watchlistMovies, shows: watchlistShows)
        let watchedItems = try await resolveSavedItems(movies: watchedMovies, shows: watchedShows)
        let likedItems = try await resolveSavedItems(movies: likedMovies, shows: likedShows)

        let storage = StorageService.shared
        storage.mergeTraktWatchlist(watchlistItems)
        storage.mergeTraktWatched(watchedItems)
        storage.mergeTraktLiked(likedItems)
        let continueWatchingItems = try await resolveContinueWatchingItems(
            historyItems: try await requestArray(path: "/sync/history/episodes?limit=100"),
            playbackItems: try await requestArray(path: "/sync/playback/episodes")
        )
        storage.updateContinueWatching(continueWatchingItems)

        upsertImportedList(name: "Trakt Watchlist", listId: "trakt-watchlist", items: watchlistItems)
        upsertImportedList(name: "Trakt Watched", listId: "trakt-watched", items: watchedItems)
        upsertImportedList(name: "Trakt Likes", listId: "trakt-likes", items: likedItems)

        return TraktSyncSummary(
            watchlistCount: watchlistItems.count,
            watchedCount: watchedItems.count,
            likedCount: likedItems.count,
            continueWatchingCount: continueWatchingItems.count
        )
    }

    func syncFromWatchGuideToTrakt() async throws -> TraktSyncSummary {
        isBusy = true
        defer { isBusy = false }

        let storage = StorageService.shared
        try await refreshAccessTokenIfNeeded()

        let watchlistBody = traktSyncBody(for: storage.wantToWatch)
        if !watchlistBody.isEmpty {
            try await post(path: "/sync/watchlist", body: watchlistBody)
        }

        let likedBody = traktRatingsBody(for: storage.liked, rating: 10)
        if !likedBody.isEmpty {
            try await post(path: "/sync/ratings", body: likedBody)
        }

        return TraktSyncSummary(
            watchlistCount: storage.wantToWatch.count,
            watchedCount: storage.watched.count,
            likedCount: storage.liked.count,
            continueWatchingCount: storage.continueWatching.count
        )
    }

    func addToWatchlist(_ item: SavedMediaItem) async {
        await syncItems(path: "/sync/watchlist", removal: false, items: [item])
    }

    func removeFromWatchlist(_ item: SavedMediaItem) async {
        await syncItems(path: "/sync/watchlist/remove", removal: true, items: [item])
    }

    func addLike(_ item: SavedMediaItem) async {
        await rate(item: item, rating: 10)
    }

    func removeLike(_ item: SavedMediaItem) async {
        await removeRating(for: item)
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
            #if os(tvOS)
            continuation.resume(throwing: TraktError.authenticationUnavailableOnPlatform)
            #else
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
            #endif
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

    #if os(tvOS)
    private func connectWithDeviceCode() async throws -> TraktTokenResponse {
        let activation = try await requestDeviceCode()
        tvActivation = activation

        let deadline = Date().addingTimeInterval(TimeInterval(activation.expiresIn))

        while Date() < deadline {
            do {
                let token = try await exchangeDeviceCodeForToken(activation.deviceCode)
                return token
            } catch let error as TraktError {
                switch error {
                case .authorizationPending:
                    break
                case .slowDown:
                    try await Task.sleep(for: .seconds(Double(activation.interval + 5)))
                    continue
                default:
                    throw error
                }
            }

            try await Task.sleep(for: .seconds(Double(activation.interval)))
        }

        throw TraktError.deviceCodeExpired
    }

    private func requestDeviceCode() async throws -> TraktTVActivation {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("oauth/device/code"))
        request.httpMethod = "POST"
        applyOAuthHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let payload = try JSONDecoder().decode(TraktDeviceCodePayload.self, from: data)
        return TraktTVActivation(
            deviceCode: payload.deviceCode,
            userCode: payload.userCode,
            verificationURL: payload.verificationURL,
            expiresIn: payload.expiresIn,
            interval: payload.interval,
            createdAt: Date()
        )
    }

    private func exchangeDeviceCodeForToken(_ deviceCode: String) async throws -> TraktTokenResponse {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("oauth/device/token"))
        request.httpMethod = "POST"
        applyOAuthHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": deviceCode,
            "client_id": clientID,
            "client_secret": clientSecret
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            switch http.statusCode {
            case 400:
                throw TraktError.authorizationPending
            case 404:
                throw TraktError.invalidDeviceCode
            case 409:
                throw TraktError.deviceCodeAlreadyUsed
            case 410:
                throw TraktError.deviceCodeExpired
            case 418:
                throw TraktError.deviceCodeDenied
            case 429:
                throw TraktError.slowDown
            default:
                break
            }

            if let payload = try? JSONDecoder().decode(TraktDeviceTokenErrorPayload.self, from: data) {
                switch payload.error {
                case "authorization_pending":
                    throw TraktError.authorizationPending
                case "slow_down":
                    throw TraktError.slowDown
                case "expired_token":
                    throw TraktError.deviceCodeExpired
                case "access_denied":
                    throw TraktError.deviceCodeDenied
                case "invalid_grant", "invalid_device_code":
                    throw TraktError.invalidDeviceCode
                default:
                    break
                }
            }
        }

        try validate(response: response, data: data)

        let payload = try JSONDecoder().decode(TraktTokenPayload.self, from: data)
        return TraktTokenResponse(payload: payload)
    }
    #endif

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
        applyOAuthHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let payload = try JSONDecoder().decode(TraktTokenPayload.self, from: data)
        return TraktTokenResponse(payload: payload)
    }

    private func syncItems(path: String, removal: Bool, items: [SavedMediaItem]) async {
        guard isConnected else { return }

        do {
            try await refreshAccessTokenIfNeeded()
            let body = traktSyncBody(for: items)
            try await post(path: path, body: body)
        } catch {
            if removal == false {
                print("Trakt watchlist sync error: \(error)")
            } else {
                print("Trakt watchlist removal error: \(error)")
            }
        }
    }

    private func rate(item: SavedMediaItem, rating: Int) async {
        guard isConnected else { return }

        do {
            try await refreshAccessTokenIfNeeded()
            let body = traktRatingsBody(for: [item], rating: rating)
            try await post(path: "/sync/ratings", body: body)
        } catch {
            print("Trakt rating sync error: \(error)")
        }
    }

    private func removeRating(for item: SavedMediaItem) async {
        guard isConnected else { return }

        do {
            try await refreshAccessTokenIfNeeded()
            let body = traktSyncBody(for: [item])
            try await post(path: "/sync/ratings/remove", body: body)
        } catch {
            print("Trakt rating removal error: \(error)")
        }
    }

    private func post(path: String, body: [String: Any]) async throws {
        guard let session else {
            throw TraktError.notConnected
        }

        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
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

        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func requestArray<T: Decodable>(path: String) async throws -> [T] {
        try await refreshAccessTokenIfNeeded()

        guard let session else {
            throw TraktError.notConnected
        }

        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        if data.isEmpty {
            return []
        }

        if let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           body.isEmpty || body == "null" {
            return []
        }

        return try JSONDecoder().decode([T].self, from: data)
    }

    private func makeURL(path: String) throws -> URL {
        guard var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false) else {
            throw TraktError.invalidResponse
        }

        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(parts.first ?? "")
        let normalizedPath = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
        components.path = normalizedPath
        if parts.count > 1 {
            components.percentEncodedQuery = String(parts[1])
        }

        guard let url = components.url else {
            throw TraktError.invalidResponse
        }

        return url
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TraktError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw TraktError.notConnected
            }

            let message = traktErrorMessage(from: data)
            throw TraktError.server(message ?? "Trakt request failed with status \(http.statusCode).")
        }
    }

    private func applyOAuthHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
    }

    private func traktErrorMessage(from data: Data) -> String? {
        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? String
        {
            let description = object["error_description"] as? String
            let errorTitle = error.replacingOccurrences(of: "_", with: " ").capitalized
            if let description, !description.isEmpty {
                return "\(errorTitle): \(description)"
            }
            return errorTitle
        }

        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? raw : nil
    }

    private func traktSyncBody(for items: [SavedMediaItem]) -> [String: Any] {
        var movies: [[String: Any]] = []
        var shows: [[String: Any]] = []

        for item in items {
            let payload: [String: Any] = [
                "ids": [
                    "tmdb": item.mediaId
                ]
            ]

            switch item.mediaType {
            case .movie:
                movies.append(payload)
            case .tv:
                shows.append(payload)
            case .person:
                break
            }
        }

        var body: [String: Any] = [:]
        if !movies.isEmpty {
            body["movies"] = movies
        }
        if !shows.isEmpty {
            body["shows"] = shows
        }
        return body
    }

    private func traktRatingsBody(for items: [SavedMediaItem], rating: Int) -> [String: Any] {
        var movies: [[String: Any]] = []
        var shows: [[String: Any]] = []

        for item in items {
            let payload: [String: Any] = [
                "rating": rating,
                "ids": [
                    "tmdb": item.mediaId
                ]
            ]

            switch item.mediaType {
            case .movie:
                movies.append(payload)
            case .tv:
                shows.append(payload)
            case .person:
                break
            }
        }

        var body: [String: Any] = [:]
        if !movies.isEmpty {
            body["movies"] = movies
        }
        if !shows.isEmpty {
            body["shows"] = shows
        }
        return body
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

    private func resolveContinueWatchingItems(
        historyItems: [TraktHistoryEpisodeItem],
        playbackItems: [TraktPlaybackEpisodeItem]
    ) async throws -> [ContinueWatchingItem] {
        var resolvedItems: [ContinueWatchingItem] = []
        let playbackByShowID: [Int: TraktPlaybackEpisodeItem] = playbackItems.reduce(into: [:]) { partialResult, item in
            guard let traktShowID = item.show?.ids.trakt else { return }
            partialResult[traktShowID] = item
        }

        for item in historyItems.sorted(by: historySortComparator) {
            do {
                if let resolved = try await resolveContinueWatchingItem(item, playbackItem: playbackByShowID[item.show?.ids.trakt ?? -1]) {
                    resolvedItems.append(resolved)
                }
            } catch {
                let traktID = item.show?.ids.trakt.map(String.init) ?? "unknown"
                print("Trakt continue watching item skipped for show \(traktID): \(error)")
            }
        }

        var seen = Set<String>()
        return resolvedItems.filter { seen.insert($0.id).inserted }
    }

    private func resolveContinueWatchingItem(
        _ item: TraktHistoryEpisodeItem,
        playbackItem: TraktPlaybackEpisodeItem?
    ) async throws -> ContinueWatchingItem? {
        guard
            let show = item.show,
            let episode = item.episode,
            let seasonNumber = episode.seasonNumber,
            let episodeNumber = episode.number,
            let traktShowID = show.ids.trakt,
            let tmdbShowID = show.ids.tmdb
        else {
            return nil
        }

        async let showDetails = TMDBService.shared.getTVShowDetails(id: tmdbShowID)
        async let airingInfo = TMDBService.shared.getTVShowNextEpisode(id: tmdbShowID)
        async let providersResponse = try? await TMDBService.shared.getTVShowWatchProviders(id: tmdbShowID)
        async let watchedProgress: TraktShowProgress? = try? await request(
            path: "/shows/\(traktShowID)/progress/watched?hidden=false&specials=false&count_specials=false"
        )

        let details = try await showDetails
        let airing = try await airingInfo
        let providers = await providersResponse
        let providerRegion: (region: WatchProviderRegion?, link: String?)?
        if let response = providers {
            providerRegion = await preferredProviderRegion(from: response)
        } else {
            providerRegion = nil
        }
        let progress = await watchedProgress

        let lastEpisode = ContinueWatchingEpisode(
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            title: episode.title,
            overview: episode.overview,
            airDate: episode.firstAired
        )

        return ContinueWatchingItem(
            show: SavedMediaItem(from: details),
            progress: min(max((playbackItem?.progress ?? 100) / 100.0, 0), 1),
            lastEpisode: lastEpisode,
            nextEpisode: progress?.nextEpisode.map(makeContinueWatchingEpisode(from:)),
            upcomingEpisode: airing.nextEpisodeToAir.map {
                ContinueWatchingEpisode(
                    seasonNumber: $0.seasonNumber ?? 0,
                    episodeNumber: $0.episodeNumber ?? 0,
                    title: $0.name,
                    overview: $0.overview,
                    airDate: $0.airDate
                )
            },
            providers: providerRegion?.region,
            providersLink: providerRegion?.link,
            lastUpdated: item.watchedAtDate ?? playbackItem?.pausedAtDate ?? Date()
        )
    }

    private func preferredProviderRegion(from response: WatchProvidersResponse) async -> (region: WatchProviderRegion?, link: String?)? {
        guard let results = response.results, !results.isEmpty else {
            return nil
        }

        let regionCode = await MainActor.run {
            let value = StorageService.shared.settings.region.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "US" : value
        }

        if let region = results[regionCode] {
            return (region, region.link)
        }
        if let fallback = results["US"] {
            return (fallback, fallback.link)
        }
        if let first = results.values.first {
            return (first, first.link)
        }
        return nil
    }

    private func makeContinueWatchingEpisode(from item: TraktProgressEpisode) -> ContinueWatchingEpisode {
        ContinueWatchingEpisode(
            seasonNumber: item.seasonNumber ?? 0,
            episodeNumber: item.number ?? 0,
            title: item.title,
            overview: item.overview,
            airDate: item.firstAired
        )
    }

    private func historySortComparator(lhs: TraktHistoryEpisodeItem, rhs: TraktHistoryEpisodeItem) -> Bool {
        let leftDate = lhs.watchedAtDate ?? .distantPast
        let rightDate = rhs.watchedAtDate ?? .distantPast
        return leftDate > rightDate
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

#if !os(tvOS)
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
#endif

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

struct TraktTVActivation: Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresIn: Int
    let interval: Int
    let createdAt: Date

    var expiresAt: Date {
        createdAt.addingTimeInterval(TimeInterval(expiresIn))
    }
}

private struct TraktDeviceCodePayload: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURL = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct TraktDeviceTokenErrorPayload: Decodable {
    let error: String
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
    let trakt: Int?
    let tmdb: Int?
}

private struct TraktPlaybackEpisodeItem: Decodable {
    let progress: Double?
    let pausedAt: String?
    let episode: TraktPlaybackEpisode?
    let show: TraktShowSummary?

    var pausedAtDate: Date? {
        pausedAt.flatMap(TraktDateParser.date)
    }

    enum CodingKeys: String, CodingKey {
        case progress
        case pausedAt = "paused_at"
        case episode
        case show
    }
}

private struct TraktHistoryEpisodeItem: Decodable {
    let watchedAt: String?
    let episode: TraktPlaybackEpisode?
    let show: TraktShowSummary?

    var watchedAtDate: Date? {
        watchedAt.flatMap(TraktDateParser.date)
    }

    enum CodingKeys: String, CodingKey {
        case watchedAt = "watched_at"
        case episode
        case show
    }
}

private struct TraktPlaybackEpisode: Decodable {
    let seasonNumber: Int?
    let number: Int?
    let title: String?
    let overview: String?
    let firstAired: String?

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case overview
        case seasonNumber = "season"
        case firstAired = "first_aired"
    }
}

private struct TraktShowProgress: Decodable {
    let nextEpisode: TraktProgressEpisode?

    enum CodingKeys: String, CodingKey {
        case nextEpisode = "next_episode"
    }
}

private struct TraktProgressEpisode: Decodable {
    let seasonNumber: Int?
    let number: Int?
    let title: String?
    let overview: String?
    let firstAired: String?

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case overview
        case seasonNumber = "season"
        case firstAired = "first_aired"
    }
}

private enum TraktDateParser {
    static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from value: String) -> Date? {
        iso8601WithFractionalSeconds.date(from: value) ?? iso8601.date(from: value)
    }
}

enum TraktError: LocalizedError {
    case missingConfiguration
    case invalidAuthorizeURL
    case missingAuthorizationCode
    case unableToStartAuthentication
    case authenticationUnavailableOnPlatform
    case authorizationPending
    case slowDown
    case deviceCodeExpired
    case deviceCodeDenied
    case invalidDeviceCode
    case deviceCodeAlreadyUsed
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
        case .authenticationUnavailableOnPlatform:
            return "Trakt sign-in is not available on this platform."
        case .authorizationPending:
            return "Waiting for Trakt approval."
        case .slowDown:
            return "Trakt asked the app to slow down polling."
        case .deviceCodeExpired:
            return "The Trakt login code expired. Start the connection again."
        case .deviceCodeDenied:
            return "The Trakt login request was denied."
        case .invalidDeviceCode:
            return "The Trakt device code is invalid. Start the connection again."
        case .deviceCodeAlreadyUsed:
            return "This Trakt code was already used. Start the connection again."
        case .notConnected:
            return "Your Trakt session is no longer valid. Please reconnect."
        case .invalidResponse:
            return "Trakt returned an invalid response."
        case .server(let message):
            return message
        }
    }
}

struct TraktSyncSummary {
    let watchlistCount: Int
    let watchedCount: Int
    let likedCount: Int
    let continueWatchingCount: Int
}
