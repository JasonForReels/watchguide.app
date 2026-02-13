import SwiftUI

// MARK: - Trailer Thumbnail Card (Inline embedded player)
// Shows an embedded YouTube player that autoplays muted with custom unmute button.
// Falls back to thumbnail + sheet on error.

struct TrailerThumbnailCard: View {
    let video: Video
    var compact: Bool = false
    
    var body: some View {
        EmbeddedTrailerPlayer(
            videoKey: video.key,
            title: video.name,
            compact: compact
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

// MARK: - Legacy WebTrailerPlayerView
struct WebTrailerPlayerView: View {
    let videoKey: String
    var autoplay: Bool = false
    var muted: Bool = true
    
    var body: some View {
        EmbeddedTrailerPlayer(
            videoKey: videoKey,
            title: "Trailer"
        )
    }
}

