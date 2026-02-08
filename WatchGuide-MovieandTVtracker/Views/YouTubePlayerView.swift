//
//  YouTubePlayerView.swift
//  WatchGuide-MovieandTVtracker
//
//  Replaced embedded WKWebView with a simple thumbnail + tap-to-open approach.
//  No more WebKit errors. Users tap play → opens YouTube app or Safari.

import SwiftUI

// Legacy compatibility wrapper — now just renders a TrailerThumbnailCard
struct YouTubePlayerView: View {
    let videoKey: String
    var autoPlay: Bool = false
    var isMuted: Bool = false
    
    var body: some View {
        let video = Video(
            id: videoKey,
            key: videoKey,
            name: "Trailer",
            site: "YouTube",
            type: "Trailer",
            official: true,
            publishedAt: nil
        )
        TrailerThumbnailCard(video: video)
    }
}

#if DEBUG
#Preview {
    YouTubePlayerView(videoKey: "dQw4w9WgXcQ", autoPlay: true, isMuted: true)
        .frame(height: 240)
        .padding()
}
#endif

