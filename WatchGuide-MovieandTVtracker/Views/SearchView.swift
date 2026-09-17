//
//  SearchView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SearchView: View {
    private enum ScoutAgentStep {
        case openingSearch
        case tappingField
        case typing
        case pressingEnter
        case selectingResult
        case openingDetails

        var title: String {
            switch self {
            case .openingSearch: return "Opening Search"
            case .tappingField: return "Placing Cursor"
            case .typing: return "Typing Title"
            case .pressingEnter: return "Searching"
            case .selectingResult: return "Reviewing Match"
            case .openingDetails: return "Opening Details"
            }
        }

        var iconName: String {
            switch self {
            case .openingSearch: return "sparkle.magnifyingglass"
            case .tappingField: return "cursorarrow.click"
            case .typing: return "keyboard"
            case .pressingEnter: return "return"
            case .selectingResult: return "checkmark.circle"
            case .openingDetails: return "rectangle.portrait.and.arrow.right"
            }
        }

    }

    @StateObject private var viewModel = SearchViewModel()
    @ObservedObject private var storage = StorageService.shared
    @ObservedObject private var scoutAgentRouteCenter = ScoutAgentRouteCenter.shared
    @Binding var selectedItem: MediaItem?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isSyncingUpload = false
    @State private var isSyncingDownload = false
    @State private var syncAlert: (title: String, message: String)?
    @State private var selectedPerson: Person?
    @State private var presentedScoutOverviewItem: MediaItem?
    @State private var isScoutOverviewExpanded = false
    @State private var scoutOverviewDragOffset: CGFloat = 0
    @State private var isInAppVisualScannerPresented = false
    @ObservedObject private var quickRouteCenter = WatchGuideQuickRouteCenter.shared
    @State private var useNaturalLanguageForNextSearch = false
    @State private var isHandlingScoutRoute = false
    @State private var scoutAgentStep: ScoutAgentStep?
    @State private var highlightedScoutResultID: Int?
    @State private var highlightedScoutPersonID: Int?
    @State private var searchFieldEmphasis = false
    @State private var showScoutPointer = false
    @State private var scoutPointerAtField = false
    @State private var showScoutCaret = false
    @State private var animateScoutCaret = false
    
    private let appleIntelligenceReport = AppleIntelligenceCapabilityService.currentReport()

    #if os(tvOS)
    private static let filterChipSpacing: CGFloat = 20
    private static let peopleGridMinSize: CGFloat = 200
    private static let peopleGridMaxSize: CGFloat = 260
    private static let peopleGridSpacing: CGFloat = 40
    private static let mediaGridMinSize: CGFloat = 220
    private static let mediaGridMaxSize: CGFloat = 260
    private static let mediaGridSpacing: CGFloat = 36
    private static let contentHorizontalPadding: CGFloat = 60
    private static let loadingScale: CGFloat = 1.8
    private static let emptyStateIconSize: CGFloat = 72
    private static let emptyStateTitleFont: Font = .title2
    private static let emptyStateSubtitleFont: Font = .body
    #else
    private static let filterChipSpacing: CGFloat = 12
    private static let peopleGridMinSize: CGFloat = 100
    private static let peopleGridMaxSize: CGFloat = 130
    private static let peopleGridSpacing: CGFloat = 20
    private static let mediaGridMinSize: CGFloat = 120
    private static let mediaGridMaxSize: CGFloat = 220
    private static let mediaGridSpacing: CGFloat = 16
    private static let contentHorizontalPadding: CGFloat = 16
    private static let loadingScale: CGFloat = 1.2
    private static let emptyStateIconSize: CGFloat = 48
    private static let emptyStateTitleFont: Font = .headline
    private static let emptyStateSubtitleFont: Font = .subheadline
    #endif

    var body: some View {
        #if os(tvOS)
        tvOSSearchBody
        #else
        iOSSearchBody
        #endif
    }

    #if os(tvOS)
    private var tvOSSearchBody: some View {
        VStack(spacing: 0) {
            searchContent
        }
        .searchable(text: $viewModel.query, prompt: "Search movies, TV shows, people...")
        .onSubmit(of: .search) {
            Task {
                await performSearch()
            }
        }
        .background(TVOSAmbientBackdrop())
        .sheet(item: $selectedPerson) { person in
            PersonDetailView(
                personId: person.id,
                personName: person.name,
                profilePath: person.profilePath
            )
        }
        .onChange(of: scoutAgentRouteCenter.pendingRoute?.id) { _, newValue in
            guard newValue != nil else { return }
            Task {
                await handlePendingScoutRouteIfNeeded()
            }
        }
        .task {
            await viewModel.loadGenres()
            await handlePendingScoutRouteIfNeeded()
        }
    }
    #else
    private var iOSSearchBody: some View {
        NavigationStack {
            iOSSearchInner
                .navigationTitle("Search")
        }
    }

    private var iOSSearchInner: some View {
        VStack(spacing: 0) {
            searchContent
        }
        .searchable(text: $viewModel.query, prompt: "Search movies, TV shows, people...")
        .onSubmit(of: .search) {
            Task {
                await performSearch()
            }
        }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                if PlatformCompatibility.supportsInAppVisualScanner {
                    inAppVisualScannerButton
                }
            }
            #endif

            ToolbarItemGroup(placement: .primaryAction) {
                if storage.settings.useAppleIntelligenceSearch && appleIntelligenceReport.isAppleIntelligenceAvailableNow {
                    appleIntelligenceSearchButton
                }

                Button {
                    Task {
                        await handleDownloadFromCloud()
                    }
                } label: {
                    if isSyncingDownload {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .help("Download from Cloud")
                .disabled(isSyncingDownload || isSyncingUpload)

                Button {
                    Task {
                        await handleUploadToCloud()
                    }
                } label: {
                    if isSyncingUpload {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle")
                    }
                }
                .help("Upload to Cloud")
                .disabled(isSyncingDownload || isSyncingUpload)
            }
        }
        .alert(syncAlert?.title ?? "", isPresented: Binding(get: { syncAlert != nil }, set: { if !$0 { syncAlert = nil } })) {
            Button("OK", role: .cancel) { syncAlert = nil }
        } message: {
            Text(syncAlert?.message ?? "")
        }
        .sheet(item: $selectedPerson) { person in
            PersonDetailView(
                personId: person.id,
                personName: person.name,
                profilePath: person.profilePath
            )
        }
        #if os(iOS)
        .sheet(isPresented: $isInAppVisualScannerPresented) {
            InAppVisualScannerView(selectedItem: $selectedItem)
        }
        #endif
        // The Scan control in Control Center opens the app on this tab and
        // leaves `.scanner` parked; the sheet is owned here, so this is where it
        // gets consumed.
        .onChange(of: quickRouteCenter.pending) { _, route in
            guard route?.destination == .scanner else { return }
            #if os(iOS)
            isInAppVisualScannerPresented = true
            #endif
            quickRouteCenter.consume()
        }
        .onChange(of: scoutAgentRouteCenter.pendingRoute?.id) { _, newValue in
            guard newValue != nil else { return }
            Task {
                await handlePendingScoutRouteIfNeeded()
            }
        }
        .task {
            await viewModel.loadGenres()
            await handlePendingScoutRouteIfNeeded()
        }
        #if !os(macOS)
        .toolbar(isScoutOverviewExpanded ? .hidden : .automatic, for: .tabBar)
        #endif
        .overlay(alignment: .bottom) {
            if let item = presentedScoutOverviewItem {
                ScoutOverviewGlassOverlay(
                    item: item,
                    dragOffset: $scoutOverviewDragOffset,
                    isExpanded: $isScoutOverviewExpanded,
                    onDismiss: {
                        dismissScoutOverview()
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }
    #endif

    @ViewBuilder
    private var searchContent: some View {
            
            

            if !isAgentRoutingActive && shouldShowInlineScoutOverview {
                scoutOverviewSection
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
            
            if !isAgentRoutingActive {
                Divider()
            }
            
            // Content
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(Self.loadingScale)
                Spacer()
            } else if viewModel.hasSearched && viewModel.isEmptyResults {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: Self.emptyStateIconSize))
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .font(Self.emptyStateTitleFont)
                    Text("Try different keywords or filters")
                        .font(Self.emptyStateSubtitleFont)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if !viewModel.hasSearched && viewModel.isEmptyResults {
                // Show search history and suggestions
                SearchSuggestionsView(
                    viewModel: viewModel,
                    onSelect: { query in
                        viewModel.query = query
                        Task {
                            await performSearch()
                        }
                    },
                    showBanner: true
                )
            } else if viewModel.isPeopleSearch {
                // People results grid (dedicated People filter)
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: Self.peopleGridMinSize, maximum: Self.peopleGridMaxSize), spacing: Self.peopleGridSpacing)
                    ], spacing: Self.peopleGridSpacing + 4) {
                        ForEach(viewModel.personResults) { person in
                            FocusableActionSurface(action: {
                                selectedPerson = person
                                let trimmed = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    StorageService.shared.addSearchHistory(trimmed)
                                }
                            }, outlineShape: .roundedRectangle(cornerRadius: 18)) {
                                PersonSearchCard(person: person)
                                    .overlay {
                                        if highlightedScoutPersonID == person.id {
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(Color.accentColor.opacity(0.9), lineWidth: 2.5)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                        .fill(Color.accentColor.opacity(0.08))
                                                )
                                                .shadow(color: Color.accentColor.opacity(0.22), radius: 16)
                                        }
                                    }
                                    .scaleEffect(highlightedScoutPersonID == person.id ? 1.02 : 1.0)
                                    .animation(.spring(response: 0.42, dampingFraction: 0.82), value: highlightedScoutPersonID)
                            }
                        }
                    }
                    .padding(.horizontal, Self.contentHorizontalPadding)
                    .padding(.vertical)
                    
                    // Load more
                    if viewModel.hasMorePages {
                        FocusableActionSurface(action: {
                            Task {
                                await viewModel.loadMore()
                            }
                        }, outlineShape: .roundedRectangle(cornerRadius: 16)) {
                            if viewModel.isLoadingMore {
                                ProgressView()
                            } else {
                                SearchActionButtonLabel(title: "Load More")
                            }
                        }
                        .padding()
                    }
                }
            } else {
                // Media results grid
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [
                            GridItem(
                                .adaptive(
                                    minimum: Self.mediaGridMinSize,
                                    maximum: Self.mediaGridMaxSize
                                ),
                                spacing: Self.mediaGridSpacing
                            )
                        ], spacing: Self.mediaGridSpacing + 4) {
                            ForEach(viewModel.results) { item in
                                FocusableActionSurface(action: {
                                    selectedItem = item
                                    let trimmed = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        StorageService.shared.addSearchHistory(trimmed)
                                    }
                                }, outlineShape: .roundedRectangle(cornerRadius: 18)) {
                                    MediaPosterCard(item: item)
                                        .overlay {
                                            if highlightedScoutResultID == item.id {
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .stroke(Color.accentColor.opacity(0.9), lineWidth: 2.5)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                            .fill(Color.accentColor.opacity(0.08))
                                                    )
                                                    .shadow(color: Color.accentColor.opacity(0.22), radius: 16)
                                            }
                                        }
                                        .scaleEffect(highlightedScoutResultID == item.id ? 1.02 : 1.0)
                                        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: highlightedScoutResultID)
                                }
                            }
                        }
                        .padding(.horizontal, Self.contentHorizontalPadding)
                    
                        // Load more
                        if viewModel.hasMorePages {
                            FocusableActionSurface(action: {
                                Task {
                                    await viewModel.loadMore()
                                }
                            }, outlineShape: .roundedRectangle(cornerRadius: 16)) {
                                if viewModel.isLoadingMore {
                                    ProgressView()
                                } else {
                                    SearchActionButtonLabel(title: "Load More")
                                }
                            }
                            .padding()
                        }
                    }
                    .padding(.top, Self.filterChipSpacing > 15 ? 20 : 8)
                }
            }
    }

    private var appleIntelligenceSearchButton: some View {
        Button {
            useNaturalLanguageForNextSearch.toggle()
        } label: {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(useNaturalLanguageForNextSearch ? .accentColor : .secondary)
        }
        .accessibilityLabel("Siri natural language search")
        .help("Use Siri natural language search for next query")
    }

    private var inAppVisualScannerButton: some View {
        Button {
            isInAppVisualScannerPresented = true
        } label: {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .accessibilityLabel("Scan a poster")
        .help("Scan a poster with the camera")
    }

    @ViewBuilder
    private var scoutAgentPointerOverlay: some View {
        if showScoutPointer {
            Image(systemName: "cursorarrow")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                .offset(
                    x: scoutPointerAtField ? 34 : 282,
                    y: scoutPointerAtField ? 24 : 84
                )
                .scaleEffect(scoutPointerAtField ? 0.92 : 1.0)
                .animation(.spring(response: 0.85, dampingFraction: 0.88), value: scoutPointerAtField)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var scoutAgentCaretOverlay: some View {
        if showScoutCaret {
            Rectangle()
                .fill(Color.accentColor.opacity(0.95))
                .frame(width: 2, height: 20)
                .clipShape(Capsule())
                .shadow(color: Color.accentColor.opacity(0.24), radius: 4)
                .opacity(animateScoutCaret ? 0.32 : 1.0)
                .offset(x: scoutCaretXOffset, y: 1)
                .allowsHitTesting(false)
                .onAppear {
                    animateScoutCaret = false
                    withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                        animateScoutCaret = true
                    }
                }
        }
    }

    private var scoutCaretXOffset: CGFloat {
        let approximateCharacterWidth: CGFloat = 8.2
        let baseOffset: CGFloat = 24
        let maxOffset: CGFloat = 250
        return min(baseOffset + (CGFloat(viewModel.query.count) * approximateCharacterWidth), maxOffset)
    }

    @ViewBuilder
    private var scoutAgentStatusPill: some View {
        if let scoutAgentStep {
            HStack(spacing: 8) {
                Image(systemName: scoutAgentStep.iconName)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(scoutAgentStep.title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.12))
            }
            .padding(.leading, 16)
            .padding(.bottom, -10)
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
    }
    
    // MARK: - Manual Sync Actions
    private func handleUploadToCloud() async {
        if isSyncingUpload || isSyncingDownload { return }
        await MainActor.run { isSyncingUpload = true }
        await storage.uploadToCloud()
        await MainActor.run {
            if let error = storage.lastSyncError, !error.isEmpty {
                syncAlert = ("Upload Failed", error)
            } else {
                syncAlert = ("Upload Complete", "Your lists have been uploaded to the cloud.")
            }
        }
        await MainActor.run { isSyncingUpload = false }
    }

    private func handleDownloadFromCloud() async {
        if isSyncingUpload || isSyncingDownload { return }
        await MainActor.run { isSyncingDownload = true }
        await storage.downloadFromCloud()
        await MainActor.run {
            if let error = storage.lastSyncError, !error.isEmpty {
                syncAlert = ("Download Failed", error)
            } else {
                syncAlert = ("Download Complete", "Your lists have been downloaded from the cloud.")
            }
        }
        await MainActor.run { isSyncingDownload = false }
    }

    private func performSearch() async {
        let shouldUseNaturalLanguage = storage.settings.useAppleIntelligenceSearch && useNaturalLanguageForNextSearch
        await viewModel.search(useNaturalLanguage: shouldUseNaturalLanguage)
        useNaturalLanguageForNextSearch = false
    }

    private func handlePendingScoutRouteIfNeeded() async {
        guard let route = scoutAgentRouteCenter.pendingRoute else { return }
        guard !isHandlingScoutRoute else { return }

        isHandlingScoutRoute = true
        highlightedScoutResultID = nil
        highlightedScoutPersonID = nil
        await updateScoutStep(.openingSearch)
        try? await Task.sleep(nanoseconds: 720_000_000)

        viewModel.selectedType = route.searchType
        viewModel.selectedGenre = nil
        viewModel.selectedYear = nil
        viewModel.selectedProductionLanguage = nil
        viewModel.selectedProductionRegion = nil
        useNaturalLanguageForNextSearch = false
        selectedItem = nil
        selectedPerson = nil

        viewModel.query = ""
        await updateScoutStep(.tappingField, emphasizeField: true)
        isSearchFocused = true
        try? await Task.sleep(nanoseconds: 920_000_000)

        await updateScoutStep(.typing, emphasizeField: true)
        for character in route.query {
            viewModel.query.append(character)
            let delay: UInt64 = character == " " ? 180_000_000 : 105_000_000
            try? await Task.sleep(nanoseconds: delay)
        }

        try? await Task.sleep(nanoseconds: 520_000_000)

        await updateScoutStep(.pressingEnter, emphasizeField: false)
        try? await Task.sleep(nanoseconds: 640_000_000)
        await viewModel.search(useNaturalLanguage: false)

        if route.opensMediaDetail, let match = route.preferredItem ?? preferredScoutAgentResult(for: route.query) {
            await updateScoutStep(.selectingResult)
            highlightedScoutResultID = match.id
            try? await Task.sleep(nanoseconds: 860_000_000)
            await updateScoutStep(.openingDetails)
            try? await Task.sleep(nanoseconds: 640_000_000)
            selectedItem = match
        } else if route.opensPersonPage, let person = route.preferredPerson ?? preferredScoutAgentPerson(for: route.query) {
            await updateScoutStep(.selectingResult)
            highlightedScoutPersonID = person.id
            try? await Task.sleep(nanoseconds: 860_000_000)
            await updateScoutStep(.openingDetails)
            try? await Task.sleep(nanoseconds: 640_000_000)
            selectedPerson = person
        }

        scoutAgentRouteCenter.consume(route.id)
        try? await Task.sleep(nanoseconds: 300_000_000)
        await clearScoutPresentation()
        isHandlingScoutRoute = false
    }

    @MainActor
    private func updateScoutStep(_ step: ScoutAgentStep?, emphasizeField: Bool = false) {
        withAnimation(.interactiveSpring(response: 0.44, dampingFraction: 0.9, blendDuration: 0.18)) {
            scoutAgentStep = step
            searchFieldEmphasis = emphasizeField
            showScoutPointer = step == .tappingField
            scoutPointerAtField = step == .tappingField
            showScoutCaret = step == .typing
        }
    }

    @MainActor
    private func clearScoutPresentation() {
        withAnimation(.easeOut(duration: 0.2)) {
            scoutAgentStep = nil
            highlightedScoutResultID = nil
            highlightedScoutPersonID = nil
            searchFieldEmphasis = false
            showScoutPointer = false
            scoutPointerAtField = false
            showScoutCaret = false
        }
    }

    private func preferredScoutAgentResult(for title: String) -> MediaItem? {
        let normalizedTitle = normalizedAgentTitle(title)
        return viewModel.results.first(where: { normalizedAgentTitle($0.displayTitle) == normalizedTitle }) ?? viewModel.results.first
    }

    private func preferredScoutAgentPerson(for title: String) -> Person? {
        let normalizedTitle = normalizedAgentTitle(title)
        return viewModel.personResults.first(where: { normalizedAgentTitle($0.name) == normalizedTitle }) ?? viewModel.personResults.first
    }

    private func normalizedAgentTitle(_ title: String) -> String {
        title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }

    private var isAgentRoutingActive: Bool {
        isHandlingScoutRoute || scoutAgentRouteCenter.pendingRoute != nil
    }

    @ViewBuilder
    private var scoutOverviewSection: some View {
        if let item = viewModel.scoutOverviewItem,
           let overview = item.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overview.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.yellow)

                    Text("Atlas Overview")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                }

                Text(item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(2)

                Text(overview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .onLongPressGesture(minimumDuration: 0.35) {
                performScoutOverviewHaptic()
                presentScoutOverview(for: item)
            }
        } else if viewModel.isLoadingScoutOverview {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Atlas is preparing an overview...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        } else {
            EmptyView()
        }
    }

    private var shouldShowInlineScoutOverview: Bool {
        #if os(tvOS)
        return !viewModel.hasSearched || viewModel.isEmptyResults || viewModel.isLoading
        #else
        return true
        #endif
    }

    private func performScoutOverviewHaptic() {
        #if canImport(UIKit) && !os(tvOS)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.9)
        #endif
    }

    private func presentScoutOverview(for item: MediaItem) {
        scoutOverviewDragOffset = 0
        isScoutOverviewExpanded = false
        presentedScoutOverviewItem = item
        DispatchQueue.main.async {
            withAnimation(.interactiveSpring(response: 0.78, dampingFraction: 0.84, blendDuration: 0.24)) {
                isScoutOverviewExpanded = true
            }
        }
    }

    private func dismissScoutOverview() {
        withAnimation(.interactiveSpring(response: 0.82, dampingFraction: 0.88, blendDuration: 0.26)) {
            isScoutOverviewExpanded = false
            scoutOverviewDragOffset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            if !isScoutOverviewExpanded {
                presentedScoutOverviewItem = nil
            }
        }
    }
}

private struct ScoutOverviewGlassOverlay: View {
    let item: MediaItem
    @Binding var dragOffset: CGFloat
    @Binding var isExpanded: Bool
    let onDismiss: () -> Void
    @State private var showExpandedContent = false

    private var overviewText: String {
        item.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var clampedDownwardOffset: CGFloat {
        max(0, dragOffset)
    }

    private var upwardStretch: CGFloat {
        max(0, -dragOffset)
    }

    private var backdropOpacity: CGFloat {
        let progress = min(clampedDownwardOffset / 220, 1)
        let baseOpacity: CGFloat = isExpanded ? 0.18 : 0.04
        return max(0.04, baseOpacity - (progress * 0.1))
    }

    private func panelWidth(for availableWidth: CGFloat) -> CGFloat {
        let expandedPanelWidth = min(620, max(availableWidth - 24, 168))
        let baseWidth = isExpanded ? expandedPanelWidth : 168
        let compression = min(clampedDownwardOffset / 6, isExpanded ? 54 : 36)
        return max(132, baseWidth - compression)
    }

    private var panelHeight: CGFloat {
        let baseHeight: CGFloat = isExpanded ? 430 : 56
        return baseHeight + upwardStretch
    }

    private var panelCornerRadius: CGFloat {
        isExpanded ? 34 : 28
    }

    private var handleWidth: CGFloat {
        42 + min(upwardStretch / 4, 18)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(backdropOpacity)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: 0) {
                    if isExpanded {
                        Capsule()
                            .fill(Color.primary.opacity(0.22))
                            .frame(width: handleWidth, height: 5 + min(upwardStretch / 30, 2))
                            .padding(.top, 12)
                            .padding(.bottom, 16)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "sparkles.rectangle.stack.fill")
                                                .foregroundStyle(.yellow)
                                            Text("Atlas Overview")
                                                .font(.headline.weight(.bold))
                                                .foregroundStyle(.primary)
                                        }

                                        Text(item.displayTitle)
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(.primary)

                                        if let year = item.year {
                                            Text(year)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Button(action: onDismiss) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.primary)
                                            .frame(width: 30, height: 30)
                                    }
                                    .buttonStyle(.glass)
                                }

                                Text(overviewText)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .opacity(showExpandedContent ? 1 : 0)
                        .offset(y: showExpandedContent ? 0 : 14)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.yellow)
                            Text("Atlas Overview")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(showExpandedContent ? 0 : 1)
                    }
                }
                .frame(
                    width: panelWidth(for: proxy.size.width),
                    height: panelHeight,
                    alignment: .top
                )
                .background {
                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: panelCornerRadius))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .offset(y: dragOffset)
                .shadow(color: .black.opacity(0.18), radius: 30, y: 8)
                #if !os(tvOS)
                .gesture(dismissDragGesture)
                #endif
                .padding(.bottom, isExpanded ? 8 : 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .animation(.interactiveSpring(response: 0.86, dampingFraction: 0.86, blendDuration: 0.24), value: isExpanded)
            }
        }
        .onAppear {
            showExpandedContent = false
            if isExpanded {
                revealExpandedContent()
            }
        }
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                showExpandedContent = false
                revealExpandedContent()
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    showExpandedContent = false
                }
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private func revealExpandedContent() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard isExpanded else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                showExpandedContent = true
            }
        }
    }

    #if !os(tvOS)
    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let translation = value.translation.height
                if translation >= 0 {
                    dragOffset = translation * 0.92
                } else {
                    dragOffset = translation * 0.35
                }
            }
            .onEnded { value in
                let shouldDismiss = value.translation.height > 150 || value.predictedEndTranslation.height > 260
                if shouldDismiss {
                    onDismiss()
                } else {
                    withAnimation(.interactiveSpring(response: 0.88, dampingFraction: 0.84, blendDuration: 0.26)) {
                        dragOffset = 0
                    }
                }
            }
    }
    #endif
}

// MARK: - Streaming Service Filter Section
struct StreamingServiceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let logoURL: String
    let brandColorHex: String
    let listURL: String
    /// Optional MDBList trending list URL — when set, tapping the card shows a trending popup
    let trendingListURL: String?
    
    init(id: String, name: String, logoURL: String, brandColorHex: String, listURL: String, trendingListURL: String? = nil) {
        self.id = id
        self.name = name
        self.logoURL = logoURL
        self.brandColorHex = brandColorHex
        self.listURL = listURL
        self.trendingListURL = trendingListURL
    }
}

struct StreamingServiceFilterSection: View {
    let services: [StreamingServiceOption]
    let selectedServiceIds: Set<String>
    let onToggle: (StreamingServiceOption) -> Void
    var onTrendingTap: ((StreamingServiceOption) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Networks")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(services) { service in
                        FocusableActionSurface(action: {
                            if service.trendingListURL != nil, let onTrendingTap {
                                onTrendingTap(service)
                            } else {
                                onToggle(service)
                            }
                        }, outlineShape: .roundedRectangle(cornerRadius: 16)) {
                            StreamingServiceCard(
                                service: service,
                                isSelected: selectedServiceIds.contains(service.id)
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct StreamingServiceCard: View {
    let service: StreamingServiceOption
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        Color(hex: service.brandColorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(backgroundColor)
                    .opacity(colorScheme == .dark ? 0.85 : 1.0)

                ResilientAsyncImage(url: URL(string: service.logoURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 26)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    case .failure:
                        Text(service.name)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    case .empty:
                        ProgressView()
                            .tint(.white)
                            .frame(height: 26)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .frame(width: 140, height: 54)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.25 : 0.12), radius: isSelected ? 8 : 4, y: 3)

            Text(service.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.gray.opacity(0.35), lineWidth: isSelected ? 2 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct StreamingRecommendationHeader: View {
    let serviceNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top 10 recommendations")
                .font(.headline)
                .fontWeight(.bold)
            if !serviceNames.isEmpty {
                Text(serviceNames.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

// MARK: - Popular TMDB Collection
struct PopularTMDBCollection: Identifiable, Hashable {
    let id: Int
    let title: String
    let logoAssetName: String?
    let artworkAssetName: String?
    let mdblistPath: String?
    let companyIds: [Int]
    let customBackdropURL: String?
    let overview: String
    let chronologicalTitles: [String]
    let timelineEntries: [CollectionTimelineEntry]

    init(
        id: Int,
        title: String,
        logoAssetName: String? = nil,
        artworkAssetName: String? = nil,
        mdblistPath: String? = nil,
        companyIds: [Int],
        customBackdropURL: String? = nil,
        overview: String,
        chronologicalTitles: [String],
        timelineEntries: [CollectionTimelineEntry] = []
    ) {
        self.id = id
        self.title = title
        self.logoAssetName = logoAssetName
        self.artworkAssetName = artworkAssetName
        self.mdblistPath = mdblistPath
        self.companyIds = companyIds
        self.customBackdropURL = customBackdropURL
        self.overview = overview
        self.chronologicalTitles = chronologicalTitles
        self.timelineEntries = timelineEntries
    }
    
    /// Resolved URL for the tile backdrop image
    var tileBackdropURL: URL? {
        guard artworkAssetName == nil else { return nil }
        if let custom = customBackdropURL, let url = URL(string: custom) {
            return url
        }
        return nil
    }
    
    var headerBackdropURL: URL? {
        guard artworkAssetName == nil else { return nil }
        guard let customBackdropURL, let url = URL(string: customBackdropURL) else { return nil }
        return url
    }

    static let popular: [PopularTMDBCollection] = [
        PopularTMDBCollection(
            id: 7505,
            title: "Marvel",
            artworkAssetName: "Marvel",
            mdblistPath: "dualipafan01/marvel-studios",
            companyIds: [7505],
            overview: "Explore Marvel movies from TMDB company 7505 with release order, MCU chronology, and box office rankings.",
            chronologicalTitles: [
                "Captain America: The First Avenger",
                "Captain Marvel",
                "Iron Man",
                "Iron Man 2",
                "The Incredible Hulk",
                "Thor",
                "The Avengers",
                "Thor: The Dark World",
                "Iron Man 3",
                "Captain America: The Winter Soldier",
                "Guardians of the Galaxy",
                "Guardians of the Galaxy Vol. 2",
                "Avengers: Age of Ultron",
                "Ant-Man",
                "Captain America: Civil War",
                "Black Widow",
                "Black Panther",
                "Spider-Man: Homecoming",
                "Doctor Strange",
                "Thor: Ragnarok",
                "Ant-Man and the Wasp",
                "Avengers: Infinity War",
                "Avengers: Endgame",
                "WandaVision",
                "Shang-Chi and the Legend of the Ten Rings",
                "Eternals",
                "Spider-Man: Far From Home",
                "Spider-Man: No Way Home",
                "Doctor Strange in the Multiverse of Madness",
                "Black Panther: Wakanda Forever",
                "The Marvels",
                "The Fantastic Four: First Steps",
                "Deadpool & Wolverine",
                "Captain America: Brave New World",
                "Thunderbolts"
            ],
            timelineEntries: CollectionTimelineEntry.marvelStudios
        )
    ]
}

struct CollectionTimelineEntry: Identifiable, Hashable {
    enum Lane: Int, Hashable {
        case sacredTimeline
        case branch
        case branchDeep
    }

    let title: String
    let chronologyText: String
    let universeLabel: String?
    let branchLabel: String?
    let lane: Lane

    var id: String { title }

    static let marvelStudios: [CollectionTimelineEntry] = [
        .init(title: "Captain America: The First Avenger", chronologyText: "World War II origin", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Captain Marvel", chronologyText: "1995 cosmic awakening", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Iron Man", chronologyText: "2008, the MCU ignition point", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Iron Man 2", chronologyText: "Fury closes in", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "The Incredible Hulk", chronologyText: "Runs parallel to early Avengers setup", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Thor", chronologyText: "Asgard enters the timeline", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "The Avengers", chronologyText: "Battle of New York", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Thor: The Dark World", chronologyText: "Post-Avengers fallout", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Iron Man 3", chronologyText: "Tony after New York", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Captain America: The Winter Soldier", chronologyText: "S.H.I.E.L.D. collapses", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Guardians of the Galaxy", chronologyText: "The cosmic side opens up", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Guardians of the Galaxy Vol. 2", chronologyText: "Immediately after Vol. 1", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Avengers: Age of Ultron", chronologyText: "The team starts to fracture", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Ant-Man", chronologyText: "Quantum Realm groundwork", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Captain America: Civil War", chronologyText: "The Avengers split", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Black Widow", chronologyText: "Immediately after Civil War", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Black Panther", chronologyText: "Wakanda rises", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Spider-Man: Homecoming", chronologyText: "Peter’s first solo chapter", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Doctor Strange", chronologyText: "The mystic corner of Earth-616", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Thor: Ragnarok", chronologyText: "Asgard falls", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Ant-Man and the Wasp", chronologyText: "Right before the Snap", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Avengers: Infinity War", chronologyText: "The Snap", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Avengers: Endgame", chronologyText: "Time Heist restores the Sacred Timeline", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Loki S1", chronologyText: "A 2012 variant gets pruned off the main line", universeLabel: "TVA / Branched 2012", branchLabel: "Branches off during the Time Heist", lane: .branch),
        .init(title: "What If…? S1", chronologyText: "The Watcher surveys alternate realities", universeLabel: "Multiverse", branchLabel: "Splits outward once Loki opens the multiverse", lane: .branchDeep),
        .init(title: "WandaVision", chronologyText: "Late 2023, grief reshapes Westview", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Shang-Chi and the Legend of the Ten Rings", chronologyText: "Post-Blip reset", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Spider-Man: Far From Home", chronologyText: "The world reckons with Endgame", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Eternals", chronologyText: "Celestial fallout reaches Earth", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Spider-Man", chronologyText: "The original live-action Peter Parker branch", universeLabel: "Raimi Universe / Earth-96283", branchLabel: "Pulled into No Way Home from the Raimi branch", lane: .branch),
        .init(title: "Spider-Man 2", chronologyText: "The Raimi timeline continues", universeLabel: "Raimi Universe / Earth-96283", branchLabel: "Same branch as Tobey Maguire's Peter Parker", lane: .branch),
        .init(title: "Spider-Man 3", chronologyText: "The Raimi branch reaches its final pre-No Way Home chapter", universeLabel: "Raimi Universe / Earth-96283", branchLabel: "Continues the Raimi branch into the multiverse crossover", lane: .branch),
        .init(title: "The Amazing Spider-Man", chronologyText: "A separate Peter Parker timeline begins", universeLabel: "Webb Universe / Earth-120703", branchLabel: "Pulled into No Way Home from Andrew Garfield's branch", lane: .branchDeep),
        .init(title: "The Amazing Spider-Man 2", chronologyText: "Electro and Andrew's Peter leave this branch for No Way Home", universeLabel: "Webb Universe / Earth-120703", branchLabel: "Continues the Webb branch into the multiverse crossover", lane: .branchDeep),
        .init(title: "Spider-Man: No Way Home", chronologyText: "Multiversal visitors collide with Earth-616", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Doctor Strange in the Multiverse of Madness", chronologyText: "Incursions touch the Sacred Timeline", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Black Panther: Wakanda Forever", chronologyText: "Wakanda after loss", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "The Marvels", chronologyText: "Cosmic threads converge", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "The Fantastic Four: First Steps", chronologyText: "Marvel's First Family begins in a retro-futurist parallel world", universeLabel: "Earth-828", branchLabel: "A separate Fantastic Four branch running beside Earth-616", lane: .branchDeep),
        .init(title: "X-Men", chronologyText: "The Fox mutant timeline begins", universeLabel: "Fox X-Men Universe / Earth-10005", branchLabel: "One of the key parallel branches feeding into Deadpool & Wolverine", lane: .branch),
        .init(title: "X2", chronologyText: "The Fox branch deepens", universeLabel: "Fox X-Men Universe / Earth-10005", branchLabel: "Continues the Fox mutant branch", lane: .branch),
        .init(title: "X-Men: The Last Stand", chronologyText: "The original Fox trilogy concludes", universeLabel: "Fox X-Men Universe / Earth-10005", branchLabel: "Part of the Fox branch later intersecting the TVA story", lane: .branch),
        .init(title: "Deadpool", chronologyText: "Wade Wilson’s universe spins off inside the Fox branch", universeLabel: "Fox X-Men Universe / Earth-10005", branchLabel: "Leads directly into the TVA collision in Deadpool & Wolverine", lane: .branch),
        .init(title: "Deadpool 2", chronologyText: "Cable and time travel complicate the Fox branch", universeLabel: "Fox X-Men Universe / Earth-10005", branchLabel: "Sets up the TVA-facing branch seen later", lane: .branch),
        .init(title: "Logan", chronologyText: "A future endpoint inside the Fox branch", universeLabel: "Fox X-Men Universe / Earth-10005", branchLabel: "A distant branch point echoed by Deadpool & Wolverine", lane: .branchDeep),
        .init(title: "Deadpool & Wolverine", chronologyText: "Fox-era reality intersects with the TVA", universeLabel: "Earth-10005 / TVA", branchLabel: "Runs parallel to the TVA branch", lane: .branch),
        .init(title: "Captain America: Brave New World", chronologyText: "A new Captain America era", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline),
        .init(title: "Thunderbolts", chronologyText: "The antihero formation", universeLabel: nil, branchLabel: nil, lane: .sacredTimeline)
    ]
}

// MARK: - Search Suggestions View
struct SearchSuggestionsView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onSelect: (String) -> Void
    var showBanner: Bool = false

    @State private var liveTrendingTitles: [String] = []

    private var trendingSuggestions: [String] {
        if !liveTrendingTitles.isEmpty { return liveTrendingTitles }
        if StorageService.shared.settings.isKidsProfile {
            return ["Frozen", "Moana", "Toy Story", "Paw Patrol", "Bluey", "SpongeBob", "Encanto", "Lego Movie"]
        }
        return ["Dune", "The Last of Us", "Oppenheimer", "Breaking Bad", "The Batman", "Succession", "Avatar", "Stranger Things"]
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Recent searches
                if !StorageService.shared.searchHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Searches")
                                #if os(tvOS)
                                .font(.title3)
                                #else
                                .font(.headline)
                                #endif
                            Spacer()
                            Button("Clear") {
                                StorageService.shared.clearSearchHistory()
                            }
                            #if os(tvOS)
                            .font(.callout)
                            #else
                            .font(.caption)
                            #endif
                            .foregroundColor(.secondary)
                            .buttonStyle(.plain)
                        }
                        
                        #if os(tvOS)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(StorageService.shared.searchHistory.prefix(10)) { item in
                                    FocusableActionSurface(action: {
                                        onSelect(item.query)
                                    }, outlineShape: .capsule) {
                                        SearchSuggestionChip(
                                            title: item.query,
                                            systemImage: "clock"
                                        )
                                    }
                                }
                            }
                        }
                        .scrollClipDisabled()
                        #else
                        FlowLayout(spacing: 8) {
                            ForEach(StorageService.shared.searchHistory.prefix(10)) { item in
                                FocusableActionSurface(action: {
                                    onSelect(item.query)
                                }, outlineShape: .capsule) {
                                    SearchSuggestionChip(
                                        title: item.query,
                                        systemImage: "clock"
                                    )
                                }
                            }
                        }
                        #endif
                    }
                }
                
                // Trending searches
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trending")
                        #if os(tvOS)
                        .font(.title3)
                        #else
                        .font(.headline)
                        #endif
                    
                    #if os(tvOS)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(trendingSuggestions, id: \.self) { term in
                                FocusableActionSurface(action: {
                                    onSelect(term)
                                }, outlineShape: .capsule) {
                                    SearchSuggestionChip(
                                        title: term,
                                        systemImage: "flame.fill",
                                        iconColor: .orange
                                    )
                                }
                            }
                        }
                    }
                    .scrollClipDisabled()
                    #else
                    FlowLayout(spacing: 8) {
                        ForEach(trendingSuggestions, id: \.self) { term in
                            FocusableActionSurface(action: {
                                onSelect(term)
                            }, outlineShape: .capsule) {
                                SearchSuggestionChip(
                                    title: term,
                                    systemImage: "flame.fill",
                                    iconColor: .orange
                                )
                            }
                        }
                    }
                    #endif
                }

                if showBanner {
                    RemoteBannerView(placement: .search)
                        #if os(tvOS)
                        .frame(maxWidth: 500)
                        .frame(maxWidth: .infinity, alignment: .center)
                        #endif
                }
            }
            #if os(tvOS)
            .padding(.horizontal, 60)
            .padding(.vertical, 24)
            #else
            .padding()
            #endif
        }
        .task {
            guard liveTrendingTitles.isEmpty && !StorageService.shared.settings.isKidsProfile else { return }
            do {
                async let moviesTask = TMDBService.shared.getTrending(mediaType: .movie)
                async let tvTask = TMDBService.shared.getTrending(mediaType: .tv)
                let (movies, shows) = try await (moviesTask, tvTask)
                let movieTitles = movies.results.prefix(6).map { $0.displayTitle }
                let tvTitles = shows.results.prefix(6).map { $0.displayTitle }
                var combined: [String] = []
                for (m, t) in zip(movieTitles, tvTitles) {
                    combined.append(m)
                    combined.append(t)
                }
                await MainActor.run {
                    liveTrendingTitles = Array(combined.prefix(12))
                }
            } catch {}
        }
    }
}

// MARK: - TMDB Collection Tile
struct TMDBCollectionTile: View {
    let collection: PopularTMDBCollection
    @State private var isPressed = false
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image
            Group {
                if let artworkAssetName = collection.artworkAssetName {
                    Image(artworkAssetName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.10))
                } else {
                    ResilientAsyncImage(url: collection.tileBackdropURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .empty:
                            Color.gray.opacity(0.18)
                                .overlay(ProgressView())
                        case .failure:
                            Color.gray.opacity(0.18)
                        @unknown default:
                            Color.gray.opacity(0.18)
                        }
                    }
                }
            }
            .frame(height: 100)
            .clipped()
            
            // Gradient overlay
            LinearGradient(
                colors: [.black.opacity(0.75), .black.opacity(0.1)],
                startPoint: .bottom,
                endPoint: .top
            )
            
            // Title
            VStack(alignment: .leading, spacing: 8) {
                if let logoAssetName = collection.logoAssetName, collection.artworkAssetName == nil {
                    Image(logoAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 22)
                }

                Text(collection.title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            .padding(10)
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - TMDB Collection Sheet
struct TMDBCollectionSheet: View {
    private enum CollectionSubview: String, CaseIterable, Identifiable {
        case release = "Release"
        case chronological = "Chronological"
        case boxOffice = "Box Office"

        var id: String { rawValue }
    }

    private struct BoxOfficeEntry: Identifiable {
        let item: MediaItem
        let revenue: Int

        var id: Int { item.id }
    }

    let collection: PopularTMDBCollection
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var items: [MediaItem] = []
    @State private var selectedSubview: CollectionSubview = .release
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedItem: MediaItem?
    @State private var boxOfficeEntries: [BoxOfficeEntry] = []
    @State private var isLoadingBoxOffice = false
    @State private var didLoadBoxOffice = false
    
    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass),
                    maximum: ResponsiveSizing.gridPosterWidth(horizontalSizeClass: horizontalSizeClass) + 30
                ),
                spacing: 16
            )
        ]
    }

    private var releaseItems: [MediaItem] {
        items.sorted { lhs, rhs in
            (lhs.releaseDate ?? "9999-99-99", lhs.displayTitle) < (rhs.releaseDate ?? "9999-99-99", rhs.displayTitle)
        }
    }

    private var chronologicalItems: [MediaItem] {
        let titleRanks = Dictionary(
            uniqueKeysWithValues: collection.chronologicalTitles.enumerated().map { offset, title in
                (Self.normalizedCollectionTitle(title), offset)
            }
        )

        return items.sorted { lhs, rhs in
            let lhsRank = titleRanks[Self.normalizedCollectionTitle(lhs.displayTitle)] ?? Int.max
            let rhsRank = titleRanks[Self.normalizedCollectionTitle(rhs.displayTitle)] ?? Int.max

            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            return (lhs.releaseDate ?? "9999-99-99", lhs.displayTitle) < (rhs.releaseDate ?? "9999-99-99", rhs.displayTitle)
        }
    }

    private var timelineItemsByTitle: [String: MediaItem] {
        items.reduce(into: [String: MediaItem]()) { partialResult, item in
            let key = Self.normalizedCollectionTitle(item.displayTitle)
            if partialResult[key] == nil {
                partialResult[key] = item
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Spacer()
                    }
                } else if let error = error, items.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text("Failed to load collection")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let artworkAssetName = collection.artworkAssetName {
                                Image(artworkAssetName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 120)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.black.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .padding(.horizontal)
                            } else if let headerBackdropURL = collection.headerBackdropURL {
                                ResilientAsyncImage(url: headerBackdropURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(height: 180)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    case .empty:
                                        ProgressView()
                                            .frame(height: 180)
                                            .frame(maxWidth: .infinity)
                                            .background(Color.gray.opacity(0.16))
                                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    case .failure:
                                        EmptyView()
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .padding(.horizontal)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                if let logoAssetName = collection.logoAssetName, collection.artworkAssetName == nil {
                                    Image(logoAssetName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 30)
                                }

                                Text(collection.overview)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                collectionSubviewPicker
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)

                            switch selectedSubview {
                            case .release:
                                collectionGrid(items: releaseItems)
                            case .chronological:
                                chronologicalContent
                            case .boxOffice:
                                boxOfficeContent
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle(collection.title)
            .inlineNavTitleIfSupported()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .mediaDetailPresentation(item: $selectedItem)
            .task {
                await loadCollection()
            }
            .task(id: selectedSubview) {
                if selectedSubview == .boxOffice {
                    await loadBoxOfficeIfNeeded()
                }
            }
        }
    }
    
    private func loadCollection() async {
        isLoading = true
        error = nil

        do {
            if let mdblistPath = collection.mdblistPath, !mdblistPath.isEmpty {
                items = try await MDBListService.shared.fetchMultipleListsAsMediaItems(
                    inputs: [mdblistPath],
                    preferTMDBDetails: false
                )
            } else {
                items = try await loadCompanyMovies()
            }
        } catch let loadError {
            self.error = loadError.localizedDescription
            print("Collection load error for \(collection.title): \(loadError)")
        }

        isLoading = false
    }

    private func loadCompanyMovies() async throws -> [MediaItem] {
        var page = 1
        var allItems: [MediaItem] = []
        var totalPages = 1

        repeat {
            let response = try await TMDBService.shared.discoverMoviesByCompany(
                companyIds: collection.companyIds,
                sortBy: "primary_release_date.asc",
                page: page
            )

            allItems.append(contentsOf: response.results)
            totalPages = min(response.totalPages ?? 1, 10)
            page += 1
        } while page <= totalPages

        var uniqueItems: [Int: MediaItem] = [:]
        for item in allItems {
            uniqueItems[item.id] = item
        }

        return uniqueItems.values.sorted { lhs, rhs in
            (lhs.releaseDate ?? "9999-99-99", lhs.displayTitle) < (rhs.releaseDate ?? "9999-99-99", rhs.displayTitle)
        }
    }

    private func loadBoxOfficeIfNeeded() async {
        guard !didLoadBoxOffice, !isLoadingBoxOffice, !items.isEmpty else { return }
        isLoadingBoxOffice = true

        defer {
            isLoadingBoxOffice = false
            didLoadBoxOffice = true
        }

        let movieItems = items.filter { $0.resolvedMediaType == .movie }
        var entries: [BoxOfficeEntry] = []

        await withTaskGroup(of: BoxOfficeEntry?.self) { group in
            for item in movieItems {
                group.addTask {
                    do {
                        let details = try await TMDBService.shared.getMovieDetails(id: item.id)
                        guard let revenue = details.revenue, revenue > 0 else { return nil }
                        return BoxOfficeEntry(item: item, revenue: revenue)
                    } catch {
                        return nil
                    }
                }
            }

            for await entry in group {
                if let entry {
                    entries.append(entry)
                }
            }
        }

        boxOfficeEntries = entries.sorted { lhs, rhs in
            if lhs.revenue != rhs.revenue {
                return lhs.revenue > rhs.revenue
            }

            return lhs.item.displayTitle < rhs.item.displayTitle
        }
    }

    @ViewBuilder
    private func collectionGrid(items: [MediaItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(items) { item in
                MediaPosterCard(item: item)
                    .onTapGesture {
                        selectedItem = item
                    }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var chronologicalContent: some View {
        if !collection.timelineEntries.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sacred Timeline")
                        .font(.title3.weight(.semibold))

                    Text("Follow the MCU in story order. Branch markers show when the path splits into alternate universes, TVA detours, or deeper multiverse threads.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        TimelineLegendChip(title: "Earth-616", systemImage: "circle.fill", tint: .red)
                        TimelineLegendChip(title: "Branch", systemImage: "point.3.filled.connected.trianglepath.dotted", tint: .orange)
                        TimelineLegendChip(title: "Deep Branch", systemImage: "sparkles", tint: .blue)
                    }

                    HStack(spacing: 12) {
                        timelineStatCard(
                            title: "Entries",
                            value: "\(collection.timelineEntries.count)",
                            tint: .red
                        )
                        timelineStatCard(
                            title: "Playable",
                            value: "\(collection.timelineEntries.filter { timelineItemsByTitle[Self.normalizedCollectionTitle($0.title)] != nil }.count)",
                            tint: .green
                        )
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.red.opacity(0.16),
                                    Color.black.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal)

                VStack(spacing: 14) {
                    ForEach(Array(collection.timelineEntries.enumerated()), id: \.element.id) { index, entry in
                        CollectionTimelineRow(
                            entry: entry,
                            item: timelineItemsByTitle[Self.normalizedCollectionTitle(entry.title)],
                            accentColor: .red,
                            chronologyIndex: index + 1
                        ) {
                            if let item = timelineItemsByTitle[Self.normalizedCollectionTitle(entry.title)] {
                                selectedItem = item
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        } else {
            collectionGrid(items: chronologicalItems)
        }
    }

    @ViewBuilder
    private var boxOfficeContent: some View {
        if isLoadingBoxOffice && boxOfficeEntries.isEmpty {
            ProgressView("Loading box office")
                .padding(.top, 24)
        } else if boxOfficeEntries.isEmpty {
            Text("No box office results available.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 24)
        } else {
            VStack(spacing: 12) {
                ForEach(Array(boxOfficeEntries.enumerated()), id: \.element.id) { index, entry in
                    FocusableActionSurface(action: {
                        selectedItem = entry.item
                    }, outlineShape: .roundedRectangle(cornerRadius: 18)) {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(width: 28)

                            MediaPosterThumbnail(item: entry.item)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.item.displayTitle)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)

                                if let releaseDate = entry.item.releaseDate, !releaseDate.isEmpty {
                                    Text(releaseDate)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Text(Self.currencyFormatter.string(from: NSNumber(value: entry.revenue)) ?? "$0")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }

                            Spacer()
                        }
                        .padding(14)
                        .background(Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var collectionSubviewPicker: some View {
        HStack(spacing: 10) {
            ForEach(CollectionSubview.allCases) { subview in
                let isSelected = selectedSubview == subview

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedSubview = subview
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subview.rawValue)
                            .font(.subheadline.weight(.semibold))
                        Text(collectionSubviewSubtitle(for: subview))
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? .white.opacity(0.86) : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(selectedSubviewFill(for: subview)) : AnyShapeStyle(Color.gray.opacity(0.12)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isSelected ? .white.opacity(0.12) : .white.opacity(0.06), lineWidth: 1)
                    )
                    .foregroundStyle(isSelected ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func collectionSubviewSubtitle(for subview: CollectionSubview) -> String {
        switch subview {
        case .release:
            return "Original launch order"
        case .chronological:
            return "Story timeline flow"
        case .boxOffice:
            return "Revenue ranking"
        }
    }

    private func selectedSubviewFill(for subview: CollectionSubview) -> some ShapeStyle {
        switch subview {
        case .release:
            return LinearGradient(colors: [Color.red.opacity(0.78), Color.orange.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .chronological:
            return LinearGradient(colors: [Color.red.opacity(0.82), Color.pink.opacity(0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .boxOffice:
            return LinearGradient(colors: [Color.green.opacity(0.78), Color.teal.opacity(0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder
    private func timelineStatCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static func normalizedCollectionTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .alphanumerics.inverted)
            .joined()
    }
}

private struct CollectionTimelineRow: View {
    let entry: CollectionTimelineEntry
    let item: MediaItem?
    let accentColor: Color
    let chronologyIndex: Int
    let action: () -> Void

    private var laneOffset: CGFloat {
        switch entry.lane {
        case .sacredTimeline:
            return 0
        case .branch:
            return 26
        case .branchDeep:
            return 52
        }
    }

    private var isInteractive: Bool {
        item != nil
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(accentColor.opacity(0.18))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .offset(x: 13)

                    if entry.lane != .sacredTimeline {
                        Rectangle()
                            .fill(accentColor.opacity(0.18))
                            .frame(width: laneOffset + 1, height: 2)
                            .offset(x: 13, y: 14)
                    }

                    Circle()
                        .fill(nodeFill)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(nodeStroke, lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: nodeSymbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(nodeForeground)
                        )
                        .offset(x: 0)
                }
                .frame(width: 28 + laneOffset, alignment: .leading)

                if let item {
                    MediaPosterThumbnail(item: item)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: 58, height: 86)
                        .overlay(
                            Image(systemName: "film")
                                .foregroundStyle(.secondary)
                        )
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Step \(chronologyIndex)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(nodeForeground)
                            #if !os(tvOS)
                                .textCase(.uppercase)
                            #endif

                            Text(entry.title)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(entry.chronologyText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        if isInteractive {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)
                        }
                    }

                    if let universeLabel = entry.universeLabel {
                        Text(universeLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(chipForeground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(chipFill)
                            )
                    }

                    if let branchLabel = entry.branchLabel {
                        Label(branchLabel, systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var nodeSymbol: String {
        switch entry.lane {
        case .sacredTimeline:
            return "circle.fill"
        case .branch:
            return "point.3.filled.connected.trianglepath.dotted"
        case .branchDeep:
            return "sparkles"
        }
    }

    private var nodeFill: Color {
        switch entry.lane {
        case .sacredTimeline:
            return accentColor.opacity(0.16)
        case .branch:
            return .orange.opacity(0.16)
        case .branchDeep:
            return .blue.opacity(0.16)
        }
    }

    private var nodeStroke: Color {
        switch entry.lane {
        case .sacredTimeline:
            return accentColor.opacity(0.35)
        case .branch:
            return .orange.opacity(0.35)
        case .branchDeep:
            return .blue.opacity(0.35)
        }
    }

    private var nodeForeground: Color {
        switch entry.lane {
        case .sacredTimeline:
            return accentColor
        case .branch:
            return .orange
        case .branchDeep:
            return .blue
        }
    }

    private var chipFill: Color {
        switch entry.lane {
        case .sacredTimeline:
            return accentColor.opacity(0.12)
        case .branch:
            return .orange.opacity(0.14)
        case .branchDeep:
            return .blue.opacity(0.14)
        }
    }

    private var chipForeground: Color {
        switch entry.lane {
        case .sacredTimeline:
            return accentColor
        case .branch:
            return .orange
        case .branchDeep:
            return .blue
        }
    }
}

private struct TimelineLegendChip: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

private struct MediaPosterThumbnail: View {
    let item: MediaItem

    var body: some View {
        ResilientAsyncImage(url: TMDBService.shared.imageURL(path: item.posterPath, size: .small)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .empty:
                Color.gray.opacity(0.2)
            case .failure:
                Color.gray.opacity(0.2)
            @unknown default:
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: 46, height: 68)
        // Deliberately tighter than `sharedPosterCornerRadius`: at 46pt wide the
        // shared 14pt radius eats a third of the thumbnail and reads as a blob.
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + maxHeight)
        }
    }
}

// MARK: - Search View Model
@MainActor
class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [MediaItem] = []
    @Published var personResults: [Person] = []
    @Published var scoutOverviewItem: MediaItem?
    @Published var selectedType: MediaType?
    @Published var selectedGenre: Genre?
    @Published var selectedYear: Int?
    @Published var selectedProductionLanguage: String?
    @Published var selectedProductionRegion: String?
    @Published var genres: [Genre] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var isLoadingScoutOverview = false
    @Published var hasSearched = false
    @Published var currentPage = 1
    @Published var totalPages = 1
    @Published var selectedStreamingServiceIds: Set<String> = []
    @Published private(set) var usedNaturalLanguageInLastSearch = false

    let streamingServices: [StreamingServiceOption] = [
        StreamingServiceOption(
            id: "netflix",
            name: "Netflix",
            logoURL: "https://cdn.brandfetch.io/ideQwN5lBE/w/800/h/216/theme/light/logo.png?c=1bxid64Mup7aczewSAYMX&t=1741362568562",
            brandColorHex: "#000000",
            listURL: "https://mdblist.com/lists/dualipafan01/netflix",
            trendingListURL: "https://mdblist.com/lists/dualipafan01/netflix-trending"
        ),
        StreamingServiceOption(
            id: "disney-plus",
            name: "Disney+",
            logoURL: "https://cdn.brandfetch.io/idhQlYRiX2/w/800/h/434/theme/light/logo.png?c=1bxid64Mup7aczewSAYMX&t=1769147818509",
            brandColorHex: "#084F60",
            listURL: "https://mdblist.com/lists/dualipafan01/disney",
            trendingListURL: "https://mdblist.com/lists/dualipafan01/disney-trending"
        ),
        StreamingServiceOption(
            id: "cartoon-network",
            name: "Cartoon Network",
            logoURL: "https://cdn.brandfetch.io/idFmMXJiW_/w/820/h/491/theme/dark/logo.png?c=1bxid64Mup7aczewSAYMX&t=1727089154071",
            brandColorHex: "#030327",
            listURL: "https://mdblist.com/lists/dualipafan01/cartoon-network"
        )
    ]

    let productionLanguageOptions: [(code: String, name: String)] = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("pt", "Portuguese"),
        ("zh", "Chinese"),
        ("hi", "Hindi"),
        ("it", "Italian")
    ]

    let productionRegionOptions: [(code: String, name: String)] = [
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
        ("NG", "Nigeria")
    ]

    private var streamingBaseResults: [MediaItem] = []
    private var activeSearchQuery = ""

    private struct NaturalLanguageIntent {
        enum ExplicitContentType {
            case movie
            case tv
        }
        
        enum PersonCreditMode {
            case cast
            case crew
            case any
        }

        var explicitContentType: ExplicitContentType?
        var genreId: Int?
        var personName: String?
        var personCreditMode: PersonCreditMode = .cast
        var companyNames: [String] = []
        var providerNames: [String] = []
        var releasedOnly: Bool = false
        var year: Int?
    }
    
    var hasMorePages: Bool {
        currentPage < totalPages
    }
    
    /// True when the People filter is active
    var isPeopleSearch: Bool {
        selectedType == .person
    }

    var isStreamingMode: Bool {
        !selectedStreamingServiceIds.isEmpty
    }

    var selectedProductionLanguageName: String? {
        guard let selectedProductionLanguage else { return nil }
        return productionLanguageOptions.first(where: { $0.code == selectedProductionLanguage })?.name
    }

    var selectedProductionRegionName: String? {
        guard let selectedProductionRegion else { return nil }
        return productionRegionOptions.first(where: { $0.code == selectedProductionRegion })?.name
    }

    var selectedStreamingServiceNames: [String] {
        streamingServices
            .filter { selectedStreamingServiceIds.contains($0.id) }
            .map { $0.name }
    }
    
    /// True when there are no results at all (media + people)
    var isEmptyResults: Bool {
        results.isEmpty && personResults.isEmpty
    }
    
    func loadGenres() async {
        do {
            let movieGenres = try await TMDBService.shared.getMovieGenres()
            let tvGenres = try await TMDBService.shared.getTVGenres()
            
            // Merge and dedupe
            var allGenres = movieGenres.genres
            for genre in tvGenres.genres {
                if !allGenres.contains(where: { $0.id == genre.id }) {
                    allGenres.append(genre)
                }
            }
            genres = allGenres.sorted { $0.name < $1.name }
        } catch {
            print("Error loading genres: \(error)")
        }
    }
    
    func search(useNaturalLanguage: Bool = false) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            personResults = []
            scoutOverviewItem = nil
            hasSearched = false
            activeSearchQuery = ""
            usedNaturalLanguageInLastSearch = false
            return
        }

        selectedStreamingServiceIds.removeAll()
        streamingBaseResults = []

        isLoading = true
        hasSearched = true
        currentPage = 1
        personResults = []
        activeSearchQuery = trimmedQuery
        
        do {
            if selectedType == .person {
                usedNaturalLanguageInLastSearch = false
                // Dedicated person search
                let response = try await TMDBService.shared.searchPerson(query: activeSearchQuery)
                totalPages = response.totalPages ?? 1
                personResults = response.results
                results = []
                scoutOverviewItem = nil
            } else if selectedGenre != nil || selectedYear != nil || selectedProductionLanguage != nil || selectedProductionRegion != nil {
                usedNaturalLanguageInLastSearch = false
                // Use discover endpoint for filters
                await searchWithFilters()
            } else {
                let shouldUseNaturalLanguage = useNaturalLanguage && StorageService.shared.settings.useAppleIntelligenceSearch
                usedNaturalLanguageInLastSearch = shouldUseNaturalLanguage

                if shouldUseNaturalLanguage, try await performStructuredNaturalLanguageSearch(for: trimmedQuery) {
                    isLoading = false
                    return
                }

                let queriesToTry: [String]
                if shouldUseNaturalLanguage {
                    queriesToTry = await AppleIntelligenceSearchService.shared.candidateQueries(for: trimmedQuery)
                } else {
                    queriesToTry = [trimmedQuery]
                }

                var processedAtLeastOneQuery = false
                for queryCandidate in queriesToTry {
                    let response = try await TMDBService.shared.searchMulti(query: queryCandidate)
                    let filteredResults = filterResults(response.results)
                    activeSearchQuery = queryCandidate
                    totalPages = response.totalPages ?? 1
                    processedAtLeastOneQuery = true

                    if !filteredResults.isEmpty || queryCandidate == queriesToTry.last {
                        results = filteredResults
                        break
                    }
                }

                if !processedAtLeastOneQuery {
                    results = []
                    totalPages = 1
                }
            }

            await refreshScoutOverview(for: trimmedQuery)
        } catch {
            print("Search error: \(error)")
            results = []
            personResults = []
            scoutOverviewItem = nil
        }
        
        isLoading = false
    }
    
    func loadMore() async {
        if isStreamingMode { return }
        if activeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        guard hasMorePages && !isLoadingMore else { return }
        
        isLoadingMore = true
        currentPage += 1
        
        do {
            if selectedType == .person {
                let response = try await TMDBService.shared.searchPerson(query: activeSearchQuery, page: currentPage)
                personResults.append(contentsOf: response.results)
            } else if selectedGenre != nil || selectedYear != nil || selectedProductionLanguage != nil || selectedProductionRegion != nil {
                let genreIds = selectedGenre != nil ? [selectedGenre!.id] : nil
                if selectedType == .tv {
                    let response = try await TMDBService.shared.discoverTV(
                        genres: genreIds,
                        year: selectedYear,
                        originalLanguage: selectedProductionLanguage,
                        productionRegion: selectedProductionRegion,
                        page: currentPage
                    )
                    results.append(contentsOf: filterResults(response.results))
                } else {
                    let response = try await TMDBService.shared.discoverMovies(
                        genres: genreIds,
                        year: selectedYear,
                        originalLanguage: selectedProductionLanguage,
                        productionRegion: selectedProductionRegion,
                        page: currentPage
                    )
                    results.append(contentsOf: filterResults(response.results))
                }
            } else {
                let response = try await TMDBService.shared.searchMulti(query: activeSearchQuery, page: currentPage)
                results.append(contentsOf: filterResults(response.results))
            }
        } catch {
            print("Load more error: \(error)")
            currentPage -= 1
        }
        
        isLoadingMore = false
    }
    
    private func searchWithFilters() async {
        do {
            let genreIds = selectedGenre != nil ? [selectedGenre!.id] : nil
            
            if selectedType == .movie || selectedType == nil {
                let movies = try await TMDBService.shared.discoverMovies(
                    genres: genreIds,
                    year: selectedYear,
                    originalLanguage: selectedProductionLanguage,
                    productionRegion: selectedProductionRegion
                )
                results = movies.results
                totalPages = movies.totalPages ?? 1
            }
            
            if selectedType == .tv {
                let shows = try await TMDBService.shared.discoverTV(
                    genres: genreIds,
                    year: selectedYear,
                    originalLanguage: selectedProductionLanguage,
                    productionRegion: selectedProductionRegion
                )
                results = shows.results
                totalPages = shows.totalPages ?? 1
            }
        } catch {
            print("Filter search error: \(error)")
        }
    }

    private func performStructuredNaturalLanguageSearch(for query: String) async throws -> Bool {
        let intent = parseNaturalLanguageIntent(from: query)
        let explicitMovieIntent = intent.explicitContentType == .movie
        let explicitTVIntent = intent.explicitContentType == .tv
        let requestedMovies = explicitMovieIntent || (intent.explicitContentType == nil && selectedType != .tv)
        let requestedTV = explicitTVIntent || (intent.explicitContentType == nil && selectedType != .movie)
        let applySelectedTypeFilter = intent.explicitContentType == nil

        if let personName = intent.personName, (requestedMovies || requestedTV) {
            let personResponse = try await TMDBService.shared.searchPerson(query: personName)
            if let person = personResponse.results.first {
                var personMedia: [MediaItem] = []
                
                if requestedMovies {
                    let movieCredits = try await TMDBService.shared.getPersonMovieCredits(id: person.id)
                    switch intent.personCreditMode {
                    case .cast:
                        personMedia.append(contentsOf: movieCredits.cast ?? [])
                    case .crew:
                        personMedia.append(contentsOf: movieCredits.crew ?? [])
                    case .any:
                        personMedia.append(contentsOf: movieCredits.cast ?? [])
                        personMedia.append(contentsOf: movieCredits.crew ?? [])
                    }
                }
                
                if requestedTV {
                    let tvCredits = try await TMDBService.shared.getPersonTVCredits(id: person.id)
                    switch intent.personCreditMode {
                    case .cast:
                        personMedia.append(contentsOf: tvCredits.cast ?? [])
                    case .crew:
                        personMedia.append(contentsOf: tvCredits.crew ?? [])
                    case .any:
                        personMedia.append(contentsOf: tvCredits.cast ?? [])
                        personMedia.append(contentsOf: tvCredits.crew ?? [])
                    }
                }

                if let genreId = intent.genreId {
                    personMedia = personMedia.filter { item in
                        guard let genreIds = item.genreIds, !genreIds.isEmpty else { return true }
                        return genreIds.contains(genreId)
                    }
                }

                if let year = intent.year {
                    personMedia = personMedia.filter { item in
                        guard let displayDate = item.displayDate, displayDate.count >= 4 else { return true }
                        return String(displayDate.prefix(4)) == String(year)
                    }
                }
                
                if intent.releasedOnly {
                    personMedia = filterReleasedItems(personMedia)
                }

                personMedia = dedupeMediaItems(personMedia).sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
                let filtered = filterResults(personMedia, applyingSelectedType: applySelectedTypeFilter)
                if !filtered.isEmpty {
                    results = filtered
                    personResults = []
                    currentPage = 1
                    totalPages = 1
                    activeSearchQuery = query
                    return true
                }
            }
        }

        if !intent.providerNames.isEmpty, (requestedMovies || requestedTV) {
            let providerIds = resolveProviderIDs(for: intent.providerNames)
            if !providerIds.isEmpty {
                let region = effectiveProviderRegion(for: intent.providerNames)
                var combinedResults: [MediaItem] = []
                var mergedTotalPages = 1

                if requestedMovies {
                    let movieResponse = try await TMDBService.shared.discoverMoviesWithProvider(
                        providerIds: providerIds,
                        region: region
                    )
                    combinedResults.append(contentsOf: movieResponse.results)
                    mergedTotalPages = max(mergedTotalPages, movieResponse.totalPages ?? 1)
                }

                if requestedTV {
                    let tvResponse = try await TMDBService.shared.discoverTVWithProvider(
                        providerIds: providerIds,
                        region: region
                    )
                    combinedResults.append(contentsOf: tvResponse.results)
                    mergedTotalPages = max(mergedTotalPages, tvResponse.totalPages ?? 1)
                }

                var providerMedia = dedupeMediaItems(combinedResults)

                if intent.releasedOnly {
                    providerMedia = filterReleasedItems(providerMedia)
                }

                if let genreId = intent.genreId {
                    providerMedia = providerMedia.filter { item in
                        guard let genreIds = item.genreIds, !genreIds.isEmpty else { return true }
                        return genreIds.contains(genreId)
                    }
                }

                if let year = intent.year {
                    providerMedia = providerMedia.filter { item in
                        guard let displayDate = item.displayDate, displayDate.count >= 4 else { return true }
                        return String(displayDate.prefix(4)) == String(year)
                    }
                }

                providerMedia.sort { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
                let filtered = filterResults(providerMedia, applyingSelectedType: applySelectedTypeFilter)
                if !filtered.isEmpty {
                    results = filtered
                    personResults = []
                    currentPage = 1
                    totalPages = mergedTotalPages
                    activeSearchQuery = query
                    return true
                }
            }
        }

        if !intent.companyNames.isEmpty, (requestedMovies || requestedTV) {
            var companyIds: Set<Int> = []
            for companyName in intent.companyNames {
                let ids = try await resolveCompanyIDs(for: companyName, wantsTV: requestedTV && !requestedMovies)
                companyIds.formUnion(ids)
            }

            guard !companyIds.isEmpty else { return false }
            var combinedResults: [MediaItem] = []
            var mergedTotalPages = 1

            if requestedMovies {
                let movieResponse = try await TMDBService.shared.discoverMoviesByCompany(companyIds: Array(companyIds))
                combinedResults.append(contentsOf: movieResponse.results)
                mergedTotalPages = max(mergedTotalPages, movieResponse.totalPages ?? 1)
            }

            if requestedTV {
                let tvResponse = try await TMDBService.shared.discoverTVByCompany(companyIds: Array(companyIds))
                combinedResults.append(contentsOf: tvResponse.results)
                mergedTotalPages = max(mergedTotalPages, tvResponse.totalPages ?? 1)
            }

            var companyMedia = dedupeMediaItems(combinedResults)

            if intent.releasedOnly {
                companyMedia = filterReleasedItems(companyMedia)
            }

            if let genreId = intent.genreId {
                companyMedia = companyMedia.filter { item in
                    guard let genreIds = item.genreIds, !genreIds.isEmpty else { return true }
                    return genreIds.contains(genreId)
                }
            }

            if let year = intent.year {
                companyMedia = companyMedia.filter { item in
                    guard let displayDate = item.displayDate, displayDate.count >= 4 else { return true }
                    return String(displayDate.prefix(4)) == String(year)
                }
            }

            companyMedia.sort { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            let filtered = filterResults(companyMedia, applyingSelectedType: applySelectedTypeFilter)
            guard !filtered.isEmpty else { return false }

            results = filtered
            personResults = []
            currentPage = 1
            totalPages = mergedTotalPages
            activeSearchQuery = query
            return true
        }

        if let genreId = intent.genreId, requestedMovies, intent.personName == nil {
            let response = try await TMDBService.shared.discoverMovies(genres: [genreId], year: intent.year)
            let filtered = filterResults(response.results, applyingSelectedType: applySelectedTypeFilter)
            guard !filtered.isEmpty else { return false }

            results = filtered
            personResults = []
            currentPage = 1
            totalPages = response.totalPages ?? 1
            activeSearchQuery = query
            return true
        }

        return false
    }

    private func parseNaturalLanguageIntent(from query: String) -> NaturalLanguageIntent {
        let normalized = normalizeIntentText(query)
        var intent = NaturalLanguageIntent()

        let releasedPhrases = [
            "released", "already released", "already out", "out now",
            "have been out", "that are out", "came out", "have come out",
            "exclude upcoming", "no upcoming", "not upcoming"
        ]
        intent.releasedOnly = releasedPhrases.contains { containsPhrase(normalized, phrase: $0) }

        let moviePhrases = ["movie", "movies", "film", "films", "cinema"]
        let tvPhrases = ["tv", "show", "shows", "series", "episodes", "episode"]
        if moviePhrases.contains(where: { containsPhrase(normalized, phrase: $0) }) {
            intent.explicitContentType = .movie
        } else if tvPhrases.contains(where: { containsPhrase(normalized, phrase: $0) }) {
            intent.explicitContentType = .tv
        }

        let genreMap: [(phrases: [String], genreId: Int)] = [
            (["action", "fight"], 28),
            (["adventure"], 12),
            (["animation", "animated"], 16),
            (["comedy", "funny"], 35),
            (["crime", "gangster"], 80),
            (["documentary", "doc"], 99),
            (["drama"], 18),
            (["family", "kids"], 10751),
            (["fantasy"], 14),
            (["history", "historical"], 36),
            (["horror", "scary"], 27),
            (["music", "musical"], 10402),
            (["mystery"], 9648),
            (["romance", "romantic"], 10749),
            (["science fiction", "sci fi", "scifi"], 878),
            (["thriller"], 53),
            (["war"], 10752),
            (["western"], 37)
        ]

        for entry in genreMap {
            if entry.phrases.contains(where: { containsPhrase(normalized, phrase: $0) }) {
                let genreId = entry.genreId
                intent.genreId = genreId
                break
            }
        }

        if let yearMatch = normalized.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
            intent.year = Int(normalized[yearMatch])
        }

        let starringPerson = extractEntity(
            in: normalized,
            triggers: ["starring", "featuring", "with actor", "with actress", "with", "acted by"],
            stoppers: [" but ", " and ", " that ", " which ", " who ", " where ", " produced by ", " made by ", " from ", " by ", " released ", " movie ", " movies ", " tv ", " show ", " series "]
        ) ?? extractEntityUsingPatterns(
            in: normalized,
            patterns: [
                #"(?:movies|movie|films|film|shows|show|series|tv shows|tv)\s+(?:starring|featuring|with|acted by)\s+([a-z0-9&\-\.' ]{2,80})"#,
                #"(?:starring|featuring|with|acted by)\s+([a-z0-9&\-\.' ]{2,80})\s+(?:movies|movie|films|film|shows|show|series|tv shows|tv)"#,
                #"(?:cast featuring|cast with)\s+([a-z0-9&\-\.' ]{2,80})"#
            ]
        )
        let crewPerson = extractEntity(
            in: normalized,
            triggers: ["directed by", "director", "directed", "produced by", "producer", "produced"],
            stoppers: [" but ", " and ", " that ", " which ", " who ", " where ", " starring ", " featuring ", " with ", " actor ", " actress ", " released ", " movie ", " movies ", " tv ", " show ", " series ", " studios ", " studio "]
        ) ?? extractEntityUsingPatterns(
            in: normalized,
            patterns: [
                #"(?:movies|movie|films|film|shows|show|series|tv shows|tv)\s+(?:directed by|directed|from director|by director)\s+([a-z0-9&\-\.' ]{2,80})"#,
                #"(?:movies|movie|films|film|shows|show|series|tv shows|tv)\s+(?:produced by|produced|from producer|by producer)\s+([a-z0-9&\-\.' ]{2,80})"#,
                #"(?:directed by|directed|from director|by director)\s+([a-z0-9&\-\.' ]{2,80})\s+(?:movies|movie|films|film|shows|show|series|tv shows|tv)"#,
                #"(?:produced by|produced|from producer|by producer)\s+([a-z0-9&\-\.' ]{2,80})\s+(?:movies|movie|films|film|shows|show|series|tv shows|tv)"#
            ]
        )
        
        if let starringPerson {
            intent.personName = starringPerson
            if containsPhrase(normalized, phrase: "director") || containsPhrase(normalized, phrase: "producer") {
                intent.personCreditMode = .any
            } else {
                intent.personCreditMode = .cast
            }
        } else if let crewPerson {
            intent.personName = crewPerson
            intent.personCreditMode = .crew
        }

        let companyPhrase = extractEntity(
            in: normalized,
            triggers: ["produced by", "production by", "made by", "studio", "studios", "from", "by"],
            stoppers: [" but ", " that ", " which ", " who ", " where ", " starring ", " featuring ", " with ", " actor ", " actress ", " directed by ", " director ", " producer ", " released ", " movie ", " movies ", " tv ", " show ", " series "]
        ) ?? extractEntityUsingPatterns(
            in: normalized,
            patterns: [
                #"(?:movies|movie|films|film|shows|show|series|tv shows|tv)\s+(?:made by|from studio|from studios|studio|studios|produced by|production by|distributed by)\s+([a-z0-9&\-\.' ]{2,80})"#,
                #"(?:made by|from studio|from studios|studio|studios|produced by|production by|distributed by)\s+([a-z0-9&\-\.' ]{2,80})\s+(?:movies|movie|films|film|shows|show|series|tv shows|tv)"#,
                #"(?:made for)\s+([a-z0-9&\-\+.' ]{2,80})"#
            ]
        )
        if let companyPhrase, intent.personName == nil || looksLikeCompanyPhrase(companyPhrase) {
            intent.companyNames = parseCompanyNames(from: companyPhrase)
        }

        intent.providerNames = extractProviderNames(from: normalized)

        return intent
    }

    private func normalizeIntentText(_ text: String) -> String {
        var normalized = text.lowercased()
        let replacements = [",", ".", "?", "!", ":", ";", "(", ")", "\"", "'"]
        for token in replacements {
            normalized = normalized.replacingOccurrences(of: token, with: " ")
        }
        while normalized.contains("  ") {
            normalized = normalized.replacingOccurrences(of: "  ", with: " ")
        }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsPhrase(_ text: String, phrase: String) -> Bool {
        let paddedText = " \(text) "
        let paddedPhrase = " \(phrase) "
        return paddedText.contains(paddedPhrase)
    }

    private func extractEntity(in normalized: String, triggers: [String], stoppers: [String]) -> String? {
        let orderedTriggers = triggers.sorted { $0.count > $1.count }
        for trigger in orderedTriggers {
            let pattern = "\(trigger) "
            guard let range = normalized.range(of: pattern) else { continue }

            var candidate = String(normalized[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            for stopper in stoppers {
                if let stopRange = candidate.range(of: stopper) {
                    candidate = String(candidate[..<stopRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if candidate.hasPrefix("the ") {
                candidate = String(candidate.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if candidate.hasSuffix(" studio") {
                candidate += "s"
            }
            if candidate.hasSuffix(" studioss") {
                candidate = candidate.replacingOccurrences(of: " studioss", with: " studios")
            }

            let words = candidate.split(separator: " ")
            if !candidate.isEmpty && words.count <= 6 {
                return candidate
            }
        }
        return nil
    }
    
    private func extractEntityUsingPatterns(in normalized: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            guard let match = regex.firstMatch(in: normalized, options: [], range: range) else { continue }
            guard match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: normalized) else { continue }
            let candidate = normalized[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = cleanupEntityCandidate(candidate)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }
    
    private func cleanupEntityCandidate(_ candidate: String) -> String {
        var cleaned = candidate
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("the ") {
            cleaned = String(cleaned.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.hasSuffix(" studio") {
            cleaned += "s"
        }
        if cleaned.hasSuffix(" studioss") {
            cleaned = cleaned.replacingOccurrences(of: " studioss", with: " studios")
        }
        let words = cleaned.split(separator: " ")
        if words.isEmpty || words.count > 8 { return "" }
        return cleaned
    }
    
    private func looksLikeCompanyPhrase(_ phrase: String) -> Bool {
        let normalized = phrase.lowercased()
        let companyTokens = [
            "studio", "studios", "pictures", "productions", "entertainment",
            "media", "films", "network", "animation", "plus", "tv"
        ]
        return companyTokens.contains { normalized.contains($0) }
    }

    private func parseCompanyNames(from phrase: String) -> [String] {
        var normalized = phrase
            .replacingOccurrences(of: " and ", with: "|")
            .replacingOccurrences(of: " & ", with: "|")
            .replacingOccurrences(of: ",", with: "|")
            .replacingOccurrences(of: " plus ", with: "|")
            .replacingOccurrences(of: " or ", with: "|")

        while normalized.contains("||") {
            normalized = normalized.replacingOccurrences(of: "||", with: "|")
        }

        let names = normalized
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { canonicalCompanyName($0) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        var deduped: [String] = []
        for name in names {
            if seen.contains(name) { continue }
            seen.insert(name)
            deduped.append(name)
        }
        return deduped
    }

    private func canonicalCompanyName(_ name: String) -> String {
        let lowered = name.lowercased()
        if lowered == "universal" {
            return "universal pictures"
        }
        return name
    }

    private func resolveCompanyIDs(for companyName: String, wantsTV: Bool) async throws -> [Int] {
        let appHubIds = resolveCompanyIDsFromAppHubs(for: companyName)
        if !appHubIds.isEmpty {
            return appHubIds
        }

        let response = try await TMDBService.shared.searchCompanies(query: companyName)
        guard !response.results.isEmpty else { return [] }

        let normalizedQuery = companyName.lowercased()
        let scored = response.results
            .map { company in
                (id: company.id, score: companyScore(name: company.name, query: normalizedQuery, wantsTV: wantsTV))
            }
            .sorted { $0.score > $1.score }

        let positive = scored.filter { $0.score > 0 }.map(\.id)
        if normalizedQuery.contains("marvel") {
            return Array(positive.prefix(6))
        }

        if let first = positive.first {
            return [first]
        }
        return [response.results[0].id]
    }

    private func resolveCompanyIDsFromAppHubs(for companyName: String) -> [Int] {
        let normalizedName = normalizeIntentText(companyName)
        let tokens = normalizedName.split(separator: " ").map(String.init)
        let hubs = StorageService.shared.companyHubs

        var matched: [Int] = []
        for hub in hubs {
            let hubName = normalizeIntentText(hub.name)
            if hubName == normalizedName || hubName.contains(normalizedName) || normalizedName.contains(hubName) {
                matched.append(contentsOf: hub.companyIds)
                continue
            }

            if !tokens.isEmpty && tokens.allSatisfy({ hubName.contains($0) }) {
                matched.append(contentsOf: hub.companyIds)
            }
        }

        return Array(Set(matched))
    }

    private func extractProviderNames(from normalized: String) -> [String] {
        let hubs = StorageService.shared.networkHubs
        guard !hubs.isEmpty else { return [] }

        var matches: [String] = []
        for hub in hubs {
            let aliases = providerAliases(for: hub.name)
            if aliases.contains(where: { containsPhrase(normalized, phrase: $0) }) {
                matches.append(hub.name)
            }
        }

        var seen: Set<String> = []
        var deduped: [String] = []
        for name in matches {
            if seen.contains(name) { continue }
            seen.insert(name)
            deduped.append(name)
        }
        return deduped
    }

    private func providerAliases(for providerName: String) -> [String] {
        let normalized = normalizeIntentText(providerName)
        switch normalized {
        case "disney+":
            return ["disney+", "disney plus", "disneyplus", "d+"]
        case "netflix":
            return ["netflix", "net flix"]
        case "max":
            return ["max", "hbo max", "hbomax"]
        case "paramount+":
            return ["paramount+", "paramount plus", "paramountplus"]
        case "apple tv+", "apple tv":
            return ["apple tv+", "apple tv plus", "appletv+", "appletv plus", "appletv"]
        case "amazon prime video":
            return ["amazon prime", "prime video", "prime"]
        default:
            return [normalized]
        }
    }

    private func resolveProviderIDs(for providerNames: [String]) -> [Int] {
        let hubs = StorageService.shared.networkHubs
        var ids: [Int] = []
        for name in providerNames {
            if let hub = hubs.first(where: { normalizeIntentText($0.name) == normalizeIntentText(name) }) {
                ids.append(contentsOf: hub.providerIds)
            }
        }
        return Array(Set(ids))
    }

    private func effectiveProviderRegion(for providerNames: [String]) -> String {
        // Disney+ ZA→GB mapping is handled centrally in TMDBService.effectiveProviderRegion
        return StorageService.shared.settings.region
    }

    private func companyScore(name: String, query: String, wantsTV: Bool) -> Int {
        let normalizedName = name.lowercased()
        var score = 0

        if normalizedName == query { score += 100 }
        if normalizedName.contains(query) { score += 60 }

        let queryTokens = query.split(separator: " ").map(String.init)
        for token in queryTokens where token.count > 1 {
            if normalizedName.contains(token) {
                score += 10
            }
        }

        if wantsTV {
            if normalizedName.contains("television") || normalizedName.contains("tv") || normalizedName.contains("animation") {
                score += 20
            }
        } else {
            if normalizedName.contains("studios") || normalizedName.contains("pictures") || normalizedName.contains("films") {
                score += 10
            }
        }

        if query.contains("marvel") && normalizedName.contains("marvel") {
            score += 50
        }

        return score
    }

    private func dedupeMediaItems(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<Int>()
        return items.filter { item in
            guard !seen.contains(item.id) else { return false }
            seen.insert(item.id)
            return true
        }
    }

    private func filterReleasedItems(_ items: [MediaItem]) -> [MediaItem] {
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)

        return items.filter { item in
            guard let releaseDate = item.releaseDate, releaseDate.count >= 10 else { return false }
            return releaseDate <= todayString
        }
    }
    
    private func filterResults(_ items: [MediaItem], applyingSelectedType: Bool = true) -> [MediaItem] {
        var filtered = items
        
        if applyingSelectedType, let type = selectedType {
            filtered = filtered.filter { $0.resolvedMediaType == type }
        }

        if let selectedProductionLanguage, !selectedProductionLanguage.isEmpty {
            filtered = filtered.filter { item in
                item.originalLanguage == selectedProductionLanguage
            }
        }
        
        // Kids profile: filter to only show family-friendly content
        if StorageService.shared.settings.isKidsProfile {
            // Kids-friendly genre IDs:
            // Movies: Animation=16, Family=10751
            // TV: Animation=16, Family=10751, Kids=10762
            let kidsGenreIds: Set<Int> = [16, 10751, 10762]
            filtered = filtered.filter { item in
                // Exclude adult-flagged content
                if item.adult == true { return false }
                // Exclude people results for kids
                if item.resolvedMediaType == .person { return false }
                // If genre info is available, require at least one kids genre
                if let genres = item.genreIds, !genres.isEmpty {
                    return !genres.filter({ kidsGenreIds.contains($0) }).isEmpty
                }
                // If no genre info, allow it through (better than hiding everything)
                return true
            }
        }
        
        return filtered
    }

    func toggleStreamingService(_ service: StreamingServiceOption) async {
        if selectedStreamingServiceIds.contains(service.id) {
            selectedStreamingServiceIds.remove(service.id)
        } else {
            selectedStreamingServiceIds.insert(service.id)
        }
        await loadStreamingRecommendations()
    }

    func applyStreamingFilters() {
        guard isStreamingMode else { return }
        results = filterResults(streamingBaseResults)
    }

    private func loadStreamingRecommendations() async {
        if selectedStreamingServiceIds.isEmpty {
            streamingBaseResults = []
            results = []
            personResults = []
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasSearched = false
            }
            return
        }

        query = ""
        selectedGenre = nil
        selectedYear = nil
        selectedProductionLanguage = nil
        selectedProductionRegion = nil
        selectedType = nil

        isLoading = true
        hasSearched = true
        currentPage = 1
        totalPages = 1
        personResults = []

        let listInputs = streamingServices
            .filter { selectedStreamingServiceIds.contains($0.id) }
            .map { $0.listURL }

        do {
            let savedItems = try await MDBListService.shared.fetchMultipleListsAsSavedMedia(
                inputs: listInputs,
                perListLimit: 20,
                totalLimit: 10,
                preferTMDBDetails: true
            )
            streamingBaseResults = savedItems.map { $0.toMediaItem() }
            results = filterResults(streamingBaseResults)
        } catch {
            print("Streaming recommendations error: \(error)")
            streamingBaseResults = []
            results = []
        }

        isLoading = false
    }
    
    func clearSearch() {
        query = ""
        results = []
        personResults = []
        scoutOverviewItem = nil
        hasSearched = false
        usedNaturalLanguageInLastSearch = false
        activeSearchQuery = ""
        selectedStreamingServiceIds.removeAll()
        streamingBaseResults = []
    }

    private func refreshScoutOverview(for query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, selectedType != .person else {
            scoutOverviewItem = nil
            isLoadingScoutOverview = false
            return
        }

        if let exactResult = bestScoutOverviewMatch(for: trimmedQuery) {
            scoutOverviewItem = exactResult
            isLoadingScoutOverview = false
            return
        }

        isLoadingScoutOverview = true
        defer { isLoadingScoutOverview = false }

        let preferredType: MediaType?
        switch selectedType {
        case .movie, .tv:
            preferredType = selectedType
        default:
            preferredType = nil
        }

        scoutOverviewItem = await ScoutAgentService.shared.resolveMediaItem(
            for: trimmedQuery,
            preferredType: preferredType
        )
    }

    private func bestScoutOverviewMatch(for query: String) -> MediaItem? {
        let normalizedQuery = normalizedScoutSearchTitle(query)
        if let exactMatch = results.first(where: {
            normalizedScoutSearchTitle($0.displayTitle) == normalizedQuery
        }) {
            return exactMatch
        }
        return results.first
    }

    private func normalizedScoutSearchTitle(_ title: String) -> String {
        title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }
}

// MARK: - Person Search Card
struct PersonSearchCard: View {
    let person: Person
    @State private var isPressed = false
    @Environment(\.isFocused) private var isFocused

    #if os(tvOS)
    private let profileSize: CGFloat = 160
    private let labelWidth: CGFloat = 180
    #else
    private let profileSize: CGFloat = 90
    private let labelWidth: CGFloat = 100
    #endif

    var body: some View {
        VStack(spacing: tvOSSizing(tv: 14, mobile: 10)) {
            ProfileImageView(profilePath: person.profilePath, size: profileSize)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            
            VStack(spacing: tvOSSizing(tv: 6, mobile: 3)) {
                Text(person.name)
                    #if os(tvOS)
                    .font(.callout)
                    #else
                    .font(.caption)
                    #endif
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                if let dept = person.knownForDepartment, !dept.isEmpty {
                    Text(dept)
                        #if os(tvOS)
                        .font(.caption)
                        #else
                        .font(.caption2)
                        #endif
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Show top known-for title
                if let knownFor = person.knownFor?.first, let title = knownFor.displayTitle as String? {
                    Text(title)
                        #if os(tvOS)
                        .font(.caption)
                        #else
                        .font(.caption2)
                        #endif
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .italic()
                }
            }
            .frame(width: labelWidth)
        }
        .padding(.vertical, tvOSSizing(tv: 16, mobile: 8))
        #if os(tvOS)
        .padding(.horizontal, 12)
        #endif
        .overlay {
            RoundedRectangle(cornerRadius: tvOSSizing(tv: 24, mobile: 18), style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 0.75)
        }
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    private func tvOSSizing(tv: CGFloat, mobile: CGFloat) -> CGFloat {
        #if os(tvOS)
        return tv
        #else
        return mobile
        #endif
    }
}

struct SearchSuggestionChip: View {
    let title: String
    let systemImage: String
    var iconColor: Color = .secondary

    var body: some View {
        HStack(spacing: chipSpacing) {
            Image(systemName: systemImage)
                .font(iconFont)
                .foregroundColor(iconColor)
            Text(title)
                .font(titleFont)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, horizontalPad)
        .padding(.vertical, verticalPad)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    #if os(tvOS)
    private var chipSpacing: CGFloat { 10 }
    private var iconFont: Font { .body }
    private var titleFont: Font { .body }
    private var horizontalPad: CGFloat { 24 }
    private var verticalPad: CGFloat { 14 }
    #else
    private var chipSpacing: CGFloat { 6 }
    private var iconFont: Font { .caption }
    private var titleFont: Font { .subheadline }
    private var horizontalPad: CGFloat { 12 }
    private var verticalPad: CGFloat { 8 }
    #endif
}

struct SearchActionButtonLabel: View {
    let title: String

    var body: some View {
        Text(title)
            #if os(tvOS)
            .font(.body)
            #else
            .font(.subheadline)
            #endif
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            #if os(tvOS)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            #else
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            #endif
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }
}

// MARK: - Network Trending Popup
struct NetworkTrendingPopup: View {
    let service: StreamingServiceOption
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var trendingMovies: [MediaItem] = []
    @State private var trendingShows: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var detailItem: MediaItem?
    
    private var brandColor: Color {
        Color(hex: service.brandColorHex)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading trending...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if let error {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.orange)
                        Text("Couldn't load trending")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                } else {
                    trendingContent
                }
            }
            .inlineNavTitleIfSupported()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .mediaDetailPresentation(item: $detailItem)
        }
        .presentationDetents([.large])
        .task {
            await loadTrending()
        }
    }
    
    private var trendingContent: some View {
        VStack(spacing: 0) {
            // Service header
            serviceHeader
                .padding(.top, 4)
                .padding(.bottom, 12)
            
            // Two columns: Movies and TV Shows
            if trendingMovies.isEmpty && trendingShows.isEmpty {
                Spacer()
                Text("No trending content found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 16) {
                    // Movies column
                    trendingColumn(
                        title: "Movies",
                        icon: "film.fill",
                        items: trendingMovies
                    )
                    
                    // Divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 1)
                        .padding(.vertical, 4)
                    
                    // TV Shows column
                    trendingColumn(
                        title: "TV Shows",
                        icon: "tv.fill",
                        items: trendingShows
                    )
                }
                .padding(.horizontal)
                
                Spacer(minLength: 16)
            }
        }
    }
    
    private var serviceHeader: some View {
        VStack(spacing: 8) {
            // Logo
            ResilientAsyncImage(url: URL(string: service.logoURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 24)
                default:
                    Text(service.name)
                        .font(.title3)
                        .fontWeight(.bold)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(brandColor)
            )
            
            Text("Trending Now")
                .font(.headline)
                .foregroundColor(.primary)
        }
    }
    
    private func trendingColumn(title: String, icon: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Column header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(.bottom, 2)
            
            if items.isEmpty {
                Text("None found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    FocusableActionSurface(action: {
                        detailItem = item
                    }, outlineShape: .roundedRectangle(cornerRadius: 16)) {
                        TrendingItemRow(item: item, rank: index + 1, brandColor: brandColor)
                    }
                    
                    if index < items.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func loadTrending() async {
        guard let listURL = service.trendingListURL else {
            error = "No trending list configured."
            isLoading = false
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            let items = try await MDBListService.shared.fetchListItemsAsSavedMedia(
                listId: listURL,
                limit: 20
            )
            
            let movies = items
                .filter { $0.mediaType == .movie }
                .prefix(5)
                .map { $0.toMediaItem() }
            
            let shows = items
                .filter { $0.mediaType == .tv }
                .prefix(5)
                .map { $0.toMediaItem() }
            
            trendingMovies = Array(movies)
            trendingShows = Array(shows)
        } catch {
            self.error = "Failed to load trending content."
            print("Network trending popup error: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Trending Item Row
private struct TrendingItemRow: View {
    let item: MediaItem
    let rank: Int
    let brandColor: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            // Poster thumbnail
            ZStack(alignment: .topLeading) {
                PosterImageView(posterPath: item.posterPath, size: .small)
                    .frame(width: 36, height: 54)

                Text("\(rank)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(rank <= 3 ? brandColor : .primary)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.3), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.16), radius: 6, x: 0, y: 2)
                    .padding(4)
            }
            
            // Title and year
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if let year = item.year {
                    Text(year)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}


#Preview {
    SearchView(selectedItem: .constant(nil))
}

// MARK: - SavedMediaItem -> MediaItem conversion
extension SavedMediaItem {
    func toMediaItem() -> MediaItem {
        let mediaTypeString = self.mediaType.rawValue

        return MediaItem(
            id: self.mediaId,
            title: mediaTypeString == "movie" ? self.title : nil,
            name: mediaTypeString == "tv" ? self.title : nil,
            originalTitle: nil,
            originalName: nil,
            overview: self.overview,
            posterPath: self.posterPath,
            backdropPath: self.backdropPath,
            releaseDate: mediaTypeString == "movie" ? self.year : nil,
            firstAirDate: mediaTypeString == "tv" ? self.year : nil,
            voteAverage: self.voteAverage,
            voteCount: nil,
            popularity: nil,
            genreIds: nil,
            mediaType: mediaTypeString,
            adult: false,
            originalLanguage: nil
        )
    }
}
