//
//  WatchAlongView.swift
//  WatchGuide-MovieandTVtracker
//
//  Watch-Along — hold the phone near the TV, WatchGuide locks onto the exact
//  second you're at, and Atlas answers questions without spoiling anything
//  that hasn't happened yet.
//

#if os(iOS)
import SwiftUI

// MARK: - Entry card (Media detail)

struct WatchAlongEntryCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch-Along with Atlas")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Syncs to your TV by listening. Ask anything — zero spoilers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Setup (episode picker + API key)

struct WatchAlongLauncherView: View {
    let item: MediaItem
    let seasons: [Season]

    @Environment(\.dismiss) private var dismiss
    @State private var season = 1
    @State private var episode = 1
    @State private var apiKeyDraft = ""
    @State private var hasApiKey = SubtitleTimelineService.hasApiKey
    @State private var session: WatchAlongSyncService?

    private var isTV: Bool { item.resolvedMediaType == .tv }
    private var playableSeasons: [Season] { seasons.filter { $0.seasonNumber > 0 } }
    private var episodeCount: Int {
        playableSeasons.first { $0.seasonNumber == season }?.episodeCount ?? 30
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    WatchAlongView(session: session)
                } else {
                    setupForm
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        session?.stop()
                        dismiss()
                    }
                }
            }
        }
    }

    private var setupForm: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "waveform.and.mic")
                        .font(.largeTitle)
                        .foregroundStyle(.purple)
                    Text("Watch-Along")
                        .font(.title2.bold())
                    Text("Start playing \(item.displayTitle) on any TV or service. WatchGuide listens for dialogue and soundtrack songs to find your exact spot, then Atlas can answer questions using only what you've already seen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            if isTV {
                Section("What are you watching?") {
                    Picker("Season", selection: $season) {
                        ForEach(playableSeasons.isEmpty ? [1] : playableSeasons.map(\.seasonNumber), id: \.self) {
                            Text("Season \($0)").tag($0)
                        }
                    }
                    Stepper("Episode \(episode)", value: $episode, in: 1...max(episodeCount, 1))
                }
                .onChange(of: season) { _, _ in episode = 1 }
            }

            if !hasApiKey {
                Section {
                    SecureField("OpenSubtitles API key", text: $apiKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save key") {
                        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty else { return }
                        _ = ApiKeyManager.shared.set(key: SubtitleTimelineService.apiKeyName, value: key)
                        hasApiKey = SubtitleTimelineService.hasApiKey
                    }
                } header: {
                    Text("Subtitle source")
                } footer: {
                    Text("Watch-Along uses timed subtitles from opensubtitles.com. Create a free API consumer there and paste the key.")
                }
            }

            Section {
                Button {
                    session = WatchAlongSyncService(
                        title: item.displayTitle,
                        tmdbId: item.id,
                        season: isTV ? season : nil,
                        episode: isTV ? episode : nil
                    )
                } label: {
                    Label("Start Watch-Along", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!hasApiKey)
            }
        }
    }
}

// MARK: - Live session

struct WatchAlongView: View {
    @ObservedObject var session: WatchAlongSyncService
    @State private var question = ""
    @FocusState private var questionFocused: Bool

    private let quickQuestions = ["Who's that?", "What did I miss?", "Recap so far", "Why does that matter?"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        clockCard
                        exchangesList
                    }
                    .padding()
                }
                .onChange(of: session.exchanges) { _, exchanges in
                    guard let last = exchanges.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            askBar
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await session.prepare()
            if session.phase == .ready { await session.sync() }
        }
        .onDisappear { session.stop() }
    }

    // MARK: Clock

    private var clockCard: some View {
        VStack(spacing: 14) {
            statusLabel

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let position = session.position(at: context.date)
                let duration = session.timeline?.duration ?? 0
                VStack(spacing: 10) {
                    Text(SubtitleTimeline.clock(position))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .opacity(session.hasSynced ? 1 : 0.35)
                    if duration > 0 {
                        ProgressView(value: min(position, duration), total: duration)
                            .tint(.purple)
                        HStack {
                            Text(SubtitleTimeline.clock(position))
                            Spacer()
                            Text("-\(SubtitleTimeline.clock(max(duration - position, 0)))")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if session.phase == .listening, !session.lastHeard.isEmpty {
                Text("“\(session.lastHeard.split(separator: " ").suffix(12).joined(separator: " "))”")
                    .font(.footnote.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            nowPlayingChip
                .animation(.easeOut, value: session.nowPlaying)

            if session.knownSongCount > 0 {
                Text("\(session.knownSongCount) soundtrack cue\(session.knownSongCount == 1 ? "" : "s") known — syncs even without dialogue")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            controls
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch session.phase {
        case .idle, .loadingSubtitles:
            Label("Loading dialogue timeline…", systemImage: "text.bubble")
                .font(.subheadline).foregroundStyle(.secondary)
        case .ready:
            Label(session.hasSynced ? "Synced" : "Hold your phone near the TV and tap Sync", systemImage: "ear")
                .font(.subheadline).foregroundStyle(.secondary)
        case .listening:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(session.hasSynced ? "Re-syncing…" : "Listening to the TV…")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.purple)
        case .synced:
            Label(session.isPaused ? "Paused" : syncedDescription,
                  systemImage: session.isPaused ? "pause.circle.fill" : "checkmark.seal.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(session.isPaused ? .orange : .green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
    }

    private var syncedDescription: String {
        switch session.syncSource {
        case .soundtrack: return "Locked on · via soundtrack"
        case .manual: return "Adjusted manually"
        default: return "Locked on · \(Int(session.lastConfidence * 100))% dialogue match"
        }
    }

    @ViewBuilder
    private var nowPlayingChip: some View {
        if let song = session.nowPlaying {
            HStack(spacing: 10) {
                AsyncImage(url: song.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "music.note").foregroundStyle(.purple)
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(song.artist ?? "On screen now").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "shazam.logo.fill").foregroundStyle(.blue)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            controlButton("gobackward.10") { session.nudge(by: -10) }
            controlButton(session.isPaused ? "play.fill" : "pause.fill") { session.togglePause() }
                .disabled(!session.hasSynced)
            Button {
                Task { await session.sync() }
            } label: {
                Label("Sync", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Color.purple, in: Capsule())
                    .foregroundStyle(.white)
            }
            .disabled(session.timeline == nil || session.phase == .listening)
            controlButton("goforward.10") { session.nudge(by: 10) }
            controlButton(session.speaksAnswers ? "airpodspro" : "speaker.slash.fill") {
                session.speaksAnswers.toggle()
            }
        }
    }

    private func controlButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Color.secondary.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Q&A

    private var exchangesList: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.exchanges.isEmpty {
                Text("Ask Atlas about anything you've seen so far. Answers only use dialogue before your current position.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            ForEach(session.exchanges) { exchange in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(exchange.question).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("at \(SubtitleTimeline.clock(exchange.askedAt))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    if let answer = exchange.answer {
                        Text(answer).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Atlas is thinking…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .id(exchange.id)
            }
        }
    }

    private var askBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickQuestions, id: \.self) { quick in
                        Button(quick) { submit(quick) }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.purple.opacity(0.15), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                }
                .padding(.horizontal)
            }
            HStack(spacing: 10) {
                TextField("Ask without spoilers…", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .focused($questionFocused)
                    .submitLabel(.send)
                    .onSubmit { submit(question) }
                Button {
                    submit(question)
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || session.isAnswering)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(.bar)
        .disabled(!session.hasSynced)
        .opacity(session.hasSynced ? 1 : 0.5)
    }

    private func submit(_ text: String) {
        let text = text
        question = ""
        questionFocused = false
        Task { await session.ask(text) }
    }
}
#endif
