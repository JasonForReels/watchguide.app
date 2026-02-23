//
//  ProfileService.swift
//  WatchGuide-MovieandTVtracker
//
//  Manages user profiles: creation, switching, persistence, and cloud sync
//

import Foundation
import Combine

@MainActor
class ProfileService: ObservableObject {
    static let shared = ProfileService()
    
    @Published private(set) var profiles: [UserProfile] = []
    @Published var activeProfile: UserProfile?
    @Published var needsProfileSelection = false
    
    /// Whether the profile picker has been shown at least once this app session.
    /// Resets every cold launch so the picker always appears on startup.
    private var hasShownPickerThisSession = false
    
    private let profilesKey = "user_profiles"
    private let activeProfileKey = "active_profile_id"
    private let documentsDirectory: URL
    private let profilesURL: URL
    
    private var supabaseURL: String {
        ApiKeyManager.shared.get(key: "SUPABASE_URL") ?? ""
    }
    
    private var supabaseAnonKey: String {
        ApiKeyManager.shared.get(key: "SUPABASE_ANON_KEY") ?? ""
    }
    
    /// Whether a cloud sync has already been performed this app session.
    private var hasSyncedThisSession = false
    
    private init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        profilesURL = documentsDirectory.appendingPathComponent("profiles.json")
        loadProfiles()
        // Automatically sync profiles from cloud on launch if authenticated
        syncFromCloudOnLaunchIfNeeded()
    }
    
    // MARK: - Persistence
    
    private func loadProfiles() {
        guard FileManager.default.fileExists(atPath: profilesURL.path) else { return }
        do {
            let data = try Data(contentsOf: profilesURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            profiles = try decoder.decode([UserProfile].self, from: data)
            
            // On cold launch, if there are multiple profiles, require selection (Netflix-style).
            // If there is exactly 1 profile, auto-select it.
            if profiles.count == 1, let onlyProfile = profiles.first {
                activeProfile = onlyProfile
                UserDefaults.standard.set(onlyProfile.id, forKey: activeProfileKey)
                applyProfileSettings(onlyProfile)
                hasShownPickerThisSession = true
            } else if profiles.count > 1 {
                // Don't auto-restore — force the "Who's Watching?" picker every launch
                activeProfile = nil
                needsProfileSelection = true
            }
        } catch {
            print("Error loading profiles: \(error)")
        }
    }
    
    private func saveProfiles() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(profiles)
            try data.write(to: profilesURL)
        } catch {
            print("Error saving profiles: \(error)")
        }
    }
    
    // MARK: - Profile CRUD
    
    func addProfile(_ profile: UserProfile) {
        profiles.append(profile)
        saveProfiles()
        syncProfilesToCloud()
    }
    
    func updateProfile(_ profile: UserProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            var updated = profile
            updated.updatedAt = Date()
            profiles[index] = updated
            saveProfiles()
            
            // If the active profile was updated, update it too
            if activeProfile?.id == profile.id {
                activeProfile = updated
                applyProfileSettings(updated)
            }
            syncProfilesToCloud()
        }
    }
    
    func deleteProfile(id: String) {
        guard profiles.count > 1 else { return } // Must have at least 1 profile
        profiles.removeAll { $0.id == id }
        saveProfiles()
        
        // If active profile was deleted, require new selection
        if activeProfile?.id == id {
            activeProfile = nil
            UserDefaults.standard.removeObject(forKey: activeProfileKey)
            needsProfileSelection = true
        }
        syncProfilesToCloud()
    }
    
    // MARK: - Profile Switching
    
    func switchToProfile(_ profile: UserProfile) {
        activeProfile = profile
        UserDefaults.standard.set(profile.id, forKey: activeProfileKey)
        needsProfileSelection = false
        hasShownPickerThisSession = true
        applyProfileSettings(profile)
    }
    
    func requestProfileSelection() {
        needsProfileSelection = true
    }

    func updateHeroCarouselLayout(widthRatio: Double, aspect: HeroCarouselAspect) {
        guard var profile = activeProfile else { return }
        profile.heroCarouselWidthRatio = widthRatio
        profile.heroCarouselAspect = aspect
        updateProfile(profile)
    }
    
    /// Resets the session flag so the picker will show again (e.g. after sign-out + sign-in)
    func resetSessionFlag() {
        hasShownPickerThisSession = false
        hasSyncedThisSession = false
    }

    
    /// Apply profile-based settings to the global UserSettings
    private func applyProfileSettings(_ profile: UserProfile) {
        var settings = StorageService.shared.settings
        
        if profile.isKids {
            settings.isKidsProfile = true
            settings.includeAdult = false
        } else {
            settings.isKidsProfile = false
            // Only enable adult content for 18+ profiles
            if profile.ageGroup == .adult {
                // Don't auto-enable adult, just allow it
            } else {
                settings.includeAdult = false
            }
        }
        
        StorageService.shared.updateSettings(settings)
    }
    
    // MARK: - Age Verification
    
    /// Calculates the age from a date of birth and returns the appropriate AgeGroup
    static func ageGroupFromDateOfBirth(_ dob: Date) -> AgeGroup {
        let calendar = Calendar.current
        let age = calendar.dateComponents([.year], from: dob, to: Date()).year ?? 0
        
        if age < 13 {
            return .kids
        } else if age < 18 {
            return .teen
        } else {
            return .adult
        }
    }
    
    /// Validates that the entered age matches the expected criteria
    static func ageFromDateOfBirth(_ dob: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.year], from: dob, to: Date()).year ?? 0
    }
    
    // MARK: - Has Profiles
    
    var hasProfiles: Bool {
        !profiles.isEmpty
    }
    
    var hasActiveProfile: Bool {
        activeProfile != nil
    }
    
    var isKidsProfileActive: Bool {
        activeProfile?.isKids == true
    }
    
    var activeAgeGroup: AgeGroup {
        activeProfile?.ageGroup ?? .adult
    }
    
    // MARK: - Cloud Sync
    
    /// Called once on launch: if the user has a restored session, silently fetch profiles from
    /// the cloud so that changes made on other devices are reflected immediately.
    private func syncFromCloudOnLaunchIfNeeded() {
        guard !hasSyncedThisSession else { return }
        
        // Defer the actual cloud check to the next run-loop iteration to avoid
        // circular singleton access during init (ProfileService → AuthService → StorageService).
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Small delay to let all singletons finish initializing first
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            
            // For Supabase sessions, require Supabase config
            // For iCloud sessions, always allow
            let isICloud = AuthService.shared.isICloudSession
            if !isICloud {
                guard !self.supabaseURL.isEmpty, !self.supabaseAnonKey.isEmpty else { return }
            }
            
            // Give auth session refresh a moment to complete (up to 2 seconds)
            for _ in 0..<10 {
                if AuthService.shared.isAuthenticated { break }
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            }
            
            guard AuthService.shared.isAuthenticated else { return }
            guard !self.hasSyncedThisSession else { return }
            self.hasSyncedThisSession = true
            await self.downloadProfilesFromCloud()
        }
    }
    
    /// Public method that can be called from views (e.g. ProfilePickerView)
    /// to ensure profiles are up-to-date from the cloud.
    func refreshFromCloudIfNeeded() {
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else { return }
        guard AuthService.shared.isAuthenticated else { return }
        
        Task { @MainActor in
            await downloadProfilesFromCloud()
        }
    }
    
    func syncProfilesToCloud() {
        guard AuthService.shared.isAuthenticated else { return }
        
        if AuthService.shared.isICloudSession {
            // CloudKit sync
            Task {
                do {
                    try await CloudKitSyncService.shared.uploadProfiles(profiles)
                } catch {
                    print("CloudKit profile sync failed: \(error)")
                }
            }
            return
        }
        
        // Supabase sync
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else { return }
        guard let userId = AuthService.shared.userId else { return }
        
        Task {
            do {
                try await uploadProfiles(userId: userId)
            } catch {
                print("Profile sync failed: \(error)")
            }
        }
    }
    
    func downloadProfilesFromCloud() async {
        guard AuthService.shared.isAuthenticated else { return }
        
        if AuthService.shared.isICloudSession {
            // CloudKit download
            do {
                let cloudProfiles = try await CloudKitSyncService.shared.downloadProfiles()
                if !cloudProfiles.isEmpty {
                    applyCloudProfiles(cloudProfiles)
                }
            } catch {
                print("CloudKit profile download failed: \(error)")
            }
            return
        }
        
        // Supabase download
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else { return }
        guard let userId = AuthService.shared.userId else { return }

        do {
            let cloudProfiles = try await fetchProfiles(userId: userId)
            applyCloudProfiles(cloudProfiles)
        } catch {
            print("Profile download failed: \(error)")
        }
    }

    /// Apply profiles from a cloud source and update selection state.
    func applyCloudProfiles(_ cloudProfiles: [UserProfile], preferredActiveId: String? = nil) {
        guard !cloudProfiles.isEmpty else { return }
        profiles = cloudProfiles
        saveProfiles()

        if let preferredActiveId = preferredActiveId {
            UserDefaults.standard.set(preferredActiveId, forKey: activeProfileKey)
        }

        // If only 1 profile, auto-select it
        if cloudProfiles.count == 1, let onlyProfile = cloudProfiles.first {
            activeProfile = onlyProfile
            UserDefaults.standard.set(onlyProfile.id, forKey: activeProfileKey)
            applyProfileSettings(onlyProfile)
            hasShownPickerThisSession = true
        } else if !hasShownPickerThisSession {
            // Multiple profiles and picker not shown yet — show it
            activeProfile = nil
            needsProfileSelection = true
        } else if let activeId = UserDefaults.standard.string(forKey: activeProfileKey),
                  let profile = cloudProfiles.first(where: { $0.id == activeId }) {
            // Picker already shown this session, just refresh the active profile data
            activeProfile = profile
            applyProfileSettings(profile)
        }
    }
    
    private func uploadProfiles(userId: String) async throws {
        // Delete existing profiles for this user
        let deleteURL = URL(string: "\(supabaseURL)/rest/v1/profiles?user_id=eq.\(userId)")!
        var deleteRequest = URLRequest(url: deleteURL)
        deleteRequest.httpMethod = "DELETE"
        deleteRequest.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let token = AuthService.shared.accessToken {
            deleteRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        deleteRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try? await URLSession.shared.data(for: deleteRequest)
        
        // Upload all profiles
        guard !profiles.isEmpty else { return }
        
        let dateFormatter = ISO8601DateFormatter()
        let syncedProfiles = profiles.map { profile in
            SyncedProfile(
                userId: userId,
                profileId: profile.id,
                name: profile.name,
                avatar: profile.avatar.rawValue,
                color: profile.color.rawValue,
                ageGroup: profile.ageGroup.rawValue,
                isKids: profile.isKids,
                dateOfBirth: profile.dateOfBirth.map { dateFormatter.string(from: $0) },
                heroCarouselWidthRatio: profile.heroCarouselWidthRatio,
                heroCarouselAspect: profile.heroCarouselAspect?.rawValue,
                createdAt: profile.createdAt,
                updatedAt: profile.updatedAt
            )
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(syncedProfiles)
        
        let uploadURL = URL(string: "\(supabaseURL)/rest/v1/profiles")!
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let token = AuthService.shared.accessToken {
            uploadRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        uploadRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        uploadRequest.addValue("return=representation", forHTTPHeaderField: "Prefer")
        uploadRequest.httpBody = body
        
        let (_, response) = try await URLSession.shared.data(for: uploadRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    private func fetchProfiles(userId: String) async throws -> [UserProfile] {
        var components = URLComponents(string: "\(supabaseURL)/rest/v1/profiles")!
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ]
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.addValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let token = AuthService.shared.accessToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let syncedProfiles = try decoder.decode([SyncedProfile].self, from: data)
        
        let dateFormatter = ISO8601DateFormatter()
        
        return syncedProfiles.compactMap { synced -> UserProfile? in
            guard let avatar = ProfileAvatar(rawValue: synced.avatar),
                  let color = ProfileColor(rawValue: synced.color),
                  let ageGroup = AgeGroup(rawValue: synced.ageGroup) else {
                return nil
            }
            
            let profile = UserProfile(
                name: synced.name,
                avatar: avatar,
                color: color,
                ageGroup: ageGroup,
                isKids: synced.isKids,
                dateOfBirth: synced.dateOfBirth.flatMap { dateFormatter.date(from: $0) },
                heroCarouselWidthRatio: synced.heroCarouselWidthRatio,
                heroCarouselAspect: synced.heroCarouselAspect.flatMap { HeroCarouselAspect(rawValue: $0) }
            )
            // Preserve the original ID for cross-device sync
            return UserProfile(
                id: synced.profileId,
                name: profile.name,
                avatar: profile.avatar,
                color: profile.color,
                ageGroup: profile.ageGroup,
                isKids: profile.isKids,
                dateOfBirth: profile.dateOfBirth,
                heroCarouselWidthRatio: profile.heroCarouselWidthRatio,
                heroCarouselAspect: profile.heroCarouselAspect,
                createdAt: synced.createdAt ?? Date(),
                updatedAt: synced.updatedAt ?? Date()
            )
        }
    }
    
    // MARK: - Clear All
    
    func clearAllProfiles() {
        profiles = []
        activeProfile = nil
        UserDefaults.standard.removeObject(forKey: activeProfileKey)
        needsProfileSelection = false
        hasShownPickerThisSession = false
        saveProfiles()
    }
}

// MARK: - UserProfile init with explicit ID (for cloud sync)
extension UserProfile {
    init(
        id: String,
        name: String,
        avatar: ProfileAvatar,
        color: ProfileColor,
        ageGroup: AgeGroup,
        isKids: Bool,
        dateOfBirth: Date?,
        heroCarouselWidthRatio: Double? = nil,
        heroCarouselAspect: HeroCarouselAspect? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.color = color
        self.ageGroup = ageGroup
        self.isKids = isKids
        self.dateOfBirth = dateOfBirth
        self.heroCarouselWidthRatio = heroCarouselWidthRatio
        self.heroCarouselAspect = heroCarouselAspect
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
