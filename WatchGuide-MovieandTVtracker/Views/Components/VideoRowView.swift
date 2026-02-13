//
//  VideoRowView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct VideoRowView: View {
    let videos: [Video]
    let title: String
    
    init(videos: [Video], title: String = "Videos & Trailers") {
        self.videos = videos
        self.title = title
    }
    
    var filteredVideos: [Video] {
        // Prioritize trailers and teasers
        let priorityTypes = ["Trailer", "Teaser", "Clip", "Featurette"]
        return videos
            .filter { $0.site.lowercased() == "youtube" }
            .sorted { video1, video2 in
                let priority1 = priorityTypes.firstIndex(of: video1.type) ?? 999
                let priority2 = priorityTypes.firstIndex(of: video2.type) ?? 999
                return priority1 < priority2
            }
    }
    
    var body: some View {
        if !filteredVideos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(filteredVideos.prefix(8)) { video in
                            VideoCard(video: video)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct VideoCard: View {
    let video: Video
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Inline embedded player (autoplay muted)
            EmbeddedTrailerPlayer(
                videoKey: video.key,
                title: video.name,
                compact: true
            )
            .frame(width: 240, height: 135)
            
            // Title
            Text(video.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: 240, alignment: .leading)
        }
    }
}

#Preview {
    VideoRowView(videos: [])
}
