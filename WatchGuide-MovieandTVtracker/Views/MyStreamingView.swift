//
//  MyStreamingView.swift
//  WatchGuide-MovieandTVtracker
//
//  A dedicated browse page that shows content only from the user's
//  selected streaming services.
//

import SwiftUI

// MARK: - Streaming Service Definition

struct StreamingService: Identifiable, Codable, Hashable {
    let id: Int               // TMDB provider ID
    let name: String
    let logoPath: String      // TMDB logo path (used with imageURL)

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: StreamingService, rhs: StreamingService) -> Bool {
        lhs.id == rhs.id
    }
}

extension StreamingService {
    /// A curated list of popular streaming services with their TMDB provider IDs.
    static let allServices: [StreamingService] = [
        StreamingService(id: 8,   name: "Netflix",       logoPath: "/pbpMk2JmcoNnQwB5JGpXAbmQpe.jpg"),
        StreamingService(id: 337, name: "Disney+",       logoPath: "/97yvRBw1GzX7fXprcF80er19ot.jpg"),
        StreamingService(id: 384, name: "Max",           logoPath: "/aS2zvJWn9mwiCOeaaCkIh4wleZS.jpg"),
        StreamingService(id: 15,  name: "Hulu",          logoPath: "/zxrVdFjIjLqkfnwyghnfywTn3Lh.jpg"),
        StreamingService(id: 531, name: "Paramount+",    logoPath: "/xbhHHa1YgtpwhC8lb1NQ3ACVcLd.jpg"),
        StreamingService(id: 386, name: "Peacock",       logoPath: "/xTHltMrZPAJFLQ6qyCBjAnXSmZt.jpg"),
        StreamingService(id: 350, name: "Apple TV",      logoPath: "/6uhKBfmtzFqOcLousHwZuzcrScK.jpg"),
        StreamingService(id: 283, name: "Crunchyroll",   logoPath: "/8Gt1iClBlzTeQs8WQm8UrCoIxnQ.jpg"),
        StreamingService(id: 73,  name: "Tubi",          logoPath: "/w2TDH9TRI7pltfahKF0ehQbi2eg.jpg"),
        StreamingService(id: 300, name: "Pluto TV",      logoPath: "/t6N57S17sdXRXmZDAkaGP0NHNG0.jpg"),
        StreamingService(id: 43,  name: "Starz",         logoPath: "/kJlVJLgbNPFKpLVFBjGBMUXnlMN.jpg"),
        StreamingService(id: 55,  name: "Showmax",       logoPath: "/6oCizsI14mPmmC1Uskpmh9EgKqf.jpg"),
        StreamingService(id: 11,  name: "MUBI",          logoPath: "/bVR4Z1LCHY7gidXAJF5pMa4QrDS.jpg"),
        StreamingService(id: 99,  name: "Shudder",       logoPath: "/dNAz0MMIPiqCD2axGUZsK2Q3C7L.jpg"),
        StreamingService(id: 151, name: "BritBox",       logoPath: "/kIbbhgfOhffl3GojH9bfLAHlu2F.jpg"),
    ]
}

// MARK: - ViewModel

@MainActor
final class MyStreamingViewModel: ObservableObject {
    @Published var selectedServiceIds: Set<Int> = [] {
        didSet { saveSelection() }
    }
    @Published var heroItems: [MediaItem] = []
    @Published var trendingMovies: [MediaItem] = []
    @Published var trendingTV: [MediaItem] = []
    @Published var popularMovies: [MediaItem] = []
    @Published var popularTV: [MediaItem] = []
    @Published var topRatedMovies: [MediaItem] = []
    @Published var topRatedTV: [MediaItem] = []
    @Published var isLoading = false
    @Published var hasLoaded = false

    init() {
        loadSelection()
    }

    var selectedServices: [StreamingService] {
        StreamingService.allServices.filter { selectedServiceIds.contains($0.id) }
    }

    var hasSelection: Bool {
        !selectedServiceIds.isEmpty
    }

    func toggle(_ service: StreamingService) {
        if selectedServiceIds.contains(service.id) {
            selectedServiceIds.remove(service.id)
        } else {
            selectedServiceIds.insert(service.id)
        }
        // Reset loaded state so content refreshes
        hasLoaded = false
    }

    func loadContent() async {
        guard hasSelection, !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    func refresh() async {
        guard hasSelection else {
            clearContent()
            return
        }

        isLoading = true
        let providerIds = Array(selectedServiceIds)
        let region = StorageService.shared.settings.region.isEmpty ? "US" : StorageService.shared.settings.region

        await withTaskGroup(of: (String, [MediaItem]).self) { group in
            group.addTask {
                let items = try? await TMDBService.shared.discoverMoviesWithProvider(
                    providerIds: providerIds, region: region, page: 1
                ).results
                return ("popularMovies", items ?? [])
            }
            group.addTask {
                let items = try? await TMDBService.shared.discoverTVWithProvider(
                    providerIds: providerIds, region: region, page: 1
                ).results
                return ("popularTV", items ?? [])
            }
            group.addTask {
                let items = try? await TMDBService.shared.discoverMoviesWithProvider(
                    providerIds: providerIds, region: region, page: 2
                ).results
                return ("trendingMovies", items ?? [])
            }
            group.addTask {
                let items = try? await TMDBService.shared.discoverTVWithProvider(
                    providerIds: providerIds, region: region, page: 2
                ).results
                return ("trendingTV", items ?? [])
            }
            group.addTask {
                let items = try? await TMDBService.shared.discoverMoviesWithProvider(
                    providerIds: providerIds, region: region, page: 3
                ).results
                return ("topRatedMovies", items ?? [])
            }
            group.addTask {
                let items = try? await TMDBService.shared.discoverTVWithProvider(
                    providerIds: providerIds, region: region, page: 3
                ).results
                return ("topRatedTV", items ?? [])
            }

            for await (key, items) in group {
                switch key {
                case "popularMovies": popularMovies = items
                case "popularTV": popularTV = items
                case "trendingMovies": trendingMovies = items
                case "trendingTV": trendingTV = items
                case "topRatedMovies": topRatedMovies = items
                case "topRatedTV": topRatedTV = items
                default: break
                }
            }
        }

        // Build hero from first page of combined content
        var merged: [MediaItem] = []
        let movieCount = max(popularMovies.count, trendingMovies.count)
        let tvCount = max(popularTV.count, trendingTV.count)
        for i in 0..<max(movieCount, tvCount) {
            if i < popularMovies.count { merged.append(popularMovies[i]) }
            if i < popularTV.count { merged.append(popularTV[i]) }
        }
        heroItems = Array(deduplicated(merged).prefix(20))

        isLoading = false
    }

    private func clearContent() {
        heroItems = []
        trendingMovies = []
        trendingTV = []
        popularMovies = []
        popularTV = []
        topRatedMovies = []
        topRatedTV = []
    }

    private func deduplicated(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = "\(item.resolvedMediaType.rawValue)-\(item.id)"
            return seen.insert(key).inserted
        }
    }

    private func saveSelection() {
        var settings = StorageService.shared.settings
        settings.streamqServiceIds = Array(selectedServiceIds)
        StorageService.shared.updateSettings(settings)
    }

    private func loadSelection() {
        let ids = StorageService.shared.settings.streamqServiceIds
        if !ids.isEmpty {
            selectedServiceIds = Set(ids)
        }
    }
}

// MARK: - MyStreamingView

struct MyStreamingView: View {
    @StateObject private var viewModel = MyStreamingViewModel()
    @ObservedObject private var leavingSoon = LeavingSoonService.shared
    @State private var selectedItem: MediaItem?
    @State private var showServicePicker = false

    var body: some View {
        Group {
            if viewModel.hasSelection {
                streamingContentView
            } else {
                emptyStateView
            }
        }
        .navigationTitle("StreamQ")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showServicePicker = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        #endif
        .sheet(isPresented: $showServicePicker) {
            StreamingServicePickerView(viewModel: viewModel)
        }
        .mediaDetailPresentation(item: $selectedItem)
        .task {
            await viewModel.loadContent()
        }
        .onChange(of: viewModel.selectedServiceIds) { _, _ in
            Task { await viewModel.loadContent() }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: tvSpacing) {
            Spacer()

            Image(systemName: "tv.and.mediabox")
                .font(.system(size: emptyStateIconSize))
                .foregroundStyle(.secondary)

            Text("Pick Your Services")
                .font(emptyStateTitleFont)
                .fontWeight(.bold)
                .foregroundStyle(tvTextColor)

            Text("Select the streaming services you subscribe to\nand we'll show you what's available to watch.")
                .font(emptyStateBodyFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showServicePicker = true
            } label: {
                Label("Choose Services", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Platform Sizing Helpers

    private var tvSpacing: CGFloat {
        #if os(tvOS)
        32
        #else
        20
        #endif
    }

    private var emptyStateIconSize: CGFloat {
        #if os(tvOS)
        96
        #else
        64
        #endif
    }

    private var emptyStateTitleFont: Font {
        #if os(tvOS)
        .title
        #else
        .title2
        #endif
    }

    private var emptyStateBodyFont: Font {
        #if os(tvOS)
        .body
        #else
        .subheadline
        #endif
    }

    private var tvTextColor: Color {
        #if os(tvOS)
        .white
        #else
        .primary
        #endif
    }

    private var serviceBarLogoSize: CGFloat {
        #if os(tvOS)
        36
        #else
        22
        #endif
    }

    private var serviceBarCornerRadius: CGFloat {
        #if os(tvOS)
        8
        #else
        5
        #endif
    }

    private var serviceBarFont: Font {
        #if os(tvOS)
        .callout
        #else
        .caption
        #endif
    }

    private var contentSpacing: CGFloat {
        #if os(tvOS)
        40
        #else
        24
        #endif
    }

    private var horizontalInset: CGFloat {
        #if os(tvOS)
        60
        #else
        16
        #endif
    }

    // MARK: - Streaming Content

    private var streamingContentView: some View {
        #if os(tvOS)
        ScrollView {
            VStack(spacing: 40) {
                // Selected services bar
                selectedServicesBar

                if viewModel.isLoading && viewModel.heroItems.isEmpty {
                    ProgressView()
                        .padding(.top, 40)
                } else {
                    streamingRows
                }
            }
            .padding(.top, 20)
            .padding(.bottom)
        }
        #else
        PopcornRefreshableScrollView {
            await viewModel.refresh()
        } content: {
            LazyVStack(spacing: contentSpacing) {
                // Selected services bar
                selectedServicesBar

                if viewModel.isLoading && viewModel.heroItems.isEmpty {
                    ProgressView()
                        .padding(.top, 40)
                } else {
                    streamingRows
                }
            }
            .padding(.vertical)
        }
        #endif
    }

    @ViewBuilder
    private var streamingRows: some View {
        // Hero carousel
        if !viewModel.heroItems.isEmpty {
            ResizableHeroCarousel(
                items: viewModel.heroItems,
                onItemTap: { item in
                    selectedItem = item
                },
                tabID: "8"
            )
            #if os(tvOS)
            .focusSection()
            #endif
        }

        if !leavingSoon.entries.isEmpty {
            LeavingSoonRow(entries: leavingSoon.entries) { item in
                selectedItem = item
            }
        }

        // Content rows
        if !viewModel.popularMovies.isEmpty {
            MediaRowView(
                title: "Popular Movies",
                items: viewModel.popularMovies,
                onItemTap: { item in selectedItem = item },
                onSeeAll: nil
            )
        }

        if !viewModel.popularTV.isEmpty {
            MediaRowView(
                title: "Popular Shows",
                items: viewModel.popularTV,
                onItemTap: { item in selectedItem = item },
                onSeeAll: nil
            )
        }

        if !viewModel.trendingMovies.isEmpty {
            MediaRowView(
                title: "More Movies",
                items: viewModel.trendingMovies,
                onItemTap: { item in selectedItem = item },
                onSeeAll: nil
            )
        }

        if !viewModel.trendingTV.isEmpty {
            MediaRowView(
                title: "More Shows",
                items: viewModel.trendingTV,
                onItemTap: { item in selectedItem = item },
                onSeeAll: nil
            )
        }

        if !viewModel.topRatedMovies.isEmpty {
            MediaRowView(
                title: "Hidden Gems",
                items: viewModel.topRatedMovies,
                onItemTap: { item in selectedItem = item },
                onSeeAll: nil
            )
        }

        if !viewModel.topRatedTV.isEmpty {
            MediaRowView(
                title: "Shows to Discover",
                items: viewModel.topRatedTV,
                onItemTap: { item in selectedItem = item },
                onSeeAll: nil
            )
        }
    }

    // MARK: - Selected Services Bar

    private var selectedServicesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: serviceBarChipSpacing) {
                ForEach(viewModel.selectedServices) { service in
                    ResilientAsyncImage(
                        url: TMDBService.shared.imageURL(path: service.logoPath, size: .logo)
                    ) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: serviceBarLogoSize, height: serviceBarLogoSize)
                                .clipShape(RoundedRectangle(cornerRadius: serviceBarCornerRadius, style: .continuous))
                        default:
                            RoundedRectangle(cornerRadius: serviceBarCornerRadius, style: .continuous)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: serviceBarLogoSize, height: serviceBarLogoSize)
                        }
                    }
                    .padding(.horizontal, serviceBarHPadding)
                    .padding(.vertical, serviceBarVPadding)
                    #if os(tvOS)
                    .background(.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                    #else
                    .glassEffect(.regular, in: .capsule)
                    #endif
                }

                Button {
                    showServicePicker = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(editButtonFont)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, horizontalInset)
        }
    }

    private var serviceBarChipSpacing: CGFloat {
        #if os(tvOS)
        16
        #else
        10
        #endif
    }

    private var serviceBarInnerSpacing: CGFloat {
        #if os(tvOS)
        10
        #else
        6
        #endif
    }

    private var serviceBarHPadding: CGFloat {
        #if os(tvOS)
        16
        #else
        10
        #endif
    }

    private var serviceBarVPadding: CGFloat {
        #if os(tvOS)
        10
        #else
        6
        #endif
    }

    private var editButtonFont: Font {
        #if os(tvOS)
        .title2
        #else
        .title3
        #endif
    }
}

// MARK: - Streaming Service Picker

struct StreamingServicePickerView: View {
    @ObservedObject var viewModel: MyStreamingViewModel
    @Environment(\.dismiss) private var dismiss

    private var columns: [GridItem] {
        #if os(tvOS)
        [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 32)]
        #else
        [GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 16)]
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(tvOS)
        32
        #else
        16
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Select the services you subscribe to. Only content from your services will appear.")
                        #if os(tvOS)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 60)
                        #else
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        #endif

                    LazyVGrid(columns: columns, spacing: gridSpacing) {
                        ForEach(StreamingService.allServices) { service in
                            ServiceToggleCell(
                                service: service,
                                isSelected: viewModel.selectedServiceIds.contains(service.id)
                            ) {
                                viewModel.toggle(service)
                            }
                        }
                    }
                    #if os(tvOS)
                    .padding(.horizontal, 60)
                    #else
                    .padding(.horizontal)
                    #endif
                }
                .padding(.vertical)
            }
            .navigationTitle("Streaming Services")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Service Toggle Cell (ActionButton style)

struct ServiceToggleCell: View {
    let service: StreamingService
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isPressed = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #endif

    private var isCompact: Bool {
        #if os(tvOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var logoSize: CGFloat {
        #if os(tvOS)
        48
        #else
        isCompact ? 32 : 40
        #endif
    }

    private var cellCornerRadius: CGFloat {
        #if os(tvOS)
        16
        #else
        isCompact ? 12 : 16
        #endif
    }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                onToggle()
            }
        }) {
            VStack(spacing: isCompact ? 4 : 6) {
                ResilientAsyncImage(
                    url: TMDBService.shared.imageURL(path: service.logoPath, size: .logo)
                ) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: logoSize, height: logoSize)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    default:
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: logoSize, height: logoSize)
                            .overlay {
                                Text(String(service.name.prefix(1)))
                                    .font(.title3)
                                    .fontWeight(.bold)
                            }
                    }
                }
                .scaleEffect(isPressed ? 1.15 : 1.0)

                Text(service.name)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 60 : 90)
            .padding(.vertical, isCompact ? 6 : 10)
            .padding(.horizontal, isCompact ? 6 : 10)
            .background(
                RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
            .scaleEffect(cellScaleEffect)
        }
        #if os(tvOS)
        .buttonStyle(TVOSTransparentButtonStyle(cornerRadius: cellCornerRadius))
        .focused($isFocused)
        #else
        .buttonStyle(.plain)
        #endif
    }

    // MARK: - Style Properties

    private var labelColor: Color {
        isSelected ? .accentColor : .secondary
    }

    private var backgroundFill: Color {
        #if os(tvOS)
        return Color.clear
        #else
        return isSelected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12)
        #endif
    }

    private var borderColor: Color {
        if isSelected {
            #if os(tvOS)
            return Color.accentColor.opacity(isFocused ? 0.95 : 0.72)
            #else
            return Color.accentColor.opacity(0.7)
            #endif
        }
        #if os(tvOS)
        return Color.white.opacity(isFocused ? 0.96 : 0.18)
        #else
        return Color.primary.opacity(0.12)
        #endif
    }

    private var borderWidth: CGFloat {
        #if os(tvOS)
        return isFocused ? 2.6 : (isSelected ? 1.6 : 1.1)
        #else
        return isSelected ? 1.4 : 1
        #endif
    }

    private var shadowColor: Color {
        #if os(tvOS)
        return Color.black.opacity(isFocused ? 0.4 : 0.16)
        #else
        return Color.clear
        #endif
    }

    private var shadowRadius: CGFloat {
        #if os(tvOS)
        return isFocused ? 18 : 6
        #else
        return 0
        #endif
    }

    private var shadowYOffset: CGFloat {
        #if os(tvOS)
        return isFocused ? 10 : 3
        #else
        return 0
        #endif
    }

    private var cellScaleEffect: CGFloat {
        #if os(tvOS)
        return isFocused ? 1.08 : 1
        #else
        return 1
        #endif
    }
}

#Preview {
    MyStreamingView()
}
