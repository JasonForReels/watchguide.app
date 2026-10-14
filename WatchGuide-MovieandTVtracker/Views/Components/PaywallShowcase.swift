//
//  PaywallShowcase.swift
//  WatchGuide-MovieandTVtracker
//
//  The pieces that make the Pro paywall about the person looking at it rather
//  than about the product: their own posters drifting behind the offer, their
//  numbers, a preview of Atlas answering with a title from their watchlist, and
//  a welcome moment once they join. Nothing here invents data — when the
//  library is thin it falls back to what's trending, and says less.
//

import SwiftUI

// MARK: - Library Snapshot

/// A read-only summary of the user's library, taken once when the paywall opens.
struct PaywallLibrarySnapshot {
    let posterURLs: [URL]
    let trackedCount: Int
    let watchedCount: Int
    let hoursWatched: Int
    let tonightPick: SavedMediaItem?
    let tonightPickDaysWaiting: Int

    /// Enough real activity that quoting it back reads as a compliment, not a taunt.
    var isPersonal: Bool { trackedCount >= 5 }

    @MainActor
    static func current(storage: StorageService = .shared) -> PaywallLibrarySnapshot {
        var seen = Set<String>()
        let library = (storage.watched + storage.liked + storage.wantToWatch)
            .sorted { $0.addedAt > $1.addedAt }
            .filter { seen.insert($0.id).inserted }

        let posters = library
            .compactMap { TMDBService.shared.imageURL(path: $0.posterPath, size: .small) }
            .prefix(36)

        let minutes = storage.watchHistory.reduce(0) { $0 + max($1.minutesWatched, 0) }

        // The title that has waited longest is the most honest "tonight" pick —
        // the user chose it themselves, and the preview can say how long ago.
        let pick = storage.wantToWatch
            .filter { $0.posterPath != nil }
            .min { $0.addedAt < $1.addedAt }
        let days = pick.map {
            Calendar.current.dateComponents([.day], from: $0.addedAt, to: Date()).day ?? 0
        } ?? 0

        return PaywallLibrarySnapshot(
            posterURLs: Array(posters),
            trackedCount: library.count,
            watchedCount: storage.watched.count,
            hoursWatched: minutes / 60,
            tonightPick: pick,
            tonightPickDaysWaiting: max(days, 0)
        )
    }
}

// MARK: - Poster Wall

/// A tilted wall of posters, each column drifting at its own pace in alternating
/// directions. The columns hold two copies of their posters so the loop is seamless.
/// Static under Reduce Motion.
struct PaywallPosterWall: View {
    let urls: [URL]
    var columns = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrifting = false

    private let spacing: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let posterWidth = geo.size.width / 3.1
            let posterHeight = posterWidth * 1.5
            HStack(alignment: .top, spacing: spacing) {
                ForEach(0..<columns, id: \.self) { column in
                    columnView(column, width: posterWidth, height: posterHeight)
                }
            }
            .frame(width: geo.size.width * 1.35, height: geo.size.height * 1.4, alignment: .top)
            .rotationEffect(.degrees(-11))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, !isDrifting else { return }
            withAnimation(.linear(duration: 48).repeatForever(autoreverses: false)) {
                isDrifting = true
            }
        }
    }

    private func posters(for column: Int) -> [URL] {
        guard !urls.isEmpty else { return [] }
        let perColumn = 7
        return (0..<perColumn).map { urls[(column * 5 + $0 * columns + column) % urls.count] }
    }

    private func columnView(_ column: Int, width: CGFloat, height: CGFloat) -> some View {
        let items = posters(for: column)
        let cycle = CGFloat(items.count) * (height + spacing)
        let movesUp = column.isMultiple(of: 2)
        // Each column travels the same distance in the same time but starts staggered,
        // so the wall never lines up into a grid.
        let start = movesUp ? 0 : -cycle
        let end = movesUp ? -cycle : 0
        let stagger = CGFloat(column) * height * 0.37

        return VStack(spacing: spacing) {
            ForEach(Array((items + items).enumerated()), id: \.offset) { _, url in
                AsyncImageView(url: url, cornerRadius: 12, maxPixelSize: 260)
                    .frame(width: width, height: height)
            }
        }
        .offset(y: (isDrifting ? end : start) - stagger)
    }
}

// MARK: - Animated Stat

/// A number that counts up when it first appears.
struct PaywallStat: View {
    let value: Int
    let label: String
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            Text(shown, format: .number)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(shown)))
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
        .task {
            guard shown != value else { return }
            if reduceMotion {
                shown = value
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.spring(response: 1.1, dampingFraction: 0.9)) { shown = value }
        }
    }
}

// MARK: - Atlas Preview

/// A short, self-typing exchange that shows what Atlas feels like. The answer is
/// built only from the user's own watchlist, and the card is labelled a preview.
struct PaywallAtlasPreview: View {
    let snapshot: PaywallLibrarySnapshot
    @State private var typed = ""
    @State private var showsAnswer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var question: String {
        snapshot.tonightPick == nil
            ? "Do I need to stay after the credits?"
            : "What should I watch tonight?"
    }

    private var answer: String {
        guard let pick = snapshot.tonightPick else {
            return "Atlas checks every film for post-credits scenes, so you'll know before the lights come up."
        }
        switch snapshot.tonightPickDaysWaiting {
        case 0:  return "\(pick.title). You saved it today, so strike while you're curious."
        case 1:  return "\(pick.title). It's been on your watchlist since yesterday."
        default: return "\(pick.title). It's been waiting on your watchlist for \(snapshot.tonightPickDaysWaiting) days. Tonight's the night."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Atlas")
                    .fontWeight(.semibold)
                Spacer()
                Text("Preview")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))

            HStack {
                Spacer(minLength: 40)
                Text(typed.isEmpty ? " " : typed)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }

            if showsAnswer {
                HStack(alignment: .top, spacing: 10) {
                    if let path = snapshot.tonightPick?.posterPath {
                        AsyncImageView(url: TMDBService.shared.imageURL(path: path, size: .small),
                                       cornerRadius: 6, maxPixelSize: 120)
                            .frame(width: 34, height: 51)
                    }
                    Text(answer)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 24)
                }
                .padding(10)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.wgBadgeArrival)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Atlas preview. You ask: \(question) Atlas answers: \(answer)")
        .task { await play() }
    }

    private func play() async {
        guard typed.isEmpty else { return }
        if reduceMotion {
            typed = question
            showsAnswer = true
            return
        }
        try? await Task.sleep(for: .milliseconds(700))
        for character in question {
            guard !Task.isCancelled else { return }
            typed.append(character)
            try? await Task.sleep(for: .milliseconds(34))
        }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(WGMotion.reveal) { showsAnswer = true }
    }
}

// MARK: - Trial Timeline

/// Spells out exactly what happens during the free trial, so starting it feels safe.
struct PaywallTrialTimeline: View {
    let trialDays: Int
    let renewalPrice: String

    private struct Step: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private var steps: [Step] {
        [
            Step(icon: "lock.open.fill", title: "Today",
                 detail: "Everything in Pro unlocks. No charge."),
            Step(icon: "bell.fill", title: "Day \(max(trialDays - 1, 1))",
                 detail: "Last day to cancel in Settings and pay nothing."),
            Step(icon: "star.fill", title: "Day \(trialDays)",
                 detail: "Your plan starts at \(renewalPrice)/year.")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Image(systemName: step.icon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(index == 0 ? AnyShapeStyle(Color.orange.gradient)
                                                   : AnyShapeStyle(.white.opacity(0.16)),
                                        in: Circle())
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.16))
                                .frame(width: 2, height: 22)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.subheadline.weight(.semibold))
                        Text(step.detail)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.top, 4)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - CTA Sheen

/// A slow highlight that sweeps across the purchase button every few seconds.
struct PaywallSheen: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.45), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.35)
                        .rotationEffect(.degrees(18))
                        .offset(x: sweep ? geo.size.width * 1.3 : -geo.size.width * 0.6)
                }
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.4).delay(1.2)
                        .repeatForever(autoreverses: false)) {
                        sweep = true
                    }
                }
            }
        }
    }
}

// MARK: - Welcome

/// Shown the moment Pro activates. The user's own posters rise into a fan behind
/// the seal; it holds long enough to feel like an arrival, then hands back.
struct PaywallWelcomeView: View {
    let posterURLs: [URL]
    let onContinue: () -> Void
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fan: [URL] { Array(posterURLs.prefix(5)) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Color.orange.opacity(0.55), .clear],
                           center: .center, startRadius: 10, endRadius: 420)
                .opacity(arrived ? 1 : 0)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    ForEach(Array(fan.enumerated()), id: \.offset) { index, url in
                        let spread = Double(index) - Double(fan.count - 1) / 2
                        AsyncImageView(url: url, cornerRadius: 12, maxPixelSize: 300)
                            .frame(width: 96, height: 144)
                            .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
                            .rotationEffect(.degrees(arrived ? spread * 12 : 0), anchor: .bottom)
                            .offset(x: arrived ? spread * 34 : 0, y: arrived ? abs(spread) * 10 : 220)
                            .opacity(arrived ? 1 : 0)
                    }
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white, Color.orange.gradient)
                        .shadow(color: .orange.opacity(0.8), radius: 24)
                        .scaleEffect(arrived ? 1 : 0.2)
                        .offset(y: fan.isEmpty ? 0 : 96)
                }
                .frame(height: 260)

                VStack(spacing: 8) {
                    Text("Welcome to Pro")
                        .font(.largeTitle.bold())
                    Text("Every feature is yours. Go find something great.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .opacity(arrived ? 1 : 0)
                .offset(y: arrived ? 0 : 20)

                Spacer()

                Button(action: onContinue) {
                    Text("Start Exploring")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .opacity(arrived ? 1 : 0)
            }
        }
        .preferredColorScheme(.dark)
        #if os(iOS)
        .sensoryFeedback(.success, trigger: arrived) { _, now in now }
        #endif
        .onAppear {
            withAnimation(WGMotion.resolved(WGMotion.bouncy.speed(0.7), reduceMotion: reduceMotion)) {
                arrived = true
            }
        }
    }
}
