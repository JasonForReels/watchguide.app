//
//  PopcornRefreshView.swift
//  WatchGuide-MovieandTVtracker
//
//  Custom popcorn pull-to-refresh spinner for Browse screen.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Popcorn Refresh Indicator
/// A custom pull-to-refresh indicator featuring an animated popcorn bucket.
/// Kernels pop out one by one while refreshing, then settle back down on completion.
struct PopcornRefreshView: View {
    let isRefreshing: Bool
    let progress: CGFloat // 0...1 representing pull progress before trigger
    
    @State private var bucketBounce = false
    @State private var kernel1Pop = false
    @State private var kernel2Pop = false
    @State private var kernel3Pop = false
    @State private var kernelRotation: Double = 0
    @State private var shimmer = false
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Popcorn kernels popping out
                popcornKernels
                
                // Bucket
                popcornBucket
            }
            .frame(width: 56, height: 56)
            .scaleEffect(bucketScale)
            .offset(y: bucketOffset)
            
            // Status text
            if isRefreshing {
                Text("Refreshing...")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            } else if progress > 0.8 {
                Text("Release to refresh")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(height: isRefreshing ? 100 : max(0, progress * 100))
        .opacity(max(0, min(1, progress * 2)))
        .onChange(of: isRefreshing) { _, refreshing in
            if refreshing {
                startRefreshAnimation()
            } else {
                stopRefreshAnimation()
            }
        }
    }
    
    // MARK: - Bucket Scale & Offset
    
    private var bucketScale: CGFloat {
        if isRefreshing {
            return bucketBounce ? 1.08 : 0.95
        }
        return 0.6 + (progress * 0.4) // Scale from 0.6 to 1.0 as user pulls
    }
    
    private var bucketOffset: CGFloat {
        isRefreshing && bucketBounce ? -2 : 0
    }
    
    // MARK: - Popcorn Bucket Shape
    
    private var popcornBucket: some View {
        ZStack {
            // Bucket body (trapezoid)
            PopcornBucketShape()
                .fill(Color.red)
                .frame(width: 32, height: 28)
                .shadow(color: .red.opacity(0.3), radius: 3, y: 2)
                .offset(y: 8)
            
            // Bucket stripes
            PopcornBucketShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red,
                            Color.red.opacity(0.85),
                            Color.white.opacity(0.25),
                            Color.red.opacity(0.85),
                            Color.red
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 32, height: 28)
                .offset(y: 8)
            
            // Bucket rim
            Capsule()
                .fill(Color.red.opacity(0.9))
                .frame(width: 34, height: 5)
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                .offset(y: -5)
            
            // Popcorn pile on top of bucket
            popcornPileInBucket
                .offset(y: -14)
        }
    }
    
    // MARK: - Popcorn Pile (static, sits in the bucket)
    
    private var popcornPileInBucket: some View {
        ZStack {
            // Bottom layer kernels
            Circle()
                .fill(Color(red: 1.0, green: 0.95, blue: 0.7))
                .frame(width: 11, height: 10)
                .offset(x: -7, y: 3)
            
            Circle()
                .fill(Color(red: 1.0, green: 0.93, blue: 0.65))
                .frame(width: 12, height: 10)
                .offset(x: 7, y: 3)
            
            Circle()
                .fill(Color(red: 1.0, green: 0.97, blue: 0.75))
                .frame(width: 10, height: 9)
                .offset(x: 0, y: 4)
            
            // Top layer kernels
            Circle()
                .fill(Color(red: 1.0, green: 0.96, blue: 0.72))
                .frame(width: 12, height: 11)
                .offset(x: -4, y: -2)
            
            Circle()
                .fill(Color(red: 1.0, green: 0.92, blue: 0.65))
                .frame(width: 11, height: 10)
                .offset(x: 5, y: -1)
            
            Circle()
                .fill(Color(red: 1.0, green: 0.98, blue: 0.78))
                .frame(width: 9, height: 8)
                .offset(x: 0, y: -5)
        }
        .scaleEffect(isRefreshing ? 1.0 : max(0.5, progress))
    }
    
    // MARK: - Popping Kernels (animated during refresh)
    
    private var popcornKernels: some View {
        ZStack {
            // Kernel 1 - pops up-left
            PopcornKernel()
                .frame(width: 10, height: 9)
                .offset(
                    x: kernel1Pop ? -14 : -4,
                    y: kernel1Pop ? -28 : -10
                )
                .rotationEffect(.degrees(kernel1Pop ? -35 : 0))
                .scaleEffect(kernel1Pop ? 1.1 : 0.5)
                .opacity(kernel1Pop ? 1 : 0)
            
            // Kernel 2 - pops straight up
            PopcornKernel()
                .frame(width: 11, height: 10)
                .offset(
                    x: kernel2Pop ? 2 : 0,
                    y: kernel2Pop ? -32 : -10
                )
                .rotationEffect(.degrees(kernel2Pop ? 20 : 0))
                .scaleEffect(kernel2Pop ? 1.15 : 0.5)
                .opacity(kernel2Pop ? 1 : 0)
            
            // Kernel 3 - pops up-right
            PopcornKernel()
                .frame(width: 9, height: 8)
                .offset(
                    x: kernel3Pop ? 16 : 5,
                    y: kernel3Pop ? -26 : -10
                )
                .rotationEffect(.degrees(kernel3Pop ? 40 : 0))
                .scaleEffect(kernel3Pop ? 1.05 : 0.5)
                .opacity(kernel3Pop ? 1 : 0)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.55), value: kernel1Pop)
        .animation(.spring(response: 0.45, dampingFraction: 0.55), value: kernel2Pop)
        .animation(.spring(response: 0.45, dampingFraction: 0.55), value: kernel3Pop)
    }
    
    // MARK: - Animation Control
    
    private func startRefreshAnimation() {
        // Bucket bounce loop
        withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
            bucketBounce = true
        }
        
        // Staggered kernel popping
        popKernelsLoop()
    }
    
    private func popKernelsLoop() {
        guard isRefreshing else { return }
        
        // Pop kernels in sequence with delays
        withAnimation { kernel1Pop = true }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard self.isRefreshing else { return }
            withAnimation { self.kernel2Pop = true }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            guard self.isRefreshing else { return }
            withAnimation { self.kernel3Pop = true }
        }
        
        // Reset and repeat
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard self.isRefreshing else { return }
            withAnimation {
                self.kernel1Pop = false
                self.kernel2Pop = false
                self.kernel3Pop = false
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.popKernelsLoop()
            }
        }
    }
    
    private func stopRefreshAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            bucketBounce = false
            kernel1Pop = false
            kernel2Pop = false
            kernel3Pop = false
        }
    }
}

// MARK: - Popcorn Kernel Shape
/// A single popcorn kernel — lumpy organic shape
struct PopcornKernel: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Base kernel
            Ellipse()
                .fill(Color(red: 1.0, green: 0.95, blue: 0.7))
                .shadow(color: Color(red: 0.85, green: 0.75, blue: 0.4).opacity(0.5), radius: 1, y: 1)
            
            // Highlight
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.6),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 6
                    )
                )
                .scaleEffect(0.7)
                .offset(x: -1, y: -1)
        }
    }
}

// MARK: - Popcorn Bucket Shape (Trapezoid)
struct PopcornBucketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topInset: CGFloat = rect.width * 0.12
        let cornerRadius: CGFloat = 3
        
        // Trapezoid: wider at top, narrower at bottom
        let topLeft = CGPoint(x: topInset, y: 0)
        let topRight = CGPoint(x: rect.width - topInset, y: 0)
        let bottomRight = CGPoint(x: rect.width * 0.82, y: rect.height)
        let bottomLeft = CGPoint(x: rect.width * 0.18, y: rect.height)
        
        path.move(to: CGPoint(x: topLeft.x + cornerRadius, y: topLeft.y))
        path.addLine(to: CGPoint(x: topRight.x - cornerRadius, y: topRight.y))
        path.addQuadCurve(to: CGPoint(x: topRight.x, y: topRight.y + cornerRadius),
                          control: topRight)
        path.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y - cornerRadius))
        path.addQuadCurve(to: CGPoint(x: bottomRight.x - cornerRadius, y: bottomRight.y),
                          control: bottomRight)
        path.addLine(to: CGPoint(x: bottomLeft.x + cornerRadius, y: bottomLeft.y))
        path.addQuadCurve(to: CGPoint(x: bottomLeft.x, y: bottomLeft.y - cornerRadius),
                          control: bottomLeft)
        path.addLine(to: CGPoint(x: topLeft.x, y: topLeft.y + cornerRadius))
        path.addQuadCurve(to: CGPoint(x: topLeft.x + cornerRadius, y: topLeft.y),
                          control: topLeft)
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Custom Refreshable ScrollView
/// A ScrollView wrapper that uses the native .refreshable modifier for reliable
/// pull-to-refresh detection, while overlaying a custom popcorn animation.
struct PopcornRefreshableScrollView<Content: View>: View {
    let onRefresh: () async -> Void
    @ViewBuilder let content: () -> Content
    
    @State private var isRefreshing = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Track scroll offset for pull progress
                GeometryReader { geo in
                    let offset = geo.frame(in: .named("popcornScroll")).minY
                    Color.clear
                        .preference(key: PopcornScrollOffsetKey.self, value: offset)
                }
                .frame(height: 0)
                
                // Popcorn refresh indicator (shows when refreshing)
                if isRefreshing {
                    PopcornRefreshView(isRefreshing: true, progress: 1.0)
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Actual content
                content()
            }
        }
        .coordinateSpace(name: "popcornScroll")
        .refreshable {
            #if canImport(UIKit) && !os(tvOS)
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            #endif
            
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isRefreshing = true
                }
            }
            
            // Run the actual data refresh
            await onRefresh()
            
            // Keep the animation visible for a satisfying duration after data loads
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.4)) {
                    isRefreshing = false
                }
            }
        }
        // Hide the default system refresh spinner by tinting it to clear
        .tint(.clear)
    }
}

// MARK: - Scroll Offset Preference Key
private struct PopcornScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    VStack(spacing: 30) {
        // Preview of the spinner in refreshing state
        let previewBackground: Color = {
            #if os(tvOS)
            return Color.gray
            #elseif canImport(UIKit)
            return Color(UIColor.systemGray6)
            #else
            return Color.gray.opacity(0.2)
            #endif
        }()
        
        PopcornRefreshView(isRefreshing: true, progress: 1.0)
            .frame(width: 120, height: 100)
            .background(previewBackground)
            .cornerRadius(16)
        
        // Preview of the spinner at various pull stages
        HStack(spacing: 20) {
            PopcornRefreshView(isRefreshing: false, progress: 0.3)
                .frame(width: 80, height: 60)
            PopcornRefreshView(isRefreshing: false, progress: 0.6)
                .frame(width: 80, height: 60)
            PopcornRefreshView(isRefreshing: false, progress: 1.0)
                .frame(width: 80, height: 60)
        }
    }
    .padding()
}
