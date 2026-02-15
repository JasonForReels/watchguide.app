//
//  FirstProfileSetupView.swift
//  WatchGuide-MovieandTVtracker
//
//  Full-screen first-time profile setup with age verification
//  Shown after a new sign-up or a returning user with no profiles
//

import SwiftUI

struct FirstProfileSetupView: View {
    @ObservedObject private var profileService = ProfileService.shared
    @State private var step: Step = .welcome
    @State private var name = ""
    @State private var selectedAvatar: ProfileAvatar = .popcorn
    @State private var selectedColor: ProfileColor = .blue
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var ageGroup: AgeGroup = .adult
    @State private var addKidsProfile = false
    @State private var animateIn = false
    
    let onComplete: () -> Void
    
    enum Step {
        case welcome
        case nameAvatar
        case ageVerify
        case kidsOption
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress bar
                progressBar
                    .padding(.top, 8)
                
                ScrollView {
                    VStack(spacing: 28) {
                        switch step {
                        case .welcome:
                            welcomeStep
                        case .nameAvatar:
                            nameAvatarStep
                        case .ageVerify:
                            ageVerifyStep
                        case .kidsOption:
                            kidsOptionStep
                        }
                    }
                    .padding(24)
                }
                
                // Bottom button
                bottomButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                animateIn = true
            }
        }
    }
    
    // MARK: - Progress Bar
    private var progressBar: some View {
        let totalSteps = 4
        let currentStep: Int = {
            switch step {
            case .welcome: return 1
            case .nameAvatar: return 2
            case .ageVerify: return 3
            case .kidsOption: return 4
            }
        }()
        
        return HStack(spacing: 6) {
            ForEach(1...totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= currentStep ? Color.accentColor : Color(.systemGray4))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Welcome Step
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)
            
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }
            .opacity(animateIn ? 1 : 0)
            .scaleEffect(animateIn ? 1 : 0.8)
            
            VStack(spacing: 10) {
                Text("Set Up Your Profile")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Create a profile to personalize your experience. Your profile syncs across all your devices.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 10)
            
            // Features list
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "person.2.fill", title: "Multiple Profiles", subtitle: "Each person gets their own experience")
                featureRow(icon: "shield.checkered", title: "Age Verification", subtitle: "Content is tailored to your age group")
                featureRow(icon: "figure.child", title: "Kids Profile", subtitle: "A safe, locked profile for younger viewers")
                featureRow(icon: "icloud.fill", title: "Cloud Synced", subtitle: "Profiles sync to all your devices automatically")
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 20)
        }
    }
    
    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Name & Avatar Step
    private var nameAvatarStep: some View {
        VStack(spacing: 24) {
            // Preview
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(selectedColor.color.opacity(0.15))
                    .frame(width: 110, height: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(selectedColor.color.opacity(0.3), lineWidth: 2)
                    )
                
                Image(systemName: selectedAvatar.rawValue)
                    .font(.system(size: 44))
                    .foregroundColor(selectedColor.color)
            }
            
            Text("What should we call you?")
                .font(.title3)
                .fontWeight(.bold)
            
            // Name
            TextField("Your name", text: $name)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            // Avatar
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose an avatar")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                    ForEach(ProfileAvatar.allCases) { avatar in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedAvatar = avatar
                            }
                        } label: {
                            Image(systemName: avatar.rawValue)
                                .font(.title3)
                                .foregroundColor(selectedAvatar == avatar ? selectedColor.color : .secondary)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selectedAvatar == avatar ? selectedColor.color.opacity(0.15) : Color(.systemGray6))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(selectedAvatar == avatar ? selectedColor.color : Color.clear, lineWidth: 2)
                                )
                        }
                    }
                }
            }
            
            // Color
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose a color")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    ForEach(ProfileColor.allCases) { color in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedColor = color
                            }
                        } label: {
                            Circle()
                                .fill(color.color)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                        .shadow(color: color.color.opacity(0.5), radius: selectedColor == color ? 4 : 0)
                                )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Age Verification Step
    private var ageVerifyStep: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(ageGroupColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 36))
                    .foregroundColor(ageGroupColor)
            }
            
            VStack(spacing: 8) {
                Text("Verify Your Age")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("Your date of birth determines what content you'll see. This is stored securely with your account.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Date Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Date of Birth")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                DatePicker(
                    "Date of Birth",
                    selection: $dateOfBirth,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .onChange(of: dateOfBirth) { _, newValue in
                    withAnimation {
                        ageGroup = ProfileService.ageGroupFromDateOfBirth(newValue)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Result card
            let age = ProfileService.ageFromDateOfBirth(dateOfBirth)
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: ageGroup == .adult ? "checkmark.shield.fill" : "shield.fill")
                        .foregroundColor(ageGroupColor)
                    Text("Age: \(age)")
                        .fontWeight(.semibold)
                }
                .font(.headline)
                
                Text("Content tier: \(ageGroup.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if ageGroup == .teen {
                    Text("Some mature content will be restricted.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                } else if ageGroup == .kids {
                    Text("Only kid-friendly content will be shown.")
                        .font(.caption)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ageGroupColor.opacity(0.08))
            )
        }
    }
    
    // MARK: - Kids Option Step
    private var kidsOptionStep: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "figure.child")
                    .font(.system(size: 36))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 8) {
                Text("Add a Kids Profile?")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("A Kids profile is locked to ages 6-12 and only shows family-friendly content. It works just like Netflix Kids.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Kids profile preview
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "pawprint.fill")
                        .font(.title)
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Kids")
                            .font(.headline)
                        Text("KIDS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green))
                    }
                    Text("Ages 6-12 only")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Content is restricted and Scout AI is hidden")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            
            // Toggle
            Toggle(isOn: $addKidsProfile) {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                    Text("Yes, add a Kids profile")
                        .fontWeight(.medium)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(addKidsProfile ? Color.green.opacity(0.08) : Color(.systemGray6))
            )
            
            Text("You can always add or remove profiles later from Settings.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var ageGroupColor: Color {
        switch ageGroup {
        case .kids: return .green
        case .teen: return .orange
        case .adult: return .accentColor
        }
    }
    
    // MARK: - Bottom Button
    private var bottomButton: some View {
        Button {
            advanceStep()
        } label: {
            Text(buttonLabel)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isButtonEnabled ? Color.accentColor : Color.gray.opacity(0.5))
                .foregroundColor(.white)
                .cornerRadius(14)
        }
        .disabled(!isButtonEnabled)
    }
    
    private var buttonLabel: String {
        switch step {
        case .welcome: return "Get Started"
        case .nameAvatar: return "Next"
        case .ageVerify: return "Continue"
        case .kidsOption: return "Finish Setup"
        }
    }
    
    private var isButtonEnabled: Bool {
        switch step {
        case .welcome: return true
        case .nameAvatar: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .ageVerify: return true
        case .kidsOption: return true
        }
    }
    
    private func advanceStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            switch step {
            case .welcome:
                step = .nameAvatar
            case .nameAvatar:
                step = .ageVerify
                ageGroup = ProfileService.ageGroupFromDateOfBirth(dateOfBirth)
            case .ageVerify:
                step = .kidsOption
            case .kidsOption:
                finishSetup()
            }
        }
    }
    
    // MARK: - Finish
    
    private func finishSetup() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        // Create the main profile
        let mainProfile = UserProfile(
            name: trimmedName,
            avatar: selectedAvatar,
            color: selectedColor,
            ageGroup: ageGroup,
            isKids: false,
            dateOfBirth: dateOfBirth
        )
        profileService.addProfile(mainProfile)
        
        // Optionally add a Kids profile
        if addKidsProfile {
            let kidsProfile = UserProfile.kidsProfile()
            profileService.addProfile(kidsProfile)
        }
        
        // Auto-select the main profile
        profileService.switchToProfile(mainProfile)
        
        // Sync to cloud
        profileService.syncProfilesToCloud()
        
        onComplete()
    }
}
