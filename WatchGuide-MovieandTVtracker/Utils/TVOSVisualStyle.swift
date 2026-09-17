#if os(tvOS)
import SwiftUI

struct TVOSAmbientBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.09),
                    Color(red: 0.06, green: 0.08, blue: 0.13),
                    Color(red: 0.03, green: 0.04, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.21, green: 0.43, blue: 0.55).opacity(0.22),
                    .clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 620
            )

            RadialGradient(
                colors: [
                    Color(red: 0.56, green: 0.24, blue: 0.16).opacity(0.14),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 60,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

struct TVOSPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let fillOpacity: Double
    let strokeOpacity: Double

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(fillOpacity))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
    }
}

extension View {
    func tvOSPanelStyle(cornerRadius: CGFloat = 24, fillOpacity: Double = 0.08, strokeOpacity: Double = 0.12) -> some View {
        modifier(TVOSPanelModifier(cornerRadius: cornerRadius, fillOpacity: fillOpacity, strokeOpacity: strokeOpacity))
    }
}

/// A button style that suppresses the default tvOS white focus chrome,
/// applying a subtle highlight and scale instead.
struct TVOSTransparentButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12

    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(isFocused ? 0.12 : 0))
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isFocused)
    }
}
#endif
