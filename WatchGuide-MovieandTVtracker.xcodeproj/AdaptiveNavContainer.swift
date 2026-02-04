import SwiftUI

extension UIDevice {
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
}

struct AdaptiveNavContainer<Content: View>: View {
    @Environment(\.verticalSizeClass) private var vSize
    let content: Content
    @State private var selectedTab: Int = 0

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var isLandscapeOnPad: Bool {
        UIDevice.isPad && vSize == .compact
    }

    var isPortraitOnPad: Bool {
        UIDevice.isPad && (vSize == .regular || vSize == nil)
    }

    var body: some View {
        Group {
            if isLandscapeOnPad {
                // Top navigation (default)
                content
                    .toolbar(.visible, for: .navigationBar)
            } else if isPortraitOnPad {
                // Bottom navigation
                ZStack(alignment: .bottom) {
                    content
                        .toolbar(.hidden, for: .navigationBar)
                    BottomNavBar(selectedIndex: $selectedTab)
                        .transition(.move(edge: .bottom))
                }
            } else {
                content
            }
        }
    }
}

struct BottomNavBar: View {
    @Binding var selectedIndex: Int

    var body: some View {
        HStack {
            navButton(index: 0, system: "house.fill")
            Spacer()
            navButton(index: 1, system: "magnifyingglass")
            Spacer()
            navButton(index: 2, system: "gearshape.fill")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private func navButton(index: Int, system: String) -> some View {
        Button {
            selectedIndex = index
            // Hook into your navigation state here
        } label: {
            Image(systemName: system)
                .font(.title3)
                .foregroundStyle(selectedIndex == index ? Color.accentColor : Color.secondary)
        }
    }
}

#Preview {
    AdaptiveNavContainer {
        NavigationStack {
            Text("Content")
                .navigationTitle("Demo")
        }
    }
}
