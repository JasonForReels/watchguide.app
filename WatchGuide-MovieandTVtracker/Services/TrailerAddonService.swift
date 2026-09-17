//
//  TrailerAddonService.swift
//  WatchGuide-MovieandTVtracker
//
//  Fetches trailer streams from Stremio-compatible add-on endpoints (e.g. Trailerio).
//

import Foundation

actor TrailerAddonService {
    static let shared = TrailerAddonService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    /// Fetches direct-playback trailer `Video` objects from the given add-ons.
    func fetchTrailers(imdbID: String, mediaType: MediaType, addons: [TrailerAddon]) async -> [Video] {
        var allVideos: [Video] = []

        await withTaskGroup(of: [Video].self) { group in
            for addon in addons where addon.isEnabled {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    return await self.fetchFromAddon(addon, imdbID: imdbID, mediaType: mediaType)
                }
            }
            for await videos in group {
                allVideos.append(contentsOf: videos)
            }
        }

        return allVideos
    }

    /// Validates that a base URL points to a working Stremio add-on manifest.
    /// Returns a `TrailerAddon` with the resolved name on success.
    func validateAddon(baseURLString: String, fallbackName: String) async throws -> TrailerAddon {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Strip manifest.json suffix to get the canonical base URL,
        // then always append it for the fetch — handles both bare base URLs and full manifest URLs.
        let baseURL = trimmed.hasSuffix("/manifest.json")
            ? String(trimmed.dropLast("/manifest.json".count))
            : trimmed

        let manifestURLString = "\(baseURL)/manifest.json"
        guard let manifestURL = URL(string: manifestURLString) else {
            throw AddonError.invalidURL
        }

        let (data, response) = try await session.data(from: manifestURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AddonError.networkError
        }

        let manifest = try JSONDecoder().decode(AddonManifest.self, from: data)

        // Verify the addon declares meta resource support with IMDB tt IDs
        guard manifest.supportsMetaWithIMDB else {
            throw AddonError.incompatibleAddon
        }

        let resolvedName = manifest.name ?? fallbackName

        return TrailerAddon(
            name: resolvedName,
            baseURL: baseURL,
            isEnabled: true
        )
    }

    // MARK: - Private

    private func fetchFromAddon(_ addon: TrailerAddon, imdbID: String, mediaType: MediaType) async -> [Video] {
        let typeString = mediaType == .movie ? "movie" : "series"
        let base = addon.baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/manifest.json", with: "")

        // Try the meta endpoint first (used by Trailerio and similar addons)
        if let metaVideos = await fetchMetaTrailers(base: base, typeString: typeString, imdbID: imdbID, addon: addon),
           !metaVideos.isEmpty {
            return metaVideos
        }

        // Fall back to the Stremio stream endpoint for other addons
        return await fetchStreamTrailers(base: base, typeString: typeString, imdbID: imdbID, addon: addon)
    }

    /// Fetches trailers from a Stremio meta endpoint (`/meta/<type>/<id>.json`).
    /// Trailerio returns `meta.links[]` with `trailers` (URL) and `provider` (label).
    private func fetchMetaTrailers(base: String, typeString: String, imdbID: String, addon: TrailerAddon) async -> [Video]? {
        let urlString = "\(base)/meta/\(typeString)/\(imdbID).json"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let metaResponse = try JSONDecoder().decode(MetaResponse.self, from: data)
            guard let links = metaResponse.meta.links, !links.isEmpty else { return nil }

            return links.compactMap { link -> Video? in
                guard let streamURL = link.streamURL, !streamURL.isEmpty,
                      !Self.isYouTubeURL(streamURL) else { return nil }
                let label = link.displayName ?? addon.name

                return Video(
                    id: "addon-\(addon.id)-\(streamURL.hashValue)",
                    key: streamURL,
                    name: label,
                    site: "Direct",
                    type: "Trailer",
                    official: nil,
                    publishedAt: nil,
                    sourceLabel: addon.name
                )
            }
        } catch {
            return nil
        }
    }

    /// Fetches trailers from a Stremio stream endpoint (`/stream/<type>/<id>.json`).
    private func fetchStreamTrailers(base: String, typeString: String, imdbID: String, addon: TrailerAddon) async -> [Video] {
        let urlString = "\(base)/stream/\(typeString)/\(imdbID).json"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }

            let streamResponse = try JSONDecoder().decode(StreamResponse.self, from: data)

            return streamResponse.streams.compactMap { stream -> Video? in
                guard let streamURL = stream.url ?? stream.externalUrl,
                      !streamURL.isEmpty,
                      !Self.isYouTubeURL(streamURL) else { return nil }

                return Video(
                    id: "addon-\(addon.id)-\(streamURL.hashValue)",
                    key: streamURL,
                    name: stream.title ?? stream.name ?? "Trailer",
                    site: "Direct",
                    type: "Trailer",
                    official: nil,
                    publishedAt: nil,
                    sourceLabel: addon.name
                )
            }
        } catch {
            return []
        }
    }

    private static func isYouTubeURL(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return host.contains("youtube.com") || host.contains("youtu.be") || host.contains("youtube-nocookie.com")
    }

    // MARK: - Models

    enum AddonError: LocalizedError {
        case invalidURL
        case networkError
        case incompatibleAddon

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "The URL is not valid."
            case .networkError: return "Could not reach the add-on server."
            case .incompatibleAddon: return "This add-on doesn't support the trailer meta resource with IMDB IDs."
            }
        }
    }

    private struct AddonManifest: Codable {
        let name: String?
        // Stremio resources can be plain strings OR objects — handle both.
        let resources: [FlexibleResource]?
        let idPrefixes: [String]?

        var supportsMetaWithIMDB: Bool {
            guard let resources else { return false }
            return resources.contains { res in
                res.name == "meta" && (res.idPrefixes?.contains("tt") ?? true)
            }
        }
    }

    private struct FlexibleResource: Codable {
        let name: String
        let idPrefixes: [String]?

        init(from decoder: Decoder) throws {
            // Accept both `"meta"` (string) and `{"name":"meta","idPrefixes":["tt"]}` (object)
            if let str = try? decoder.singleValueContainer().decode(String.self) {
                name = str
                idPrefixes = nil
            } else {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                idPrefixes = try c.decodeIfPresent([String].self, forKey: .idPrefixes)
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(idPrefixes, forKey: .idPrefixes)
        }

        private enum CodingKeys: String, CodingKey { case name, idPrefixes }
    }

    private struct MetaResponse: Codable {
        let meta: MetaContent
    }

    private struct MetaContent: Codable {
        let links: [MetaLink]?
    }

    private struct MetaLink: Codable {
        // Trailerio uses "trailers"/"provider"; standard Stremio uses "url"/"name"
        let trailers: String?
        let url: String?
        let provider: String?
        let name: String?

        var streamURL: String? { trailers ?? url }
        var displayName: String? { provider ?? name }
    }

    private struct StreamResponse: Codable {
        let streams: [StreamItem]
    }

    private struct StreamItem: Codable {
        let url: String?
        let externalUrl: String?
        let title: String?
        let name: String?
    }
}
