//
//  ClipsView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI

struct ClipsView: View {
    @Binding var selectedItem: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ClipsFeedViewModel()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                if viewModel.isLoading && viewModel.items.isEmpty {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                    errorView(message: errorMessage)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.items) { item in
                                ClipsFeedPage(
                                    item: item,
                                    pageSize: proxy.size,
                                    onOpenTitle: {
                                        selectedItem = item.media
                                        dismiss()
                                    }
                                )
                                .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .ignoresSafeArea()
                }

                topBar
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Loading clips...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.yellow)

            Text("Clips Unavailable")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))

            Button {
                Task { await viewModel.reload() }
            } label: {
                Text("Try Again")
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

    private var topBar: some View {
        HStack {
            Text("Clips")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

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
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct ClipsFeedPage: View {
    let item: ClipFeedItem
    let pageSize: CGSize
    let onOpenTitle: () -> Void

    var body: some View {
        ZStack {
            clipBackground
                .ignoresSafeArea()

            EmbeddedTrailerPlayer(
                videoKey: item.video.key,
                title: item.media.displayTitle,
                compact: false,
                autoPlay: true,
                loops: true,
                aspectRatio: 9.0 / 16.0,
                contentMode: .fill,
                cornerRadius: 0,
                zoomScale: 3.2
            )
            .frame(width: pageSize.width, height: pageSize.height)
            .clipped()

            overlayChrome
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .background(Color.black)
    }

    private var overlayChrome: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.28), .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.media.displayTitle)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(item.media.resolvedMediaType == .movie ? "Movie" : "Series")
                        if let year = item.media.year {
                            Text("• \(year)")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))

                    Text(item.video.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 18) {
                    railButton(symbol: "play.rectangle.fill", title: "Open", action: onOpenTitle)
                    railButton(symbol: "plus", title: "List", action: {})
                    railButton(symbol: "square.and.arrow.up", title: "Share", action: {})
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
    }

    @ViewBuilder
    private var clipBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.16, green: 0.03, blue: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )

            AsyncImageView(
                url: TMDBService.shared.imageURL(path: item.media.backdropPath ?? item.media.posterPath, size: .backdrop),
                contentMode: .fill,
                cornerRadius: 0
            )
            .blur(radius: 18)
            .scaleEffect(1.18)
            .overlay(Color.black.opacity(0.5))

            LinearGradient(
                colors: [
                    Color(red: 0.19, green: 0.03, blue: 0.08).opacity(0.6),
                    .clear,
                    Color.black.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func railButton(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct ClipFeedItem: Identifiable {
    let media: MediaItem
    let video: Video

    var id: String {
        "\(media.id)-\(video.id)"
    }
}

@MainActor
private final class ClipsFeedViewModel: ObservableObject {
    @Published private(set) var items: [ClipFeedItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil

        do {
            let movieResponse = try await TMDBService.shared.getTrending(mediaType: .movie)
            let tvResponse = try await TMDBService.shared.getTrending(mediaType: .tv)
            let candidates = Array((movieResponse.results + tvResponse.results).prefix(16))

            var feedItems: [ClipFeedItem] = []
            for media in candidates {
                guard feedItems.count < 12 else { break }
                let videos: [Video]
                switch media.resolvedMediaType {
                case .movie:
                    videos = try await TMDBService.shared.getMovieVideos(id: media.id).results
                case .tv:
                    videos = try await TMDBService.shared.getTVShowVideos(id: media.id).results
                case .person:
                    videos = []
                }

                let clipVideos = videos
                    .filter { video in
                        video.site.caseInsensitiveCompare("YouTube") == .orderedSame &&
                        video.type.caseInsensitiveCompare("Clip") == .orderedSame &&
                        !video.name.localizedCaseInsensitiveContains("featurette") &&
                        !video.isRedBand
                    }
                    .sorted { lhs, rhs in
                        if let lhsDate = lhs.publishedAt, let rhsDate = rhs.publishedAt {
                            return lhsDate > rhsDate
                        }
                        if lhs.official != rhs.official {
                            return lhs.official == true
                        }
                        return lhs.name < rhs.name
                    }

                for video in clipVideos.prefix(2) {
                    feedItems.append(ClipFeedItem(media: media, video: video))
                }
            }

            items = feedItems
            hasLoaded = true

            if feedItems.isEmpty {
                errorMessage = "No vertical-ready clips were returned for the current trending titles."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
