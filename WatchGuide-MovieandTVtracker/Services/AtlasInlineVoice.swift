//
//  AtlasInlineVoice.swift
//  WatchGuide-MovieandTVtracker
//
//  Owns the voice session when the call is running *inside* the Atlas dock bar
//  rather than on its own screen.
//
//  The dock bar is a struct that gets rebuilt every time the detent, the
//  keyboard or the transcript moves. A session parked in its `@State` would be
//  torn down and re-opened by that churn — and a re-opened session means a
//  second microphone tap and a second socket. So the session lives out here,
//  and the bar only reads it.
//

import Foundation

#if os(iOS)

@MainActor
@Observable
final class AtlasInlineVoice {
    static let shared = AtlasInlineVoice()

    /// Non-nil while a call is up in the dock bar.
    private(set) var session: AtlasVoiceSession?

    /// Why the last call stopped, when it stopped on its own — the daily
    /// budget ran out, or the connection failed. The bar shows this in place
    /// of the reply for a moment so a call that dies isn't silent.
    private(set) var endedNotice: String?

    private init() {}

    var isActive: Bool { session != nil }

    /// Starts a call using the voice and expression the user last tuned.
    func start() {
        guard session == nil else { return }

        endedNotice = nil
        let session = AtlasVoiceSession()
        self.session = session

        // Stand the app's trailers down for the duration, exactly as the
        // full-screen surface does.
        HeroCarouselMuteManager.shared.isVoiceModeActive = true

        let voice = AtlasVoice(rawValue: UserDefaults.standard.string(forKey: AtlasVoice.storageKey) ?? "")
            ?? .defaultVoice

        Task {
            await session.start(
                voice: voice,
                expression: Self.storedExpression(),
                restrictedMode: ScoutAgeGateManager.shared.isKidsRestricted
            )
        }
    }

    /// Hangs up and hands the bar back to the text composer.
    func end() {
        session?.end(reason: .user)
        session = nil
        HeroCarouselMuteManager.shared.isVoiceModeActive = false
    }

    func toggleMute() {
        session?.toggleMute()
    }

    /// Called when the live session reports it has finished by itself. A call
    /// the user hung up needs no notice; anything else does.
    func handleSessionEnded(_ reason: AtlasVoiceSession.EndReason) {
        switch reason {
        case .user:
            endedNotice = nil
        case .timeLimitReached:
            endedNotice = session?.hitQuotaLimit == true
                ? "Voice time\u{2019}s up for today."
                : "That voice session hit its time limit."
        case .error(let text):
            endedNotice = text
        }
        session = nil
        HeroCarouselMuteManager.shared.isVoiceModeActive = false
    }

    func clearNotice() {
        endedNotice = nil
    }

    // MARK: - Stored tuning

    /// `@AppStorage` never writes its default, so an untouched axis has no
    /// entry at all — read through `object(forKey:)` so "unset" doesn't come
    /// back as 0 and flatten the delivery.
    private static func storedExpression() -> AtlasVoiceExpression {
        let defaults = UserDefaults.standard
        func axis(_ key: String, fallback: Double) -> Double {
            defaults.object(forKey: key) as? Double ?? fallback
        }
        return AtlasVoiceExpression(
            energy: axis(AtlasVoiceExpression.Key.energy, fallback: AtlasVoiceExpression.default.energy),
            warmth: axis(AtlasVoiceExpression.Key.warmth, fallback: AtlasVoiceExpression.default.warmth),
            pace:   axis(AtlasVoiceExpression.Key.pace,   fallback: AtlasVoiceExpression.default.pace),
            drama:  axis(AtlasVoiceExpression.Key.drama,  fallback: AtlasVoiceExpression.default.drama)
        )
    }
}

// MARK: - Phase → wave mode

extension AtlasVoiceSession {
    /// How the waveform should read this session right now.
    var waveMode: AtlasWaveMode {
        switch phase {
        case .idle:       return .idle
        case .connecting: return .connecting
        case .listening:  return isMuted ? .muted : .listening
        case .speaking:   return .speaking
        case .ended:      return .idle
        }
    }
}

#endif
