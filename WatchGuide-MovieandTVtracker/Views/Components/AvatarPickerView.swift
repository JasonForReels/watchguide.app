//
//  AvatarPickerView.swift
//  WatchGuide-MovieandTVtracker
//
//  Full-screen avatar picker that loads avatars from the remote JSON
//

import SwiftUI

struct AvatarPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var avatarService = AvatarService.shared
    
    let profileColor: ProfileColor
    let currentAvatarURL: String?
    let onSelect: (String) -> Void
    
    @State private var selectedURL: String?
    @State private var searchText = ""
    
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
            .navigationTitle("Choose Avatar")
            .navigationBarTitleDisplayMode(.inline)
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
        }
    }
    
    private var avatarGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
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
                            Color(.systemGray5)
                            Image(systemName: "person.fill")
                                .foregroundColor(.secondary)
                        }
                    case .empty:
                        ZStack {
                            Color(.systemGray6)
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    @unknown default:
                        Color(.systemGray5)
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
           !avatarURL.isEmpty,
           let url = URL(string: avatarURL) {
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
            // Default SF Symbol avatar
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
