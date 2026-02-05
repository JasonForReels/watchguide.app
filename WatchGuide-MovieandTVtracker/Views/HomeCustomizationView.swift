//
//  HomeCustomizationView.swift
//  WatchGuide-MovieandTVtracker
//
//  Full home screen customization view with MDBList import
//

import SwiftUI

struct HomeCustomizationView: View {
    @ObservedObject private var storage = StorageService.shared
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var browseRows: [BrowseRowConfig] = []
    @State private var customHomeRows: [CustomHomeRow] = []
    @State private var importedLists: [ImportedListItem] = []
    @State private var networkHubs: [NetworkHub] = []
    
    @State private var showAddRowSheet = false
    @State private var showImportMDBList = false
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var showSyncError = false
    @State private var syncErrorMessage = ""
    
    @State private var selectedSection: HomeSection = .browseRows
    
    enum HomeSection: String, CaseIterable {
        case browseRows = "Browse Rows"
        case customRows = "Custom Rows"
        case importedLists = "Imported Lists"
        case networks = "Networks"
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
                    case .customRows:
                        customRowsSection
                    case .importedLists:
                        importedListsSection
                    case .networks:
                        networksSection
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
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if authService.isAuthenticated {
                            Button {
                                Task { await syncToCloud() }
                            } label: {
                                Label("Upload to Cloud", systemImage: "icloud.and.arrow.up")
                            }
                            
                            Button {
                                Task { await syncFromCloud() }
                            } label: {
                                Label("Download from Cloud", systemImage: "icloud.and.arrow.down")
                            }
                        } else {
                            Text("Sign in to sync")
                        }
                    } label: {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "icloud")
                        }
                    }
                    .disabled(isSyncing || !authService.isAuthenticated)
                }
            }
            .onAppear {
                loadData()
            }
            .sheet(isPresented: $showAddRowSheet) {
                AddHomeRowSheet(
                    importedLists: importedLists,
                    onAdd: { row in
                        customHomeRows.append(row)
                    }
                )
            }
            .sheet(isPresented: $showImportMDBList) {
                ImportMDBListFullSheet { importedList in
                    importedLists.append(importedList)
                }
            }
            .alert("Sync Complete", isPresented: .init(
                get: { syncMessage != nil },
                set: { if !$0 { syncMessage = nil } }
            )) {
                Button("OK") { syncMessage = nil }
            } message: {
                Text(syncMessage ?? "")
            }
            .alert("Sync Error", isPresented: $showSyncError) {
                Button("OK") { }
            } message: {
                Text(syncErrorMessage)
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
            Text("Default Content Rows")
        } footer: {
            Text("Drag to reorder, toggle to show/hide")
        }
    }
    
    // MARK: - Custom Rows Section
    private var customRowsSection: some View {
        Group {
            if customHomeRows.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Custom Rows")
                            .font(.headline)
                        Text("Add rows from imported lists or create custom hubs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section {
                    ForEach($customHomeRows) { $row in
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
                            
                            Toggle("", isOn: $row.isEnabled)
                                .labelsHidden()
                        }
                    }
                    .onDelete { indexSet in
                        customHomeRows.remove(atOffsets: indexSet)
                    }
                    .onMove { from, to in
                        customHomeRows.move(fromOffsets: from, toOffset: to)
                        updateCustomRowsSortOrder()
                    }
                } header: {
                    Text("Custom Rows")
                }
            }
            
            Section {
                Button {
                    showAddRowSheet = true
                } label: {
                    Label("Add Custom Row", systemImage: "plus.circle")
                }
            }
        }
    }
    
    // MARK: - Imported Lists Section
    private var importedListsSection: some View {
        Group {
            if importedLists.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "list.star")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Imported Lists")
                            .font(.headline)
                        Text("Import lists from MDBList or PublicMetaDB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section {
                    ForEach($importedLists) { $list in
                        HStack {
                            Image(systemName: list.source.iconName)
                                .foregroundColor(list.source == .mdblist ? .purple : .orange)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(list.displayName)
                                        .fontWeight(.medium)
                                    Text("(\(list.source.displayName))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    Text("\(list.items.count) items")
                                    if let synced = list.lastSynced {
                                        Text("•")
                                        Text(synced.formatted(.relative(presentation: .named)))
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("Home", isOn: $list.showOnHome)
                                .labelsHidden()
                        }
                    }
                    .onDelete { indexSet in
                        importedLists.remove(atOffsets: indexSet)
                    }
                } header: {
                    Text("Imported Lists")
                } footer: {
                    Text("Toggle to show on home screen")
                }
            }
            
            Section {
                Button {
                    showImportMDBList = true
                } label: {
                    Label("Import from MDBList", systemImage: "plus.circle")
                }
            }
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
    
    // MARK: - Data Management
    
    private func loadData() {
        browseRows = storage.browseRows.sorted { $0.sortOrder < $1.sortOrder }
        customHomeRows = storage.customHomeRows.sorted { $0.sortOrder < $1.sortOrder }
        importedLists = storage.importedLists
        networkHubs = storage.networkHubs.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private func saveChanges() {
        // Update sort orders
        updateBrowseSortOrder()
        updateCustomRowsSortOrder()
        updateNetworkHubsSortOrder()
        
        // Save to storage
        storage.updateBrowseRows(browseRows)
        storage.reorderCustomHomeRows(customHomeRows)
        storage.reorderNetworkHubs(networkHubs)
        
        // Update imported lists
        for list in importedLists {
            if storage.importedLists.contains(where: { $0.id == list.id }) {
                storage.updateImportedList(list)
            } else {
                storage.addImportedList(list)
            }
        }
        
        // Remove deleted lists
        for existingList in storage.importedLists {
            if !importedLists.contains(where: { $0.id == existingList.id }) {
                storage.deleteImportedList(id: existingList.id)
            }
        }
    }
    
    private func updateBrowseSortOrder() {
        for (index, _) in browseRows.enumerated() {
            browseRows[index].sortOrder = index
        }
    }
    
    private func updateCustomRowsSortOrder() {
        for (index, _) in customHomeRows.enumerated() {
            customHomeRows[index].sortOrder = index
        }
    }
    
    private func updateNetworkHubsSortOrder() {
        for (index, _) in networkHubs.enumerated() {
            networkHubs[index].sortOrder = index
        }
    }
    
    // MARK: - Cloud Sync
    
    private func syncToCloud() async {
        isSyncing = true
        
        do {
            try await HomeScreenSyncService.shared.uploadAllHomeScreenConfig(
                browseRows: browseRows,
                extensionLists: importedLists,
                customHomeRows: customHomeRows,
                networkHubs: networkHubs
            )
            await MainActor.run {
                syncMessage = "Home screen configuration uploaded to cloud!"
            }
        } catch {
            await MainActor.run {
                syncErrorMessage = error.localizedDescription
                showSyncError = true
            }
        }
        
        isSyncing = false
    }
    
    private func syncFromCloud() async {
        isSyncing = true
        
        do {
            let config = try await HomeScreenSyncService.shared.downloadAllHomeScreenConfig()
            
            await MainActor.run {
                // Apply browse rows if any
                if !config.browseRows.isEmpty {
                    browseRows = config.browseRows
                }
                
                // Apply extension lists
                if !config.extensionLists.isEmpty {
                    importedLists = config.extensionLists
                }
                
                // Apply custom home rows
                if !config.customHomeRows.isEmpty {
                    customHomeRows = config.customHomeRows
                }
                
                // Apply network hub config
                if !config.networkHubsConfig.isEmpty {
                    for hubConfig in config.networkHubsConfig {
                        if let index = networkHubs.firstIndex(where: { $0.id == hubConfig.hubId }) {
                            networkHubs[index].isEnabled = hubConfig.isEnabled
                            networkHubs[index].sortOrder = hubConfig.sortOrder
                        }
                    }
                    networkHubs.sort { $0.sortOrder < $1.sortOrder }
                }
                
                syncMessage = "Home screen configuration downloaded from cloud!"
            }
        } catch {
            await MainActor.run {
                syncErrorMessage = error.localizedDescription
                showSyncError = true
            }
        }
        
        isSyncing = false
    }
}

// MARK: - Add Home Row Sheet

struct AddHomeRowSheet: View {
    let importedLists: [ImportedListItem]
    let onAdd: (CustomHomeRow) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var rowType: CustomHomeRow.CustomRowType = .importedList
    @State private var name = ""
    @State private var imageURL = ""
    @State private var selectedList: ImportedListItem?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Row Type", selection: $rowType) {
                        Text("From Imported List").tag(CustomHomeRow.CustomRowType.importedList)
                        Text("Custom Hub").tag(CustomHomeRow.CustomRowType.customHub)
                    }
                    .pickerStyle(.segmented)
                }
                
                if rowType == .importedList {
                    Section("Select List") {
                        if importedLists.isEmpty {
                            Text("No imported lists available")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(importedLists) { list in
                                Button {
                                    selectedList = list
                                    if name.isEmpty {
                                        name = list.displayName
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: list.source.iconName)
                                            .foregroundColor(list.source == .mdblist ? .purple : .orange)
                                        Text(list.displayName)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if selectedList?.id == list.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if selectedList != nil {
                        Section {
                            TextField("Display Name (optional)", text: $name)
                        }
                    }
                } else {
                    Section("Hub Details") {
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
                                        .frame(height: 80)
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
                    .disabled(!canAdd)
                }
            }
        }
    }
    
    private var canAdd: Bool {
        if rowType == .importedList {
            return selectedList != nil
        } else {
            return !name.isEmpty
        }
    }
    
    private func addRow() {
        var row: CustomHomeRow
        
        if rowType == .importedList, let list = selectedList {
            row = CustomHomeRow.importedListRow(
                name: name.isEmpty ? list.displayName : name,
                listId: list.id,
                sortOrder: 0
            )
        } else {
            row = CustomHomeRow.hubRow(
                name: name,
                imageURL: imageURL.isEmpty ? nil : imageURL,
                sortOrder: 0
            )
        }
        
        onAdd(row)
        dismiss()
    }
}

// MARK: - Import MDBList Full Sheet

struct ImportMDBListFullSheet: View {
    let onImport: (ImportedListItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var listIdOrURL = ""
    @State private var customName = ""
    @State private var showOnHome = true
    @State private var isLoading = false
    @State private var error: String?
    @State private var previewItems: [SavedMediaItem] = []
    @State private var listName = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("MDBList URL or ID", text: $listIdOrURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: listIdOrURL) { _, _ in
                            previewItems = []
                            listName = ""
                            error = nil
                        }
                    
                    Button("Preview List") {
                        Task { await previewList() }
                    }
                    .disabled(listIdOrURL.isEmpty || isLoading)
                } header: {
                    Text("MDBList")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enter the MDBList URL or ID in format: username/listname")
                        Text("Example: dualipafan01/trending-titles")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !previewItems.isEmpty {
                    Section("Preview (\(previewItems.count) items)") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(previewItems.prefix(10)) { item in
                                    VStack(spacing: 4) {
                                        PosterImageView(posterPath: item.posterPath, size: .small)
                                            .frame(width: 60, height: 90)
                                        Text(item.title)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .frame(width: 60)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    
                    Section("Options") {
                        TextField("Custom Name (optional)", text: $customName)
                        Toggle("Show on Home Screen", isOn: $showOnHome)
                    }
                }
                
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
            }
            .navigationTitle("Import MDBList")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importList()
                    }
                    .disabled(previewItems.isEmpty || isLoading)
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
    
    private func previewList() async {
        isLoading = true
        error = nil
        
        let listId = MDBListService.shared.parseListId(from: listIdOrURL)
        
        // Extract name from URL
        if listId.contains("/") {
            let components = listId.split(separator: "/")
            if components.count >= 2 {
                listName = String(components.last ?? "MDBList")
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized
            }
        } else {
            listName = "MDBList"
        }
        
        do {
            previewItems = try await MDBListService.shared.fetchListItemsAsSavedMedia(listId: listId)
        } catch {
            self.error = "Failed to load list. Please check the URL or ID."
            print("MDBList error: \(error)")
        }
        
        isLoading = false
    }
    
    private func importList() {
        let listId = MDBListService.shared.parseListId(from: listIdOrURL)
        let finalName = customName.isEmpty ? listName : customName
        
        var newList = ImportedListItem(
            name: finalName,
            listId: listId,
            showOnHome: showOnHome,
            source: .mdblist
        )
        newList.items = previewItems
        newList.lastSynced = Date()
        
        if !customName.isEmpty {
            newList.customName = customName
        }
        
        onImport(newList)
        dismiss()
    }
}

#Preview {
    HomeCustomizationView()
}
