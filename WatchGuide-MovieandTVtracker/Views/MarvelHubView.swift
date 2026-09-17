import SwiftUI

struct MarvelHubView: View {
    @State private var movies: [MediaItem] = []
    @State private var phaseItems: [String: [MediaItem]] = [:]
    @State private var loading = true
    @State private var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let marvelRed = Color(red: 0.9, green: 0.11, blue: 0.14)

    var body: some View {
        Group {
            if loading {
                ZStack {
                    Color(red: 0.05, green: 0.0, blue: 0.0).ignoresSafeArea()
                    ProgressView().tint(marvelRed).scaleEffect(1.2)
                }
            } else {
                NavigationStack {
                    ZStack(alignment: .top) {
                        Color(red: 0.05, green: 0.0, blue: 0.0).ignoresSafeArea()
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                // Cinematic hero with red energy tint
                                heroSection
                                
                                // Marvel Studios logo with red glow
                                Image("Marvel Studios")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.white)
                                    .frame(height: 50)
                                    .shadow(color: marvelRed.opacity(0.7), radius: 25)
                                    .padding(.top, -50)
                                    .padding(.bottom, 8)
                                
                                // Cinematic red divider
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, marvelRed.opacity(0.6), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 1.5)
                                    .padding(.horizontal, 60)
                                    .padding(.bottom, 20)
                                
                                VStack(spacing: horizontalSizeClass == .regular ? 64 : 32) {
                                    // Saga rows
                                    phaseRow("The Infinity Saga", key: "infinitySaga")
                                    phaseRow("The Multiverse Saga", key: "multiverseSaga")
                                    
                                    // Phase rows
                                    phaseRow("Phase 1", key: "phase1")
                                    phaseRow("Phase 2", key: "phase2")
                                    phaseRow("Phase 3", key: "phase3")
                                    phaseRow("Phase 4", key: "phase4")
                                    phaseRow("Phase 5", key: "phase5")
                                    phaseRow("Phase 6", key: "phase6")
                                    
                                    Color.clear.frame(height: 100)
                                }
                                .padding(.top, horizontalSizeClass == .regular ? 40 : 20)
                            }
                        }
                        .scrollIndicators(.hidden)
                        #if os(iOS)
                        .ignoresSafeArea(edges: .top)
                        #endif
                        
                        navBar
                    }
                    #if os(tvOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #elseif os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
                }
                .mediaDetailPresentation(item: $selectedItem)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadContent() }
    }

    @ViewBuilder
    private func phaseRow(_ title: String, key: String) -> some View {
        let items = phaseItems[key] ?? []
        if !items.isEmpty {
            MediaRowView(
                title: title,
                items: items,
                limit: items.count,
                onItemTap: { selectedItem = $0 },
                isImmersiveStyle: true
            )
        }
    }
    
    // MARK: - Sections
    
    private var heroSection: some View {
        HeroCarouselView(
            items: Array(movies.prefix(10)),
            onItemTap: { selectedItem = $0 },
            aspectRatio: horizontalSizeClass == .regular ? 16/9 : 10/12,
            isPortrait: horizontalSizeClass != .regular,
            isEdgeToEdge: true,
            externalVisibilityOverride: true,
            isImmersiveStyle: true
        )
        .overlay(
            ZStack {
                // Red-tinted cinematic gradient
                LinearGradient(
                    colors: [.clear, marvelRed.opacity(0.12), Color(red: 0.05, green: 0.0, blue: 0.0).opacity(0.9)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                // Subtle red vignette on edges
                RadialGradient(
                    colors: [.clear, marvelRed.opacity(0.08)],
                    center: .center,
                    startRadius: 200,
                    endRadius: 600
                )
                .blendMode(.screen)
            }
            .padding(.top, 200)
            .allowsHitTesting(false)
        )
    }
    
    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 60 : 20)
        .padding(.top, horizontalSizeClass == .regular ? 80 : 50)
        .background(
            LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
    
    // MARK: - Data Loading

    private func loadContent() async {
        loading = true

        // Fetch ALL MCU items individually by TMDB ID — no company discover API
        let allEntries = MCUPhases.allEntries
        var itemIndex: [String: MediaItem] = [:]

        await withTaskGroup(of: (String, MediaItem?).self) { group in
            for entry in allEntries {
                group.addTask {
                    do {
                        if entry.type == .movie {
                            let details = try await TMDBService.shared.getMovieDetails(id: Int(entry.id) ?? 0)
                            return (entry.id, MediaItem(from: details))
                        } else {
                            let details = try await TMDBService.shared.getTVShowDetails(id: Int(entry.id) ?? 0)
                            return (entry.id, MediaItem(from: details))
                        }
                    } catch {
                        return (entry.id, nil)
                    }
                }
            }
            for await (id, item) in group {
                if let item = item {
                    itemIndex[id] = item
                }
            }
        }

        // Build phase/saga rows from index
        let phases: [(String, [MCUPhaseEntry])] = [
            ("phase1", MCUPhases.phase1),
            ("phase2", MCUPhases.phase2),
            ("phase3", MCUPhases.phase3),
            ("phase4", MCUPhases.phase4),
            ("phase5", MCUPhases.phase5),
            ("phase6", MCUPhases.phase6),
            ("infinitySaga", MCUPhases.infinitySaga),
            ("multiverseSaga", MCUPhases.multiverseSaga),
        ]

        var built: [String: [MediaItem]] = [:]
        for (key, entries) in phases {
            built[key] = entries.compactMap { itemIndex[$0.id] }
        }

        // Hero carousel: most recent MCU releases
        let allItems = MCUPhases.allEntries.compactMap { itemIndex[$0.id] }
        let heroItems = allItems.sorted {
            ($0.releaseDate ?? $0.firstAirDate ?? "") > ($1.releaseDate ?? $1.firstAirDate ?? "")
        }

        await MainActor.run {
            self.movies = heroItems
            self.phaseItems = built
            self.loading = false
        }
    }
}

// MARK: - MCU Phase Entry

private struct MCUPhaseEntry {
    let id: String
    let type: MediaType

    enum MediaType {
        case movie, tv
    }

    static func movie(_ id: String) -> MCUPhaseEntry { .init(id: id, type: .movie) }
    static func tv(_ id: String) -> MCUPhaseEntry { .init(id: id, type: .tv) }
}

// MARK: - MCU Phase & Saga TMDB IDs (release order)

private enum MCUPhases {
    // Phase 1 (2008-2012)
    static let phase1: [MCUPhaseEntry] = [
        .movie("1726"),   // Iron Man
        .movie("1724"),   // The Incredible Hulk
        .movie("10138"),  // Iron Man 2
        .movie("10195"),  // Thor
        .movie("1771"),   // Captain America: The First Avenger
        .movie("24428"),  // The Avengers
    ]

    // Phase 2 (2013-2015)
    static let phase2: [MCUPhaseEntry] = [
        .movie("68721"),  // Iron Man 3
        .movie("76338"),  // Thor: The Dark World
        .movie("100402"), // Captain America: The Winter Soldier
        .movie("118340"), // Guardians of the Galaxy
        .movie("99861"),  // Avengers: Age of Ultron
        .movie("102899"), // Ant-Man
    ]

    // Phase 3 (2016-2019)
    static let phase3: [MCUPhaseEntry] = [
        .movie("271110"), // Captain America: Civil War
        .movie("284052"), // Doctor Strange
        .movie("283995"), // Guardians of the Galaxy Vol. 2
        .movie("315635"), // Spider-Man: Homecoming
        .movie("284053"), // Thor: Ragnarok
        .movie("284054"), // Black Panther
        .movie("299536"), // Avengers: Infinity War
        .movie("363088"), // Ant-Man and the Wasp
        .movie("299537"), // Captain Marvel
        .movie("299534"), // Avengers: Endgame
        .movie("429617"), // Spider-Man: Far From Home
    ]

    // Phase 4 (2021-2022)
    static let phase4: [MCUPhaseEntry] = [
        .movie("497698"), // Black Widow
        .tv("85271"),     // WandaVision
        .tv("88396"),     // The Falcon and the Winter Soldier
        .tv("84958"),     // Loki
        .movie("566525"), // Shang-Chi and the Legend of the Ten Rings
        .movie("524434"), // Eternals
        .tv("88329"),     // Hawkeye
        .movie("634649"), // Spider-Man: No Way Home
        .tv("92749"),     // Moon Knight
        .movie("453395"), // Doctor Strange in the Multiverse of Madness
        .tv("92782"),     // Ms. Marvel
        .movie("616037"), // Thor: Love and Thunder
        .tv("92783"),     // She-Hulk: Attorney at Law
        .tv("91363"),     // What If...?
        .movie("894205"), // Werewolf by Night
        .movie("505642"), // Black Panther: Wakanda Forever
        .movie("774752"), // The Guardians of the Galaxy Holiday Special
    ]

    // Phase 5 (2023-2024)
    static let phase5: [MCUPhaseEntry] = [
        .movie("640146"), // Ant-Man and the Wasp: Quantumania
        .movie("447365"), // Guardians of the Galaxy Vol. 3
        .tv("114472"),    // Secret Invasion
        .tv("84958"),     // Loki Season 2 (same show ID)
        .movie("609681"), // The Marvels
        .tv("91363"),     // What If...? Season 2 (same show ID)
        .tv("122226"),    // Echo
        .movie("533535"), // Deadpool & Wolverine
        .tv("138501"),    // Agatha All Along
    ]

    // Phase 6 (2025+)
    static let phase6: [MCUPhaseEntry] = [
        .movie("822119"), // Captain America: Brave New World
        .tv("202555"),    // Daredevil: Born Again
        .movie("986056"), // Thunderbolts*
        .movie("617126"), // The Fantastic Four: First Steps
    ]

    // The Infinity Saga (Phases 1-3)
    static let infinitySaga: [MCUPhaseEntry] = phase1 + phase2 + phase3

    // The Multiverse Saga (Phases 4-6)
    static let multiverseSaga: [MCUPhaseEntry] = phase4 + phase5 + phase6

    // All unique entries for fetching (deduplicated by ID)
    static var allEntries: [MCUPhaseEntry] {
        var seen = Set<String>()
        var result: [MCUPhaseEntry] = []
        for entry in phase1 + phase2 + phase3 + phase4 + phase5 + phase6 {
            if !seen.contains(entry.id) {
                seen.insert(entry.id)
                result.append(entry)
            }
        }
        return result
    }
}
