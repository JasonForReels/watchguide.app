//
//  ImagePrefetchService.swift
//  WatchGuide-MovieandTVtracker
//
//  Lightweight image prefetching to warm URLCache for upcoming poster/backdrop images
//

import Foundation

actor ImagePrefetchService {
    static let shared = ImagePrefetchService()
    
    // Shared session with aggressive caching
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 80 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()
    
    private var prefetchedURLs = Set<String>()
    private var activeTasks = Set<String>()
    
    private init() {}
    
    /// Prefetch an array of image URLs in the background.
    /// Already-prefetched URLs are skipped.
    nonisolated func prefetch(urls: [URL?]) {
        let validURLs = urls.compactMap { $0 }
        guard !validURLs.isEmpty else { return }
        
        Task {
            await self._prefetch(validURLs)
        }
    }
    
    private func _prefetch(_ urls: [URL]) {
        for url in urls {
            let key = url.absoluteString
            guard !prefetchedURLs.contains(key), !activeTasks.contains(key) else { continue }
            activeTasks.insert(key)
            
            Task {
                do {
                    let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
                    let _ = try await session.data(for: request)
                    prefetchedURLs.insert(key)
                } catch {
                    // Silently fail — prefetch is best-effort
                }
                activeTasks.remove(key)
            }
        }
        
        // Limit memory of tracked URLs
        if prefetchedURLs.count > 2000 {
            prefetchedURLs.removeAll()
        }
    }
    
    /// Convenience: prefetch poster images for a list of media items
    nonisolated func prefetchPosters(for items: [MediaItem], size: TMDBService.ImageSize = .medium) {
        let urls = items.compactMap { TMDBService.shared.imageURL(path: $0.posterPath, size: size) }
        prefetch(urls: urls)
    }
    
    /// Convenience: prefetch backdrop images for a list of media items
    nonisolated func prefetchBackdrops(for items: [MediaItem], size: TMDBService.ImageSize = .backdropSmall) {
        let urls = items.compactMap { TMDBService.shared.imageURL(path: $0.backdropPath, size: size) }
        prefetch(urls: urls)
    }
}
