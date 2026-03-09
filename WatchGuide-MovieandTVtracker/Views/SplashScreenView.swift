//
//  SplashScreenView.swift
//  WatchGuide-MovieandTVtracker
//
//  Popcorn launch screensaver.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var fadeOut: Double = 1.0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if isActive {
            ContentView()
                .transition(.opacity)
        } else {
            splashContent
            .opacity(fadeOut)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + splashDuration) {
                    finishSplash()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    finishSplash()
                }
            }
            #if !os(tvOS) && !os(macOS)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            #endif
        }
    }
    
    private var splashContent: some View {
        Group {
            if isIPad {
                IPadPopcornSplashView()
            } else {
                phoneSplashContent
            }
        }
    }
    
    private var phoneSplashContent: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.12, green: 0.05, blue: 0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 18) {
                PopcornRefreshView(isRefreshing: true, progress: 1.0)
                    .frame(width: 150, height: 120)
                
                Text("WATCH GUIDE")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.9))
                    .tracking(2)
            }
            .padding(.bottom, 24)
        }
    }
    
    private var splashDuration: TimeInterval {
        isIPad ? 3.0 : 2.2
    }
    
    private var isIPad: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    private func finishSplash() {
        guard !isActive else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            fadeOut = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation {
                isActive = true
            }
        }
    }
}

private struct IPadPopcornSplashView: View {
    @State private var animateZoom = false
    @State private var animateDrift = false
    @State private var animateKernels = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                splashImage(in: geo.size)
                
                ZStack {
                    poppingKernels
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                animateZoom = true
                animateDrift = true
                animateKernels = true
            }
        }
    }
    
    @ViewBuilder
    private func splashImage(in size: CGSize) -> some View {
        #if canImport(UIKit)
        if let image = UIImage(named: "iPadOS splash screen") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .ignoresSafeArea()
                .scaleEffect(animateZoom ? 1.08 : 1.0)
                .offset(y: animateDrift ? -16 : 16)
                .overlay {
                    // Cinematic polish: subtle lighting pass over the full-screen art.
                    LinearGradient(
                        colors: [Color.white.opacity(0.0), Color.white.opacity(0.12), Color.white.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)
                    .ignoresSafeArea()
                }
                .animation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: animateZoom)
                .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: animateDrift)
        } else {
            fallbackBackground(in: size)
        }
        #else
        fallbackBackground(in: size)
        #endif
    }
    
    private func fallbackBackground(in size: CGSize) -> some View {
        LinearGradient(
            colors: [
                Color(red: 0.65, green: 0.76, blue: 0.73),
                Color(red: 0.58, green: 0.70, blue: 0.67)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            PopcornRefreshView(isRefreshing: true, progress: 1.0)
                .frame(width: 280, height: 220)
        }
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
    }
    
    private var poppingKernels: some View {
        ZStack {
            animatedKernel(size: 16, x: -98, y: -150, lift: 44, delay: 0.0)
            animatedKernel(size: 14, x: -52, y: -180, lift: 56, delay: 0.26)
            animatedKernel(size: 15, x: 0, y: -192, lift: 60, delay: 0.48)
            animatedKernel(size: 13, x: 52, y: -175, lift: 50, delay: 0.72)
            animatedKernel(size: 15, x: 98, y: -150, lift: 42, delay: 0.95)
        }
    }
    
    private func animatedKernel(size: CGFloat, x: CGFloat, y: CGFloat, lift: CGFloat, delay: TimeInterval) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.98, green: 0.95, blue: 0.79), Color(red: 0.93, green: 0.83, blue: 0.53)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.33), lineWidth: 1)
            )
            .offset(x: x, y: animateKernels ? y - lift : y)
            .scaleEffect(animateKernels ? 0.72 : 1.0)
            .opacity(animateKernels ? 0 : 0.95)
            .animation(
                .easeOut(duration: 1.25)
                    .repeatForever(autoreverses: false)
                    .delay(delay),
                value: animateKernels
            )
    }
}

#Preview {
    SplashScreenView()
}
