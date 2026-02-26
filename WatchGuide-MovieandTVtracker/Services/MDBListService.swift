//
//  MDBListService.swift
//  WatchGuide-MovieandTVtracker
//
//  MDBList service for fetching curated movie & TV lists
//  Uses public JSON export first, then API /lists/{id}/items fallback
//

import Foundation

actor MDBListService {
    static let shared = MDBListService()
    
    private let baseURL = "https://mdblist.com/api"
    
    private let apiKey = "mi46uequ1wi40i8fxp4789jxz"
    
    // Optimized session with caching
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()
    
    // In-memory cache for list results
    private var listCache: [String: (items: [MDBListItem], timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 600 // 10 minutes
    
    // In-memory cache for list path resolution (slugOrId -> username/slug)
    private var listPathCache: [String: String] = [:] // slugOrId -> username/slug
    
    private init() {}
    
    var isConfigured: Bool {
        !apiKey.isEmpty
    }
    
    /// Resolve an input (slug, numeric id, or username/slug) to a fetchable path for list items.
    /// Returns username/slug when possible. Caches results.
    private func resolveListPath(from input: String) async -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return input }
        
        // If it's a full URL, return parsed username/slug directly to avoid API calls
        if trimmed.lowercased().contains("mdblist.com/lists/") {
            return parseListId(from: trimmed)
        }
        
        // If already in username/slug format (has a slash), return as-is
        if trimmed.contains("/") { return trimmed }
        
        // If cached, return
        if let cached = listPathCache[trimmed] { return cached }
        
        // Try search API to find a matching list by slug or name
        do {
            let results = try await searchLists(query: trimmed)
            // Prefer exact slug match, else first result
            if let exact = results.first(where: { ($0.slug ?? "").lowercased() == trimmed.lowercased() }) {
                let path = exact.listPath
                listPathCache[trimmed] = path
                return path
            }
            if let first = results.first {
                let path = first.listPath
                listPathCache[trimmed] = path
                return path
            }
        } catch {
            print("resolveListPath search error: \(error)")
        }
        
        // Fallback: return input as-is
        return trimmed
    }
    
    // MARK: - List Endpoints
    
    /// Fetch list items from a full list URL or username/slug using only the public JSON export (no API key).
    /// This avoids API rate limiting. Input can be a full URL like
    /// https://mdblist.com/lists/{username}/{slug} or just "username/slug".
    func getListItemsFromURL(_ input: String) async throws -> [MDBListItem] {
        let path = parseListId(from: input)
        guard !path.isEmpty else { throw MDBListError.invalidList }

        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let publicURLString = "https://mdblist.com/lists/\(encoded)/json"
        return try await getListItemsFromDirectURL(publicURLString)
    }

    /// Fetch list items from an exact MDBList JSON export URL (supports query params like sort=imdb_popular).
    func getListItemsFromDirectURL(_ urlString: String) async throws -> [MDBListItem] {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MDBListError.invalidURL }

        let cacheKey = "directURL::\(trimmed)"
        if let cached = listCache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.items
        }

        guard let url = URL(string: trimmed) else { throw MDBListError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw MDBListError.networkError }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("MDBList direct URL fetch failed (\(httpResponse.statusCode)): \(body.prefix(300))")
            throw MDBListError.apiError(httpResponse.statusCode)
        }

        let items = try decodeListItems(from: data)
        listCache[cacheKey] = (items: items, timestamp: Date())
        return items
    }
    
    /// Get list items by list ID using the JSON export endpoint
    func getListItems(listId: String) async throws -> [MDBListItem] {
        guard !apiKey.isEmpty else {
            throw MDBListError.notConfigured
        }
        
        // If input is a full URL, bypass search/API and use public export only to avoid rate limits
        if listId.lowercased().contains("mdblist.com/lists/") {
            let path = parseListId(from: listId)
            let encodedListId = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            let publicURLString = "https://mdblist.com/lists/\(encodedListId)/json"
            print("MDBList public URL (direct): \(publicURLString)")
            guard let publicURL = URL(string: publicURLString) else { throw MDBListError.invalidURL }
            var request = URLRequest(url: publicURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw MDBListError.networkError }
            guard (200...299).contains(httpResponse.statusCode) else {
                let bodyPreview = String(data: data, encoding: .utf8) ?? ""
                print("MDBList public (direct) failed (\(httpResponse.statusCode)): \(bodyPreview.prefix(300))")
                throw MDBListError.apiError(httpResponse.statusCode)
            }
            let items = try decodeListItems(from: data)
            if !items.isEmpty { listCache[listId] = (items: items, timestamp: Date()) }
            return items
        }
        
        // Check in-memory cache
        if let cached = listCache[listId],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.items
        }
        
        let resolvedPath = await resolveListPath(from: listId)
        print("MDBList resolved path: \(resolvedPath) from input: \(listId)")
        
        // Try the public JSON export endpoint first (no API key needed, flat array)
        // Format: https://mdblist.com/lists/username/listname/json
        let encodedListId = resolvedPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resolvedPath
        let publicURLString = "https://mdblist.com/lists/\(encodedListId)/json"
        print("MDBList public URL: \(publicURLString)")
        
        guard let publicURL = URL(string: publicURLString) else {
            throw MDBListError.invalidURL
        }
        
        var request = URLRequest(url: publicURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MDBListError.networkError
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyPreview = String(data: data, encoding: .utf8) ?? ""
            print("MDBList public export failed (\(httpResponse.statusCode)): \(bodyPreview.prefix(300)) — falling back to API")
            // Fallback: try the API endpoint with key
            return try await getListItemsViaAPI(listId: listId, resolvedPath: resolvedPath)
        }
        
        let items = try decodeListItems(from: data)
        
        // Cache the result
        if !items.isEmpty {
            listCache[listId] = (items: items, timestamp: Date())
        }
        
        return items
    }
    
    /// Fallback: use the API endpoint with apikey parameter
    private func getListItemsViaAPI(listId: String, resolvedPath: String? = nil) async throws -> [MDBListItem] {
        let pathId = (resolvedPath ?? listId)
        let encodedListId = pathId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pathId

        // Try multiple endpoint variants in order
        let paths = [
            "/lists/\(encodedListId)/items",   // plural
            "/list/\(encodedListId)/items",    // singular (in case docs differ)
            "/lists/\(encodedListId)/json"     // legacy json path under API (unlikely, but try)
        ]

        // Try both auth mechanisms: query apikey and Authorization header
        enum AuthStyle { case query, header }
        let authStyles: [AuthStyle] = [.query, .header]

        var lastError: (code: Int, body: String)? = nil

        for path in paths {
            for style in authStyles {
                var components = URLComponents(string: "\(baseURL)\(path)")!
                if style == .query {
                    components.queryItems = [URLQueryItem(name: "apikey", value: apiKey)]
                }
                guard let url = components.url else { continue }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 15
                if style == .header {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }

                print("MDBList API URL: \(url.absoluteString) [auth=\(style == .query ? "query" : "header")]")

                do {
                    let (data, response) = try await session.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continue
                    }

                    if (200...299).contains(httpResponse.statusCode) {
                        // Decode
                        do {
                            let items = try decodeListItems(from: data)
                            if !items.isEmpty {
                                listCache[listId] = (items: items, timestamp: Date())
                                return items
                            }
                        } catch {
                            // Try next variant
                            let bodyPreview = String(data: data, encoding: .utf8) ?? ""
                            print("MDBList decode error on \(path): \(error) body: \(bodyPreview.prefix(200))")
                        }
                    } else {
                        let body = String(data: data, encoding: .utf8) ?? ""
                        lastError = (httpResponse.statusCode, body)
                        print("MDBList API error \(httpResponse.statusCode) on \(path): \(body.prefix(300))")
                    }
                } catch {
                    print("MDBList request failed for \(path): \(error)")
                    continue
                }
            }
        }

        if let last = lastError {
            throw MDBListError.apiError(last.code)
        } else {
            throw MDBListError.invalidList
        }
    }
    
    /// Decode list items supporting multiple response formats:
    /// 1. Flat array: [{ "id": 123, "title": "...", ... }]
    /// 2. Wrapped: { "movies": [...], "shows": [...] }
    private func decodeListItems(from data: Data) throws -> [MDBListItem] {
        // First try: flat array (public /json endpoint format)
        if let items = try? JSONDecoder().decode([MDBListItem].self, from: data), !items.isEmpty {
            return items
        }
        
        // Second try: wrapped { "movies": [...], "shows": [...] } (API endpoint format)
        if let wrapped = try? JSONDecoder().decode(MDBListWrappedResponse.self, from: data) {
            var combined: [MDBListItem] = []
            combined.append(contentsOf: wrapped.movies ?? [])
            combined.append(contentsOf: wrapped.shows ?? [])
            if !combined.isEmpty {
                return combined
            }
        }
        
        // Third try: snake_case decoding for flat array
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let items = try? decoder.decode([MDBListItem].self, from: data), !items.isEmpty {
            return items
        }
        
        // Fourth try: snake_case decoding for wrapped response
        if let wrapped = try? decoder.decode(MDBListWrappedResponse.self, from: data) {
            var combined: [MDBListItem] = []
            combined.append(contentsOf: wrapped.movies ?? [])
            combined.append(contentsOf: wrapped.shows ?? [])
            if !combined.isEmpty {
                return combined
            }
        }
        
        // Fifth try: { "items": [...] }
        struct ItemsWrapper: Codable { let items: [MDBListItem]? }
        if let iw = try? JSONDecoder().decode(ItemsWrapper.self, from: data),
           let arr = iw.items, !arr.isEmpty {
            return arr
        }
        
        // Additional try: wrapped with "items" key
        /*
        struct ItemsWrapper: Codable {
            let items: [MDBListItem]?
        }
        if let iw = try? JSONDecoder().decode(ItemsWrapper.self, from: data),
           let arr = iw.items, !arr.isEmpty {
            return arr
        }
        */
        // If nothing worked, throw
        throw MDBListError.invalidList
    }

    private func resolveMDBListMediaType(_ rawValue: String?) -> MediaType {
        let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if normalized == "show" || normalized == "tv" || normalized == "series" {
            return .tv
        }
        return .movie
    }
    
    // MARK: - Ratings Lookup
    
    /// Fetch ratings from MDBList by TMDB ID.
    /// Returns aggregated scores from IMDb, Rotten Tomatoes, Metacritic, Letterboxd, Trakt, etc.
    func getRatings(tmdbId: Int, mediaType: MediaType) async throws -> MDBListMediaInfo {
        guard !apiKey.isEmpty else { throw MDBListError.notConfigured }
        
        // Check in-memory cache
        let cacheKey = "ratings-\(mediaType.rawValue)-\(tmdbId)"
        if let cached = ratingsCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.info
        }
        
        var urlString = "https://mdblist.com/api/?apikey=\(apiKey)&tm=\(tmdbId)"
        if mediaType == .tv {
            urlString += "&m=show"
        }
        
        guard let url = URL(string: urlString) else {
            throw MDBListError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MDBListError.networkError
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MDBListError.apiError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let info = try decoder.decode(MDBListMediaInfo.self, from: data)
        
        // Cache the result
        ratingsCache[cacheKey] = (info: info, timestamp: Date())
        
        return info
    }
    
    /// Convenience: get a RatingsSummary from MDBList for the detail page.
    /// Falls back to nil on any error so the view model can try OMDb.
    func getRatingsSummary(tmdbId: Int, mediaType: MediaType) async -> RatingsSummary? {
        do {
            let info = try await getRatings(tmdbId: tmdbId, mediaType: mediaType)
            return RatingsSummary(from: info)
        } catch {
            print("MDBList ratings error: \(error)")
            return nil
        }
    }
    
    // In-memory cache for ratings
    private var ratingsCache: [String: (info: MDBListMediaInfo, timestamp: Date)] = [:]
    
    // MARK: - Convenience Methods
    
    /// Fetch list items and convert to MediaItem format (for hero carousel, etc.)
    func fetchListItemsAsMediaItems(listId: String, limit: Int? = nil) async throws -> [MediaItem] {
        let items = try await getListItems(listId: listId)
        var mediaItems: [MediaItem] = []
        
        let sequence = (limit != nil) ? Array(items.prefix(limit!)) : items
        for item in sequence {
            if let tmdbId = item.id, tmdbId > 0 {
                do {
                    let mediaType = resolveMDBListMediaType(item.mediatype)
                    
                    if mediaType == .movie {
                        let details = try await TMDBService.shared.getMovieDetails(id: tmdbId)
                        let mi = MediaItem(
                            id: details.id,
                            title: details.title,
                            name: nil,
                            originalTitle: details.originalTitle,
                            originalName: nil,
                            overview: details.overview,
                            posterPath: details.posterPath,
                            backdropPath: details.backdropPath,
                            releaseDate: details.releaseDate,
                            firstAirDate: nil,
                            voteAverage: details.voteAverage,
                            voteCount: nil,
                            popularity: nil,
                            genreIds: nil,
                            mediaType: "movie",
                            adult: nil,
                            originalLanguage: nil
                        )
                        mediaItems.append(mi)
                    } else {
                        let details = try await TMDBService.shared.getTVShowDetails(id: tmdbId)
                        let mi = MediaItem(
                            id: details.id,
                            title: nil,
                            name: details.name,
                            originalTitle: nil,
                            originalName: details.originalName,
                            overview: details.overview,
                            posterPath: details.posterPath,
                            backdropPath: details.backdropPath,
                            releaseDate: nil,
                            firstAirDate: details.firstAirDate,
                            voteAverage: details.voteAverage,
                            voteCount: nil,
                            popularity: nil,
                            genreIds: nil,
                            mediaType: "tv",
                            adult: nil,
                            originalLanguage: nil
                        )
                        mediaItems.append(mi)
                    }
                } catch {
                    // Fall back to basic item from MDBList data
                    if let basicItem = item.toSavedMediaItem() {
                        mediaItems.append(basicItem.asMediaItem())
                    }
                }
            } else if let basicItem = item.toSavedMediaItem() {
                mediaItems.append(basicItem.asMediaItem())
            }
        }
        
        return mediaItems
    }
    
    /// Fetch list items and convert to app's SavedMediaItem format
    func fetchListItemsAsSavedMedia(listId: String, limit: Int? = nil) async throws -> [SavedMediaItem] {
        let items = try await getListItems(listId: listId)
        var savedItems: [SavedMediaItem] = []
        
        let sequence = (limit != nil) ? Array(items.prefix(limit!)) : items
        for item in sequence {
            // Try to look up in TMDB for full details
            if let tmdbId = item.id, tmdbId > 0 {
                do {
                    let mediaType = resolveMDBListMediaType(item.mediatype)
                    
                    if mediaType == .movie {
                        let details = try await TMDBService.shared.getMovieDetails(id: tmdbId)
                        savedItems.append(SavedMediaItem(from: details))
                    } else {
                        let details = try await TMDBService.shared.getTVShowDetails(id: tmdbId)
                        savedItems.append(SavedMediaItem(from: details))
                    }
                } catch {
                    // Create basic saved item from MDBList data
                    if let savedItem = item.toSavedMediaItem() {
                        savedItems.append(savedItem)
                    }
                }
            } else if let savedItem = item.toSavedMediaItem() {
                savedItems.append(savedItem)
            }
        }
        
        return savedItems
    }
    
    /// Parse list ID from URL or return as-is
    nonisolated func parseListId(from input: String) -> String {
        var id = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return id }

        // If it's a URL, extract username/slug after /lists/
        if id.lowercased().contains("mdblist.com/lists/") {
            if let url = URL(string: id), let host = url.host, host.contains("mdblist.com") {
                let pathComponents = url.pathComponents.filter { $0 != "/" }
                if let listsIndex = pathComponents.firstIndex(of: "lists"), listsIndex + 2 < pathComponents.count {
                    let username = pathComponents[listsIndex + 1]
                    let listname = pathComponents[listsIndex + 2]
                    return "\(username)/\(listname)"
                }
            } else {
                // Fallback simple parsing for malformed URL strings
                if let range = id.range(of: "/lists/") {
                    let tail = id[range.upperBound...]
                    let parts = tail.split(separator: "/").map(String.init)
                    if parts.count >= 2 {
                        return "\(parts[0])/\(parts[1])"
                    }
                }
            }
        }

        // Already username/slug
        if id.contains("/") { return id }

        return id
    }
    
    // MARK: - Search Lists
    
    /// Search public MDBList lists by query string.
    func searchLists(query: String) async throws -> [MDBListSearchResult] {
        guard !apiKey.isEmpty else { throw MDBListError.notConfigured }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(baseURL)/lists/search?s=\(encoded)&apikey=\(apiKey)"
        
        guard let url = URL(string: urlString) else { throw MDBListError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else { throw MDBListError.networkError }
        guard (200...299).contains(httpResponse.statusCode) else { throw MDBListError.apiError(httpResponse.statusCode) }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        // The search endpoint returns an array of list objects
        let results = try decoder.decode([MDBListSearchResult].self, from: data)
        return results
    }
    
    /// Get top/popular MDBList lists.
    func getTopLists() async throws -> [MDBListSearchResult] {
        guard !apiKey.isEmpty else { throw MDBListError.notConfigured }
        
        let urlString = "\(baseURL)/lists/top?apikey=\(apiKey)"
        
        guard let url = URL(string: urlString) else { throw MDBListError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else { throw MDBListError.networkError }
        guard (200...299).contains(httpResponse.statusCode) else { throw MDBListError.apiError(httpResponse.statusCode) }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let results = try decoder.decode([MDBListSearchResult].self, from: data)
        return results
    }
    
    // MARK: - New Convenience Methods for Multiple Lists
    
    /// Combine multiple MDBList inputs (URLs or username/slug) into a single array of SavedMediaItem.
    /// - Parameters:
    ///   - inputs: Array of list identifiers or full URLs
    ///   - perListLimit: Optional cap per list before merging (nil = all)
    ///   - totalLimit: Optional cap after merging (nil = all)
    ///   - preferTMDBDetails: If true, attempts TMDB lookups for richer data; otherwise uses MDBList basics
    func fetchMultipleListsAsSavedMedia(inputs: [String], perListLimit: Int? = nil, totalLimit: Int? = nil, preferTMDBDetails: Bool = true) async throws -> [SavedMediaItem] {
        var combined: [SavedMediaItem] = []
        var seenKeys = Set<String>() // mediaType-mediaId

        for input in inputs {
            // Use public JSON export when input is a URL to avoid rate limiting
            let items: [MDBListItem]
            if input.lowercased().contains("mdblist.com/lists/") {
                items = try await getListItemsFromURL(input)
            } else {
                items = try await getListItems(listId: input)
            }
            let sequence = (perListLimit != nil) ? Array(items.prefix(perListLimit!)) : items

            for item in sequence {
                // If we have a TMDB id, we can optionally enrich
                if preferTMDBDetails, let tmdbId = item.id, tmdbId > 0 {
                    let mediaType = resolveMDBListMediaType(item.mediatype)
                    do {
                        if mediaType == .movie {
                            let details = try await TMDBService.shared.getMovieDetails(id: tmdbId)
                            let saved = SavedMediaItem(from: details)
                            let key = "\(saved.mediaType.rawValue)-\(saved.mediaId)"
                            if !seenKeys.contains(key) {
                                seenKeys.insert(key)
                                combined.append(saved)
                            }
                        } else {
                            let details = try await TMDBService.shared.getTVShowDetails(id: tmdbId)
                            let saved = SavedMediaItem(from: details)
                            let key = "\(saved.mediaType.rawValue)-\(saved.mediaId)"
                            if !seenKeys.contains(key) {
                                seenKeys.insert(key)
                                combined.append(saved)
                            }
                        }
                    } catch {
                        if let basic = item.toSavedMediaItem() {
                            let key = "\(basic.mediaType.rawValue)-\(basic.mediaId)"
                            if !seenKeys.contains(key) {
                                seenKeys.insert(key)
                                combined.append(basic)
                            }
                        }
                    }
                } else if let basic = item.toSavedMediaItem() {
                    let key = "\(basic.mediaType.rawValue)-\(basic.mediaId)"
                    if !seenKeys.contains(key) {
                        seenKeys.insert(key)
                        combined.append(basic)
                    }
                }

                if let totalLimit, combined.count >= totalLimit { return combined }
            }
        }

        return combined
    }
    
    /// Combine multiple MDBList inputs (URLs or username/slug) into a single array of MediaItem.
    /// - Parameters:
    ///   - inputs: Array of list identifiers or full URLs
    ///   - perListLimit: Optional cap per list before merging (nil = all)
    ///   - totalLimit: Optional cap after merging (nil = all)
    ///   - preferTMDBDetails: If true, attempts TMDB lookups for richer data; otherwise uses MDBList basics
    func fetchMultipleListsAsMediaItems(inputs: [String], perListLimit: Int? = nil, totalLimit: Int? = nil, preferTMDBDetails: Bool = true) async throws -> [MediaItem] {
        let saved = try await fetchMultipleListsAsSavedMedia(inputs: inputs, perListLimit: perListLimit, totalLimit: totalLimit, preferTMDBDetails: preferTMDBDetails)
        return saved.map { $0.asMediaItem() }
    }

    /// Convenience: load exactly two lists (IDs or URLs) and merge into a single array of SavedMediaItem.
    /// - Parameters:
    ///   - first: First list identifier or full URL
    ///   - second: Second list identifier or full URL
    ///   - perListLimit: Optional cap per list before merging (nil = all)
    ///   - totalLimit: Optional cap after merging (nil = all)
    ///   - preferTMDBDetails: If true, attempts TMDB lookups for richer data; otherwise uses MDBList basics
    /// - Returns: De-duplicated merged SavedMediaItem array
    func fetchTwoListsAsSavedMedia(first: String, second: String, perListLimit: Int? = nil, totalLimit: Int? = nil, preferTMDBDetails: Bool = true) async throws -> [SavedMediaItem] {
        return try await fetchMultipleListsAsSavedMedia(
            inputs: [first, second],
            perListLimit: perListLimit,
            totalLimit: totalLimit,
            preferTMDBDetails: preferTMDBDetails
        )
    }

    /// Convenience: load exactly two lists (IDs or URLs) and merge into a single array of MediaItem.
    /// - Parameters:
    ///   - first: First list identifier or full URL
    ///   - second: Second list identifier or full URL
    ///   - perListLimit: Optional cap per list before merging (nil = all)
    ///   - totalLimit: Optional cap after merging (nil = all)
    ///   - preferTMDBDetails: If true, attempts TMDB lookups for richer data; otherwise uses MDBList basics
    /// - Returns: De-duplicated merged MediaItem array
    func fetchTwoListsAsMediaItems(first: String, second: String, perListLimit: Int? = nil, totalLimit: Int? = nil, preferTMDBDetails: Bool = true) async throws -> [MediaItem] {
        let saved = try await fetchTwoListsAsSavedMedia(
            first: first,
            second: second,
            perListLimit: perListLimit,
            totalLimit: totalLimit,
            preferTMDBDetails: preferTMDBDetails
        )
        return saved.map { $0.asMediaItem() }
    }
}

// MARK: - MDBList Response Models

/// Wrapped response format from MDBList API: { "movies": [...], "shows": [...] }
struct MDBListWrappedResponse: Codable {
    let movies: [MDBListItem]?
    let shows: [MDBListItem]?
}

/// Item from MDBList JSON export
/// Supports both flat array and wrapped response fields:
/// - `id` = TMDB ID
/// - `year` or `release_year` = release year
/// - `imdb_id` = IMDb ID
/// - `tvdb_id` = TVDB ID
/// - `mediatype` = "movie" or "show"
struct MDBListItem: Codable, Identifiable {
    let id: Int?
    let title: String?
    let year: Int?
    let releaseYear: Int?
    let imdbId: String?
    let tvdbId: Int?
    let mediatype: String?
    let rank: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, title, year, rank, mediatype
        case releaseYear = "release_year"
        case imdbId = "imdb_id"
        case tvdbId = "tvdb_id"
    }
    
    /// Resolved year from either `year` or `release_year`
    var resolvedYear: Int? {
        year ?? releaseYear
    }
    
    func toSavedMediaItem() -> SavedMediaItem? {
        guard let title = title, let itemId = id, itemId > 0 else { return nil }
        
        let normalized = mediatype?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let type: MediaType = (normalized == "show" || normalized == "tv" || normalized == "series") ? .tv : .movie
        let yearStr = resolvedYear.map { "\($0)" }
        
        let mediaItem = MediaItem(
            id: itemId,
            title: type == .movie ? title : nil,
            name: type == .tv ? title : nil,
            originalTitle: nil,
            originalName: nil,
            overview: nil,
            posterPath: nil,
            backdropPath: nil,
            releaseDate: yearStr,
            firstAirDate: yearStr,
            voteAverage: nil,
            voteCount: nil,
            popularity: nil,
            genreIds: nil,
            mediaType: type.rawValue,
            adult: nil,
            originalLanguage: nil
        )
        
        return SavedMediaItem(from: mediaItem)
    }
}

// MARK: - MDBList Media Info (ratings response)

struct MDBListMediaInfo: Codable {
    let title: String?
    let year: Int?
    let imdbid: String?
    let traktid: Int?
    let tmdbid: Int?
    let score: Int?
    let ratings: [MDBListRating]?
    
    enum CodingKeys: String, CodingKey {
        case title, year, imdbid, traktid, tmdbid, score, ratings
    }
}

struct MDBListRating: Codable {
    let source: String
    let value: Double?
    let score: Int?
    let votes: Int?
    let url: String?
}

// MARK: - RatingsSummary from MDBList

extension RatingsSummary {
    /// Build a RatingsSummary from MDBList media-info ratings array.
    init?(from info: MDBListMediaInfo) {
        guard let ratings = info.ratings, !ratings.isEmpty else { return nil }
        
        // IMDb
        let imdb = ratings.first { $0.source == "imdb" }
        self.imdbRating = imdb.flatMap { r in r.value.map { String(format: "%.1f", $0) } }
        self.imdbVotes = imdb.flatMap { r in r.votes.map { formatVotes($0) } }
        
        // Rotten Tomatoes (critics)
        let rt = ratings.first { $0.source == "tomatoes" }
        self.rottenTomatoesScore = rt.flatMap { r in r.score.map { "\($0)%" } }
        
        // Rotten Tomatoes (audience)
        let rtAudience = ratings.first { $0.source == "tomatoesaudience" }
        self.rottenTomatoesAudienceScore = rtAudience.flatMap { r in r.score.map { "\($0)%" } }
        
        // Metacritic
        let meta = ratings.first { $0.source == "metacritic" }
        self.metacriticScore = meta.flatMap { r in r.score.map { "\($0)/100" } }
    }
}

/// Format vote counts to a human-readable string (e.g., 12345 → "12,345")
private func formatVotes(_ votes: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: votes)) ?? "\(votes)"
}

// MARK: - MDBList Search Result

struct MDBListSearchResult: Codable, Identifiable {
    let id: Int
    let name: String?
    let slug: String?
    let items: Int?
    let likes: Int?
    let username: String?
    let description: String?
    let mediatype: String?
    
    /// The list path used to fetch items (username/slug)
    var listPath: String {
        if let username = username, let slug = slug {
            return "\(username)/\(slug)"
        }
        return slug ?? "\(id)"
    }
    
    var displayName: String {
        name ?? slug ?? "Untitled"
    }
    
    var itemCount: Int {
        items ?? 0
    }
    
    var likeCount: Int {
        likes ?? 0
    }
}

// MARK: - Errors

enum MDBListError: LocalizedError {
    case notConfigured
    case invalidURL
    case networkError
    case invalidList
    case apiError(Int)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "MDBList not configured"
        case .invalidURL:
            return "Invalid URL"
        case .networkError:
            return "Network error"
        case .invalidList:
            return "Invalid list ID"
        case .apiError(let code):
            return "API error: \(code)"
        }
    }
}

// MARK: - SavedMediaItem extension for conversion
extension SavedMediaItem {
    func asMediaItem() -> MediaItem {
        MediaItem(
            id: mediaId,
            title: mediaType == .movie ? title : nil,
            name: mediaType == .tv ? title : nil,
            originalTitle: nil,
            originalName: nil,
            overview: overview,
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseDate: year,
            firstAirDate: year,
            voteAverage: voteAverage,
            voteCount: nil,
            popularity: nil,
            genreIds: nil,
            mediaType: mediaType.rawValue,
            adult: nil,
            originalLanguage: nil
        )
    }
}
