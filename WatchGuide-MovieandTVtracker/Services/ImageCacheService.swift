//
//  ImageCacheService.swift
//  WatchGuide-MovieandTVtracker
//
//  Shared decoded-image cache and downloader for poster/backdrop artwork.
//
//  Posters are the single most repeated network+CPU cost in the app: the same
//  URL is requested every time a cell scrolls back into view, and `UIImage(data:)`
//  defers its decode to the first draw — on the main thread. This service holds
//  fully decoded, display-ready images in memory and does all download + decode
//  work off the main actor, so a revisited poster renders on the very next frame
//  with no network call at all.
//

import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

// MARK: - Decoded Image Memory Cache

/// In-memory cache of decoded, display-ready images keyed by URL + target size.
final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()

    private let cache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        // Costs are tracked in bytes; ~150 MB holds several screens of posters.
        cache.totalCostLimit = 150 * 1024 * 1024
        cache.countLimit = 800
        return cache
    }()

    private init() {
        #if canImport(UIKit) && !os(tvOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
        #endif
    }

    /// Cache keys fold in the decode size, so a thumbnail and a full-size decode
    /// of the same URL never collide.
    static func key(for url: URL, maxPixelSize: CGFloat?) -> NSString {
        let size = maxPixelSize.map { Int($0.rounded()) } ?? 0
        return "\(url.absoluteString)|\(size)" as NSString
    }

    func image(for url: URL, maxPixelSize: CGFloat?) -> PlatformImage? {
        cache.object(forKey: Self.key(for: url, maxPixelSize: maxPixelSize))
    }

    func insert(_ image: PlatformImage, for url: URL, maxPixelSize: CGFloat?) {
        cache.setObject(
            image,
            forKey: Self.key(for: url, maxPixelSize: maxPixelSize),
            cost: image.approximateByteCost
        )
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

private extension PlatformImage {
    /// Rough decoded footprint (4 bytes per pixel) used as the NSCache cost.
    var approximateByteCost: Int {
        #if canImport(UIKit)
        let pixels = size.width * scale * size.height * scale
        #else
        let pixels = size.width * size.height
        #endif
        return max(Int(pixels) * 4, 1)
    }
}

// MARK: - Image Downloader

/// Downloads and decodes artwork off the main actor, coalescing duplicate
/// requests for the same URL so a row of identical placeholders only fetches once.
actor ImageDownloader {
    static let shared = ImageDownloader()

    /// Artwork all comes from a handful of CDN hosts, so the per-host connection
    /// limit is what actually gates how fast a screen of posters fills in.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 400 * 1024 * 1024
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        // Fail fast rather than leaving a poster shimmering for half a minute.
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        config.httpMaximumConnectionsPerHost = 12
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private var inFlight: [NSString: Task<PlatformImage, Error>] = [:]

    private init() {}

    /// Returns a decoded image, from memory if possible, otherwise downloading it.
    /// `maxPixelSize` downsamples during decode — pass the on-screen size in pixels.
    func image(for url: URL, maxPixelSize: CGFloat? = nil) async throws -> PlatformImage {
        if let cached = ImageMemoryCache.shared.image(for: url, maxPixelSize: maxPixelSize) {
            return cached
        }

        let key = ImageMemoryCache.key(for: url, maxPixelSize: maxPixelSize)
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let session = self.session
        let task = Task<PlatformImage, Error> {
            let request = URLRequest(
                url: url,
                cachePolicy: .returnCacheDataElseLoad,
                timeoutInterval: 12
            )

            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            guard let image = Self.decode(data: data, maxPixelSize: maxPixelSize) else {
                throw URLError(.cannotDecodeContentData)
            }

            ImageMemoryCache.shared.insert(image, for: url, maxPixelSize: maxPixelSize)
            return image
        }

        inFlight[key] = task

        do {
            let image = try await task.value
            inFlight[key] = nil
            return image
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    /// Warms the cache without a caller waiting on the result.
    nonisolated func prefetch(_ urls: [URL], maxPixelSize: CGFloat? = nil) {
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask {
                        _ = try? await ImageDownloader.shared.image(for: url, maxPixelSize: maxPixelSize)
                    }
                }
            }
        }
    }

    // MARK: - Decoding

    /// Decodes fully (and downsamples when a target size is given) so the image
    /// handed to SwiftUI needs no further work on the main thread at draw time.
    private static func decode(data: Data, maxPixelSize: CGFloat?) -> PlatformImage? {
        if let maxPixelSize, maxPixelSize > 0,
           let downsampled = downsample(data: data, maxPixelSize: maxPixelSize) {
            return downsampled
        }

        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return image.preparingForDisplay() ?? image
        #else
        return NSImage(data: data)
        #endif
    }

    private static func downsample(data: Data, maxPixelSize: CGFloat) -> PlatformImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded())
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #else
        return NSImage(cgImage: cgImage, size: .zero)
        #endif
    }
}
