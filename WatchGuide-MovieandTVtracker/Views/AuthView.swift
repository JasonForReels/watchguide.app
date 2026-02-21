//
//  AuthView.swift
//  WatchGuide-MovieandTVtracker
//
//  Sign in / Sign up view for user authentication
//

import SwiftUI
#if !os(tvOS)
import MessageUI
import AuthenticationServices
#endif

struct AuthView: View {
    @ObservedObject var authService = AuthService.shared
    @ObservedObject var profileService = ProfileService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showForgotPassword = false
    @State private var resetEmailSent = false
    @State private var showProfileSetup = false
    @State private var appleNonce: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.accentColor)
                        }
                        
                        Text(isSignUp ? "Create Account" : "Welcome Back")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(isSignUp ? "Sign up to sync your lists across devices" : "Sign in to access your synced lists")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Form
                    VStack(spacing: 16) {
                        // Email field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack {
                                Image(systemName: "envelope")
                                    .foregroundColor(.secondary)
                                TextField("you@example.com", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        
                        // Password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack {
                                Image(systemName: "lock")
                                    .foregroundColor(.secondary)
                                SecureField("Password", text: $password)
                                    .textContentType(isSignUp ? .newPassword : .password)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        
                        // Confirm password (sign up only)
                        if isSignUp {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Confirm Password")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                HStack {
                                    Image(systemName: "lock")
                                        .foregroundColor(.secondary)
                                    SecureField("Confirm password", text: $confirmPassword)
                                        .textContentType(.newPassword)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                        }
                        
                        // Forgot password (sign in only)
                        if !isSignUp {
                            HStack {
                                Spacer()
                                Button("Forgot Password?") {
                                    showForgotPassword = true
                                }
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                            }
                        }
                    }
                    
                    // Error message
                    if let error = authService.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    // Submit button
                    Button {
                        Task {
                            await handleSubmit()
                        }
                    } label: {
                        HStack {
                            if authService.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isFormValid ? Color.accentColor : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!isFormValid || authService.isLoading)

                    #if !os(tvOS)
                    VStack(spacing: 12) {
                        Text("or")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        SignInWithAppleButton(.signIn) { request in
                            let nonce = AuthService.randomNonceString()
                            appleNonce = nonce
                            request.requestedScopes = [.email]
                            request.nonce = AuthService.sha256(nonce)
                        } onCompletion: { result in
                            Task {
                                await handleAppleSignIn(result)
                            }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 44)
                    }
                    #endif
                    
                    // Toggle sign up / sign in
                    HStack {
                        Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                            .foregroundColor(.secondary)
                        Button(isSignUp ? "Sign In" : "Sign Up") {
                            withAnimation {
                                isSignUp.toggle()
                                password = ""
                                confirmPassword = ""
                                authService.errorMessage = nil
                            }
                        }
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                    }
                    .font(.subheadline)
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle(isSignUp ? "Sign Up" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Reset Password", isPresented: $showForgotPassword) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                Button("Cancel", role: .cancel) { }
                Button("Send Reset Link") {
                    Task {
                        let success = await authService.sendPasswordReset(email: email)
                        if success {
                            resetEmailSent = true
                        }
                    }
                }
            } message: {
                Text("Enter your email address and we'll send you a link to reset your password.")
            }
            .alert("Check Your Email", isPresented: $resetEmailSent) {
                Button("OK") { }
            } message: {
                Text("If an account exists with that email, you'll receive a password reset link shortly.")
            }
            .fullScreenCover(isPresented: $showProfileSetup) {
                FirstProfileSetupView {
                    dismiss()
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        let emailValid = email.contains("@") && email.contains(".")
        let passwordValid = password.count >= 6
        
        if isSignUp {
            return emailValid && passwordValid && password == confirmPassword
        }
        return emailValid && passwordValid
    }
    
    private func handleSubmit() async {
        if isSignUp {
            let success = await authService.signUp(email: email, password: password)
            if success {
                // Dismiss — ContentView will detect no profiles and show FirstProfileSetupView
                dismiss()
            }
        } else {
            let success = await authService.signIn(email: email, password: password)
            if success {
                await handleAuthSuccess()
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                authService.errorMessage = "Unable to read Apple ID token."
                return
            }

            let success = await authService.signInWithApple(idToken: idToken, nonce: nonce)
            if success {
                await handleAuthSuccess()
            }
        case .failure(let error):
            authService.errorMessage = error.localizedDescription
        }
    }

    private func handleAuthSuccess() async {
        // Try to download existing profiles from cloud
        await profileService.downloadProfilesFromCloud()

        if profileService.hasProfiles && !profileService.hasActiveProfile {
            // Has existing profiles — ContentView will show profile picker
            profileService.requestProfileSelection()
        }
        // Dismiss — ContentView handles what to show next
        dismiss()
    }
}

// MARK: - Account View (for Settings)

struct AccountView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var showSignOutConfirmation = false
    @State private var showMailError = false
    
    var body: some View {
        if let user = authService.currentUser {
            // Logged in state
            VStack(spacing: 16) {
                // User info card
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 56, height: 56)
                        
                        Text(userInitials(from: user.email))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.email ?? "User")
                            .font(.headline)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("Signed in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Sign out button
                Button {
                    showSignOutConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // Delete account button — opens Mail
                Button {
                    openDeleteAccountEmail()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Account")
                    }
                    .font(.subheadline)
                    .foregroundColor(.red.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                #if os(tvOS)
                .disabled(true)
                #endif
            }
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await authService.signOut()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You will need to sign in again to sync your lists across devices.")
            }
            .alert("Unable to Open Mail", isPresented: $showMailError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please send an email to support@watchguide.app with the subject \"Account deletion request\" to request your account be deleted.")
            }
        }
    }
    
    private func openDeleteAccountEmail() {
        #if os(tvOS)
        showMailError = true
        return
        #else
        let recipient = "support@watchguide.app"
        let subject = "Account deletion request"
        let body = "Input your email so we can go ahead and permanently delete your account and all data, optionally, go back into the app and press \"Clear All Data\" under \"Data Management\" if you don't want your account deleted.\n\nEmail: "
        
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        
        let mailtoString = "mailto:\(recipient)?subject=\(subjectEncoded)&body=\(bodyEncoded)"
        
        if let url = URL(string: mailtoString) {
            if PlatformURLHandler.canOpenURL(url) {
                PlatformURLHandler.openURL(url)
            } else {
                showMailError = true
            }
        }
        #endif
    }
    
    private func userInitials(from email: String?) -> String {
        guard let email = email else { return "?" }
        let parts = email.split(separator: "@")
        if let name = parts.first {
            return String(name.prefix(2)).uppercased()
        }
        return "?"
    }
}

#Preview {
    AuthView()
}
