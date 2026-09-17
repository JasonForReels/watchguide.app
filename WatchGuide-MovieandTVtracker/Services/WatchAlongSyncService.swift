//
//  WatchAlongSyncService.swift
//  WatchGuide-MovieandTVtracker
//
//  Watch-Along — keeps a clock locked to the exact second of whatever is
//  playing on the TV, on any service, without touching the stream. It listens
//  to a few seconds of dialogue with on-device speech recognition, matches the
//  words against the title's subtitle timeline, and then runs a local clock,
//  re-listening periodically to correct drift, pauses and skipped intros.
//
//  Songs are a second signal (see SoundtrackSyncService): ShazamKit hears the
//  same microphone buffers, and a known song position locks the clock even in
//  scenes with no dialogue.
//
//  Questions to Atlas are answered only from dialogue before the current
//  position, so answers can't spoil what hasn't happened yet.
//
//  iOS-only (AVAudioSession / Speech).
//

#if os(iOS)
import Foundation
import AVFoundation
import Speech

@MainActor
final class WatchAlongSyncService: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loadingSubtitles
        case ready
        case listening
        case synced
        case failed(String)
    }

    enum SyncSource: Equatable {
        case dialogue
        case soundtrack
        case manual
    }

    struct Exchange: Identifiable, Equatable {
        let id = UUID()
        let question: String
        var answer: String?
        let askedAt: TimeInterval
    }

    // MARK: - Published state

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isPaused = false
    @Published private(set) var lastHeard = ""
    @Published private(set) var lastConfidence: Double = 0
    @Published private(set) var syncSource: SyncSource?
    /// The most recent song ShazamKit recognised from the TV.
    @Published private(set) var nowPlaying: SoundtrackMatch?
    /// Songs WatchGuide has learned positions for in this title.
    @Published private(set) var knownSongCount = 0
    @Published private(set) var exchanges: [Exchange] = []
    @Published private(set) var isAnswering = false
    /// Speak answers aloud (AirPods recommended) in addition to showing them.
    @Published var speaksAnswers = true

    let title: String
    let tmdbId: Int
    let season: Int?
    let episode: Int?

    private(set) var timeline: SubtitleTimeline?

    // Clock: position = anchorPosition + (now - anchorDate) while playing.
    private var anchorPosition: TimeInterval = 0
    private var anchorDate = Date()
    private var titleKey: String { SoundtrackAnchorStore.titleKey(tmdbId: tmdbId, season: season, episode: episode) }
    private lazy var soundtrack = SoundtrackRecognizer { [weak self] match in
        self?.handleSoundtrack(match)
    }
    /// When the clock was last set from dialogue — only fresh dialogue locks
    /// are trusted to teach new song anchors.
    private var lastDialogueLock: Date?

    // MARK: - Tuning

    /// How long a single listen lasts before giving up.
    private let listenWindow: TimeInterval = 30
    /// How often to quietly re-listen once synced.
    private let resyncInterval: TimeInterval = 4 * 60

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var listenTimeout: Task<Void, Never>?
    private var resyncTask: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()

    init(title: String, tmdbId: Int, season: Int? = nil, episode: Int? = nil) {
        self.title = title
        self.tmdbId = tmdbId
        self.season = season
        self.episode = episode
    }

    // MARK: - Clock

    func position(at date: Date = Date()) -> TimeInterval {
        guard phase == .synced || phase == .listening, anchorDate <= date else { return anchorPosition }
        if isPaused { return anchorPosition }
        let raw = anchorPosition + date.timeIntervalSince(anchorDate)
        return min(raw, timeline?.duration ?? raw)
    }

    var hasSynced: Bool { anchorPosition > 0 }

    func togglePause() {
        anchorPosition = position()
        anchorDate = Date()
        isPaused.toggle()
    }

    /// Manual correction, e.g. after skipping ahead on the TV.
    func nudge(by seconds: TimeInterval) {
        anchorPosition = max(0, position() + seconds)
        anchorDate = Date()
        syncSource = .manual
        lastDialogueLock = nil
        if phase == .ready { phase = .synced }
    }

    // MARK: - Lifecycle

    func prepare() async {
        guard timeline == nil else { return }
        phase = .loadingSubtitles
        do {
            timeline = try await SubtitleTimelineService.shared.timeline(tmdbId: tmdbId, season: season, episode: episode)
            knownSongCount = Set(await SoundtrackAnchorStore.shared.anchors(for: titleKey).map(\.songKey)).count
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stop() {
        stopListening()
        resyncTask?.cancel()
        resyncTask = nil
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Listening

    func sync() async {
        guard timeline != nil else { return }
        guard await requestPermissions() else {
            phase = .failed("Watch-Along needs microphone and speech recognition access to hear the TV.")
            return
        }
        do {
            try startListening()
        } catch {
            phase = .failed("Couldn't start listening: \(error.localizedDescription)")
        }
    }

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private func startListening() throws {
        stopListening()
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "WatchAlong", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition is unavailable right now."])
        }

        let session = AVAudioSession.sharedInstance()
        // A2DP keeps AirPods on high-quality output while the iPhone's own
        // microphone listens to the room.
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers])
        try session.setActive(true, options: [])

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            // Audio never leaves the device.
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        let soundtrack = self.soundtrack
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, when in
            request.append(buffer)
            soundtrack.append(buffer, when: when)
        }
        audioEngine.prepare()
        try audioEngine.start()

        let wasSynced = hasSynced
        phase = .listening
        lastHeard = ""

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let result else {
                if error != nil {
                    Task { @MainActor in self?.finishListening(matched: false, wasSynced: wasSynced) }
                }
                return
            }
            let text = result.bestTranscription.formattedString
            Task { @MainActor in self?.handleHeard(text, wasSynced: wasSynced) }
        }

        listenTimeout = Task { [weak self, listenWindow] in
            try? await Task.sleep(nanoseconds: UInt64(listenWindow * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finishListening(matched: false, wasSynced: wasSynced)
        }
    }

    private func handleHeard(_ text: String, wasSynced: Bool) {
        guard phase == .listening, let timeline else { return }
        lastHeard = text
        // Match only the most recent words so the anchor reflects "now".
        let recent = text.split(separator: " ").suffix(18).joined(separator: " ")
        guard let match = timeline.match(heard: recent, near: wasSynced ? position() : nil) else { return }
        anchorPosition = match.time
        anchorDate = Date()
        lastConfidence = match.confidence
        syncSource = .dialogue
        lastDialogueLock = Date()
        isPaused = false
        finishListening(matched: true, wasSynced: wasSynced)
    }

    private func finishListening(matched: Bool, wasSynced: Bool) {
        guard phase == .listening else { return }
        stopListening()
        if matched || wasSynced {
            phase = .synced
            scheduleResync()
        } else {
            phase = .ready
        }
    }

    private func stopListening() {
        listenTimeout?.cancel()
        listenTimeout = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    // MARK: - Soundtrack

    private func handleSoundtrack(_ match: SoundtrackMatch) {
        let isNewSong = nowPlaying?.key != match.key
        nowPlaying = match
        guard phase == .listening || phase == .synced else { return }

        Task {
            let anchors = await SoundtrackAnchorStore.shared.anchors(for: titleKey).filter { $0.songKey == match.key }
            // Where the title would be now according to each known use of this song.
            let elapsed = Date().timeIntervalSince(match.matchedAt)
            let candidates = anchors.map { $0.titleTimeAtSongStart + match.songOffset + elapsed }

            if hasSynced, let lock = lastDialogueLock, Date().timeIntervalSince(lock) < 10 * 60 {
                let expected = position()
                if let nearest = candidates.min(by: { abs($0 - expected) < abs($1 - expected) }), abs(nearest - expected) < 90 {
                    // Known song, agreeing with dialogue: tighten the clock.
                    anchorPosition = nearest
                    anchorDate = Date()
                } else if isNewSong || candidates.isEmpty {
                    // Unknown use of this song: teach it from the dialogue lock.
                    let songStart = expected - match.songOffset - elapsed
                    await SoundtrackAnchorStore.shared.learn(titleKey: titleKey, match: match, titleTimeAtSongStart: songStart)
                    knownSongCount = Set(await SoundtrackAnchorStore.shared.anchors(for: titleKey).map(\.songKey)).count
                }
                return
            }

            // Not (freshly) dialogue-synced: lock from the song if its position is unambiguous.
            let target: TimeInterval?
            if hasSynced {
                let expected = position()
                target = candidates.min(by: { abs($0 - expected) < abs($1 - expected) })
            } else {
                target = candidates.count == 1 ? candidates.first : nil
            }
            guard let target else { return }
            anchorPosition = target
            anchorDate = Date()
            lastConfidence = 1
            syncSource = .soundtrack
            isPaused = false
            if phase == .listening {
                finishListening(matched: true, wasSynced: hasSynced)
            }
        }
    }

    private func scheduleResync() {
        resyncTask?.cancel()
        resyncTask = Task { [weak self, resyncInterval] in
            try? await Task.sleep(nanoseconds: UInt64(resyncInterval * 1_000_000_000))
            guard !Task.isCancelled, let self, self.phase == .synced, !self.isAnswering, !self.isPaused else { return }
            try? self.startListening()
        }
    }

    // MARK: - Ask Atlas

    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let timeline, !isAnswering else { return }

        if phase == .listening { finishListening(matched: false, wasSynced: hasSynced) }
        let now = position()
        exchanges.append(Exchange(question: trimmed, answer: nil, askedAt: now))
        let exchangeId = exchanges.last!.id
        isAnswering = true
        defer { isAnswering = false }

        let answer: String
        do {
            let (text, _) = try await AIService.shared.sendMessage(
                prompt(for: trimmed, at: now, timeline: timeline),
                conversationHistory: [],
                likedItems: [],
                webSearchEnabled: false
            )
            answer = AIService.strippingControlTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            answer = "Atlas couldn't answer right now: \(error.localizedDescription)"
        }

        if let index = exchanges.firstIndex(where: { $0.id == exchangeId }) {
            exchanges[index].answer = answer
        }
        if speaksAnswers { speak(answer) }
    }

    private func prompt(for question: String, at time: TimeInterval, timeline: SubtitleTimeline) -> String {
        let where_ = [season.map { "Season \($0)" }, episode.map { "Episode \($0)" }].compactMap { $0 }.joined(separator: ", ")
        return """
        WATCH-ALONG MODE. The user is watching "\(title)"\(where_.isEmpty ? "" : " (\(where_))") right now and is at \(SubtitleTimeline.clock(time)).

        STRICT SPOILER RULES:
        - Treat the dialogue below as everything that has happened so far. Nothing after \(SubtitleTimeline.clock(time)) exists for this user.
        - Never reveal, hint at, or foreshadow later events, twists, deaths, reveals or the ending — even if you know them.
        - Cast names are fine for characters who have already appeared. Do not mention characters who haven't appeared yet.
        - If answering would require future knowledge, say "Keep watching — that's coming up." and stop.

        STYLE: Reply in 1–3 short spoken sentences. No markdown, no lists, no tags. It will be read aloud while they watch.

        DIALOGUE SO FAR (timestamped):
        \(timeline.transcript(upTo: time))

        QUESTION: \(question)
        """
    }

    private func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.volume = 0.9
        synthesizer.speak(utterance)
    }
}
#endif
