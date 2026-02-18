//
//  HomeCustomizationView.swift
//  WatchGuide-MovieandTVtracker
//
//  Home screen customization view
//

import SwiftUI

struct HomeCustomizationView: View {
    @ObservedObject private var storage = StorageService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var browseSections: [BrowseSectionItem] = []
    @State private var browseRows: [BrowseRowConfig] = []
    @State private var networkHubs: [NetworkHub] = []
    @State private var customHubs: [CustomJSONHub] = []
    
    @State private var selectedSection: HomeSection = .sections
    
    @State private var showAddJSONHub = false
    
    enum HomeSection: String, CaseIterable {
        case sections = "Sections"
        case networks = "Networks"
        case rows = "Rows"
        case hubs = "Hubs"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Section picker
                Picker("Section", selection: $selectedSection) {
                    ForEach(HomeSection.allCases, id: \.rawValue) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)
                
                // Content
                List {
                    switch selectedSection {
                    case .sections:
                        browseSectionsEditor
                    case .networks:
                        networksEditor
                    case .rows:
                        browseRowsEditor
                    case .hubs:
                        customHubsEditor
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, .constant(.active))
            }
            .navigationTitle("Customize Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadData()
            }
        }
    }
    
    // MARK: - Sections (Top-Level Order)
    private var browseSectionsEditor: some View {
        Section {
            ForEach($browseSections) { $section in
                HStack(spacing: 12) {
                    Image(systemName: section.iconName)
                        .font(.body)
                        .foregroundColor(.accentColor)
                        .frame(width: 28)
                    
                    Text(section.displayName)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Toggle("", isOn: $section.isEnabled)
                        .labelsHidden()
                }
            }
            .onMove { from, to in
                browseSections.move(fromOffsets: from, toOffset: to)
                updateSectionSortOrder()
            }
        } header: {
            Text("Section Order")
        } footer: {
            Text("Drag to reorder how sections appear on the Browse page. Toggle to show or hide.")
        }
    }
    
    // MARK: - Networks
    private var networksEditor: some View {
        Section {
            let filtered = $networkHubs.filter { hub in
                storage.settings.region.isEmpty || hub.wrappedValue.regions.contains(storage.settings.region) || hub.wrappedValue.regions.isEmpty
            }
            ForEach(filtered) { $hub in
                HStack {
                    Text(hub.name)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Toggle("", isOn: $hub.isEnabled)
                        .labelsHidden()
                }
            }
            .onMove { from, to in
                networkHubs.move(fromOffsets: from, toOffset: to)
                updateNetworkHubsSortOrder()
            }
        } header: {
            Text("Networks")
        } footer: {
            Text("Drag to reorder, toggle to show/hide individual streaming services.")
        }
    }
    
    // MARK: - Browse Rows
    private var browseRowsEditor: some View {
        Section {
            ForEach($browseRows) { $row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .fontWeight(.medium)
                        Text(row.endpoint.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $row.isEnabled)
                        .labelsHidden()
                }
            }
            .onMove { from, to in
                browseRows.move(fromOffsets: from, toOffset: to)
                updateBrowseSortOrder()
            }
        } header: {
            Text("Content Rows")
        } footer: {
            Text("Drag to reorder, toggle to show/hide content rows.")
        }
    }
    
    // MARK: - Custom Hubs
    private var customHubsEditor: some View {
        Group {
            if customHubs.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.badge.plus")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No Custom Hubs")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Add hubs from MDBList or JSON URLs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            } else {
                Section {
                    ForEach($customHubs) { $hub in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hub.name)
                                    .fontWeight(.medium)
                                HStack(spacing: 6) {
                                    Text("\(hub.items.count) items")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    let listCount = hub.resolvedMDBListIds.count
                                    if listCount > 1 {
                                        Text("\(listCount) lists")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $hub.isEnabled)
                                .labelsHidden()
                        }
                    }
                    .onMove { from, to in
                        customHubs.move(fromOffsets: from, toOffset: to)
                        updateCustomHubsSortOrder()
                    }
                    .onDelete { indexSet in
                        customHubs.remove(atOffsets: indexSet)
                    }
                } header: {
                    Text("Custom Hubs")
                } footer: {
                    Text("Drag to reorder, toggle to show/hide, swipe to delete.")
                }
            }
            
            Section {
                Button {
                    showAddJSONHub = true
                } label: {
                    Label("Add Custom Hub", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $showAddJSONHub) {
            AddCustomHubSheet()
        }
    }
    
    // MARK: - Data Management
    
    private func loadData() {
        browseSections = storage.browseSections.sorted { $0.sortOrder < $1.sortOrder }
        browseRows = storage.browseRows.sorted { $0.sortOrder < $1.sortOrder }
        networkHubs = storage.networkHubs.sorted { $0.sortOrder < $1.sortOrder }
        customHubs = storage.customJSONHubs.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private func saveChanges() {
        // Finalize sort orders
        updateSectionSortOrder()
        updateBrowseSortOrder()
        updateNetworkHubsSortOrder()
        updateCustomHubsSortOrder()
        
        // Persist
        storage.updateBrowseSections(browseSections)
        storage.updateBrowseRows(browseRows)
        storage.reorderNetworkHubs(networkHubs)
        
        // For custom hubs: reconcile with storage (handle deletions + reorder)
        let currentIds = Set(customHubs.map { $0.id })
        for existing in storage.customJSONHubs where !currentIds.contains(existing.id) {
            storage.deleteCustomJSONHub(id: existing.id)
        }
        storage.reorderCustomJSONHubs(customHubs)
    }
    
    private func updateSectionSortOrder() {
        for i in browseSections.indices {
            browseSections[i].sortOrder = i
        }
    }
    
    private func updateBrowseSortOrder() {
        for i in browseRows.indices {
            browseRows[i].sortOrder = i
        }
    }
    
    private func updateNetworkHubsSortOrder() {
        for i in networkHubs.indices {
            networkHubs[i].sortOrder = i
        }
    }
    
    private func updateCustomHubsSortOrder() {
        for i in customHubs.indices {
            customHubs[i].sortOrder = i
        }
    }
}

#Preview {
    HomeCustomizationView()
}
