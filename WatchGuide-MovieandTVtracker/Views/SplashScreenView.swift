//
//  SplashScreenView.swift
//  WatchGuide-MovieandTVtracker
//
//  Splash screen displaying the app logo on launch
//

import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.85
    @State private var isPulsing = false

    var body: some View {
        if isActive {
            ContentView()
        } else {
            GeometryReader { geometry in
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    Image("D7BC305B-40A8-4086-B3F8-69ECFD32D11F_Untitled_design_2")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .opacity(logoOpacity)
                        .scaleEffect(isPulsing ? 1.06 : logoScale)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .ignoresSafeArea()
            .onAppear {
                // Phase 1: Fade in and scale up
                withAnimation(.easeOut(duration: 0.6)) {
                    logoOpacity = 1
                    logoScale = 1
                }

                // Phase 2: Start pulsing after fade-in completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    withAnimation(
                        .easeInOut(duration: 0.6)
                        .repeatCount(3, autoreverses: true)
                    ) {
                        isPulsing = true
                    }
                }

                // Phase 3: Transition to app after pulses finish
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.3) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isActive = true
                    }
                }
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
