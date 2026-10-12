//
//  PopsSearchView.swift
//  WatchGuide-MovieandTVtracker
//
//  Search from inside Pops: type a title, a studio or a person and watch their
//  clips. A title opens a feed of its own clips followed by similar titles, a
//  person opens a feed of what they're known for, and a studio opens its
//  profile (which has its own Pops button). Results come through TMDBService,
//  so they're cached with everything else.
//

import SwiftUI

/// What the viewer chose, resolved far enough for Pops to act on it. Plain
/// data, so the Pops screen can hold one on every platform.
enum PopsSearchPick {
    /// A feed of these titles' clips, labelled with what was searched for.
    case feed(label: String, titles: [MediaItem])
    case studio(PopsStudio)
}

#if !os(tvOS)

struct PopsSearchView: View {
    let onPick: (PopsSearchPick) -> Void
    let onClose: () -> Void

    private struct Results {
        var titles: [MediaItem] = []
        var studios: [Company] = []
        var people: [Person] = []
        var isEmpty: Bool { titles.isEmpty && studios.isEmpty && people.isEmpty }
    }

    @State private var query = ""
    @State private var results = Results()
    @State private var isSearching = false
    /// The row being resolved after a tap, so it can show a spinner.
    @State private var resolvingID: String?
    @FocusState private var isFocused: Bool

    private let suggestions = ["Marvel", "Pixar", "Horror", "Zendaya", "A24", "Anime", "Christopher Nolan"]

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Color.accentColor.opacity(0.22), .clear],
                           center: .top, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                content
            }
        }
        .preferredColorScheme(.dark)
        .task { isFocused = true }
        .task(id: trimmed) { await search(for: trimmed) }
    }

    // MARK: Field

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.6))
                TextField("Search titles, studios, people", text: $query)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .modifier(SearchGlassCapsule())

            Button("Cancel", action: onClose)
                .font(.body)
                .foregroundStyle(.white)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if trimmed.count < 2 {
            suggestionsView
        } else if isSearching && results.isEmpty {
            VStack { ProgressView().tint(.white).padding(.top, 60); Spacer() }
        } else if results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.5))
                Text("No results for “\(trimmed)”")
                    .font(.headline)
                Text("Try a different spelling, or search for a studio or an actor.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.top, 70)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !results.studios.isEmpty {
                        header("Studios")
                        ForEach(results.studios) { studioRow($0) }
                    }
                    if !results.people.isEmpty {
                        header("People")
                        ForEach(results.people) { personRow($0) }
                    }
                    if !results.titles.isEmpty {
                        header("Titles")
                        ForEach(results.titles) { titleRow($0) }
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { query = suggestion } label: {
                        Text(suggestion)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .modifier(SearchGlassCapsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    // MARK: Rows

    private func row<Leading: View>(id: String, title: String, subtitle: String?,
                                    @ViewBuilder leading: () -> Leading,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if resolvingID == id {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(resolvingID != nil)
    }

    private func titleRow(_ media: MediaItem) -> some View {
        let kind = media.resolvedMediaType == .movie ? "Movie" : "Series"
        return row(id: "t\(media.id)",
                   title: media.displayTitle,
                   subtitle: [kind, media.year].compactMap { $0 }.joined(separator: " · ")) {
            AsyncImageView(url: TMDBService.shared.imageURL(path: media.posterPath, size: .small),
                           contentMode: .fill, cornerRadius: 6)
                .frame(width: 44, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } action: {
            Task { await pickTitle(media) }
        }
    }

    private func studioRow(_ company: Company) -> some View {
        // The same studio a clip from it would lead to: a company that belongs
        // to a curated hub (Warner Bros.) opens that hub, not the single company.
        let studio = PopsStudio.from(company: company, hubs: StorageService.shared.companyHubs)
        return row(id: "s\(company.id)",
                   title: studio.name,
                   subtitle: studio.originCountry.flatMap { $0.isEmpty ? nil : $0 }) {
            StudioLogoAvatar(studio: studio, diameter: 44)
        } action: {
            onPick(.studio(studio))
        }
    }

    private func personRow(_ person: Person) -> some View {
        row(id: "p\(person.id)",
            title: person.name,
            subtitle: person.knownForDepartment) {
            AsyncImageView(url: TMDBService.shared.imageURL(path: person.profilePath, size: .small),
                           contentMode: .fill, cornerRadius: 22)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        } action: {
            let titles = (person.knownFor ?? []).filter { $0.resolvedMediaType != .person }
            onPick(.feed(label: person.name, titles: titles))
        }
    }

    // MARK: Data

    private func search(for text: String) async {
        guard text.count >= 2 else {
            results = Results()
            isSearching = false
            return
        }
        isSearching = true
        // Wait for a pause in typing, so each keystroke isn't a request.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        async let multi = try? await TMDBService.shared.searchMulti(query: text)
        async let companies = try? await TMDBService.shared.searchCompanies(query: text)
        async let people = try? await TMDBService.shared.searchPerson(query: text)
        let (found, studios, persons) = await (multi, companies, people)
        guard !Task.isCancelled else { return }

        results = Results(
            titles: Array((found?.results ?? []).filter { $0.resolvedMediaType != .person }.prefix(12)),
            studios: Array((studios?.results ?? []).prefix(4)),
            // People with nothing to watch have no clips to show.
            people: Array((persons?.results ?? []).filter { !($0.knownFor ?? []).isEmpty }.prefix(4))
        )
        isSearching = false
    }

    /// The title first, then similar ones, so a title with a couple of clips
    /// still makes a feed worth swiping.
    private func pickTitle(_ media: MediaItem) async {
        resolvingID = "t\(media.id)"
        let similar: [MediaItem]
        switch media.resolvedMediaType {
        case .movie:
            similar = (try? await TMDBService.shared.getMovieRecommendations(id: media.id).results) ?? []
        case .tv:
            similar = (try? await TMDBService.shared.getTVShowRecommendations(id: media.id).results) ?? []
        case .person:
            similar = []
        }
        resolvingID = nil
        let more = similar.filter { $0.id != media.id }.prefix(14)
        onPick(.feed(label: media.displayTitle, titles: [media] + more))
    }
}

/// Liquid Glass where it exists, a thin material everywhere else.
private struct SearchGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.8))
        }
    }
}

#endif
