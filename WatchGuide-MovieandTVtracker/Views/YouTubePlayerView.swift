//
//  YouTubePlayerView.swift
//  WatchGuide-MovieandTVtracker
//
//  Legacy compatibility wrapper — now renders an embedded autoplay-muted player.

import SwiftUI

struct YouTubePlayerView: View {
    let videoKey: String
    var autoPlay: Bool = false
    var isMuted: Bool = false
    
    var body: some View {
        EmbeddedTrailerPlayer(
            videoKey: videoKey,
            title: "Trailer"
        )
    }
}

#if DEBUG
#Preview {
    YouTubePlayerView(videoKey: "dQw4w9WgXcQ", autoPlay: true, isMuted: true)
        .frame(height: 240)
        .padding()
}
#endif

