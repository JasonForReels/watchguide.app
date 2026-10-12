//
//  PopsOnboardingView.swift
//  WatchGuide-MovieandTVtracker
//
//  Sets Pops up for a viewer: how the feed works, what they're into, and which
//  studios to follow. Shown the first time Pops opens, and again from the
//  tune button at the top of the feed (without the introduction). Interests
//  seed For You; followed studios are the ones Following draws from, and the
//  same ones as the Browse page's studio row.
//

import SwiftUI

// MARK: - Stored choices

enum PopsOnboarding {
    static let doneKey = "popsOnboardingDone"
    static let interestsKey = "popsInterests"
}

/// A taste the viewer can pick. TMDB numbers movie and TV genres differently,
/// so each interest carries both.
enum PopsInterest: String, CaseIterable, Identifiable, Hashable {
    case action, adventure, comedy, drama, horror, sciFi, fantasy
    case animation, romance, thriller, crime, mystery, family, documentary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .action: return "Action"
        case .adventure: return "Adventure"
        case .comedy: return "Comedy"
        case .drama: return "Drama"
        case .horror: return "Horror"
        case .sciFi: return "Sci-Fi"
        case .fantasy: return "Fantasy"
        case .animation: return "Animation"
        case .romance: return "Romance"
        case .thriller: return "Thriller"
        case .crime: return "Crime"
        case .mystery: return "Mystery"
        case .family: return "Family"
        case .documentary: return "Documentary"
        }
    }

    var emoji: String {
        switch self {
        case .action: return "💥"
        case .adventure: return "🧭"
        case .comedy: return "😂"
        case .drama: return "🎭"
        case .horror: return "👻"
        case .sciFi: return "🚀"
        case .fantasy: return "🐉"
        case .animation: return "🎨"
        case .romance: return "💘"
        case .thriller: return "🔪"
        case .crime: return "🕵️"
        case .mystery: return "🔎"
        case .family: return "👨‍👩‍👧"
        case .documentary: return "🎥"
        }
    }

    var movieGenre: Int {
        switch self {
        case .action: return 28
        case .adventure: return 12
        case .comedy: return 35
        case .drama: return 18
        case .horror: return 27
        case .sciFi: return 878
        case .fantasy: return 14
        case .animation: return 16
        case .romance: return 10749
        case .thriller: return 53
        case .crime: return 80
        case .mystery: return 9648
        case .family: return 10751
        case .documentary: return 99
        }
    }

    /// TV has no horror, romance or thriller genre, so those use the nearest one.
    var tvGenre: Int {
        switch self {
        case .action, .adventure: return 10759
        case .comedy: return 35
        case .drama, .romance: return 18
        case .horror, .thriller, .mystery: return 9648
        case .sciFi, .fantasy: return 10765
        case .animation: return 16
        case .crime: return 80
        case .family: return 10751
        case .documentary: return 99
        }
    }

    static func selected() -> [PopsInterest] {
        let raw = UserDefaults.standard.stringArray(forKey: PopsOnboarding.interestsKey) ?? []
        return raw.compactMap(PopsInterest.init(rawValue:))
    }

    static func save(_ interests: Set<PopsInterest>) {
        UserDefaults.standard.set(interests.map(\.rawValue).sorted(), forKey: PopsOnboarding.interestsKey)
    }
}

#if !os(tvOS)

// MARK: - View

struct PopsOnboardingView: View {
    /// First time: starts with how Pops works. From the tune button: skips it.
    let isFirstRun: Bool
    /// `changed` is true when the viewer's interests or followed studios differ
    /// from when this opened, so the feed knows to rebuild.
    let onFinish: (_ changed: Bool) -> Void

    private enum Step: Hashable { case intro, interests, studios }

    @ObservedObject private var storage = StorageService.shared
    @State private var step: Step
    @State private var interests: Set<PopsInterest>
    @State private var followedIDs: Set<String>

    private let initialInterests: Set<PopsInterest>
    private let initialFollowed: Set<String>

    init(isFirstRun: Bool, onFinish: @escaping (_ changed: Bool) -> Void) {
        self.isFirstRun = isFirstRun
        self.onFinish = onFinish
        let chosen = Set(PopsInterest.selected())
        let followed = Set(StorageService.shared.companyHubs.filter(\.isEnabled).map(\.id))
        _step = State(initialValue: isFirstRun ? .intro : .interests)
        _interests = State(initialValue: chosen)
        _followedIDs = State(initialValue: followed)
        initialInterests = chosen
        initialFollowed = followed
    }

    private var steps: [Step] {
        isFirstRun ? [.intro, .interests, .studios] : [.interests, .studios]
    }

    private var stepIndex: Int { steps.firstIndex(of: step) ?? 0 }
    private var isLastStep: Bool { stepIndex == steps.count - 1 }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header

                ZStack {
                    switch step {
                    case .intro: introPage
                    case .interests: interestsPage
                    case .studios: studiosPage
                    }
                }
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Chrome

    private var background: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Color.accentColor.opacity(0.32), .clear],
                           center: .top, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color.pink.opacity(0.18), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            if stepIndex > 0 {
                Button { go(to: steps[stepIndex - 1]) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .modifier(OnboardingGlass(shape: Circle()))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 40, height: 40)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                    Capsule()
                        .fill(index == stepIndex ? Color.white : Color.white.opacity(0.28))
                        .frame(width: index == stepIndex ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(stepIndex + 1) of \(steps.count)")

            Spacer()

            Button(isFirstRun ? "Skip" : "Cancel") { finish(save: false) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(minWidth: 40, minHeight: 40, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var footer: some View {
        Button {
            if isLastStep {
                finish(save: true)
            } else {
                go(to: steps[stepIndex + 1])
            }
        } label: {
            Text(footerTitle)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    private var footerTitle: String {
        if isLastStep { return isFirstRun ? "Start watching" : "Done" }
        if step == .interests && interests.isEmpty { return "Skip for now" }
        return "Continue"
    }

    // MARK: Pages

    private func pageTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private var introPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                pageTitle("Pops, made for you",
                          "Short clips from movies and shows. Here's how it works.")

                VStack(spacing: 14) {
                    introRow("sparkles", "For You",
                             "Learns from what you like and save, and keeps surprising you.")
                    introRow("person.2.fill", "Following",
                             "Clips from the studios you follow.")
                    introRow("arrow.up", "Swipe up for the next clip",
                             "There's always another one.")
                    introRow("hand.tap.fill", "Tap to pause, double-tap to like",
                             "Likes and saves teach For You what you want more of.")
                    introRow("building.2.fill", "Tap a studio's logo",
                             "See everything it makes, and follow it.")
                    introRow(nil, "Ask Atlas",
                             "Tap Atlas on any clip to ask about what you're watching.")
                }
                .padding(.horizontal, 22)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func introRow(_ symbol: String?, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                } else {
                    AtlasMark(size: 22, tint: .white)
                }
            }
            .frame(width: 46, height: 46)
            .modifier(OnboardingGlass(shape: Circle()))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var interestsPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                pageTitle("What are you into?",
                          "Pick a few. For You starts here and gets sharper the more you like.")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    ForEach(PopsInterest.allCases) { interest in
                        interestChip(interest)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func interestChip(_ interest: PopsInterest) -> some View {
        let isSelected = interests.contains(interest)
        return Button {
            if isSelected { interests.remove(interest) } else { interests.insert(interest) }
            tap()
        } label: {
            HStack(spacing: 8) {
                Text(interest.emoji)
                Text(interest.title)
                    .font(.subheadline.weight(.semibold))
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .modifier(OnboardingGlass(shape: Capsule(), tint: isSelected ? Color.accentColor : nil))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var studiosPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                pageTitle("Follow your studios",
                          "Following shows their clips. Followed studios also appear on your Browse page.")

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 18) {
                    ForEach(storage.companyHubs) { hub in
                        studioTile(hub)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func studioTile(_ hub: CompanyHub) -> some View {
        let isFollowed = followedIDs.contains(hub.id)
        return Button {
            if isFollowed { followedIDs.remove(hub.id) } else { followedIDs.insert(hub.id) }
            tap()
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        if let url = logoURL(for: hub) {
                            AsyncImageView(url: url, contentMode: .fit, cornerRadius: 0)
                                .padding(16)
                        } else {
                            Text(String(hub.name.prefix(1)))
                                .font(.title2.weight(.bold))
                        }
                    }
                    .frame(width: 76, height: 76)
                    .modifier(OnboardingGlass(shape: Circle(), tint: isFollowed ? Color.accentColor : nil))

                    if isFollowed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white, Color.accentColor)
                            .background(Circle().fill(Color.black).padding(2))
                    }
                }

                Text(hub.name)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(isFollowed ? 1 : 0.78))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hub.name), \(isFollowed ? "following" : "not following")")
        .accessibilityAddTraits(isFollowed ? [.isButton, .isSelected] : .isButton)
    }

    /// The same logo the Browse page's studio row uses.
    private func logoURL(for hub: CompanyHub) -> URL? {
        guard let raw = hub.logoPath ?? BrowseView.defaultStudioLogosByName[hub.name], !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "https://raw.githubusercontent.com/WatchGuide-app/Studios-hubs/refs/heads/main/\(trimmed)")
    }

    // MARK: Actions

    private func go(to next: Step) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { step = next }
    }

    private func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// Saves what was chosen (unless skipped) and hands back whether it changed anything.
    private func finish(save: Bool) {
        var changed = false
        if save {
            if interests != initialInterests {
                PopsInterest.save(interests)
                changed = true
            }
            if followedIDs != initialFollowed {
                for hub in storage.companyHubs where followedIDs.contains(hub.id) != hub.isEnabled {
                    var updated = hub
                    updated.isEnabled = followedIDs.contains(hub.id)
                    storage.updateCompanyHub(updated)
                }
                changed = true
            }
        }
        onFinish(changed)
    }
}

// MARK: - Glass

/// Liquid Glass where it exists, a thin material everywhere else.
private struct OnboardingGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color? = nil

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            if let tint {
                content.glassEffect(.regular.tint(tint.opacity(0.55)).interactive(), in: shape)
            } else {
                content.glassEffect(.regular.interactive(), in: shape)
            }
        } else {
            content
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.fill(tint?.opacity(0.35) ?? Color.clear))
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.8))
        }
    }
}

#endif
