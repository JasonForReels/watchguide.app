import SwiftUI

extension View {
    @ViewBuilder
    func inlineNavTitleIfSupported() -> some View {
        #if os(macOS) || os(tvOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }

    func onFocusChange(perform action: @escaping (Bool) -> Void) -> some View {
        #if os(tvOS)
        self.modifier(FocusChangeModifier(action: action))
        #else
        self
        #endif
    }

    @ViewBuilder
    func applyDefaultBackground() -> some View {
        #if os(tvOS)
        self.background(Color.clear.ignoresSafeArea())
        #elseif os(macOS)
        self.background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        #else
        self.background(Color(.systemGroupedBackground).ignoresSafeArea())
        #endif
    }

    @ViewBuilder
    func applySecondaryBackground() -> some View {
        #if os(tvOS)
        self.background(Color.white.opacity(0.1))
        #elseif os(macOS)
        self.background(Color(nsColor: .controlBackgroundColor))
        #else
        self.background(Color(.secondarySystemGroupedBackground))
        #endif
    }

    @ViewBuilder
    func applyInlineNavigationView() -> some View {
        #if !os(tvOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

// MARK: - Shimmer Loading Effect
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0.001

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: max(0, phase - 0.3)),
                        .init(color: .white.opacity(0.18), location: phase),
                        .init(color: .clear, location: min(1, phase + 0.3))
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.4)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.3
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

#if os(tvOS)
struct FocusChangeModifier: ViewModifier {
    let action: (Bool) -> Void
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: isFocused) { newValue in
                action(newValue)
            }
    }
}
#endif
