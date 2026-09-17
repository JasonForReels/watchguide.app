//
//  TrailerPlaybackSession.swift
//  WatchGuide-MovieandTVtracker
//
//  Shared AVPlayer plumbing for direct-URL trailers (Trailerio / addon mp4 + m3u8).
//  YouTube trailers go through YouTubePlayerKit and don't touch this.
//

import AVFoundation
import CoreGraphics
import Foundation
import Network

/// Owns one direct-URL trailer player plus everything around it that keeps
/// `MEDIA_PLAYBACK_STALL` reports down.
///
/// Three habits in the old call sites produced nearly all of the stall traffic:
///
///  1. Playback started at `.readyToPlay`, which fires once a fraction of a second of
///     media has arrived. On anything short of good Wi-Fi the buffer drained almost
///     immediately. We now start on `isPlaybackLikelyToKeepUp`, with a bounded timeout
///     so a slow-but-healthy item still plays.
///  2. A stall was never handled, so the item re-stalled every time the buffer ran dry
///     and each drain was reported separately. We pause, let the buffer refill, then
///     resume — one report instead of a run of them — and stop retrying once the
///     connection has clearly lost.
///  3. Players were released with an item still attached while CoreMedia had an open
///     reporting session, which is what logs
///     `reportingAgentStatsEndDuration signalled err=-12005 ... StartDuration must be
///     called first`: the stall-end event arrives after the session it belonged to is
///     gone. `invalidate()` closes things in order instead.
///
/// Callers must call `invalidate()`; the session deliberately has no `deinit` cleanup
/// because the ordered teardown has to run while the player is still alive.
@MainActor
final class TrailerPlaybackSession {

    // MARK: - Tunables

    /// Media buffered ahead of the playhead. Bigger on metered/Low Data paths, where
    /// throughput is both lower and burstier.
    private static let forwardBuffer: TimeInterval = 6
    private static let constrainedForwardBuffer: TimeInterval = 12

    /// Longest we wait for `isPlaybackLikelyToKeepUp` before starting anyway. A late
    /// stall is recoverable; a slide that never plays is not.
    private static let readinessTimeout: TimeInterval = 6

    /// Stalls tolerated before we give up and hand back to the caller's fallback.
    private static let maxStallRecoveries = 3

    /// Direct-URL trailers allowed to buffer from cold at the same time. Hero carousel
    /// slides and trailer rows can otherwise fetch several files over one connection.
    private static let maxConcurrentWarmups = 2

    /// Safety valve so a slot can never be held forever by a session that never starts.
    private static let warmupSlotTimeout: TimeInterval = 8
    /// Longest a queued session waits for a slot before starting regardless.
    private static let warmupQueueTimeout: TimeInterval = 4

    private static var activeWarmups = 0

    // MARK: - Public surface

    let player: AVPlayer

    /// Fires once the item can play without stalling on the first frame — or once the
    /// readiness timeout expires. Called at most once.
    var onReadyToPlay: (() -> Void)?

    /// Fires when the item can't be played at all, or when stall recovery gives up.
    var onFailure: (() -> Void)?

    // MARK: - State

    private let item: AVPlayerItem
    private var statusObserver: NSKeyValueObservation?
    private var keepUpObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var stalledObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var readinessTimeoutTask: Task<Void, Never>?
    private var warmupQueueTask: Task<Void, Never>?
    private var warmupSlotTimeoutTask: Task<Void, Never>?
    private var stallRecoveryTask: Task<Void, Never>?

    private var hasSignalledReady = false
    private var wantsToPlay = false
    private var isRecoveringFromStall = false
    private var holdsWarmupSlot = false
    private var isInvalidated = false
    private var stallRecoveries = 0

    // MARK: - Init

    init(url: URL, muted: Bool, volume: Float = 1.0) {
        let constrained = TrailerNetworkConditions.shared.isConstrained

        let asset = AVURLAsset(url: url, options: [
            AVURLAssetAllowsCellularAccessKey: true,
            AVURLAssetAllowsExpensiveNetworkAccessKey: true,
            AVURLAssetAllowsConstrainedNetworkAccessKey: true
        ])

        item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable", "duration"])
        item.preferredForwardBufferDuration = constrained
            ? Self.constrainedForwardBuffer
            : Self.forwardBuffer
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        // Trailers render into a slide or an inline card, never larger than 1080p, and
        // on a metered path a 720p rendition is far likelier to keep up. Both of these
        // only bind for HLS; progressive mp4 ignores them.
        item.preferredMaximumResolution = constrained
            ? CGSize(width: 1280, height: 720)
            : CGSize(width: 1920, height: 1080)
        if constrained {
            item.preferredPeakBitRate = 2_000_000
        }

        player = AVPlayer(playerItem: item)
        player.isMuted = muted
        player.volume = volume
        // Let AVFoundation hold playback until it believes it can play through, rather
        // than starting into an empty buffer.
        player.automaticallyWaitsToMinimizeStalling = true

        startObserving()
    }

    // MARK: - Playback control

    /// Requests playback. The player only actually starts once a warm-up slot is free,
    /// so several trailers can't fight over the same connection from cold.
    func play() {
        guard !isInvalidated else { return }
        wantsToPlay = true
        guard !isRecoveringFromStall else { return }

        if holdsWarmupSlot || acquireWarmupSlot() {
            player.play()
        } else {
            waitForWarmupSlot()
        }
    }

    func pause() {
        guard !isInvalidated else { return }
        wantsToPlay = false
        warmupQueueTask?.cancel()
        warmupQueueTask = nil
        stallRecoveryTask?.cancel()
        stallRecoveryTask = nil
        isRecoveringFromStall = false
        player.pause()
        releaseWarmupSlot()
    }

    /// Ordered teardown: stop, detach the item, then drop the observers. Detaching the
    /// item while the player is still alive is what lets CoreMedia close its reporting
    /// session cleanly instead of emitting an orphaned stall-end event.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        wantsToPlay = false

        readinessTimeoutTask?.cancel()
        readinessTimeoutTask = nil
        warmupQueueTask?.cancel()
        warmupQueueTask = nil
        warmupSlotTimeoutTask?.cancel()
        warmupSlotTimeoutTask = nil
        stallRecoveryTask?.cancel()
        stallRecoveryTask = nil

        player.pause()
        player.replaceCurrentItem(with: nil)

        statusObserver?.invalidate()
        statusObserver = nil
        keepUpObserver?.invalidate()
        keepUpObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
            self.stalledObserver = nil
        }
        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
            self.failedObserver = nil
        }

        releaseWarmupSlot()
    }

    // MARK: - Observation

    private func startObserving() {
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor in
                guard let self, !self.isInvalidated else { return }
                switch status {
                case .failed: self.fail()
                case .readyToPlay: self.evaluateReadiness()
                default: break
                }
            }
        }

        keepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, !self.isInvalidated else { return }
                self.evaluateReadiness()
                self.resumeIfBufferRecovered()
            }
        }

        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                guard let self, !self.isInvalidated else { return }
                // Once frames are actually moving the cold-start is over; hand the
                // warm-up slot to whoever is waiting.
                if status == .playing { self.releaseWarmupSlot() }
            }
        }

        stalledObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleStall() }
        }

        failedObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.fail() }
        }
    }

    // MARK: - Readiness

    private func evaluateReadiness() {
        guard !hasSignalledReady, item.status == .readyToPlay else { return }
        startReadinessTimeoutIfNeeded()
        guard item.isPlaybackLikelyToKeepUp else { return }
        signalReady()
    }

    private func startReadinessTimeoutIfNeeded() {
        guard readinessTimeoutTask == nil else { return }
        readinessTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.readinessTimeout))
            guard !Task.isCancelled, let self, !self.isInvalidated else { return }
            self.signalReady()
        }
    }

    private func signalReady() {
        guard !hasSignalledReady else { return }
        hasSignalledReady = true
        readinessTimeoutTask?.cancel()
        readinessTimeoutTask = nil
        onReadyToPlay?()
    }

    private func fail() {
        guard !isInvalidated else { return }
        wantsToPlay = false
        player.pause()
        releaseWarmupSlot()
        onFailure?()
    }

    // MARK: - Stall recovery

    private func handleStall() {
        guard !isInvalidated, wantsToPlay, !isRecoveringFromStall else { return }

        stallRecoveries += 1
        guard stallRecoveries <= Self.maxStallRecoveries else {
            // The connection can't carry this file. Stop, rather than let CoreMedia
            // report another stall every few seconds for the rest of the slide.
            fail()
            return
        }

        isRecoveringFromStall = true
        // Pausing collapses what would be a run of stall reports into one and lets the
        // buffer refill instead of draining at the playhead.
        player.pause()

        // Backoff, in case the buffer never reports healthy and the KVO resume path
        // below never fires.
        let delay = Double(stallRecoveries) * 1.5
        stallRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.isInvalidated, self.isRecoveringFromStall else { return }
            self.isRecoveringFromStall = false
            if self.wantsToPlay { self.player.play() }
        }
    }

    private func resumeIfBufferRecovered() {
        guard isRecoveringFromStall, wantsToPlay, item.isPlaybackLikelyToKeepUp else { return }
        stallRecoveryTask?.cancel()
        stallRecoveryTask = nil
        isRecoveringFromStall = false
        player.play()
    }

    // MARK: - Warm-up admission control

    private func acquireWarmupSlot() -> Bool {
        guard Self.activeWarmups < Self.maxConcurrentWarmups else { return false }
        Self.activeWarmups += 1
        holdsWarmupSlot = true
        warmupSlotTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.warmupSlotTimeout))
            guard !Task.isCancelled else { return }
            self?.releaseWarmupSlot()
        }
        return true
    }

    private func releaseWarmupSlot() {
        warmupSlotTimeoutTask?.cancel()
        warmupSlotTimeoutTask = nil
        guard holdsWarmupSlot else { return }
        holdsWarmupSlot = false
        Self.activeWarmups = max(0, Self.activeWarmups - 1)
    }

    private func waitForWarmupSlot() {
        guard warmupQueueTask == nil else { return }
        warmupQueueTask = Task { @MainActor [weak self] in
            let deadline = Date().addingTimeInterval(Self.warmupQueueTimeout)
            while Date() < deadline {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let self, !self.isInvalidated, self.wantsToPlay else { return }
                if self.acquireWarmupSlot() {
                    self.warmupQueueTask = nil
                    self.player.play()
                    return
                }
            }
            // Never starve a trailer on our own accounting — worst case we behave the
            // way the old code always did.
            guard !Task.isCancelled, let self, !self.isInvalidated, self.wantsToPlay else { return }
            self.warmupQueueTask = nil
            self.player.play()
        }
    }
}

// MARK: - Network conditions

/// Cheap shared read of whether the current path is metered or in Low Data Mode.
/// Used to pick buffer sizes and bitrate caps at player-construction time.
final class TrailerNetworkConditions {
    static let shared = TrailerNetworkConditions()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var _isConstrained = false

    var isConstrained: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConstrained
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let constrained = path.isConstrained || path.isExpensive
            self.lock.lock()
            self._isConstrained = constrained
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "app.watchguide.trailer-network", qos: .utility))
    }
}
