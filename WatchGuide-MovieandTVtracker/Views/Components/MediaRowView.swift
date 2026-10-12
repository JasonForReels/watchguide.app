//
//  MediaRowView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct MediaRowView: View {
    enum RowStyle {
        /// Standard horizontal row of portrait poster cards
        case standard
        /// Landscape backdrop cards — used to break up visual monotony
        case featured
        /// Large portrait posters that let the artwork carry the row
        case spotlight
        /// Smaller, denser posters with the score on the artwork
        case compact
        /// One wide 16:9 card per swipe, snapping, with the synopsis
        case cinematic

        /// The look a Browse row gets from what it shows. Each category has its
        /// own shape so neighbouring rows never read as the same strip twice.
        static func forBrowse(_ endpoint: BrowseRowConfig.BrowseEndpoint?) -> RowStyle {
            switch endpoint {
            case .popularMovies, .latestCertifiedFresh: return .spotlight
            case .nowPlayingMovies, .airingTodayTV: return .featured
            case .topRatedMovies, .onTheAirTV: return .compact
            case .upcomingMovies: return .cinematic
            default: return .standard
            }
        }
    }

    let title: String
    let items: [MediaItem]
    let limit: Int?
    let onItemTap: (MediaItem) -> Void
    let onSeeAll: (() -> Void)?
    let isImmersiveStyle: Bool
    let rowStyle: RowStyle
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var scrollOffset: CGFloat = 0

    init(
        title: String,
        items: [MediaItem],
        limit: Int? = 10,
        onItemTap: @escaping (MediaItem) -> Void,
        onSeeAll: (() -> Void)? = nil,
        isImmersiveStyle: Bool = false,
        rowStyle: RowStyle = .standard
    ) {
        self.title = title
        self.items = items
        self.limit = limit
        self.onItemTap = onItemTap
        self.onSeeAll = onSeeAll
        self.isImmersiveStyle = isImmersiveStyle
        self.rowStyle = rowStyle
    }

    var body: some View {
        let isRegular = horizontalSizeClass == .regular
        let displayedItems = limit != nil ? Array(items.prefix(limit!)) : items
        let isRankedTrendingRow = [
            "trending movies",
            "trending tv shows",
            "trending tv"
        ].contains(title.lowercased())
        VStack(alignment: .leading, spacing: rowSpacing(isRegular: isRegular)) {
            // Header
            #if os(iOS)
            if !isImmersiveStyle {
                // App Store style: the title itself is the "see all" affordance.
                Group {
                    if let onSeeAll {
                        Button(action: onSeeAll) { RowHeaderLabel(title: title) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows all titles")
                    } else {
                        RowHeaderLabel(title: title, showsChevron: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalPadding(isRegular: isRegular))
            } else {
                legacyHeader(displayedCount: displayedItems.count, isRegular: isRegular)
            }
            #else
            legacyHeader(displayedCount: displayedItems.count, isRegular: isRegular)
            #endif

            // Scrolling content
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: isRegular ? 16 : 12) {
                    ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                        let zoomID = WGZoomID.media(item.id, context: title)
                        FocusableActionSurface(action: {
                            WGZoom.willPresent(zoomID)
                            onItemTap(item)
                        }, outlineShape: .roundedRectangle(cornerRadius: 18)) {
                            switch rowStyle {
                            case .featured:
                                FeaturedBackdropCard(item: item, appearanceIndex: index)
                            case .cinematic:
                                CinematicWideCard(item: item, appearanceIndex: index,
                                                  sideInset: horizontalPadding(isRegular: isRegular))
                            case .spotlight:
                                MediaPosterCard(item: item, appearanceIndex: index, scale: 1.45)
                            case .compact:
                                MediaPosterCard(item: item, appearanceIndex: index, scale: 0.78, showsScore: true)
                            case .standard:
                                MediaPosterCard(
                                    item: item,
                                    rank: isRankedTrendingRow ? index + 1 : nil,
                                    appearanceIndex: index
                                )
                            }
                        }
                        .wgCarouselItem()
                        .wgZoomSource(id: zoomID)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, horizontalPadding(isRegular: isRegular))
                #if os(tvOS)
                .padding(.vertical, 4)
                #endif
            }
            .modifier(CardSnapping(isEnabled: rowStyle == .cinematic))
            .scrollClipDisabled()
            #if os(tvOS)
            .focusSection()
            #endif
        }
        // Rows are the unit that enters the feed, not individual cards — one
        // reveal per section reads as content arriving, card-by-card reads as
        // the screen assembling itself.
        .wgSectionReveal()
    }

    @ViewBuilder
    private func legacyHeader(displayedCount: Int, isRegular: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(isRegular ? .title2 : .title3)
                    .fontWeight(.bold)
                    .foregroundStyle(rowTitleColor)

                #if os(tvOS)
                Text("\(displayedCount) picks ready to explore")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(rowSecondaryColor)
                #endif
            }

            Spacer()

            if let onSeeAll = onSeeAll {
                Button(action: onSeeAll) {
                    #if os(tvOS)
                    TVSeeAllButtonLabel()
                    #else
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundStyle(rowSecondaryColor)
                    #endif
                }
                #if os(tvOS)
                .buttonStyle(.plain)
                #endif
            }
        }
        .padding(.horizontal, horizontalPadding(isRegular: isRegular))
    }

    private var rowTitleColor: Color {
        #if os(tvOS)
        .white
        #else
        isImmersiveStyle ? .white : .primary
        #endif
    }

    private var rowSecondaryColor: Color {
        #if os(tvOS)
        .white.opacity(0.78)
        #else
        isImmersiveStyle ? .white.opacity(0.78) : .gray
        #endif
    }

    private func rowSpacing(isRegular: Bool) -> CGFloat {
        #if os(tvOS)
        return isImmersiveStyle ? 32 : 18
        #else
        isRegular ? 16 : 12
        #endif
    }
    
    private func horizontalPadding(isRegular: Bool) -> CGFloat {
        #if os(tvOS)
        return isImmersiveStyle ? 90 : 60
        #else
        isRegular ? 20 : 16
        #endif
    }
}

// MARK: - Media Poster Card
struct MediaPosterCard: View {
    let item: MediaItem
    let rank: Int?
    let appearanceIndex: Int
    /// Poster size relative to the standard row; spotlight and compact rows set it.
    let scale: CGFloat
    /// Puts the TMDB score on the artwork, for dense rows where it is the point.
    let showsScore: Bool
    @State private var isHovered = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isFocused) private var isFocused

    init(item: MediaItem, rank: Int? = nil, appearanceIndex: Int = 0,
         scale: CGFloat = 1, showsScore: Bool = false) {
        self.item = item
        self.rank = rank
        self.appearanceIndex = appearanceIndex
        self.scale = scale
        self.showsScore = showsScore
    }

    private var contentBadgeText: String? {
        guard let dateStr = item.displayDate,
              let date = Self.dateFormatter.date(from: dateStr) else { return nil }
        let daysSince = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        guard daysSince >= 0, daysSince <= 30 else { return nil }
        return item.resolvedMediaType == .tv ? "NEW SERIES" : "NEW MOVIE"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        let basePosterSize = ResponsiveSizing.posterSize(horizontalSizeClass: horizontalSizeClass)
        // Ranked rows get taller posters for visual emphasis
        let sizeFactor = rank != nil ? 1.15 : scale
        let posterSize = CGSize(width: basePosterSize.width * sizeFactor,
                                height: basePosterSize.height * sizeFactor)
        let isLarge = scale > 1.2
        let isEngaged = isHovered || isFocused

        HStack(alignment: .bottom, spacing: rank != nil ? -8 : 0) {
            // Large rank number positioned to the left, partially behind the poster
            if let rank {
                Text("\(rank)")
                    .font(.system(size: posterSize.height * 0.5, weight: .black, design: .default))
                    .foregroundStyle(.primary.opacity(0.15))
                    .offset(y: posterSize.height * 0.08)
                    .zIndex(0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    PosterImageView(
                        posterPath: item.posterPath,
                        backdropPath: item.backdropPath,
                        size: .medium,
                        mediaId: item.id,
                        mediaType: item.resolvedMediaType,
                        displayWidth: posterSize.width
                    )
                    .frame(width: posterSize.width, height: posterSize.height)
                    // Round at the framed size, not `.clipped()`. The poster fills
                    // its frame, so a plain rectangular clip cuts through the
                    // rounded shape applied inside PosterImageView and leaves the
                    // bottom corners square.
                    .clipShape(RoundedRectangle(cornerRadius: sharedPosterCornerRadius, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        StreamingLogoBadge(
                            mediaId: item.id,
                            mediaType: item.resolvedMediaType,
                            showsStudioLogo: false
                        )
                        .padding(6)
                    }
                    .overlay(alignment: .topLeading) {
                        if let badge = contentBadgeText {
                            Text(badge)
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.5)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.blue)
                                )
                                .padding(6)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if showsScore, let score = item.voteAverage, score > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.yellow)
                                Text(score, format: .number.precision(.fractionLength(1)))
                                    .font(.system(size: 11, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(6)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 0.75)
                    }
                    .shadow(color: .black.opacity(isLarge ? 0.35 : 0.2),
                            radius: isEngaged ? 14 : (isLarge ? 10 : 5), y: isEngaged ? 6 : (isLarge ? 5 : 2))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEngaged)
                }

                // Title + metadata below poster (Disney+ style)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(isLarge ? .subheadline.weight(.semibold) : .caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let year = item.year {
                        Text(year)
                            .font(isLarge ? .caption : .caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: posterSize.width, alignment: .leading)
            }
            .zIndex(1)
        }
        .contentShape(Rectangle())
        .wgStaggeredAppear(index: appearanceIndex)
        #if !os(tvOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }
}

// MARK: - Featured Backdrop Card
/// Landscape card showing a cinematic backdrop image with title overlay — used in `.featured` rows.
struct FeaturedBackdropCard: View {
    let item: MediaItem
    let appearanceIndex: Int
    @State private var isHovered = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isFocused) private var isFocused

    init(item: MediaItem, appearanceIndex: Int = 0) {
        self.item = item
        self.appearanceIndex = appearanceIndex
    }

    var body: some View {
        let isRegular = horizontalSizeClass == .regular
        let cardWidth: CGFloat = isRegular ? 320 : 260
        let cardHeight: CGFloat = cardWidth * 9.0 / 16.0
        let isEngaged = isHovered || isFocused

        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                BackdropImageView(
                    backdropPath: item.backdropPath,
                    size: .backdropSmall,
                    mediaId: item.id,
                    mediaType: item.resolvedMediaType,
                    displayWidth: cardWidth
                )
                .frame(width: cardWidth, height: cardHeight)
                .clipped()

                // Cinematic gradient
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.25),
                        .init(color: .black.opacity(0.4), location: 0.55),
                        .init(color: .black.opacity(0.88), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Content badge + title
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.resolvedMediaType == .tv ? "SERIES" : "MOVIE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.7))

                    Text(item.displayTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(12)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.25), radius: isEngaged ? 12 : 5, y: isEngaged ? 6 : 3)
            .scaleEffect(isEngaged ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEngaged)

            // Metadata below card
            HStack(spacing: 6) {
                if let rating = item.voteAverage, rating > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", rating))
                            .font(.caption2.weight(.semibold))
                    }
                }
                if let year = item.year {
                    Text(year)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .contentShape(Rectangle())
        .wgStaggeredAppear(index: appearanceIndex)
        #if !os(tvOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }
}

// MARK: - Cinematic Wide Card
/// Nearly full-width 16:9 card for `.cinematic` rows: one title per swipe, with
/// its synopsis, so a row like Coming Soon reads as a set of trailers to flip
/// through rather than another strip of posters. The next card peeks in at the
/// edge so it's obvious the row continues.
struct CinematicWideCard: View {
    let item: MediaItem
    let appearanceIndex: Int
    let sideInset: CGFloat
    @Environment(\.isFocused) private var isFocused

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "In cinemas 24 Oct" for a title that hasn't opened yet; otherwise its type.
    private var eyebrow: String {
        if let raw = item.displayDate, let date = Self.parser.date(from: raw), date > Date() {
            let day = date.formatted(.dateTime.day().month(.abbreviated))
            return item.resolvedMediaType == .tv ? "Premieres \(day)" : "In cinemas \(day)"
        }
        return item.resolvedMediaType == .tv ? "Series" : "Movie"
    }

    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                BackdropImageView(
                    backdropPath: item.backdropPath,
                    size: .backdropSmall,
                    mediaId: item.id,
                    mediaType: item.resolvedMediaType,
                    displayWidth: 420
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: .black.opacity(0.55), location: 0.62),
                        .init(color: .black.opacity(0.9), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(item.displayTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            .containerRelativeFrame(.horizontal) { length, _ in
                min(length - sideInset * 2 - 20, 560)
            }
            .contentShape(Rectangle())
            .wgStaggeredAppear(index: appearanceIndex)
    }
}

/// Snaps a row to whole cards. Only the cinematic row uses it: one card per
/// swipe is the point there, while poster rows are for free browsing.
private struct CardSnapping: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.scrollTargetBehavior(.viewAligned)
        } else {
            content
        }
    }
}

// MARK: - Saved Media Row
struct SavedMediaRowView: View {
    let title: String
    let items: [SavedMediaItem]
    let onItemTap: (SavedMediaItem) -> Void
    let onSeeAll: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(title: String, items: [SavedMediaItem], onItemTap: @escaping (SavedMediaItem) -> Void, onSeeAll: (() -> Void)? = nil) {
        self.title = title
        self.items = items
        self.onItemTap = onItemTap
        self.onSeeAll = onSeeAll
    }

    var body: some View {
        let isRegular = horizontalSizeClass == .regular
        VStack(alignment: .leading, spacing: isRegular ? 16 : 12) {
            // Header
            HStack {
                Text(LocalizedStringKey(title))
                    .font(isRegular ? .title2 : .title3)
                    .fontWeight(.bold)
                    .foregroundStyle(rowTitleColor)

                Spacer()

                if let onSeeAll = onSeeAll {
                    Button(action: onSeeAll) {
                        #if os(tvOS)
                        TVSeeAllButtonLabel()
                        #else
                        HStack(spacing: 4) {
                            Text("See All")
                                .font(.subheadline)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundColor(.accentColor)
                        #endif
                    }
                    #if os(tvOS)
                    .buttonStyle(.plain)
                    #endif
                }
            }
            .padding(.horizontal, isRegular ? 20 : 16)

            // Scrolling content
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: isRegular ? 16 : 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let zoomID = WGZoomID.media(item.mediaId, context: title)
                        FocusableActionSurface(action: {
                            WGZoom.willPresent(zoomID)
                            onItemTap(item)
                        }, outlineShape: .roundedRectangle(cornerRadius: 18)) {
                            SavedMediaPosterCard(item: item, appearanceIndex: index)
                        }
                        .wgCarouselItem()
                        .wgZoomSource(id: zoomID)
                    }
                }
                .padding(.horizontal, isRegular ? 20 : 16)
            }
            .scrollClipDisabled()
        }
    }

    private var rowTitleColor: Color {
        #if os(tvOS)
        .white
        #else
        .primary
        #endif
    }
}

#if os(tvOS)
struct TVSeeAllButtonLabel: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("See All")
                .font(.caption.weight(.medium))
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.7))
    }
}
#endif

// MARK: - Saved Media Poster Card
struct SavedMediaPosterCard: View {
    let item: SavedMediaItem
    var allowsExpansion = true
    var widthOverride: CGFloat? = nil
    var appearanceIndex: Int = 0
    @State private var isHovered = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let defaultPosterSize = ResponsiveSizing.posterSize(horizontalSizeClass: horizontalSizeClass)
        let posterWidth = widthOverride ?? defaultPosterSize.width
        let posterHeight = posterWidth * 1.5
        let isEngaged = allowsExpansion && (isHovered || isFocused)

        ZStack {
            PosterImageView(
                posterPath: item.posterPath,
                backdropPath: item.backdropPath,
                size: .medium,
                mediaId: item.mediaId,
                mediaType: item.mediaType,
                displayWidth: posterWidth
            )
                .frame(width: posterWidth, height: posterHeight)
                // Matches the 18pt border drawn in the overlay below, so the
                // artwork and its stroke share one silhouette.
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.2), radius: isEngaged ? 8 : 4, y: isEngaged ? 4 : 2)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEngaged)
        }
        .frame(width: posterWidth, height: posterHeight)
        .contentShape(Rectangle())
        .wgStaggeredAppear(index: appearanceIndex)
        #if !os(tvOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }
}

#Preview {
    MediaRowView(
        title: "Trending Movies",
        items: [],
        onItemTap: { _ in }
    )
}

enum FocusOutlineShape {
    case roundedRectangle(cornerRadius: CGFloat)
    case capsule
    case circle
}

struct FocusableActionSurface<Content: View>: View {
    let action: () -> Void
    var outlineShape: FocusOutlineShape? = nil
    @ViewBuilder let content: () -> Content

    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #endif

    var body: some View {
        #if os(tvOS)
        content()
            .focusable(true)
            .focused($isFocused)
            .onTapGesture(perform: action)
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .shadow(color: .white.opacity(isFocused ? 0.08 : 0), radius: isFocused ? 12 : 0)
            .shadow(color: .black.opacity(isFocused ? 0.32 : 0.18), radius: isFocused ? 18 : 8, y: isFocused ? 10 : 6)
            .animation(.spring(response: 0.26, dampingFraction: 0.8), value: isFocused)
            .overlay {
                if let outlineShape, isFocused {
                    focusOutline(for: outlineShape)
                }
            }
        #else
        Button(action: action) {
            content()
        }
        .buttonStyle(.wgPress)
        #endif
    }

    @ViewBuilder
    private func focusOutline(for shape: FocusOutlineShape) -> some View {
        switch shape {
        case .roundedRectangle(let cornerRadius):
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.92), lineWidth: 0.75)
        case .capsule:
            Capsule()
                .stroke(Color.white.opacity(0.92), lineWidth: 0.75)
        case .circle:
            Circle()
                .stroke(Color.white.opacity(0.92), lineWidth: 0.75)
        }
    }
}
