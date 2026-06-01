//
//  ActionButtonAnimationView.swift
//  WatchGuide-MovieandTVtracker
//
//  A premium 3D-style Action Button with concentric ring animations,
//  shimmer sweep, glow pulse, and spring-based press interaction.
//

import SwiftUI

struct ActionButtonAnimationView: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isPressed = false
    @State private var ringRotation: Double = 0
    @State private var outerRingRotation: Double = 0
    @State private var glowPulse: Bool = false
    @State private var shimmerOffset: CGFloat = -200
    @State private var appeared = false
    @State private var particleBurst = false

    private let buttonSize: CGFloat = 80
    private let ringGap: CGFloat = 6

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Ambient glow behind the button
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(glowPulse ? 0.25 : 0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: buttonSize / 2,
                            endRadius: buttonSize * 1.3
                        )
                    )
                    .frame(width: buttonSize * 2.6, height: buttonSize * 2.6)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: glowPulse)

                // Outer rotating ring with gradient stroke
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: buttonSize + ringGap * 6, height: buttonSize + ringGap * 6)
                    .rotationEffect(.degrees(outerRingRotation))

                // Middle ring — counter-rotating dashed accent
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.0)
                            ]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 8])
                    )
                    .frame(width: buttonSize + ringGap * 3, height: buttonSize + ringGap * 3)
                    .rotationEffect(.degrees(-ringRotation * 0.6))

                // Inner ring — solid accent
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: buttonSize + ringGap, height: buttonSize + ringGap)

                // Main button body
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                        isPressed = true
                    }
                    triggerHaptic()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.15)) {
                        particleBurst = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        action()
                    }
                }) {
                    ZStack {
                        // Button fill with 3D-esque gradient
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(red: 0.95, green: 0.95, blue: 0.98),
                                        Color(red: 0.82, green: 0.82, blue: 0.88)
                                    ],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: buttonSize
                                )
                            )

                        // Top highlight for 3D effect
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .padding(2)

                        // Shimmer sweep across the surface
                        Circle()
                            .fill(Color.clear)
                            .overlay(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.0),
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 30)
                                .offset(x: shimmerOffset)
                                .animation(
                                    .easeInOut(duration: 2.5)
                                    .repeatForever(autoreverses: false)
                                    .delay(0.8),
                                    value: shimmerOffset
                                )
                            )
                            .clipShape(Circle())

                        // Icon
                        Image(systemName: icon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.15, green: 0.15, blue: 0.22),
                                        Color(red: 0.25, green: 0.25, blue: 0.35)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .frame(width: buttonSize, height: buttonSize)
                }
                .buttonStyle(ActionButtonPressStyle())

                // Particle burst on press
                if particleBurst {
                    ForEach(0..<8, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 4, height: 4)
                            .offset(
                                x: particleBurst ? cos(Double(i) * .pi / 4) * 60 : 0,
                                y: particleBurst ? sin(Double(i) * .pi / 4) * 60 : 0
                            )
                            .opacity(particleBurst ? 0 : 1)
                            .animation(
                                .easeOut(duration: 0.6)
                                .delay(Double(i) * 0.03),
                                value: particleBurst
                            )
                    }
                }
            }
            .rotation3DEffect(
                .degrees(appeared ? 0 : 25),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.5
            )
            .scaleEffect(appeared ? 1.0 : 0.7)
            .opacity(appeared ? 1.0 : 0.0)

            // Label below
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
        }
        .onAppear {
            // Start continuous ring rotation
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                outerRingRotation = 360
            }

            // Glow pulse
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulse = true
            }

            // Shimmer
            shimmerOffset = 200

            // Entrance animation
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) {
                appeared = true
            }
        }
    }

    private func triggerHaptic() {
        #if canImport(UIKit) && !os(tvOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
}

// MARK: - Press Style

private struct ActionButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .shadow(
                color: Color.white.opacity(configuration.isPressed ? 0.4 : 0.15),
                radius: configuration.isPressed ? 16 : 8,
                y: configuration.isPressed ? 2 : 4
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ActionButtonAnimationView(
            title: "Get Started",
            icon: "play.fill"
        ) {
            print("tapped!")
        }
    }
}
