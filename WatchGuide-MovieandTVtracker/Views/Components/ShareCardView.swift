//
//  ShareCardView.swift
//  WatchGuide-MovieandTVtracker
//
//  Generates a branded share image for movies/shows with optional rating and comment.
//

import SwiftUI

struct ShareCardView: View {
    let title: String
    let posterPath: String?
    let mediaType: MediaType
    let rating: Float?
    let comment: String?
    let userName: String?
    
    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: PlatformImage?
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview of the card
                shareCardContent
                    .frame(width: 340, height: 440)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                
                Button {
                    renderAndShare()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 40)
            }
            .padding()
            .navigationTitle("Share Card")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = renderedImage {
                    ShareSheet(items: [image])
                }
            }
        }
    }
    
    @ViewBuilder
    private var shareCardContent: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.15),
                    Color(red: 0.12, green: 0.05, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 16) {
                // Poster
                if let posterPath {
                    ResilientAsyncImage(url: TMDBService.shared.imageURL(path: posterPath, size: .medium)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.1))
                        }
                    }
                    .frame(width: 160, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                }
                
                // Title
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
                
                // Rating stars
                if let rating, rating > 0 {
                    HStack(spacing: 3) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: Float(star) <= rating ? "star.fill" : (Float(star) - 0.5 <= rating ? "star.leadinghalf.filled" : "star"))
                                .font(.body)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                
                // Comment
                if let comment, !comment.isEmpty {
                    Text("\"\(comment)\"")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .italic()
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 20)
                }
                
                Spacer(minLength: 0)
                
                // Branding
                HStack(spacing: 6) {
                    if let userName {
                        Text(userName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                        
                        Text("•")
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    
                    Text("WatchGuide")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 16)
            }
            .padding(.top, 20)
        }
    }
    
    @MainActor
    private func renderAndShare() {
        let renderer = ImageRenderer(content: shareCardContent.frame(width: 340, height: 440))
        renderer.scale = 3.0
        
        #if os(macOS)
        let image = renderer.nsImage
        #else
        let image = renderer.uiImage
        #endif
        if let image {
            renderedImage = image
            showShareSheet = true
        }
    }
}

// MARK: - Share Sheet (UIActivityViewController wrapper)
#if os(macOS)
/// Shows the system share picker as soon as the view lands in a window.
struct ShareSheet: NSViewRepresentable {
    let items: [Any]

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        DispatchQueue.main.async {
            guard view.window != nil else { return }
            NSSharingServicePicker(items: items).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#elseif !os(tvOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct ShareSheet: View {
    let items: [Any]
    var body: some View {
        Text("Sharing is not available on tvOS")
    }
}
#endif

#Preview {
    ShareCardView(
        title: "Dune: Part Two",
        posterPath: nil,
        mediaType: .movie,
        rating: 4.5,
        comment: "Incredible visuals and storytelling",
        userName: "Jason"
    )
}
