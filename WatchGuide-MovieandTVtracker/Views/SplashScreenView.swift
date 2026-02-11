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
                        .scaleEffect(logoScale)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    logoOpacity = 1
                    logoScale = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
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
