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
    
    @State private var browseRows: [BrowseRowConfig] = []
    @State private var networkHubs: [NetworkHub] = []
    @State private var hiddenSections: HiddenDefaultSections = .default
    
    @State private var selectedSection: HomeSection = .sections
    
    @State private var showAddJSONHub = false
    
    enum HomeSection: String, CaseIterable {
        case sections = "Sections"
        case browseRows = "Rows"
        case customHubs = "Hubs"
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
                .padding()
                
                // Content
                List {
                    switch selectedSection {
                    case .sections:
                        defaultSectionsSection
                    case .browseRows:
                        browseRowsSection
                    case .customHubs:
                        customHubsSection
                    }
                }
                .listStyle(.insetGrouped)
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
    
    // MARK: - Default Sections Visibility
    private var defaultSectionsSection: some View {
        Group {
            Section {
                Toggle("Networks (Streaming)", isOn: Binding(
                    get: { !hiddenSections.hideNetworksRow },
                    set: { hiddenSections.hideNetworksRow = !$0 }
                ))
                
                Toggle("Studios", isOn: Binding(
                    get: { !hiddenSections.hideStudiosRow },
                    set: { hiddenSections.hideStudiosRow = !$0 }
                ))
                
                Toggle("For You (AI Picks)", isOn: Binding(
                    get: { !hiddenSections.hideForYouRow },
                    set: { hiddenSections.hideForYouRow = !$0 }
                ))
                
                Toggle("Discover Section", isOn: Binding(
                    get: { !hiddenSections.hideDiscoverSection },
                    set: { hiddenSections.hideDiscoverSection = !$0 }
                ))
            } header: {
                Text("Default Sections")
            } footer: {
                Text("Toggle off any built-in section you don't want on the Browse page. Your custom hubs will still appear.")
            }
            
            // Networks sub-section (quick toggles)
            if !hiddenSections.hideNetworksRow {
                Section {
                    ForEach($networkHubs.filter { storage.settings.region.isEmpty || $0.wrappedValue.regions.contains(storage.settings.region) || $0.wrappedValue.regions.isEmpty }) { $hub in
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
                    Text("Drag to reorder, toggle to show/hide individual networks.")
                }
            }
        }
    }
    
    // MARK: - Browse Rows Section
    private var browseRowsSection: some View {
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
            Text("Drag to reorder, toggle to show/hide")
        }
    }
    
    // MARK: - Custom Hubs Section
    private var customHubsSection: some View {
        Group {
            if storage.customJSONHubs.isEmpty {
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
                    ForEach(storage.customJSONHubs.sorted { $0.sortOrder < $1.sortOrder }) { hub in
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
                    }
                    .onDelete { indexSet in
                        let sortedHubs = storage.customJSONHubs.sorted { $0.sortOrder < $1.sortOrder }
                        for index in indexSet {
                            storage.deleteCustomJSONHub(id: sortedHubs[index].id)
                        }
                    }
                } header: {
                    Text("Custom Hubs")
                } footer: {
                    Text("Toggle to show/hide on Browse. Swipe to delete.")
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
        browseRows = storage.browseRows.sorted { $0.sortOrder < $1.sortOrder }
        networkHubs = storage.networkHubs.sorted { $0.sortOrder < $1.sortOrder }
        hiddenSections = storage.hiddenSections
    }
    
    private func saveChanges() {
        // Update sort orders
        updateBrowseSortOrder()
        updateNetworkHubsSortOrder()
        
        // Save to storage
        storage.updateBrowseRows(browseRows)
        storage.reorderNetworkHubs(networkHubs)
        storage.updateHiddenSections(hiddenSections)
    }
    
    private func updateBrowseSortOrder() {
        for (index, _) in browseRows.enumerated() {
            browseRows[index].sortOrder = index
        }
    }
    
    private func updateNetworkHubsSortOrder() {
        for (index, _) in networkHubs.enumerated() {
            networkHubs[index].sortOrder = index
        }
    }
}

#Preview {
    HomeCustomizationView()
}
