//
//  VideoRowView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct VideoRowView: View {
    let videos: [Video]
    let title: String
    var vpnDetected: Bool = false
    
    init(videos: [Video], title: String = "Videos & Trailers", vpnDetected: Bool = false) {
        self.videos = videos
        self.title = title
        self.vpnDetected = vpnDetected
    }
    
    var filteredVideos: [Video] {
        // Prioritize trailers and teasers, exclude red band (R-rated) trailers
        let priorityTypes = ["Trailer", "Teaser", "Clip", "Featurette"]
        let allowedSites: Set<String> = ["youtube", "direct"]
        return videos
            .filter { allowedSites.contains($0.site.lowercased()) }
            .filter { !$0.isRedBand }
            .sorted { video1, video2 in
                // Always sort Direct videos before YouTube (more reliable, no bot walls)
                let isDirect1 = video1.site.lowercased() == "direct"
                let isDirect2 = video2.site.lowercased() == "direct"
                if isDirect1 != isDirect2 { return isDirect1 }
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
    @State private var isPlaying = false
    @State private var showSheet = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        let cardSize = ResponsiveSizing.videoCardSize(horizontalSizeClass: horizontalSizeClass)
        VStack(alignment: .leading, spacing: 6) {
            if isPlaying {
                // Inline embedded player (user tapped play)
                EmbeddedTrailerPlayer(
                    videoKey: video.key,
                    title: video.name,
                    compact: true,
                    autoPlay: true
                )
                .frame(width: cardSize.width, height: cardSize.height)
            } else {
                // Thumbnail with play button — does NOT auto-play
                ZStack {
                    if video.site.lowercased() == "direct" {
                        // Direct video (addon) — no YouTube thumbnail available
                        ZStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.18))
                            Image(systemName: "play.rectangle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .frame(width: cardSize.width, height: cardSize.height)
                    } else {
                        AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(video.key)/mqdefault.jpg")) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(16.0/9.0, contentMode: .fill)
                            default:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.18))
                            }
                        }
                        .frame(width: cardSize.width, height: cardSize.height)
                        .clipped()
                    }
                    
                    // Dark overlay
                    Color.black.opacity(0.3)
                    
                    // Play button
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.5))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "play.fill")
                            .font(.body)
                            .foregroundColor(.white)
                            .offset(x: 2)
                    }
                    
                    // Type badge
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(video.type.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background {
                                    Capsule()
                                        .fill(.clear)
                                        .glassEffect(.regular, in: .capsule)
                                }
                                .padding(6)
                        }
                    }
                }
                .frame(width: cardSize.width, height: cardSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeIn(duration: 0.2)) {
                        isPlaying = true
                    }
                }
            }
            
            // Title
            Text(video.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: cardSize.width, alignment: .leading)
        }
    }
}

#Preview {
    VideoRowView(videos: [])
}
