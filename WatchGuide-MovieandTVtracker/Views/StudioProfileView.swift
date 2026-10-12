//
//  StudioProfileView.swift
//  WatchGuide-MovieandTVtracker
//
//  A studio's page in the shape of a creator profile: logo avatar, handle,
//  counts, Follow and Pops buttons, a short bio, then a dense grid of its
//  movies and shows. Opened from the studio avatar on a Pops clip.
//

import SwiftUI

// MARK: - Studio

/// The studio (or streamer) a clip is attributed to. A curated hub covers
/// several TMDB companies, so this holds lists rather than one id.
struct PopsStudio: Identifiable, Hashable {
    let name: String
    /// A TMDB logo path (a company's or a network's).
    let logoPath: String?
    let originCountry: String?
    let companyIds: [Int]
    let networkIds: [Int]
    /// Companies whose titles this studio's page leaves out: a parent group
    /// doesn't also list the labels that sit under it.
    var excludedCompanyIds: [Int] = []

    var id: String {
        "c" + companyIds.map(String.init).joined(separator: ",")
            + "n" + networkIds.map(String.init).joined(separator: ",")
    }

    /// A streamer or network, with no film catalogue of its own here.
    var isNetworkOnly: Bool { companyIds.isEmpty }
}

extension PopsStudio {
    /// Companies that count as a real studio when no curated hub matches.
    private static let majorCompanyIDs: Set<Int> = [
        174, 17, 12, 33, 4, 5, 34, 25, 2, 3, 420, 7505, 1, 521, 923, 1632, 41077,
        3172, 21, 20580, 559, 10146, 43, 6704, 128064, 3268, 82819, 56, 11073
    ]

    /// Labels with their own identity and audience that sit under a larger
    /// group: Marvel Studios, Pixar, Lucasfilm and the like have their own
    /// channels and followers. A title from one is shown as that label, never
    /// as its parent, and the parent's page leaves them out.
    static let labelIDs: [Int] = labelCompanyIDs.sorted()

    private static let labelCompanyIDs: Set<Int> = [
        420,    // Marvel Studios
        7505,   // Marvel Entertainment
        3,      // Pixar
        1,      // Lucasfilm
        6125,   // Walt Disney Animation Studios
        43,     // Searchlight Pictures
        127929  // Searchlight Pictures (current)
    ]

    /// Streamers and networks that should be shown as the source of a series
    /// even when they aren't one of the user's hubs.
    private static let streamerNetworkIDs: Set<Int> = [
        213, 1024, 2739, 2552, 453, 49, 3186, 4330, 3353, 67, 318, 88, 174, 6, 16, 2, 19
    ]

    /// The studio that best explains where a title comes from.
    ///
    /// TMDB lists a title's production companies in no meaningful order, and
    /// many are small producers (a film's producer, not the studio behind it).
    /// So rather than take the first, in order of preference:
    ///  1. For a series, the streamer or network it's on.
    ///  2. A standalone label among its companies (Marvel Studios, Pixar).
    ///  3. The most specific curated hub one of its companies belongs to.
    ///  4. A well-known studio.
    ///  5. Failing all that, the first company that has a logo (reported as
    ///     not confident).
    static func best(companies: [ProductionCompany], networks: [Network], hubs: [CompanyHub]) -> (studio: PopsStudio, confident: Bool)? {
        let knownNetworks = Set(hubs.flatMap(\.networkIds)).union(streamerNetworkIDs)
        if let network = networks.first(where: { knownNetworks.contains($0.id) }) {
            return (PopsStudio(name: network.name, logoPath: network.logoPath,
                               originCountry: network.originCountry,
                               companyIds: [], networkIds: [network.id]), true)
        }

        var best: (studio: PopsStudio, tier: Int, size: Int, order: Int)?
        for (order, company) in companies.enumerated() {
            let candidate: (studio: PopsStudio, tier: Int, size: Int, order: Int)
            if labelCompanyIDs.contains(company.id) {
                candidate = (label(company, hubs: hubs), 0, 1, order)
            } else if let hub = smallestHub(containing: company.id, in: hubs) {
                candidate = (parent(hub, matchedLogo: company.logoPath, country: company.originCountry),
                             1, hub.companyIds.count, order)
            } else if majorCompanyIDs.contains(company.id) {
                candidate = (single(company), 2, 1, order)
            } else {
                continue
            }
            if let current = best,
               (current.tier, current.size, current.order) <= (candidate.tier, candidate.size, candidate.order) {
                continue
            }
            best = candidate
        }
        if let best { return (best.studio, true) }

        // Nothing recognised: the first company with a logo is a guess, and the
        // caller is told so, since the uploading channel is usually better.
        guard let fallback = companies.first(where: { $0.logoPath != nil }) ?? companies.first else { return nil }
        return (single(fallback), false)
    }

    /// A company as it came from a search, resolved the same way as a clip's,
    /// so searching "Marvel" or "Warner" and tapping a clip's logo agree.
    static func from(company: Company, hubs: [CompanyHub]) -> PopsStudio {
        let asProduction = ProductionCompany(id: company.id, name: company.name,
                                             logoPath: company.logoPath, originCountry: company.originCountry)
        if labelCompanyIDs.contains(company.id) {
            return label(asProduction, hubs: hubs)
        }
        if let hub = smallestHub(containing: company.id, in: hubs) {
            return parent(hub, matchedLogo: company.logoPath, country: company.originCountry)
        }
        return single(asProduction)
    }

    private static func smallestHub(containing id: Int, in hubs: [CompanyHub]) -> CompanyHub? {
        hubs.filter { $0.companyIds.contains(id) }.min { $0.companyIds.count < $1.companyIds.count }
    }

    /// A label shows as itself. If there's already a small hub for it (one
    /// made for it, not its parent's big one) that's used so names and
    /// follows line up; otherwise it's the company alone.
    private static func label(_ company: ProductionCompany, hubs: [CompanyHub]) -> PopsStudio {
        if let hub = smallestHub(containing: company.id, in: hubs), hub.companyIds.count <= 3 {
            return PopsStudio(name: hub.name, logoPath: company.logoPath, originCountry: company.originCountry,
                              companyIds: hub.companyIds, networkIds: hub.networkIds)
        }
        return single(company)
    }

    /// A group hub, without the labels under it (which have their own pages).
    private static func parent(_ hub: CompanyHub, matchedLogo: String?, country: String?) -> PopsStudio {
        let own = hub.companyIds.filter { !labelCompanyIDs.contains($0) }
        let holdsLabels = own.count != hub.companyIds.count
        return PopsStudio(
            name: hub.name,
            logoPath: matchedLogo,
            originCountry: country,
            companyIds: own.isEmpty ? hub.companyIds : own,
            networkIds: hub.networkIds,
            excludedCompanyIds: holdsLabels && !own.isEmpty ? labelCompanyIDs.sorted() : []
        )
    }

    private static func single(_ company: ProductionCompany) -> PopsStudio {
        PopsStudio(name: company.name, logoPath: company.logoPath,
                   originCountry: company.originCountry,
                   companyIds: [company.id], networkIds: [])
    }
}

// MARK: - Uploading channel

/// Who uploaded a clip. TMDB's production companies leave out distributors and
/// often list only a film's small producer, but official clips come from the
/// studio's own channel ("Searchlight Pictures", "Prime Video"), which YouTube
/// reports without a key.
actor ClipChannelLookup {
    static let shared = ClipChannelLookup()

    private var cache: [String: String?] = [:]

    func channelName(forVideo key: String) async -> String? {
        if let cached = cache[key] { return cached }
        guard let url = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(key)&format=json") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["author_name"] as? String else {
            return nil   // not remembered: a bad connection shouldn't stick
        }
        cache[key] = name
        return name
    }
}

/// A studio recognised from a channel's name.
private struct ChannelStudio {
    /// Matched against the channel name with everything but letters and digits
    /// removed. Short ones must be the whole name, so "max" doesn't claim
    /// "maxmovies" and "neon" doesn't claim "neonlights".
    let aliases: [String]
    let name: String
    let companyIds: [Int]
    let networkIds: [Int]
    var excludesLabels = false

    func matches(_ channel: String) -> Bool {
        aliases.contains { alias in
            alias.count <= 4 ? channel == alias : channel.contains(alias)
        }
    }

    /// Ordered most specific first: "Disney+" must be tried before "Disney".
    static let all: [ChannelStudio] = [
        ChannelStudio(aliases: ["disneyplus"], name: "Disney+", companyIds: [], networkIds: [2739]),
        ChannelStudio(aliases: ["paramountplus"], name: "Paramount+", companyIds: [], networkIds: [4330]),
        ChannelStudio(aliases: ["appletv"], name: "Apple TV+", companyIds: [], networkIds: [2552]),
        ChannelStudio(aliases: ["primevideo", "amazonprime"], name: "Prime Video", companyIds: [], networkIds: [1024]),
        ChannelStudio(aliases: ["netflix"], name: "Netflix", companyIds: [], networkIds: [213]),
        ChannelStudio(aliases: ["hulu"], name: "Hulu", companyIds: [], networkIds: [453]),
        ChannelStudio(aliases: ["peacock"], name: "Peacock", companyIds: [], networkIds: [3353]),
        ChannelStudio(aliases: ["hbo", "max"], name: "HBO", companyIds: [], networkIds: [49]),
        ChannelStudio(aliases: ["searchlight"], name: "Searchlight Pictures", companyIds: [127929, 43], networkIds: []),
        ChannelStudio(aliases: ["marvel"], name: "Marvel Studios", companyIds: [420], networkIds: []),
        ChannelStudio(aliases: ["pixar"], name: "Pixar", companyIds: [3], networkIds: []),
        ChannelStudio(aliases: ["lucasfilm", "starwars"], name: "Lucasfilm", companyIds: [1], networkIds: []),
        ChannelStudio(aliases: ["20thcentury", "20thcenturystudios"], name: "20th Century Studios", companyIds: [25], networkIds: []),
        ChannelStudio(aliases: ["disney", "waltdisney"], name: "Walt Disney Pictures", companyIds: [2, 7521], networkIds: [], excludesLabels: true),
        ChannelStudio(aliases: ["warnerbros", "wb"], name: "Warner Bros.", companyIds: [174, 17], networkIds: []),
        ChannelStudio(aliases: ["dccomics", "dcstudios"], name: "DC", companyIds: [429, 184898, 128064], networkIds: []),
        ChannelStudio(aliases: ["universal"], name: "Universal Pictures", companyIds: [33], networkIds: []),
        ChannelStudio(aliases: ["paramount"], name: "Paramount Pictures", companyIds: [4], networkIds: []),
        ChannelStudio(aliases: ["sonypictures", "columbiapictures", "sony"], name: "Sony Pictures", companyIds: [5, 34], networkIds: []),
        ChannelStudio(aliases: ["lionsgate"], name: "Lionsgate", companyIds: [1632], networkIds: []),
        ChannelStudio(aliases: ["a24"], name: "A24", companyIds: [41077], networkIds: []),
        ChannelStudio(aliases: ["neon"], name: "Neon", companyIds: [90733], networkIds: []),
        ChannelStudio(aliases: ["focusfeatures"], name: "Focus Features", companyIds: [10146], networkIds: []),
        ChannelStudio(aliases: ["blumhouse"], name: "Blumhouse", companyIds: [3172], networkIds: []),
        ChannelStudio(aliases: ["legendary"], name: "Legendary Pictures", companyIds: [923], networkIds: []),
        ChannelStudio(aliases: ["dreamworks"], name: "DreamWorks", companyIds: [521], networkIds: []),
        ChannelStudio(aliases: ["illumination"], name: "Illumination", companyIds: [6704], networkIds: []),
        ChannelStudio(aliases: ["amazonmgm", "metrogoldwynmayer", "mgm"], name: "Amazon MGM Studios", companyIds: [21, 20580], networkIds: []),
        ChannelStudio(aliases: ["newline"], name: "New Line Cinema", companyIds: [12], networkIds: [])
    ]

    /// "Disney+" and "Warner Bros." both reduce to plain letters and digits;
    /// the plus is spelled out first so Disney+ isn't read as Disney.
    static func normalised(_ channel: String) -> String {
        channel.lowercased()
            .replacingOccurrences(of: "+", with: "plus")
            .filter { $0.isLetter || $0.isNumber }
    }

    static func matching(channel: String) -> ChannelStudio? {
        let key = normalised(channel)
        guard !key.isEmpty else { return nil }
        return all.first { $0.matches(key) }
    }
}

// MARK: - Studio lookup

/// Resolves the studio behind a title, once per title per launch.
actor StudioLookup {
    static let shared = StudioLookup()

    private var cache: [String: PopsStudio?] = [:]

    /// `videoKey` is the clip being shown. It's only used when TMDB's own
    /// company list doesn't settle it.
    func studio(for media: MediaItem, videoKey: String? = nil) async -> PopsStudio? {
        let key = "\(media.resolvedMediaType.rawValue)-\(media.id)"
        if let cached = cache[key] { return cached }

        let companies: [ProductionCompany]
        let networks: [Network]
        switch media.resolvedMediaType {
        case .movie:
            let details = try? await TMDBService.shared.getMovieDetails(id: media.id)
            companies = details?.productionCompanies ?? []
            networks = []
        case .tv:
            let details = try? await TMDBService.shared.getTVShowDetails(id: media.id)
            companies = details?.productionCompanies ?? []
            networks = details?.networks ?? []
        case .person:
            companies = []
            networks = []
        }
        let hubs = await MainActor.run { StorageService.shared.companyHubs }
        let match = PopsStudio.best(companies: companies, networks: networks, hubs: hubs)

        if let match, match.confident {
            cache[key] = match.studio
            return match.studio
        }

        // TMDB left out the studio (or only listed a small producer), so go by
        // who uploaded the clip.
        if let videoKey,
           let channel = await ClipChannelLookup.shared.channelName(forVideo: videoKey),
           let seed = ChannelStudio.matching(channel: channel),
           let studio = await resolve(seed) {
            cache[key] = studio
            return studio
        }

        cache[key] = match?.studio
        return match?.studio
    }

    /// Fills in the logo and country a channel-matched studio needs from TMDB.
    private func resolve(_ seed: ChannelStudio) async -> PopsStudio? {
        var logoPath: String?
        var country: String?
        if seed.companyIds.isEmpty, let networkID = seed.networkIds.first {
            let network = try? await TMDBService.shared.getNetworkDetails(id: networkID)
            logoPath = network?.logoPath
            country = network?.originCountry
        } else {
            for id in seed.companyIds.prefix(2) {
                if let company = try? await TMDBService.shared.getCompanyDetails(id: id) {
                    logoPath = logoPath ?? company.logoPath
                    country = country ?? company.originCountry
                    if logoPath != nil { break }
                }
            }
        }
        return PopsStudio(
            name: seed.name,
            logoPath: logoPath,
            originCountry: country,
            companyIds: seed.companyIds,
            networkIds: seed.networkIds,
            excludedCompanyIds: seed.excludesLabels ? PopsStudio.labelIDs : []
        )
    }
}

// MARK: - Avatar

#if canImport(UIKit)
/// A studio logo trimmed to its visible artwork. Logos come with uneven
/// transparent margins, so drawing them as they are leaves the mark off-centre
/// in its circle; trimming first lets it sit in the middle. Also reports
/// whether the artwork is light, since a white logo is invisible on white.
actor StudioLogoArt {
    struct Result {
        let image: UIImage
        let isLight: Bool
    }

    static let shared = StudioLogoArt()
    private var cache: [URL: Result] = [:]

    func art(for url: URL) async -> Result? {
        if let cached = cache[url] { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = UIImage(data: data),
              let cgImage = source.cgImage else { return nil }
        let analysed = Self.trim(cgImage)
        let image = analysed.cropped.map { UIImage(cgImage: $0, scale: source.scale, orientation: .up) } ?? source
        let result = Result(image: image, isLight: analysed.isLight)
        cache[url] = result
        return result
    }

    /// Finds the box that holds the visible pixels, and how light they are.
    private static func trim(_ image: CGImage) -> (cropped: CGImage?, isLight: Bool) {
        let side = 96
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (nil, false) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        var minX = side, minY = side, maxX = -1, maxY = -1
        var luminance = 0.0, counted = 0.0
        for y in 0..<side {
            for x in 0..<side {
                let offset = (y * side + x) * 4
                let alpha = Double(pixels[offset + 3]) / 255
                guard alpha > 0.12 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                // Premultiplied: divide the alpha back out.
                let r = Double(pixels[offset]) / 255 / alpha
                let g = Double(pixels[offset + 1]) / 255 / alpha
                let b = Double(pixels[offset + 2]) / 255 / alpha
                luminance += (0.299 * r + 0.587 * g + 0.114 * b) * alpha
                counted += alpha
            }
        }
        guard maxX >= minX, maxY >= minY, counted > 0 else { return (nil, false) }
        let isLight = luminance / counted > 0.82

        // Scale the box back to the image, with a little breathing room.
        let scaleX = Double(image.width) / Double(side)
        let scaleY = Double(image.height) / Double(side)
        let pad = 1.0
        let x0 = max(0, (Double(minX) - pad) * scaleX)
        let y0 = max(0, (Double(minY) - pad) * scaleY)
        let x1 = min(Double(image.width), (Double(maxX) + 1 + pad) * scaleX)
        let y1 = min(Double(image.height), (Double(maxY) + 1 + pad) * scaleY)
        let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).integral

        // Already fills the image: nothing to trim.
        if rect.width >= Double(image.width) * 0.97, rect.height >= Double(image.height) * 0.97 {
            return (nil, isLight)
        }
        return (image.cropping(to: rect), isLight)
    }
}
#endif

/// A studio's logo on a round plate, with the mark centred. The plate is
/// white for dark and coloured logos and dark for light ones.
struct StudioLogoAvatar: View {
    let studio: PopsStudio
    let diameter: CGFloat

    #if canImport(UIKit)
    @State private var art: StudioLogoArt.Result?
    @State private var failed = false
    #endif

    private var logoURL: URL? {
        TMDBService.shared.imageURL(path: studio.logoPath, size: .logo)
    }

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            Circle().fill(plateIsDark ? Color(white: 0.13) : Color.white)

            if let art {
                Image(uiImage: art.image)
                    .resizable()
                    .scaledToFit()
                    .padding(diameter * 0.2)
            } else if logoURL == nil || failed {
                initialsView
            }
            #else
            Circle().fill(Color.white)
            if let url = logoURL {
                AsyncImageView(url: url, contentMode: .fit, cornerRadius: 0)
                    .padding(diameter * 0.2)
            } else {
                initialsView
            }
            #endif
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        #if canImport(UIKit)
        .task(id: logoURL) {
            art = nil
            failed = false
            guard let url = logoURL else { return }
            if let result = await StudioLogoArt.shared.art(for: url) {
                art = result
            } else {
                failed = true
            }
        }
        #endif
    }

    /// Light artwork goes on a dark plate, or it would vanish.
    private var plateIsDark: Bool {
        #if canImport(UIKit)
        return art?.isLight == true
        #else
        return false
        #endif
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: diameter * 0.32, weight: .bold))
            .foregroundStyle(plateIsDark ? .white : .black)
    }

    private var initials: String {
        studio.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

// MARK: - Profile

struct StudioProfileView: View {
    let studio: PopsStudio
    let onOpenTitle: (MediaItem) -> Void

    private enum Shelf: Hashable { case movies, shows }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var storage = StorageService.shared

    @State private var details: Company?
    @State private var shelf: Shelf = .movies
    @State private var movies: [MediaItem] = []
    @State private var shows: [MediaItem] = []
    @State private var movieTotal: Int?
    @State private var showTotal: Int?
    @State private var moviePage = 0
    @State private var showPage = 0
    @State private var moviePages = 1
    @State private var showPages = 1
    /// Shelves with a page request in flight, so scrolling can't start two at once.
    @State private var loadingShelves: Set<Shelf> = []
    @State private var didLoad = false
    @State private var showPops = false
    @State private var popsPick: MediaItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    init(studio: PopsStudio, onOpenTitle: @escaping (MediaItem) -> Void) {
        self.studio = studio
        self.onOpenTitle = onOpenTitle
        // A streamer has shows, not films, so it opens on those.
        _shelf = State(initialValue: studio.isNetworkOnly ? .shows : .movies)
    }

    private var hasMovies: Bool { !studio.companyIds.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 18)

                    if hasMovies {
                        shelfPicker
                    }

                    grid
                }
            }
            .background(Color.black.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle(studio.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard !didLoad else { return }
            didLoad = true
            async let info = companyDetails()
            async let firstMovies: Void = loadMore(.movies)
            async let firstShows: Void = loadMore(.shows)
            details = await info
            _ = await (firstMovies, firstShows)
        }
        .fullScreenCover(isPresented: $showPops, onDismiss: {
            guard let pick = popsPick else { return }
            popsPick = nil
            onOpenTitle(pick)
        }) {
            ClipsView(selectedItem: $popsPick, scope: .titles(popsTitles, label: studio.name))
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            StudioLogoAvatar(studio: studio, diameter: 96)

            VStack(spacing: 4) {
                Text(studio.name)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(handle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                if hasMovies {
                    stat(movieTotal, "Movies")
                    Divider().frame(height: 22).overlay(Color.white.opacity(0.2))
                }
                stat(showTotal, "Shows")
                if let country = details?.originCountry ?? studio.originCountry, !country.isEmpty {
                    Divider().frame(height: 22).overlay(Color.white.opacity(0.2))
                    stat(text: flag(for: country) ?? country, "Country")
                }
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                Button(action: toggleFollow) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isFollowing ? Color.white.opacity(0.14) : Color(red: 1, green: 0.17, blue: 0.33))
                        )
                }
                .buttonStyle(.plain)

                Button { showPops = true } label: {
                    Label("Pops", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .disabled(popsTitles.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)

            if let bio {
                Text(bio)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            if isFollowing {
                Text("Following puts \(studio.name) on your Browse page.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ value: Int?, _ label: String) -> some View {
        stat(text: value.map { $0.formatted(.number.notation(.compactName)) } ?? "–", label)
    }

    private func stat(text: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(text)
                .font(.headline.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 84)
    }

    private var handle: String {
        "@" + studio.name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private var bio: String? {
        if let text = details?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        if let hq = details?.headquarters, !hq.isEmpty {
            return "Based in \(hq)"
        }
        return nil
    }

    private func flag(for country: String) -> String? {
        let base: UInt32 = 127397
        let scalars = country.uppercased().unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
        guard country.count == 2, scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    // MARK: Shelves

    private var shelfPicker: some View {
        HStack(spacing: 0) {
            shelfTab(.movies, symbol: "film")
            shelfTab(.shows, symbol: "tv")
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
        }
    }

    private func shelfTab(_ value: Shelf, symbol: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { shelf = value }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(shelf == value ? .white : .white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    if shelf == value {
                        Capsule().fill(Color.white).frame(width: 44, height: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value == .movies ? "Movies" : "Shows")
    }

    @ViewBuilder
    private var grid: some View {
        let items = shelf == .movies ? movies : shows
        if items.isEmpty {
            VStack(spacing: 10) {
                if !didLoad || !loadingShelves.isEmpty {
                    ProgressView()
                } else {
                    Image(systemName: shelf == .movies ? "film" : "tv")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No \(shelf == .movies ? "movies" : "shows") yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(items) { item in
                    tile(item)
                        .onAppear {
                            if item.id == items.last?.id {
                                Task { await loadMore(shelf) }
                            }
                        }
                }
            }
            .padding(.top, 2)
        }
    }

    private func tile(_ item: MediaItem) -> some View {
        Button { onOpenTitle(item) } label: {
            Color.white.opacity(0.06)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    AsyncImageView(
                        url: TMDBService.shared.imageURL(path: item.posterPath, size: .medium),
                        contentMode: .fill,
                        cornerRadius: 0
                    )
                }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if let rating = item.voteAverage, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.8), radius: 3)
                            .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.displayTitle)
    }

    // MARK: Data

    /// Clips for the Pops button: the studio's most popular titles, alternating
    /// movies and shows.
    private var popsTitles: [MediaItem] {
        var mixed: [MediaItem] = []
        for index in 0..<max(movies.count, shows.count) {
            if index < movies.count { mixed.append(movies[index]) }
            if index < shows.count { mixed.append(shows[index]) }
        }
        return mixed
    }

    /// Loads the next page of a shelf. The page counter only moves once the
    /// request has succeeded, so a failed request is simply tried again.
    private func loadMore(_ which: Shelf) async {
        guard !loadingShelves.contains(which) else { return }
        loadingShelves.insert(which)
        defer { loadingShelves.remove(which) }

        switch which {
        case .movies:
            guard hasMovies, moviePage < moviePages else { return }
            let next = moviePage + 1
            guard let response = try? await TMDBService.shared.discoverMoviesByCompany(companyIds: studio.companyIds, page: next, excludingCompanyIds: studio.excludedCompanyIds) else { return }
            moviePage = next
            movies += response.results.filter { new in !movies.contains { $0.id == new.id } }
            movieTotal = response.totalResults
            moviePages = response.totalPages ?? next
        case .shows:
            guard showPage < showPages else { return }
            let next = showPage + 1
            // A streamer's shows come from the network; a studio's from the
            // companies that made them.
            let request: TMDBResponse<MediaItem>?
            if studio.companyIds.isEmpty {
                request = try? await TMDBService.shared.discoverTVByNetwork(networkIds: studio.networkIds, page: next)
            } else {
                request = try? await TMDBService.shared.discoverTVByCompany(companyIds: studio.companyIds, page: next, excludingCompanyIds: studio.excludedCompanyIds)
            }
            guard let response = request else { return }
            showPage = next
            shows += response.results.filter { new in !shows.contains { $0.id == new.id } }
            showTotal = response.totalResults
            showPages = response.totalPages ?? next
        }
    }

    /// The company's own description and country; a streamer has neither here.
    private func companyDetails() async -> Company? {
        guard let id = studio.companyIds.first else { return nil }
        return try? await TMDBService.shared.getCompanyDetails(id: id)
    }

    // MARK: Follow

    /// Hubs that are this studio: same name, or exactly the same companies.
    /// Matching on overlap would make following Marvel Studios also switch on
    /// the whole Disney hub.
    private var matchingHubs: [CompanyHub] {
        storage.companyHubs.filter {
            $0.syncKey == studio.name.lowercased()
                || (Set($0.companyIds) == Set(studio.companyIds) && Set($0.networkIds) == Set(studio.networkIds))
        }
    }

    /// Following is the Browse page's studio row: a followed studio is an
    /// enabled company hub that is exactly this one.
    private var isFollowing: Bool {
        matchingHubs.contains { $0.isEnabled }
    }

    private func toggleFollow() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        let hubs = matchingHubs
        if isFollowing {
            // Switched off rather than deleted: a curated hub would only come
            // back from the studio list on the next launch.
            for hub in hubs where hub.isEnabled {
                var disabled = hub
                disabled.isEnabled = false
                storage.updateCompanyHub(disabled)
            }
        } else if var existing = hubs.first {
            existing.isEnabled = true
            storage.updateCompanyHub(existing)
        } else {
            storage.addCompanyHub(CompanyHub(
                name: studio.name,
                logoPath: TMDBService.shared.imageURL(path: studio.logoPath, size: .logo)?.absoluteString,
                companyIds: studio.companyIds,
                networkIds: studio.networkIds
            ))
        }
    }
}
