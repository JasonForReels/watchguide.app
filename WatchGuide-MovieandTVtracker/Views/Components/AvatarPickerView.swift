//
//  AvatarPickerView.swift
//  WatchGuide-MovieandTVtracker
//
//  Full-screen avatar picker that loads avatars from the remote JSON
//

import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(ImagePlayground)
import ImagePlayground
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

private extension Color {
    static var platformGray6: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGray6)
        #elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color.gray.opacity(0.12)
        #endif
    }

    static var platformGray5: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGray5)
        #elseif canImport(AppKit)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color.gray.opacity(0.18)
        #endif
    }

    static var platformGray4: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGray4)
        #elseif canImport(AppKit)
        return Color(nsColor: .separatorColor)
        #else
        return Color.gray.opacity(0.3)
        #endif
    }
}

struct AvatarPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var avatarService = AvatarService.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var storage = StorageService.shared
    
    let profileColor: ProfileColor
    let currentAvatarURL: String?
    let onSelect: (String) -> Void
    
    @State private var selectedURL: String?
    @State private var searchText = ""
    #if canImport(PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif
    @State private var photoPickerError: String?
    @State private var showCloudSyncDisclaimer = false
    @State private var pendingLocalPhotoURL: URL?
    @State private var isUploadingToCloud = false
    @State private var showImagePlayground = false
    @State private var imagePlaygroundConcept = "Stylized profile avatar portrait"
#if canImport(ImagePlayground)
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
#endif
    
    init(profileColor: ProfileColor, currentAvatarURL: String?, onSelect: @escaping (String) -> Void) {
        self.profileColor = profileColor
        self.currentAvatarURL = currentAvatarURL
        self.onSelect = onSelect
    }
    
    private var filteredCategories: [AvatarCategory] {
        if searchText.isEmpty {
            return avatarService.categories
        }
        let query = searchText.lowercased()
        return avatarService.categories.compactMap { category in
            let filtered = category.avatars.filter {
                $0.name.lowercased().contains(query) ||
                category.name.lowercased().contains(query)
            }
            guard !filtered.isEmpty else { return nil }
            return AvatarCategory(name: category.name, avatars: filtered)
        }
    }

    private var canUseImagePlayground: Bool {
#if canImport(ImagePlayground)
        if #available(iOS 18.2, *) {
            return storage.settings.useAppleIntelligenceSearch && supportsImagePlayground
        }
#endif
        return false
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if avatarService.isLoading && avatarService.categories.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading avatars...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = avatarService.error, avatarService.categories.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await avatarService.fetchAvatars(force: true) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    avatarGrid
                }
            }
            .navigationTitle("Avatars")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Search avatars")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let url = selectedURL {
                            onSelect(url)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedURL == nil)
                }
            }
            .task {
                await avatarService.fetchAvatars()
                // Pre-select current avatar
                selectedURL = currentAvatarURL
            }
            #if canImport(PhotosUI)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task { await importPhotoAvatar(from: newItem) }
            }
            #endif
            .alert("Sync Custom Avatar to Cloud?", isPresented: $showCloudSyncDisclaimer) {
                Button("Local Only", role: .cancel) {
                    if let pendingLocalPhotoURL {
                        selectedURL = pendingLocalPhotoURL.absoluteString
                    }
                    pendingLocalPhotoURL = nil
                }
                Button("Sync to Cloud") {
                    guard let pendingLocalPhotoURL else { return }
                    Task { await uploadPendingPhotoToCloud(localURL: pendingLocalPhotoURL) }
                }
            } message: {
                Text("If you choose Sync to Cloud, this photo will be uploaded to your account storage so it can appear on your other devices. Avoid sensitive photos.")
            }
#if canImport(ImagePlayground)
            .modifier(
                AvatarImagePlaygroundPresenter(
                    isPresented: $showImagePlayground,
                    concept: imagePlaygroundConcept,
                    isEnabled: canUseImagePlayground,
                    onCompletion: { generatedURL in
                        Task { await importGeneratedAvatar(from: generatedURL) }
                    }
                )
            )
#endif
        }
    }
    
    private var avatarGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                betaHeaderCard
                
                customPhotoSection
                
                ForEach(filteredCategories) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(category.name)
                            .font(.headline)
                            .fontWeight(.bold)
                            .padding(.horizontal, 16)
                        
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 72, maximum: 90), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            ForEach(category.avatars) { avatar in
                                AvatarGridItem(
                                    avatar: avatar,
                                    isSelected: selectedURL == avatar.url,
                                    profileColor: profileColor
                                ) {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedURL = avatar.url
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 16)
        }
    }
    
    private var betaHeaderCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flask.fill")
                .foregroundColor(.orange)
                .font(.subheadline)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Avatar Picker")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("BETA")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundColor(.orange)
                }
                
                Text("Photo avatars can be synced to your account, or kept local on this device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.platformGray6)
        )
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private var customPhotoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Photos")
                .font(.headline)
                .fontWeight(.bold)
                .padding(.horizontal, 16)
            
            HStack(spacing: 12) {
                if canUseImagePlayground {
                    Button {
                        imagePlaygroundConcept = "Stylized profile avatar portrait"
                        showImagePlayground = true
                    } label: {
                        imagePlaygroundTile
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Generate avatar with Apple Intelligence")
                    .help("Create an avatar with Image Playground")
                }

                #if canImport(PhotosUI)
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    customPhotoTile
                }
                .buttonStyle(.plain)
                #else
                customPhotoTile
                #endif
                
                if selectedURL?.hasPrefix("file://") == true {
                    selectedCustomPhotoPreview
                }
            }
            .padding(.horizontal, 16)
            
            if let photoPickerError, !photoPickerError.isEmpty {
                Text(photoPickerError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
            }
            
            if isUploadingToCloud {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Uploading avatar securely to your account...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var imagePlaygroundTile: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.platformGray6)
                    .frame(width: 68, height: 68)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.platformGray4, lineWidth: 1)
                    )

                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(profileColor.color)
            }

            Text("Generate")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 68)
        }
    }
    
    private var customPhotoTile: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.platformGray6)
                    .frame(width: 68, height: 68)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                selectedURL?.hasPrefix("file://") == true ? profileColor.color : .platformGray4,
                                lineWidth: selectedURL?.hasPrefix("file://") == true ? 3 : 1
                            )
                    )
                
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(profileColor.color)
            }
            
            Text("Choose Photo")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 68)
        }
    }
    
    private var selectedCustomPhotoPreview: some View {
        VStack(spacing: 6) {
            Group {
                if let selectedURL, let url = URL(string: selectedURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            fallbackPreview
                        case .empty:
                            ZStack {
                                Color.platformGray6
                                ProgressView().scaleEffect(0.7)
                            }
                        @unknown default:
                            fallbackPreview
                        }
                    }
                } else {
                    fallbackPreview
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(profileColor.color, lineWidth: 3)
            )
            
            Text("Selected")
                .font(.caption2)
                .foregroundColor(profileColor.color)
                .lineLimit(1)
                .frame(width: 68)
        }
    }
    
    private var fallbackPreview: some View {
        ZStack {
            Color.platformGray5
            Image(systemName: "person.fill")
                .foregroundColor(.secondary)
        }
    }
    
    #if canImport(PhotosUI)
    @MainActor
    private func importPhotoAvatar(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                photoPickerError = "Couldn't read that photo."
                return
            }
            guard let savedURL = savePhotoAvatarData(data) else {
                photoPickerError = "Couldn't save that photo."
                return
            }
            
            photoPickerError = nil
            pendingLocalPhotoURL = savedURL
            
            let canOfferCloudSync = authService.isAuthenticated
                && !ApiKeyManager.shared.get(key: "SUPABASE_URL").orEmpty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY").orEmpty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
            if canOfferCloudSync {
                showCloudSyncDisclaimer = true
            } else {
                selectedURL = savedURL.absoluteString
            }
        } catch {
            photoPickerError = "Failed to import photo."
        }
    }
    #endif
    
    @MainActor
    private func uploadPendingPhotoToCloud(localURL: URL) async {
        guard let userId = authService.userId else {
            pendingLocalPhotoURL = nil
            photoPickerError = "Sign in to sync this avatar to cloud."
            return
        }
        
        isUploadingToCloud = true
        defer {
            isUploadingToCloud = false
            pendingLocalPhotoURL = nil
        }
        
        do {
            let cloudURL = try await ProfileAvatarUploadService.shared.uploadAvatar(
                localFileURL: localURL,
                userId: userId,
                accessToken: authService.accessToken
            )
            selectedURL = cloudURL
            photoPickerError = nil
        } catch {
            photoPickerError = "Cloud sync failed. Please try again, or choose Local Only."
        }
    }

    @MainActor
    private func importGeneratedAvatar(from generatedURL: URL) async {
        do {
            let generatedData = try Data(contentsOf: generatedURL)
            guard let savedURL = savePhotoAvatarData(generatedData) else {
                photoPickerError = "Couldn't save the generated avatar."
                return
            }
            photoPickerError = nil
            pendingLocalPhotoURL = savedURL

            let canOfferCloudSync = authService.isAuthenticated
                && !ApiKeyManager.shared.get(key: "SUPABASE_URL").orEmpty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY").orEmpty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if canOfferCloudSync {
                showCloudSyncDisclaimer = true
            } else {
                selectedURL = savedURL.absoluteString
            }
        } catch {
            photoPickerError = "Failed to import generated avatar."
        }
    }
    
    private func savePhotoAvatarData(_ data: Data) -> URL? {
        do {
            let avatarsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("ProfileAvatars", isDirectory: true)
            guard let avatarsDirectory else { return nil }
            
            if !FileManager.default.fileExists(atPath: avatarsDirectory.path) {
                try FileManager.default.createDirectory(at: avatarsDirectory, withIntermediateDirectories: true)
            }
            
            let fileURL = avatarsDirectory.appendingPathComponent("avatar-\(UUID().uuidString).jpg")
            
            #if canImport(UIKit)
            if let image = UIImage(data: data), let compressed = image.jpegData(compressionQuality: 0.82) {
                try compressed.write(to: fileURL, options: [.atomic])
            } else {
                try data.write(to: fileURL, options: [.atomic])
            }
            #else
            try data.write(to: fileURL, options: [.atomic])
            #endif
            
            return fileURL
        } catch {
            return nil
        }
    }
}

#if canImport(ImagePlayground)
private struct AvatarImagePlaygroundPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let concept: String
    let isEnabled: Bool
    let onCompletion: (URL) -> Void
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.2, *), isEnabled, supportsImagePlayground {
            content.imagePlaygroundSheet(
                isPresented: $isPresented,
                concept: concept,
                onCompletion: { url in
                    onCompletion(url)
                },
                onCancellation: nil
            )
        } else {
            content
        }
    }
}
#endif

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

// MARK: - Avatar Grid Item
private struct AvatarGridItem: View {
    let avatar: AvatarItem
    let isSelected: Bool
    let profileColor: ProfileColor
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                AsyncImage(url: URL(string: avatar.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        ZStack {
                            Color.platformGray5
                            Image(systemName: "person.fill")
                                .foregroundColor(.secondary)
                        }
                    case .empty:
                        ZStack {
                            Color.platformGray6
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    @unknown default:
                        Color.platformGray5
                    }
                }
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isSelected ? profileColor.color : Color.clear,
                            lineWidth: 3
                        )
                )
                .shadow(
                    color: isSelected ? profileColor.color.opacity(0.4) : .clear,
                    radius: isSelected ? 6 : 0
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
                
                Text(avatar.name)
                    .font(.caption2)
                    .foregroundColor(isSelected ? profileColor.color : .secondary)
                    .lineLimit(1)
                    .frame(width: 68)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile Avatar Display View
/// Reusable component that shows the profile avatar image (if set) or falls back to the SF Symbol
struct ProfileAvatarImageView: View {
    let profile: UserProfile
    let size: CGFloat
    var showBorder: Bool = true
    
    var body: some View {
        if let avatarURL = profile.avatarImageURL,
           !avatarURL.isEmpty {
            if avatarURL.hasPrefix("e2ee-avatar://") {
                EncryptedProfileAvatarImageView(
                    profile: profile,
                    avatarReference: avatarURL,
                    size: size,
                    showBorder: showBorder
                )
            } else if let url = URL(string: avatarURL) {
            // Custom avatar image
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        fallbackIcon
                    case .empty:
                        ZStack {
                            profile.color.color.opacity(0.15)
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    @unknown default:
                        fallbackIcon
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                        .stroke(
                            showBorder ? profile.color.color.opacity(0.3) : Color.clear,
                            lineWidth: 2
                        )
                )
            } else {
                defaultAvatar
            }
        } else {
            defaultAvatar
        }
    }
    
    private var defaultAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(profile.color.color.opacity(0.15))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                        .stroke(
                            showBorder ? profile.color.color.opacity(0.3) : Color.clear,
                            lineWidth: 2
                        )
                )
            
            Image(systemName: profile.avatar.rawValue)
                .font(.system(size: size * 0.36))
                .foregroundColor(profile.color.color)
        }
    }
    
    private var fallbackIcon: some View {
        ZStack {
            profile.color.color.opacity(0.15)
            Image(systemName: profile.avatar.rawValue)
                .font(.system(size: size * 0.36))
                .foregroundColor(profile.color.color)
        }
    }
}

private struct EncryptedProfileAvatarImageView: View {
    let profile: UserProfile
    let avatarReference: String
    let size: CGFloat
    let showBorder: Bool
    
    @ObservedObject private var authService = AuthService.shared
    @State private var imageData: Data?
    @State private var didFail = false
    
    var body: some View {
        Group {
            if let imageData, let decryptedImage = decryptedImage(from: imageData) {
                decryptedImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if didFail {
                fallbackIcon
            } else {
                ZStack {
                    profile.color.color.opacity(0.15)
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .stroke(
                    showBorder ? profile.color.color.opacity(0.3) : Color.clear,
                    lineWidth: 2
                )
        )
        .task(id: avatarReference) {
            await loadEncryptedAvatar()
        }
    }

    private func decryptedImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }
    
    private func loadEncryptedAvatar() async {
        guard let userId = authService.userId else {
            didFail = true
            return
        }
        do {
            let data = try await EncryptedAvatarService.shared.decryptAvatarReference(
                avatarReference,
                userId: userId,
                accessToken: authService.accessToken
            )
            imageData = data
            didFail = false
        } catch {
            didFail = true
        }
    }
    
    private var fallbackIcon: some View {
        ZStack {
            profile.color.color.opacity(0.15)
            Image(systemName: profile.avatar.rawValue)
                .font(.system(size: size * 0.36))
                .foregroundColor(profile.color.color)
        }
    }
}
