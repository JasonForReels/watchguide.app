#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

public struct ReleaseActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic data that can change during the release window
        public var releaseStatus: String // e.g. "Coming Soon", "Out Now!", "1 Hour Left"
        public var progress: Double // 0.0 to 1.0 (e.g. for a progress bar on the big day)
        
        public init(releaseStatus: String, progress: Double = 0.0) {
            self.releaseStatus = releaseStatus
            self.progress = progress
        }
    }

    // Static data about the media
    public var mediaTitle: String
    public var releaseDate: Date
    public var mediaType: String // "Movie" or "TV"
    
    public init(mediaTitle: String, releaseDate: Date, mediaType: String) {
        self.mediaTitle = mediaTitle
        self.releaseDate = releaseDate
        self.mediaType = mediaType
    }
}
#endif
