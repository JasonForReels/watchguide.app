//
//  OnboardingFlowView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct OnboardingFlowView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var step: Step = .welcome
    @State private var tmdbKey = ""
    @State private var mdblistKey = ""
    @State private var isDownloading = false
    @State private var downloadError: String?
    
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var storage = StorageService.shared
    
    enum Step: Int, CaseIterable {
        case welcome
        case tmdbKey
        case mdblistKey
        case login
        case download
    }
    
    var body: some View {
        ZStack {
            background
            
            VStack(spacing: 24) {
                header
                
                content
                
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: step)
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
            
            Text(titleText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            if !subtitleText.isEmpty {
                Text(subtitleText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var content: some View {
        Group {
            switch step {
            case .welcome:
                welcomeCard
            case .tmdbKey:
                apiKeyCard(
                    title: "TMDB API Key",
                    subtitle: "Add your personal TMDB key to fetch movies, shows, and artwork.",
                    placeholder: "Paste TMDB API Key",
                    text: $tmdbKey,
                    helpURL: URL(string: "https://www.themoviedb.org/settings/api")!,
                    helpLabel: "Get a TMDB API key",
                    actionTitle: "Save TMDB Key",
                    onAction: saveTMDB
                )
            case .mdblistKey:
                apiKeyCard(
                    title: "MDBList API Key",
                    subtitle: "Enable curated lists and discovery collections.",
                    placeholder: "Paste MDBList API Key",
                    text: $mdblistKey,
                    helpURL: URL(string: "https://mdblist.com/preferences/")!,
                    helpLabel: "Get a MDBList API key",
                    actionTitle: "Save MDBList Key",
                    onAction: saveMDBList
                )
            case .login:
                OnboardingAuthView(onAuthenticated: {
                    step = .download
                })
            case .download:
                downloadCard
            }
        }
        .frame(maxWidth: 520)
    }
    
    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    step = Step(rawValue: max(step.rawValue - 1, 0)) ?? .welcome
                }
                .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            if step == .welcome {
                Button("Get Started") {
                    step = .tmdbKey
                }
                .buttonStyle(PrimaryPillButtonStyle())
            }
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
                Pill(text: "Sync", icon: "icloud.fill")
            }
        }
        .padding(28)
        .background(cardBackground)
    }
    
    private func apiKeyCard(
        title: String,
        subtitle: String,
        placeholder: String,
        text: Binding<String>,
        helpURL: URL,
        helpLabel: String,
        actionTitle: String,
        onAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .padding(14)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .foregroundColor(.white)
            
            Link(destination: helpURL) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text(helpLabel)
                }
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
            }
            
            Button(actionTitle) {
                onAction()
            }
            .buttonStyle(PrimaryPillButtonStyle())
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(24)
        .background(cardBackground)
    }
    
    private var downloadCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download From Cloud")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text("You are signed in. Pull your saved lists and history from the cloud to continue.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            
            if let error = downloadError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.orange)
            }
            
            Button(isDownloading ? "Downloading..." : "Download From Cloud") {
                Task {
                    await downloadFromCloud()
                }
            }
            .buttonStyle(PrimaryPillButtonStyle())
            .disabled(isDownloading)
            
            Button("Skip for now") {
                onboardingComplete = true
            }
            .font(.footnote)
            .foregroundColor(.white.opacity(0.7))
        }
        .padding(24)
        .background(cardBackground)
        .onAppear {
            if authService.isAuthenticated == false {
                step = .login
            }
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
    
    private var titleText: String {
        switch step {
        case .welcome: return "Welcome"
        case .tmdbKey: return "TMDB Setup"
        case .mdblistKey: return "MDBList Setup"
        case .login: return "Sign In"
        case .download: return "Cloud Sync"
        }
    }
    
    private var subtitleText: String {
        switch step {
        case .welcome: return "Your personal movie and TV guide"
        case .tmdbKey: return "Required to fetch TMDB data"
        case .mdblistKey: return "Required for curated lists"
        case .login: return "Access your synced data"
        case .download: return "Pull your saved lists"
        }
    }
    
    private func saveTMDB() {
        let saved = ApiKeyManager.shared.set(key: "TMDB_API_KEY", value: tmdbKey)
        if saved {
            step = .mdblistKey
        }
    }
    
    private func saveMDBList() {
        let saved = ApiKeyManager.shared.set(key: "MDBLIST_API_KEY", value: mdblistKey)
        if saved {
            step = .login
        }
    }
    
    private func downloadFromCloud() async {
        guard storage.isCloudConfigured else {
            downloadError = "Cloud sync is not configured. You can set it up later in Settings."
            onboardingComplete = true
            return
        }
        
        isDownloading = true
        downloadError = nil
        await storage.downloadFromCloud()
        isDownloading = false
        
        if let error = storage.lastSyncError {
            downloadError = error
        } else {
            onboardingComplete = true
        }
    }
}

private struct OnboardingAuthView: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    
    let onAuthenticated: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if authService.isAuthenticated {
                Text("You are already signed in.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Button("Continue") {
                    onAuthenticated()
                }
                .buttonStyle(PrimaryPillButtonStyle())
            } else {
                Text(isSignUp ? "Create Account" : "Sign In")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(isSignUp ? "Create an account to sync your lists across devices." : "Sign in to continue your synced experience.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .foregroundColor(.white)
                    
                    SecureField("Password", text: $password)
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .foregroundColor(.white)
                    
                    if isSignUp {
                        SecureField("Confirm Password", text: $confirmPassword)
                            .padding(12)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .foregroundColor(.white)
                    }
                }
                
                if let error = authService.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
                
                Button(authService.isLoading ? "Working..." : (isSignUp ? "Create Account" : "Sign In")) {
                    Task {
                        let success: Bool
                        if isSignUp {
                            success = await authService.signUp(email: email, password: password)
                        } else {
                            success = await authService.signIn(email: email, password: password)
                        }
                        if success {
                            onAuthenticated()
                        }
                    }
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(!isFormValid || authService.isLoading)
                
                Button(isSignUp ? "Have an account? Sign In" : "Need an account? Sign Up") {
                    isSignUp.toggle()
                    authService.errorMessage = nil
                }
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private var isFormValid: Bool {
        let emailValid = email.contains("@") && email.contains(".")
        let passwordValid = password.count >= 6
        if isSignUp {
            return emailValid && passwordValid && password == confirmPassword
        }
        return emailValid && passwordValid
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
