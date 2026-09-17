import SwiftUI

struct AIPlaylistView: View {
    let items: [MediaItem]
    @Binding var selectedItem: MediaItem?
    var isSavedToList: Bool = false
    var onRemove: ((MediaItem) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundColor(.accentColor)
                Text("Atlas's Curated Playlist")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Spacer()
                if isSavedToList {
                    Label("Saved to Lists", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                selectedItem = item
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    PosterImageView(posterPath: item.posterPath, size: .small)
                                        .frame(width: 100, height: 150)
                                        .cornerRadius(10)

                                    Text(item.displayTitle)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                        .frame(width: 100, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)

                            if let onRemove {
                                Button {
                                    onRemove(item)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color.black.opacity(0.6))
                                }
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                }
                .padding(.top, 6)
                .padding(.trailing, 6)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
}
