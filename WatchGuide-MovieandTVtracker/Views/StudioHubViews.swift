//
//  StudioHubViews.swift
//  WatchGuide-MovieandTVtracker
//
//  Immersive hub views for each major production studio.
//  Each hub uses ImmersiveHubLayout with a unique brand palette.
//

import SwiftUI

// MARK: - Shared Studio Hub Data Loader

@MainActor
private func loadStudioContent(companyIds: [Int]) async throws -> [MediaItem] {
    return try await Task.detached(priority: .userInitiated) {
        var allItems: [MediaItem] = []
        var seenIds = Set<String>()

        func addBatch(_ items: [MediaItem]) {
            for item in items {
                let id = "\(item.resolvedMediaType.rawValue)-\(item.id)"
                if !seenIds.contains(id) {
                    seenIds.insert(id)
                    allItems.append(item)
                }
            }
        }

        for companyId in companyIds {
            let firstMoviePage = try await TMDBService.shared.discoverMoviesByCompany(companyIds: [companyId], page: 1)
            addBatch(firstMoviePage.results)
            let moviePages = min(firstMoviePage.totalPages ?? 1, 3)
            if moviePages > 1 {
                try await withThrowingTaskGroup(of: [MediaItem].self) { group in
                    for page in 2...moviePages {
                        group.addTask {
                            try await TMDBService.shared.discoverMoviesByCompany(companyIds: [companyId], page: page).results
                        }
                    }
                    for try await r in group { addBatch(r) }
                }
            }

            let firstTVPage = try await TMDBService.shared.discoverTVByCompany(companyIds: [companyId], page: 1)
            addBatch(firstTVPage.results)
            let tvPages = min(firstTVPage.totalPages ?? 1, 3)
            if tvPages > 1 {
                try await withThrowingTaskGroup(of: [MediaItem].self) { group in
                    for page in 2...tvPages {
                        group.addTask {
                            try await TMDBService.shared.discoverTVByCompany(companyIds: [companyId], page: page).results
                        }
                    }
                    for try await r in group { addBatch(r) }
                }
            }
        }

        let now = Date()
        let filtered = allItems.filter { item in
            let dateStr = item.releaseDate ?? item.firstAirDate ?? ""
            if let date = TMDBService.shared.date(from: dateStr) {
                return date <= now
            }
            return true
        }
        return filtered.sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
    }.value
}


// MARK: - Warner Bros Pictures Hub
// Design: Shield gold on dark navy, classic Hollywood grandeur

struct WarnerBrosHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true

    private let brandGold = Color(red: 0.85, green: 0.72, blue: 0.3)
    private let bgColor = Color(red: 0.1, green: 0.1, blue: 0.18)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    bgColor.ignoresSafeArea()
                    ProgressView().tint(brandGold).scaleEffect(1.2)
                }
            } else {
                ImmersiveHubLayout(
                    items: items,
                    logo: Image("Warner Bros Pictures")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(.white)
                        .shadow(color: brandGold.opacity(0.6), radius: 25),
                    backgroundColor: bgColor
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadContent() }
    }

    private func loadContent() async {
        loading = true
        do {
            items = try await loadStudioContent(companyIds: [174])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Universal Pictures Hub
// Design: Globe blue on deep space black, epic cinematic scope

struct UniversalHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true

    private let brandBlue = Color(red: 0.05, green: 0.28, blue: 0.63)
    private let bgColor = Color(red: 0.03, green: 0.03, blue: 0.06)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    bgColor.ignoresSafeArea()
                    ProgressView().tint(brandBlue).scaleEffect(1.2)
                }
            } else {
                ImmersiveHubLayout(
                    items: items,
                    logo: Image("Universal Pictures")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(.white)
                        .shadow(color: brandBlue.opacity(0.6), radius: 25),
                    backgroundColor: bgColor
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadContent() }
    }

    private func loadContent() async {
        loading = true
        do {
            items = try await loadStudioContent(companyIds: [33])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Sony Pictures Hub
// Design: Clean modern blue on near-black, sleek and contemporary

struct SonyPicturesHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true

    private let brandBlue = Color(red: 0.08, green: 0.40, blue: 0.75)
    private let bgColor = Color(red: 0.04, green: 0.04, blue: 0.06)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    bgColor.ignoresSafeArea()
                    ProgressView().tint(brandBlue).scaleEffect(1.2)
                }
            } else {
                ImmersiveHubLayout(
                    items: items,
                    logo: Image("Sony Pictures")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(.white)
                        .shadow(color: brandBlue.opacity(0.6), radius: 25),
                    backgroundColor: bgColor
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadContent() }
    }

    private func loadContent() async {
        loading = true
        do {
            items = try await loadStudioContent(companyIds: [34])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Columbia Pictures Hub
// Design: Torch lady copper warmth, classic prestige feel

struct ColumbiaHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true

    private let brandCopper = Color(red: 0.75, green: 0.34, blue: 0.0)
    private let bgColor = Color(red: 0.06, green: 0.04, blue: 0.03)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    bgColor.ignoresSafeArea()
                    ProgressView().tint(brandCopper).scaleEffect(1.2)
                }
            } else {
                ImmersiveHubLayout(
                    items: items,
                    logo: Image("Columbia Pictures")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(.white)
                        .shadow(color: brandCopper.opacity(0.6), radius: 25),
                    backgroundColor: bgColor
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadContent() }
    }

    private func loadContent() async {
        loading = true
        do {
            items = try await loadStudioContent(companyIds: [5])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Paramount Pictures Hub
// Design: Mountain peak blue on dark, snowy summit grandeur

struct ParamountPicturesHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true

    private let brandBlue = Color(red: 0.0, green: 0.2, blue: 0.63)
    private let bgColor = Color(red: 0.03, green: 0.03, blue: 0.08)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    bgColor.ignoresSafeArea()
                    ProgressView().tint(brandBlue).scaleEffect(1.2)
                }
            } else {
                ImmersiveHubLayout(
                    items: items,
                    logo: Image("Paramount Pictures")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(.white)
                        .shadow(color: brandBlue.opacity(0.6), radius: 25),
                    backgroundColor: bgColor
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadContent() }
    }

    private func loadContent() async {
        loading = true
        do {
            items = try await loadStudioContent(companyIds: [4])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - DreamWorks Hub
// Design: Moonlit sky whimsy, warm glow on dark teal canvas

struct DreamWorksHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true

    private let moonGlow = Color(red: 0.75, green: 0.65, blue: 0.4)
    private let bgColor = Color(red: 0.08, green: 0.12, blue: 0.18)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    bgColor.ignoresSafeArea()
                    ProgressView().tint(moonGlow).scaleEffect(1.2)
                }
            } else {
                ImmersiveHubLayout(
                    items: items,
                    logo: Image("Dreamworks")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(.white)
                        .shadow(color: moonGlow.opacity(0.6), radius: 25),
                    backgroundColor: bgColor
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadContent() }
    }

    private func loadContent() async {
        loading = true
        do {
            items = try await loadStudioContent(companyIds: [7])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Illumination Hub
// Design: Playful bright yellow on dark, Minion-energy vibrance

struct IlluminationHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true

    private let brandYellow = Color(red: 1.0, green: 0.7, blue: 0.0)
    private let bgColor = Color(red: 0.06, green: 0.04, blue: 0.0)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    bgColor.ignoresSafeArea()
                    ProgressView().tint(brandYellow).scaleEffect(1.2)
                }
            } else {
                ImmersiveHubLayout(
                    items: items,
                    logo: Image("Illumination")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(.white)
                        .shadow(color: brandYellow.opacity(0.6), radius: 25),
                    backgroundColor: bgColor
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadContent() }
    }

    private func loadContent() async {
        loading = true
        do {
            items = try await loadStudioContent(companyIds: [6704])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Searchlight Pictures Hub
// Design: Cinema amber spotlights on dark theater, indie prestige

struct SearchlightHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true

    private let brandGold = Color(red: 0.83, green: 0.63, blue: 0.09)
    private let bgColor = Color(red: 0.06, green: 0.05, blue: 0.03)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    bgColor.ignoresSafeArea()
                    ProgressView().tint(brandGold).scaleEffect(1.2)
                }
            } else {
                ImmersiveHubLayout(
                    items: items,
                    logo: Image("Searchlight Pictures")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(.white)
                        .shadow(color: brandGold.opacity(0.6), radius: 25),
                    backgroundColor: bgColor
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadContent() }
    }

    private func loadContent() async {
        loading = true
        do {
            items = try await loadStudioContent(companyIds: [43])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Skydance Hub
// Design: Sleek modern cool blue, high-tech action aesthetic

struct SkydanceHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true

    private let brandBlue = Color(red: 0.0, green: 0.47, blue: 0.76)
    private let bgColor = Color(red: 0.03, green: 0.03, blue: 0.06)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    bgColor.ignoresSafeArea()
                    ProgressView().tint(brandBlue).scaleEffect(1.2)
                }
            } else {
                ImmersiveHubLayout(
                    items: items,
                    logo: Image("Skydance")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(.white)
                        .shadow(color: brandBlue.opacity(0.6), radius: 25),
                    backgroundColor: bgColor
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadContent() }
    }

    private func loadContent() async {
        loading = true
        do {
            items = try await loadStudioContent(companyIds: [82819])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Happy Madison Hub
// Design: Comedy casual warm orange, laid-back fun energy

struct HappyMadisonHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true

    private let brandOrange = Color(red: 1.0, green: 0.43, blue: 0.0)
    private let bgColor = Color(red: 0.06, green: 0.04, blue: 0.02)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    bgColor.ignoresSafeArea()
                    ProgressView().tint(brandOrange).scaleEffect(1.2)
                }
            } else {
                ImmersiveHubLayout(
                    items: items,
                    logo: Image("Happy Madison")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(.white)
                        .shadow(color: brandOrange.opacity(0.6), radius: 25),
                    backgroundColor: bgColor
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadContent() }
    }

    private func loadContent() async {
        loading = true
        do {
            items = try await loadStudioContent(companyIds: [11509])
            loading = false
        } catch { loading = false }
    }
}


// MARK: - Walt Disney Pictures Hub
// Design: Enchanted castle deep blue, fairy-tale magic sparkle

struct WaltDisneyHubView: View {
    @State private var items: [MediaItem] = []
    @State private var loading = true

    private let brandBlue = Color(red: 0.1, green: 0.14, blue: 0.49)
    private let bgColor = Color(red: 0.04, green: 0.04, blue: 0.12)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    bgColor.ignoresSafeArea()
                    ProgressView().tint(brandBlue).scaleEffect(1.2)
                }
            } else {
                ImmersiveHubLayout(
                    items: items,
                    logo: Image("Walt Disney Pictures")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(.white)
                        .shadow(color: brandBlue.opacity(0.7), radius: 30),
                    backgroundColor: bgColor
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadContent() }
    }

    private func loadContent() async {
        loading = true
        do {
            items = try await loadStudioContent(companyIds: [2])
            loading = false
        } catch { loading = false }
    }
}
