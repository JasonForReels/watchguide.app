//
//  OnboardingFlowView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct OnboardingFlowView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    
    var body: some View {
        ZStack {
            background
            
            VStack(spacing: 24) {
                header
                welcomeCard
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
    }
    
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.12, blue: 0.18),
                    Color(red: 0.02, green: 0.02, blue: 0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 240, height: 240)
                .blur(radius: 10)
                .offset(x: -140, y: -200)
            
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 320, height: 320)
                .rotationEffect(.degrees(18))
                .blur(radius: 24)
                .offset(x: 160, y: 220)
        }
    }
    
    private var header: some View {
        VStack(spacing: 6) {
            Text("WatchGuide")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            
            Text("Welcome")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Your personal movie and TV guide")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }
    
    private var welcomeCard: some View {
        VStack(spacing: 18) {
            Text("Welcome to WatchGuide")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("The Movie and TV recommendation & Discovery app")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                Pill(text: "Personalized", icon: "sparkles")
                Pill(text: "Curated Lists", icon: "square.stack.3d.up.fill")
                Pill(text: "Sync", icon: "cloud.fill")
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .frame(maxWidth: 520)
    }
    
    private var footer: some View {
        HStack {
            Spacer()
            Button("Get Started") {
                onboardingComplete = true
            }
            .buttonStyle(PrimaryPillButtonStyle())
        }
    }
}

private struct Pill: View {
    let text: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.1))
        .foregroundColor(.white.opacity(0.9))
        .cornerRadius(20)
    }
}

private struct PrimaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 999)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

#Preview {
    OnboardingFlowView()
}
