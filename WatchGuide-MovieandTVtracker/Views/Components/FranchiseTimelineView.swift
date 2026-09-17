import SwiftUI

struct FranchiseTimelineItem: Identifiable, Codable {
    let id: Int
    let title: String
    let releaseDate: Date
    let chronologicalOrder: Int
    let posterPath: String?
    
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: releaseDate)
    }
}

struct FranchiseTimelineView: View {
    let title: String
    let items: [FranchiseTimelineItem]
    @State private var sortMode: SortMode = .release
    @Binding var selectedItem: MediaItem?
    
    enum SortMode {
        case release
        case chronology
    }
    
    var sortedItems: [FranchiseTimelineItem] {
        switch sortMode {
        case .release:
            return items.sorted(by: { $0.releaseDate < $1.releaseDate })
        case .chronology:
            return items.sorted(by: { $0.chronologicalOrder < $1.chronologicalOrder })
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(title)
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                Picker("Order", selection: $sortMode) {
                    Text("Release").tag(SortMode.release)
                    Text("In-Universe").tag(SortMode.chronology)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
            .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .center) {
                    // Timeline Line
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(height: 2)
                        .padding(.top, 40)
                    
                    HStack(spacing: 40) {
                        ForEach(sortedItems) { item in
                            VStack(spacing: 12) {
                                // Date Label
                                Text(sortMode == .release ? item.displayDate : "Chrono #\(item.chronologicalOrder)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                // Node
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 12, height: 12)
                                
                                // Movie Poster
                                Button {
                                    selectedItem = convertToMediaItem(item)
                                } label: {
                                    VStack(spacing: 8) {
                                        PosterImageView(posterPath: item.posterPath, size: .small)
                                            .frame(width: 120, height: 180)
                                            .cornerRadius(12)
                                        
                                        Text(item.title)
                                            .font(.caption)
                                            .bold()
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                            .frame(width: 120)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                }
            }
        }
    }
    
    private func convertToMediaItem(_ item: FranchiseTimelineItem) -> MediaItem {
        // Create a lightweight MediaItem for the detail view
        MediaItem(
            id: item.id,
            title: item.title,
            name: nil,
            originalTitle: nil,
            originalName: nil,
            overview: nil,
            posterPath: item.posterPath,
            backdropPath: nil,
            releaseDate: nil,
            firstAirDate: nil,
            voteAverage: nil,
            voteCount: nil,
            popularity: nil,
            genreIds: nil,
            mediaType: "movie",
            adult: nil,
            originalLanguage: nil
        )
    }
}
