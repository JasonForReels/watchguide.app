//
//  SettingsView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import AuthenticationServices

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
                    }
                    
                    NavigationLink(destination: CustomHomeRowsSettingsView()) {
                        HStack {
                            Image(systemName: "square.grid.2x2")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            Text("Custom Rows & Hubs")
                            Spacer()
                            Text("\(storage.customHomeRows.filter { $0.isEnabled }.count)")
                                .foregroundColor(.secondary)
                        }
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
                    }
                }
                
                // Integrations
                Section {
                    NavigationLink(destination: ImportedListsSettingsView()) {
                        HStack {
                            Image(systemName: "list.bullet.clipboard")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PublicMetaDB")
                                Text("Import curated movie & TV lists")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(storage.importedLists.filter { $0.source == .publicMetaDB }.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Integrations")
                }
                
                // Extensions
                Section {
                    NavigationLink(destination: MDBListExtensionView()) {
                        HStack {
                            Image(systemName: "list.star")
                                .foregroundColor(.purple)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("MDBList")
                                Text("Curated comedy list")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Extensions")
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
                
                // Community
                Section {
                    Link(destination: URL(string: "https://discord.watchguide.app")!) {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundColor(.indigo)
                                .frame(width: 24)
                            Text("Join our Discord")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Community")
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
    @State private var rowType: CustomHomeRow.CustomRowType = .customHub
    @State private var name = ""
    @State private var imageURL = ""
    @State private var selectedImportedList: ImportedListItem?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Row Type", selection: $rowType) {
                        Text("Custom Hub").tag(CustomHomeRow.CustomRowType.customHub)
                        Text("Imported List").tag(CustomHomeRow.CustomRowType.importedList)
                    }
                    .pickerStyle(.segmented)
                }
                
                if rowType == .customHub {
                    Section("Custom Hub") {
                        TextField("Row Name", text: $name)
                        
                        TextField("Header Image URL (optional)", text: $imageURL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    
                    if !imageURL.isEmpty, let url = URL(string: imageURL) {
                        Section("Preview") {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 100)
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
                } else {
                    Section("Select Imported List") {
                        if storage.importedLists.isEmpty {
                            Text("No lists imported yet")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(storage.importedLists) { list in
                                Button {
                                    selectedImportedList = list
                                    name = list.displayName
                                } label: {
                                    HStack {
                                        Text(list.displayName)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if selectedImportedList?.id == list.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if selectedImportedList != nil {
                        Section {
                            TextField("Custom Name (optional)", text: $name)
                        }
                    }
                }
            }
            .navigationTitle("Add Row")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addRow()
                    }
                    .disabled(name.isEmpty && selectedImportedList == nil)
                }
            }
        }
    }
    
    private func addRow() {
        var row: CustomHomeRow
        
        if rowType == .importedList, let list = selectedImportedList {
            row = CustomHomeRow.importedListRow(
                name: name.isEmpty ? list.displayName : name,
                listId: list.id,
                sortOrder: storage.customHomeRows.count
            )
        } else {
            row = CustomHomeRow.hubRow(
                name: name,
                imageURL: imageURL.isEmpty ? nil : imageURL,
                sortOrder: storage.customHomeRows.count
            )
        }
        
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

// MARK: - MDBList Extension View
struct MDBListExtensionView: View {
    @State private var items: [SavedMediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showOnHome = false
    @ObservedObject private var storage = StorageService.shared
    
    // Hardcoded MDBList comedy list
    private let listId = "garycrawfordgc/comedy"
    private let listName = "Comedy Collection"
    
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
                            Text("Curated comedy movies & shows")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Link(destination: URL(string: "https://mdblist.com/lists/garycrawfordgc/comedy")!) {
                        HStack {
                            Text("View on MDBList")
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
        .navigationTitle("MDBList")
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
        // Check if this list is already added to home
        showOnHome = storage.importedLists.contains { $0.listId == listId && $0.showOnHome }
    }
    
    private func toggleHomeDisplay(_ show: Bool) {
        if show {
            // Add to imported lists if not already there
            if let existing = storage.importedLists.first(where: { $0.listId == listId }) {
                // Update existing list
                var updatedList = existing
                updatedList.showOnHome = true
                updatedList.items = items
                updatedList.lastSynced = Date()
                storage.updateImportedList(updatedList)
                
                // Add home row if not already present
                if !storage.customHomeRows.contains(where: { $0.importedListId == existing.id }) {
                    let homeRow = CustomHomeRow.importedListRow(
                        name: listName,
                        listId: existing.id,
                        sortOrder: storage.customHomeRows.count
                    )
                    storage.addCustomHomeRow(homeRow)
                }
            } else {
                // Create new list
                var newList = ImportedListItem(
                    name: listName,
                    listId: listId,
                    showOnHome: true,
                    source: .mdblist
                )
                newList.items = items
                newList.lastSynced = Date()
                storage.addImportedList(newList)
                
                // Add home row using the new list's UUID
                let homeRow = CustomHomeRow.importedListRow(
                    name: listName,
                    listId: newList.id,
                    sortOrder: storage.customHomeRows.count
                )
                storage.addCustomHomeRow(homeRow)
            }
        } else {
            // Remove from home but keep in imported lists
            if var existing = storage.importedLists.first(where: { $0.listId == listId }) {
                existing.showOnHome = false
                storage.updateImportedList(existing)
                
                // Remove home row
                if let homeRow = storage.customHomeRows.first(where: { $0.importedListId == existing.id }) {
                    storage.deleteCustomHomeRow(id: homeRow.id)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
