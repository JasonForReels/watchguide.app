//
//  AuthView.swift
//  WatchGuide-MovieandTVtracker
//
//  Sign in / Sign up view for user authentication
//

import SwiftUI

struct AuthView: View {
    @ObservedObject var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showForgotPassword = false
    @State private var resetEmailSent = false
    
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
                dismiss()
            }
        } else {
            let success = await authService.signIn(email: email, password: password)
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Account View (for Settings)

struct AccountView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var showSignOutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showDeleteFinalConfirmation = false
    @State private var deleteConfirmText = ""
    @State private var accountDeleted = false
    
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
                
                // Delete account button
                Button {
                    showDeleteConfirmation = true
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
            .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Continue", role: .destructive) {
                    showDeleteFinalConfirmation = true
                }
            } message: {
                Text("This will permanently delete all your data including your watchlist, watched history, liked items, and custom lists. This action cannot be undone.")
            }
            .alert("Type DELETE to confirm", isPresented: $showDeleteFinalConfirmation) {
                TextField("Type DELETE", text: $deleteConfirmText)
                    .autocapitalization(.allCharacters)
                Button("Cancel", role: .cancel) {
                    deleteConfirmText = ""
                }
                Button("Delete My Account", role: .destructive) {
                    guard deleteConfirmText.uppercased() == "DELETE" else {
                        deleteConfirmText = ""
                        return
                    }
                    Task {
                        let success = await authService.deleteAccount()
                        if success {
                            accountDeleted = true
                        }
                        deleteConfirmText = ""
                    }
                }
            } message: {
                Text("This is your final confirmation. Type DELETE to permanently remove your account and all associated data.")
            }
            .alert("Account Deleted", isPresented: $accountDeleted) {
                Button("OK") { }
            } message: {
                Text("Your account and all associated data have been successfully deleted.")
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

#Preview {
    AuthView()
}
