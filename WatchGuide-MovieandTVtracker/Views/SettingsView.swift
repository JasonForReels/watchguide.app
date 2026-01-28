//
//  SettingsView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var storage = StorageService.shared
    @ObservedObject private var authService = AuthService.shared
    @State private var settings: UserSettings
    @State private var showClearDataAlert = false
    @State private var showSyncOptions = false
    @State private var syncMessage: String?
    @State private var showAuthSheet = false
    
    init() {
        _settings = State(initialValue: StorageService.shared.settings)
    }
    
    var body: some View {
        NavigationStack {
            Form {
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
                
                // Display Options
                Section("Display") {
                    Toggle("Compact Mode", isOn: $settings.compactMode)
                    Toggle("Auto-play Trailers", isOn: $settings.autoPlayTrailers)
                    Toggle("Include Adult Content", isOn: $settings.includeAdult)
                    
                    Picker("Hero Carousel", selection: $settings.heroCarouselSource) {
                        ForEach(HeroCarouselSource.allCases, id: \.rawValue) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                }
                
                // Browse Rows
                Section("Browse Rows") {
                    NavigationLink(destination: BrowseRowsSettingsView()) {
                        HStack {
                            Text("Customize Home Rows")
                            Spacer()
                            Text("\(storage.browseRows.filter { $0.isEnabled }.count) enabled")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Company Hubs
                Section("Company Hubs") {
                    NavigationLink(destination: CompanyHubsSettingsView()) {
                        HStack {
                            Text("Manage Hubs")
                            Spacer()
                            Text("\(storage.companyHubs.filter { $0.isEnabled }.count) enabled")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Cloud Sync
                Section {
                    Toggle("Enable Cloud Sync", isOn: Binding(
                        get: { storage.cloudSyncEnabled },
                        set: { storage.setCloudSyncEnabled($0) }
                    ))
                    .disabled(!storage.isCloudConfigured)
                    
                    if storage.isCloudConfigured {
                        HStack {
                            Text("Status")
                            Spacer()
                            if storage.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if let error = storage.lastSyncError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                if authService.isAuthenticated {
                                    Text("Signed in")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Device sync")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        if let lastSync = storage.lastSyncTime {
                            HStack {
                                Text("Last Synced")
                                Spacer()
                                Text(lastSync.formatted(.relative(presentation: .named)))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Button {
                            showSyncOptions = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Options")
                            }
                        }
                        .disabled(storage.isSyncing)
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("Link a Supabase project to enable sync")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        NavigationLink(destination: SupabaseSetupGuideView()) {
                            HStack {
                                Image(systemName: "book.pages")
                                Text("Setup Guide")
                            }
                        }
                    }
                } header: {
                    Text("Cloud Sync")
                } footer: {
                    if authService.isAuthenticated {
                        Text("Your lists sync across all devices signed into this account")
                    } else {
                        Text("Sign in above to sync across devices, or use device-only sync")
                    }
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
                        Text("1.0.0")
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
            .confirmationDialog("Sync Options", isPresented: $showSyncOptions, titleVisibility: .visible) {
                Button("Upload to Cloud") {
                    Task {
                        await storage.uploadToCloud()
                        syncMessage = storage.lastSyncError == nil ? "Upload complete!" : nil
                    }
                }
                Button("Download from Cloud") {
                    Task {
                        await storage.downloadFromCloud()
                        syncMessage = storage.lastSyncError == nil ? "Download complete!" : nil
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Choose how to sync your data")
            }
            .alert("Sync Complete", isPresented: .init(
                get: { syncMessage != nil },
                set: { if !$0 { syncMessage = nil } }
            )) {
                Button("OK") { syncMessage = nil }
            } message: {
                Text(syncMessage ?? "")
            }
            .sheet(isPresented: $showAuthSheet) {
                AuthView()
            }
        }
    }
    
    private var regionOptions: [(code: String, name: String)] {
        [
            ("US", "United States"),
            ("GB", "United Kingdom"),
            ("CA", "Canada"),
            ("AU", "Australia"),
            ("DE", "Germany"),
            ("FR", "France"),
            ("JP", "Japan"),
            ("KR", "South Korea"),
            ("IN", "India"),
            ("BR", "Brazil"),
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

// MARK: - Company Hubs Settings
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

        ALTER TABLE media_items ENABLE ROW LEVEL SECURITY;

        CREATE POLICY "Allow all for anon" ON media_items
            FOR ALL TO anon
            USING (true) WITH CHECK (true);
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

#Preview {
    SettingsView()
}
