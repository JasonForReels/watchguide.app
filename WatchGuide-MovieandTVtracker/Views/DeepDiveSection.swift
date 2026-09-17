//
//  DeepDiveSection.swift
//  WatchGuide-MovieandTVtracker
//
//  Craft notes, making-of timeline, adaptation changes and ending explained.
//  Spoiler tabs stay locked until the title is marked watched.
//

import SwiftUI

struct DeepDiveSection: View {
    let item: MediaItem
    let crew: [CrewMember]
    let budget: String?
    let revenue: String?
    let isWatched: Bool
    let onQuotaReached: () -> Void

    @State private var selectedTab: DeepDiveTab = .craft
    @State private var endingDepth: EndingDepth = .quick
    @State private var keywords: [String] = []
    @State private var safe: DeepDiveSafeContent?
    @State private var spoiler: DeepDiveSpoilerContent?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var spoilersRevealed = false
    @State private var confirmReveal = false

    private var context: DeepDiveContext {
        DeepDiveContext(
            tmdbId: item.id,
            mediaType: item.resolvedMediaType,
            title: item.displayTitle,
            year: item.year,
            crew: crew,
            budget: budget,
            revenue: revenue,
            keywords: keywords
        )
    }

    /// Adaptation is only offered when TMDB tags the title as based on something.
    private var visibleTabs: [DeepDiveTab] {
        DeepDiveTab.allCases.filter { $0 != .adaptation || context.adaptationKeyword != nil }
    }

    private var isUnlocked: Bool { isWatched || spoilersRevealed }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Deep Dive")
                    .font(.title3)
                    .fontWeight(.bold)
                if !AIMessageQuota.isUnlimited() && !AIMessageQuota.canUseDeepDiveThisMonth() {
                    WGUnlimitedLockButton()
                }
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleTabs) { tab in
                        tabChip(tab)
                    }
                }
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)

            if safe != nil || spoiler != nil {
                Text("Written by Atlas AI and may contain mistakes.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .task(id: item.id) {
            keywords = await TMDBService.shared.getKeywords(id: item.id, mediaType: item.resolvedMediaType).map(\.name)
        }
        .confirmationDialog("Show spoilers?", isPresented: $confirmReveal, titleVisibility: .visible) {
            Button("Show spoilers", role: .destructive) { spoilersRevealed = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You haven’t marked \(item.displayTitle) as watched.")
        }
    }

    // MARK: - Tabs

    private func tabChip(_ tab: DeepDiveTab) -> some View {
        let selected = tab == selectedTab
        return Button {
            selectedTab = tab
            errorMessage = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.isSpoiler && !isUnlocked ? "lock.fill" : tab.systemImage)
                Text(tab.rawValue)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? Color.accentColor : Color.gray.opacity(0.12))
            .foregroundColor(selected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if selectedTab.isSpoiler && !isUnlocked {
            lockedView
        } else if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                Text("Atlas is researching \(item.displayTitle)…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        } else if let errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text(errorMessage).font(.caption).foregroundColor(.secondary)
                Button("Try again") { load(selectedTab) }.font(.caption)
            }
        } else {
            switch selectedTab {
            case .craft:
                if let safe { craftView(safe.craft) } else { startButton }
            case .making:
                if let safe { makingView(safe.making) } else { startButton }
            case .adaptation:
                if let spoiler { adaptationView(spoiler) } else { startButton }
            case .ending:
                if let spoiler { endingView(spoiler) } else { startButton }
            }
        }
    }

    private var startButton: some View {
        Button { load(selectedTab) } label: {
            Label(selectedTab.isSpoiler ? "Explain it" : "Ask Atlas how it was made", systemImage: "sparkles")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var lockedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Contains spoilers", systemImage: "eye.slash")
                .font(.callout.weight(.semibold))
            Text("This unlocks once you mark \(item.displayTitle) as watched.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Show anyway") { confirmReveal = true }
                .font(.caption.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Content views

    private func craftView(_ notes: [CraftNote]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(notes, id: \.self) { note in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(note.area).font(.subheadline.weight(.semibold))
                        if let person = note.person, !person.isEmpty {
                            Text("· \(person)").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    Text(note.note).font(.callout).foregroundColor(.secondary)
                }
            }
        }
    }

    private func makingView(_ events: [MakingOfEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle().fill(Color.accentColor).frame(width: 9, height: 9).padding(.top, 5)
                        if index < events.count - 1 {
                            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 2)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(event.phase).font(.subheadline.weight(.semibold))
                            if let when = event.when, !when.isEmpty {
                                Text(when).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Text(event.detail).font(.callout).foregroundColor(.secondary)
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func adaptationView(_ content: DeepDiveSpoilerContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let source = content.source {
                Text(source).font(.subheadline.weight(.semibold))
            }
            if content.adaptation.isEmpty {
                Text("Atlas couldn’t find notable changes from the source.")
                    .font(.callout).foregroundColor(.secondary)
            }
            ForEach(content.adaptation, id: \.self) { change in
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.change).font(.callout)
                    if let why = change.why, !why.isEmpty {
                        Text(why).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func endingView(_ content: DeepDiveSpoilerContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Depth", selection: $endingDepth) {
                ForEach(EndingDepth.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(endingText(content))
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func endingText(_ content: DeepDiveSpoilerContent) -> String {
        switch endingDepth {
        case .quick: return content.endingQuick
        case .full: return content.endingFull
        case .themes: return content.endingThemes
        }
    }

    // MARK: - Loading

    private func load(_ tab: DeepDiveTab) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let context = self.context
        Task {
            defer { isLoading = false }
            do {
                if tab.isSpoiler {
                    spoiler = try await DeepDiveService.shared.spoilerContent(for: context)
                } else {
                    safe = try await DeepDiveService.shared.safeContent(for: context)
                }
            } catch DeepDiveError.quotaReached {
                onQuotaReached()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn’t load this right now. Please try again."
            }
        }
    }
}
