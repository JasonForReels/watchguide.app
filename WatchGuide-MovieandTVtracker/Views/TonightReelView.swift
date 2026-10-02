//
//  TonightReelView.swift
//  WatchGuide-MovieandTVtracker
//
//  Tonight answers one question: what should we watch right now? Instead of
//  more rows of posters, it shows one title at a time. Swipe right to save it,
//  left to skip, or up once you've watched it to keep a ticket stub.
//
//  The deck opens instantly with the user's own watchlist and last session's
//  personal picks, then trending fills in behind and fresh picks slot in after
//  the watchlist once they arrive. Every swipe can be undone.
//

import SwiftUI

enum TonightAction: Equatable { case skip, save, watched }

@MainActor
final class TonightReelModel: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable {
        case everything = "Everything", movies = "Movies", shows = "Shows"
        var id: String { rawValue }

        var taste: TasteRecommender.Kind {
            switch self {
            case .everything: return .any
            case .movies: return .movies
            case .shows: return .shows
            }
        }
    }

    /// What a swipe changed, so it can be reversed exactly.
    struct Swipe {
        let item: MediaItem
        let action: TonightAction
        let date: Date
        let addedToWatchlist: Bool
        let addedToWatched: Bool
        let wasLiked: Bool
    }

    @Published var deck: [MediaItem] = []
    @Published var isLoading = false
    @Published var failed = false
    @Published private(set) var history: [Swipe] = []
    @Published var kind: Kind = .everything {
        didSet { if oldValue != kind { restart() } }
    }

    private var page = 1
    private var seen = Set<String>()
    /// Bumped on every restart so results from an older kind are dropped.
    private var generation = 0

    static func key(_ item: MediaItem) -> String {
        "\(item.resolvedMediaType.rawValue)-\(item.id)"
    }

    func startIfNeeded() {
        if deck.isEmpty && !isLoading { restart() }
    }

    func restart() {
        generation += 1
        deck = []
        page = 1
        seen = []
        isLoading = false
        failed = false
        seed()
        Task { await loadMore() }
        Task { await blendFreshPicks() }
    }

    /// Everything we can show without the network: the watchlist, then the
    /// personal picks cached from last time.
    private func seed() {
        let today = String(ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: .withFullDate))
        let watchlist = StorageService.shared.wantToWatch
            .filter { saved in
                // Unreleased titles can't be watched tonight.
                guard let date = saved.releaseDate, date.count >= 10 else { return true }
                return String(date.prefix(10)) <= today
            }
            .map { $0.toMediaItem() }
        append(watchlist + TasteRecommender.shared.cached(kind: kind.taste))
    }

    func loadMore() async {
        guard !isLoading else { return }
        let gen = generation
        isLoading = true
        failed = false
        defer { if gen == generation { isLoading = false } }

        let tmdb = TMDBService.shared
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
            guard gen == generation else { return }
            page += 1
            append(items)
        } catch {
            guard gen == generation else { return }
            failed = deck.isEmpty
        }
    }

    /// Fresh personal picks go right after the watchlist, never above the card
    /// the user is looking at.
    private func blendFreshPicks() async {
        let gen = generation
        let picks = await TasteRecommender.shared.recommendations(kind: kind.taste, count: 15)
        guard gen == generation else { return }
        let fresh = eligible(picks)
        guard !fresh.isEmpty else { return }
        fresh.forEach { seen.insert(Self.key($0)) }
        let storage = StorageService.shared
        let onList = deck.prefix { storage.isInWantToWatch($0.id, mediaType: $0.resolvedMediaType) }.count
        let anchor = min(max(onList, deck.isEmpty ? 0 : 1), deck.count)
        deck.insert(contentsOf: fresh, at: anchor)
        failed = false
    }

    private func append(_ items: [MediaItem]) {
        let fresh = eligible(items)
        fresh.forEach { seen.insert(Self.key($0)) }
        deck.append(contentsOf: fresh)
    }

    private func eligible(_ items: [MediaItem]) -> [MediaItem] {
        let storage = StorageService.shared
        let taste = TasteRecommender.shared
        var batch = Set<String>()
        return items.filter { item in
            let key = Self.key(item)
            return item.posterPath != nil
                && matches(item)
                && !seen.contains(key)
                && batch.insert(key).inserted
                && !storage.isInWatched(item.id, mediaType: item.resolvedMediaType)
                && !storage.isInLiked(item.id, mediaType: item.resolvedMediaType)
                && !taste.isSkipped(item)
        }
    }

    private func matches(_ item: MediaItem) -> Bool {
        switch kind {
        case .everything: return item.resolvedMediaType != .person
        case .movies: return item.resolvedMediaType == .movie
        case .shows: return item.resolvedMediaType == .tv
        }
    }

    // MARK: Swipes

    func apply(_ action: TonightAction, to item: MediaItem) {
        let storage = StorageService.shared
        let saved = SavedMediaItem(from: item)
        let type = item.resolvedMediaType
        var addedToWatchlist = false
        var addedToWatched = false
        let wasLiked = storage.isInLiked(item.id, mediaType: type)

        switch action {
        case .skip:
            TasteRecommender.shared.noteSkipped(item)
        case .save:
            if !storage.isInWantToWatch(item.id, mediaType: type) {
                storage.addToWantToWatch(saved)
                addedToWatchlist = true
            }
        case .watched:
            // Swiping up means "I've seen it", whether or not a stub is kept.
            if !storage.isInWatched(item.id, mediaType: type) {
                storage.addToWatched(saved)
                addedToWatched = true
            }
        }

        history.append(Swipe(item: item, action: action, date: Date(),
                             addedToWatchlist: addedToWatchlist, addedToWatched: addedToWatched, wasLiked: wasLiked))
        if history.count > 30 { history.removeFirst() }

        let key = Self.key(item)
        deck.removeAll { Self.key($0) == key }
        if deck.count < 4 { Task { await loadMore() } }
    }

    /// Reverses the last swipe and puts the card back on top.
    @discardableResult
    func undo() -> Swipe? {
        guard let last = history.popLast() else { return nil }
        let storage = StorageService.shared
        let saved = SavedMediaItem(from: last.item)
        let type = last.item.resolvedMediaType

        switch last.action {
        case .skip:
            TasteRecommender.shared.unnoteSkipped(last.item)
        case .save:
            if last.addedToWatchlist { storage.removeFromWantToWatch(saved) }
        case .watched:
            let stubs = TicketStubStore.shared
            for stub in stubs.stubs where stub.mediaId == last.item.id && stub.mediaType == type && stub.watchedAt >= last.date {
                stubs.remove(stub)
            }
            if last.addedToWatched { storage.removeFromWatched(saved) }
            if !last.wasLiked, storage.isInLiked(last.item.id, mediaType: type) { storage.removeFromLiked(saved) }
        }

        deck.insert(last.item, at: 0)
        return last
    }
}

struct TonightReelView: View {
    @Binding var selectedItem: MediaItem?
    @StateObject private var model = TonightReelModel()
    @ObservedObject private var stubs = TicketStubStore.shared
    @State private var drag: CGSize = .zero
    @State private var pendingStub: MediaItem?
    @State private var showStubBox = false
    @State private var feedback: Feedback?
    /// True while a card is flying off; ignores further input so a quick
    /// double tap can't act on the next, unseen card.
    @State private var isExiting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Feedback: Equatable {
        enum Kind { case skip, save, watched, undo }
        let id = UUID()
        let kind: Kind
    }

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
                Button(action: undo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(model.history.isEmpty || isExiting)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showStubBox = true } label: {
                    Label("Ticket Stubs", systemImage: "ticket")
                }
                .badge(stubs.stubs.count)
            }
        }
        .sensoryFeedback(trigger: feedback) { _, new in
            switch new?.kind {
            case .skip: return .impact(weight: .light)
            case .save: return .success
            case .watched: return .impact(weight: .heavy)
            case .undo: return .impact(flexibility: .soft)
            case nil: return nil
            }
        }
        .task { model.startIfNeeded() }
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
            .onChanged { if !isExiting { drag = $0.translation } }
            .onEnded { value in
                guard !isExiting else { return }
                let t = value.predictedEndTranslation
                if t.width > 180 { act(.save, item) }
                else if t.width < -180 { act(.skip, item) }
                else if t.height < -220 { act(.watched, item) }
                else { withAnimation(WGMotion.bouncy) { drag = .zero } }
            }
    }
    #endif

    private func act(_ action: TonightAction, _ item: MediaItem) {
        guard !isExiting, top.map(TonightReelModel.key) == TonightReelModel.key(item) else { return }
        isExiting = true
        let exit: CGSize
        switch action {
        case .skip:
            exit = CGSize(width: -800, height: drag.height)
            feedback = Feedback(kind: .skip)
        case .save:
            exit = CGSize(width: 800, height: drag.height)
            feedback = Feedback(kind: .save)
        case .watched:
            exit = CGSize(width: drag.width, height: -1000)
            feedback = Feedback(kind: .watched)
        }
        withAnimation(WGMotion.resolved(WGMotion.smooth, reduceMotion: reduceMotion)) { drag = exit }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            model.apply(action, to: item)
            drag = .zero
            isExiting = false
            if action == .watched { pendingStub = item }
        }
    }

    private func undo() {
        guard !isExiting, let swipe = model.undo() else { return }
        feedback = Feedback(kind: .undo)
        // Bring the card back from the side it left.
        switch swipe.action {
        case .skip: drag = CGSize(width: -800, height: 0)
        case .save: drag = CGSize(width: 800, height: 0)
        case .watched: drag = CGSize(width: 0, height: -1000)
        }
        Task {
            // Let the off-screen position render first so the return animates.
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(WGMotion.resolved(WGMotion.bouncy, reduceMotion: reduceMotion)) { drag = .zero }
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
                Button("Try Again") { model.restart() }
            }
        } else {
            ContentUnavailableView {
                Label("You're All Caught Up", systemImage: "checkmark.circle")
            } actions: {
                Button("Show More") { Task { await model.loadMore() } }
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
            } else if let reason = TasteRecommender.shared.reason(for: item) {
                Label(reason, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Reel.accent)
                    .lineLimit(1)
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
