//
//  PersonDetailView.swift
//  WatchGuide-MovieandTVtracker
//
//  Profile page for an actor, director, producer or any other credited person.
//

import SwiftUI

struct PersonDetailView: View {
    let personId: Int
    let personName: String
    let profilePath: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel: PersonDetailViewModel
    @State private var selectedItem: MediaItem?
    @State private var showsFullBiography = false
    @State private var showsNavigationTitle = false

    init(personId: Int, personName: String, profilePath: String?) {
        self.personId = personId
        self.personName = personName
        self.profilePath = profilePath
        _viewModel = StateObject(wrappedValue: PersonDetailViewModel(personId: personId))
    }

    private var horizontalInset: CGFloat {
        #if os(tvOS)
        return 80
        #else
        return horizontalSizeClass == .regular ? 32 : 20
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    PersonHeroHeader(
                        name: personName,
                        profilePath: profilePath ?? viewModel.person?.profilePath,
                        roles: viewModel.roleSummary,
                        lifespan: viewModel.lifespanSummary
                    )

                    biographySection
                    creditsContent
                    informationSection

                    RemoteBannerView(placement: .personDetail)
                        .padding(.horizontal, horizontalInset)
                }
                .padding(.bottom, 40)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 240
            } action: { _, isPastHeader in
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsNavigationTitle = isPastHeader
                }
            }
            .background { PersonAmbientBackground(profilePath: profilePath ?? viewModel.person?.profilePath) }
            .navigationTitle(showsNavigationTitle ? personName : "")
            .inlineNavTitleIfSupported()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .navigationDestination(for: PersonCreditShelf.self) { shelf in
                PersonCreditsGridView(shelf: shelf, selectedItem: $selectedItem)
            }
        }
        .colorScheme(.dark)
        .task {
            await viewModel.loadDetails()
        }
        .sheet(isPresented: $showsFullBiography) {
            PersonBiographySheet(name: personName, biography: viewModel.person?.biography ?? "")
        }
        .mediaDetailPresentation(item: $selectedItem)
    }

    // MARK: - About

    @ViewBuilder
    private var biographySection: some View {
        if let bio = viewModel.person?.biography?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
            let isLong = bio.count > 240
            VStack(alignment: .leading, spacing: 10) {
                PersonSectionHeader(title: "About")

                Button {
                    showsFullBiography = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(bio)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                        if isLong {
                            Text("More")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(!isLong)
            }
            .padding(.horizontal, horizontalInset)
        }
    }

    // MARK: - Credits

    @ViewBuilder
    private var creditsContent: some View {
        if viewModel.isLoading && viewModel.shelves.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        } else if viewModel.shelves.isEmpty {
            ContentUnavailableView(
                "No Credits",
                systemImage: "film.stack",
                description: Text("There aren't any movies or shows for \(personName) yet.")
            )
            .padding(.vertical, 24)
        } else {
            if !viewModel.knownFor.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    PersonSectionHeader(title: "Known For")
                        .padding(.horizontal, horizontalInset)
                    shelfScroller(spacing: 16) {
                        ForEach(viewModel.knownFor) { credit in
                            Button {
                                selectedItem = credit.item
                            } label: {
                                KnownForCard(credit: credit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            ForEach(viewModel.shelves) { shelf in
                creditShelf(shelf)
            }
        }
    }

    private func creditShelf(_ shelf: PersonCreditShelf) -> some View {
        let showsAll = shelf.credits.count > PersonCreditShelf.previewLimit
        return VStack(alignment: .leading, spacing: 12) {
            Group {
                if showsAll {
                    NavigationLink(value: shelf) {
                        PersonSectionHeader(title: shelf.title, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    PersonSectionHeader(title: shelf.title)
                }
            }
            .padding(.horizontal, horizontalInset)

            shelfScroller(spacing: 14) {
                ForEach(shelf.preview) { credit in
                    Button {
                        selectedItem = credit.item
                    } label: {
                        CreditPosterCard(credit: credit, width: CreditPosterCard.shelfWidth(horizontalSizeClass))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func shelfScroller<Content: View>(spacing: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: spacing) {
                content()
            }
            .scrollTargetLayout()
            #if os(tvOS)
            .padding(.vertical, 24)
            #endif
        }
        .contentMargins(.horizontal, horizontalInset, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }

    // MARK: - Information

    @ViewBuilder
    private var informationSection: some View {
        let rows = viewModel.informationRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                PersonSectionHeader(title: "Information")
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 16)
                            Text(row.value)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 12)

                        if index < rows.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: 760)
            }
            .padding(.horizontal, horizontalInset)
        }
    }
}

// MARK: - Hero

private struct PersonHeroHeader: View {
    let name: String
    let profilePath: String?
    let roles: String?
    let lifespan: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var portraitSize: CGFloat {
        #if os(tvOS)
        return 280
        #else
        return horizontalSizeClass == .regular ? 200 : 164
        #endif
    }

    var body: some View {
        VStack(spacing: 6) {
            PersonCutoutPortrait(profilePath: profilePath, size: portraitSize)
                .padding(.bottom, 14)

            Text(name)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Group {
                if let roles {
                    Text(roles)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                if let lifespan {
                    Text(lifespan)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .multilineTextAlignment(.center)
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.25), value: roles)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

/// The round portrait, with the person lifted out of their photo so the page
/// shows through behind them. Shows the plain photo until the cutout is ready,
/// and keeps it when Vision can't find a clear subject.
private struct PersonCutoutPortrait: View {
    let profilePath: String?
    let size: CGFloat

    @State private var cutout: CGImage?

    /// The untouched photo, top-anchored so heads stay in frame.
    private var photo: some View {
        ResilientAsyncImage(
            url: TMDBService.shared.imageURL(path: profilePath, size: .profile),
            maxPixelSize: size * 3
        ) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size, alignment: .top)
            } else {
                ZStack {
                    Circle().fill(.white.opacity(0.08))
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }

    var body: some View {
        ZStack {
            if let cutout {
                Circle()
                    .fill(.white.opacity(0.08))
                Image(decorative: cutout, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .transition(.opacity)
            } else {
                photo
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .task(id: profilePath) {
            cutout = nil
            guard let profilePath else { return }
            guard let image = await PersonCutoutService.shared.cutout(forProfilePath: profilePath) else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                cutout = image
            }
        }
    }
}

/// A soft wash of the portrait's colors behind the top of the page.
private struct PersonAmbientBackground: View {
    let profilePath: String?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black

            Color.clear
                .frame(height: 560)
                .overlay {
                    ResilientAsyncImage(
                        url: TMDBService.shared.imageURL(path: profilePath, size: .small),
                        maxPixelSize: 185
                    ) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                }
                .clipped()
                .blur(radius: 80, opaque: true)
                .opacity(0.55)
                .mask {
                    LinearGradient(
                        colors: [.black, .black.opacity(0.5), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Building Blocks

private struct PersonSectionHeader: View {
    let title: String
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.title2.weight(.bold))
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

private struct KnownForCard: View {
    let credit: PersonCredit

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isFocused) private var isFocused

    private var width: CGFloat {
        #if os(tvOS)
        return 500
        #else
        return horizontalSizeClass == .regular ? 340 : 280
        #endif
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .frame(width: width, height: width * 9 / 16)
                .overlay {
                    ResilientAsyncImage(
                        url: TMDBService.shared.imageURL(
                            path: credit.item.backdropPath ?? credit.item.posterPath,
                            size: .backdropSmall
                        ),
                        maxPixelSize: width * 2
                    ) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Rectangle().fill(.white.opacity(0.06))
                        }
                    }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 18, y: 10)
                .scaleEffect(isFocused ? 1.05 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(credit.item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(credit.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

private struct CreditPosterCard: View {
    let credit: PersonCredit
    let width: CGFloat

    @Environment(\.isFocused) private var isFocused

    static func shelfWidth(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        #if os(tvOS)
        return 200
        #else
        return sizeClass == .regular ? 150 : 118
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterImageView(
                posterPath: credit.item.posterPath,
                backdropPath: credit.item.backdropPath,
                size: .medium,
                mediaId: credit.item.id,
                mediaType: credit.item.resolvedMediaType,
                displayWidth: width
            )
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: sharedPosterCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: sharedPosterCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 14, y: 8)
            .scaleEffect(isFocused ? 1.06 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(credit.item.displayTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(credit.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - See All

private struct PersonCreditsGridView: View {
    let shelf: PersonCreditShelf
    @Binding var selectedItem: MediaItem?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var filter: MediaType?

    private var hasBothKinds: Bool {
        let kinds = Set(shelf.credits.map(\.item.resolvedMediaType))
        return kinds.contains(.movie) && kinds.contains(.tv)
    }

    /// Newest first; titles without a date are usually still in development, so they lead.
    private var credits: [PersonCredit] {
        shelf.credits
            .filter { filter == nil || $0.item.resolvedMediaType == filter }
            .sorted { ($0.item.displayDate ?? "9999") > ($1.item.displayDate ?? "9999") }
    }

    var body: some View {
        let width = CreditPosterCard.shelfWidth(horizontalSizeClass)

        ScrollView {
            VStack(spacing: 20) {
                if hasBothKinds {
                    Picker("Type", selection: $filter) {
                        Text("All").tag(MediaType?.none)
                        Text("Movies").tag(MediaType?.some(.movie))
                        Text("TV Shows").tag(MediaType?.some(.tv))
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: width, maximum: width), spacing: 16, alignment: .top)],
                    spacing: 24
                ) {
                    ForEach(credits) { credit in
                        Button {
                            selectedItem = credit.item
                        } label: {
                            CreditPosterCard(credit: credit, width: width)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(shelf.title)
        .inlineNavTitleIfSupported()
    }
}

private struct PersonBiographySheet: View {
    let name: String
    let biography: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(biography)
                    .font(.body)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationTitle(name)
            .inlineNavTitleIfSupported()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #elseif os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }
}

// MARK: - Models

/// A title the person worked on, with every role they had on it.
struct PersonCredit: Identifiable, Hashable {
    let item: MediaItem
    let roles: [String]

    var id: String { "\(item.resolvedMediaType.rawValue)-\(item.id)" }

    var subtitle: String {
        [roles.isEmpty ? nil : roles.joined(separator: ", "), item.year]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Collapses repeat entries for the same title (e.g. Producer and Executive Producer).
    static func merging(_ entries: [PersonCreditEntry], role: (PersonCreditEntry) -> String?) -> [PersonCredit] {
        var order: [String] = []
        var items: [String: MediaItem] = [:]
        var roles: [String: [String]] = [:]

        for entry in entries {
            let key = "\(entry.item.resolvedMediaType.rawValue)-\(entry.item.id)"
            if items[key] == nil {
                order.append(key)
                items[key] = entry.item
                roles[key] = []
            }
            if let value = role(entry)?.trimmingCharacters(in: .whitespaces), !value.isEmpty,
               roles[key]?.contains(value) == false {
                roles[key]?.append(value)
            }
        }

        return order.compactMap { key in
            items[key].map { PersonCredit(item: $0, roles: roles[key] ?? []) }
        }
    }
}

struct PersonCreditShelf: Identifiable, Hashable {
    static let previewLimit = 20

    let id: String
    let title: String
    /// Most popular first.
    let credits: [PersonCredit]

    var preview: ArraySlice<PersonCredit> { credits.prefix(Self.previewLimit) }
}

// MARK: - View Model

@MainActor
final class PersonDetailViewModel: ObservableObject {
    struct InformationRow {
        let label: String
        let value: String
    }

    let personId: Int

    @Published private(set) var person: Person?
    @Published private(set) var knownFor: [PersonCredit] = []
    @Published private(set) var shelves: [PersonCreditShelf] = []
    @Published private(set) var roleSummary: String?
    @Published private(set) var lifespanSummary: String?
    @Published private(set) var informationRows: [InformationRow] = []
    @Published private(set) var isLoading = true

    /// TMDB genre ids for talk and news shows, where people appear as themselves.
    private static let appearanceGenres: Set<Int> = [10767, 10763]

    private static let departmentOrder = ["Acting", "Directing", "Writing", "Creator", "Production"]

    private static let shelfTitles = [
        "Acting": "Acting",
        "Directing": "Directing",
        "Writing": "Writing",
        "Creator": "Created By",
        "Production": "Producing",
        "Sound": "Music",
        "Camera": "Cinematography",
        "Editing": "Editing",
        "Art": "Production Design",
        "Costume & Make-Up": "Costume & Make-Up",
        "Visual Effects": "Visual Effects",
        "Lighting": "Lighting",
        "Crew": "Additional Crew"
    ]

    private static let roleNouns = [
        "Acting": "Actor",
        "Directing": "Director",
        "Writing": "Writer",
        "Creator": "Creator",
        "Production": "Producer",
        "Sound": "Composer",
        "Camera": "Cinematographer",
        "Editing": "Editor",
        "Art": "Production Designer"
    ]

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()

    init(personId: Int) {
        self.personId = personId
    }

    func loadDetails() async {
        isLoading = true
        let pid = personId

        async let details = TMDBService.shared.getPersonDetails(id: pid)
        async let credits = TMDBService.shared.getPersonCombinedCredits(id: pid)

        var loadedPerson: Person?
        do {
            loadedPerson = try await details
        } catch {
            print("Error loading person details: \(error)")
        }

        var loadedCredits: PersonCombinedCredits?
        do {
            loadedCredits = try await credits
        } catch {
            print("Error loading person credits: \(error)")
        }

        person = loadedPerson
        informationRows = []
        buildFacts(from: loadedPerson)
        if let loadedCredits {
            buildCredits(from: loadedCredits, primaryDepartment: loadedPerson?.knownForDepartment)
        }
        isLoading = false
    }

    // MARK: Credits

    private func buildCredits(from response: PersonCombinedCredits, primaryDepartment: String?) {
        let isTitle: (PersonCreditEntry) -> Bool = { $0.item.mediaType == "movie" || $0.item.mediaType == "tv" }
        let allCast = (response.cast ?? []).filter(isTitle)
        let crew = (response.crew ?? []).filter(isTitle)

        // Talk-show and "Himself" appearances crowd out real roles; drop them
        // unless they are all this person has.
        let roleCast = allCast.filter { entry in
            let genres = Set(entry.item.genreIds ?? [])
            let character = entry.character?.lowercased() ?? ""
            return genres.isDisjoint(with: Self.appearanceGenres)
                && !character.contains("self")
        }
        let cast = roleCast.isEmpty ? allCast : roleCast

        var byDepartment: [String: [PersonCredit]] = [:]
        if !cast.isEmpty {
            byDepartment["Acting"] = PersonCredit.merging(cast) { $0.character }
        }
        for (department, entries) in Dictionary(grouping: crew, by: { $0.department ?? "Crew" }) {
            byDepartment[department] = PersonCredit.merging(entries) { $0.job }
        }

        let primary = primaryDepartment.flatMap { byDepartment[$0] == nil ? nil : $0 }
        let departments = byDepartment.keys.sorted { lhs, rhs in
            if lhs == primary { return true }
            if rhs == primary { return false }
            let lhsRank = Self.departmentOrder.firstIndex(of: lhs) ?? Int.max
            let rhsRank = Self.departmentOrder.firstIndex(of: rhs) ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return (byDepartment[lhs]?.count ?? 0) > (byDepartment[rhs]?.count ?? 0)
        }

        shelves = departments.compactMap { department in
            guard let credits = byDepartment[department], !credits.isEmpty else { return nil }
            return PersonCreditShelf(
                id: department,
                title: Self.shelfTitles[department] ?? department,
                credits: credits.sorted { ($0.item.popularity ?? 0) > ($1.item.popularity ?? 0) }
            )
        }

        // Known For: the most-rated titles from the person's main line of work.
        let knownForPool = byDepartment[primary ?? departments.first ?? ""] ?? []
        knownFor = Array(
            knownForPool
                .filter { $0.item.backdropPath != nil }
                .sorted { ($0.item.voteCount ?? 0) > ($1.item.voteCount ?? 0) }
                .prefix(10)
        )

        // "Actor, Producer, Director" — roles with real weight, primary first.
        let roles = departments
            .filter { department in
                department == primary || (byDepartment[department]?.count ?? 0) >= 3
            }
            .compactMap { Self.roleNouns[$0] }
        roleSummary = roles.isEmpty ? nil : roles.prefix(3).joined(separator: ", ")

        let titles = Set((allCast + crew).map { "\($0.item.resolvedMediaType.rawValue)-\($0.item.id)" })
        let movieCount = titles.filter { $0.hasPrefix("movie-") }.count
        let showCount = titles.count - movieCount
        let parts = [
            movieCount > 0 ? "\(movieCount) \(movieCount == 1 ? "movie" : "movies")" : nil,
            showCount > 0 ? "\(showCount) \(showCount == 1 ? "show" : "shows")" : nil
        ].compactMap { $0 }
        if !parts.isEmpty {
            informationRows.append(InformationRow(label: "Credits", value: parts.joined(separator: ", ")))
        }
    }

    // MARK: Facts

    private func buildFacts(from person: Person?) {
        guard let person else { return }

        let birth = person.birthday.flatMap(Self.apiDateFormatter.date(from:))
        let death = person.deathday.flatMap(Self.apiDateFormatter.date(from:))
        let age = birth.flatMap { Calendar.current.dateComponents([.year], from: $0, to: death ?? Date()).year }
        let birthYear = birth.map { Calendar.current.component(.year, from: $0) }
        let deathYear = death.map { Calendar.current.component(.year, from: $0) }

        if let birthYear, let deathYear {
            lifespanSummary = "\(birthYear)–\(deathYear)"
        } else if let age, death == nil {
            lifespanSummary = "Age \(age)"
        }

        var rows: [InformationRow] = []
        if let department = person.knownForDepartment {
            rows.append(InformationRow(label: "Known For", value: department))
        }
        if let birth {
            var value = Self.displayDateFormatter.string(from: birth)
            if death == nil, let age { value += " (age \(age))" }
            rows.append(InformationRow(label: "Born", value: value))
        }
        if let death {
            var value = Self.displayDateFormatter.string(from: death)
            if let age { value += " (aged \(age))" }
            rows.append(InformationRow(label: "Died", value: value))
        }
        if let place = person.placeOfBirth, !place.isEmpty {
            rows.append(InformationRow(label: "Birthplace", value: place))
        }
        informationRows.append(contentsOf: rows)
    }
}

#Preview {
    PersonDetailView(personId: 287, personName: "Brad Pitt", profilePath: nil)
}
