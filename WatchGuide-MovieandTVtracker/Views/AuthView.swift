//
//  AuthView.swift
//  WatchGuide-MovieandTVtracker
//
//  Sign in / Sign up view — supports Supabase email auth
//

import SwiftUI

struct AuthView: View {
    @ObservedObject var authService = AuthService.shared
    @ObservedObject var profileService = ProfileService.shared
    @ObservedObject private var storage = StorageService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showForgotPassword = false
    @State private var resetEmailSent = false
    @State private var showProfileSetup = false
    @State private var showEmailForm = false
    
    var body: some View {
        authContent
            .navigationTitle("Sign In")
            #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if !os(tvOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                #endif
            }
            .alert("Reset Password", isPresented: $showForgotPassword) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    #if !os(macOS)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    #endif
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
            #if os(macOS)
            .sheet(isPresented: $showProfileSetup) {
                FirstProfileSetupView {
                    dismiss()
                }
            }
            #else
            .fullScreenCover(isPresented: $showProfileSetup) {
                FirstProfileSetupView {
                    dismiss()
                }
            }
            #endif
    }

    @ViewBuilder
    private var authContent: some View {
        authScrollView
    }

    private var authScrollView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            #if os(tvOS)
                            .fill(Color.white.opacity(0.1))
                            #else
                            .fill(Color.accentColor.opacity(0.15))
                            #endif
                            .frame(width: 80, height: 80)

                        if let profile = profileService.activeProfile {
                            ProfileAvatarImageView(
                                profile: profile,
                                size: 56,
                                showBorder: false
                            )
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 28, weight: .semibold))
                                #if os(tvOS)
                                .foregroundColor(.white)
                                #else
                                .foregroundColor(.accentColor)
                                #endif
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        #if os(tvOS)
                                        .fill(Color.white.opacity(0.08))
                                        #else
                                        .fill(Color.accentColor.opacity(0.12))
                                        #endif
                                )
                                .clipShape(Circle())
                        }
                    }

                    Text("Sign In")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Sync your lists and profiles across all your devices")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 20)

                // Email option
                if showEmailForm {
                    emailFormSection
                } else {
                    emailOptionButton
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        #if !os(macOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    @ViewBuilder
    private var emailOptionButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showEmailForm = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                Text("Continue with Email")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            #if os(tvOS)
            .background(Color.white.opacity(0.12))
            .foregroundColor(.white)
            #else
            .background(Color.gray.opacity(0.12))
            .foregroundColor(.primary)
            #endif
            .cornerRadius(12)
        }
        .disabled(!authService.isSupabaseAvailable)
        .opacity(authService.isSupabaseAvailable ? 1.0 : 0.55)

        if !authService.isSupabaseAvailable {
            Text("Email sign-in requires Supabase. Link Supabase in Settings.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Email Form
    
    @ViewBuilder
    private var emailFormSection: some View {
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
                        #if !os(macOS)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()
                }
                .padding()
                #if os(tvOS)
                .background(Color.white.opacity(0.08))
                #else
                .background(Color.gray.opacity(0.12))
                #endif
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
                #if os(tvOS)
                .background(Color.white.opacity(0.08))
                #else
                .background(Color.gray.opacity(0.12))
                #endif
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
                    #if os(tvOS)
                    .background(Color.white.opacity(0.08))
                    #else
                    .background(Color.gray.opacity(0.12))
                    #endif
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
                    #if os(tvOS)
                    .foregroundColor(Color.white.opacity(0.7))
                    #else
                    .foregroundColor(.accentColor)
                    #endif
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
                #if os(tvOS)
                .background(Color.orange.opacity(0.15))
                #else
                .background(Color.orange.opacity(0.1))
                #endif
                .cornerRadius(10)
            }
            
            // Submit button
            Button {
                Task {
                    await handleEmailSubmit()
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
                #if os(tvOS)
                .background(isFormValid ? Color.white.opacity(0.22) : Color.white.opacity(0.06))
                .foregroundColor(isFormValid ? .white : Color.white.opacity(0.5))
                #else
                .background(isFormValid ? Color.accentColor : Color.gray)
                .foregroundColor(.white)
                #endif
                .cornerRadius(12)
            }
            .disabled(!isFormValid || authService.isLoading)

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
                #if os(tvOS)
                .foregroundColor(.white)
                #else
                .foregroundColor(.accentColor)
                #endif
            }
            .font(.subheadline)
        }
    }
    
    // MARK: - Validation
    
    private var isFormValid: Bool {
        let emailValid = email.contains("@") && email.contains(".")
        let passwordValid = password.count >= 6
        
        if isSignUp {
            return emailValid && passwordValid && password == confirmPassword
        }
        return emailValid && passwordValid
    }
    
    // MARK: - Email Auth
    
    private func handleEmailSubmit() async {
        guard authService.isSupabaseAvailable else {
            authService.errorMessage = "Email sign-in requires a linked Supabase project."
            return
        }

        if isSignUp {
            let success = await authService.signUp(email: email, password: password)
            if success {
                // requiresPostSignInSyncDecision is already set by AuthService
                // ContentView will show the PostSignInSyncView
                dismiss()
            }
        } else {
            let success = await authService.signIn(email: email, password: password)
            if success {
                // requiresPostSignInSyncDecision is already set by AuthService
                // ContentView will show the PostSignInSyncView
                dismiss()
            }
        }
    }

}

// MARK: - Account View (for Settings)

struct AccountView: View {
    @ObservedObject var authService = AuthService.shared
    @ObservedObject private var storage = StorageService.shared
    @State private var deleteAccountError: String?
    @State private var isManualUpload = false
    @State private var isManualDownload = false

    var body: some View {
        if let user = authService.currentUser {
            VStack(spacing: 16) {
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
                .background(Color.gray.opacity(0.12))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Sync")
                            .font(.headline)
                        Spacer()
                        Text(storage.cloudProviderDisplayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Last Sync")
                            .font(.subheadline)
                        Spacer()
                        if let lastSync = storage.lastSyncTime {
                            Text(lastSync.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Never")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let error = storage.lastSyncError, !error.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    HStack(spacing: 12) {
                        Button {
                            guard !isManualUpload && !isManualDownload else { return }
                            isManualUpload = true
                            Task {
                                await storage.uploadToCloud()
                                await MainActor.run {
                                    isManualUpload = false
                                }
                            }
                        } label: {
                            Label(isManualUpload ? "Syncing Changes..." : "Sync Changes", systemImage: "arrow.up.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isManualUpload || isManualDownload)
                        .buttonStyle(.borderedProminent)

                        Button {
                            guard !isManualUpload && !isManualDownload else { return }
                            isManualDownload = true
                            Task {
                                await storage.downloadFromCloud()
                                await MainActor.run {
                                    isManualDownload = false
                                }
                            }
                        } label: {
                            Label(isManualDownload ? "Fetching Additions..." : "Get Additions", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isManualUpload || isManualDownload)
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.12))
                .cornerRadius(12)

                SignOutActionButton {
                    Task {
                        await authService.signOut()
                    }
                }

                DeleteAccountActionButton {
                    Task {
                        let success = await authService.deleteAccount()
                        if !success {
                            deleteAccountError = authService.errorMessage ?? "Failed to delete account."
                        }
                    }
                }
            }
            .alert("Delete Account Failed", isPresented: Binding(
                get: { deleteAccountError != nil },
                set: { if !$0 { deleteAccountError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deleteAccountError ?? "Unknown error.")
            }
        }
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

private struct SignOutActionButton: View {
    let onConfirm: () -> Void
    @State private var showConfirmation = false

    var body: some View {
        Button {
            showConfirmation = true
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
        .confirmationDialog("Sign Out", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                onConfirm()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You will need to sign in again to sync your lists across devices.")
        }
    }
}

private struct DeleteAccountActionButton: View {
    let onConfirm: () -> Void
    @State private var showConfirmation = false

    var body: some View {
        Button {
            showConfirmation = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Account")
            }
            .font(.subheadline)
            .foregroundColor(.red.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Color.gray.opacity(0.12))
            .cornerRadius(12)
        }
        .confirmationDialog("Delete Account?", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                onConfirm()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes your account and cloud data. This cannot be undone.")
        }
    }
}

#Preview {
    AuthView()
}
