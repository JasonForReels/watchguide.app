//
//  SettingsView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var settings: UserSettings
    @State private var showClearDataAlert = false
    
    init() {
        _settings = State(initialValue: StorageService.shared.settings)
    }
    
    var body: some View {
        NavigationStack {
            Form {
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

#Preview {
    SettingsView()
}
