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
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Thumbnail
            ZStack {
                AsyncImage(url: video.thumbnailUrl) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay {
                                ProgressView()
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay {
                                Image(systemName: "play.rectangle")
                                    .font(.title)
                                    .foregroundColor(.secondary)
                            }
                    @unknown default:
                        Rectangle()
                            .fill(Color(.systemGray5))
                    }
                }
                .frame(width: 240, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Play overlay
                Circle()
                    .fill(.black.opacity(0.6))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .offset(x: 2)
                    }
                    .opacity(isHovered ? 1 : 0.8)
                
                // Type badge
                VStack {
                    HStack {
                        Spacer()
                        Text(video.type)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                    }
                    Spacer()
                }
                .padding(8)
            }
            .shadow(color: .black.opacity(0.2), radius: isHovered ? 10 : 4, y: isHovered ? 6 : 2)
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .onTapGesture {
                if let url = video.youtubeUrl {
                    #if os(iOS)
                    UIApplication.shared.open(url)
                    #else
                    NSWorkspace.shared.open(url)
                    #endif
                }
            }
            
            // Title
            Text(video.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: 240, alignment: .leading)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    VideoRowView(videos: [])
}
