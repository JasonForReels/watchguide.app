import SwiftUI

struct FranchiseCircleButton: View {
    let collection: HubCollection
    let action: () -> Void
    
    @Environment(\.isFocused) private var isFocused
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if let backdrop = collection.backdropAssetName {
                    // Modern Rectangular Style with Backdrop
                    Image(backdrop)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: horizontalSizeClass == .regular ? 320 : 180,
                            height: horizontalSizeClass == .regular ? 180 : 100
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(Color.white.opacity(isFocused || isHovered ? 0.3 : 0.1), lineWidth: 2)
                        )
                    
                    // Darker gradient overlay for grounding
                    LinearGradient(
                        colors: [.black.opacity(0.3), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                } else {
                    // Original Circular Style
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        
                        Image(collection.logoAssetName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(20)
                    }
                    .frame(
                        width: horizontalSizeClass == .regular ? 180 : 120,
                        height: horizontalSizeClass == .regular ? 180 : 120
                    )
                }
            }
            .scaleEffect(isHovered || isFocused ? 1.08 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0.2), radius: isFocused ? 15 : 8, y: isFocused ? 10 : 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered || isFocused)
        }
        .buttonStyle(.plain)
        #if !os(tvOS)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        #endif
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        FranchiseCircleButton(
            collection: HubCollection(
                id: 101,
                name: "Toy Story",
                logoAssetName: "pixar_toy_story_logo",
                backgroundColor: .blue
            ),
            action: {}
        )
    }
}
