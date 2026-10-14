//
//  ClipsView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

/// Which titles the Pops feed draws from.
enum PopsScope {
    case trending
    case titles([MediaItem], label: String)
}

/// Pops-wide viewing options.
private enum PopsFormat {
    /// True: only portrait clips. False: every format.
    static let verticalOnlyKey = "popsVerticalOnly"
}

/// A feed opened from search: these titles' clips, under the search term.
private struct SearchFeed: Identifiable {
    let id = UUID()
    let label: String
    let titles: [MediaItem]
}

struct ClipsView: View {
    @Binding var selectedItem: MediaItem?
    private let scope: PopsScope
    private let showsCloseButton: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ClipsFeedViewModel
    /// The page on screen. Only it gets a player: LazyVStack builds neighbours
    /// ahead of time, and their autoplaying players used to play audio over
    /// the visible clip.
    @State private var activeID: String?
    /// The studio whose profile is open, and a title picked there that should
    /// open once the profile has closed.
    @State private var openStudio: PopsStudio?
    @State private var pendingTitle: MediaItem?
    /// First-run setup, and the same flow reopened from the tune button.
    @AppStorage(PopsOnboarding.doneKey) private var onboardingDone = false
    @State private var showPersonalise = false
    /// The clip whose Atlas comment sheet is open; the feed shrinks above it.
    @State private var atlasClip: ClipFeedItem?
    /// When each clip's Atlas thread began, so reopening shows the same thread.
    @State private var threadStarts: [String: Date] = [:]
    /// Portrait only, or every format. Changing it rebuilds the feed.
    @AppStorage(PopsFormat.verticalOnlyKey) private var verticalOnly = false
    /// Search: the sheet, what was picked in it (acted on once it has closed,
    /// since one presentation can't replace another mid-dismiss), and the feed
    /// that opens from it.
    @State private var showSearch = false
    @State private var pendingSearchPick: PopsSearchPick?
    @State private var searchFeed: SearchFeed?
    @State private var searchFeedPick: MediaItem?
    /// Whether this view is holding the Atlas orb hidden; onAppear can fire
    /// more than once, and the hide is counted, so each view hides it once.
    @State private var orbIsHidden = false

    init(selectedItem: Binding<MediaItem?>, scope: PopsScope = .trending, showsCloseButton: Bool = true) {
        _selectedItem = selectedItem
        self.scope = scope
        self.showsCloseButton = showsCloseButton
        _viewModel = StateObject(wrappedValue: ClipsFeedViewModel(scope: scope))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                if viewModel.followsNothing {
                    followingEmptyView
                } else if viewModel.isLoading && viewModel.items.isEmpty {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                    errorView(message: errorMessage)
                } else {
                    // Pages run edge to edge like TikTok; each page keeps its own
                    // chrome clear of the status bar and the floating tab bar.
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.items) { item in
                                ClipsFeedPage(
                                    item: item,
                                    isActive: item.id == (activeID ?? viewModel.items.first?.id),
                                    isCovered: openStudio != nil || showPersonalise || showSearch || searchFeed != nil,
                                    isCompact: atlasClip != nil,
                                    safeArea: proxy.safeAreaInsets,
                                    onOpenStudio: { openStudio = $0 },
                                    onOpenAtlas: { openAtlas(for: item) },
                                    onOpenTitle: {
                                        selectedItem = item.media
                                        dismiss()
                                    }
                                )
                                .containerRelativeFrame([.horizontal, .vertical])
                                .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $activeID)
                    // A new feed starts from its first clip, not wherever the
                    // other one was scrolled to.
                    .id(viewModel.mode)
                    .scrollDisabled(atlasClip != nil)
                    .modifier(CompactFeedModifier(
                        clip: atlasClip,
                        size: proxy.size,
                        safeArea: proxy.safeAreaInsets
                    ))
                    .ignoresSafeArea()
                }

                if atlasClip == nil {
                    topBar
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onChange(of: activeID) { _, current in
            Task { await viewModel.loadMoreIfNeeded(currentID: current) }
        }
        .onChange(of: viewModel.mode) { _, _ in
            activeID = nil
        }
        #if !os(tvOS)
        .task {
            // The first time Pops opens, set it up before the viewer settles in.
            guard viewModel.offersModes, !onboardingDone else { return }
            try? await Task.sleep(for: .milliseconds(500))
            showPersonalise = true
        }
        .onChange(of: verticalOnly) { _, _ in
            viewModel.refreshIfPersonalisationChanged()
        }
        .fullScreenCover(isPresented: $showSearch, onDismiss: {
            // The search sheet has closed; now act on what was picked in it.
            guard let pick = pendingSearchPick else { return }
            pendingSearchPick = nil
            switch pick {
            case .studio(let studio):
                openStudio = studio
            case .feed(let label, let titles):
                searchFeed = SearchFeed(label: label, titles: titles)
            }
        }) {
            PopsSearchView(
                onPick: { pick in
                    pendingSearchPick = pick
                    showSearch = false
                },
                onClose: { showSearch = false }
            )
        }
        .fullScreenCover(item: $searchFeed, onDismiss: {
            guard let title = searchFeedPick else { return }
            searchFeedPick = nil
            selectedItem = title
        }) { feed in
            ClipsView(selectedItem: $searchFeedPick, scope: .titles(feed.titles, label: feed.label))
        }
        .fullScreenCover(isPresented: $showPersonalise) {
            PopsOnboardingView(isFirstRun: !onboardingDone) { changed in
                onboardingDone = true
                showPersonalise = false
                if changed { viewModel.refreshIfPersonalisationChanged() }
            }
        }
        #endif
        #if !os(tvOS)
        // Atlas sits at the top of each clip's action rail here instead.
        .onAppear {
            guard !orbIsHidden else { return }
            orbIsHidden = true
            AtlasDockState.shared.suppressOrb()
        }
        .onDisappear {
            guard orbIsHidden else { return }
            orbIsHidden = false
            AtlasDockState.shared.restoreOrb()
        }
        #endif
        #if !os(tvOS)
        .sheet(item: $atlasClip) { clip in
            AtlasCommentsSheet(media: clip.media, threadStart: threadStarts[clip.id] ?? .now)
                .presentationDetents([.fraction(CompactFeedModifier.sheetFraction), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        #endif
        .sheet(item: $openStudio, onDismiss: {
            guard let title = pendingTitle else { return }
            pendingTitle = nil
            selectedItem = title
            dismiss()
        }) { studio in
            StudioProfileView(studio: studio) { title in
                pendingTitle = title
                openStudio = nil
            }
        }
    }

    private func openAtlas(for item: ClipFeedItem) {
        if threadStarts[item.id] == nil {
            threadStarts[item.id] = .now
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            atlasClip = item
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Loading Pops...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    private var followingEmptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text("Follow studios to fill this feed")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("Open a studio's profile from any clip and tap Follow. Its movies and shows will show up here.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.selectMode(.forYou)
                }
            } label: {
                Text("Back to For You")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private func errorView(message: String) -> some View {
        let formatIsTheCause = viewModel.isEmptyBecauseVertical
        return VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.yellow)

            Text("Pops Unavailable")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))

            Button {
                if formatIsTheCause {
                    verticalOnly = false
                } else {
                    Task { await viewModel.reload() }
                }
            } label: {
                Text(formatIsTheCause ? "Show all formats" : "Try Again")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    #if !os(tvOS)
    /// Format (all, or portrait only) and, on the main feed, the setup flow.
    private func optionsMenu(includesPersonalise: Bool) -> some View {
        Menu {
            Section("Format") {
                Button {
                    verticalOnly = false
                } label: {
                    Label("All formats", systemImage: verticalOnly ? "rectangle" : "checkmark")
                }
                Button {
                    verticalOnly = true
                } label: {
                    Label("Vertical only", systemImage: verticalOnly ? "checkmark" : "rectangle.portrait")
                }
            }
            if includesPersonalise {
                Divider()
                Button {
                    showPersonalise = true
                } label: {
                    Label("Personalise…", systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            Image(systemName: verticalOnly ? "rectangle.portrait.fill" : "slider.horizontal.3")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(verticalOnly ? Color.accentColor : .white)
                .frame(width: 40, height: 40)
                .modifier(PopsGlassCircle())
        }
        .accessibilityLabel(verticalOnly ? "Options, vertical only" : "Options")
    }
    #endif

    /// No "Pops" heading: the tab bar already names the screen. The main feed
    /// shows the Following / For You switch; feeds opened on their own (a
    /// studio's, Marvel's) keep their label and a close button instead.
    @ViewBuilder
    private var topBar: some View {
        let label: String? = {
            if case .titles(_, let label) = scope { return label }
            return nil
        }()
        if label != nil || showsCloseButton || viewModel.offersModes {
            ZStack {
                if viewModel.offersModes {
                    PopsModeSwitch(mode: viewModel.mode) { new in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            viewModel.selectMode(new)
                        }
                    }
                }

                HStack {
                    #if !os(tvOS)
                    if viewModel.offersModes {
                        optionsMenu(includesPersonalise: true)
                    } else if let label {
                        Text(label)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4)
                    }
                    #else
                    if let label {
                        Text(label)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    #endif

                    Spacer()

                    #if !os(tvOS)
                    if viewModel.offersModes {
                        Button {
                            showSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .modifier(PopsGlassCircle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Search Pops")
                    } else {
                        // Studio and search feeds can switch format too.
                        optionsMenu(includesPersonalise: false)
                    }
                    #endif

                    if showsCloseButton {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.black.opacity(0.34), in: Circle())
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            )
        }
    }
}

/// Following | For You, drawn like the tab bar: a Liquid Glass capsule with a
/// dark pill that slides to the selected side, and the accent colour on its label.
private struct PopsModeSwitch: View {
    let mode: PopsFeedMode
    let onSelect: (PopsFeedMode) -> Void

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            segment("Following", for: .following)
            segment("For You", for: .forYou)
        }
        .padding(4)
        .modifier(PopsGlassCapsule())
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private func segment(_ title: String, for value: PopsFeedMode) -> some View {
        let isSelected = mode == value
        return Button {
            onSelect(value)
            #if canImport(UIKit) && !os(tvOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.black.opacity(0.38))
                            .matchedGeometryEffect(id: "selected", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The round version, for the tune button.
private struct PopsGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.8))
        }
    }
}

/// Liquid Glass where it exists, a thin material everywhere else.
private struct PopsGlassCapsule: ViewModifier {
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

private struct ClipsFeedPage: View {
    let item: ClipFeedItem
    let isActive: Bool
    /// True while something (the studio profile) covers the feed.
    let isCovered: Bool
    /// True while Atlas's comment sheet is up and the feed is shrunk above it.
    let isCompact: Bool
    let safeArea: EdgeInsets
    let onOpenStudio: (PopsStudio) -> Void
    let onOpenAtlas: () -> Void
    let onOpenTitle: () -> Void

    @State private var inWatchlist: Bool
    @State private var isLiked: Bool
    @State private var heartBurst = false
    @State private var isPaused = false
    @State private var studio: PopsStudio?
    /// Shared across every clip, so unmuting once keeps sound on as you swipe.
    @AppStorage("popsMuted") private var isMuted = false

    init(item: ClipFeedItem, isActive: Bool, isCovered: Bool, isCompact: Bool, safeArea: EdgeInsets,
         onOpenStudio: @escaping (PopsStudio) -> Void, onOpenAtlas: @escaping () -> Void,
         onOpenTitle: @escaping () -> Void) {
        self.item = item
        self.isActive = isActive
        self.isCovered = isCovered
        self.isCompact = isCompact
        self.safeArea = safeArea
        self.onOpenStudio = onOpenStudio
        self.onOpenAtlas = onOpenAtlas
        self.onOpenTitle = onOpenTitle
        let type = item.media.resolvedMediaType
        _inWatchlist = State(initialValue: StorageService.shared.isInWantToWatch(item.media.id, mediaType: type))
        _isLiked = State(initialValue: StorageService.shared.isInLiked(item.media.id, mediaType: type))
    }

    private var isVertical: Bool { item.isVertical }

    var body: some View {
        // Backdrop and player are overlays on a fixed-size base so their fill
        // modes can never widen the page past the screen.
        Color.black
            .overlay { clipBackground }
            .overlay { player }
            .clipped()
            .overlay {
                // Sits above the web view so taps reach us, never the YouTube UI.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { like(fromDoubleTap: true) }
                    .onTapGesture { togglePause() }
            }
            .overlay {
                ZStack {
                    Image(systemName: "play.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 10)
                        .opacity(isPaused ? 1 : 0)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 96))
                        .foregroundStyle(.white)
                        .shadow(radius: 12)
                        .scaleEffect(heartBurst ? 1 : 0.4)
                        .opacity(heartBurst ? 1 : 0)
                }
                .allowsHitTesting(false)
            }
            .overlay {
                overlayChrome
                    .opacity(isCompact ? 0 : 1)
                    .allowsHitTesting(!isCompact)
            }
            .onChange(of: isActive) { _, active in
                // A clip you paused starts fresh when you swipe back to it.
                if !active { isPaused = false }
            }
            .task(id: item.media.id) {
                studio = await StudioLookup.shared.studio(for: item.media, videoKey: item.video.key)
            }
    }

    private func togglePause() {
        withAnimation(.easeOut(duration: 0.15)) { isPaused.toggle() }
    }

    @ViewBuilder
    private var player: some View {
        if !isActive {
            // Off-screen pages show the clip's still, never a live player.
            AsyncImageView(
                // `oar2` is the frame at the video's own shape; `hqdefault` is
                // always 4:3 and would letterbox a portrait clip.
                url: URL(string: "https://i.ytimg.com/vi/\(item.video.key)/\(isVertical ? "oar2" : "hqdefault").jpg"),
                contentMode: isVertical ? .fill : .fit,
                cornerRadius: 0
            )
            .aspectRatio(isVertical ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: isVertical ? .fill : .fit)
        } else if isVertical {
            EmbeddedTrailerPlayer(
                videoKey: item.video.key,
                title: item.media.displayTitle,
                autoPlay: true,
                showsControls: false,
                loops: true,
                aspectRatio: 9.0 / 16.0,
                contentMode: .fill,
                cornerRadius: 0,
                isPaused: isPaused || isCovered,
                muted: isMuted,
                revealOnPlay: true
            )
        } else {
            EmbeddedTrailerPlayer(
                videoKey: item.video.key,
                title: item.media.displayTitle,
                autoPlay: true,
                showsControls: false,
                loops: true,
                aspectRatio: 16.0 / 9.0,
                contentMode: .fit,
                cornerRadius: 0,
                isPaused: isPaused || isCovered,
                muted: isMuted,
                revealOnPlay: true
            )
        }
    }

    private var overlayChrome: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: onOpenTitle) {
                        HStack(spacing: 6) {
                            Text(item.media.displayTitle)
                                .font(.system(size: 20, weight: .bold))
                                .lineLimit(2)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Text(item.media.resolvedMediaType == .movie ? "Movie" : "Series")
                        if let year = item.media.year {
                            Text("• \(year)")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))

                    Text(item.video.name)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .shadow(color: .black.opacity(0.6), radius: 6)

                rail
            }
            .padding(.leading, 16 + safeArea.leading)
            .padding(.trailing, 10 + safeArea.trailing)
            .padding(.bottom, safeArea.bottom + 16)
        }
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .frame(height: safeArea.bottom + 280)
                .allowsHitTesting(false)
        }
    }

    private var rail: some View {
        VStack(spacing: 18) {
            #if !os(tvOS)
            AtlasRailButton(onTap: onOpenAtlas)
                .padding(.bottom, 4)
            #endif

            avatar

            railButton(symbol: isLiked ? "heart.fill" : "heart",
                       title: isLiked ? "Liked" : "Like",
                       tint: isLiked ? .red : .white) {
                like(fromDoubleTap: false)
            }

            railButton(symbol: inWatchlist ? "bookmark.fill" : "bookmark",
                       title: inWatchlist ? "Saved" : "Save",
                       tint: inWatchlist ? .yellow : .white) {
                StorageService.shared.toggleWantToWatch(SavedMediaItem(from: item.media))
                inWatchlist.toggle()
                haptic()
            }

            railButton(symbol: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       title: isMuted ? "Muted" : "Sound",
                       tint: .white) {
                isMuted.toggle()
                haptic()
            }

            #if !os(tvOS)
            ShareLink(item: "https://www.youtube.com/watch?v=\(item.video.key)",
                      subject: Text(item.media.displayTitle)) {
                railLabel(symbol: "arrowshape.turn.up.right.fill", title: "Share", tint: .white)
            }
            #endif
        }
    }

    /// The studio's logo, TikTok-profile style, opening its profile. Until the
    /// studio is known (or when TMDB lists none) it's the poster, opening the title.
    @ViewBuilder
    private var avatar: some View {
        if let studio {
            Button { onOpenStudio(studio) } label: {
                StudioLogoAvatar(studio: studio, diameter: 48)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(studio.name) profile")
        } else {
            Button(action: onOpenTitle) {
                AsyncImageView(
                    url: TMDBService.shared.imageURL(path: item.media.posterPath, size: .small),
                    cornerRadius: 24
                )
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.media.displayTitle)")
        }
    }

    private func like(fromDoubleTap: Bool) {
        let storage = StorageService.shared
        if fromDoubleTap {
            // Double tap only ever likes, as on TikTok; the heart button unlikes.
            if !isLiked {
                storage.toggleLiked(SavedMediaItem(from: item.media))
                isLiked = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { heartBurst = true }
            Task {
                try? await Task.sleep(nanoseconds: 650_000_000)
                withAnimation(.easeOut(duration: 0.25)) { heartBurst = false }
            }
        } else {
            storage.toggleLiked(SavedMediaItem(from: item.media))
            isLiked.toggle()
        }
        haptic()
    }

    private func haptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    @ViewBuilder
    private var clipBackground: some View {
        ZStack {
            AsyncImageView(
                url: TMDBService.shared.imageURL(path: item.media.backdropPath ?? item.media.posterPath, size: .backdrop),
                contentMode: .fill,
                cornerRadius: 0
            )
            .blur(radius: 30)
            .scaleEffect(1.3)
            .overlay(Color.black.opacity(0.55))
        }
    }

    private func railButton(symbol: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            railLabel(symbol: symbol, title: title, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func railLabel(symbol: String, title: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: .black.opacity(0.5), radius: 4)
                .frame(width: 48, height: 40)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3)
        }
    }
}

private struct ClipFeedItem: Identifiable {
    let media: MediaItem
    let video: Video
    /// True when the video itself is portrait (measured, not guessed from its
    /// title). Portrait clips fill the screen; the rest are shown whole,
    /// never cropped.
    let isPortrait: Bool

    var id: String {
        "\(media.id)-\(video.id)"
    }

    var isVertical: Bool {
        if isPortrait { return true }
        let name = video.name.lowercased()
        return ["#shorts", "vertical", "tiktok"].contains { name.contains($0) }
    }
}

/// Shrinks the feed into the space above Atlas's comment sheet, the way a
/// video steps up above its comments: the clip itself (not the page around a
/// landscape clip) is fitted into that space and rounded.
private struct CompactFeedModifier: ViewModifier {
    static let sheetFraction: CGFloat = 0.62

    let clip: ClipFeedItem?
    let size: CGSize
    let safeArea: EdgeInsets

    func body(content: Content) -> some View {
        let fullWidth = size.width + safeArea.leading + safeArea.trailing
        let fullHeight = size.height + safeArea.top + safeArea.bottom
        let space = max(80, fullHeight * (1 - Self.sheetFraction) - safeArea.top - 16)
        let clipHeight = (clip?.isVertical ?? true) ? fullHeight : fullWidth * 9 / 16
        let scale = clip == nil ? 1 : min(1, space / clipHeight)
        let centreY = safeArea.top + 8 + space / 2
        let offset = clip == nil ? 0 : centreY - fullHeight / 2

        content
            .scaleEffect(scale)
            .offset(y: offset)
            .mask {
                if clip != nil {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .frame(width: fullWidth * scale, height: clipHeight * scale)
                        .position(x: fullWidth / 2, y: centreY)
                } else {
                    Rectangle()
                }
            }
            // Swiping the sheet away clears `clip` outside any animation, so
            // the spring lives here to bring the feed back smoothly.
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: clip?.id)
    }
}

/// The two feeds on the main Pops tab. Studio and Marvel feeds have only one.
private enum PopsFeedMode: String {
    case forYou
    case following
}

@MainActor
private final class ClipsFeedViewModel: ObservableObject {
    /// Everything one feed needs, kept per mode so switching back and forth
    /// neither loses your place's clips nor mixes the two feeds up.
    private struct FeedState {
        var items: [ClipFeedItem] = []
        /// Clips found but not shown yet. Each batch is drawn from here, so a
        /// refill that finds plenty doesn't have to be fetched again.
        var pool: [ClipFeedItem] = []
        var seenClipIDs: Set<String> = []
        /// Titles shown most recently, so the same one never comes round twice
        /// in a short stretch.
        var recentMediaIDs: [Int] = []
        var titlesFetched = false
        var hasLoaded = false
        var isLoading = false
        var isLoadingMore = false
        var errorMessage: String?
        /// What the feed was built from; Following is rebuilt when it changes.
        var signature = ""
        /// Bumped by every reload. A load that finishes after its feed has been
        /// rebuilt (the format was flipped, say) sees a different number and
        /// drops what it found, instead of mixing it into the new feed.
        var generation = 0
    }

    private typealias Source = () async throws -> TMDBResponse<MediaItem>

    @Published private var current = FeedState()
    @Published private(set) var mode: PopsFeedMode

    private var stash: [PopsFeedMode: FeedState] = [:]
    private let scope: PopsScope

    private static let modeKey = "popsFeedMode"
    private static let firstBatch = 8
    private static let laterBatch = 10
    /// Unseen clips to keep ahead of whoever is scrolling.
    private static let lookahead = 4
    private static let spacing = 6

    init(scope: PopsScope) {
        self.scope = scope
        if case .trending = scope,
           let raw = UserDefaults.standard.string(forKey: Self.modeKey),
           let saved = PopsFeedMode(rawValue: raw) {
            mode = saved
        } else {
            mode = .forYou
        }
    }

    var items: [ClipFeedItem] { current.items }
    var isLoading: Bool { current.isLoading }
    var errorMessage: String? { current.errorMessage }
    /// Following, with no studio followed: nothing to show, and a reason to.
    var followsNothing: Bool { mode == .following && Self.followedHubs().isEmpty }
    var offersModes: Bool {
        if case .trending = scope { return true }
        return false
    }

    // MARK: State by mode

    private func state(for mode: PopsFeedMode) -> FeedState {
        mode == self.mode ? current : (stash[mode] ?? FeedState())
    }

    /// Applies a change to a feed even if the viewer has switched to the
    /// other one while it was loading.
    private func update(_ mode: PopsFeedMode, _ change: (inout FeedState) -> Void) {
        if mode == self.mode {
            change(&current)
        } else {
            var other = stash[mode] ?? FeedState()
            change(&other)
            stash[mode] = other
        }
    }

    /// What a feed was built from; when this changes the feed is stale.
    private static func signature(for mode: PopsFeedMode) -> String {
        let format = verticalOnly ? "|vertical" : ""
        switch mode {
        case .following:
            return followedHubs().map(\.id).sorted().joined(separator: ",") + format
        case .forYou:
            return PopsInterest.selected().map(\.rawValue).sorted().joined(separator: ",") + format
        }
    }

    /// Portrait clips only. Read when needed rather than stored, so the menu's
    /// choice is always the one a refill uses.
    private static var verticalOnly: Bool {
        UserDefaults.standard.bool(forKey: PopsFormat.verticalOnlyKey)
    }

    /// For the screen: nothing to show *because* of the format choice.
    var isEmptyBecauseVertical: Bool { items.isEmpty && Self.verticalOnly }

    /// After the setup flow: rebuild the feed on screen if its inputs changed.
    /// The other feed is checked when the viewer switches to it.
    func refreshIfPersonalisationChanged() {
        guard current.signature != Self.signature(for: mode) else { return }
        Task { await reload() }
    }

    // MARK: Loading

    func selectMode(_ new: PopsFeedMode) {
        guard offersModes, new != mode else { return }
        stash[mode] = current
        mode = new
        current = stash.removeValue(forKey: new) ?? FeedState()
        UserDefaults.standard.set(new.rawValue, forKey: Self.modeKey)

        let upToDate = current.hasLoaded && current.signature == Self.signature(for: new)
        if !upToDate {
            Task { await reload() }
        }
    }

    func loadIfNeeded() async {
        guard !current.hasLoaded, !current.isLoading else { return }
        await reload()
    }

    func reload() async {
        let mode = self.mode
        let generation = state(for: mode).generation + 1
        update(mode) {
            $0 = FeedState()
            $0.generation = generation
            $0.isLoading = true
            $0.signature = Self.signature(for: mode)
        }

        await appendBatch(mode: mode, count: Self.firstBatch, generation: generation)

        // Rebuilt again while this was loading: the newer load owns the feed.
        guard state(for: mode).generation == generation else { return }
        update(mode) { feed in
            if feed.items.isEmpty {
                // Following with nobody followed has its own explanation.
                feed.errorMessage = (mode == .following && Self.followedHubs().isEmpty)
                    ? nil
                    : (Self.verticalOnly
                        ? "No vertical clips turned up. Studios rarely publish them to the movie database, so there are few."
                        : "No clips were found right now.")
            } else {
                feed.hasLoaded = true
            }
            feed.isLoading = false
        }
    }

    /// Called as the viewer moves through the feed; tops it up before they
    /// reach the end, so it never runs out.
    func loadMoreIfNeeded(currentID: String?) async {
        let mode = self.mode
        let feed = state(for: mode)
        guard feed.hasLoaded, !feed.isLoadingMore, let currentID,
              let index = feed.items.firstIndex(where: { $0.id == currentID }),
              index >= feed.items.count - Self.lookahead else { return }
        let generation = feed.generation
        update(mode) { $0.isLoadingMore = true }
        await appendBatch(mode: mode, count: Self.laterBatch, generation: generation)
        guard state(for: mode).generation == generation else { return }
        update(mode) { $0.isLoadingMore = false }
    }

    // MARK: Batches

    private func appendBatch(mode: PopsFeedMode, count: Int, generation: Int) async {
        var rounds = 0
        // Portrait clips are scarce, so look further before giving up on them.
        let maxRounds = Self.verticalOnly ? 6 : 3
        while state(for: mode).pool.count < count, canRefill(mode), rounds < maxRounds {
            rounds += 1
            await refillPool(mode: mode, generation: generation)
            guard state(for: mode).generation == generation else { return }
        }
        let feed = state(for: mode)
        guard feed.generation == generation, !feed.pool.isEmpty else { return }

        let batch = Array(Self.order(feed.pool, avoiding: feed.recentMediaIDs).prefix(count))
        let batchIDs = Set(batch.map(\.id))
        update(mode) { feed in
            feed.pool.removeAll { batchIDs.contains($0.id) }
            feed.items.append(contentsOf: batch)
            feed.seenClipIDs.formUnion(batchIDs)
            feed.recentMediaIDs = Array((feed.recentMediaIDs + batch.map { $0.media.id }).suffix(Self.spacing * 2))
        }
    }

    private func canRefill(_ mode: PopsFeedMode) -> Bool {
        switch scope {
        case .trending: return true
        case .titles: return !state(for: mode).titlesFetched
        }
    }

    private func refillPool(mode: PopsFeedMode, generation: Int) async {
        let candidates: [MediaItem]
        switch scope {
        case .trending:
            let count = state(for: mode).items.isEmpty ? 14 : 20
            candidates = mode == .following
                ? await Self.followingCandidates(count: count)
                : await Self.forYouCandidates(count: count)
        case .titles(let titles, _):
            update(mode) { $0.titlesFetched = true }
            candidates = Array(titles.shuffled().prefix(40))
        }

        let videosByTitle = await Self.fetchVideos(for: candidates)
        let feed = state(for: mode)
        let known = feed.seenClipIDs.union(feed.pool.map(\.id))
        let verticalOnly = Self.verticalOnly
        let allowedTypes: Set<String> = ["clip", "teaser", "trailer"]

        var found: [(MediaItem, Video)] = []
        for media in candidates {
            let usable = (videosByTitle[media.id] ?? []).filter { video in
                // Portrait clips are mostly social cuts that studios file as
                // featurettes or behind-the-scenes, so that mode looks at every type.
                video.site.caseInsensitiveCompare("YouTube") == .orderedSame &&
                (verticalOnly || allowedTypes.contains(video.type.lowercased())) &&
                (verticalOnly || !video.name.localizedCaseInsensitiveContains("featurette")) &&
                !video.isRedBand &&
                !known.contains("\(media.id)-\(video.id)")
            }
            // A couple per title is plenty; the shuffle spreads them out.
            for video in usable.shuffled().prefix(verticalOnly ? 5 : 2) {
                found.append((media, video))
            }
        }

        let portrait = await Self.portraitAmong(found.map { $0.1.key })
        if verticalOnly {
            found = found.filter { portrait.contains($0.1.key) }
        }
        let clips = found.map { media, video in
            ClipFeedItem(media: media, video: video, isPortrait: portrait.contains(video.key))
        }
        // The feed may have been rebuilt while this was fetching.
        guard state(for: mode).generation == generation else { return }
        update(mode) { $0.pool.append(contentsOf: clips) }
    }

    // MARK: Ordering

    /// A weighted shuffle, so the order is different every time, with portrait
    /// and short clips more likely to come up early; then spaced so no title
    /// repeats within `spacing` clips.
    private static func order(_ clips: [ClipFeedItem], avoiding recent: [Int]) -> [ClipFeedItem] {
        func weight(_ clip: ClipFeedItem) -> Double {
            if clip.isVertical { return 3 }
            switch clip.video.type.lowercased() {
            case "clip": return 2
            case "teaser": return 1.2
            default: return 1
            }
        }
        // Efraimidis–Spirakis: sorting by u^(1/w) draws a weighted random order.
        var remaining = clips
            .map { (clip: $0, key: pow(Double.random(in: 0.0001..<1), 1 / weight($0))) }
            .sorted { $0.key > $1.key }
            .map(\.clip)

        var ordered: [ClipFeedItem] = []
        var window = Array(recent.suffix(spacing))
        while !remaining.isEmpty {
            let index = remaining.firstIndex { !window.contains($0.media.id) } ?? 0
            let next = remaining.remove(at: index)
            ordered.append(next)
            window = Array((window + [next.media.id]).suffix(spacing))
        }
        return ordered
    }

    // MARK: Sources

    private static let movieGenres = [28, 12, 16, 35, 80, 18, 14, 27, 9648, 10749, 878, 53]
    private static let tvGenres = [10759, 16, 35, 80, 18, 9648, 10765, 10768]

    /// Runs the sources side by side; a source that fails just contributes nothing.
    private static func gather(_ sources: [Source]) async -> [MediaItem] {
        await withTaskGroup(of: [MediaItem].self) { group in
            for source in sources {
                group.addTask { (try? await source().results) ?? [] }
            }
            var all: [MediaItem] = []
            for await results in group { all += results }
            return all
        }
    }

    /// One of each title, no people, and nothing the viewer has already passed on.
    private static func unique(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<Int>()
        return items.filter {
            $0.resolvedMediaType != .person
                && !TasteRecommender.shared.isSkipped($0)
                && seen.insert($0.id).inserted
        }
    }

    /// Titles from a few randomly chosen sources, each at a random depth, so
    /// the feed reaches past whatever is on top.
    private static func randomCandidates(count: Int, sourceCount: Int) async -> [MediaItem] {
        let tmdb = TMDBService.shared
        let kids = StorageService.shared.settings.isKidsProfile

        let sources: [Source]
        if kids {
            sources = [
                { try await tmdb.discoverKidsMovies(page: .random(in: 1...6)) },
                { try await tmdb.discoverKidsTV(page: .random(in: 1...6)) }
            ]
        } else {
            sources = [
                { try await tmdb.getTrending(mediaType: .movie, timeWindow: "day", page: .random(in: 1...3)) },
                { try await tmdb.getTrending(mediaType: .tv, timeWindow: "day", page: .random(in: 1...3)) },
                { try await tmdb.getTrending(mediaType: .movie, timeWindow: "week", page: .random(in: 1...6)) },
                { try await tmdb.getTrending(mediaType: .tv, timeWindow: "week", page: .random(in: 1...6)) },
                { try await tmdb.getPopularMovies(page: .random(in: 1...15)) },
                { try await tmdb.getPopularTV(page: .random(in: 1...15)) },
                { try await tmdb.getTopRatedMovies(page: .random(in: 1...12)) },
                { try await tmdb.getTopRatedTV(page: .random(in: 1...12)) },
                { try await tmdb.getNowPlayingMovies(page: .random(in: 1...5)) },
                { try await tmdb.getOnTheAirTV(page: .random(in: 1...5)) },
                { try await tmdb.getUpcomingMovies(page: .random(in: 1...3)) },
                { try await tmdb.discoverMovies(genres: [movieGenres.randomElement()!], page: .random(in: 1...8)) },
                { try await tmdb.discoverTV(genres: [tvGenres.randomElement()!], page: .random(in: 1...8)) }
            ]
        }

        let found = await gather(Array(sources.shuffled().prefix(sourceCount)))
        return Array(unique(found.shuffled()).prefix(count))
    }

    /// For You: about two thirds from what the viewer's own taste points to,
    /// one third from the open pool, so it keeps surprising them. Likes and
    /// saves made in Pops count immediately, since they go to the same lists.
    private static func forYouCandidates(count: Int) async -> [MediaItem] {
        let tmdb = TMDBService.shared
        let storage = StorageService.shared

        // Likes count double; a few random seeds give a different slice of
        // taste each time.
        var seenSeeds = Set<Int>()
        let seedPool = storage.liked + storage.liked + storage.watched + storage.wantToWatch
        let seeds = Array(seedPool.shuffled().filter { seenSeeds.insert($0.mediaId).inserted }.prefix(3))
        let picks = Array(TasteRecommender.shared.cached().shuffled().prefix(10))

        // What they said they're into during setup: a couple of those genres
        // each time, at random depths.
        let interestSources: [Source] = PopsInterest.selected().shuffled().prefix(2).flatMap { interest -> [Source] in
            [
                { try await tmdb.discoverMovies(genres: [interest.movieGenre], page: .random(in: 1...6)) },
                { try await tmdb.discoverTV(genres: [interest.tvGenre], page: .random(in: 1...6)) }
            ]
        }

        // Nothing known about them yet: the open pool is all there is.
        guard !seeds.isEmpty || !picks.isEmpty || !interestSources.isEmpty else {
            return await randomCandidates(count: count, sourceCount: 4)
        }

        let seedSources: [Source] = interestSources + seeds.map { seed in
            {
                seed.mediaType == .tv
                    ? try await tmdb.getTVShowRecommendations(id: seed.mediaId, page: .random(in: 1...2))
                    : try await tmdb.getMovieRecommendations(id: seed.mediaId, page: .random(in: 1...2))
            }
        }
        async let recommended = gather(seedSources)
        async let discovery = randomCandidates(count: max(4, count / 3), sourceCount: 2)

        let personal = unique(picks + (await recommended).shuffled())
        let mixed = Array(personal.prefix(count * 2 / 3)) + (await discovery)
        return Array(unique(mixed).shuffled().prefix(count))
    }

    /// Studios the viewer follows: the same ones as the Browse page's studio row.
    static func followedHubs() -> [CompanyHub] {
        StorageService.shared.companyHubs.filter {
            $0.isEnabled && (!$0.companyIds.isEmpty || !$0.networkIds.isEmpty)
        }
    }

    /// Following: movies and shows from a few followed studios, at random depths.
    private static func followingCandidates(count: Int) async -> [MediaItem] {
        let tmdb = TMDBService.shared
        var sources: [Source] = []
        for hub in followedHubs().shuffled().prefix(4) {
            let companyIDs = hub.companyIds
            let networkIDs = hub.networkIds
            if !companyIDs.isEmpty {
                sources.append { try await tmdb.discoverMoviesByCompany(companyIds: companyIDs, page: .random(in: 1...4)) }
                sources.append { try await tmdb.discoverTVByCompany(companyIds: companyIDs, page: .random(in: 1...3)) }
            }
            if !networkIDs.isEmpty {
                sources.append { try await tmdb.discoverTVByNetwork(networkIds: networkIDs, page: .random(in: 1...3)) }
            }
        }
        let found = await gather(sources)
        return Array(unique(found.shuffled()).prefix(count))
    }

    /// Which of these YouTube keys are portrait videos, checked in parallel.
    private static func portraitAmong(_ keys: [String]) async -> Set<String> {
        await withTaskGroup(of: (String, Bool).self) { group in
            for key in Set(keys) {
                group.addTask { (key, await YouTubeShapeProbe.shared.isPortrait(key)) }
            }
            var portrait = Set<String>()
            for await (key, isPortrait) in group where isPortrait { portrait.insert(key) }
            return portrait
        }
    }

    /// Fetches TMDB videos for every title in parallel, keyed by media id.
    private static func fetchVideos(for titles: [MediaItem]) async -> [Int: [Video]] {
        await withTaskGroup(of: (Int, [Video]).self) { group in
            for media in titles {
                group.addTask {
                    switch media.resolvedMediaType {
                    case .movie:
                        return (media.id, (try? await TMDBService.shared.getMovieVideos(id: media.id).results) ?? [])
                    case .tv:
                        return (media.id, (try? await TMDBService.shared.getTVShowVideos(id: media.id).results) ?? [])
                    case .person:
                        return (media.id, [])
                    }
                }
            }
            var result: [Int: [Video]] = [:]
            for await (id, videos) in group {
                result[id] = videos
            }
            return result
        }
    }
}

// MARK: - Shape probe

/// Whether a YouTube video is portrait. TMDB doesn't say, and YouTube's oEmbed
/// reports a landscape size even for Shorts. The `oar2` thumbnail is the
/// video's frame at its original aspect ratio, so the size in the first few
/// KB of that image is the video's own shape. It comes from `i.ytimg.com`,
/// which has no consent page: asking youtube.com itself (e.g. `/shorts/<id>`)
/// gets redirected for viewers in some regions, which read as "not a Short".
/// A video with no such image, or a request that fails, counts as landscape;
/// failures aren't remembered, so they're retried next time.
actor YouTubeShapeProbe {
    static let shared = YouTubeShapeProbe()

    private var cache: [String: Bool] = [:]
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func isPortrait(_ key: String) async -> Bool {
        if let cached = cache[key] { return cached }
        guard let url = URL(string: "https://i.ytimg.com/vi/\(key)/oar2.jpg") else { return false }
        var request = URLRequest(url: url)
        request.setValue("bytes=0-4095", forHTTPHeaderField: "Range")
        do {
            let (data, response) = try await session.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return false }
            if status == 404 {
                cache[key] = false
                return false
            }
            guard (200..<300).contains(status), let size = Self.jpegSize(data) else { return false }
            let portrait = size.height > size.width
            cache[key] = portrait
            return portrait
        } catch {
            return false
        }
    }

    /// Reads the frame size from a JPEG's start-of-frame marker.
    private static func jpegSize(_ data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data)
        var index = 2
        while index + 9 < bytes.count {
            guard bytes[index] == 0xFF else { index += 1; continue }
            let marker = bytes[index + 1]
            if marker == 0xC0 || marker == 0xC1 || marker == 0xC2 {
                let height = Int(bytes[index + 5]) << 8 | Int(bytes[index + 6])
                let width = Int(bytes[index + 7]) << 8 | Int(bytes[index + 8])
                return (width, height)
            }
            index += 2 + (Int(bytes[index + 2]) << 8 | Int(bytes[index + 3]))
        }
        return nil
    }
}
