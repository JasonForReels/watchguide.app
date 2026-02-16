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
    
    @State private var selectedSection: HomeSection = .browseRows
    
    @State private var showAddJSONHub = false
    
    enum HomeSection: String, CaseIterable {
        case browseRows = "Browse Rows"
        case networks = "Networks"
        case customHubs = "Custom Hubs"
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
                    case .browseRows:
                        browseRowsSection
                    case .networks:
                        networksSection
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
    
    // MARK: - Networks Section
    private var networksSection: some View {
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
            Text("Streaming Networks")
        } footer: {
            Text("Drag to reorder, toggle to show/hide. Only networks available in your region are shown.")
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
                        Text("Add hubs from external JSON URLs in Settings")
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
                                Text("\(hub.items.count) items")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
                    Text("Toggle to show/hide on Browse. Manage hubs in Settings > Custom Hubs.")
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
            AddCustomJSONHubSheet()
        }
    }
    
    // MARK: - Data Management
    
    private func loadData() {
        browseRows = storage.browseRows.sorted { $0.sortOrder < $1.sortOrder }
        networkHubs = storage.networkHubs.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private func saveChanges() {
        // Update sort orders
        updateBrowseSortOrder()
        updateNetworkHubsSortOrder()
        
        // Save to storage
        storage.updateBrowseRows(browseRows)
        storage.reorderNetworkHubs(networkHubs)
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
