//
//  SettingsView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @ObservedObject private var storage = StorageService.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var profileService = ProfileService.shared
    @State private var settings: UserSettings
    @State private var showClearDataAlert = false
    @State private var showAuthSheet = false
    @State private var isManualUpload = false
    @State private var isManualDownload = false
    @State private var showPasscodeSetup = false
    @State private var showPasscodeEntry = false
    @State private var passcodeAction: PasscodeAction = .disableKids
    @State private var showEditProfile = false
    
    enum PasscodeAction {
        case disableKids       // Turn off kids profile
        case enableAdult       // Turn on "Include Adult Content"
        case changePasscode    // Change the parent passcode
    }
    
    init() {
        _settings = State(initialValue: StorageService.shared.settings)
    }
    
    var body: some View {
        Form {
            // Scout AI Banner (in a plain section)
            Section {
                ScoutPromoBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            
            // Account Section
            Section {
                if authService.isAuthenticated {
                    AccountView()
                } else {
                    Button {
                        showAuthSheet = true
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "person.circle")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sign In")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Sync your lists across all devices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Account")
            } footer: {
                if !authService.isAuthenticated {
                    Text("Sign in to sync your watchlist, watched items, and likes across all your devices")
                }
            }
            
            // Active Profile Section
            if authService.isAuthenticated && profileService.hasProfiles {
                Section {
                    if let profile = profileService.activeProfile {
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
                                        .font(.headline)
                                    
                                    if profile.isKids {
                                        Text("KIDS")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.green))
                                    }
                                }
                                
                                Text(profile.isKids ? "Kids (6-12)" : profile.ageGroup.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        Button {
                            showEditProfile = true
                        } label: {
                            HStack {
                                Image(systemName: "pencil")
                                    .foregroundColor(.accentColor)
                                Text("Edit Profile")
                            }
                        }
                        
                        Button {
                            profileService.requestProfileSelection()
                        } label: {
                            HStack {
                                Image(systemName: "person.2.fill")
                                    .foregroundColor(.accentColor)
                                Text("Switch Profile")
                            }
                        }
                    }
                } header: {
                    Text("Active Profile")
                } footer: {
                    if let profile = profileService.activeProfile {
                        if profile.isKids {
                            Text("Kids profile is active. Content is restricted to ages 6-12. Switch to a different profile to access all content.")
                        } else if profile.ageGroup == .teen {
                            Text("Teen profile is active. Some mature content may be restricted.")
                        }
                    }
                }
            }
            
            // Region & Language
            Section("Region & Language") {
                Picker("Region", selection: $settings.region) {
                    ForEach(regionOptions, id: \.code) { region in
                        Text(region.name).tag(region.code)
                    }
                }
                
                Picker("Language", selection: $settings.preferredLanguage) {
                    ForEach(languageOptions, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
            }
            
            // Kids Profile
            Section {
                Toggle("Kids Profile", isOn: Binding(
                    get: { settings.isKidsProfile },
                    set: { newValue in
                        if newValue {
                            // Turning ON kids profile — show passcode setup
                            if settings.parentPasscode == nil {
                                showPasscodeSetup = true
                            } else {
                                settings.isKidsProfile = true
                                settings.includeAdult = false // Force restrict content
                            }
                        } else {
                            // Turning OFF kids profile — require passcode
                            if settings.parentPasscode != nil {
                                passcodeAction = .disableKids
                                showPasscodeEntry = true
                            } else {
                                settings.isKidsProfile = false
                            }
                        }
                    }
                ))
                
                if settings.isKidsProfile {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundColor(.green)
                        Text("Kids mode is active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if settings.parentPasscode != nil {
                    Button {
                        passcodeAction = .changePasscode
                        showPasscodeEntry = true
                    } label: {
                        HStack {
                            Image(systemName: "lock.rotation")
                                .foregroundColor(.accentColor)
                            Text("Change Parent Passcode")
                        }
                    }
                }
            } header: {
                Text("Parental Controls")
            } footer: {
                if settings.isKidsProfile {
                    Text("Scout AI is hidden and content is restricted to ages 13 and under. A parent passcode is required to change these settings.")
                } else {
                    Text("Enable Kids Profile to restrict content to ages 13 and under and hide Scout AI. A parent passcode protects the setting.")
                }
            }
            
            // Display Options
            Section("Display") {
                Toggle("Compact Mode", isOn: $settings.compactMode)
                Toggle("Ambient Mode", isOn: $settings.ambientModeEnabled)
                Toggle("Auto-play Trailers", isOn: $settings.autoPlayTrailers)
                Toggle("Mute Trailers on Autoplay", isOn: $settings.autoPlayTrailersMuted)
                
                // Include Adult Content toggle — only affects TMDB browse results, NOT Scout AI
                Toggle("Include Adult Content (Browse)", isOn: Binding(
                    get: { settings.includeAdult },
                    set: { newValue in
                        if newValue && settings.parentPasscode != nil {
                            // Require passcode to enable adult content
                            passcodeAction = .enableAdult
                            showPasscodeEntry = true
                        } else {
                            settings.includeAdult = newValue
                        }
                    }
                ))
                .disabled(settings.isKidsProfile) // Cannot enable adult content in kids mode
                
                if !settings.isKidsProfile {
                    Picker("Hero Carousel", selection: $settings.heroCarouselSource) {
                        ForEach(HeroCarouselSource.allCases, id: \.rawValue) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                }
            }
            
            // Home Screen Customization
            Section("Home Screen") {
                NavigationLink(destination: BrowseRowsSettingsView()) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundColor(.accentColor)
                            .frame(width: 24)
                        Text("Browse Rows")
                        Spacer()
                        Text("\(storage.browseRows.filter { $0.isEnabled }.count) enabled")
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                }
                

                
                NavigationLink(destination: NetworkHubsSettingsView()) {
                    HStack {
                        Image(systemName: "play.tv")
                            .foregroundColor(.purple)
                            .frame(width: 24)
                        Text("Networks")
                        Spacer()
                        Text("\(storage.networkHubs.filter { $0.isEnabled }.count) enabled")
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                }
                
                NavigationLink(destination: CustomJSONHubsSettingsView()) {
                    HStack {
                        Image(systemName: "square.grid.3x3.fill")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        Text("Hub Customisation")
                        Spacer()
                        Text("\(storage.customJSONHubs.filter { $0.isEnabled }.count) active")
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                }
            }
            
            // Cloud Sync
            Section("Cloud Sync") {
                Toggle("Enable Cloud Sync", isOn: Binding(
                    get: { storage.cloudSyncEnabled },
                    set: { storage.setCloudSyncEnabled($0) }
                ))
                
                if !storage.isCloudConfigured {
                    NavigationLink(destination: SupabaseSetupGuideView()) {
                        Label("Setup Guide", systemImage: "cloud.fill")
                    }
                    Text("Supabase is not configured. Cloud sync will remain off until setup is complete.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Last Sync")
                    Spacer()
                    if let lastSync = storage.lastSyncTime {
                        Text(lastSync.formatted(.relative(presentation: .named)))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never")
                            .foregroundColor(.secondary)
                    }
                }
                
                if let error = storage.lastSyncError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
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
                    if isManualUpload {
                        Label("Uploading...", systemImage: "arrow.up.circle")
                    } else {
                        Label("Upload to Cloud", systemImage: "arrow.up.circle")
                    }
                }
                .disabled(isManualDownload || isManualUpload)
                
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
                    if isManualDownload {
                        Label("Downloading...", systemImage: "arrow.down.circle")
                    } else {
                        Label("Download from Cloud", systemImage: "arrow.down.circle")
                    }
                }
                .disabled(isManualDownload || isManualUpload)
            }
            

            

            
            // Data Management
            Section("Data Management") {
                Button(role: .destructive) {
                    showClearDataAlert = true
                } label: {
                    Text("Clear All Data")
                }
            }
            
            // About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersionString)
                        .foregroundColor(.secondary)
                }
                
                Link(destination: URL(string: "https://www.themoviedb.org/")!) {
                    HStack {
                        Text("Powered by TMDB")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
                
                Link(destination: URL(string: "https://www.omdbapi.com/")!) {
                    HStack {
                        Text("Ratings by OMDb")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
                
                Link(destination: URL(string: "https://publicmetadb.com/")!) {
                    HStack {
                        Text("Lists by PublicMetaDB")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: settings) { _, newValue in
            storage.updateSettings(newValue)
        }
        .alert("Clear All Data?", isPresented: $showClearDataAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                // Clear all local data
            }
        } message: {
            Text("This will remove all your lists, watched history, and preferences. This cannot be undone.")
        }
        .sheet(isPresented: $showAuthSheet) {
            AuthView()
        }
        .sheet(isPresented: $showPasscodeSetup) {
            ParentPasscodeSetupSheet { passcode in
                settings.parentPasscode = passcode
                settings.isKidsProfile = true
                settings.includeAdult = false
            }
        }
        .sheet(isPresented: $showPasscodeEntry) {
            ParentPasscodeEntrySheet(
                storedPasscode: settings.parentPasscode ?? ""
            ) {
                // Passcode verified — perform the action
                switch passcodeAction {
                case .disableKids:
                    settings.isKidsProfile = false
                case .enableAdult:
                    settings.includeAdult = true
                case .changePasscode:
                    // After verifying old passcode, show setup for new one
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showPasscodeSetup = true
                    }
                }
            }
        }
        .sheet(isPresented: $showEditProfile) {
            if let profile = profileService.activeProfile {
                ProfileSetupView(mode: .edit(profile))
            }
        }
    }
    
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(version)"
    }
    
    private var regionOptions: [(code: String, name: String)] {
        [
            ("US", "United States"),
            ("GB", "United Kingdom"),
            ("CA", "Canada"),
            ("AU", "Australia"),
            ("ZA", "South Africa"),
            ("DE", "Germany"),
            ("FR", "France"),
            ("JP", "Japan"),
            ("KR", "South Korea"),
            ("IN", "India"),
            ("BR", "Brazil"),
            ("NZ", "New Zealand"),
            ("NG", "Nigeria"),
            ("KE", "Kenya"),
        ]
    }
    
    private var languageOptions: [(code: String, name: String)] {
        [
            ("en", "English"),
            ("es", "Spanish"),
            ("fr", "French"),
            ("de", "German"),
            ("ja", "Japanese"),
            ("ko", "Korean"),
            ("pt", "Portuguese"),
            ("zh", "Chinese"),
        ]
    }
}

// MARK: - Browse Rows Settings
struct BrowseRowsSettingsView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var rows: [BrowseRowConfig] = []
    
    var body: some View {
        List {
            ForEach($rows) { $row in
                HStack {
                    Toggle(row.title, isOn: $row.isEnabled)
                }
            }
            .onMove { from, to in
                rows.move(fromOffsets: from, toOffset: to)
                updateSortOrder()
            }
        }
        .navigationTitle("Browse Rows")
        .toolbar {
            EditButton()
        }
        .onAppear {
            rows = storage.browseRows.sorted { $0.sortOrder < $1.sortOrder }
        }
        .onDisappear {
            storage.updateBrowseRows(rows)
        }
    }
    
    private func updateSortOrder() {
        for (index, _) in rows.enumerated() {
            rows[index].sortOrder = index
        }
    }
}

// MARK: - Network Hubs Settings (Streaming Services)
struct NetworkHubsSettingsView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var hubs: [NetworkHub] = []
    
    var body: some View {
        List {
            Section {
                ForEach($hubs) { $hub in
                    HStack {
                        if let logoURL = hub.logoURL, let url = URL(string: logoURL) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 60, height: 30)
                                        .colorInvert()
                                        .environment(\.colorScheme, .light)
                                default:
                                    Text(hub.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                            }
                        } else {
                            Text(hub.name)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $hub.isEnabled)
                            .labelsHidden()
                    }
                }
                .onMove { from, to in
                    hubs.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text("Streaming Services")
            } footer: {
                Text("Drag to reorder, toggle to show/hide on Browse screen")
            }
        }
        .navigationTitle("Networks")
        .toolbar {
            EditButton()
        }
        .onAppear {
            hubs = storage.networkHubs.sorted { $0.sortOrder < $1.sortOrder }
        }
        .onDisappear {
            storage.reorderNetworkHubs(hubs)
        }
    }
}

// MARK: - Company Hubs Settings (Legacy)
struct CompanyHubsSettingsView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var showAddHub = false
    
    var body: some View {
        List {
            ForEach(storage.companyHubs) { hub in
                HStack {
                    VStack(alignment: .leading) {
                        Text(hub.name)
                            .fontWeight(.medium)
                        Text("\(hub.companyIds.count + hub.networkIds.count) sources")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { hub.isEnabled },
                        set: { newValue in
                            var updatedHub = hub
                            updatedHub.isEnabled = newValue
                            storage.updateCompanyHub(updatedHub)
                        }
                    ))
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    storage.deleteCompanyHub(id: storage.companyHubs[index].id)
                }
            }
        }
        .navigationTitle("Company Hubs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddHub = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddHub) {
            AddCompanyHubSheet()
        }
    }
}

// MARK: - Add Company Hub Sheet
struct AddCompanyHubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var storage = StorageService.shared
    @State private var name = ""
    @State private var companyIdsText = ""
    @State private var networkIdsText = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Hub Name") {
                    TextField("Name", text: $name)
                }
                
                Section {
                    TextField("e.g., 420, 174", text: $companyIdsText)
                        .keyboardType(.numbersAndPunctuation)
                } header: {
                    Text("Company IDs")
                } footer: {
                    Text("Comma-separated TMDB company IDs")
                }
                
                Section {
                    TextField("e.g., 213, 49", text: $networkIdsText)
                        .keyboardType(.numbersAndPunctuation)
                } header: {
                    Text("Network IDs")
                } footer: {
                    Text("Comma-separated TMDB network IDs (for TV)")
                }
            }
            .navigationTitle("Add Company Hub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addHub()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func addHub() {
        let companyIds = companyIdsText
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        
        let networkIds = networkIdsText
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        
        let hub = CompanyHub(
            name: name,
            companyIds: companyIds,
            networkIds: networkIds
        )
        
        storage.addCompanyHub(hub)
        dismiss()
    }
}

// MARK: - Imported Lists Settings View (PublicMetaDB)
struct ImportedListsSettingsView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var showAddList = false
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            // Info Section
            Section {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PublicMetaDB Connected")
                            .fontWeight(.medium)
                        Text("Import curated movie & TV lists")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Status")
            } footer: {
                Text("PublicMetaDB provides access to curated lists of movies and TV shows")
            }
            
            // Error message
            if let error = errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Imported Lists
            if !storage.importedLists.isEmpty {
                Section("Imported Lists") {
                    ForEach(storage.importedLists) { list in
                        ImportedListRowView(list: list)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            storage.deleteImportedList(id: storage.importedLists[index].id)
                        }
                    }
                }
            }
            
            // Add List
            Section {
                Button {
                    showAddList = true
                } label: {
                    Label("Add List by ID or URL", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("PublicMetaDB")
        .sheet(isPresented: $showAddList) {
            AddImportedListSheet()
        }
    }
}

// MARK: - Imported List Row View
struct ImportedListRowView: View {
    let list: ImportedListItem
    @ObservedObject private var storage = StorageService.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(list.displayName)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text("\(list.items.count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if list.showOnHome {
                        Label("Home", systemImage: "house.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                    
                    if let synced = list.lastSynced {
                        Text("Synced \(synced.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { list.showOnHome },
                set: { newValue in
                    var updatedList = list
                    updatedList.showOnHome = newValue
                    storage.updateImportedList(updatedList)
                }
            ))
            .labelsHidden()
        }
    }
}

// MARK: - Add Imported List Sheet
struct AddImportedListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var storage = StorageService.shared
    @State private var listIdOrURL = ""
    @State private var customName = ""
    @State private var showOnHome = true
    @State private var isLoading = false
    @State private var error: String?
    @State private var previewInfo: PMDBListInfo?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List ID or URL", text: $listIdOrURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: listIdOrURL) { _, _ in
                            previewInfo = nil
                            error = nil
                        }
                    
                    Button("Preview List") {
                        Task { await previewList() }
                    }
                    .disabled(listIdOrURL.isEmpty || isLoading)
                } header: {
                    Text("PublicMetaDB List ID or URL")
                } footer: {
                    Text("Enter the list ID or paste the full URL from publicmetadb.com")
                }
                
                // Preview
                if let info = previewInfo {
                    Section("Preview") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(info.name)
                                .font(.headline)
                            
                            if let desc = info.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            
                            HStack {
                                if let count = info.itemCount {
                                    Label("\(count) items", systemImage: "film.stack")
                                }
                                if let likes = info.likes {
                                    Label("\(likes) likes", systemImage: "heart")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    Section {
                        TextField("Custom Name (optional)", text: $customName)
                        
                        Toggle("Show on Home Screen", isOn: $showOnHome)
                    } header: {
                        Text("Options")
                    }
                }
                
                if let error = error {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(error)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await addList() }
                    }
                    .disabled(previewInfo == nil || isLoading)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    private func extractListId() -> String {
        var id = listIdOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle URL formats
        if id.contains("publicmetadb.com") {
            // Try to extract the list ID from various URL formats
            if let url = URL(string: id) {
                let pathComponents = url.pathComponents
                if let listIndex = pathComponents.firstIndex(of: "lists"),
                   listIndex + 1 < pathComponents.count {
                    id = pathComponents[listIndex + 1]
                } else if let lastComponent = pathComponents.last, !lastComponent.isEmpty {
                    id = lastComponent
                }
            }
        }
        
        return id
    }
    
    private func previewList() async {
        isLoading = true
        error = nil
        
        let listId = extractListId()
        
        do {
            previewInfo = try await PublicMetaDBService.shared.getListInfo(listId: listId)
        } catch {
            self.error = "Could not find list. Please check the ID or URL."
        }
        
        isLoading = false
    }
    
    private func addList() async {
        guard let info = previewInfo else { return }
        
        isLoading = true
        let listId = extractListId()
        
        var newList = ImportedListItem(
            name: info.name,
            listId: listId,
            showOnHome: showOnHome
        )
        
        if !customName.isEmpty {
            newList.customName = customName
        }
        
        // Fetch items from PublicMetaDB
        do {
            newList.items = try await PublicMetaDBService.shared.fetchListItemsAsSavedMedia(listId: listId)
            newList.lastSynced = Date()
        } catch {
            print("Failed to fetch list items: \(error)")
        }
        
        storage.addImportedList(newList)
        
        // Also create a home row if showOnHome is enabled
        if showOnHome {
            let homeRow = CustomHomeRow.importedListRow(
                name: newList.displayName,
                listId: newList.id,
                sortOrder: storage.customHomeRows.count
            )
            storage.addCustomHomeRow(homeRow)
        }
        
        isLoading = false
        dismiss()
    }
}

// MARK: - Custom Home Rows Settings View
struct CustomHomeRowsSettingsView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var showAddRow = false
    
    var body: some View {
        List {
            if storage.customHomeRows.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Custom Rows")
                            .font(.headline)
                        Text("Add imported list rows or custom hubs to personalize your home screen")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section("Custom Rows") {
                    ForEach(storage.customHomeRows.sorted { $0.sortOrder < $1.sortOrder }) { row in
                        HStack {
                            Image(systemName: row.rowType == .importedList ? "list.bullet.clipboard" : "photo.on.rectangle")
                                .foregroundColor(row.rowType == .importedList ? .orange : .purple)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .fontWeight(.medium)
                                Text(row.rowType == .importedList ? "Imported List" : "Custom Hub")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { row.isEnabled },
                                set: { newValue in
                                    var updatedRow = row
                                    updatedRow.isEnabled = newValue
                                    storage.updateCustomHomeRow(updatedRow)
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                    .onDelete { indexSet in
                        let sortedRows = storage.customHomeRows.sorted { $0.sortOrder < $1.sortOrder }
                        for index in indexSet {
                            storage.deleteCustomHomeRow(id: sortedRows[index].id)
                        }
                    }
                    .onMove { from, to in
                        var rows = storage.customHomeRows.sorted { $0.sortOrder < $1.sortOrder }
                        rows.move(fromOffsets: from, toOffset: to)
                        storage.reorderCustomHomeRows(rows)
                    }
                }
            }
            
            Section {
                Button {
                    showAddRow = true
                } label: {
                    Label("Add Custom Row", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Custom Rows")
        .toolbar {
            EditButton()
        }
        .sheet(isPresented: $showAddRow) {
            AddCustomHomeRowSheet()
        }
    }
}

// MARK: - Add Custom Home Row Sheet
struct AddCustomHomeRowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var storage = StorageService.shared
    
    // MDBList import states
    @State private var mdblistURL = ""
    @State private var isLoadingMDBList = false
    @State private var mdblistError: String?
    @State private var previewItems: [SavedMediaItem] = []
    @State private var mdblistName = ""
    @State private var customName = ""
    @State private var imageURL = ""
    
    var body: some View {
        NavigationStack {
            Form {
                // MDBList URL input - required for custom rows
                Section {
                    TextField("e.g. username/list-name", text: $mdblistURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: mdblistURL) { _, _ in
                            previewItems = []
                            mdblistName = ""
                            mdblistError = nil
                        }
                    
                    Button {
                        Task { await previewMDBList() }
                    } label: {
                        HStack {
                            Text("Load List")
                            if isLoadingMDBList {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(mdblistURL.isEmpty || isLoadingMDBList)
                } header: {
                    Label("MDBList URL (Required)", systemImage: "list.star")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom rows are powered by MDBList. Enter the list URL or ID.")
                        Text("Find lists at mdblist.com")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let error = mdblistError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if !previewItems.isEmpty {
                    Section("Preview (\(previewItems.count) items)") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(previewItems.prefix(8)) { item in
                                    VStack(spacing: 4) {
                                        PosterImageView(posterPath: item.posterPath, size: .small)
                                            .frame(width: 50, height: 75)
                                        Text(item.title)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .frame(width: 50)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    
                    Section("Options") {
                        TextField("Custom Name (optional)", text: $customName)
                        TextField("Header Image URL (optional)", text: $imageURL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    
                    if !imageURL.isEmpty, let url = URL(string: imageURL) {
                        Section("Header Preview") {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 60)
                                        .clipped()
                                        .cornerRadius(8)
                                case .failure:
                                    Text("Invalid image URL")
                                        .foregroundColor(.red)
                                default:
                                    ProgressView()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Custom Row")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addRow()
                    }
                    .disabled(previewItems.isEmpty)
                }
            }
        }
    }
    
    private func previewMDBList() async {
        isLoadingMDBList = true
        mdblistError = nil
        
        let listId = MDBListService.shared.parseListId(from: mdblistURL)
        
        // Extract name from URL
        if listId.contains("/") {
            let components = listId.split(separator: "/")
            if components.count >= 2 {
                mdblistName = String(components.last ?? "MDBList")
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized
            }
        } else {
            mdblistName = "MDBList"
        }
        
        do {
            previewItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: listId)
            if previewItems.isEmpty {
                mdblistError = "List is empty or could not be found."
            }
        } catch {
            mdblistError = "Failed to load list. Please check the URL or ID."
            print("MDBList error: \(error)")
        }
        
        isLoadingMDBList = false
    }
    
    private func addRow() {
        // Create a new imported list from MDBList
        let listId = MDBListService.shared.parseListId(from: mdblistURL)
        let finalName = customName.isEmpty ? mdblistName : customName
        
        var newList = ImportedListItem(
            name: finalName,
            listId: listId,
            showOnHome: true,
            source: .mdblist
        )
        newList.items = previewItems
        newList.lastSynced = Date()
        
        if !customName.isEmpty {
            newList.customName = customName
        }
        
        // Add the imported list to storage
        storage.addImportedList(newList)
        
        // Create a custom home row with the items
        var row = CustomHomeRow.hubRow(
            name: finalName,
            imageURL: imageURL.isEmpty ? nil : imageURL,
            sortOrder: storage.customHomeRows.count
        )
        row.items = previewItems
        
        storage.addCustomHomeRow(row)
        dismiss()
    }
}

// MARK: - Supabase Setup Guide View
struct SupabaseSetupGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "cloud.fill")
                            .font(.largeTitle)
                            .foregroundColor(.green)
                        Text("Cloud Sync Setup")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    
                    Text("Follow these steps to enable cloud syncing for your watchlist, watched items, and liked items.")
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
                
                // Step 1
                SetupStepView(
                    number: 1,
                    title: "Link Supabase Project",
                    description: "In Milq, go to Sidebar → Supabase and link your Supabase project. If you don't have one, create a free account at supabase.com.",
                    iconName: "link"
                )
                
                // Step 2
                SetupStepView(
                    number: 2,
                    title: "Create Database Table",
                    description: "In your Supabase Dashboard, go to SQL Editor → New Query and run the SQL schema below.",
                    iconName: "tablecells"
                )
                
                // SQL Code Block
                VStack(alignment: .leading, spacing: 8) {
                    Text("SQL Schema")
                        .font(.headline)
                    
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(sqlSchema)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    
                    Button {
                        UIPasteboard.general.string = sqlSchema
                    } label: {
                        Label("Copy SQL", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(12)
                
                // Step 3
                SetupStepView(
                    number: 3,
                    title: "Enable Cloud Sync",
                    description: "Return to Settings and toggle on 'Enable Cloud Sync'. Your data will automatically sync when you add or remove items.",
                    iconName: "checkmark.circle"
                )
                
                // Step 4
                SetupStepView(
                    number: 4,
                    title: "Initial Sync",
                    description: "Use 'Sync Options' to upload your existing data to the cloud or download from cloud to this device.",
                    iconName: "arrow.triangle.2.circlepath"
                )
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle("Setup Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var sqlSchema: String {
        """
        -- ===================================================
        -- WatchGuide Cloud Sync — Full Schema
        -- Run this entire script in Supabase SQL Editor
        -- ===================================================

        -- 1. Media Items (watchlist, watched, liked)
        CREATE TABLE IF NOT EXISTS media_items (
            id SERIAL PRIMARY KEY,
            device_id TEXT NOT NULL,
            list_type TEXT NOT NULL,
            media_id INTEGER NOT NULL,
            media_type TEXT NOT NULL,
            title TEXT NOT NULL,
            poster_path TEXT,
            backdrop_path TEXT,
            year TEXT,
            vote_average DOUBLE PRECISION,
            overview TEXT,
            added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            UNIQUE(device_id, list_type, media_id, media_type)
        );

        -- 2. User Settings (region, kids profile, passcode, display prefs)
        CREATE TABLE IF NOT EXISTS user_settings (
            id SERIAL PRIMARY KEY,
            user_id TEXT NOT NULL UNIQUE,
            region TEXT DEFAULT 'US',
            preferred_language TEXT DEFAULT 'en',
            include_adult BOOLEAN DEFAULT FALSE,
            auto_play_trailers BOOLEAN DEFAULT FALSE,
            auto_play_trailers_muted BOOLEAN DEFAULT TRUE,
            compact_mode BOOLEAN DEFAULT FALSE,
            ambient_mode_enabled BOOLEAN DEFAULT FALSE,
            hero_carousel_source TEXT DEFAULT 'trending_movies',
            is_kids_profile BOOLEAN DEFAULT FALSE,
            parent_passcode TEXT,
            updated_at TIMESTAMPTZ DEFAULT NOW()
        );

        -- 3. Custom Lists (user-created lists)
        CREATE TABLE IF NOT EXISTS custom_lists (
            id SERIAL PRIMARY KEY,
            user_id TEXT NOT NULL,
            list_id TEXT NOT NULL,
            name TEXT NOT NULL,
            description TEXT,
            icon_name TEXT DEFAULT 'folder.fill',
            display_style TEXT DEFAULT 'row',
            created_at TIMESTAMPTZ DEFAULT NOW(),
            updated_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(user_id, list_id)
        );

        -- 4. Custom List Items
        CREATE TABLE IF NOT EXISTS custom_list_items (
            id SERIAL PRIMARY KEY,
            user_id TEXT NOT NULL,
            list_id TEXT NOT NULL,
            media_id INTEGER NOT NULL,
            media_type TEXT NOT NULL,
            title TEXT NOT NULL,
            poster_path TEXT,
            backdrop_path TEXT,
            year TEXT,
            vote_average DOUBLE PRECISION,
            overview TEXT,
            sort_order INTEGER DEFAULT 0,
            added_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(user_id, list_id, media_id, media_type)
        );

        -- 5. Browse Config (row visibility & order)
        CREATE TABLE IF NOT EXISTS browse_config (
            id SERIAL PRIMARY KEY,
            user_id TEXT NOT NULL,
            row_id TEXT NOT NULL,
            row_type TEXT NOT NULL,
            title TEXT NOT NULL,
            is_enabled BOOLEAN DEFAULT TRUE,
            sort_order INTEGER DEFAULT 0,
            UNIQUE(user_id, row_id)
        );

        -- 6. Extension Lists (MDBList / PublicMetaDB)
        CREATE TABLE IF NOT EXISTS extension_lists (
            id SERIAL PRIMARY KEY,
            user_id TEXT NOT NULL,
            list_id TEXT NOT NULL,
            name TEXT NOT NULL,
            source TEXT NOT NULL,
            custom_name TEXT,
            show_on_home BOOLEAN DEFAULT FALSE,
            last_synced TIMESTAMPTZ,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(user_id, list_id)
        );

        -- 7. Extension List Items
        CREATE TABLE IF NOT EXISTS extension_list_items (
            id SERIAL PRIMARY KEY,
            user_id TEXT NOT NULL,
            list_id TEXT NOT NULL,
            media_id INTEGER NOT NULL,
            media_type TEXT NOT NULL,
            title TEXT NOT NULL,
            poster_path TEXT,
            backdrop_path TEXT,
            year TEXT,
            vote_average DOUBLE PRECISION,
            overview TEXT,
            sort_order INTEGER DEFAULT 0,
            UNIQUE(user_id, list_id, media_id, media_type)
        );

        -- 8. Custom Home Rows
        CREATE TABLE IF NOT EXISTS custom_home_rows (
            id SERIAL PRIMARY KEY,
            user_id TEXT NOT NULL,
            row_id TEXT NOT NULL,
            name TEXT NOT NULL,
            row_type TEXT NOT NULL,
            imported_list_id TEXT,
            hub_image_url TEXT,
            is_enabled BOOLEAN DEFAULT TRUE,
            sort_order INTEGER DEFAULT 0,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(user_id, row_id)
        );

        -- 9. Network Hubs Config (streaming service visibility & order)
        CREATE TABLE IF NOT EXISTS network_hubs_config (
            id SERIAL PRIMARY KEY,
            user_id TEXT NOT NULL,
            hub_id TEXT NOT NULL,
            is_enabled BOOLEAN DEFAULT TRUE,
            sort_order INTEGER DEFAULT 0,
            UNIQUE(user_id, hub_id)
        );

        -- 10. Hidden Sections (which default browse sections are hidden)
        CREATE TABLE IF NOT EXISTS hidden_sections (
            id SERIAL PRIMARY KEY,
            user_id TEXT NOT NULL UNIQUE,
            hide_studios_row BOOLEAN DEFAULT FALSE,
            hide_networks_row BOOLEAN DEFAULT FALSE,
            hide_for_you_row BOOLEAN DEFAULT FALSE,
            hide_discover_section BOOLEAN DEFAULT FALSE
        );

        -- 11. Profiles (user profiles with age verification)
        CREATE TABLE IF NOT EXISTS profiles (
            id SERIAL PRIMARY KEY,
            user_id TEXT NOT NULL,
            profile_id TEXT NOT NULL,
            name TEXT NOT NULL,
            avatar TEXT NOT NULL DEFAULT 'popcorn.fill',
            color TEXT NOT NULL DEFAULT 'blue',
            age_group TEXT NOT NULL DEFAULT 'adult',
            is_kids BOOLEAN DEFAULT FALSE,
            date_of_birth TEXT,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            updated_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(user_id, profile_id)
        );

        -- ===================================================
        -- Enable Row Level Security on ALL tables
        -- ===================================================
        ALTER TABLE media_items ENABLE ROW LEVEL SECURITY;
        ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;
        ALTER TABLE custom_lists ENABLE ROW LEVEL SECURITY;
        ALTER TABLE custom_list_items ENABLE ROW LEVEL SECURITY;
        ALTER TABLE browse_config ENABLE ROW LEVEL SECURITY;
        ALTER TABLE extension_lists ENABLE ROW LEVEL SECURITY;
        ALTER TABLE extension_list_items ENABLE ROW LEVEL SECURITY;
        ALTER TABLE custom_home_rows ENABLE ROW LEVEL SECURITY;
        ALTER TABLE network_hubs_config ENABLE ROW LEVEL SECURITY;
        ALTER TABLE hidden_sections ENABLE ROW LEVEL SECURITY;
        ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

        -- ===================================================
        -- RLS Policies — allow all for anon & authenticated
        -- ===================================================
        CREATE POLICY "Allow all for anon" ON media_items FOR ALL TO anon USING (true) WITH CHECK (true);
        CREATE POLICY "Allow all for auth" ON media_items FOR ALL TO authenticated USING (true) WITH CHECK (true);

        CREATE POLICY "Allow all for anon" ON user_settings FOR ALL TO anon USING (true) WITH CHECK (true);
        CREATE POLICY "Allow all for auth" ON user_settings FOR ALL TO authenticated USING (true) WITH CHECK (true);

        CREATE POLICY "Allow all for anon" ON custom_lists FOR ALL TO anon USING (true) WITH CHECK (true);
        CREATE POLICY "Allow all for auth" ON custom_lists FOR ALL TO authenticated USING (true) WITH CHECK (true);

        CREATE POLICY "Allow all for anon" ON custom_list_items FOR ALL TO anon USING (true) WITH CHECK (true);
        CREATE POLICY "Allow all for auth" ON custom_list_items FOR ALL TO authenticated USING (true) WITH CHECK (true);

        CREATE POLICY "Allow all for anon" ON browse_config FOR ALL TO anon USING (true) WITH CHECK (true);
        CREATE POLICY "Allow all for auth" ON browse_config FOR ALL TO authenticated USING (true) WITH CHECK (true);

        CREATE POLICY "Allow all for anon" ON extension_lists FOR ALL TO anon USING (true) WITH CHECK (true);
        CREATE POLICY "Allow all for auth" ON extension_lists FOR ALL TO authenticated USING (true) WITH CHECK (true);

        CREATE POLICY "Allow all for anon" ON extension_list_items FOR ALL TO anon USING (true) WITH CHECK (true);
        CREATE POLICY "Allow all for auth" ON extension_list_items FOR ALL TO authenticated USING (true) WITH CHECK (true);

        CREATE POLICY "Allow all for anon" ON custom_home_rows FOR ALL TO anon USING (true) WITH CHECK (true);
        CREATE POLICY "Allow all for auth" ON custom_home_rows FOR ALL TO authenticated USING (true) WITH CHECK (true);

        CREATE POLICY "Allow all for anon" ON network_hubs_config FOR ALL TO anon USING (true) WITH CHECK (true);
        CREATE POLICY "Allow all for auth" ON network_hubs_config FOR ALL TO authenticated USING (true) WITH CHECK (true);

        CREATE POLICY "Allow all for anon" ON hidden_sections FOR ALL TO anon USING (true) WITH CHECK (true);
        CREATE POLICY "Allow all for auth" ON hidden_sections FOR ALL TO authenticated USING (true) WITH CHECK (true);

        CREATE POLICY "Allow all for anon" ON profiles FOR ALL TO anon USING (true) WITH CHECK (true);
        CREATE POLICY "Allow all for auth" ON profiles FOR ALL TO authenticated USING (true) WITH CHECK (true);
        """
    }
}

// MARK: - Setup Step View
struct SetupStepView: View {
    let number: Int
    let title: String
    let description: String
    let iconName: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: iconName)
                        .foregroundColor(.accentColor)
                    Text(title)
                        .font(.headline)
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - MDBList Extension View
struct MDBListExtensionView: View {
    @ObservedObject private var storage = StorageService.shared
    
    var body: some View {
        List {
            // Header Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "list.star")
                            .font(.title2)
                            .foregroundColor(.purple)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MDBList Extension")
                                .font(.headline)
                            Text("Curated movie & TV lists")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Link(destination: URL(string: "https://mdblist.com")!) {
                        HStack {
                            Text("Visit MDBList")
                                .font(.caption)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                        }
                        .foregroundColor(.purple)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("About")
            }
            
            // Available Lists
            Section {
                NavigationLink(destination: MDBListDetailView(
                    listId: "dualipafan01/trending-titles",
                    listName: "Trending",
                    listDescription: "Currently trending movies & TV shows"
                )) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trending")
                                .fontWeight(.medium)
                            Text("Currently trending titles")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                NavigationLink(destination: MDBListDetailView(
                    listId: "garycrawfordgc/comedy",
                    listName: "Comedy Collection",
                    listDescription: "Curated comedy movies & shows"
                )) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.yellow.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: "face.smiling.fill")
                                .foregroundColor(.yellow)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Comedy Collection")
                                .fontWeight(.medium)
                            Text("Curated comedy movies & shows")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Available Lists")
            }
        }
        .navigationTitle("MDBList")
    }
}

// MARK: - MDBList Detail View
struct MDBListDetailView: View {
    let listId: String
    let listName: String
    let listDescription: String
    
    @State private var items: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showOnHome = false
    @ObservedObject private var storage = StorageService.shared
    
    var body: some View {
        List {
            // Options
            Section {
                Toggle("Show on Home Screen", isOn: $showOnHome)
                    .onChange(of: showOnHome) { _, newValue in
                        toggleHomeDisplay(newValue)
                    }
            } header: {
                Text("Options")
            }
            
            // Content Preview
            Section {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if let error = error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Retry") {
                        Task { await loadList() }
                    }
                } else {
                    ForEach(items.prefix(10)) { item in
                        HStack(spacing: 12) {
                            PosterImageView(posterPath: item.posterPath, size: .small)
                                .frame(width: 50, height: 75)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(2)
                                
                                HStack {
                                    if let year = item.year {
                                        Text(year)
                                    }
                                    if let rating = item.voteAverage, rating > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: "star.fill")
                                                .font(.caption2)
                                                .foregroundColor(.yellow)
                                            Text(String(format: "%.1f", rating))
                                        }
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    if items.count > 10 {
                        Text("...and \(items.count - 10) more items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Preview (\(items.count) items)")
            }
        }
        .navigationTitle(listName)
        .task {
            await loadList()
            checkHomeStatus()
        }
    }
    
    private func loadList() async {
        isLoading = true
        error = nil
        
        do {
            items = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: listId)
        } catch {
            self.error = "Failed to load list. Please try again."
            print("MDBList error: \(error)")
        }
        
        isLoading = false
    }
    
    private func checkHomeStatus() {
        showOnHome = storage.importedLists.contains { $0.listId == listId && $0.showOnHome }
    }
    
    private func toggleHomeDisplay(_ show: Bool) {
        if show {
            if let existing = storage.importedLists.first(where: { $0.listId == listId }) {
                var updatedList = existing
                updatedList.showOnHome = true
                updatedList.items = items
                updatedList.lastSynced = Date()
                storage.updateImportedList(updatedList)
                
                if !storage.customHomeRows.contains(where: { $0.importedListId == existing.id }) {
                    let homeRow = CustomHomeRow.importedListRow(
                        name: listName,
                        listId: existing.id,
                        sortOrder: storage.customHomeRows.count
                    )
                    storage.addCustomHomeRow(homeRow)
                }
            } else {
                var newList = ImportedListItem(
                    name: listName,
                    listId: listId,
                    showOnHome: true,
                    source: .mdblist
                )
                newList.items = items
                newList.lastSynced = Date()
                storage.addImportedList(newList)
                
                let homeRow = CustomHomeRow.importedListRow(
                    name: listName,
                    listId: newList.id,
                    sortOrder: storage.customHomeRows.count
                )
                storage.addCustomHomeRow(homeRow)
            }
        } else {
            if var existing = storage.importedLists.first(where: { $0.listId == listId }) {
                existing.showOnHome = false
                storage.updateImportedList(existing)
                
                if let homeRow = storage.customHomeRows.first(where: { $0.importedListId == existing.id }) {
                    storage.deleteCustomHomeRow(id: homeRow.id)
                }
            }
        }
    }
}

// MARK: - Parent Passcode Setup Sheet
struct ParentPasscodeSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var step: PasscodeSetupStep = .create
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool
    
    let onComplete: (String) -> Void
    
    enum PasscodeSetupStep {
        case create
        case confirm
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.accentColor)
                }
                
                VStack(spacing: 8) {
                    Text(step == .create ? "Create Parent Passcode" : "Confirm Passcode")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text(step == .create
                         ? "Set a 4-digit passcode to protect parental settings"
                         : "Enter the same passcode again to confirm")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                // Passcode dots
                HStack(spacing: 16) {
                    let currentCode = step == .create ? passcode : confirmPasscode
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < currentCode.count ? Color.accentColor : Color(.systemGray4))
                            .frame(width: 16, height: 16)
                            .animation(.easeInOut(duration: 0.15), value: currentCode.count)
                    }
                }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .transition(.opacity)
                }
                
                // Hidden text field to capture keyboard input
                TextField("", text: step == .create ? $passcode : $confirmPasscode)
                    .keyboardType(.numberPad)
                    .focused($isFocused)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .onChange(of: passcode) { _, newValue in
                        // Limit to 4 digits
                        if newValue.count > 4 {
                            passcode = String(newValue.prefix(4))
                        }
                        // Filter non-digits
                        passcode = newValue.filter { $0.isNumber }
                        if passcode.count > 4 { passcode = String(passcode.prefix(4)) }
                        
                        if passcode.count == 4 && step == .create {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation { step = .confirm }
                            }
                        }
                    }
                    .onChange(of: confirmPasscode) { _, newValue in
                        confirmPasscode = newValue.filter { $0.isNumber }
                        if confirmPasscode.count > 4 { confirmPasscode = String(confirmPasscode.prefix(4)) }
                        
                        if confirmPasscode.count == 4 {
                            if confirmPasscode == passcode {
                                onComplete(passcode)
                                dismiss()
                            } else {
                                errorMessage = "Passcodes don't match. Try again."
                                confirmPasscode = ""
                            }
                        } else {
                            errorMessage = nil
                        }
                    }
                
                Spacer()
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

// MARK: - Parent Passcode Entry Sheet
struct ParentPasscodeEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let storedPasscode: String
    let onVerified: () -> Void
    
    @State private var enteredPasscode = ""
    @State private var errorMessage: String?
    @State private var attempts = 0
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                }
                
                VStack(spacing: 8) {
                    Text("Enter Parent Passcode")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("A parent passcode is required to change this setting")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                // Passcode dots
                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < enteredPasscode.count ? Color.orange : Color(.systemGray4))
                            .frame(width: 16, height: 16)
                            .animation(.easeInOut(duration: 0.15), value: enteredPasscode.count)
                    }
                }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .transition(.opacity)
                }
                
                // Hidden text field
                TextField("", text: $enteredPasscode)
                    .keyboardType(.numberPad)
                    .focused($isFocused)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .onChange(of: enteredPasscode) { _, newValue in
                        enteredPasscode = newValue.filter { $0.isNumber }
                        if enteredPasscode.count > 4 { enteredPasscode = String(enteredPasscode.prefix(4)) }
                        
                        if enteredPasscode.count == 4 {
                            if enteredPasscode == storedPasscode {
                                onVerified()
                                dismiss()
                            } else {
                                attempts += 1
                                errorMessage = "Incorrect passcode. Try again."
                                enteredPasscode = ""
                            }
                        } else {
                            errorMessage = nil
                        }
                    }
                
                Spacer()
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

// MARK: - Custom JSON Hubs Settings
struct CustomJSONHubsSettingsView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var showAddHub = false
    @State private var showExportSheet = false
    @State private var exportHub: CustomJSONHub?
    @State private var exportedJSON: String?
    
    var body: some View {
        List {
            // Info section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hub Customisation")
                                .font(.headline)
                            Text("Create your own hubs using MDBList or JSON URLs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("Add custom collections to your Browse page. Use an MDBList URL, search for lists, or provide a JSON file.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // Existing hubs
            if !storage.customJSONHubs.isEmpty {
                Section("Your Hubs") {
                    ForEach(storage.customJSONHubs.sorted { $0.sortOrder < $1.sortOrder }) { hub in
                        HStack(spacing: 12) {
                            // Hub image thumbnail
                            if let imageURL = hub.imageURL, !imageURL.isEmpty, let url = URL(string: imageURL) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 40, height: 40)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    default:
                                        hubPlaceholder(hub)
                                    }
                                }
                            } else {
                                hubPlaceholder(hub)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(hub.name)
                                    .fontWeight(.medium)
                                
                                HStack(spacing: 8) {
                                    Text("\(hub.items.count) items")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    let listCount = hub.resolvedMDBListIds.count
                                    if listCount > 1 {
                                        Text("\(listCount) lists")
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.orange))
                                    }
                                    
                                    Text(hub.source.displayName)
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(hub.source == .mdblist ? Color.purple : Color.blue))
                                    
                                    if let synced = hub.lastSynced {
                                        Text(synced.formatted(.relative(presentation: .named)))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { hub.isEnabled },
                                set: { newValue in
                                    var updatedHub = hub
                                    updatedHub.isEnabled = newValue
                                    storage.updateCustomJSONHub(updatedHub)
                                }
                            ))
                            .labelsHidden()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                storage.deleteCustomJSONHub(id: hub.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                Task {
                                    await refreshHub(hub)
                                }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                exportHub = hub
                                generateExportJSON(hub)
                                showExportSheet = true
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .tint(.green)
                        }
                    }
                    .onMove { from, to in
                        var hubs = storage.customJSONHubs.sorted { $0.sortOrder < $1.sortOrder }
                        hubs.move(fromOffsets: from, toOffset: to)
                        storage.reorderCustomJSONHubs(hubs)
                    }
                }
            }
            
            // Add button
            Section {
                Button {
                    showAddHub = true
                } label: {
                    Label("Add Custom Hub", systemImage: "plus.circle")
                }
            } footer: {
                Text("Swipe right on a hub to export it as shareable JSON")
            }
        }
        .navigationTitle("Hub Customisation")
        .toolbar {
            if !storage.customJSONHubs.isEmpty {
                EditButton()
            }
        }
        .sheet(isPresented: $showAddHub) {
            AddCustomHubSheet()
        }
        .sheet(isPresented: $showExportSheet) {
            if let hub = exportHub, let json = exportedJSON {
                ExportHubSheet(hub: hub, jsonString: json)
            }
        }
    }
    
    @ViewBuilder
    private func hubPlaceholder(_ hub: CustomJSONHub) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: hub.brandColor ?? "#FF6600").opacity(0.2))
                .frame(width: 40, height: 40)
            Image(systemName: hub.source == .mdblist ? "list.star" : "doc.text")
                .font(.caption)
                .foregroundColor(Color(hex: hub.brandColor ?? "#FF6600"))
        }
    }
    
    private func refreshHub(_ hub: CustomJSONHub) async {
        let listIds = hub.resolvedMDBListIds
        if hub.source == .mdblist, !listIds.isEmpty {
            do {
                let items = try await MDBListService.shared.fetchMultipleListsAsSavedMedia(inputs: listIds)
                await MainActor.run {
                    var updatedHub = hub
                    updatedHub.items = items
                    updatedHub.lastSynced = Date()
                    storage.updateCustomJSONHub(updatedHub)
                }
            } catch {
                print("Error refreshing MDBList hub \(hub.name): \(error)")
            }
        } else {
            do {
                let result = try await JSONHubService.shared.fetchAndResolve(from: hub.jsonURL)
                await MainActor.run {
                    var updatedHub = hub
                    updatedHub.items = result.items
                    updatedHub.lastSynced = Date()
                    storage.updateCustomJSONHub(updatedHub)
                }
            } catch {
                print("Error refreshing hub \(hub.name): \(error)")
            }
        }
    }
    
    private func generateExportJSON(_ hub: CustomJSONHub) {
        let exportItems: [[String: Any]] = hub.items.map { item in
            var dict: [String: Any] = [
                "tmdb_id": item.mediaId,
                "media_type": item.mediaType.rawValue,
                "title": item.title
            ]
            if let year = item.year { dict["year"] = year }
            return dict
        }
        
        let wrapper: [String: Any] = [
            "name": hub.name,
            "items": exportItems
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            exportedJSON = string
        }
    }
}

// MARK: - Export Hub Sheet
struct ExportHubSheet: View {
    let hub: CustomJSONHub
    let jsonString: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("Export \"\(hub.name)\"")
                        .font(.headline)
                    Text("\(hub.items.count) items as JSON")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                
                // JSON preview
                ScrollView {
                    Text(jsonString)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                .frame(maxHeight: 300)
                .padding(.horizontal)
                
                // Actions
                VStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = jsonString
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        HStack {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied!" : "Copy JSON")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button {
                        shareJSON()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func shareJSON() {
        guard let data = jsonString.data(using: .utf8) else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(hub.name.replacingOccurrences(of: " ", with: "_")).json")
        try? data.write(to: tempURL)
        
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            activityVC.popoverPresentationController?.sourceView = topVC.view
            topVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Add Custom Hub Sheet (Revamped)
struct AddCustomHubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var storage = StorageService.shared
    
    enum HubSourceTab: String, CaseIterable {
        case mdblist = "MDBList"
        case json = "JSON URL"
    }
    
    // MARK: - MDBList List Entry (for multi-list support)
    struct MDBListEntry: Identifiable {
        let id = UUID()
        let listPath: String
        let displayName: String
        var itemCount: Int
        var items: [SavedMediaItem]
    }
    
    // General
    @State private var selectedSource: HubSourceTab = .mdblist
    @State private var hubName = ""
    @State private var imageURL = ""
    @State private var rowName = ""
    @State private var brandColor = ""
    @State private var error: String?
    @State private var isImporting = false
    
    // MDBList — multiple lists support
    @State private var mdblistInput = ""
    @State private var isSearching = false
    @State private var searchResults: [MDBListSearchResult] = []
    @State private var addedLists: [MDBListEntry] = []
    @State private var isLoadingPreview = false
    @State private var hasSearched = false
    
    // JSON
    @State private var jsonURL = ""
    @State private var jsonPreviewCount = 0
    @State private var jsonPreviewSamples: [ExternalJSONEntry] = []
    @State private var jsonPreviewName: String?
    @State private var isLoadingJSON = false
    
    private var hasValidContent: Bool {
        if selectedSource == .mdblist {
            return !addedLists.isEmpty
        } else {
            return jsonPreviewCount > 0
        }
    }
    
    private var allMDBListPreviewItems: [SavedMediaItem] {
        addedLists.flatMap { $0.items }
    }
    
    private var totalItemCount: Int {
        addedLists.reduce(0) { $0 + $1.itemCount }
    }
    
    private var effectiveName: String {
        if !hubName.isEmpty { return hubName }
        if selectedSource == .mdblist, addedLists.count == 1 {
            return addedLists.first?.displayName ?? ""
        }
        if selectedSource == .json, let name = jsonPreviewName {
            return name
        }
        return ""
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Step 1: Hub Name
                Section {
                    TextField("Hub Name", text: $hubName)
                } header: {
                    HStack(spacing: 6) {
                        StepBadge(number: 1)
                        Text("Name Your Hub")
                    }
                }
                
                // Step 2: Source Selection
                Section {
                    Picker("Source", selection: $selectedSource) {
                        ForEach(HubSourceTab.allCases, id: \.rawValue) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedSource) { _, _ in
                        error = nil
                    }
                    
                    if selectedSource == .mdblist {
                        mdblistSection
                    } else {
                        jsonSection
                    }
                } header: {
                    HStack(spacing: 6) {
                        StepBadge(number: 2)
                        Text("Add Content")
                    }
                }
                
                // Error
                if let error = error {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Added lists summary (MDBList multi-list)
                if selectedSource == .mdblist && !addedLists.isEmpty {
                    Section {
                        ForEach(addedLists) { entry in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("\(entry.itemCount) items")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button {
                                    addedLists.removeAll { $0.id == entry.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Added Lists (\(addedLists.count))")
                            Spacer()
                            Text("\(totalItemCount) total items")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Preview
                    Section("Preview") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(allMDBListPreviewItems.prefix(10)) { item in
                                    VStack(spacing: 4) {
                                        PosterImageView(posterPath: item.posterPath, size: .small)
                                            .frame(width: 50, height: 75)
                                        Text(item.title)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .frame(width: 50)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                
                // Preview (JSON)
                if selectedSource == .json && jsonPreviewCount > 0 {
                    Section("Preview (\(jsonPreviewCount) entries)") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("\(jsonPreviewCount) entries found")
                                .fontWeight(.medium)
                        }
                        
                        ForEach(jsonPreviewSamples.indices, id: \.self) { index in
                            let sample = jsonPreviewSamples[index]
                            HStack(spacing: 8) {
                                Image(systemName: sample.mediaType == "tv" || sample.mediaType == "show" ? "tv" : "film")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text(sample.title ?? "ID: \(sample.tmdbId ?? 0)")
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                        }
                        
                        if jsonPreviewCount > 5 {
                            Text("...and \(jsonPreviewCount - 5) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Step 3: Customisation
                if hasValidContent {
                    Section {
                        TextField("https://example.com/image.png", text: $imageURL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        
                        // Image preview
                        if !imageURL.isEmpty, let url = URL(string: imageURL) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 50)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                case .failure:
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundColor(.orange)
                                        Text("Invalid image URL")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                default:
                                    ProgressView()
                                        .frame(height: 50)
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            StepBadge(number: 3)
                            Text("Hub Image (optional)")
                        }
                    } footer: {
                        Text("Paste a hosted image link for your hub's icon")
                    }
                    
                    Section {
                        TextField("Row Name (shown on Browse)", text: $rowName)
                        
                        TextField("Brand Color (optional, e.g. #FF6600)", text: $brandColor)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    } header: {
                        HStack(spacing: 6) {
                            StepBadge(number: 4)
                            Text("Row Name & Style")
                        }
                    } footer: {
                        Text("The row name appears on the Browse page button. Leave blank to use the hub name.")
                    }
                }
            }
            .navigationTitle("Add Custom Hub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task { await importHub() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasValidContent || effectiveName.isEmpty || isImporting)
                }
            }
            .overlay {
                if isImporting {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Importing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
    
    // MARK: - MDBList Section
    @ViewBuilder
    private var mdblistSection: some View {
        // URL or search input
        TextField("Paste MDBList URL or search...", text: $mdblistInput)
            .textContentType(.URL)
            .autocapitalization(.none)
            .autocorrectionDisabled()
            .onChange(of: mdblistInput) { _, _ in
                error = nil
                hasSearched = false
                searchResults = []
            }
        
        HStack(spacing: 12) {
            // Load button (for direct URL/ID)
            Button {
                Task { await loadMDBList() }
            } label: {
                HStack {
                    Image(systemName: "link")
                    Text("Add")
                }
            }
            .disabled(mdblistInput.isEmpty || isLoadingPreview)
            
            // Search button
            Button {
                Task { await searchMDBLists() }
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
            .disabled(mdblistInput.isEmpty || isSearching)
        }
        
        // Loading preview indicator
        if isLoadingPreview {
            HStack {
                ProgressView()
                Text("Loading list...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        
        // Search Results
        if !searchResults.isEmpty {
            ForEach(searchResults) { result in
                let isAlreadyAdded = addedLists.contains { $0.listPath == result.listPath }
                Button {
                    if !isAlreadyAdded {
                        selectSearchResult(result)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isAlreadyAdded ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundColor(isAlreadyAdded ? .green : .accentColor)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 8) {
                                if result.itemCount > 0 {
                                    Label("\(result.itemCount)", systemImage: "film.stack")
                                }
                                if result.likeCount > 0 {
                                    Label("\(result.likeCount)", systemImage: "heart")
                                }
                                if let username = result.username {
                                    Text("by \(username)")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if isAlreadyAdded {
                            Text("Added")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }
                .disabled(isAlreadyAdded)
            }
        } else if hasSearched && searchResults.isEmpty && !isSearching {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                Text("No lists found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - JSON Section
    @ViewBuilder
    private var jsonSection: some View {
        TextField("https://example.com/list.json", text: $jsonURL)
            .textContentType(.URL)
            .autocapitalization(.none)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .onChange(of: jsonURL) { _, _ in
                jsonPreviewCount = 0
                jsonPreviewSamples = []
                jsonPreviewName = nil
                error = nil
            }
        
        Button {
            Task { await previewJSON() }
        } label: {
            HStack {
                Text("Preview")
                if isLoadingJSON {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(jsonURL.isEmpty || isLoadingJSON)
    }
    
    // MARK: - Actions
    
    private func searchMDBLists() async {
        isSearching = true
        error = nil
        hasSearched = true
        
        do {
            searchResults = try await MDBListService.shared.searchLists(query: mdblistInput)
        } catch {
            self.error = "Search failed: \(error.localizedDescription)"
        }
        
        isSearching = false
    }
    
    private func loadMDBList() async {
        isLoadingPreview = true
        error = nil
        
        let listId = MDBListService.shared.parseListId(from: mdblistInput)
        
        // Check if already added
        if addedLists.contains(where: { $0.listPath == listId }) {
            error = "This list has already been added."
            isLoadingPreview = false
            return
        }
        
        // Extract name from URL
        var derivedName = ""
        if listId.contains("/") {
            let components = listId.split(separator: "/")
            if components.count >= 2 {
                derivedName = String(components.last ?? "MDBList")
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized
            }
        }
        
        do {
            let items = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: listId)
            
            await MainActor.run {
                if items.isEmpty {
                    error = "List is empty or could not be found."
                } else {
                    let entry = MDBListEntry(
                        listPath: listId,
                        displayName: derivedName.isEmpty ? listId : derivedName,
                        itemCount: items.count,
                        items: items
                    )
                    addedLists.append(entry)
                    
                    // Auto-fill hub name with first list name if empty
                    if hubName.isEmpty {
                        hubName = derivedName.isEmpty ? listId : derivedName
                    }
                    
                    // Clear input for next list
                    mdblistInput = ""
                    searchResults = []
                }
            }
        } catch {
            self.error = "Failed to load list. Check the URL or ID."
        }
        
        isLoadingPreview = false
    }
    
    private func selectSearchResult(_ result: MDBListSearchResult) {
        // Check if already added
        guard !addedLists.contains(where: { $0.listPath == result.listPath }) else { return }
        
        // Auto-fill hub name with first list name if empty
        if hubName.isEmpty && addedLists.isEmpty {
            hubName = result.displayName
        }
        
        // Load list items
        Task {
            await MainActor.run {
                isLoadingPreview = true
                error = nil
            }
            
            do {
                let items = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: result.listPath)
                await MainActor.run {
                    if items.isEmpty {
                        error = "This list appears to be empty."
                    } else {
                        let entry = MDBListEntry(
                            listPath: result.listPath,
                            displayName: result.displayName,
                            itemCount: items.count,
                            items: items
                        )
                        addedLists.append(entry)
                    }
                }
            } catch {
                print("MDBList selectSearchResult error for '\(result.listPath)': \(error)")
                await MainActor.run {
                    self.error = "Failed to load list items: \(error.localizedDescription)"
                }
            }
            
            await MainActor.run { isLoadingPreview = false }
        }
    }
    
    private func previewJSON() async {
        isLoadingJSON = true
        error = nil
        
        do {
            let result = try await JSONHubService.shared.preview(from: jsonURL)
            await MainActor.run {
                jsonPreviewName = result.name
                jsonPreviewCount = result.count
                jsonPreviewSamples = result.sampleEntries
                
                if hubName.isEmpty {
                    if let name = result.name {
                        hubName = name
                    } else if let urlObj = URL(string: jsonURL) {
                        let filename = urlObj.deletingPathExtension().lastPathComponent
                        hubName = filename
                            .replacingOccurrences(of: "-", with: " ")
                            .replacingOccurrences(of: "_", with: " ")
                            .capitalized
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
        
        await MainActor.run { isLoadingJSON = false }
    }
    
    private func importHub() async {
        isImporting = true
        let finalName = effectiveName
        
        if selectedSource == .mdblist {
            guard !addedLists.isEmpty else { return }
            
            // Merge all items, de-duplicate by mediaType-mediaId
            var mergedItems: [SavedMediaItem] = []
            var seenKeys = Set<String>()
            for entry in addedLists {
                for item in entry.items {
                    let key = "\(item.mediaType.rawValue)-\(item.mediaId)"
                    if !seenKeys.contains(key) {
                        seenKeys.insert(key)
                        mergedItems.append(item)
                    }
                }
            }
            
            let allListPaths = addedLists.map { $0.listPath }
            let primaryPath = allListPaths.first ?? ""
            
            await MainActor.run {
                var hub = CustomJSONHub(
                    name: finalName,
                    jsonURL: "mdblist://\(primaryPath)",
                    brandColor: brandColor.isEmpty ? nil : brandColor,
                    source: .mdblist
                )
                hub.items = mergedItems
                hub.lastSynced = Date()
                hub.mdblistId = primaryPath
                hub.mdblistIds = allListPaths
                hub.imageURL = imageURL.isEmpty ? nil : imageURL
                hub.rowName = rowName.isEmpty ? nil : rowName
                
                storage.addCustomJSONHub(hub)
                dismiss()
            }
        } else {
            // JSON source
            do {
                let result = try await JSONHubService.shared.fetchAndResolve(from: jsonURL)
                
                await MainActor.run {
                    var hub = CustomJSONHub(
                        name: finalName,
                        jsonURL: jsonURL,
                        brandColor: brandColor.isEmpty ? nil : brandColor,
                        source: .json
                    )
                    hub.items = result.items
                    hub.lastSynced = Date()
                    hub.imageURL = imageURL.isEmpty ? nil : imageURL
                    hub.rowName = rowName.isEmpty ? nil : rowName
                    
                    storage.addCustomJSONHub(hub)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = "Import failed: \(error.localizedDescription)"
                    isImporting = false
                }
                return
            }
        }
    }
}

// MARK: - Step Badge
private struct StepBadge: View {
    let number: Int
    
    var body: some View {
        Text("\(number)")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.accentColor))
    }
}

#Preview {
    SettingsView()
}
