//
//  TonightReelView.swift
//  WatchGuide-MovieandTVtracker
//
//  Tonight answers one question: what should we watch right now? Instead of
//  more rows of posters, it shows one title at a time. Swipe right to save it,
//  left to skip, or up once you've watched it to keep a ticket stub.
//

import SwiftUI

@MainActor
final class TonightReelModel: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable {
        case everything = "Everything", movies = "Movies", shows = "Shows"
        var id: String { rawValue }
    }

    @Published var deck: [MediaItem] = []
    @Published var isLoading = false
    @Published var failed = false
    @Published var kind: Kind = .everything {
        didSet { if oldValue != kind { Task { await load(reset: true) } } }
    }

    private var page = 1
    private var seen = Set<Int>()

    func load(reset: Bool = false) async {
        if reset { deck = []; page = 1; seen = [] }
        guard !isLoading else { return }
        isLoading = true
        failed = false
        defer { isLoading = false }

        let tmdb = TMDBService.shared
        let storage = StorageService.shared
        do {
            let items: [MediaItem]
            switch kind {
            case .shows:
                items = try await tmdb.getTrending(mediaType: .tv, page: page).results
            case .movies:
                items = try await tmdb.getTrending(mediaType: .movie, page: page).results
            case .everything:
                async let movies = tmdb.getTrending(mediaType: .movie, page: page).results
                async let shows = tmdb.getTrending(mediaType: .tv, page: page).results
                let (m, s) = try await (movies, shows)
                items = zip(m, s).flatMap { [$0, $1] }
            }
            // First load: lead with GPT-5 Nano picks based on Liked + Watched.
            var personal: [MediaItem] = []
            if page == 1 {
                let recKind: TasteRecommender.Kind = kind == .movies ? .movies : kind == .shows ? .shows : .any
                personal = await TasteRecommender.shared.recommendations(kind: recKind, count: 15)
            }
            page += 1
            let fresh = (personal + items).filter { item in
                item.posterPath != nil
                    && !seen.contains(item.id)
                    && !storage.isInWatched(item.id, mediaType: item.resolvedMediaType)
                    && !storage.isInLiked(item.id, mediaType: item.resolvedMediaType)
            }
            fresh.forEach { seen.insert($0.id) }
            // Titles already on the watchlist come first: tonight could be the night.
            let personalIds = Set(personal.map(\.id))
            let onList = fresh.filter { storage.isInWantToWatch($0.id, mediaType: $0.resolvedMediaType) }
            let picks = fresh.filter { personalIds.contains($0.id) && !storage.isInWantToWatch($0.id, mediaType: $0.resolvedMediaType) }
            let rest = fresh.filter { !personalIds.contains($0.id) && !storage.isInWantToWatch($0.id, mediaType: $0.resolvedMediaType) }
            deck.append(contentsOf: onList + picks + rest)
        } catch {
            failed = deck.isEmpty
        }
    }

    func pop() {
        guard !deck.isEmpty else { return }
        deck.removeFirst()
        if deck.count < 4 { Task { await load() } }
    }
}

struct TonightReelView: View {
    @Binding var selectedItem: MediaItem?
    @StateObject private var model = TonightReelModel()
    @ObservedObject private var stubs = TicketStubStore.shared
    @State private var drag: CGSize = .zero
    @State private var pendingStub: MediaItem?
    @State private var showStubBox = false
    @State private var feedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var top: MediaItem? { model.deck.first }

    var body: some View {
        VStack(spacing: 20) {
            Picker("Show", selection: $model.kind) {
                ForEach(TonightReelModel.Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            deck
                .frame(maxHeight: .infinity)

            controls
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .background {
            PosterAmbience(url: TMDBService.shared.imageURL(path: top?.posterPath, size: .small))
        }
        .navigationTitle("Tonight")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showStubBox = true } label: {
                    Label("Ticket Stubs", systemImage: "ticket")
                }
                .badge(stubs.stubs.count)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: feedback)
        .task { if model.deck.isEmpty { await model.load() } }
        .sheet(item: $pendingStub) { item in
            NavigationStack {
                KeepStubSheet(item: item) { verdict, company, note in
                    stubs.tear(for: item, verdict: verdict, company: company, note: note)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showStubBox) {
            NavigationStack { StubBoxView() }
        }
    }

    // MARK: Deck

    private var deck: some View {
        GeometryReader { geo in
            ZStack {
                if model.deck.isEmpty {
                    emptyState
                } else {
                    let visible = Array(model.deck.prefix(3).enumerated())
                    ForEach(visible.reversed(), id: \.element.id) { index, item in
                        card(item, index: index, width: min(geo.size.width, geo.size.height * 0.667))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func card(_ item: MediaItem, index: Int, width: CGFloat) -> some View {
        TonightCard(item: item, drag: index == 0 ? drag : .zero)
            .frame(width: width)
            .scaleEffect(1 - CGFloat(index) * 0.04, anchor: .top)
            .offset(y: CGFloat(index) * 10)
            .opacity(index == 2 ? 0.6 : 1)
            .offset(index == 0 ? drag : .zero)
            .rotationEffect(.degrees(index == 0 && !reduceMotion ? Double(drag.width / 22) : 0))
            .zIndex(Double(3 - index))
            .allowsHitTesting(index == 0)
            .onTapGesture { selectedItem = item }
            #if !os(tvOS)
            .gesture(swipe(for: item))
            #endif
            .accessibilityActions {
                Button("Save for Later") { act(.save, item) }
                Button("Skip") { act(.skip, item) }
                Button("I Watched This") { act(.watched, item) }
            }
    }

    #if !os(tvOS)
    private func swipe(for item: MediaItem) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let t = value.predictedEndTranslation
                if t.width > 180 { act(.save, item) }
                else if t.width < -180 { act(.skip, item) }
                else if t.height < -220 { act(.watched, item) }
                else { withAnimation(WGMotion.bouncy) { drag = .zero } }
            }
    }
    #endif

    private enum Action { case skip, save, watched }

    private func act(_ action: Action, _ item: MediaItem) {
        let exit: CGSize
        switch action {
        case .skip:
            exit = CGSize(width: -800, height: drag.height)
        case .save:
            exit = CGSize(width: 800, height: drag.height)
            let storage = StorageService.shared
            if !storage.isInWantToWatch(item.id, mediaType: item.resolvedMediaType) {
                storage.addToWantToWatch(SavedMediaItem(from: item))
            }
        case .watched:
            exit = CGSize(width: drag.width, height: -1000)
            pendingStub = item
        }
        feedback += 1
        withAnimation(WGMotion.resolved(WGMotion.smooth, reduceMotion: reduceMotion)) { drag = exit }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            model.pop()
            drag = .zero
        }
    }

    // MARK: Controls

    private var controls: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 20) {
                circleButton("xmark", "Skip") { if let top { act(.skip, top) } }
                Button {
                    if let top { act(.watched, top) }
                } label: {
                    Label("Watched", systemImage: "ticket.fill")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(Reel.accent)
                circleButton("bookmark", "Save for Later") { if let top { act(.save, top) } }
            }
        }
        .disabled(top == nil)
    }

    private func circleButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isLoading {
            ProgressView()
        } else if model.failed {
            ContentUnavailableView {
                Label("Couldn't Load Picks", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") { Task { await model.load() } }
            }
        } else {
            ContentUnavailableView {
                Label("You're All Caught Up", systemImage: "checkmark.circle")
            } actions: {
                Button("Show More") { Task { await model.load() } }
            }
        }
    }
}

// MARK: - Card

private struct TonightCard: View {
    let item: MediaItem
    let drag: CGSize

    var body: some View {
        AsyncImageView(url: TMDBService.shared.imageURL(path: item.posterPath, size: .large), cornerRadius: 0)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay(alignment: .bottom) { caption }
            .overlay { swipeHint }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Double tap for details.")
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            if StorageService.shared.isInWantToWatch(item.id, mediaType: item.resolvedMediaType) {
                Label("On Your Watchlist", systemImage: "bookmark.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Reel.accent)
            }
            Text(item.displayTitle)
                .font(.title2.bold())
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(item.resolvedMediaType == .tv ? "Series" : "Movie")
                if let year = item.year { Text("·"); Text(year) }
                if let vote = item.voteAverage, vote > 0 {
                    Text("·")
                    Image(systemName: "star.fill").imageScale(.small)
                    Text(vote, format: .number.precision(.fractionLength(1)))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }

    /// A glass badge that fades in to show what letting go will do.
    @ViewBuilder
    private var swipeHint: some View {
        if let hint {
            Label(hint.title, systemImage: hint.symbol)
                .font(.title3.bold())
                .foregroundStyle(hint.color)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .opacity(min(max(hint.amount, 0), 1))
        }
    }

    private var hint: (title: String, symbol: String, color: Color, amount: Double)? {
        if drag.height < -40, abs(drag.width) < 60 { return ("Watched", "ticket.fill", Reel.accent, -drag.height / 160) }
        if drag.width > 20 { return ("Save", "bookmark.fill", Reel.save, drag.width / 140) }
        if drag.width < -20 { return ("Skip", "xmark", Reel.pass, -drag.width / 140) }
        return nil
    }
}

// MARK: - Keep stub sheet

struct KeepStubSheet: View {
    let item: MediaItem
    let onKeep: (TicketStub.Verdict, String, String) -> Void
    @State private var verdict: TicketStub.Verdict = .liked
    @State private var company = ""
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AsyncImageView(url: TMDBService.shared.imageURL(path: item.posterPath, size: .small), cornerRadius: 8)
                        .frame(width: 50, height: 75)
                    VStack(alignment: .leading) {
                        Text(item.displayTitle).font(.headline)
                        Text("Watched today").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Section("How Was It?") {
                Picker("Verdict", selection: $verdict) {
                    ForEach(TicketStub.Verdict.allCases) { v in
                        Label(v.label, systemImage: v.symbol).tag(v)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Details") {
                TextField("Watched with", text: $company)
                TextField("A note to remember it by", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }
        }
        .navigationTitle("Keep a Ticket Stub")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Not Now") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Keep") {
                    onKeep(verdict, company.trimmingCharacters(in: .whitespaces), note.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }
}
