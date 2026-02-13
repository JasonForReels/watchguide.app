import SwiftUI

// MARK: - Trailer Thumbnail Card (Tap to play in-app)
// Tapping opens the video in an in-app YouTube player sheet.
// No external app launches — everything plays within the app.

struct TrailerThumbnailCard: View {
    let video: Video
    var compact: Bool = false
    @State private var isPressed = false
    @State private var showPlayer = false
    
    private var thumbnailURL: URL? {
        guard video.site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(video.key)/maxresdefault.jpg")
    }
    
    var body: some View {
        Button {
            showPlayer = true
        } label: {
            ZStack {
                // Thumbnail image
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16.0/9.0, contentMode: .fill)
                    case .failure:
                        fallbackThumbnail
                    case .empty:
                        ZStack {
                            Color.black
                            ProgressView()
                                .tint(.white)
                        }
                        .aspectRatio(16.0/9.0, contentMode: .fill)
                    @unknown default:
                        fallbackThumbnail
                    }
                }
                .clipped()
                
                // Dark overlay for contrast
                Color.black.opacity(0.25)
                
                // Play button
                playButton
                
                // Video title & type badge
                VStack {
                    // Type badge (top-right)
                    HStack {
                        Spacer()
                        Text(video.type)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    // Title (bottom)
                    if !compact {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(video.name)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "play.rectangle.fill")
                                        .font(.system(size: 9))
                                    Text("YouTube")
                                        .font(.system(size: 10))
                                }
                                .foregroundColor(.white.opacity(0.7))
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.25), radius: isPressed ? 2 : 8, y: isPressed ? 1 : 4)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .sheet(isPresented: $showPlayer) {
            YouTubePlayerSheet(videoKey: video.key, title: video.name)
        }
    }
    
    private var playButton: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.5))
                .frame(width: compact ? 40 : 56, height: compact ? 40 : 56)
            
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: compact ? 40 : 56, height: compact ? 40 : 56)
            
            Image(systemName: "play.fill")
                .font(compact ? .body : .title3)
                .foregroundColor(.white)
                .offset(x: 2)
        }
    }
    
    private var fallbackThumbnail: some View {
        ZStack {
            Color(.systemGray5)
            Image(systemName: "play.rectangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
        }
        .aspectRatio(16.0/9.0, contentMode: .fill)
    }
}

// MARK: - Legacy WebTrailerPlayerView
struct WebTrailerPlayerView: View {
    let videoKey: String
    var autoplay: Bool = false
    var muted: Bool = true
    
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

