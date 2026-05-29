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
        StreamingService(id: 350, name: "Apple TV+",     logoPath: "/6uhKBfmtzFqOcLousHwZuzcrScK.jpg"),
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

    private static let storageKey = "myStreamingSelectedServiceIds"

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
        let data = try? JSONEncoder().encode(Array(selectedServiceIds))
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func loadSelection() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let ids = try? JSONDecoder().decode([Int].self, from: data) else { return }
        selectedServiceIds = Set(ids)
    }
}

// MARK: - MyStreamingView

struct MyStreamingView: View {
    @StateObject private var viewModel = MyStreamingViewModel()
    @State private var selectedItem: MediaItem?
    @State private var showServicePicker = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.hasSelection {
                    streamingContentView
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("My Streaming")
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
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "tv.and.mediabox")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Pick Your Services")
                .font(.title2)
                .fontWeight(.bold)

            Text("Select the streaming services you subscribe to\nand we'll show you what's available to watch.")
                .font(.subheadline)
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

    // MARK: - Streaming Content

    private var streamingContentView: some View {
        PopcornRefreshableScrollView {
            await viewModel.refresh()
        } content: {
            LazyVStack(spacing: 24) {
                // Selected services bar
                selectedServicesBar

                if viewModel.isLoading && viewModel.heroItems.isEmpty {
                    ProgressView()
                        .padding(.top, 40)
                } else {
                    // Hero carousel
                    if !viewModel.heroItems.isEmpty {
                        ResizableHeroCarousel(
                            items: viewModel.heroItems,
                            onItemTap: { item in
                                selectedItem = item
                            }
                        )
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
            }
            .padding(.vertical)
        }
    }

    // MARK: - Selected Services Bar

    private var selectedServicesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.selectedServices) { service in
                    HStack(spacing: 6) {
                        ResilientAsyncImage(
                            url: TMDBService.shared.imageURL(path: service.logoPath, size: .logo)
                        ) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 22, height: 22)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            default:
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 22, height: 22)
                            }
                        }

                        Text(service.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                }

                Button {
                    showServicePicker = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Streaming Service Picker

struct StreamingServicePickerView: View {
    @ObservedObject var viewModel: MyStreamingViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Select the services you subscribe to. Only content from your services will appear.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(StreamingService.allServices) { service in
                            ServiceToggleCell(
                                service: service,
                                isSelected: viewModel.selectedServiceIds.contains(service.id)
                            ) {
                                viewModel.toggle(service)
                            }
                        }
                    }
                    .padding(.horizontal)
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

// MARK: - Service Toggle Cell

struct ServiceToggleCell: View {
    let service: StreamingService
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ResilientAsyncImage(
                        url: TMDBService.shared.imageURL(path: service.logoPath, size: .logo)
                    ) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        default:
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 56, height: 56)
                                .overlay {
                                    Text(String(service.name.prefix(1)))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                }
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                    )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(service.name)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MyStreamingView()
}
