//
//  HomeCustomizationView.swift
//  WatchGuide-MovieandTVtracker
//
//  Home screen customization view
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct HomeCustomizationView: View {
    @ObservedObject private var storage = StorageService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var browseSections: [BrowseSectionItem] = []
    @State private var browseRows: [BrowseRowConfig] = []
    @State private var networkHubs: [NetworkHub] = []
    @State private var companyHubs: [CompanyHub] = []
    @State private var customHubs: [CustomJSONHub] = []
    
    @State private var selectedSection: HomeSection = .sections
    
    @State private var showAddJSONHub = false
    @State private var showAddStudioSheet = false
    
    // Hero Carousel sizing
    @ObservedObject private var profileService = ProfileService.shared
    @State private var selectedAspect: HeroCarouselAspect = .landscape
    @State private var widthRatio: Double = 1.0
    
    enum HomeSection: String, CaseIterable {
        case sections = "Sections"
        case carousel = "Carousel"
        case networks = "Networks"
        case studios = "Studios"
        case rows = "Rows"
        case hubs = "Hubs"
    }
    
    var body: some View {
        #if os(tvOS)
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "iphone")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("Customize on iPhone")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Home customization is managed on iPhone. Sync your changes to see them on Apple TV.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
            }
            .navigationTitle("Customize Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #else
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
                    case .carousel:
                        carouselSizeEditor
                    case .networks:
                        networksEditor
                    case .studios:
                        studiosEditor
                    case .rows:
                        browseRowsEditor
                    case .hubs:
                        customHubsEditor
                    }
                }
                #if os(macOS)
                .listStyle(.inset)
                #else
                .listStyle(.insetGrouped)
                .environment(\.editMode, .constant(.active))
                #endif
            }
            .navigationTitle("Customize Home")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        #endif
    }
    
    // MARK: - Carousel Size Editor
    private var carouselSizeEditor: some View {
        Group {
            Section {
                Picker("Orientation", selection: $selectedAspect) {
                    Text("Landscape").tag(HeroCarouselAspect.landscape)
                    Text("Portrait").tag(HeroCarouselAspect.portrait)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Carousel Orientation")
            } footer: {
                Text(selectedAspect == .landscape
                     ? "Landscape shows backdrop images in a wide cinematic view."
                     : "Portrait shows poster-style artwork in a taller format.")
            }
            
            Section {
                VStack(spacing: 12) {
                    HStack {
                        Text("Width")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(widthRatio * 100))%")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                    }
                    
                    Slider(value: $widthRatio, in: 0.45...1.0, step: 0.05)
                        .tint(.accentColor)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Carousel Width")
            } footer: {
                Text("Drag the slider to make the hero carousel narrower or wider on the home screen.")
            }
            
            // Live preview
            Section {
                carouselPreview
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text("Preview")
            }
            
            Section {
                Button {
                    selectedAspect = .landscape
                    widthRatio = 1.0
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.accentColor)
                        Text("Reset to Default")
                    }
                }
            }
        }
    }
    
    private var carouselPreview: some View {
        GeometryReader { geo in
            let previewAvailableWidth = geo.size.width
            let previewWidth = previewAvailableWidth * max(0.45, min(1.0, widthRatio))
            let previewHeight = previewWidth / selectedAspect.aspectRatio
            
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gray.opacity(0.18))
                .frame(width: previewWidth, height: previewHeight)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: selectedAspect == .landscape ? "rectangle.fill" : "rectangle.portrait.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("\(selectedAspect == .landscape ? "Landscape" : "Portrait") — \(Int(widthRatio * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.5, antialiased: true)
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.easeInOut(duration: 0.25), value: selectedAspect)
                .animation(.easeInOut(duration: 0.15), value: widthRatio)
        }
        .frame(height: carouselPreviewHeight)
        .padding(.vertical, 8)
    }
    
    private var carouselPreviewHeight: CGFloat {
        #if os(macOS)
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1200
        #else
        let screenWidth = UIScreen.main.bounds.width - 48 // approximate list inset
        #endif
        let previewWidth = screenWidth * max(0.45, min(1.0, widthRatio))
        return previewWidth / selectedAspect.aspectRatio + 16
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

    // MARK: - Studios
    private var studiosEditor: some View {
        Group {
            if companyHubs.isEmpty {
                Section {
                    Text("No studios configured")
                        .foregroundColor(.secondary)
                }
            } else {
                Section {
                    ForEach($companyHubs) { $hub in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(hub.name)
                                    .fontWeight(.medium)
                                Spacer()
                                Toggle("", isOn: $hub.isEnabled)
                                    .labelsHidden()
                            }

                            HStack(spacing: 10) {
                                Picker("Shape", selection: shapeBinding(for: $hub)) {
                                    ForEach(CompanyHub.ButtonShape.allCases, id: \.rawValue) { shape in
                                        Text(shape.displayName).tag(shape)
                                    }
                                }

                                Picker("Background", selection: backgroundBinding(for: $hub)) {
                                    ForEach(CompanyHub.BackgroundStyle.allCases, id: \.rawValue) { style in
                                        Text(style.displayName).tag(style)
                                    }
                                }
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { from, to in
                        companyHubs.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { indexSet in
                        companyHubs.remove(atOffsets: indexSet)
                    }
                } header: {
                    Text("Studios")
                } footer: {
                    Text("Drag to reorder. Toggle to show/hide. Choose shape and background for each studio button.")
                }
            }

            Section {
                Button {
                    showAddStudioSheet = true
                } label: {
                    Label("Add Studio", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $showAddStudioSheet) {
            NavigationStack {
                List {
                    ForEach(StudioTemplate.defaults, id: \.name) { template in
                        Button {
                            addStudioTemplate(template)
                            showAddStudioSheet = false
                        } label: {
                            HStack {
                                Text(template.name)
                                Spacer()
                                if companyHubs.contains(where: { $0.name.caseInsensitiveCompare(template.name) == .orderedSame }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Add Studio")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showAddStudioSheet = false }
                    }
                }
            }
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
        companyHubs = storage.companyHubs
        customHubs = storage.customJSONHubs.sorted { $0.sortOrder < $1.sortOrder }
        
        // Load carousel settings from active profile
        let profile = profileService.activeProfile
        selectedAspect = profile?.heroCarouselAspect ?? .landscape
        widthRatio = profile?.heroCarouselWidthRatio ?? 1.0
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
        storage.reorderCompanyHubs(companyHubs)
        
        // For custom hubs: reconcile with storage (handle deletions + reorder)
        let currentIds = Set(customHubs.map { $0.id })
        for existing in storage.customJSONHubs where !currentIds.contains(existing.id) {
            storage.deleteCustomJSONHub(id: existing.id)
        }
        storage.reorderCustomJSONHubs(customHubs)
        
        // Save carousel layout to active profile
        profileService.updateHeroCarouselLayout(widthRatio: widthRatio, aspect: selectedAspect)
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

    private func shapeBinding(for hub: Binding<CompanyHub>) -> Binding<CompanyHub.ButtonShape> {
        Binding<CompanyHub.ButtonShape>(
            get: { hub.wrappedValue.buttonShape ?? .roundedRectangle },
            set: { hub.wrappedValue.buttonShape = $0 }
        )
    }

    private func backgroundBinding(for hub: Binding<CompanyHub>) -> Binding<CompanyHub.BackgroundStyle> {
        Binding<CompanyHub.BackgroundStyle>(
            get: { hub.wrappedValue.backgroundStyle ?? .solid },
            set: { hub.wrappedValue.backgroundStyle = $0 }
        )
    }

    private func addStudioTemplate(_ template: StudioTemplate) {
        guard !companyHubs.contains(where: { $0.name.caseInsensitiveCompare(template.name) == .orderedSame }) else { return }
        companyHubs.append(
            CompanyHub(
                name: template.name,
                logoPath: template.logoURL,
                companyIds: [template.companyId],
                networkIds: [],
                buttonShape: .roundedRectangle,
                backgroundStyle: .solid
            )
        )
    }
}

private struct StudioTemplate {
    let name: String
    let companyId: Int
    let logoURL: String?

    static let defaults: [StudioTemplate] = [
        StudioTemplate(name: "Paramount Pictures", companyId: 4, logoURL: "https://cdn.brandfetch.io/idrAEeTLeo/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1757576972155"),
        StudioTemplate(name: "Walt Disney Pictures", companyId: 2, logoURL: "https://cdn.brandfetch.io/idxASqzkm_/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1675929043591"),
        StudioTemplate(name: "20th Century Studios", companyId: 127928, logoURL: "https://cdn.brandfetch.io/id80eyhRc1/w/820/h/683/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1667562091650"),
        StudioTemplate(name: "Searchlight Pictures", companyId: 127929, logoURL: nil),
        StudioTemplate(name: "Warner Bros.", companyId: 174, logoURL: "https://cdn.brandfetch.io/idxBWIwtz0/w/405/h/396/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1768344714851"),
        StudioTemplate(name: "Pixar", companyId: 3, logoURL: "https://cdn.brandfetch.io/idYVybSjsA/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1764458646138"),
        StudioTemplate(name: "Universal Pictures", companyId: 33, logoURL: "https://cdn.brandfetch.io/id4AnmmNSk/theme/light/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1767628904850"),
        StudioTemplate(name: "Sony Pictures", companyId: 34, logoURL: "https://cdn.brandfetch.io/idIBgcvFOi/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1766845823465"),
        StudioTemplate(name: "Metro-Goldwyn-Mayer", companyId: 21, logoURL: "https://cdn.brandfetch.io/idLI5gJfl8/w/161/h/86/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1667810266726"),
        StudioTemplate(name: "Lionsgate Films", companyId: 1632, logoURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/9/95/Lionsgate_2025.svg/500px-Lionsgate_2025.svg.png"),
        StudioTemplate(name: "A24", companyId: 41077, logoURL: "https://cdn.brandfetch.io/idHlMmIC6s/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1748302432792"),
        StudioTemplate(name: "DreamWorks", companyId: 521, logoURL: "https://cdn.brandfetch.io/idj7QnEvUG/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1764869429974"),
        StudioTemplate(name: "Blumhouse Productions", companyId: 3172, logoURL: "https://cdn.brandfetch.io/idMdr695hi/theme/dark/logo.svg?c=1bxid64Mup7aczewSAYMX&t=1767230760280"),
        StudioTemplate(name: "Happy Madison Productions", companyId: 878, logoURL: "https://upload.wikimedia.org/wikipedia/commons/4/4f/Happy-Madison-Productions-logo.png"),
        StudioTemplate(name: "Amblin Entertainment", companyId: 56, logoURL: "https://upload.wikimedia.org/wikipedia/en/1/16/Amblin_Entertainment_%28Print%29.svg")
    ]
}

#Preview {
    HomeCustomizationView()
}
