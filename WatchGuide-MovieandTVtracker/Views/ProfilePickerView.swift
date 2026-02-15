//
//  ProfilePickerView.swift
//  WatchGuide-MovieandTVtracker
//
//  Netflix-style profile selection screen
//

import SwiftUI

struct ProfilePickerView: View {
    @ObservedObject private var profileService = ProfileService.shared
    @State private var showAddProfile = false
    @State private var showEditProfile: UserProfile?
    @State private var isManageMode = false
    @State private var selectedProfile: UserProfile?
    @State private var animateIn = false
    @State private var isRefreshing = false
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                Spacer()
                
                // Title
                Text("Who's Watching?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : -10)
                
                // Profile Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20)
                ], spacing: 24) {
                    ForEach(profileService.profiles) { profile in
                        ProfileAvatarCard(
                            profile: profile,
                            isManageMode: isManageMode,
                            onTap: {
                                if isManageMode {
                                    showEditProfile = profile
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedProfile = profile
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                        profileService.switchToProfile(profile)
                                    }
                                }
                            }
                        )
                    }
                    
                    // Add Profile Button (max 5 profiles)
                    if profileService.profiles.count < 5 {
                        AddProfileCard {
                            showAddProfile = true
                        }
                    }
                }
                .padding(.horizontal, 40)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
                
                Spacer()
                
                // Manage Profiles Button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isManageMode.toggle()
                    }
                } label: {
                    Text(isManageMode ? "Done" : "Manage Profiles")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                }
                .padding(.bottom, 40)
                .opacity(animateIn ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                animateIn = true
            }
            // Silently refresh profiles from cloud so cross-device changes appear
            if !isRefreshing {
                isRefreshing = true
                profileService.refreshFromCloudIfNeeded()
                // Reset flag after a short delay to allow re-refresh if view reappears
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    isRefreshing = false
                }
            }
        }
        .sheet(isPresented: $showAddProfile) {
            ProfileSetupView(mode: .create)
        }
        .sheet(item: $showEditProfile) { profile in
            ProfileSetupView(mode: .edit(profile))
        }
    }
}

// MARK: - Profile Avatar Card
struct ProfileAvatarCard: View {
    let profile: UserProfile
    let isManageMode: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(profile.color.color.opacity(0.15))
                        .frame(width: 100, height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(profile.color.color.opacity(0.3), lineWidth: 2)
                        )
                    
                    Image(systemName: profile.avatar.rawValue)
                        .font(.system(size: 36))
                        .foregroundColor(profile.color.color)
                    
                    // Kids badge
                    if profile.isKids {
                        VStack {
                            HStack {
                                Spacer()
                                Text("KIDS")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.green)
                                    )
                                    .offset(x: 4, y: -4)
                            }
                            Spacer()
                        }
                        .frame(width: 100, height: 100)
                    }
                    
                    // Edit overlay in manage mode
                    if isManageMode {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "pencil")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                
                Text(profile.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !profile.isKids {
                    Text(profile.ageGroup.ageRange)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Add Profile Card
struct AddProfileCard: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemGray6))
                        .frame(width: 100, height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(.systemGray4), lineWidth: 1.5)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        )
                    
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Text("Add Profile")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text(" ")
                    .font(.caption2)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Profile Switcher Sheet (compact, for in-app switching)
struct ProfileSwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profileService = ProfileService.shared
    @State private var showAddProfile = false
    @State private var showEditProfile: UserProfile?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Current profile header
                    if let active = profileService.activeProfile {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(active.color.color.opacity(0.15))
                                    .frame(width: 72, height: 72)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(active.color.color.opacity(0.3), lineWidth: 2)
                                    )
                                
                                Image(systemName: active.avatar.rawValue)
                                    .font(.system(size: 30))
                                    .foregroundColor(active.color.color)
                            }
                            
                            HStack(spacing: 6) {
                                Text(active.name)
                                    .font(.headline)
                                if active.isKids {
                                    Text("KIDS")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.green))
                                }
                            }
                            
                            Text("Active Profile")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                    }
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Other profiles
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Switch to")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                        
                        ForEach(profileService.profiles.filter { $0.id != profileService.activeProfile?.id }) { profile in
                            Button {
                                profileService.switchToProfile(profile)
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(profile.color.color.opacity(0.15))
                                            .frame(width: 44, height: 44)
                                        
                                        Image(systemName: profile.avatar.rawValue)
                                            .font(.title3)
                                            .foregroundColor(profile.color.color)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(profile.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.primary)
                                            
                                            if profile.isKids {
                                                Text("KIDS")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Capsule().fill(Color.green))
                                            }
                                        }
                                        
                                        Text(profile.isKids ? "Ages 6-12" : profile.ageGroup.displayName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.systemGray6))
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }
                        
                        // "No other profiles" if only 1 profile
                        if profileService.profiles.count <= 1 {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                    Text("No other profiles yet")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 16)
                                Spacer()
                            }
                        }
                    }
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Actions
                    VStack(spacing: 10) {
                        // Add profile (max 5)
                        if profileService.profiles.count < 5 {
                            Button {
                                showAddProfile = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.accentColor)
                                    Text("Add Profile")
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.systemGray6))
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }
                        
                        // Edit current profile
                        if let active = profileService.activeProfile {
                            Button {
                                showEditProfile = active
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundColor(.secondary)
                                    Text("Edit Current Profile")
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.systemGray6))
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
            }
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddProfile) {
                ProfileSetupView(mode: .create)
            }
            .sheet(item: $showEditProfile) { profile in
                ProfileSetupView(mode: .edit(profile))
            }
        }
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Profile Setup View (Create / Edit)
struct ProfileSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profileService = ProfileService.shared
    
    enum Mode: Identifiable {
        case create
        case edit(UserProfile)
        
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let profile): return profile.id
            }
        }
    }
    
    let mode: Mode
    
    @State private var step: SetupStep = .info
    @State private var name: String = ""
    @State private var selectedAvatar: ProfileAvatar = .popcorn
    @State private var selectedColor: ProfileColor = .blue
    @State private var isKidsProfile = false
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var ageGroup: AgeGroup = .adult
    @State private var showDeleteConfirmation = false
    
    enum SetupStep {
        case info      // Name, avatar, color, isKids toggle
        case ageVerify // Date of birth picker (not for Kids profiles)
    }
    
    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }
    
    private var editingProfile: UserProfile? {
        if case .edit(let profile) = mode { return profile }
        return nil
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if step == .info {
                        infoStep
                    } else {
                        ageVerificationStep
                    }
                }
                .padding(24)
            }
            .navigationTitle(isEditing ? "Edit Profile" : "New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if step == .info {
                        Button(isKidsProfile ? "Save" : "Next") {
                            if isKidsProfile {
                                saveProfile()
                            } else {
                                withAnimation { step = .ageVerify }
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button("Save") {
                            saveProfile()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                if let profile = editingProfile {
                    name = profile.name
                    selectedAvatar = profile.avatar
                    selectedColor = profile.color
                    isKidsProfile = profile.isKids
                    dateOfBirth = profile.dateOfBirth ?? Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
                    ageGroup = profile.ageGroup
                }
            }
        }
    }
    
    // MARK: - Info Step
    private var infoStep: some View {
        VStack(spacing: 28) {
            // Avatar Preview
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(selectedColor.color.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(selectedColor.color.opacity(0.3), lineWidth: 2)
                    )
                
                Image(systemName: selectedAvatar.rawValue)
                    .font(.system(size: 48))
                    .foregroundColor(selectedColor.color)
            }
            
            // Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Profile Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("Name", text: $name)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
            
            // Avatar Selection
            VStack(alignment: .leading, spacing: 10) {
                Text("Avatar")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                    ForEach(ProfileAvatar.allCases) { avatar in
                        Button {
                            selectedAvatar = avatar
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
            
            // Color Selection
            VStack(alignment: .leading, spacing: 10) {
                Text("Color")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 12) {
                    ForEach(ProfileColor.allCases) { color in
                        Button {
                            selectedColor = color
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
            
            // Kids Profile Toggle
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $isKidsProfile) {
                    HStack(spacing: 10) {
                        Image(systemName: "figure.child")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kids Profile")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Locked to ages 6-12. Only shows kid-friendly content.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onChange(of: isKidsProfile) { _, newValue in
                    if newValue {
                        selectedColor = .green
                        selectedAvatar = .pawprint
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Delete button (editing only, non-kids profile if more than 1 profile)
            if isEditing && profileService.profiles.count > 1 {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Profile")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }
                .confirmationDialog("Delete Profile?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        if let profile = editingProfile {
                            profileService.deleteProfile(id: profile.id)
                        }
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will permanently remove this profile. This cannot be undone.")
                }
            }
        }
    }
    
    // MARK: - Age Verification Step
    private var ageVerificationStep: some View {
        VStack(spacing: 28) {
            // Header
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 8) {
                Text("Verify Your Age")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("Your date of birth determines what content is available on this profile. This syncs with your account.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Date of Birth Picker
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
                    ageGroup = ProfileService.ageGroupFromDateOfBirth(newValue)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Age Group Result
            let computedAge = ProfileService.ageFromDateOfBirth(dateOfBirth)
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: ageGroup == .adult ? "checkmark.shield.fill" : "shield.fill")
                        .foregroundColor(ageGroupColor)
                    Text("Age: \(computedAge)")
                        .fontWeight(.semibold)
                }
                .font(.headline)
                
                Text("Content tier: \(ageGroup.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if ageGroup == .teen {
                    Text("Some mature content will be restricted on this profile.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                } else if ageGroup == .kids {
                    Text("Only kids-friendly content will be shown.")
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
            
            // Back button
            Button {
                withAnimation { step = .info }
            } label: {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Back to Profile Info")
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }
        }
    }
    
    private var ageGroupColor: Color {
        switch ageGroup {
        case .kids: return .green
        case .teen: return .orange
        case .adult: return .accentColor
        }
    }
    
    // MARK: - Save
    
    private func saveProfile() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        let finalAgeGroup: AgeGroup = isKidsProfile ? .kids : ageGroup
        let finalDOB: Date? = isKidsProfile ? nil : dateOfBirth
        
        if let existing = editingProfile {
            var updated = existing
            updated.name = trimmedName
            updated.avatar = selectedAvatar
            updated.color = selectedColor
            updated.isKids = isKidsProfile
            updated.ageGroup = finalAgeGroup
            updated.dateOfBirth = finalDOB
            updated.updatedAt = Date()
            profileService.updateProfile(updated)
        } else {
            let newProfile = UserProfile(
                name: trimmedName,
                avatar: selectedAvatar,
                color: selectedColor,
                ageGroup: finalAgeGroup,
                isKids: isKidsProfile,
                dateOfBirth: finalDOB
            )
            profileService.addProfile(newProfile)
            
            // If this is the first profile, auto-switch to it
            if profileService.profiles.count == 1 {
                profileService.switchToProfile(newProfile)
            }
        }
        
        dismiss()
    }
}
